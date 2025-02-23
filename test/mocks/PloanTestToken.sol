// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice PloanTestToken is a simple ERC20 for testing
/// @author Joshua Hyde
/// @custom:security-contact 0x9134fc7112b478e97eE6F0E6A7bf81EcAfef19ED
contract PloanTestToken is ERC20 {
    /// @notice constructor
    /// @param _initialSupply initial supply of the token
    constructor(uint256 _initialSupply) ERC20("PloanTestToken", "PTT") {
        _mint(msg.sender, _initialSupply);
    }
}
