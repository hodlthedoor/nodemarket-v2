// SPDX-License-Identifier: MIT
/*
    Hypercycle Reentry test contract
*/

pragma solidity ^0.8.19;

import "node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "node_modules/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "src/core/interfaces/IHyperCycleLicense.sol";

contract MockERC721ReceiverLicenseSplitTest is IERC721Receiver {
    IHyperCycleLicense public immutable hypcLicense;
    
    uint256 testCase;
    uint256 variable;

    constructor(
        address hypcLicenseAddress
    ) {
        hypcLicense = IHyperCycleLicense(hypcLicenseAddress);
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
            hypcLicense.mint(8796629893120);
        } else if (testCase == 1){
            hypcLicense.split(8796629893120);
        } else if (testCase == 2){
            hypcLicense.merge(8796629893120);
        }
        return this.onERC721Received.selector;
    }

    function callMint(uint256 number) external {
        hypcLicense.mint(number);
    }

    function callSplit(uint256 number) external {
        hypcLicense.split(number);
    }
    function callMerge(uint256 number) external {
        hypcLicense.merge(number);
    }
}
