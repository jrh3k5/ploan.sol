// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title A contract for managing personal loans
/// @author 0x9134fc7112b478e97eE6F0E6A7bf81EcAfef19ED
contract Ploan is Initializable {
    uint256 public loanIdBucket;
    mapping(uint256 loanId => PersonalLoan loan) public loansByID;
    mapping(address allowlistOwner => address[] allowlist) public loanProposalAllowlist;
    mapping(address loanParticipant => uint256[] loanIds) public participatingLoans;
    bool initialized;

    function initialize() public initializer {
        loanIdBucket = 1;
    }

    // allowLoanProposal allows a user to be added to the loan proposal allowlist
    function allowLoanProposal(address toAllow) public {
        loanProposalAllowlist[msg.sender].push(toAllow);
    }

    // proposeLoan creates a loan and returns the loan ID
    function proposeLoan(address borrower, address loanedAsset, uint256 totalAmount) public returns (uint256) {
        require(totalAmount > 0, "Total amount must be greater than 0");
        require(borrower != msg.sender, "Borrower cannot be the lender");
        require(loanedAsset != address(0), "Loaned asset cannot be zero address");

        bool isAllowlisted = false;
        for (uint256 i = 0; i < loanProposalAllowlist[borrower].length; i++) {
            if (loanProposalAllowlist[borrower][i] == msg.sender) {
                isAllowlisted = true;

                break;
            }
        }

        require(isAllowlisted, "Lender is not allowed to propose a loan");

        uint256 loanId = loanIdBucket;
        loanIdBucket++;

        uint256 lenderBalance = ERC20(loanedAsset).balanceOf(msg.sender);
        require(lenderBalance >= totalAmount, "Lender does not have enough balance");

        PersonalLoan memory newLoan;
        newLoan.loanId = loanId;
        newLoan.totalAmountLoaned = totalAmount;
        newLoan.totalAmountRepaid = 0;
        newLoan.borrower = borrower;
        newLoan.lender = msg.sender;
        newLoan.loanedAsset = loanedAsset;

        address[] memory loanParticipants = new address[](2);
        loanParticipants[0] = msg.sender;
        loanParticipants[1] = borrower;
        associateToLoan(loanId, loanParticipants);

        loansByID[loanId] = newLoan;

        return loanId;
    }

    // commitToLoan commits the borrower to the loan
    function commitToLoan(uint256 loanId) public {
        PersonalLoan memory loan = loansByID[loanId];
        require(loan.borrower == msg.sender, "Only the borrower can commit to the loan");

        if (loan.borrowerCommitted) {
            return;
        }

        loan.borrowerCommitted = true;

        loansByID[loanId] = loan;
    }

    // disallowLoanProposal removes an address from the loan proposal allowlist for the current user
    function disallowLoanProposal(address toDisallow) public {
        address[] memory allowlist = loanProposalAllowlist[msg.sender];
        if (allowlist.length == 0) {
            return;
        }

        for (uint256 i = 0; i < allowlist.length; i++) {
            if (allowlist[i] == toDisallow) {
                allowlist[i] = allowlist[allowlist.length - 1];
                delete allowlist[allowlist.length - 1];
            }
        }

        loanProposalAllowlist[msg.sender] = allowlist;
    }

    // executeLoan executes a loan, transferring the asset from the lender to the borrower
    function executeLoan(uint256 loanId) public {
        PersonalLoan memory loan = loansByID[loanId];
        require(loan.lender == msg.sender, "Only the lender can execute the loan");
        require(loan.borrowerCommitted, "Borrower has not committed to the loan");

        if (loan.started) {
            return;
        }

        loan.started = true;
        loan.repayable = true;

        ERC20(loan.loanedAsset).transferFrom(msg.sender, loan.borrower, loan.totalAmountLoaned);

        loansByID[loanId] = loan;
    }

    // cancelLoan cancels a loan
    function cancelLoan(uint256 loanId) public {
        PersonalLoan memory loan = loansByID[loanId];
        require(loan.lender == msg.sender, "Only the lender can cancel the loan");

        if (loan.canceled) {
            return;
        }

        loan.canceled = true;
        loan.repayable = false;

        loansByID[loanId] = loan;
    }

    // payLoan executes a repayment of a loan.
    function payLoan(uint256 loanId, uint256 amount) public {
        PersonalLoan memory loan = loansByID[loanId];
        require(loan.repayable, "Loan is not repayable");
        require(amount > 0, "Amount must be greater than 0");
        require(
            loan.totalAmountRepaid + amount <= loan.totalAmountLoaned,
            "Total amount repaid must be less than or equal to total amount loaned"
        );

        ERC20(loan.loanedAsset).transferFrom(msg.sender, loan.lender, amount);

        loan.totalAmountRepaid += amount;

        if (loan.totalAmountRepaid == loan.totalAmountLoaned) {
            loan.completed = true;
            loan.repayable = false;
        }

        loansByID[loanId] = loan;
    }

    // cancelPendingLoan cancels a loan
    function cancelPendingLoan(uint256 loanId) public {
        PersonalLoan memory loan = loansByID[loanId];
        if (loan.loanId == 0) {
            return;
        }

        require(
            loan.lender == msg.sender || loan.borrower == msg.sender,
            "Only the lender or borrower can cancel a pending loan"
        );

        if (loan.started) {
            revert("Loan has already been started and cannot be canceled");
        }

        address[] memory participants = new address[](2);
        participants[0] = loan.lender;
        participants[1] = loan.borrower;
        disassociateFromLoan(loanId, participants);

        delete loansByID[loanId];
    }

    // getLoans gets all of the loans for the current user
    function getLoans() external view returns (PersonalLoan[] memory) {
        uint256[] memory mappedLoanIds = participatingLoans[msg.sender];
        if (mappedLoanIds.length == 0) {
            PersonalLoan[] memory noLoans = new PersonalLoan[](0);
            return noLoans;
        }

        uint256 nonZeroCount = 0;
        for (uint256 i = 0; i < mappedLoanIds.length; i++) {
            if (mappedLoanIds[i] != 0) {
                nonZeroCount++;
            }
        }

        if (nonZeroCount == 0) {
            PersonalLoan[] memory noLoans = new PersonalLoan[](0);
            return noLoans;
        }

        PersonalLoan[] memory userLoans = new PersonalLoan[](nonZeroCount);
        uint256 userLoansIndex = 0;
        for (uint256 i = 0; i < mappedLoanIds.length; i++) {
            if (mappedLoanIds[i] == 0) {
                // skip loans that have been deleted
                continue;
            }
            userLoans[userLoansIndex] = loansByID[mappedLoanIds[i]];
            userLoansIndex++;
        }

        return userLoans;
    }

    // associateToLoan associates the given participants to a loan
    function associateToLoan(uint256 loanId, address[] memory participants) private {
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            participatingLoans[participant].push(loanId);
        }
    }

    // disassociateFromLoan disassociates the given participants from a loan
    function disassociateFromLoan(uint256 loanId, address[] memory participants) private {
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint256[] memory loans = participatingLoans[participant];
            for (uint256 j = 0; j < loans.length; j++) {
                if (loans[j] == loanId) {
                    delete loans[j];
                }
            }

            participatingLoans[participant] = loans;
        }
    }

    struct PersonalLoan {
        uint256 loanId; // the ID of the loan
        uint256 totalAmountLoaned; // the total amount of the asset that was loaned
        uint256 totalAmountRepaid; // the total amount of the asset that has been repaid
        address borrower; // the address to whom the amount is loaned
        address lender; // the address that loaned the asset
        address loanedAsset; // the address of the loaned asset
        bool borrowerCommitted;
        bool canceled;
        bool completed;
        bool started;
        bool repayable;
    }
}
