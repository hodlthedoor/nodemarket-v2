// SPDX-License-Identifier: MIT
/*
    Hypercycle Reentry test contract
*/

pragma solidity ^0.8.19;

import "node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "node_modules/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "src/core/interfaces/IHYPCSwapV2.sol";
import "src/core/interfaces/IHYPC.sol";

contract MockERC721ReceiverSwapV2Test is IERC721Receiver {
    IHYPCSwapV2 public immutable hypcSwapV2;
    IHYPC public immutable hypc;

    uint256 testCase;
    uint256 variable;

    constructor(
        address hypcSwapV2Address,
        address hypcAddress
    ) {
        hypcSwapV2 = IHYPCSwapV2(hypcSwapV2Address);
        hypc = IHYPC(hypcAddress);
    }
        
    function setTest(uint256 newTest, uint256 newVariable) public {
        testCase = newTest;
        variable = newVariable;
    }

    function test1() public {
        hypc.approve(address(hypcSwapV2), 524288*(10**6));
        hypcSwapV2.swap();
    }

    function test2() public {
        hypc.approve(address(hypcSwapV2), 300*524288*(10**6));
        
        for(uint256 i; i < 500; i++) {
            if (gasleft() < 200000) {
                break;
            } else {
                hypcSwapV2.swap();
            }
        }
    }

    function onERC721Received( 
        address /*operator*/, 
        address /*from*/, 
        uint256 tokenId, 
        bytes calldata /*data*/ 
    ) public override returns (bytes4) {
        hypc.approve(address(hypcSwapV2), 524288*(10**6));

        if (testCase == 0) {
           hypcSwapV2.swapV2(19);
        } else if (testCase == 1){
            hypcSwapV2.swap();
        } else if (testCase == 2) {
            bool check = true;
            uint256 lastBalance;
            while (check) {
                if (hypc.balanceOf(address(hypcSwapV2)) < 524288*(10**6) || (hypc.balanceOf(address(this)) == lastBalance && hypc.balanceOf(address(this)) != 0)) {
                    check = false;
                } else {
                    lastBalance = hypc.balanceOf(address(this));
                    hypcSwapV2.redeem(tokenId);
                }
            }
        }
        return this.onERC721Received.selector;
    }
}
