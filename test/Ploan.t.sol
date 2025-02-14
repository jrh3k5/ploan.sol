// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

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

        token.transfer(lender, 120);
    }

    function test_defaultLifecycle() public {
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

    function test_createLoan_zeroAmount() public {
        vm.expectRevert("Total amount must be greater than 0");
        ploan.createLoan(borrower, address(token), 0);
    }

    function test_createLoan_noSelfLoans() public {
        vm.expectRevert("Borrower cannot be the lender");
        vm.prank(lender);
        ploan.createLoan(lender, address(token), 100);
    }

    function test_createLoan_zeroAssetAddress() public {
        vm.expectRevert("Loaned asset cannot be zero address");
        ploan.createLoan(borrower, address(0), 100);
    }

    function test_createLoan_insufficientLenderBalance() public {
        vm.expectRevert("Lender does not have enough balance");
        vm.prank(lender);
        ploan.createLoan(borrower, address(token), 1000);
    }

    function test_commitToLoan_notBorrower() public {
        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.expectRevert("Only the borrower can commit to the loan");
        ploan.commitToLoan(loanID);
    }

    function test_commitToLoan_alreadyCommitted() public {
        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanID);

        vm.prank(borrower);
        ploan.commitToLoan(loanID);
    }

    function test_executeLoan_notLender() public {
        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.expectRevert("Only the lender can execute the loan");
        ploan.executeLoan(loanID);
    }

    function test_executeLoan_borrowerNotCommitted() public {
        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.prank(lender);
        vm.expectRevert("Borrower has not committed to the loan");
        ploan.executeLoan(loanID);
    }

    function test_cancelLoan() public {
        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.prank(lender);
        ploan.cancelLoan(loanID);

        Ploan.PersonalLoan memory loan = ploan.getLoan(loanID);
        assert(loan.canceled);
        assert(!loan.repayable);
    }

    function test_cancelLoan_notLender() public {
        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.expectRevert("Only the lender can cancel the loan");
        ploan.cancelLoan(loanID);
    }

    function test_cancelLoan_alreadyCanceled() public {
        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.prank(lender);
        ploan.cancelLoan(loanID);

        // the lack of an error indicates the idempotency of the operation
        vm.prank(lender);
        ploan.cancelLoan(loanID);
    }

    function test_payLoan_zeroAmount() public {
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

        vm.expectRevert("Amount must be greater than 0");
        vm.prank(borrower);
        ploan.payLoan(loanID, 0);
    }

    function test_payLoan_canceled() public {
        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanID);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanID);

        vm.prank(lender);
        ploan.cancelLoan(loanID);

        vm.prank(borrower);
        vm.expectRevert("Loan is not repayable");
        ploan.payLoan(loanID, 100);
    }

    function test_payLoan_completed() public {
        // Give the lender a starting non-zero balance so that they can
        // try to pay after the loan is completed
        token.transfer(lender, 20);

        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanID);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanID);

        vm.prank(borrower);
        token.approve(address(ploan), 100);

        vm.prank(borrower);
        ploan.payLoan(loanID, 100);

        vm.prank(borrower);
        vm.expectRevert("Loan is not repayable");
        ploan.payLoan(loanID, 20);
    }

    function test_payLoan_overpay() public {
        // Give the lender a starting non-zero balance so that they can
        // try to pay more than what's owed on the loan
        token.transfer(lender, 20);

        vm.prank(lender);
        uint256 loanID = ploan.createLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanID);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanID);

        vm.prank(borrower);
        vm.expectRevert("Total amount repaid must be less than or equal to total amount loaned");
        ploan.payLoan(loanID, 120);
    }
}
