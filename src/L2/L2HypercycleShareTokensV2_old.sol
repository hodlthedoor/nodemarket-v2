// SPDX-License-Identifier: MIT
/*
    Version 1 of the HyperCycle Share contract.
*/

pragma solidity ^0.8.19;

import "node_modules/@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "node_modules/@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "node_modules/@openzeppelin/contracts/utils/Strings.sol";
import "src/core/interfaces/IHyperCycleLicense.sol";
import "src/core/interfaces/ICHYPC.sol";
import "src/core/interfaces/IHYPCSwapV2.sol";
import "src/core/interfaces/IHyperCycleShareTokens.sol";
import "src/core/interfaces/IHYPC.sol";

/*
@title HyperCycle Share ERC1155, revenue sharing contract.
@author Barry Rowe, Rodolfo Cova 
@notice This contract is a mechanism to share revenue for participants in the HyperCycle system.
      
        HyperCycle is a network of AI computation nodes offering different AI services in a 
        decentralized manner. In this system, there are license holders, token holders, hardware
        operators, and AI developers. Using the HyperCycleSwapV2 contract, an amount of HyPC (erc20)
        can be swapped for a cHyPC (containerized HyPC) token, which can then point towards a
        license (HyperCycleLicense) NFT id. At this point, the owner of this license can assign
        their license to some hardware running the HyperCycle Node Manager, and can from then
        on accept AI service requests on the network. 

        While all of this can be done by a single user, there are benefits to dividing up the
        responsibilities of each party, so a user can participate as a license holder, token holder,
        hardware operator, or AI developer. This is where the HyperCycle Share contracts come into
        play. The HyperCycleShareTokens contract is an ERC1155 contract that accepts a deposit of
        a license NFT and a cHyPC NFT, and creates two new tokens: a wealth token, and a revenue
        token. While the license and cHyPC are locked in the new Share, revenue can be deposited
        into the HyperCycleShareTokens by the hardware manager (that is, using the node manager
        software) with the depositRevenue() method. After some HyPC has been deposited this way,
        the revenue becomes locked for a minimum waiting period (for example, 7 days), after which,
        this revenue can be unlocked, and at that point, owners of the revenue token can claim 
        their portion of the share's income by using the claimRevenue() method. This will update 
        their withdrawable amount of HyPC that they can then withdraw from the contract. The revenue
        deposit delay is useful for ensuring more fairness of the revenue sharing. For instance,
        without a delay, the hardware operator could buy a lot of revenue tokens from an exchange,
        then make a huge revenue deposit into the contract, and then immediately claim their revenue
        and then sell the revenue tokens back to the exchange. With a delay period, the hardware
        operator would have to hold onto those tokens for the 7 day period, and with the pending
        deposit coming through, the revenue token price would increase (similar to dividend yielding
        stocks when leading up to the day a dividend will be paid out). The other holders of the
        revenue tokens can sell their tokens at the higher price, and then buy back the revenue
        tokens after the revenue is unlocked and claimable by the contract, when the price is lower.
        This counteracts the advantage the hardware operator,or users who would front run a deposit
        transaction, would have.

        Since revenue tokens can be transferred at any time, while revenue is collected only on the 
        claimRevenue call, whenever a transfer of revenue tokens happens, a claimRevenue call is 
        made for both the sender and receiver of the tokens first via the safeTransferFrom ERC1155 
        overrides defined at the end of the contract. This prevents the following situation:
        suppose Alice and Bob have 50% of the revenue tokens each, and the contract earns 1000 HyPC.
        Alice then sends Bob half of her revenue tokens. Bob now owns 75% of the revenue tokens and
        can claim 75% of the 1000 HyPC, even though the 1000 HyPC was deposited when Alice owned
        50% of those tokens. 

        The claimRevenue hook on the transfer of revenue tokens fixes this issue by forcing the
        revenue to be claimed whenever revenue tokens are transferred between parties. In effect,
        the issue is that revenue tokens are only fungible if they have collected revenue at the
        same time (if Alice claims revenue on her tokens while Bob has not, then these tokens
        are not equivalent to each other). If both holders of the tokens have collected at the
        same time however, then these tokens are indeed equivalent.

        Besides the revenue tokens, there are also the wealth tokens. In this contract they do not
        have any special usage, but are intended for use in future contracts (for example: a share
        manager contract) that can use them for governance functions. Right now, the current contract
        is intended to be used either via a multi-sig wallet with a general delgation mechanism 
        (eg: gnosis), or more likely via an external manager contract that interfaces with this 
        contract. In that case, the license holder and cHyPC holders would use the manager contract
        to create the share and divide the wealth and revenue tokens amongst themselves, or other
        parties, using governing mechanisms inside the manager contract.

        If the original creator of the share (or someone that had the share transferred to them) 
        decides to cancel the share itself by calling the cancelShareTokens() method, then the 
        original license and cHyPC NFTs are sent back to the creator (or new owner), and future
        deposits to share are halted. At this time, owners of the revenue tokens can claim their 
        last amounts of HyPC, and withdraw their HyPC from the contract.

        As well, while the typical use case is that the original creator of the share deposits 
        both the license and cHyPC tokens into the share contract, there are some use cases where 
        it might make sense to only deposit the license instead. This could be the case where 
        this creator is a smart contract that used the CrowdFundHYPCPoolV2 contract get an 
        assignment pointed to the license Id. In this case, the smart contract would have an 
        external guarantee that the license has backing but does not own the cHyPC itself. 
        In this case, a share can be created instead with a cHyPC id of 0, which will bypass the 
        cHyPC retrieval and assignment in that case. 
 
        Finally, there's also a message function to allow the owner of a share to set a message
        associated to this share. This is mainly intended for future manager contracts to use.
*/

