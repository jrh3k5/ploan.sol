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
    LoanProposalAllowlistModified,
    LoanProposed,
    PendingLoanCanceled,
    AlreadyPaidExceedsLoaned
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

        PersonalLoan[] memory loans = ploan.getLoans(lender);
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

    function test_importLoan_revertsIfAlreadyPaidExceedsLoaned() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(AlreadyPaidExceedsLoaned.selector, 2000, 1000));
        ploan.importLoan(borrower, address(token), 1000, 2000);
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

        PersonalLoan[] memory loans = ploan.getLoans(lender);
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

    function test_allowLoanProposal() public {
        vm.prank(borrower);

        vm.expectEmit();
        emit LoanProposalAllowlistModified(borrower, lender, true);

        ploan.allowLoanProposal(lender);

        address[] memory allowlisted = ploan.getLoanProposalAllowlist(borrower);
        assertEq(allowlisted.length, 1);
        assertEq(allowlisted[0], lender);
    }

    function test_allowLoanProposal_alreadyAllowlist() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        address[] memory allowlisted = ploan.getLoanProposalAllowlist(borrower);
        assertEq(allowlisted.length, 1);
        assertEq(allowlisted[0], lender);

        // Do it again - the allowlist should remain unchanged
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        allowlisted = ploan.getLoanProposalAllowlist(borrower);
        assertEq(allowlisted.length, 1);
        assertEq(allowlisted[0], lender);
    }

    function test_allowLoanProposal_resuseSlots() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(address(1));

        vm.prank(borrower);
        ploan.allowLoanProposal(address(2));

        vm.prank(borrower);
        ploan.allowLoanProposal(address(3));

        // Sanity check
        address[] memory allowlisted = ploan.getLoanProposalAllowlist(borrower);
        assertEq(allowlisted.length, 3);
        assertEq(allowlisted[0], address(1));
        assertEq(allowlisted[1], address(2));
        assertEq(allowlisted[2], address(3));

        // Now, disallow address(2) and allow address(4) - it should reuse the slot
        vm.prank(borrower);
        ploan.disallowLoanProposal(address(2));

        vm.prank(borrower);
        ploan.allowLoanProposal(address(4));

        allowlisted = ploan.getLoanProposalAllowlist(borrower);
        assertEq(allowlisted.length, 3);
        assertEq(allowlisted[0], address(1));
        assertEq(allowlisted[1], address(3));
        assertEq(allowlisted[2], address(4));
    }

    /// @dev make sure that this won't suffer from out-of-bounds access
    function test_allowLoanProposal_resuseFinalSlot() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(address(1));

        // Sanity check
        address[] memory allowlisted = ploan.getLoanProposalAllowlist(borrower);
        assertEq(allowlisted.length, 1);
        assertEq(allowlisted[0], address(1));

        // Now, disallow address(2) and allow address(4) - it should reuse the slot
        vm.prank(borrower);
        ploan.disallowLoanProposal(address(1));

        vm.prank(borrower);
        ploan.allowLoanProposal(address(4));

        allowlisted = ploan.getLoanProposalAllowlist(borrower);
        assertEq(allowlisted.length, 1);
        assertEq(allowlisted[0], address(4));
    }

    function test_getLoanProposalAllowlist() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        address[] memory allowlisted = ploan.getLoanProposalAllowlist(borrower);
        assertEq(allowlisted.length, 1);
        assertEq(allowlisted[0], lender);

        // Verify that, if a user does not have an allowlist set up, the list is empty
        address[] memory lenderAllowlisted = ploan.getLoanProposalAllowlist(lender);
        assertEq(lenderAllowlisted.length, 0);
    }

    function test_disallowLoanProposal() public {
        vm.prank(borrower);
        ploan.allowLoanProposal(lender);

        vm.prank(lender);
        // a lack of a failure indicates success
        ploan.proposeLoan(borrower, address(token), 100);

        vm.expectEmit();
        emit LoanProposalAllowlistModified(borrower, lender, false);

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

        PersonalLoan[] memory loans = ploan.getLoans(borrower);
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
        emit PendingLoanCanceled(loanId);

        vm.expectEmit();
        emit LoanDisassociated(loanId, lender);

        vm.expectEmit();
        emit LoanDisassociated(loanId, borrower);

        vm.prank(borrower);
        ploan.cancelPendingLoan(loanId);

        // The loan should not be in the mappings for either the borrow or lender
        PersonalLoan[] memory borrowerLoans = ploan.getLoans(borrower);
        assertEq(borrowerLoans[0].loanId, retainableLoanID);
        assertEq(borrowerLoans.length, 1);

        PersonalLoan[] memory lenderLoans = ploan.getLoans(lender);
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

    function test_deleteLoan_completed() public {
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

        // The loan should still exist and be mapped for the lender and borrower after completion
        PersonalLoan[] memory borrowerLoans = ploan.getLoans(borrower);
        assertEq(borrowerLoans[0].loanId, loanId);
        assertEq(borrowerLoans.length, 1);
        assertTrue(borrowerLoans[0].completed);

        PersonalLoan[] memory lenderLoans = ploan.getLoans(lender);
        assertEq(lenderLoans[0].loanId, loanId);
        assertEq(lenderLoans.length, 1);
        assertTrue(lenderLoans[0].completed);

        vm.prank(borrower);
        ploan.deleteLoan(loanId);

        // The loan should not be in the mappings for either the borrow or lender
        borrowerLoans = ploan.getLoans(borrower);
        assertEq(borrowerLoans.length, 0);

        lenderLoans = ploan.getLoans(lender);
        assertEq(lenderLoans.length, 0);
    }

    function test_deleteLoan_canceled() public {
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

        // The loan should still exist and be mapped for the lender and borrower after completion
        PersonalLoan[] memory borrowerLoans = ploan.getLoans(borrower);
        assertEq(borrowerLoans[0].loanId, loanId);
        assertEq(borrowerLoans.length, 1);
        assertTrue(borrowerLoans[0].canceled);

        PersonalLoan[] memory lenderLoans = ploan.getLoans(lender);
        assertEq(lenderLoans[0].loanId, loanId);
        assertEq(lenderLoans.length, 1);
        assertTrue(lenderLoans[0].canceled);

        vm.prank(borrower);
        ploan.deleteLoan(loanId);

        // The loan should not be in the mappings for either the borrow or lender
        borrowerLoans = ploan.getLoans(borrower);
        assertEq(borrowerLoans.length, 0);

        lenderLoans = ploan.getLoans(lender);
        assertEq(lenderLoans.length, 0);
    }

    /// @dev makes sure that a lender can delete a loan - the other happy
    /// path tests just exercise that path as the borrower
    function test_deleteLoan_asLender() public {
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

        vm.prank(lender);
        ploan.deleteLoan(loanId);

        // The loan should not be in the mappings for either the borrow or lender
        PersonalLoan[] memory borrowerLoans = ploan.getLoans(borrower);
        assertEq(borrowerLoans.length, 0);

        PersonalLoan[] memory lenderLoans = ploan.getLoans(lender);
        assertEq(lenderLoans.length, 0);
    }

    function test_deleteLoan_notLenderOrBorrower() public {
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

        vm.prank(address(4));
        vm.expectRevert(LoanAuthorizationFailure.selector);
        ploan.deleteLoan(loanId);
    }

    function test_deleteLoan_notCanceledOrCompleted() public {
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
        vm.expectRevert(InvalidLoanState.selector);
        ploan.deleteLoan(loanId);
    }

    function test_deleteLoan_notFound() public {
        vm.prank(borrower);
        vm.expectRevert(LoanAuthorizationFailure.selector);
        ploan.deleteLoan(0);
    }
}
