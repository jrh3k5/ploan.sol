/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @dev raised when an invalid amount is specified for a loan
error InvalidLoanAmount();

/// @dev raised when the assert in a loan is invalid
error InvalidLoanAsset();

/// @dev raised when the recipient of a loan is invalid
error InvalidLoanRecipient();

/// @dev raised when the loan state is not in a valid state to perform a particular action
error InvalidLoanState();

/// @dev raised if a payment amount is not a valid amount
error InvalidPaymentAmount();

/// @dev raised when a lender is not allowlisted to propose a loan to a user
/// @param lender the address of the lender
error LenderNotAllowlisted(address lender);

/// @dev raised when there is an authorization failure accessing a loan
error LoanAuthorizationFailure();

/// @title A contract for managing personal loans
/// @author Joshua Hyde
/// @custom:security-contact 0x9134fc7112b478e97eE6F0E6A7bf81EcAfef19ED
contract Ploan is Initializable {
    /// @notice the ID of the next loan
    uint256 private loanIdBucket;
    /// @notice all of the loans
    mapping(uint256 loanId => PersonalLoan loan) private loansByID;
    /// @notice all of the loan proposal allowlists
    mapping(address allowlistOwner => address[] allowlist) private loanProposalAllowlist;
    /// @notice all of the loan participants
    mapping(address loanParticipant => uint256[] loanIds) private participatingLoans;

    /// constructor; disables initializer
    constructor() {
        _disableInitializers();
    }

    /// @notice initialize the contract
    function initialize() public initializer {
        loanIdBucket = 1;
    }

    /// @notice allows a user to be added to the loan proposal allowlist
    /// @param toAllow the address to be added
    function allowLoanProposal(address toAllow) public {
        loanProposalAllowlist[msg.sender].push(toAllow);
    }

    /// @notice creates a loan and returns the loan ID
    /// @param borrower the address of the borrower who is going to borrow the asset
    /// @param loanedAsset the address of the loaned asset being loaned
    /// @param totalAmount the total amount of the loan (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @return the ID of the proposed loan
    function proposeLoan(address borrower, address loanedAsset, uint256 totalAmount) public returns (uint256) {
        if (totalAmount == 0) {
            revert InvalidLoanAmount();
        }

        if (borrower == msg.sender) {
            revert InvalidLoanRecipient();
        }

        if (loanedAsset == address(0)) {
            revert InvalidLoanAsset();
        }

        bool isAllowlisted;
        uint256 loanCount = loanProposalAllowlist[borrower].length;
        for (uint256 i; i < loanCount; i++) {
            if (loanProposalAllowlist[borrower][i] == msg.sender) {
                isAllowlisted = true;

                break;
            }
        }

        if (!isAllowlisted) {
            revert LenderNotAllowlisted({lender: msg.sender});
        }

        uint256 loanId = loanIdBucket;
        loanIdBucket++;

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

    /// @notice commits the sender (who is the borrower) to the loan, signaling that they wish to proceed with the loan
    /// @param loanId the ID of the loan
    function commitToLoan(uint256 loanId) public {
        PersonalLoan memory loan = loansByID[loanId];
        if (loan.borrower != msg.sender) {
            revert LoanAuthorizationFailure();
        }

        if (loan.borrowerCommitted) {
            return;
        }

        loan.borrowerCommitted = true;

        loansByID[loanId] = loan;
    }

    /// @notice removes an address from the loan proposal allowlist for the current user, which disallows that address from proposing loans to the sender to borrow
    /// @param toDisallow the address to be removed
    function disallowLoanProposal(address toDisallow) public {
        address[] memory allowlist = loanProposalAllowlist[msg.sender];
        uint256 allowlistLength = allowlist.length;
        if (allowlistLength == 0) {
            return;
        }

        for (uint256 i; i < allowlistLength; i++) {
            if (allowlist[i] == toDisallow) {
                allowlist[i] = allowlist[allowlistLength - 1];
                delete allowlist[allowlistLength - 1];
            }
        }

        loanProposalAllowlist[msg.sender] = allowlist;
    }

    /// @notice executes a loan, transferring the asset from the lender to the borrower
    /// @param loanId the ID of the loan
    function executeLoan(uint256 loanId) public {
        PersonalLoan memory loan = loansByID[loanId];
        if (loan.lender != msg.sender) {
            revert LoanAuthorizationFailure();
        }

        if (!loan.borrowerCommitted) {
            revert InvalidLoanState();
        }

        if (loan.started) {
            return;
        }

        loan.started = true;
        loan.repayable = true;

        ERC20(loan.loanedAsset).transferFrom(msg.sender, loan.borrower, loan.totalAmountLoaned);

        loansByID[loanId] = loan;
    }

    /// @notice cancels a loan
    /// @param loanId the ID of the loan
    function cancelLoan(uint256 loanId) public {
        PersonalLoan memory loan = loansByID[loanId];
        if (loan.lender != msg.sender) {
            revert LoanAuthorizationFailure();
        }

        if (loan.canceled) {
            return;
        }

        loan.canceled = true;
        loan.repayable = false;

        loansByID[loanId] = loan;
    }

    /// @notice executes a repayment of a loan
    /// @param loanId the ID of the loan
    /// @param amount the amount to be repaid (expressed in the base amount of the asset - e.g., wei of ETH)
    function payLoan(uint256 loanId, uint256 amount) public {
        PersonalLoan memory loan = loansByID[loanId];
        if (!loan.repayable) {
            revert InvalidLoanState();
        }

        if (amount == 0 || loan.totalAmountRepaid + amount > loan.totalAmountLoaned) {
            revert InvalidPaymentAmount();
        }

        ERC20(loan.loanedAsset).transferFrom(msg.sender, loan.lender, amount);

        loan.totalAmountRepaid += amount;

        if (loan.totalAmountRepaid == loan.totalAmountLoaned) {
            loan.completed = true;
            loan.repayable = false;
        }

        loansByID[loanId] = loan;
    }

    /// @notice cancels a loan that has not yet been executed
    /// @param loanId the ID of the loan
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

    /// @notice gets all of the loans for the sender
    /// @return all of the loans for the sender
    function getLoans() external view returns (PersonalLoan[] memory) {
        uint256[] memory mappedLoanIds = participatingLoans[msg.sender];
        uint256 loanCount = mappedLoanIds.length;
        if (loanCount == 0) {
            PersonalLoan[] memory noLoans = new PersonalLoan[](0);
            return noLoans;
        }

        uint256 nonZeroCount;
        for (uint256 i; i < loanCount; i++) {
            if (mappedLoanIds[i] != 0) {
                nonZeroCount++;
            }
        }

        if (nonZeroCount == 0) {
            PersonalLoan[] memory noLoans = new PersonalLoan[](0);
            return noLoans;
        }

        PersonalLoan[] memory userLoans = new PersonalLoan[](nonZeroCount);
        uint256 userLoansIndex;
        for (uint256 i; i < loanCount; i++) {
            if (mappedLoanIds[i] == 0) {
                /// skip loans that have been deleted
                continue;
            }
            userLoans[userLoansIndex] = loansByID[mappedLoanIds[i]];
            userLoansIndex++;
        }

        return userLoans;
    }

    /// @notice associates the given participants to a loan, faciliating indexed lookups in the future
    /// @param loanId the ID of the loan
    /// @param participants the participants to be associated
    function associateToLoan(uint256 loanId, address[] memory participants) private {
        uint256 participantsCount = participants.length;
        for (uint256 i; i < participantsCount; i++) {
            address participant = participants[i];
            participatingLoans[participant].push(loanId);
        }
    }

    /// @notice disassociates the given participants from a loan
    /// @param loanId the ID of the loan
    /// @param participants the participants to be disassociated
    function disassociateFromLoan(uint256 loanId, address[] memory participants) private {
        uint256 participantsCount = participants.length;
        for (uint256 i; i < participantsCount; i++) {
            address participant = participants[i];
            uint256[] memory loans = participatingLoans[participant];
            uint256 participantLoanCount = loans.length;
            for (uint256 j; j < participantLoanCount; j++) {
                if (loans[j] == loanId) {
                    delete loans[j];
                }
            }

            participatingLoans[participant] = loans;
        }
    }

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
    }
    /// true if the loan can be repaid
}
