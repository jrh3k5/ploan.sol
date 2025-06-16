// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ploan, NotAllowedPauser, EntryPointManagerModified} from "../src/Ploan.sol";
import {UnsafeUpgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

contract PloanEntryPointTest is Test {
    Ploan private ploan;
    address internal pauser1;
    address internal nonPauser;
    address internal manager;
    address internal entryPoint;

    function setUp() public {
        pauser1 = address(1);
        nonPauser = address(2);
        manager = address(10);
        entryPoint = address(100);

        address implementation = address(new Ploan());
        address proxy = UnsafeUpgrades.deployUUPSProxy(implementation, abi.encodeCall(Ploan.initialize, ()));
        ploan = Ploan(proxy);
    }

    function test_onlyPauserCanAddRemoveEntryPointManager() public {
        // Only pauser can add entry point manager
        vm.prank(pauser1);
        vm.expectRevert(abi.encodeWithSelector(NotAllowedPauser.selector, pauser1));
        ploan.addEntryPointManager(manager);
        // Add pauser1
        ploan.addPauser(pauser1);
        // Now pauser1 can add entry point manager
        vm.prank(pauser1);
        vm.expectEmit(true, true, false, true);
        emit EntryPointManagerModified(manager, true);
        ploan.addEntryPointManager(manager);
        assertTrue(ploan.isEntryPointManager(manager));
        // Only pauser can remove entry point manager
        vm.prank(pauser1);
        vm.expectEmit(true, true, false, true);
        emit EntryPointManagerModified(manager, false);
        ploan.removeEntryPointManager(manager);
        assertFalse(ploan.isEntryPointManager(manager));
    }

    function test_entryPointManagerEventEmitted() public {
        ploan.addPauser(pauser1);
        vm.prank(pauser1);
        vm.expectEmit(true, true, false, true);
        emit EntryPointManagerModified(manager, true);
        ploan.addEntryPointManager(manager);
        vm.prank(pauser1);
        vm.expectEmit(true, true, false, true);
        emit EntryPointManagerModified(manager, false);
        ploan.removeEntryPointManager(manager);
    }

    function test_onlyEntryPointManagerCanAddRemoveEntryPoint() public {
        // Add pauser1 and make manager an entry point manager
        ploan.addPauser(pauser1);
        vm.prank(pauser1);
        ploan.addEntryPointManager(manager);
        // Only entry point manager can add entry point
        vm.prank(nonPauser);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("NotAllowedEntryPointManager(address)")), nonPauser));
        ploan.addEntryPoint(entryPoint);
        // Manager can add entry point
        vm.prank(manager);
        ploan.addEntryPoint(entryPoint);
        assertTrue(ploan.isEntryPoint(entryPoint));
        // Only entry point manager can remove entry point
        vm.prank(nonPauser);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("NotAllowedEntryPointManager(address)")), nonPauser));
        ploan.removeEntryPoint(entryPoint);
        // Manager can remove entry point
        vm.prank(manager);
        ploan.removeEntryPoint(entryPoint);
        assertFalse(ploan.isEntryPoint(entryPoint));
    }

    function test_entryPointManagerAndEntryPointQueries() public {
        ploan.addPauser(pauser1);
        vm.prank(pauser1);
        ploan.addEntryPointManager(manager);
        vm.prank(manager);
        ploan.addEntryPoint(entryPoint);
        assertTrue(ploan.isEntryPointManager(manager));
        assertTrue(ploan.isEntryPoint(entryPoint));
        vm.prank(manager);
        ploan.removeEntryPoint(entryPoint);
        assertFalse(ploan.isEntryPoint(entryPoint));
        vm.prank(pauser1);
        ploan.removeEntryPointManager(manager);
        assertFalse(ploan.isEntryPointManager(manager));
    }
}
