/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @dev represents a loan
struct PersonalLoan {
    uint256 loanId;
    /// the ID of the loan
    uint256 totalAmountLoaned;
    /// the total amount of the asset that was loaned
    uint256 totalAmountRepaid;
    /// the total amount of the asset that has been repaid
    address borrower;
    /// the address to whom the amount is loaned
    address lender;
    /// the address that loaned the asset
    address loanedAsset;
    /// the address of the loaned asset
    bool borrowerCommitted;
    /// true if the borrower has committed the loan; the loan has not necessarily been executed yet
    bool canceled;
    /// true if the loan was canceled before it could be executed
    bool completed;
    /// true if the loan has been fully paid off
    bool started;
    /// true if the loan has been executed by the lender, transferring assets to the borrower
    bool repayable;
    /// true if the loan existed previously and was merely imported into the app
    bool imported;
}