/* Errors */
// Modifier Errors
error MustBeShareOwner();
error ShareMustBeActive();
error ShareDoesntExist();
error PendingDepositMustExist();

/* Constructor Errors */
error EndShareNumberWouldOverflow();
error InvalidShareNumberRange();
error InvalidLicenseAddress();
error InvalidSwapV2Address();
error InvalidHYPCAddress();
error InvalidCHYPCV1Address();
error InvalidStartingLimit();

/* increaseShareLimit Errors */
error ShareLimitIncreasedTooMuch();

/* createShareTokens Errors */
error CantCreateSharesBeyondShareLimit();
error LicenseMustHaveCHYPCBacking();
error InvalidCHYPCTokenLevel();

/* unlockRevenue Errors */
error UnlockingRevenueTooEarly();

/* claimRevenue Errors */
error NoRevenueTokensForThisShare();
error NoRevenueToClaim();

/* transferShareOwnership Errors */
error CantTransferToZeroAddress();

/* cancelShareTokens Errors */
error ShareMinDurationHasNotPassed();

/* withdrawEarnings Errors */
error NothingToWithdraw();

/* burn Errors */
error MustClaimRevenueToBurnTokens();
error ShareMustBeEnded();
error MustBurnSomeRevenueTokens();
error NotEnoughRevenueTokensOwned();
error MustBurnSomeWealthTokens();
error NotEnoughWealthTokensOwned();


