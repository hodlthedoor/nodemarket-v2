// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/core/HyperCycleShareTokensV2.sol";
import "src/core/HyperCycleLicense.sol";
import "src/core/HyperCycleSwapV2.sol";
import "src/core/HyperCycleToken.sol";

contract HyperCycleShareTokenV2Test is Test {


    HyperCycleToken public hypcToken;
    HyperCycleLicense public hypcLicense;
    HyperCycleSwapV2 public hypcSwapV2;
    HyperCycleShareTokensV2 public hypcShare;

    address owner = address(this);
    address user1 = address(0x1);
    address user2 = address(0x2);

    uint256 startNumber = 8796629893120;
    uint256 delayAmount = 7 * 24 * 60 * 60;

    function setUp() public {
        // Deploy HyperCycle token
        hypcToken = new HyperCycleToken("HyperCycle", "HyPC");

        // Deploy License and SwapV2 contracts
        hypcLicense = new HyperCycleLicense();
        hypcSwapV2 = new HyperCycleSwapV2(address(hypcToken), 67108864, 67112959);

        // Deploy ShareTokensV2
        hypcShare = new HyperCycleShareTokensV2(
            8590983168,
            8592031743,
            8590983168,
            address(hypcLicense),
            address(0x1), // CHYPC address (fake address)
            address(hypcSwapV2),
            address(hypcToken)
        );

        // Add root tokens to the contract to be swapped for c_HyPC tokens
        hypcSwapV2.addRootTokens(2); // Add root tokens to level 19

        // Simulate user minting tokens and approvals
        hypcToken.mint(user1, 2**31 * 1000000); // Mint HyPC tokens for user1
        vm.startPrank(user1); // Begin using user1 address for further calls
        hypcToken.approve(address(hypcSwapV2), 1000000000 * 1000000); // Approve swapV2 contract to use tokens



        // Perform swap for the first token to mint it
        hypcSwapV2.swapV2(19); // Swap for level 19 c_HyPC token to mint it

        vm.stopPrank(); // End using user1 address
    }

 function testUserCanStartShare() public {
    // Mint licenses to user1
    hypcLicense.mint(5);

    // Mint tokens to the contract
    hypcSwapV2.addRootTokens(2); // Adds root tokens, which are initially minted to the contract

    // Transfer the minted c_HyPC token to user1
    uint256 tokenId = hypcSwapV2.getAvailableToken(19, 0); // Get the tokenId that was minted


    hypcLicense.safeTransferFrom(address(this), user1, 8796629893120);


    // Now that user1 owns the token, start their transactions
    vm.startPrank(user1);
    // Swap for a v2 token to ensure user1 has a token for sharing
    hypcSwapV2.swapV2(19); // Swap for a level 19 c_HyPC token to mint it

    // Approve the share contract for licenses and c_HyPC tokens
    hypcLicense.approve(address(hypcShare), 8796629893120);
    hypcSwapV2.setApprovalForAll(address(hypcShare), true);

    // Assign the token a number (necessary before creating shares)
    hypcSwapV2.assignNumber(tokenId, 8796629893120);

    // Create share tokens for user1
    hypcShare.createShareTokens(8796629893120, tokenId, true, "start message", delayAmount);

    // Check that the assignment number is correctly set
    assertEq(hypcSwapV2.getAssignmentNumber(tokenId), 8796629893120);

    // Check that the share message is set correctly
    assertEq(hypcShare.getShareMessage(8590983168), "start message");

    // Try creating share beyond the limit and expect a revert
    vm.expectRevert(abi.encodeWithSelector(CantCreateSharesBeyondShareLimit.selector));
    hypcShare.createShareTokens(8796629893120, tokenId, true, "", delayAmount);

    vm.stopPrank();
}

}
