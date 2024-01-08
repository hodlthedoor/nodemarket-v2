// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

struct Order {
    uint128 amount;
    uint128 price;
    address seller;
    uint64 validUntil;
    uint32 id;
    address paymentToken;
    address saleToken;
    uint64 nonce;
    address buyer;
    uint256 pairNonce;
}
