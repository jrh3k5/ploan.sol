// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// PloanTestToken is a simple ERC20 for testing
contract PloanTestToken is ERC20 {
    constructor(uint256 _initialSupply) ERC20("PloanTestToken", "PTT") {
        _mint(msg.sender, _initialSupply);
    }
}