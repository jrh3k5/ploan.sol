// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";

import {Ploan} from "../src/Ploan.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {console} from "forge-std/console.sol";

contract UpgradesScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address transparentProxy = vm.envOr("TRANSPARENT_PROXY_ADDRESS", address(0));
        if (transparentProxy == address(0)) {
            console.log("Deploying a new instance of the contract");

            Upgrades.deployTransparentProxy("Ploan.sol", msg.sender, abi.encodeCall(Ploan.initialize, ()));

            console.log("Deployed contract to address", transparentProxy);

            return;
        }

        console.log("Upgrading contract at address", transparentProxy);

        Upgrades.upgradeProxy(transparentProxy, "Ploan.sol", "");
    }
}
