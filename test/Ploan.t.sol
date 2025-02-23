// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    Ploan,
    InvalidLoanAmount,
    InvalidLoanAsset,
    InvalidLoanRecipient,
    InvalidLoanState,
    InvalidPaymentAmount,
    LenderDisallowed,
    LoanAssociated,
    LoanCanceled,
    LoanCompleted,
    LoanDisassociated,
    LoanExecuted,
    LoanImported,
    LenderNotAllowlisted,
    LoanAuthorizationFailure,
    LoanCommitted,
    LoanPaymentMade,
    LoanProposed,
    PendingLoanCanceled
} from "../src/Ploan.sol";
import {PersonalLoan} from "../src/PersonalLoan.sol";
import {PloanTestToken} from "./mocks/PloanTestToken.sol";
import {UnsafeUpgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

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

    function test_proposeLoan_defaultLifecycle() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        address assetAddress = address(token);
        uint256 loanAmount = 100;

        // Cheat on the loan ID since this test assumes the loan contract is previously unused
        vm.expectEmit();
        emit LoanAssociated(1, lender);

        vm.expectEmit();
        emit LoanAssociated(1, borrower);

        vm.expectEmit();
        emit LoanProposed(lender, borrower, assetAddress, loanAmount, 1);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, assetAddress, loanAmount);

        vm.expectEmit();
        emit LoanCommitted(loanId);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        vm.prank(lender);
        token.approve(address(ploan), 100);

        vm.expectEmit();
        emit LoanExecuted(loanId);

        vm.prank(lender);
        ploan.executeLoan(loanId);

        // The loaned amount should be transferred to the lender
        assertEq(token.balanceOf(lender), 20);
        assertEq(token.balanceOf(borrower), 100);

        vm.prank(borrower);
        token.approve(address(ploan), 50);

        vm.expectEmit();
        emit LoanPaymentMade(loanId, 50);

        vm.prank(borrower);
        ploan.payLoan(loanId, 50);

        assertEq(token.balanceOf(lender), 70);
        assertEq(token.balanceOf(borrower), 50);

        vm.prank(borrower);
        token.approve(address(ploan), 50);

        vm.expectEmit();
        emit LoanPaymentMade(loanId, 50);

        vm.expectEmit();
        emit LoanCompleted(loanId);

        vm.prank(borrower);
        ploan.payLoan(loanId, 50);

        assertEq(token.balanceOf(lender), 120);
        assertEq(token.balanceOf(borrower), 0);

        vm.prank(lender);
        PersonalLoan[] memory loans = ploan.getLoans();
        assertEq(loans.length, 1);
        PersonalLoan memory completedLoan = loans[0];
        assert(completedLoan.completed);
    }

    function test_proposeLoan_zeroAmount() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.expectRevert(InvalidLoanAmount.selector);
        ploan.proposeLoan(borrower, address(token), 0);
    }

    function test_proposeLoan_noSelfLoans() public {
        vm.expectRevert(InvalidLoanRecipient.selector);
        vm.prank(lender);
        ploan.proposeLoan(lender, address(token), 100);
    }

    function test_proposeLoan_zeroAssetAddress() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.expectRevert(InvalidLoanAsset.selector);
        ploan.proposeLoan(borrower, address(0), 100);
    }

    function test_proposeLoan_notAllowed() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(LenderNotAllowlisted.selector, lender));
        ploan.proposeLoan(borrower, address(token), 100);
    }

    function test_importLoan_defaultLifecycle() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        address assetAddress = address(token);
        uint256 loanAmount = 100;

        token.transfer(borrower, 80);

        // Cheat on the loan ID since this test assumes the loan contract is previously unused
        vm.expectEmit();
        emit LoanAssociated(1, lender);

        vm.expectEmit();
        emit LoanAssociated(1, borrower);

        vm.expectEmit();
        emit LoanImported(lender, borrower, assetAddress, loanAmount, 35, 1);

        vm.prank(lender);
        uint256 loanId = ploan.importLoan(borrower, assetAddress, loanAmount, 35);

        vm.expectEmit();
        emit LoanCommitted(loanId);

        vm.prank(borrower);
        ploan.commitToLoan(loanId);

        // no token approvals needed since no asset will be transferred

        vm.expectEmit();
        emit LoanExecuted(loanId);

        vm.prank(lender);
        ploan.executeLoan(loanId);

        // No amount of tokens should have been transferred
        assertEq(token.balanceOf(lender), 120);
        assertEq(token.balanceOf(borrower), 80);

        vm.prank(borrower);
        token.approve(address(ploan), 50);

        vm.expectEmit();
        emit LoanPaymentMade(loanId, 50);

        vm.prank(borrower);
        ploan.payLoan(loanId, 50);

        assertEq(token.balanceOf(lender), 170);
        assertEq(token.balanceOf(borrower), 30);

        vm.prank(borrower);
        token.approve(address(ploan), 15);

        vm.expectEmit();
        emit LoanPaymentMade(loanId, 15);

        vm.expectEmit();
        emit LoanCompleted(loanId);

        vm.prank(borrower);
        ploan.payLoan(loanId, 15);

        assertEq(token.balanceOf(lender), 185);
        assertEq(token.balanceOf(borrower), 15);

        vm.prank(lender);
        PersonalLoan[] memory loans = ploan.getLoans();
        assertEq(loans.length, 1);
        PersonalLoan memory completedLoan = loans[0];
        assert(completedLoan.completed);
    }

    function test_importLoan_zeroAmount() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.expectRevert(InvalidLoanAmount.selector);
        ploan.importLoan(borrower, address(token), 0, 0);
    }

    function test_importLoan_noSelfLoans() public {
        vm.expectRevert(InvalidLoanRecipient.selector);
        vm.prank(lender);
        ploan.importLoan(lender, address(token), 100, 15);
    }

    function test_importLoan_zeroAssetAddress() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.expectRevert(InvalidLoanAsset.selector);
        ploan.importLoan(borrower, address(0), 100, 15);
    }

    function test_importLoan_notAllowed() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(LenderNotAllowlisted.selector, lender));
        ploan.importLoan(borrower, address(token), 100, 15);
    }

    function test_disallowLoanProposal() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        // a lack of a failure indicates success
        ploan.proposeLoan(borrower, address(token), 100);

        vm.expectEmit();
        emit LenderDisallowed(lender, borrower);

        vm.prank(borrower);
        ploan.disallowLoanProposal(lender);

        // Now it should fail
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(LenderNotAllowlisted.selector, lender));
        ploan.proposeLoan(borrower, address(token), 100);
    }

    function test_commitToLoan_notBorrower() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.expectRevert(LoanAuthorizationFailure.selector);
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

        vm.expectRevert(LoanAuthorizationFailure.selector);
        ploan.executeLoan(loanId);
    }

    function test_executeLoan_borrowerNotCommitted() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(lender);
        vm.expectRevert(InvalidLoanState.selector);
        ploan.executeLoan(loanId);
    }

    function test_cancelLoan() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.expectEmit();
        emit LoanCanceled(loanId);

        vm.prank(lender);
        ploan.cancelLoan(loanId);

        vm.prank(borrower);
        PersonalLoan[] memory loans = ploan.getLoans();
        assertEq(loans.length, 1);
        PersonalLoan memory canceledLoan = loans[0];

        assert(canceledLoan.canceled);
        assert(!canceledLoan.repayable);
    }

    function test_cancelLoan_notLender() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.expectRevert(LoanAuthorizationFailure.selector);
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

        vm.expectRevert(InvalidPaymentAmount.selector);
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
        vm.expectRevert(InvalidLoanState.selector);
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
        vm.expectRevert(InvalidLoanState.selector);
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
        vm.expectRevert(InvalidPaymentAmount.selector);
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

        vm.expectEmit();
        emit LoanDisassociated(loanId, lender);

        vm.expectEmit();
        emit LoanDisassociated(loanId, borrower);

        vm.expectEmit();
        emit PendingLoanCanceled(loanId);

        vm.prank(borrower);
        ploan.cancelPendingLoan(loanId);

        // The loan should not be in the mappings for either the borrow or lender
        vm.prank(borrower);
        PersonalLoan[] memory borrowerLoans = ploan.getLoans();
        assertEq(borrowerLoans[0].loanId, retainableLoanID);
        assertEq(borrowerLoans.length, 1);

        vm.prank(lender);
        PersonalLoan[] memory lenderLoans = ploan.getLoans();
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
        vm.expectRevert(InvalidLoanState.selector);
        ploan.cancelPendingLoan(loanId);
    }

    function test_cancelPendingLoan_notLenderOrBorrower() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        uint256 loanId = ploan.proposeLoan(borrower, address(token), 100);

        vm.prank(address(3));
        vm.expectRevert(LoanAuthorizationFailure.selector);
        ploan.cancelPendingLoan(loanId);
    }
}
