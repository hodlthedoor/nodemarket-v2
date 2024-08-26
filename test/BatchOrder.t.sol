// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "src/OtcExchange_V3.sol";
import "src/structs/Order.sol";
import "src/structs/Signature.sol";
import "./mock-erc20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract BatchOrderTest is Test {

    OtcExchange_V3 exchange;

    uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
    bytes32 domainHash = 0xa0ac488034f9144b60cdae469cdaf727ea7277fd99c8f0b2df34981e87afb26f;


    function setUp() public {
        exchange = new OtcExchange_V3(msg.sender, domainHash);
        exchange.updateSigner(vm.addr(ownerPrivateKey), true);
    }

    
    function testCreateSignature() public {

        
        // Initial Setup
        address seller = 0xdb36f1d03aa9887C56d95353905F7379aE82C41c;
        address buyer = 0x5Af87C2F08F9B13775887e01876CA211a7b9b63c;

        uint128 orderAmount = 1;
        uint128 priceInWei = 1;


        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 1,
            validUntil: uint64(1722971820),
            paymentToken: address(0x74348eE5375463FC1Cb2f5fC1C9A2cCCe23f79Ee),
            saleToken: address(0x9DF3350b265F8b5248Fd3F7c1d701DB1E7Ad7f35),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = _getEIP712OrderHash(order, buyer, seller, domainHash);


        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);

        vm.startPrank(buyer);
        exchange.fillOrder(order, v, r, s, v,r,s,buyer);

        


    }

       function _getEIP712OrderHash(
        Order memory order,
        address buyer,
        address seller,
        bytes32 domainSeparator
    ) private pure returns (bytes32) {
        bytes32 typeHash = keccak256(
            "Order(uint128 amount,uint128 price,address seller,uint64 validUntil,uint32 id,address paymentToken,address saleToken,uint64 nonce,address buyer,uint256 pairNonce)"
        );

        // Create the hash using EIP-712 standard
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    domainSeparator,
                    keccak256(
                        abi.encode(
                            typeHash,
                            order.amount,
                            order.price,
                            seller,
                            order.validUntil,
                            order.id,
                            order.paymentToken,
                            order.saleToken,
                            order.nonce,
                            buyer,
                            order.pairNonce
                        )
                    )
                )
            );
    }

}
