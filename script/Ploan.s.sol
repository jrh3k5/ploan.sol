// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Ploan} from "../src/Ploan.sol";

contract CounterScript is Script {
    Ploan public ploan;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ploan = new Ploan();

        vm.stopBroadcast();
    }
}
