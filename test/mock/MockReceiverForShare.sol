// SPDX-License-Identifier: MIT
/*
    Hypercycle Reentry test contract
*/

pragma solidity ^0.8.19;

import "node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "node_modules/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "src/core/interfaces/IHyperCycleShareTokens.sol";

contract MockERC721ReceiverShareTest is IERC721Receiver {
    IHyperCycleShareTokens public immutable shareTokens;
    
    uint256 testCase;
    uint256 variable;

    constructor(
        address shareAddress
    ) {
        shareTokens = IHyperCycleShareTokens(shareAddress);
    }
        
    function setTest(uint256 newTest, uint256 newVariable) public {
        testCase = newTest;
        variable = newVariable;
    }

    function doCall() external {
        shareTokens.cancelShareTokens(8590983170);
    }

    function onERC721Received( 
        address /*operator*/, 
        address /*from*/, 
        uint256 /*tokenId*/, 
        bytes calldata /*data*/ 
    ) public override returns (bytes4) {
        if (testCase == 0) {
            shareTokens.createShareTokens(1,1,true, "", 1000000000000000);
        } else if (testCase == 1){
            shareTokens.cancelShareTokens(8590983169);
        } 
        return this.onERC721Received.selector;
    }
}
