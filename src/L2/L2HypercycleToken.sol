// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { OptimismMintableERC20 } from "./OptimismMintableERC20.sol";

/// @title L2HypercycleToken
/// @notice L2HypercycleToken is a token contract that inherits from OptimismMintableERC20
///         and serves as the L2 representation of the HyperCycleToken.
contract L2HypercycleToken is OptimismMintableERC20 {
    /// @param _bridge      Address of the L2 standard bridge.
    /// @param _remoteToken Address of the corresponding L1 token.
    constructor(address _bridge, address _remoteToken)
        OptimismMintableERC20(_bridge, _remoteToken, "HyperCycleToken", "HYPC", 6)
    {}
}
