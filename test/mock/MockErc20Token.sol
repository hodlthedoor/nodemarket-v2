// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract HYPCMockToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("HYPCMockToken", "HYPC") {
        _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
