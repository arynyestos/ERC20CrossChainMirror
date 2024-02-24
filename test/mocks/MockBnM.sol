// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockBnM is ERC20 {
    constructor() ERC20("BurnAndMint", "BnM") {}

    // You can add custom functions here, for example, to support burning or minting
    function mint(address to, uint256 amount) public {
        // Note: You should add access control to minting (e.g., onlyOwner)
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        // Note: You should add access control to burning (e.g., onlyOwner)
        _burn(from, amount);
    }
}
