//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        // Mint some initial tokens to the deployer for testing purposes
        _mint(msg.sender, 1_000_000_000 * 10**18); // 1 billion tokens
    }
} 