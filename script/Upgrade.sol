// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";

import {Ploan} from "../src/Ploan.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradesScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy `Ploan` as a transparent proxy using the Upgrades Plugin
        address transparentProxy =
            Upgrades.deployTransparentProxy("Ploan", msg.sender, abi.encodeCall(Ploan.initialize, ()));
    }
}
