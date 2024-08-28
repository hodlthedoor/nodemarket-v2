// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'node_modules/@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import 'node_modules/@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol';
import 'node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol';
import 'node_modules/@openzeppelin/contracts/access/Ownable.sol';
import 'src/core/interfaces/IHYPCSwapV2.sol';
import 'src/core/interfaces/IHYPC.sol';
import 'src/core/interfaces/ICrowdFundPoolV3Mock.sol';

/**
    @title  Mock HyperCycle SwapV2 for PoolV3 testing.
    @author Barry Rowe
*/

/* Modifier Errors */
///@dev Error for when requiring the owner of the tokenNumber to call the function.
error SenderMustOwnToken();
///@dev Error for when trying to interact with levels lower than MIN_LEVEL.
error TokenLevelTooLow();
///@dev Error for when trying to interact with levels higher than MAX_LEVEL.
error TokenLevelTooHigh();

///@dev Error for when a virtual/real token is not held by the contract at the given level.
error InvalidTokenLevelIndex();
///@dev Error for when trying to get burn data from a non-burned token.
error TokenNotBurned();
///@dev Error for when trying to use a token that's not yet minted.
error TokenNotMinted();

/* Constructor Errors */
///@dev Error when deploying a contract with a zero address token.
error InvalidToken();
///@dev Error for when deploying a contract with a startingNumber of 0.
error InvalidStartingNumber();
///@dev Error for when deploying a contract with the endingNumber less than the startingNumber.
error InvalidEndingNumber();
///@dev Error for when deploying a contract with the endingNumber greater or equal to 2*startingNumber.
error InvalidNumberRange();


/* addRootToken Errors*/
///@dev Error for when trying to add a root token to the contract past the endRootNumber.
error TooManyRootTokens();

/* splitHeldToken Errors */
///@dev Error for when skipLevels during the split call is 0.
error SkipLevelsMustBePositive();
///@dev Error for when trying to split a token beyond the MIN_LEVEL limit.
error TokenLevelTooLowToSplit();
///@dev Error for when trying to split a token and the next level has too many tokens already.
error CreatingTooManyTokens();
///@dev Error for when skipLevels is too large.
error SkipLevelsTooLarge();


