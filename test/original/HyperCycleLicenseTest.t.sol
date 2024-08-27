// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/core/HyperCycleLicense.sol";

contract HyperCycleLicenseTest is Test {

    // error MintingTooManyTokens();
    // error MustBeTokenOwner();
    // error HeightMustBeHigherThanTen();

    HyperCycleLicense public license;
    HyperCycleLicense public license2;
    address public owner;
    address public user1;
    address public user2;
    uint256 public constant startNumber = 8796629893120;
    string public mode = "fast"; // Can be changed to "full" for more extensive tests

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        license = new HyperCycleLicense();
        license2 = new HyperCycleLicense();
        
    }

    function testOwnerCanMint() public {
        vm.expectRevert(abi.encodeWithSelector(MintingTooManyTokens.selector));
        license.mint(4100);

        if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("full"))) {
            console.log("minting 4096 tokens...(May take a while)");
            uint256 batch = 128;
            for (uint256 i = 0; i < 4096; i += batch) {
                license.mint(batch);
                console.log(i);
            }
            console.log("minted all tokens");
            vm.expectRevert(abi.encodeWithSelector(MintingTooManyTokens.selector));
            license.mint(1);
        } else {
            console.log("minting 40 tokens...");
            uint256 batch = 4;
            for (uint256 i = 0; i < 40; i += batch) {
                license.mint(batch);
            }
            console.log("minted all tokens");
            vm.expectRevert(abi.encodeWithSelector(MintingTooManyTokens.selector));
            license.mint(4100);
        }

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        license.mint(4);
    }

    function testUserCanSplitLicense() public {
        // Mint some tokens first
        license.mint(40);

        // Transfer some tokens to user1
        for (uint256 i = 0; i < 5; i++) {
            license.transferFrom(owner, user1, startNumber + i);
        }

        if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("full"))) {
            license.transferFrom(owner, user1, startNumber + 4095);
        }

        // Test splitting
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(MustBeTokenOwner.selector));
        license.split(startNumber);

        assertEq(license.ownerOf(startNumber), user1);
        vm.expectRevert("ERC721: invalid token ID");
        license.ownerOf(startNumber * 2);

        vm.prank(user1);
        license.split(startNumber);
        assertEq(license.ownerOf(startNumber * 2), user1);
        assertEq(license.ownerOf(startNumber * 2 + 1), user1);

        // Test splitting down to height 10
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(user1);
            license.split(startNumber * (2 ** (1 + i)));
            assertEq(license.ownerOf(startNumber * (2 ** (2 + i))), user1);
            assertEq(license.getLicenseHeight(startNumber * (2 ** (2 + i))), 17 - i);
            assertTrue(startNumber * (2 ** (2 + i)) < 4503874507374592);
        }

        assertEq(license.ownerOf(4503874505277440), user1);
        assertEq(license.ownerOf(4503874505277441), user1);

        vm.expectRevert("ERC721: invalid token ID");
        license.ownerOf(4503874505277440 * 2);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(HeightMustBeHigherThanTen.selector));
        license.split(startNumber * (2 ** (2 + 7)));

        // Additional tests for full mode can be added here
    }

function testUserCanBurnLicense() public {
    // Mint some tokens first
    license.mint(40);

    // Transfer a token to user1
    license.transferFrom(address(this), user1, startNumber + 4);

    // Attempt to burn as non-owner
    vm.expectRevert(abi.encodeWithSelector(MustBeTokenOwner.selector));
    license.burn(startNumber + 4, "burnDataString");

    // Burn as the owner
    vm.prank(user1);
    license.burn(startNumber + 4, "burnDataString");

    // Check burn data
    assertEq(license.getBurnData(startNumber + 4), "burnDataString");

    // Check burn data for non-burned token
    vm.expectRevert(abi.encodeWithSelector(TokenMustBeBurnt.selector));
    license.getBurnData(startNumber + 5);
}

function testUserCanMergeLicense() public {
    // Mint some tokens first
    license.mint(40);

    // Transfer tokens to users
    for (uint i = 0; i < 6; i++) {
        license.transferFrom(address(this), user1, startNumber + i);
    }
    

    // Attempt to merge non-existent token
    vm.prank(user1);
    vm.expectRevert("ERC721: invalid token ID");
    license.merge(startNumber + 50);

    // Attempt to merge token not owned by user
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(MustBeTokenOwner.selector));
    license.merge(startNumber + 5);

    // Attempt to merge odd token
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(MustBeEvenToken.selector));
    license.merge(startNumber + 1);

    // Attempt to merge root license
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(CantMergeRootLicenses.selector));
    license.merge(startNumber + 2);

    // Split a token and then merge it
    vm.prank(user1);
    license.split(startNumber + 3);

    vm.expectRevert("ERC721: invalid token ID");
    license.ownerOf(startNumber + 3);

    assertEq(license.ownerOf((startNumber + 3) * 2), user1);

    vm.prank(user1);
    license.merge((startNumber + 3) * 2);

    assertEq(license.ownerOf(startNumber + 3), user1);
    
    vm.expectRevert("ERC721: invalid token ID");
    license.ownerOf((startNumber + 3) * 2);
}

}