contract L2HypercycleShareTokensV2 is 
    ERC1155, ERC721Holder, Ownable, ReentrancyGuard, IHyperCycleShareTokens {

    //@dev Contract interfaces
    IHYPC private immutable hypcToken;
    ICHYPC private immutable chypcV1Contract;
    IHYPCSwapV2 private immutable swapV2Contract;
    IHyperCycleLicense private immutable licenseContract;

    // Contract constants
    uint256 public constant REVENUE_TOKEN_MAX_SUPPLY = 2**19;
    uint256 public constant WEALTH_TOKEN_MAX_SUPPLY = 2**19;
    uint256 public constant MIN_SHARE_DURATION = 24 hours;
    uint256 public constant RATIO_DECIMALS = 10**12;

    enum Status {
        NOT_CREATED,
        STARTED,
        ENDED
    }

    struct ShareData {
        uint256 licenseId;
        uint256 chypcId;
        Status status;
        address owner;
        uint256 rTokenNumber;
        uint256 wTokenNumber;
        uint256 rTokenSupply;
        uint256 wTokenSupply;
        uint256 startTimestamp;
        uint256 revenueDeposited;
        uint256 revenueDepositDelay;
        string message;
        bool chypcTokenHeld;
    }

    // Mappings
    mapping(uint256=>ShareData) public shareData;
    mapping(uint256=>mapping(address=>uint256)) public lastShareClaimRevenue;
    mapping(uint256=>mapping(address=>uint256)) public withdrawableAmounts;
    mapping(uint256=>uint256) public licenseToShareNumber;
    mapping(uint256=> PendingDeposit[]) public pendingDeposits;

    // Variables
    uint256 public startShareNumber;
    uint256 public endShareNumber;
    uint256 public shareLimitNumber;
    uint256 public currentShareNumber;
    uint256 public totalDeposited;


    event IncreaseShareLimit(uint256 amount);
    event CreateShare(
        uint256 licenseNumber, 
        uint256 chypcNumber,
        address owner, 
        uint256 shareNumber,
        bool chypcTokenHeld
    );
    event ShareOwnershipTransferred(uint256 shareNumber, address to);
    event PendingRevenueDelayChange(uint256 shareNumber, uint256 newDelay);
    event RevenueDeposited(uint256 shareNumber, uint256 amount, uint256 timestamp);
    event PendingRevenueDeposit(uint256 shareNumber, uint256 index, uint256 amount);
    event CancelledSharedTokens(uint256 shareNumber, uint256 chypcNumber, uint256 licenseNumber);
    event ClaimRevenue(uint256 shareNumber, address claimer, uint256 amount);
    event EarningsWithdrawal(uint256 shareNumber, address claimer, uint256 amount);
    event ShareMessageChangedTo(uint256 shareNumber, string message);

    modifier shareOwner(uint256 shareNumber) {
        if (shareData[shareNumber].owner != msg.sender) revert MustBeShareOwner();
        _;
    }
 
    modifier shareActive(uint256 shareNumber) {
        if (shareData[shareNumber].status != Status.STARTED) revert ShareMustBeActive();
        _;
    }

    modifier shareExists(uint256 shareNumber) {
        if (shareData[shareNumber].status == Status.NOT_CREATED) revert ShareDoesntExist();
        _;
    }

    modifier shareEnded(uint256 shareNumber) {
        if (shareData[shareNumber].status != Status.ENDED) revert ShareMustBeEnded();
        _;
    }

    modifier pendingDepositExists(uint256 shareNumber, uint256 index) {
        if (index >= pendingDeposits[shareNumber].length) revert PendingDepositMustExist();
        _;
    }

    constructor(
        uint256 startNumber,
        uint256 endNumber,
        uint256 startLimit,
        address licenseAddress,
        address chypcV1Address,
        address swapV2Address,
        address hypcAddress
    ) ERC1155("") {

        
        if (endNumber >= 2**255 - 2) revert EndShareNumberWouldOverflow();
        if (endNumber/2 >= startNumber) revert InvalidShareNumberRange();
        if (endNumber < startNumber) revert InvalidShareNumberRange();
        if (licenseAddress == address(0)) revert InvalidLicenseAddress();
        if (swapV2Address == address(0)) revert InvalidSwapV2Address();
        if (hypcAddress == address(0)) revert InvalidHYPCAddress();
        if (chypcV1Address == address(0)) revert InvalidCHYPCV1Address();
        if (startLimit < startNumber || startLimit > endNumber) revert InvalidStartingLimit();

        startShareNumber = startNumber;
        endShareNumber = endNumber;

        shareLimitNumber = endShareNumber;
        currentShareNumber = endShareNumber; // Start from the highest number

        chypcV1Contract = ICHYPC(chypcV1Address);
        swapV2Contract = IHYPCSwapV2(swapV2Address);
        licenseContract = IHyperCycleLicense(licenseAddress);
        hypcToken = IHYPC(hypcAddress);
       
    }

    function createShareTokens(
        uint256 licenseNumber,
        uint256 chypcNumber,
        bool chypcTokenHeld,
        string memory startingMessage,
        uint256 revenueDepositDelay
    ) external nonReentrant {

        if (currentShareNumber < shareLimitNumber) revert CantCreateSharesBeyondShareLimit();


        if (!chypcTokenHeld) {
            _verifyCHYPCAssignment(chypcNumber, licenseNumber);
        }

        address to = msg.sender;

        uint256 shareNumber = currentShareNumber;
        uint256 rTokenType = shareNumber * 2;
        uint256 wTokenType = shareNumber * 2 + 1;


        currentShareNumber -= 1; // Decrement for Optimism


        shareData[shareNumber] = ShareData(
            licenseNumber,
            chypcNumber,
            Status.STARTED,
            to,
            rTokenType,
            wTokenType,
            REVENUE_TOKEN_MAX_SUPPLY,
            WEALTH_TOKEN_MAX_SUPPLY,
            block.timestamp,
            0,
            revenueDepositDelay,
            startingMessage,
            chypcTokenHeld
        );
        licenseToShareNumber[licenseNumber] = shareNumber;

        licenseContract.safeTransferFrom(to, address(this), licenseNumber);

        if (chypcTokenHeld) {
            swapV2Contract.safeTransferFrom(to, address(this), chypcNumber);
            swapV2Contract.assignNumber(chypcNumber, licenseNumber);
        }

        _mint(to, rTokenType, REVENUE_TOKEN_MAX_SUPPLY, "");
        _mint(to, wTokenType, WEALTH_TOKEN_MAX_SUPPLY, "");

        emit CreateShare({
            licenseNumber: licenseNumber,
            chypcNumber: chypcNumber,
            owner: to,
            shareNumber: shareNumber,
            chypcTokenHeld: chypcTokenHeld
        });
    }

    // @notice An internal function to check the backing of the license from the given
    //         chypcNumber. This checks assignments via the SwapV2 contract first, and
    //         then the SwapV1 contract.
    // @param  chypcNumber: The cHyPC NFT Id pointing to the licenseNumber.
    // @param  licenseNumber: The license NFT Id to deposit into this share.
    function _verifyCHYPCAssignment(uint256 chypcNumber, uint256 licenseNumber) internal {
    // Convert the uint256 to a string manually
    string memory stringAssigned = _uintToString(licenseNumber);
    
    // Check the assignments without relying on Strings library
    if (
        swapV2Contract.getAssignmentNumber(chypcNumber) != licenseNumber &&
        !_compareStrings(swapV2Contract.getAssignmentString(chypcNumber), stringAssigned) &&
        !_compareStrings(chypcV1Contract.getAssignment(chypcNumber), stringAssigned)
    ) {
        revert LicenseMustHaveCHYPCBacking();
    }
}

// Helper function to convert uint256 to string
function _uintToString(uint256 value) internal pure returns (string memory) {
    if (value == 0) {
        return "0";
    }
    uint256 temp = value;
    uint256 digits;
    while (temp != 0) {
        digits++;
        temp /= 10;
    }
    bytes memory buffer = new bytes(digits);
    while (value != 0) {
        digits -= 1;
        buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
        value /= 10;
    }
    return string(buffer);
}

// Helper function to compare two strings
function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
}

    function transferShareOwnership(uint256 shareNumber, address to) external shareOwner(shareNumber) shareActive(shareNumber) {
        if (to == address(0)) revert CantTransferToZeroAddress();
        shareData[shareNumber].owner = to;
        emit ShareOwnershipTransferred({shareNumber: shareNumber, to: to});
    }

    function changePendingRevenueDelay(uint256 shareNumber, uint256 newDelay) external shareOwner(shareNumber) shareActive(shareNumber) {
        shareData[shareNumber].revenueDepositDelay = newDelay;
        emit PendingRevenueDelayChange(shareNumber, newDelay);
    }

    function cancelShareTokens(uint256 shareNumber) external shareOwner(shareNumber) shareActive(shareNumber) nonReentrant {
        if (shareData[shareNumber].startTimestamp + MIN_SHARE_DURATION > block.timestamp) revert ShareMinDurationHasNotPassed();

        uint256 licenseNumber = shareData[shareNumber].licenseId;
        uint256 chypcNumber = shareData[shareNumber].chypcId;
        bool chypcTokenHeld = shareData[shareNumber].chypcTokenHeld;
        shareData[shareNumber].status = Status.ENDED;
        delete licenseToShareNumber[licenseNumber];

        if (chypcTokenHeld) {
            swapV2Contract.assignNumber(chypcNumber, 0);
            swapV2Contract.safeTransferFrom(address(this), msg.sender, chypcNumber);
        }
        licenseContract.safeTransferFrom(address(this), msg.sender, licenseNumber);      
        emit CancelledSharedTokens({
            shareNumber: shareNumber, 
            chypcNumber: chypcNumber, 
            licenseNumber: licenseNumber
        });
    }
   
    function setShareMessage(uint256 shareNumber, string memory message) external shareOwner(shareNumber) shareActive(shareNumber) {
        shareData[shareNumber].message = message;
        emit ShareMessageChangedTo({shareNumber: shareNumber, message: message});
    }

    /* Revenue sharing functions */
    function depositRevenue(uint256 shareNumber, uint256 amt) external shareActive(shareNumber) {
        pendingDeposits[shareNumber].push(
            PendingDeposit({
                availableAtTimestamp: block.timestamp+shareData[shareNumber].revenueDepositDelay,
                amount: amt
            })
        );
        hypcToken.transferFrom(msg.sender, address(this), amt);
        emit PendingRevenueDeposit({
            shareNumber: shareNumber, 
            index: pendingDeposits[shareNumber].length-1, 
            amount: amt
        });
    }

    function unlockRevenue(uint256 shareNumber, uint256 index) external pendingDepositExists(shareNumber, index) {
        PendingDeposit memory pd = pendingDeposits[shareNumber][index];
        if (pd.availableAtTimestamp > block.timestamp) {
            revert UnlockingRevenueTooEarly();
        }
        totalDeposited += pd.amount;
        shareData[shareNumber].revenueDeposited += pd.amount;

        //Remove old index now;
        if (pendingDeposits[shareNumber].length > 1 && index < pendingDeposits[shareNumber].length -1 ) {
            pendingDeposits[shareNumber][index] = pendingDeposits[shareNumber][pendingDeposits[shareNumber].length -1];
        }
        pendingDeposits[shareNumber].pop();

        emit RevenueDeposited({
            shareNumber: shareNumber, 
            amount: pd.amount,
            timestamp: block.timestamp
        });
    }

    function _claimRevenue(uint256 shareNumber, address claimerAddress) internal returns (uint256) {
        uint256 rTokenNumber = shareData[shareNumber].rTokenNumber;
        uint256 revenueDeposited = shareData[shareNumber].revenueDeposited;
        uint256 ownershipRatio = RATIO_DECIMALS*balanceOf(claimerAddress, rTokenNumber)/REVENUE_TOKEN_MAX_SUPPLY;

        uint256 amountToGiveAddress = (revenueDeposited-lastShareClaimRevenue[shareNumber][claimerAddress])*ownershipRatio/RATIO_DECIMALS;
        lastShareClaimRevenue[shareNumber][claimerAddress] = revenueDeposited;
        withdrawableAmounts[shareNumber][claimerAddress] += amountToGiveAddress;
        emit ClaimRevenue(shareNumber, claimerAddress, amountToGiveAddress);
        return amountToGiveAddress;
    }

    function claimRevenue(uint256 shareNumber) external shareExists(shareNumber) {
        if (balanceOf(msg.sender, shareData[shareNumber].rTokenNumber) == 0) revert NoRevenueTokensForThisShare();
        if (_claimRevenue(shareNumber, msg.sender) == 0) revert NoRevenueToClaim();
    }

    function _withdrawEarnings(uint256 shareNumber) internal shareExists(shareNumber) {
        uint256 amt = withdrawableAmounts[shareNumber][msg.sender];
        if (amt == 0) revert NothingToWithdraw();
        withdrawableAmounts[shareNumber][msg.sender] = 0;
        hypcToken.transfer(msg.sender, amt);
        emit EarningsWithdrawal({
            shareNumber: shareNumber,
            claimer: msg.sender,
            amount: amt
        });
    }

    function withdrawEarnings(uint256 shareNumber) external {
        _withdrawEarnings(shareNumber);
    }

    function claimAndWithdraw(uint256 shareNumber) external {
        if (balanceOf(msg.sender, shareData[shareNumber].rTokenNumber) == 0) revert NoRevenueTokensForThisShare();
        if (_claimRevenue(shareNumber, msg.sender) == 0) revert NoRevenueToClaim();
        _withdrawEarnings(shareNumber);
    }

    function burnRevenueTokens(uint256 shareNumber, uint256 amount) external shareEnded(shareNumber) {
        if (_claimRevenue(shareNumber, msg.sender) > 0) revert MustClaimRevenueToBurnTokens();
        if (amount == 0) revert MustBurnSomeRevenueTokens();
        if (balanceOf(msg.sender, shareData[shareNumber].rTokenNumber) < amount) revert NotEnoughRevenueTokensOwned();
        shareData[shareNumber].rTokenSupply -= amount;
        _burn(msg.sender, shareData[shareNumber].rTokenNumber, amount);
    }

    function burnWealthTokens(uint256 shareNumber, uint256 amount) external shareOwner(shareNumber) shareEnded(shareNumber) {
        if (amount == 0) revert MustBurnSomeWealthTokens();
        if (balanceOf(msg.sender, shareData[shareNumber].wTokenNumber) < amount) revert NotEnoughWealthTokensOwned();
        shareData[shareNumber].wTokenSupply -= amount;
    }

    /* Getters */
    function getShareLicenseId(uint256 shareNumber) external view returns (uint256) {
        return shareData[shareNumber].licenseId;
    }

    function getShareCHyPCId(uint256 shareNumber) external view returns (uint256) {
        return shareData[shareNumber].chypcId;
    }

    function getShareOwner(uint256 shareNumber) external view returns (address) {
        return shareData[shareNumber].owner;
    }

    function getShareRevenueTokenId(uint256 shareNumber) external view returns (uint256) {
        return shareData[shareNumber].rTokenNumber;
    }

    function getShareWealthTokenId(uint256 shareNumber) external view returns (uint256) {
        return shareData[shareNumber].wTokenNumber;
    }

    function getShareTotalRevenue(uint256 shareNumber) external view returns (uint256) {
        return shareData[shareNumber].revenueDeposited;
    }

    function getShareStartTime(uint256 shareNumber) external view returns (uint256) {
        return shareData[shareNumber].startTimestamp;
    }

    function getShareMessage(uint256 shareNumber) external view returns (string memory) {
        return shareData[shareNumber].message;
    }

    function isShareActive(uint256 shareNumber) external view returns (bool) {
        return shareData[shareNumber].status == Status.STARTED;
    }

    function shareCreated(uint256 shareNumber) external view returns (bool) {
        return shareData[shareNumber].status != Status.NOT_CREATED;
    }

    function getRevenueTokenTotalSupply(uint256 shareNumber) external shareExists(shareNumber) view returns (uint256) {
        return shareData[shareNumber].rTokenSupply;
    }

    function getWealthTokenTotalSupply(uint256 shareNumber) external shareExists(shareNumber) view returns (uint256) {
        return shareData[shareNumber].wTokenSupply;
    }

    function getPendingDeposit(uint256 shareNumber, uint256 index) external pendingDepositExists(shareNumber, index) view returns (PendingDeposit memory) {
        return pendingDeposits[shareNumber][index];
    }

    function getPendingDepositsLength(uint256 shareNumber) external shareExists(shareNumber) view returns (uint256) {
        return pendingDeposits[shareNumber].length;
    }

    function increaseShareLimit(uint256 number) external onlyOwner {

        if (shareLimitNumber - number < startShareNumber) {
            revert ShareLimitIncreasedTooMuch();
        }
        shareLimitNumber -= number;


        emit IncreaseShareLimit(number);
    }


    /* ERC1155 Overrides */

    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) public override(ERC1155, IERC1155) {
        if (id % 2 == 0) {   
            uint256 shareNumber = id/2;
            if (shareData[shareNumber].status == Status.NOT_CREATED) revert ShareDoesntExist();
            _claimRevenue(shareNumber, from);
            _claimRevenue(shareNumber, to);
        }
        super.safeTransferFrom(from, to, id, value, data);  
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public override(ERC1155, IERC1155) {
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            if (id % 2 == 0) {   
                uint256 shareNumber = id/2;
                if (shareData[shareNumber].status == Status.NOT_CREATED) revert ShareDoesntExist();
                _claimRevenue(shareNumber, from);
                _claimRevenue(shareNumber, to);
            }
        }
        super.safeBatchTransferFrom(from, to, ids, values, data);
    }
}
