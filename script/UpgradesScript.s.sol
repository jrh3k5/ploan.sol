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

        console.log("Deploying a new instance of the contract");

        address transparentProxy = Upgrades.deployTransparentProxy("Ploan.sol", msg.sender, abi.encodeCall(Ploan.initialize, ()));

        console.log("Deployed contract to proxy address", transparentProxy);

        address implementationAddress = Upgrades.getImplementationAddress(transparentProxy);

        console.log("Deployed implementation contract to address", implementationAddress);
    }
}
