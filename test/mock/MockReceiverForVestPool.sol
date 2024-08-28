// SPDX-License-Identifier: MIT
/*
    Hypercycle Reentry test contract
*/

pragma solidity ^0.8.19;

import "node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "node_modules/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "src/core/interfaces/IHYPCSwap.sol";
import "src/core/interfaces/ICHYPC.sol";
import "src/core/interfaces/IHYPC.sol";


contract MockERC721VestReceiverTest is IERC721Receiver {
    IHYPC public immutable HYPCToken;
    ICHYPC public immutable HYPCNFT;
    IHYPCSwap public immutable SwapContract;

    uint256 testCase;
    uint256 variable;

    constructor(
        address hypcTokenAddress,
        address hypcNFTAddress,
        address swapContractAddress
    ) {
        HYPCToken = IHYPC(hypcTokenAddress);
        HYPCNFT = ICHYPC(hypcNFTAddress);
        SwapContract = IHYPCSwap(swapContractAddress);
    }
        
    function setTest(uint256 newTest, uint256 newVariable) public {
        testCase = newTest;
        variable = newVariable;
    }

    function onERC721Received( 
        address /*operator*/, 
        address /*from*/, 
        uint256 /*tokenId*/, 
        bytes calldata /*data*/ 
    ) public override returns (bytes4) {
        if (testCase == 0) {
            SwapContract.swap();
        } else {
            SwapContract.redeem(variable);
        }
        //return "";
    }

    function callApprove(address addr, uint256 amount) public
    {
        HYPCToken.approve(addr, amount);
    }
 
    function callSwap() public
    {
        SwapContract.swap();
    } 
}
