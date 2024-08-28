// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "node_modules/@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "src/core/interfaces/IHyperCycleShareTokensV2.sol";

contract MockHyperCycleShareTokens is ERC1155, Ownable, IHyperCycleShareTokensV2 {
    uint256 private _currentShareNumber = 0;

     struct ShareData {
        uint256 licenseId;
        uint256 chypcId;
        uint256 status;
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

    mapping(uint256 => ShareData) private shares;

    mapping(uint256 => address) public shareOwners;
    mapping(uint256 => uint256) public shareLicenseIds;
    mapping(uint256 => uint256) public shareChypcIds;
    mapping(uint256 => bool) public shareActivity;
    mapping(uint256 => string) public shareMessages;
    mapping(uint256 => uint256) public shareTotalRevenue;
    mapping(uint256 => uint256) public sharePendingDelay;
    mapping(uint256 => uint256) public shareStartTimes;

    event ShareOwnershipTransferred(uint256 indexed shareNumber, address indexed newOwner);
    event ShareCreated(uint256 indexed shareNumber);
    event ShareCancelled(uint256 indexed shareNumber);
    event CancelledSharedTokens(uint256 shareNumber, uint256 chypcNumber, uint256 licenseNumber);
    event WealthTokensBurned(uint256 shareNumber, uint256 amount);
    event ShareMessageChangedTo(uint256 shareNumber, string message);
    event PendingRevenueDelayChange(uint256 shareNumber, uint256 newDelay);
    event RevenueDeposited(uint256 shareNumber, uint256 amount);
     event ClaimRevenue(uint256 shareNumber, address claimer, uint256 amount);

    constructor() ERC1155("https://example.com/api/token/{id}.json") {}

    function currentShareNumber() external view returns (uint256) {
        return _currentShareNumber;
    }

    function increaseShareLimit(uint256 number) external override {
        _currentShareNumber += number;
    }

    function setShareActivity(uint256 shareNumber, bool active) external {
        shareActivity[shareNumber] = active;
    }

    function createShareTokens(
        uint256 licenseNumber,
        uint256 chypcNumber,
        bool chypcTokenHeld,
        string memory startingMessage,
        uint256 maxRevenueDeposit
    ) external override {
        shareLicenseIds[_currentShareNumber] = licenseNumber;
        shareChypcIds[_currentShareNumber] = chypcNumber;
        shareOwners[_currentShareNumber] = msg.sender;
        shareActivity[_currentShareNumber] = true;
        shareMessages[_currentShareNumber] = startingMessage;
        shareTotalRevenue[_currentShareNumber] = maxRevenueDeposit;
        shareStartTimes[_currentShareNumber] = block.timestamp;
        _currentShareNumber++;
        emit ShareCreated(_currentShareNumber - 1);
    }

    // mock function so that we can set up
    function mint(uint256 tokenId, address to) external {
        _mint(to, tokenId, 1, "");
    }

    function setShareOwner(uint256 shareNumber, address owner) external {
        shareOwners[shareNumber] = owner;
    }

    function transferShareOwnership(uint256 shareNumber, address to) external override {
        require(shareOwners[shareNumber] == msg.sender, "Not owner of the share");
        shareOwners[shareNumber] = to;
        emit ShareOwnershipTransferred(shareNumber, to);
    }

    function cancelShareTokens(uint256 shareNumber) external override {
        require(shareOwners[shareNumber] == msg.sender, "Not owner of the share");
        shareActivity[shareNumber] = false;
        emit ShareCancelled(shareNumber);
    }

    function depositRevenue(uint256 shareNumber, uint256 amt) external override {
        shareTotalRevenue[shareNumber] += amt;
        emit RevenueDeposited(shareNumber, amt);
    }

    function claimRevenue(uint256 shareNumber) external override {
        require(shareOwners[shareNumber] == msg.sender, "Not owner of the share");
        shareTotalRevenue[shareNumber] = 0;
        emit ClaimRevenue(shareNumber, msg.sender, 69);
    }

    function withdrawEarnings(uint256 shareNumber) external override {
        require(shareOwners[shareNumber] == msg.sender, "Not owner of the share");
        shareTotalRevenue[shareNumber] = 0;
    }

    function claimAndWithdraw(uint256 shareNumber) external override {

    }

    function setShareMessage(uint256 shareNumber, string memory message) external override {
        require(shareOwners[shareNumber] == msg.sender, "Not owner of the share");
        shareMessages[shareNumber] = message;
    }

    function burnRevenueTokens(uint256 shareNumber, uint256 amount) external override {
        require(shareOwners[shareNumber] == msg.sender, "Not owner of the share");
    }

    function burnWealthTokens(uint256 shareNumber, uint256 amount) external override {
        require(shareOwners[shareNumber] == msg.sender, "Not owner of the share");
        emit WealthTokensBurned(shareNumber, amount);
    }

    function changePendingRevenueDelay(uint256 shareNumber, uint256 newDelay) external override {

        sharePendingDelay[shareNumber] = newDelay;
        //emit PendingRevenueDelayChange(shareNumber, newDelay);
    }

    function getShareLicenseId(uint256 shareNumber) external view returns (uint256) {
        return shareLicenseIds[shareNumber];
    }

    function getShareCHyPCId(uint256 shareNumber) external view returns (uint256) {
        return shareChypcIds[shareNumber];
    }

    function getShareOwner(uint256 shareNumber) external view returns (address) {
        return shareOwners[shareNumber];
    }

    function getShareRevenueTokenId(uint256 shareNumber) external view returns (uint256) {
        return shareNumber * 2; 
    }

    function getShareWealthTokenId(uint256 shareNumber) external view returns (uint256) {
        return shareNumber * 2 + 1;
    }

    function getShareTotalRevenue(uint256 shareNumber) external view returns (uint256) {
        return shareTotalRevenue[shareNumber];
    }

    function getShareStartTime(uint256 shareNumber) external view returns (uint256) {
        return shareStartTimes[shareNumber];
    }
    
   function getShareMessage(uint256 shareNumber) external view returns (string memory) {
        return shareMessages[shareNumber];
    }

    function isShareActive(uint256 shareNumber) external view returns (bool) {
        return shareActivity[shareNumber];
    }

    function shareCreated(uint256 shareNumber) external view returns (bool) {
        return shareActivity[shareNumber];
    }

    function getRevenueTokenTotalSupply(uint256 shareNumber) external view returns (uint256) {
        return 1000; // Mock value
    }

    function getWealthTokenTotalSupply(uint256 shareNumber) external view returns (uint256) {
        return 500; // Mock value
    }

    function getPendingDeposit(uint256 shareNumber, uint256 index) external view returns (PendingDeposit memory) {
        return PendingDeposit(block.timestamp + 1 days, 100); // Mock value
    }

    function getPendingDepositsLength(uint256 shareNumber) external view returns (uint256) {
        return 1; // Mock value
    }

   

    // Function to set share data
    function setShareData(
        uint256 shareNumber,
        uint256 _licenseId,
        uint256 _chypcId,
        uint256 _status,
        address _owner,
        uint256 _rTokenNumber,
        uint256 _wTokenNumber,
        uint256 _rTokenSupply,
        uint256 _wTokenSupply,
        uint256 _startTimestamp,
        uint256 _revenueDeposited,
        uint256 _revenueDepositDelay,
        string memory _message,
        bool _chypcTokenHeld
    ) public {
        shares[shareNumber] = ShareData({
            licenseId: _licenseId,
            chypcId: _chypcId,
            status: _status,
            owner: _owner,
            rTokenNumber: _rTokenNumber,
            wTokenNumber: _wTokenNumber,
            rTokenSupply: _rTokenSupply,
            wTokenSupply: _wTokenSupply,
            startTimestamp: _startTimestamp,
            revenueDeposited: _revenueDeposited,
            revenueDepositDelay: _revenueDepositDelay,
            message: _message,
            chypcTokenHeld: _chypcTokenHeld
        });
    }

    // Function to get share data
    function shareData(uint256 shareNumber)
        public
        view
        returns (
            uint256 licenseId,
            uint256 chypcId,
            uint256 status,
            address owner,
            uint256 rTokenNumber,
            uint256 wTokenNumber,
            uint256 rTokenSupply,
            uint256 wTokenSupply,
            uint256 startTimestamp,
            uint256 revenueDeposited,
            uint256 revenueDepositDelay,
            string memory message,
            bool chypcTokenHeld
        )
    {
        ShareData memory s = shares[shareNumber];
        return (
            s.licenseId,
            s.chypcId,
            s.status,
            s.owner,
            s.rTokenNumber,
            s.wTokenNumber,
            s.rTokenSupply,
            s.wTokenSupply,
            s.startTimestamp,
            s.revenueDeposited,
            s.revenueDepositDelay,
            s.message,
            s.chypcTokenHeld
        );
    }
}
