// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Ploan} from "../src/Ploan.sol";

contract PloanScript is Script {
    Ploan public ploan;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ploan = new Ploan();

        vm.stopBroadcast();
    }
}
