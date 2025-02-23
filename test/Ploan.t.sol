// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ploan} from "../src/Ploan.sol";
import {PloanTestToken} from "./mocks/PloanTestToken.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title A simple ERC20 for testing purposes.
/// @author 0x9134fc7112b478e97eE6F0E6A7bf81EcAfef19ED
contract PloanTest is Test {
    Ploan private ploan;
    PloanTestToken private token;

    address internal lender;
    address internal borrower;

    function setUp() public {
        lender = address(1);
        borrower = address(2);

        address implementation = address(new Ploan());
        address proxy = UnsafeUpgrades.deployUUPSProxy(implementation, abi.encodeCall(Ploan.initialize, ()));
        ploan = Ploan(proxy);

        token = new PloanTestToken(1000);
        token.transfer(lender, 120);
    }

    function test_defaultLifecycle() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanId);

        // The loaned amount should be transferred to the lender
        assertEq(token.balanceOf(lender), 20);
        assertEq(token.balanceOf(borrower), 100);

        vm.prank(borrower);
        token.approve(address(ploan), 50);

        vm.prank(borrower);
        ploan.payLoan(loanId, 50);

        assertEq(token.balanceOf(lender), 70);
        assertEq(token.balanceOf(borrower), 50);

        vm.prank(borrower);
        token.approve(address(ploan), 50);

        vm.prank(borrower);
        ploan.payLoan(loanId, 50);

        assertEq(token.balanceOf(lender), 120);
        assertEq(token.balanceOf(borrower), 0);

        vm.prank(lender);
        Ploan.PersonalLoan[] memory loans = ploan.getLoans();
        assertEq(loans.length, 1);
        Ploan.PersonalLoan memory completedLoan = loans[0];
        assert(completedLoan.completed);
    }

    function test_initialize_again() public {
        vm.expectRevert();
        // you should only be able to initialize once
        ploan.initialize();
    }

    function test_disallowLoanProposal() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        // a lack of a failure indicates success
        ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.disallowLoanProposal(lender);

        // Now it should fail
        vm.prank(lender);
        vm.expectRevert("Lender is not allowed to propose a loan");
        ploan.proposeLoan(borrower, address(token), 100);
    }

    function test_proposeLoan_zeroAmount() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.expectRevert("Total amount must be greater than 0");
        ploan.proposeLoan(borrower, address(token), 0);
    }

    function test_proposeLoan_noSelfLoans() public {
        vm.expectRevert("Borrower cannot be the lender");
        vm.prank(lender);
        ploan.proposeLoan(lender, address(token), 100);
    }

    function test_proposeLoan_zeroAssetAddress() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.expectRevert("Loaned asset cannot be zero address");
        ploan.proposeLoan(borrower, address(0), 100);
    }

    function test_proposeLoan_insufficientLenderBalance() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.expectRevert("Lender does not have enough balance");
        vm.prank(lender);
        ploan.proposeLoan(borrower, address(token), 1000);
    }

    function test_proposeLoan_notAllowed() public {
        vm.prank(lender);
        vm.expectRevert("Lender is not allowed to propose a loan");
        ploan.proposeLoan(borrower, address(token), 100);
    }

    function test_commitToLoan_notBorrower() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.expectRevert("Only the borrower can commit to the loan");
        ploan.commitToLoan(loanId);
    }

    function test_commitToLoan_alreadyCommitted() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);
    }

    function test_executeLoan_notLender() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.expectRevert("Only the lender can execute the loan");
        ploan.executeLoan(loanId);
    }

    function test_executeLoan_borrowerNotCommitted() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(lender);
        vm.expectRevert("Borrower has not committed to the loan");
        ploan.executeLoan(loanId);
    }

    function test_cancelLoan() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(lender);
        ploan.cancelLoan(loanId);

        vm.prank(borrower);
        Ploan.PersonalLoan[] memory loans = ploan.getLoans();
        assertEq(loans.length, 1);
        Ploan.PersonalLoan memory canceledLoan = loans[0];

        assert(canceledLoan.canceled);
        assert(!canceledLoan.repayable);
    }

    function test_cancelLoan_notLender() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.expectRevert("Only the lender can cancel the loan");
        ploan.cancelLoan(loanId);
    }

    function test_cancelLoan_alreadyCanceled() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(lender);
        ploan.cancelLoan(loanId);

        // the lack of an error indicates the idempotency of the operation
        vm.prank(lender);
        ploan.cancelLoan(loanId);
    }

    function test_payLoan_zeroAmount() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanId);

        // The loaned amount should be transferred to the lender
        assertEq(token.balanceOf(lender), 20);
        assertEq(token.balanceOf(borrower), 100);

        vm.expectRevert("Amount must be greater than 0");
        vm.prank(borrower);
        ploan.payLoan(loanId, 0);
    }

    function test_payLoan_canceled() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanId);

        vm.prank(lender);
        ploan.cancelLoan(loanId);

        vm.prank(borrower);
        vm.expectRevert("Loan is not repayable");
        ploan.payLoan(loanId, 100);
    }

    function test_payLoan_completed() public {
        // Give the lender a starting non-zero balance so that they can
        // try to pay after the loan is completed
        token.transfer(lender, 20);

        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanId);

        vm.prank(borrower);
        token.approve(address(ploan), 100);

        vm.prank(borrower);
        ploan.payLoan(loanId, 100);

        vm.prank(borrower);
        vm.expectRevert("Loan is not repayable");
        ploan.payLoan(loanId, 20);
    }

    function test_payLoan_overpay() public {
        // Give the lender a starting non-zero balance so that they can
        // try to pay more than what's owed on the loan
        token.transfer(lender, 20);

        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanId);

        vm.prank(borrower);
        vm.expectRevert("Total amount repaid must be less than or equal to total amount loaned");
        ploan.payLoan(loanId, 120);
    }

    function test_cancelPendingLoan() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        // Propose another loan that should not be cleared out by the cancel task
        vm.prank(lender);
        uint256 retainableLoanID = ploan.proposeLoan(borrower, address(token), 5);

        vm.prank(borrower);
        ploan.cancelPendingLoan(loanId);

        // The loan should not be in the mappings for either the borrow or lender
        vm.prank(borrower);
        Ploan.PersonalLoan[] memory borrowerLoans = ploan.getLoans();
        assertEq(borrowerLoans[0].loanId, retainableLoanID);
        assertEq(borrowerLoans.length, 1);

        vm.prank(lender);
        Ploan.PersonalLoan[] memory lenderLoans = ploan.getLoans();
        assertEq(lenderLoans.length, 1);
        assertEq(lenderLoans[0].loanId, retainableLoanID);
    }

    function test_cancelPendingLoan_inProgress() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.prank(lender);
        ploan.executeLoan(loanId);

        vm.prank(borrower);
        vm.expectRevert("Loan has already been started and cannot be canceled");
        ploan.cancelPendingLoan(loanId);
    }

    function test_cancelPendingLoan_notLenderOrBorrower() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(address(3));
        vm.expectRevert("Only the lender or borrower can cancel a pending loan");
        ploan.cancelPendingLoan(loanId);
    }
}
