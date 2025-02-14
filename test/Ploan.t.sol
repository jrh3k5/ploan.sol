// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Ploan} from "../src/Ploan.sol";
import {PloanTestToken} from "./mocks/PloanTestToken.sol";

contract PloanTest is Test {
    Ploan public ploan;
    PloanTestToken public token;

    address internal lender;
    address internal borrower;

    function setUp() public {
        lender = address(1);
        borrower = address(2);

        ploan = new Ploan();
        token = new PloanTestToken(1000);
    }

    function test_defaultLifecycle() public {
        token.transfer(lender, 120);

        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanID);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanID);

        // The loaned amount should be transferred to the lender
        assertEq(token.balanceOf(lender), 20);
        assertEq(token.balanceOf(borrower), 100);

        vm.prank(borrower);
        token.approve(address(ploan), 50);

        vm.prank(borrower);
        ploan.payLoan(loanID, 50);

        assertEq(token.balanceOf(lender), 70);
        assertEq(token.balanceOf(borrower), 50);

        vm.prank(borrower);
        token.approve(address(ploan), 50);

        vm.prank(borrower);
        ploan.payLoan(loanID, 50);

        assertEq(token.balanceOf(lender), 120);
        assertEq(token.balanceOf(borrower), 0);

        Ploan.PersonalLoan memory completedLoan = ploan.getLoan(loanID);
        assert(completedLoan.completed);
    }
}
