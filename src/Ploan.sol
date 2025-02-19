// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title A contract for managing personal loans
/// @author 0x9134fc7112b478e97eE6F0E6A7bf81EcAfef19ED
contract Ploan {
    uint256 private loanIdBucket = 1;
    mapping(uint256 loanId => PersonalLoan loan) private loansByID;

    // createLoan creates a loan and returns the loan ID
    function createLoan(address borrower, address loanedAsset, uint256 totalAmount) public returns (uint256) {
        uint256 loanId = loanIdBucket;
        loanIdBucket++;

        require(totalAmount > 0, "Total amount must be greater than 0");
        require(borrower != msg.sender, "Borrower cannot be the lender");
        require(loanedAsset != address(0), "Loaned asset cannot be zero address");

        uint256 lenderBalance = ERC20(loanedAsset).balanceOf(msg.sender);
        require(lenderBalance >= totalAmount, "Lender does not have enough balance");

        PersonalLoan memory newLoan;
        newLoan.loanId = loanId;
        newLoan.totalAmountLoaned = totalAmount;
        newLoan.totalAmountRepaid = 0;
        newLoan.borrower = borrower;
        newLoan.lender = msg.sender;
        newLoan.loanedAsset = loanedAsset;

        loansByID[loanId] = newLoan;

        return loanId;
    }

    // commitToLoan commits the borrower to the loan
    function commitToLoan(uint256 loanID) public {
        PersonalLoan memory loan = loansByID[loanID];
        require(loan.borrower == msg.sender, "Only the borrower can commit to the loan");

        if (loan.borrowerCommitted) {
            return;
        }

        loan.borrowerCommitted = true;

        loansByID[loanID] = loan;
    }

    // executeLoan executes a loan, transferring the asset from the lender to the borrower
    function executeLoan(uint256 loanID) public {
        PersonalLoan memory loan = loansByID[loanID];
        require(loan.lender == msg.sender, "Only the lender can execute the loan");
        require(loan.borrowerCommitted, "Borrower has not committed to the loan");

        if (loan.started) {
            return;
        }

        loan.started = true;
        loan.repayable = true;

        ERC20(loan.loanedAsset).transferFrom(msg.sender, loan.borrower, loan.totalAmountLoaned);

        loansByID[loanID] = loan;
    }

    // cancelLoan cancels a loan
    function cancelLoan(uint256 loanID) public {
        PersonalLoan memory loan = loansByID[loanID];
        require(loan.lender == msg.sender, "Only the lender can cancel the loan");

        if (loan.canceled) {
            return;
        }

        loan.canceled = true;
        loan.repayable = false;

        loansByID[loanID] = loan;
    }

    function payLoan(uint256 loanID, uint256 amount) public {
        PersonalLoan memory loan = loansByID[loanID];
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

        loansByID[loanID] = loan;
    }

    function getLoan(uint256 loanID) external view returns (PersonalLoan memory) {
        return loansByID[loanID];
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