contract MockHyperCycleSwapV2 is ERC721Enumerable, ERC721Holder, Ownable, ReentrancyGuard, IHYPCSwapV2 {
    IHYPC private immutable _hypcToken;
    ICrowdFundPoolV3Mock private _poolContract;

    uint256 public constant LEVEL_LIMIT = 16;

    uint256 public constant MAX_LEVEL = 19;

    uint256 public constant MIN_LEVEL = 10;

    uint256 public constant SIX_DECIMALS = 10 ** 6;

    struct TokenData {
        string assignedString;
        uint256 assignedNumber;
        uint256 level;
        bool minted;
    }

    struct RootData {
        /// @dev The first token number to be added
        uint256 startRootNumber;
        /// @dev The next token to be added to the contract from the addRootTokens call.
        uint256 currentRootNumber;
        /// @dev The last root token to be created, inclusive.
        uint256 endRootNumber;
    }

    mapping(uint256 => TokenData) public nftTokens;

    mapping(uint256 => uint256) public assignedNumbers;

    mapping(string => uint256) public assignedStrings;
   
    mapping(uint256 => uint256) public _lastBlockAssigned;

    mapping(uint256 => uint256[]) public levels;

    uint256[] public nfts;

    RootData private _rootData;

    uint256 public totalLocked;

    event AddRootToken(uint256 rootNumber);

    event SplitHeldTokens(uint256 tokenNumber, uint256 level, uint256 skipLevels);

    event Swap(uint256 tokenNumber, uint256 level, uint256 hypcAmount);

    event Redeem(uint256 level, uint256 tokenNumber, uint256 hypcAmount);

    event AssignNumber(uint256 tokenNumber, uint256 targetNumber, uint256 backingAmount, uint256 totalAmount);

    event AssignString(uint256 tokenNumber, string targetString, uint256 backingAmount);

    event Burn(uint256 tokenNumber, string burnString);

    modifier isOwnerOf(uint256 tokenNumber) {
        if (ownerOf(tokenNumber) != _msgSender()) revert SenderMustOwnToken();
        _;
    }

    modifier validHeldToken(uint256 level, uint256 index) {
        if (level < MIN_LEVEL) revert TokenLevelTooLow();
        if (level > MAX_LEVEL) revert TokenLevelTooHigh();
        if (levels[level].length <= index ) revert InvalidTokenLevelIndex();
        _;
    }

    modifier isMintedAndBurned(uint256 tokenNumber) {
        if (_exists(tokenNumber) || !nftTokens[tokenNumber].minted) revert TokenNotBurned();
        _;
    }

    modifier isMinted(uint256 tokenNumber) {
        if (!nftTokens[tokenNumber].minted) revert TokenNotMinted();
        _;
    }

    uint256 public testRunning = 0;

    function setTest(uint256 test, address pool) external {
        testRunning = test;
        _poolContract = ICrowdFundPoolV3Mock(pool);
    }

    constructor(address hypcTokenAddress, uint256 startingNumber, uint256 endingNumber) ERC721('c_HyPC', 'c_HyPC') {
        if (hypcTokenAddress == address(0)) revert InvalidToken();
        if (startingNumber == 0) revert InvalidStartingNumber();
        if (endingNumber < startingNumber) revert InvalidEndingNumber();
        if (endingNumber >= 2*startingNumber) revert InvalidNumberRange();

        _hypcToken = IHYPC(hypcTokenAddress);
        _rootData.startRootNumber = startingNumber; //67108864;
        _rootData.endRootNumber = endingNumber; //67108864+4095 = 67112959;
        _rootData.currentRootNumber = startingNumber;
    }

    function mint(uint256 tokenId, address to) external {
        _mint(to, tokenId);
    }

    function addRootTokens(uint256 tokens) external onlyOwner {
        uint256 currentRootNumber = _rootData.currentRootNumber;
        if (tokens > 1+_rootData.endRootNumber - _rootData.startRootNumber) revert TooManyRootTokens();

        //@dev _rootData.endRootNumber is inclusive, so we need to add 1 to it for this check.
        if (currentRootNumber + tokens > _rootData.endRootNumber + 1) revert TooManyRootTokens();

        uint256 endLimit = currentRootNumber+tokens;
        for (uint256 i=currentRootNumber; i < endLimit; i++) {
            levels[MAX_LEVEL].push(i);
            nftTokens[i] = TokenData('', 0, MAX_LEVEL, false);

            emit AddRootToken({
                rootNumber: i
            });
        }

        _rootData.currentRootNumber += tokens;
        _updateNFTArray(MAX_LEVEL);
    }

    function splitHeldToken(uint256 level, uint256 skipLevels) external validHeldToken(level, 0) {
        if (skipLevels > level) revert SkipLevelsTooLarge();

        if (skipLevels == 0) revert SkipLevelsMustBePositive();
        uint256 levelMinusSkipLevels = level-skipLevels;
        if (levelMinusSkipLevels < MIN_LEVEL) revert TokenLevelTooLowToSplit();

        uint256 tokensToCreate = 2 ** skipLevels;
        if (levels[levelMinusSkipLevels].length + tokensToCreate > LEVEL_LIMIT) revert CreatingTooManyTokens();

        uint256[] storage _targetLevel = levels[level];
        uint256 tokenNumber = _targetLevel[0];
        _targetLevel[0] = _targetLevel[_targetLevel.length - 1];
        _targetLevel.pop();
        _updateNFTArray(level);

        if (nftTokens[tokenNumber].minted) {
            _burn(tokenNumber);
        }

        uint256 endLimit = tokenNumber*tokensToCreate+tokensToCreate;
        for (uint256 i=tokenNumber*tokensToCreate; i < endLimit; i++) {
            levels[levelMinusSkipLevels].push(i);
            nftTokens[i] = TokenData('', 0, levelMinusSkipLevels, false);
        }

        emit SplitHeldTokens({
            tokenNumber: tokenNumber, 
            level: level, 
            skipLevels: skipLevels
        });
    }

    function _updateNFTArray(uint256 level) internal {
        if (level == MAX_LEVEL) {
            if (levels[MAX_LEVEL].length > 0) {
                if (nfts.length == 0) {
                    nfts.push(levels[MAX_LEVEL][0]);
                } else {
                    nfts[0] = levels[MAX_LEVEL][0];
                }
            } else {
                if (nfts.length > 0) {
                    nfts.pop();
                }
            }
        }
    }

    function swapV2(uint256 level) external validHeldToken(level, 0) nonReentrant {
        _swapV2(level);
    }

    function _swapV2(uint256 level) internal {
        uint256 amount = 2 ** level;
        totalLocked += amount;
        runTest();

        uint256[] storage _targetLevel = levels[level];
        uint256 tokenNumber = _targetLevel[0];
        _targetLevel[0] = _targetLevel[_targetLevel.length - 1];
        _targetLevel.pop();
        _updateNFTArray(level);

        TokenData storage _targetToken = nftTokens[tokenNumber];

        if (_targetToken.minted) {
            _safeTransfer(address(this), _msgSender(), tokenNumber, "");
        } else {
            _targetToken.minted = true;
            _safeMint(_msgSender(), tokenNumber);
        }
        _hypcToken.transferFrom(_msgSender(), address(this), amount * SIX_DECIMALS);

        emit Swap({
            tokenNumber: tokenNumber, 
            level: level, 
            hypcAmount: amount
        });
    }

    function runTest() internal {
        if (testRunning == 1) {
            _poolContract.swapTokens(0,0,0);
        } else if (testRunning == 2) {
            _poolContract.redeemTokens(0,1);
        } else if (testRunning == 3) {
            _poolContract.redeemSingleToken(0,0);
        }
    }

    function redeem(uint256 tokenNumber) external nonReentrant isOwnerOf(tokenNumber) {
        _unassign(tokenNumber);
        runTest();
        uint256 level = nftTokens[tokenNumber].level;
        levels[level].push(tokenNumber);
        _updateNFTArray(level);
        
        uint256 amount = 2 ** level;
        totalLocked -= amount;
        safeTransferFrom(_msgSender(), address(this), tokenNumber);
        _hypcToken.transfer(_msgSender(), amount * SIX_DECIMALS);

        emit Redeem({
            level: level, 
            tokenNumber: tokenNumber, 
            hypcAmount: amount
        });
    }

    function assignNumber(uint256 tokenNumber, uint256 targetNumber) external isOwnerOf(tokenNumber) {
        _unassign(tokenNumber);

        if (targetNumber > 0) {

            TokenData storage _targetToken = nftTokens[tokenNumber];
            _targetToken.assignedNumber = targetNumber;
            assignedNumbers[targetNumber] += 2 ** (_targetToken.level);
            
            emit AssignNumber({
                tokenNumber: tokenNumber,
                targetNumber: targetNumber,
                backingAmount: 2 ** (_targetToken.level),
                totalAmount: assignedNumbers[targetNumber]
            });
        }
    }

    function assignString(uint256 tokenNumber, string memory data) external isOwnerOf(tokenNumber) {
        _assignString(tokenNumber, data);
    }

    function _assignString(uint256 tokenNumber, string memory data) internal {
        _unassign(tokenNumber);

        TokenData storage _targetToken = nftTokens[tokenNumber];
        _targetToken.assignedString = data;
        assignedStrings[data] += 2 ** (_targetToken.level);

        emit AssignString({
            tokenNumber: tokenNumber,
            targetString: data,
            backingAmount: 2 ** (_targetToken.level)
        });
    }

    function burn(uint256 tokenNumber, string memory data) external isOwnerOf(tokenNumber) {
        _assignString(tokenNumber, data);
        _burn(tokenNumber);
        emit Burn(tokenNumber, data);
    }

    function _unassign(uint256 tokenNumber) internal {
        TokenData storage _targetToken = nftTokens[tokenNumber];
        _lastBlockAssigned[tokenNumber] = block.timestamp;

        if (_targetToken.assignedNumber > 0) {
            assignedNumbers[_targetToken.assignedNumber] -= 2 ** (_targetToken.level);
            delete _targetToken.assignedNumber;
        }
        if (bytes(_targetToken.assignedString).length > 0) {
            assignedStrings[_targetToken.assignedString] -= 2 ** (_targetToken.level);
            delete _targetToken.assignedString;
        }
    }

    function assign(uint256 tokenNumber, string memory data) external isOwnerOf(tokenNumber) {
        //assign a string
        _assignString(tokenNumber, data);
    }

    function swap() external nonReentrant validHeldToken(MAX_LEVEL, 0) {
        _swapV2(MAX_LEVEL);
    }

    function getAssignment(uint256 tokenNumber) external view returns (string memory) {
        return _getAssignmentString(tokenNumber);
    }

    function getLevelLength(uint256 level) external view returns (uint256) {
        return levels[level].length;
    }

    function getAvailableToken(uint256 level, uint256 index) external view validHeldToken(level, index) returns (uint256) {
        return levels[level][index];
    }

    function getAssignmentString(uint256 tokenNumber) external view returns (string memory) {
        return _getAssignmentString(tokenNumber);
    }

    function _getAssignmentString(uint256 tokenNumber) internal view returns (string memory) {
        return nftTokens[tokenNumber].assignedString;
    }

    function getAssignmentNumber(uint256 tokenNumber) external view returns (uint256) {
        return nftTokens[tokenNumber].assignedNumber;
    }

    function getAssignmentTargetNumber(uint256 targetNumber) external view returns (uint256) {
        return assignedNumbers[targetNumber];
    }

    function getAssignmentTargetString(string memory targetString) external view returns (uint256) {
        return assignedStrings[targetString];
    }

    function getLastAssigned(uint256 tokenId) external view returns (uint256) {
        return _lastBlockAssigned[tokenId];
    }

    function getBurnData(uint256 tokenNumber) external view isMintedAndBurned(tokenNumber) returns (string memory) {
        return nftTokens[tokenNumber].assignedString;
    }

    function getTokenLevel(uint256 tokenNumber) external view isMinted(tokenNumber) returns (uint256) {
        return nftTokens[tokenNumber].level;
    }
}
