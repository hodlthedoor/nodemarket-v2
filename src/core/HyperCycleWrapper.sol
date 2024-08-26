// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IHyperCycleShareTokensV2} from './interfaces/IHyperCycleShareTokensV2.sol';
import "node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IHyperCycleLicense.sol";
//import "./HyperCycleShareTokensV2.sol";
import "./interfaces/IHYPCSwapV2.sol";

/**
 * @title ShareOwnershipWrapper
 * @dev This contract wraps HyperCycleShareTokens, allowing them to be managed as ERC721 tokens.
 * The wrapper contract enables the registration, wrapping, and unwrapping of shares, as well as
 * various management functions for share owners.
 */
contract ShareOwnershipWrapper is Ownable, ERC721, IERC721Receiver {

    //@dev Enum for the status of a share.
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


    IHyperCycleShareTokensV2 private immutable shareManagement;
    IHYPCSwapV2 private immutable swapV2Contract;
    IHyperCycleLicense private immutable licenseContract;
    IERC20 private immutable hypcToken;
    

    event ShareOwnershipWrapped(uint256 indexed shareNumber, address newOwner, address triggeredBy);
    event ShareOwnershipUnwrapped(uint256 indexed shareNumber, address newOwner);
    event ShareOwnershipRegistered(uint256 indexed shareNumber, address owner);
    event ShareOwnershipRecovered(uint256 indexed shareNumber, address newOwner);

    error RegistrationExpired();
    error ShareOwnershipNotRegistered();
    error ShareAlreadyWrapped();
    error Unauthorised();
    error ZeroAddress();
    error ShareAlreadyRegistered();
    error MustBeShareOwner();

    mapping(uint256 => address) public shareOwners;

    string public baseURI;

    /**
     * @dev Initializes the contract by setting the share management contract address and
     * the ERC721 token name and symbol.
     * @param _shareManagementAddress The address of the HyperCycleShareTokensV2 contract.
     */
    constructor(address _shareManagementAddress, address _licenceAddress, address swapV2Address, address erc20) ERC721("Wrapped HyperShare", "WHS") {
        shareManagement = IHyperCycleShareTokensV2(_shareManagementAddress);
        licenseContract = IHyperCycleLicense(_licenceAddress);
        swapV2Contract = IHYPCSwapV2(swapV2Address);
        hypcToken = IERC20(erc20);

        // approve the management contract to spend the tokens
    }

    /**
     * @dev Allows a user to register ownership of a share.
     * @param _shareNumber The share number to register ownership for.
     */
    function registerShareOwnership(uint256 _shareNumber) external {
        if (shareManagement.getShareOwner(_shareNumber) != msg.sender) {
            revert Unauthorised();
        }

        shareOwners[_shareNumber] = msg.sender;
        emit ShareOwnershipRegistered(_shareNumber, msg.sender);
    }

    /**
     * @dev Allows a registered share owner to mint a wrapped token.
     * @param shareNumber The share number to wrap.
     * @param to The address to mint the wrapped token to.
     */
    function mintWrappedToken(uint256 shareNumber, address to) external {
        if (shareOwners[shareNumber] != msg.sender) {
            revert Unauthorised();
        }

        if (shareManagement.getShareOwner(shareNumber) != address(this)) {
            revert Unauthorised();
        }

        if (_exists(shareNumber)) {
            revert ShareAlreadyWrapped();
        }

        shareOwners[shareNumber] = address(0x1); // it's cheaper to do this
        _mint(to, shareNumber);

        emit ShareOwnershipWrapped(shareNumber, to, msg.sender);
    }

    /**
     * @dev Allows the contract owner to recover an orphaned share.
     * @param _shareNumber The share number to recover.
     * @param _owner The address to transfer ownership to.
     */
    function recoverOrphanedShare(uint256 _shareNumber, address _owner) external onlyOwner {
        if (_owner == address(0)) {
            revert ZeroAddress();
        }

        if (_exists(_shareNumber)) {
            revert ShareAlreadyWrapped();
        }

        if (shareOwners[_shareNumber] == address(0x1) || shareOwners[_shareNumber] == address(0x0)) {
            shareManagement.transferShareOwnership(_shareNumber, _owner);
            emit ShareOwnershipRecovered(_shareNumber, _owner);
        } else {
            revert ShareAlreadyRegistered();
        }
    }

    /**
     * @dev Allows the owner of a wrapped share to cancel the share.
     * @param _shareNumber The share number to cancel.
     */
 function cancelShareTokens(uint256 _shareNumber) external {
    if (ownerOf(_shareNumber) != msg.sender) {
        revert MustBeShareOwner();
    }

    shareManagement.cancelShareTokens(_shareNumber);

    (uint256 licenseId,uint256 chypcId,,,,,,,,,,,bool chypcTokenHeld) = shareManagement.shareData(_shareNumber);

    // Transfer tokens back to msg.sender
    if (chypcTokenHeld) {
        swapV2Contract.safeTransferFrom(address(this), msg.sender, chypcId);
    }

    licenseContract.safeTransferFrom(address(this), msg.sender, licenseId);
}


    /**
     * @dev Allows the owner of a wrapped share to set a message for the share.
     * @param _shareNumber The share number to set the message for.
     * @param _message The message to set.
     */
    function setShareMessage(uint256 _shareNumber, string memory _message) external {
        if (ownerOf(_shareNumber) != msg.sender) {
            revert MustBeShareOwner();
        }
        shareManagement.setShareMessage(_shareNumber, _message);
    }

  

    /**
     * @dev Allows the owner of a wrapped share to change the pending revenue delay.
     * @param _shareNumber The share number to change the pending revenue delay for.
     * @param _delay The new delay in seconds.
     */
    function changePendingRevenueDelay(uint256 _shareNumber, uint256 _delay) external {
        if (ownerOf(_shareNumber) != msg.sender) {
            revert MustBeShareOwner();
        }
        shareManagement.changePendingRevenueDelay(_shareNumber, _delay);
    }

    /**
     * @dev Allows the owner of a wrapped share to unwrap the share, burning the token and
     * transferring ownership of the share back to the unwrapping address.
     * @param _shareNumber The share number to unwrap.
     */
    function unwrapShareOwnership(uint256 _shareNumber) external {
        if (ownerOf(_shareNumber) != msg.sender) {
            revert MustBeShareOwner();
        }

        shareManagement.transferShareOwnership(_shareNumber, msg.sender);
        _burn(_shareNumber);
        emit ShareOwnershipUnwrapped(_shareNumber, msg.sender);
    }

    /* Revenue sharing functions */
    // @notice Deposits revenue into a share. It remains locked until it is later released.
    // @param  shareNumber: The share this revenue is deposited for.
    // @param  amt: The amount of HyPC being deposited.
    function depositRevenue(uint256 _shareNumber, uint256 _amt) external {
        if (ownerOf(_shareNumber) != msg.sender) {
            revert MustBeShareOwner();
        }

        hypcToken.transferFrom(msg.sender, address(this), _amt);
        shareManagement.depositRevenue(_shareNumber, _amt);

    }

    function claimRevenue(uint256 shareNumber) external {
        if (ownerOf(shareNumber) != msg.sender) {
            revert MustBeShareOwner();
        }

        uint256 rTokenId = shareManagement.getShareRevenueTokenId(shareNumber);

        shareManagement.claimRevenue(shareNumber);

        uint256 balance = shareManagement.balanceOf(address(this), rTokenId);
        shareManagement.safeTransferFrom(address(this), msg.sender, rTokenId, balance, "");
    }

    function claimAndWithdraw(uint256 shareNumber) external {
        revert("Not implemented");
    }


    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /// @notice Sets the base URI for the token metadata
    /// @dev This function can only be called by the owner of the contract
    /// @param _uri The new base URI to be set
    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

       function onERC721Received( 
        address /*operator*/, 
        address /*from*/, 
        uint256 /*tokenId*/, 
        bytes calldata /*data*/ 
    ) public override returns (bytes4) {

    }
}
