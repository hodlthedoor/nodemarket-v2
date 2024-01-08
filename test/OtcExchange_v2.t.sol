// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "src/OtcExchange_V2.sol";
import "src/structs/Order.sol";
import "src/structs/Signature.sol";
import "./mock-erc20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract OtcExchange_V2Test is Test {
    address internal contractOwner = address(0x69696969);
    uint256 internal ownerPrivateKey = 0xA11CE;
    uint256 internal owner2PrivateKey = 0xA11CE2;
    uint256 internal spenderPrivateKey = 0xB0B;
    uint256 internal signerPrivateKey = 0xB0B2;

    OtcExchange_V2 exchange;
    MockERC20 token;

    address constant zeroAddress = address(0);
    address commissionAddress = address(0x420690);

    function setUp() public {
        token = new MockERC20("TEST", "TEST", 0);
        exchange = new OtcExchange_V2(commissionAddress);

        exchange.updateSaleToken(address(token), true);
        exchange.setCommission(0);
        exchange.updateSigner(vm.addr(signerPrivateKey), true);

        //exchange.updateSigner(vm.addr(ownerPrivateKey), true);
    }

    function testFillOrderWithIncorrectSignature_fail() public {
        address seller = vm.addr(signerPrivateKey);
        // Mock Order
        Order memory order = Order({
            amount: 1000,
            price: 2000,
            seller: seller,
            validUntil: uint64(block.timestamp + 1 days),
            id: 0,
            paymentToken: zeroAddress,
            saleToken: address(token),
            nonce: 0,
            buyer: address(0),
            pairNonce: 0
        });

        // Mock incorrect signature components
        uint8 v = 27;
        bytes32 r = bytes32(keccak256("incorrectR"));
        bytes32 s = bytes32(keccak256("incorrectS"));

        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Prepare the custom error data
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        hoax(address(0x13371377));
        // Try to fill the same order again and expect a revert
        vm.expectRevert(customErrorData);
        exchange.fillOrder{value: 2000}(order, v, r, s, v2, r2, s2, address(0));
    }

    function testFillOrder_() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0), // For ETH
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHashNewFunction = getEIP712OrderHashWithZeroBuyer(order);

        // console.logBytes32( orderHash);
        // console.logBytes32(orderHashNewFunction);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Perform the purchase (Fill the order)
        startHoax(buyer);
        uint256 initialSellerEthBalance = address(seller).balance;
        uint256 initialBuyerEthBalance = address(buyer).balance;

        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0)
        );

        // Assert token balances
        uint256 expectedSellerTokenBalance = initialSellerTokenBalance -
            orderAmount;
        uint256 expectedBuyerTokenBalance = initialBuyerTokenBalance +
            orderAmount;
        uint256 sellerTokenBalance = token.balanceOf(seller);
        uint256 buyerTokenBalance = token.balanceOf(buyer);
        assertEq(
            sellerTokenBalance,
            expectedSellerTokenBalance,
            "Seller token balance incorrect after filling order"
        );
        assertEq(
            buyerTokenBalance,
            expectedBuyerTokenBalance,
            "Buyer token balance incorrect after filling order"
        );

        // Assert ETH balances
        uint256 expectedSellerEthBalance = initialSellerEthBalance + priceInWei;
        uint256 expectedBuyerEthBalance = initialBuyerEthBalance - priceInWei;
        uint256 sellerEthBalance = address(seller).balance;
        uint256 buyerEthBalance = address(buyer).balance;
        assertEq(
            sellerEthBalance,
            expectedSellerEthBalance,
            "Seller ETH balance incorrect after filling order"
        );
        assertEq(
            buyerEthBalance,
            expectedBuyerEthBalance,
            "Buyer ETH balance incorrect after filling order"
        );
    }

    function testFillOrder_IncrementTradingPairNonce_() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);

        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, priceInWei + 1);
        token.mint(buyer, priceInWei + 1);

        vm.prank(buyer);
        token.approve(address(exchange), priceInWei);

        exchange.updateSaleToken(address(0), true);
        exchange.updatePaymentToken(address(token), true);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(token), // For ETH
            saleToken: address(0),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        Order memory order2 = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(token), // For ETH
            saleToken: address(0),
            nonce: 0,
            buyer: address(0),
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHashNewFunction = getEIP712OrderHashWithZeroBuyer(order);

        // console.logBytes32( orderHash);
        // console.logBytes32(orderHashNewFunction);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        Order[] memory orders = new Order[](1);
        Signature[] memory signatures = new Signature[](1);

        orders[0] = order2;

        signatures[0] = Signature({v: v, r: r, s: s});

        hoax(seller, 10 ether);
        exchange.createOrder{value: order.amount}(order2, v, r, s);

        assertEq(seller.balance, 10 ether - order.amount);

        vm.prank(seller);
        exchange.incrementPairNonce(
            address(token),
            address(0),
            orders,
            signatures
        );

        // should have refund
        assertEq(seller.balance, 10 ether);

        // Perform the purchase (Fill the order)
        startHoax(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                OtcExchange_V2.OrderFillFailed.selector,
                order
            )
        );
        exchange.fillOrder(order, v, r, s, v2, r2, s2, address(0));
    }

    function testFillOrder_IncrementTradingPairNonceWithDuplicateOrder()
        public
    {
        // Initial Setup
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);

        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, priceInWei + 1);
        token.mint(buyer, priceInWei + 1);

        vm.prank(buyer);
        token.approve(address(exchange), priceInWei);

        exchange.updateSaleToken(address(0), true);
        exchange.updatePaymentToken(address(token), true);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(token), // For ETH
            saleToken: address(0),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        Order memory order2 = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(token), // For ETH
            saleToken: address(0),
            nonce: 0,
            buyer: address(0),
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHashNewFunction = getEIP712OrderHashWithZeroBuyer(order);

        // console.logBytes32( orderHash);
        // console.logBytes32(orderHashNewFunction);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        Order[] memory orders = new Order[](2);
        Signature[] memory signatures = new Signature[](2);

        orders[0] = order2;
        orders[1] = order2;

        signatures[0] = Signature({v: v, r: r, s: s});
        signatures[1] = Signature({v: v, r: r, s: s});

        hoax(seller, 10 ether);
        exchange.createOrder{value: order.amount}(order2, v, r, s);

        assertEq(seller.balance, 10 ether - order.amount);

        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                OtcExchange_V2.OrderCancelError.selector,
                order2
            )
        );
        exchange.incrementPairNonce(
            address(token),
            address(0),
            orders,
            signatures
        );
    }

    function testFillOrder_2() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 priceInWei = 100;
        uint128 orderAmount = 1 ether;

        exchange.updateSaleToken(address(0), true);
        exchange.updatePaymentToken(address(token), true);

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(buyer);
        token.approve(address(exchange), orderAmount);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(token), // For ETH
            saleToken: address(0),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        uint256 initialSellerEthBalance = 10 ether;

        hoax(seller, 10 ether);
        exchange.createOrder{value: orderAmount}(order, v, r, s);

        // Perform the purchase (Fill the order)
        startHoax(buyer);

        uint256 initialBuyerEthBalance = address(buyer).balance;

        // zero value because we are buying eth with tokens
        exchange.fillOrder{value: 0}(order, v, r, s, v2, r2, s2, buyer);

        // Assert token balances
        uint256 expectedSellerTokenBalance = initialSellerTokenBalance +
            priceInWei;
        uint256 expectedBuyerTokenBalance = initialBuyerTokenBalance -
            priceInWei;
        uint256 sellerTokenBalance = token.balanceOf(seller);
        uint256 buyerTokenBalance = token.balanceOf(buyer);
        assertEq(
            sellerTokenBalance,
            expectedSellerTokenBalance,
            "Seller token balance incorrect after filling order"
        );
        assertEq(
            buyerTokenBalance,
            expectedBuyerTokenBalance,
            "Buyer token balance incorrect after filling order"
        );

        // Assert ETH balances
        uint256 expectedSellerEthBalance = initialSellerEthBalance -
            orderAmount;
        uint256 expectedBuyerEthBalance = initialBuyerEthBalance + orderAmount;
        uint256 sellerEthBalance = address(seller).balance;
        uint256 buyerEthBalance = address(buyer).balance;
        assertEq(
            sellerEthBalance,
            expectedSellerEthBalance,
            "Seller ETH balance incorrect after filling order"
        );
        assertEq(
            buyerEthBalance,
            expectedBuyerEthBalance,
            "Buyer ETH balance incorrect after filling order"
        );
    }

    function testFillOrder_2_CancelOrderCannotBeFilled() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 priceInWei = 100;
        uint128 orderAmount = 1 ether;

        exchange.updateSaleToken(address(0), true);
        exchange.updatePaymentToken(address(token), true);

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(buyer);
        token.approve(address(exchange), orderAmount);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(token), // For ETH
            saleToken: address(0),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        uint256 initialSellerEthBalance = 10 ether;

        hoax(seller, 10 ether);
        exchange.createOrder{value: orderAmount}(order, v, r, s);
        assertEq(
            initialSellerEthBalance - orderAmount,
            address(seller).balance
        );
        vm.prank(seller);
        exchange.cancelOrder(order, v, r, s);

        assertEq(initialSellerEthBalance, address(seller).balance);

        // Perform the purchase (Fill the order)
        startHoax(buyer);

        uint256 initialBuyerEthBalance = address(buyer).balance;

        vm.expectRevert(
            abi.encodeWithSelector(
                OtcExchange_V2.OrderFillFailed.selector,
                order
            )
        );
        exchange.fillOrder{value: 0}(order, v, r, s, v2, r2, s2, buyer);
    }

    function testFillOrder_2_CancelOrderFromWrongAddress() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 priceInWei = 100;
        uint128 orderAmount = 1 ether;

        exchange.updateSaleToken(address(0), true);
        exchange.updatePaymentToken(address(token), true);

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(buyer);
        token.approve(address(exchange), orderAmount);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(token), // For ETH
            saleToken: address(0),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        uint256 initialSellerEthBalance = 10 ether;

        hoax(seller, 10 ether);
        exchange.createOrder{value: orderAmount}(order, v, r, s);
        assertEq(
            initialSellerEthBalance - orderAmount,
            address(seller).balance
        );

        vm.prank(buyer);
        vm.expectRevert(OtcExchange_V2.Unauthorised.selector);
        exchange.cancelOrder(order, v, r, s);

        vm.prank(seller);
        vm.expectRevert(OtcExchange_V2.Unauthorised.selector);
        exchange.cancelOrder(order, v, r, bytes32(uint256(0x4444)));

        vm.prank(seller);
        exchange.cancelOrder(order, v, r, s);

        assertEq(initialSellerEthBalance, address(seller).balance);
    }

    function testFillOrderWithIncorrectBuyer() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        address wrongAddress = address(0x69696969);
        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0), // For ETH
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order (use the correct buyer address)
        bytes32 orderHash = exchange.getEIP712OrderHash(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Perform the purchase (Fill the order)
        startHoax(wrongAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                OtcExchange_V2.OrderFillFailed.selector,
                order
            )
        );
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            buyer
        );

        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         OtcExchange_V2.OrderFillFailed.selector,
        //         order
        //     )
        // );
        // exchange.fillOrder{value: priceInWei}(
        //     order,
        //     v,
        //     r,
        //     s,
        //     v2,
        //     r2,
        //     s2,
        //     wrongAddress
        // );

        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         OtcExchange_V2.OrderFillFailed.selector,
        //         order
        //     )
        // );
        // exchange.fillOrder{value: priceInWei}(
        //     order,
        //     v,
        //     r,
        //     s,
        //     v2,
        //     r2,
        //     s2,
        //     buyer
        // );
    }

    function testCannotFillOrderTwice() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount * 2);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Perform the purchase (Fill the order)
        startHoax(buyer);
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0)
        );

        // Prepare the custom error data
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        // Try to fill the same order again and expect a revert
        vm.expectRevert(customErrorData);
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0)
        );
    }

    function testCannotFillCancelledOrder() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount * 2);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHash(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            exchange.getEIP712OrderHashWithZeroBuyer(order)
        );

        // Cancel the order
        vm.prank(seller);
        exchange.cancelOrder(order, v, r, s);

        // Prepare the custom error data for a failed order fill attempt
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        hoax(buyer);

        // Try to fill the cancelled order and expect a revert
        vm.expectRevert(customErrorData);
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0)
        );
    }

    function testOnlySellerCanCancelOrder() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address nonSeller = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balance for the seller
        token.mint(seller, initialSellerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount * 2);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0),
            saleToken: address(token),
            nonce: 0,
            buyer: address(0),
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        vm.prank(nonSeller);
        vm.expectRevert(OtcExchange_V2.Unauthorised.selector);
        exchange.cancelOrder(order, v, r, s);

        // Proper cancellation by the seller should succeed
        vm.prank(seller);
        exchange.cancelOrder(order, v, r, s);

        // Verify that the order is indeed cancelled (e.g., attempt to fill it)
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        vm.expectRevert(customErrorData);
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0)
        );
    }

    /// @notice Test that an order with an invalid sale token cannot be filled
    /// @dev Uses OpenZeppelin's AccessControl for role-based access control.
    function testCannotFillInvalidSaleTokenOrder() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount * 2);

        exchange.updateSaleToken(address(token), false);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Prepare the custom error data for a failed order fill attempt
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        // Try to fill the order with invalid sale token and expect a revert
        vm.expectRevert(customErrorData);
        hoax(buyer);
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0)
        );
    }

    function testCannotFillExpiredOrder() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount * 2);

        // Construct an order that expires immediately
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Prepare the custom error data for a failed order fill attempt
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        vm.warp(block.timestamp + 1 days + 1 seconds);

        hoax(buyer);
        // Try to fill the expired order and expect a revert
        vm.expectRevert(customErrorData);
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0)
        );
    }

    function testCannotFillOrderWithIncrementedNonce() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount * 2);

        // Construct the initial order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        Order[] memory orders = new Order[](0);
        Signature[] memory signatures = new Signature[](0);

        // Increment the seller's nonce
        vm.prank(seller);
        exchange.incrementNonce(orders, signatures);

        // Prepare the custom error data for a failed order fill attempt
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        // Try to fill the order with the incremented nonce and expect a revert
        vm.expectRevert(customErrorData);
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0)
        );
    }

    /// @notice Test that only accounts with WITHDRAWER_ROLE can withdraw ETH.
    /// @dev Uses OpenZeppelin's AccessControl for role-based access control.
    function testOnlyWithdrawerCanWithdrawETH() public {
        address payable recipient = payable(vm.addr(ownerPrivateKey));

        // Test that only an account with WITHDRAWER_ROLE can withdraw
        vm.prank(address(0x1337));

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(0x1337), 0x10dac8c06a04bec0b551627dad28bc00d6516b0caacd1c7b345fcdb5211334e4));
        exchange.withdraw(recipient);

        // Assign WITHDRAWER_ROLE to the msg.sender (contract's owner assumed)
        vm.prank(vm.addr(ownerPrivateKey));
        exchange.grantRole(exchange.WITHDRAWER_ROLE(), address(this));

        // Now, the withdraw should work
        exchange.withdraw(recipient);
    }

    /// @notice Test that only accounts with WITHDRAWER_ROLE can withdraw ERC20 tokens.
    /// @dev Uses OpenZeppelin's AccessControl for role-based access control.
    function testOnlyWithdrawerCanWithdrawTokens() public {
        address recipient = vm.addr(ownerPrivateKey);
        uint256 initialContractTokenBalance = 1000 * 10 ** 18; // Assume 18 decimals
        uint256 withdrawAmount = 200 * 10 ** 18; // Assume 18 decimals
        uint256 initialRecipientBalance = token.balanceOf(recipient);

        // Mint tokens to the contract
        token.mint(address(exchange), initialContractTokenBalance);

        // Test that only an account with WITHDRAWER_ROLE can withdraw tokens
        vm.prank(address(0x1337));
         vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(0x1337), 0x10dac8c06a04bec0b551627dad28bc00d6516b0caacd1c7b345fcdb5211334e4));
       
        exchange.withdrawToken(token, recipient, withdrawAmount);

        // Assign WITHDRAWER_ROLE to the msg.sender (contract's owner assumed)
        vm.prank(vm.addr(ownerPrivateKey));
        exchange.grantRole(exchange.WITHDRAWER_ROLE(), address(this));

        // Now, the token withdraw should work
        exchange.withdrawToken(token, recipient, withdrawAmount);

        // Assert that the contract's and recipient's token balances are as expected
        assertEq(
            token.balanceOf(address(exchange)),
            initialContractTokenBalance - withdrawAmount
        );
        assertEq(
            token.balanceOf(recipient),
            initialRecipientBalance + withdrawAmount
        );
    }

    function testFillOrderWithErc20Payment() public {
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint256 initialPaymentTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInTokens = 50; // Price in ERC-20 tokens

        MockERC20 paymentToken = new MockERC20("PaymentToken", "PT", 0);
        exchange.updatePaymentToken(address(paymentToken), true);

        // Mint initial token balances for sale and payment tokens
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);
        paymentToken.mint(buyer, initialPaymentTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount); // Seller approves the sale token

        vm.prank(buyer);
        paymentToken.approve(address(exchange), priceInTokens); // Buyer approves the payment token

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInTokens,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(paymentToken),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Perform the purchase (Fill the order)
        startHoax(buyer);
        uint256 initialBuyerPaymentTokenBalance = paymentToken.balanceOf(buyer);

        exchange.fillOrder(order, v, r, s, v2, r2, s2, address(0));

        // Assert token balances
        uint256 expectedSellerTokenBalance = initialSellerTokenBalance -
            orderAmount;
        uint256 expectedBuyerTokenBalance = initialBuyerTokenBalance +
            orderAmount;
        uint256 expectedBuyerPaymentTokenBalance = initialBuyerPaymentTokenBalance -
                priceInTokens;

        uint256 sellerTokenBalance = token.balanceOf(seller);
        uint256 buyerTokenBalance = token.balanceOf(buyer);
        uint256 buyerPaymentTokenBalance = paymentToken.balanceOf(buyer);

        assertEq(
            sellerTokenBalance,
            expectedSellerTokenBalance,
            "Seller token balance incorrect after filling order"
        );
        assertEq(
            buyerTokenBalance,
            expectedBuyerTokenBalance,
            "Buyer token balance incorrect after filling order"
        );
        assertEq(
            buyerPaymentTokenBalance,
            expectedBuyerPaymentTokenBalance,
            "Buyer payment token balance incorrect after filling order"
        );
    }

    function testFillOrderWithErc20PaymentNotValidPaymentToken() public {
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint256 initialPaymentTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInTokens = 50; // Price in ERC-20 tokens

        MockERC20 paymentToken = new MockERC20("PaymentToken", "PT", 0);

        // don't update payment token
        //exchange.updatePaymentToken(address(paymentToken), true);

        // Mint initial token balances for sale and payment tokens
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);
        paymentToken.mint(buyer, initialPaymentTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount); // Seller approves the sale token

        vm.prank(buyer);
        paymentToken.approve(address(exchange), priceInTokens); // Buyer approves the payment token

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInTokens,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(paymentToken),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Perform the purchase (Fill the order)
        startHoax(buyer);
        uint256 initialBuyerPaymentTokenBalance = paymentToken.balanceOf(buyer);

        // Prepare the custom error data
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        // Try to fill the same order again and expect a revert
        vm.expectRevert(customErrorData);
        exchange.fillOrder(order, v, r, s, v2, r2, s2, address(0));
    }

    function testInsufficientSellerTokensWithErc20Payment() public {
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialBuyerTokenBalance = 1000;
        uint256 initialPaymentTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInTokens = 50; // Price in ERC-20 tokens

        MockERC20 paymentToken = new MockERC20("PaymentToken", "PT", 0);
        exchange.updatePaymentToken(address(paymentToken), true);

        // Mint initial token balances for buyer
        token.mint(buyer, initialBuyerTokenBalance);
        paymentToken.mint(buyer, initialPaymentTokenBalance);

        // Mint tokens to the seller, but 1 less than the order amount
        uint256 insufficientSellerTokenBalance = orderAmount - 1;
        token.mint(seller, insufficientSellerTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount); // Seller approves the sale token

        vm.prank(buyer);
        paymentToken.approve(address(exchange), priceInTokens); // Buyer approves the payment token

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInTokens,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(paymentToken),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Perform the purchase (Should revert)
        startHoax(buyer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, seller, insufficientSellerTokenBalance, orderAmount));
        
        exchange.fillOrder(order, v, r, s, v2, r2, s2, address(0));
    }

    function testInsufficientBuyerPaymentTokens() public {
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInTokens = 50; // Price in ERC-20 tokens

        MockERC20 paymentToken = new MockERC20("PaymentToken", "PT", 0);

        exchange.updatePaymentToken(address(paymentToken), true);

        // Mint initial token balances for seller and buyer
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        // Mint payment tokens to the buyer, but 1 less than the price in tokens
        uint256 insufficientBuyerPaymentTokenBalance = priceInTokens - 1;
        paymentToken.mint(buyer, insufficientBuyerPaymentTokenBalance);

        vm.prank(seller);
        token.approve(address(exchange), orderAmount); // Seller approves the sale token

        vm.prank(buyer);
        paymentToken.approve(address(exchange), priceInTokens); // Buyer approves the payment token

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInTokens,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(paymentToken),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroBuyer(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Perform the purchase (Should revert)
        startHoax(buyer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, buyer, insufficientBuyerPaymentTokenBalance, priceInTokens));
        exchange.fillOrder(order, v, r, s, v2, r2, s2, address(0));
    }

    function testFillBuyOrderWithErc20Payment() public {
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint256 initialPaymentTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInTokens = 50; // Price in ERC-20 tokens

        MockERC20 paymentToken = new MockERC20("PaymentToken", "PT", 0);
        exchange.updatePaymentToken(address(paymentToken), true);

        // Mint initial token balances for sale and payment tokens
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);
        paymentToken.mint(buyer, initialPaymentTokenBalance); // Mint payment tokens to buyer

        vm.prank(buyer);
        paymentToken.approve(address(exchange), priceInTokens); // Buyer approves the payment token

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInTokens,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(paymentToken),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHashWithZeroSeller(order);
        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(spenderPrivateKey, orderHash); // Signing by buyer
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Perform the purchase (Fill the order)
        startHoax(seller); // Assuming seller initiates the filling of buy order
        uint256 initialSellerPaymentTokenBalance = paymentToken.balanceOf(
            seller
        );
        token.approve(address(exchange), orderAmount); // Seller approves the sale token

        exchange.fillOrder(order, v, r, s, v2, r2, s2, address(0));

        // Assert token balances
        uint256 expectedSellerTokenBalance = initialSellerTokenBalance -
            orderAmount;
        uint256 expectedBuyerTokenBalance = initialBuyerTokenBalance +
            orderAmount;
        uint256 expectedSellerPaymentTokenBalance = initialSellerPaymentTokenBalance +
                priceInTokens;

        uint256 sellerTokenBalance = token.balanceOf(seller);
        uint256 buyerTokenBalance = token.balanceOf(buyer);
        uint256 sellerPaymentTokenBalance = paymentToken.balanceOf(seller);

        assertEq(
            sellerTokenBalance,
            expectedSellerTokenBalance,
            "Seller token balance incorrect after filling order"
        );
        assertEq(
            buyerTokenBalance,
            expectedBuyerTokenBalance,
            "Buyer token balance incorrect after filling order"
        );
        assertEq(
            sellerPaymentTokenBalance,
            expectedSellerPaymentTokenBalance,
            "Seller payment token balance incorrect after filling order"
        );
    }

    /// @notice Generates the EIP-712 hash of the order with zero buyer address
    /// @param order The order to hash
    /// @return hash of the order
    function getEIP712OrderHashWithZeroBuyer(
        Order memory order
    ) private view returns (bytes32) {
        Order memory newOrder = Order({
            amount: order.amount,
            price: order.price,
            seller: order.seller,
            validUntil: order.validUntil,
            id: order.id,
            paymentToken: order.paymentToken,
            saleToken: order.saleToken,
            nonce: order.nonce,
            buyer: address(0),
            pairNonce: 0 // Setting buyer to address(0)
        });
        return exchange.getEIP712OrderHash(newOrder);
    }

    /// @notice Generates the EIP-712 hash of the order with zero seller address
    /// @param order The order to hash
    /// @return hash of the order
    function getEIP712OrderHashWithZeroSeller(
        Order memory order
    ) private view returns (bytes32) {
        Order memory newOrder = Order({
            amount: order.amount,
            price: order.price,
            seller: address(0), // Setting seller to address(0)
            validUntil: order.validUntil,
            id: order.id,
            paymentToken: order.paymentToken,
            saleToken: order.saleToken,
            nonce: order.nonce,
            buyer: order.buyer,
            pairNonce: 0
        });
        return exchange.getEIP712OrderHash(newOrder);
    }

    function testCreateOnchainOrder() public {
        // Initial Setup
        address buyer = vm.addr(ownerPrivateKey);
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: address(0),
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0), // For ETH
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);

        // Perform the order creation
        startHoax(buyer);
        uint256 initialBuyerEthBalance = address(buyer).balance;

        exchange.createOrder{value: priceInWei}(order, v, r, s);

        // Assert order storage
        bytes32 expectedOrderHash = exchange.getEIP712OrderHash(order);

        (
            uint128 amount2,
            uint128 price2,
            address seller2,
            uint64 validUntil2,
            uint32 id2,
            address paymentToken2,
            address saleToken2,
            uint64 nonce2,
            address buyer2,
            uint256 pairNonce2
        ) = exchange.buyOrdersWithEth(expectedOrderHash);

        Order memory storedOrder = Order({
            amount: amount2,
            price: price2,
            seller: seller2,
            id: id2,
            validUntil: validUntil2,
            paymentToken: paymentToken2,
            saleToken: saleToken2,
            nonce: nonce2,
            buyer: buyer2,
            pairNonce: 0
        });

        assertEq(
            storedOrder.amount,
            orderAmount,
            "Stored order amount incorrect after creating order"
        );

        // Check the other fields of the stored order
        assertEq(
            storedOrder.price,
            priceInWei,
            "Stored order price incorrect after creating order"
        );
        assertEq(
            storedOrder.seller,
            address(0),
            "Stored order seller incorrect after creating order"
        );
        assertEq(
            storedOrder.buyer,
            buyer,
            "Stored order buyer incorrect after creating order"
        );
        assertEq(
            storedOrder.paymentToken,
            address(0),
            "Stored order paymentToken incorrect after creating order"
        );
        assertEq(
            storedOrder.saleToken,
            address(token),
            "Stored order saleToken incorrect after creating order"
        );
        assertEq(
            storedOrder.validUntil,
            uint64(block.timestamp + 1 days),
            "Stored order validUntil incorrect after creating order"
        );
        // Assert ETH balances
        uint256 expectedBuyerEthBalance = initialBuyerEthBalance - priceInWei;
        uint256 buyerEthBalance = address(buyer).balance;
        assertEq(
            buyerEthBalance,
            expectedBuyerEthBalance,
            "Seller ETH balance incorrect after creating order"
        );
    }

    function testCreateOnchainOrderTwice() public {
        // Initial Setup
        address buyer = vm.addr(ownerPrivateKey);
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: address(0),
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0), // For ETH
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);

        // Perform the order creation
        startHoax(buyer);
        exchange.createOrder{value: priceInWei}(order, v, r, s);

        // Attempt to create the same order again and expect a revert
        vm.expectRevert(
            abi.encodeWithSelector(
                OtcExchange_V2.OrderCreateError.selector,
                order
            )
        );
        exchange.createOrder{value: priceInWei}(order, v, r, s);
    }

    function testCreateOnchainOrderWithInsufficientEth() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0), // For ETH
            saleToken: address(token),
            nonce: 0,
            buyer: address(0),
            pairNonce: 0 // No buyer specified
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);

        // Perform the order creation with insufficient Ether and expect a revert
        startHoax(seller);

        vm.expectRevert(
            abi.encodeWithSelector(
                OtcExchange_V2.OrderCreateError.selector,
                order
            )
        );
        exchange.createOrder{value: priceInWei - 1}(order, v, r, s); // Sending one less wei than the order price
    }

    function testCreateAndFillOnchainOrder() public {
        // Initial Setup
        address buyer = vm.addr(ownerPrivateKey);
        address signer = vm.addr(signerPrivateKey);

        exchange.updateSigner(signer, true);
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: address(0),
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0), // For ETH
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);

        // Perform the order creation
        startHoax(buyer);

        uint256 initialBuyerEthBalance = address(buyer).balance;
        exchange.createOrder{value: priceInWei}(order, v, r, s);

        // Assert order storage
        bytes32 expectedOrderHash = exchange.getEIP712OrderHash(order);
        (
            uint128 amount2,
            uint128 price2,
            address seller2,
            uint64 validUntil2,
            uint32 id2,
            address paymentToken2,
            address saleToken2,
            uint64 nonce2,
            address buyer2,
            uint256 pairNonce2
        ) = exchange.buyOrdersWithEth(expectedOrderHash);

        Order memory storedOrder = Order({
            amount: amount2,
            price: price2,
            seller: seller2,
            id: id2,
            validUntil: validUntil2,
            paymentToken: paymentToken2,
            saleToken: saleToken2,
            nonce: nonce2,
            buyer: buyer2,
            pairNonce: pairNonce2
        });

        assertEq(
            storedOrder.amount,
            orderAmount,
            "Stored order amount incorrect after creating order"
        );

        // Perform the order filling
        address seller = vm.addr(spenderPrivateKey);

        token.mint(seller, orderAmount);

        vm.stopPrank();
        startHoax(seller);

        token.approve(address(exchange), orderAmount);

        Order memory orderToFill = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0), // For ETH
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        bytes32 orderHash2 = exchange.getEIP712OrderHash(orderToFill);

        // Sign the order again for the fillOrder function
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        uint256 initialSellerEthBalance = address(seller).balance;

        console.log("start fill order for: ", msg.sender);
        exchange.fillOrder(
            orderToFill,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            address(0) // Allowing any taker
        );

        // Assert token balances
        uint256 sellerTokenBalance = token.balanceOf(seller);
        uint256 buyerTokenBalance = token.balanceOf(buyer);

        assertEq(
            sellerTokenBalance,
            0,
            "Seller token balance incorrect after filling order"
        );
        assertEq(
            buyerTokenBalance,
            orderAmount,
            "Buyer token balance incorrect after filling order"
        );

        // Assert ETH balances
        uint256 expectedSellerEthBalance = initialSellerEthBalance + priceInWei;
        uint256 expectedBuyerEthBalance = initialBuyerEthBalance - priceInWei;
        uint256 sellerEthBalance = address(seller).balance;
        uint256 buyerEthBalance = address(buyer).balance;

        assertEq(
            sellerEthBalance,
            expectedSellerEthBalance,
            "Seller ETH balance incorrect after filling order"
        );
        assertEq(
            buyerEthBalance,
            expectedBuyerEthBalance,
            "Buyer ETH balance incorrect after filling order"
        );
    }

    function testCannotFillOrderAfterNonceIncrement() public {
        // Initial Setup
        address seller = vm.addr(ownerPrivateKey);
        address buyer = vm.addr(spenderPrivateKey);
        uint256 initialSellerTokenBalance = 1000;
        uint256 initialBuyerTokenBalance = 1000;
        uint128 orderAmount = 100;
        uint128 priceInWei = 1 ether;

        // Mint initial token balances
        token.mint(seller, initialSellerTokenBalance);
        token.mint(buyer, initialBuyerTokenBalance);

        vm.startPrank(seller);
        token.approve(address(exchange), orderAmount);

        // Construct the order
        Order memory order = Order({
            amount: orderAmount,
            price: priceInWei,
            seller: seller,
            id: 0,
            validUntil: uint64(block.timestamp + 1 days),
            paymentToken: address(0),
            saleToken: address(token),
            nonce: 0,
            buyer: buyer,
            pairNonce: 0
        });

        // Sign the order
        bytes32 orderHash = exchange.getEIP712OrderHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, orderHash);

        bytes32 orderHash2 = exchange.getEIP712OrderHash(order);

        // Sign the order again for the fillOrder function
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            signerPrivateKey,
            orderHash2
        );

        // Increment the seller's sellNonce

        Order[] memory orders = new Order[](0);
        Signature[] memory signatures = new Signature[](0);

        exchange.incrementNonce(orders, signatures);
        vm.stopPrank();

        // Prepare the custom error data for the expected revert
        bytes memory customErrorData = abi.encodeWithSelector(
            OtcExchange_V2.OrderFillFailed.selector,
            order
        );

        // Try to fill the order after nonce increment and expect a revert
        vm.expectRevert(customErrorData);
        startHoax(buyer);
        exchange.fillOrder{value: priceInWei}(
            order,
            v,
            r,
            s,
            v2,
            r2,
            s2,
            buyer
        );
    }
}
