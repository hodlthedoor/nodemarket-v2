// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ICrowdFundPoolV3Mock {
    function swapTokens(uint256 proposalIndex, uint256 tokensToSwap, uint256 level) external;
    function redeemTokens(uint256 proposalIndex, uint256 tokensToRedeem) external;
    function redeemSingleToken(uint256 proposalIndex, uint256 tokenToRedeem) external;
}
