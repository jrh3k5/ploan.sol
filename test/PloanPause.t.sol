// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ploan, NotAllowedPauser} from "../src/Ploan.sol";
import {PloanTestToken} from "./mocks/PloanTestToken.sol";
import {UnsafeUpgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

contract PloanPauseTest is Test {
    Ploan private ploan;
    address internal pauser1;
    address internal pauser2;
    address internal nonPauser;

    function setUp() public {
        pauser1 = address(1);
        pauser2 = address(2);
        nonPauser = address(3);

        address implementation = address(new Ploan());
        address proxy = UnsafeUpgrades.deployUUPSProxy(implementation, abi.encodeCall(Ploan.initialize, ()));
        ploan = Ploan(proxy);
    }

    function test_initialPauserIsDeployer() public view {
        // The test contract is the deployer and should be a pauser
        assertTrue(ploan.isPauser(address(this)));
    }

    function test_onlyPauserCanPause() public {
        // Add pauser1
        ploan.addPauser(pauser1);
        assertTrue(ploan.isPauser(pauser1));

        // pauser1 can pause
        vm.prank(pauser1);
        ploan.pause();
        assertTrue(ploan.paused());
    }

    function test_onlyPauserCanUnpause() public {
        // Add pauser1 and pause
        ploan.addPauser(pauser1);
        vm.prank(pauser1);
        ploan.pause();
        assertTrue(ploan.paused());

        // pauser1 can unpause
        vm.prank(pauser1);
        ploan.unpause();
        assertFalse(ploan.paused());
    }

    function test_nonPauserCannotPauseOrUnpause() public {
        // Non-pauser cannot pause
        vm.prank(nonPauser);
        vm.expectRevert(abi.encodeWithSelector(NotAllowedPauser.selector, nonPauser));
        ploan.pause();

        // Add pauser1 and pause
        ploan.addPauser(pauser1);
        vm.prank(pauser1);
        ploan.pause();
        assertTrue(ploan.paused());

        // Non-pauser cannot unpause
        vm.prank(nonPauser);
        vm.expectRevert(abi.encodeWithSelector(NotAllowedPauser.selector, nonPauser));
        ploan.unpause();
    }

    function test_pauserCanAddAndRemovePauser() public {
        // Add pauser1
        ploan.addPauser(pauser1);
        assertTrue(ploan.isPauser(pauser1));

        // pauser1 adds pauser2
        vm.prank(pauser1);
        ploan.addPauser(pauser2);
        assertTrue(ploan.isPauser(pauser2));

        // pauser1 removes pauser2
        vm.prank(pauser1);
        ploan.removePauser(pauser2);
        assertFalse(ploan.isPauser(pauser2));
    }

    function test_pauseBlocksStateChangingFunctions() public {
        // Add pauser1 and pause
        ploan.addPauser(pauser1);
        vm.prank(pauser1);
        ploan.pause();
        assertTrue(ploan.paused());

        // Try to call a state-changing function (e.g., addPauser)
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        ploan.addPauser(address(4));
    }
}
