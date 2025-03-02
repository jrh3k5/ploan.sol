/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {PersonalLoan} from "./PersonalLoan.sol";

/// events

/// @dev emitted every time a user is associated to a loan
event LoanAssociated(uint256 indexed loanId, address indexed user);

/// @dev emitted when someone is added to or removed from a loan proposal allowlist.
/// @param allowlistOwner the address of the allowlist owner
/// @param allowlistedAddress the address of the allowlisted address
/// @param allowlisted whether the address is allowlisted; true if it is, false if it is not (i.e., it has been removed from the allowlist)
event LoanProposalAllowlistModified(
    address indexed allowlistOwner, address indexed allowlistedAddress, bool indexed allowlisted
);

/// @dev emitted when a loan is canceled
event LoanCanceled(uint256 indexed loanId);

/// @dev emitted when a borrower commits to a loan
event LoanCommitted(uint256 indexed loanId);

/// @dev emitted when a loan is completely repaid
event LoanCompleted(uint256 indexed loanId);

/// @dev emitted every time a user is disassociated from a loan
event LoanDisassociated(uint256 indexed loanId, address indexed user);

/// @dev emitted when a loan is executed by the lender
event LoanExecuted(uint256 indexed loanId);

/// @dev emitted when a loan is imported into the app
event LoanImported(
    address indexed lender,
    address indexed borrower,
    address indexed asset,
    uint256 amountLoaned,
    uint256 amountAlreadyPaid,
    uint256 loanId
);

/// @dev emitted when a loan payment is made.
event LoanPaymentMade(uint256 indexed loanId, uint256 amount);

/// @dev emitted when a loan is proposed
event LoanProposed(
    address indexed lender, address indexed borrower, address indexed asset, uint256 amount, uint256 loanId
);

/// @dev emitted when a pending loan is canceled
event PendingLoanCanceled(uint256 indexed loanId);

/// errors

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

/// @dev raised when a transfer fails to execute
error TransferFailed();

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

    /// @notice initialize the contract
    function initialize() external initializer {
        loanIdBucket = 1;
    }

    /// @notice allows a user to be added to the loan proposal allowlist
    /// @param toAllow the address to be added
    function allowLoanProposal(address toAllow) external {
        address[] storage allowlist = loanProposalAllowlist[msg.sender];
        uint256 allowlistLength = allowlist.length;
        for (uint256 i; i < allowlistLength; ++i) {
            if (allowlist[i] == toAllow) {
                return;
            }
        }

        emit LoanProposalAllowlistModified(msg.sender, toAllow, true);

        loanProposalAllowlist[msg.sender].push(toAllow);
    }

    /// @notice imports a pre-existing loan that, upon execution, will not transfer any assets, but merely create a record of the loan to be tracked within this app
    /// @param borrower the address of the borrower who is going to borrow the asset
    /// @param loanedAsset the address of the loaned asset being loaned
    /// @param amountLoaned the total amount of the loan (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @param amountAlreadyPaid the amount of the loan that has already been paid (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @return the ID of the proposed loan
    function importLoan(address borrower, address loanedAsset, uint256 amountLoaned, uint256 amountAlreadyPaid)
        external
        returns (uint256)
    {
        address lender = msg.sender;

        uint256 loanId = addProposedLoan(lender, borrower, loanedAsset, amountLoaned, amountAlreadyPaid, true);

        emit LoanImported(lender, borrower, loanedAsset, amountLoaned, amountAlreadyPaid, loanId);

        return loanId;
    }

    /// @notice creates a loan and returns the loan ID
    /// @param borrower the address of the borrower who is going to borrow the asset
    /// @param loanedAsset the address of the loaned asset being loaned
    /// @param amountLoaned the total amount of the loan (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @return the ID of the proposed loan
    function proposeLoan(address borrower, address loanedAsset, uint256 amountLoaned) external returns (uint256) {
        address lender = msg.sender;

        uint256 loanId = addProposedLoan(lender, borrower, loanedAsset, amountLoaned, 0, false);

        emit LoanProposed(lender, borrower, loanedAsset, amountLoaned, loanId);

        return loanId;
    }

    /// @notice commits the sender (who is the borrower) to the loan, signaling that they wish to proceed with the loan
    /// @param loanId the ID of the loan
    function commitToLoan(uint256 loanId) external {
        PersonalLoan storage loan = loansByID[loanId];
        if (loan.borrower != msg.sender) {
            revert LoanAuthorizationFailure();
        }

        if (loan.borrowerCommitted) {
            return;
        }

        loan.borrowerCommitted = true;

        emit LoanCommitted(loanId);
    }

    /// @notice removes an address from the loan proposal allowlist for the current user, which disallows that address from proposing loans to the sender to borrow
    /// @param toDisallow the address to be removed
    function disallowLoanProposal(address toDisallow) external {
        address[] storage allowlist = loanProposalAllowlist[msg.sender];
        uint256 allowlistLength = allowlist.length;
        if (allowlistLength == 0) {
            return;
        }

        for (uint256 i; i < allowlistLength; ++i) {
            if (allowlist[i] == toDisallow) {
                allowlist[i] = allowlist[allowlistLength - 1];
                delete allowlist[allowlistLength - 1];

                emit LoanProposalAllowlistModified(msg.sender, toDisallow, false);
            }
        }
    }

    /// @notice executes a loan, transferring the asset from the lender to the borrower
    /// @param loanId the ID of the loan
    function executeLoan(uint256 loanId) external {
        PersonalLoan storage loan = loansByID[loanId];
        if (loan.lender != msg.sender) {
            revert LoanAuthorizationFailure();
        }

        if (!loan.borrowerCommitted) {
            revert InvalidLoanState();
        }

        if (loan.started) {
            return;
        }

        emit LoanExecuted(loanId);

        loan.started = true;
        loan.repayable = true;

        if (!loan.imported) {
            bool transferSucceeded =
                ERC20(loan.loanedAsset).transferFrom(msg.sender, loan.borrower, loan.totalAmountLoaned);
            if (!transferSucceeded) {
                revert TransferFailed();
            }
        }
    }

    /// @notice cancels a loan
    /// @param loanId the ID of the loan
    function cancelLoan(uint256 loanId) external {
        PersonalLoan storage loan = loansByID[loanId];
        if (loan.lender != msg.sender) {
            revert LoanAuthorizationFailure();
        }

        if (loan.canceled) {
            return;
        }

        loan.canceled = true;
        loan.repayable = false;

        emit LoanCanceled(loanId);
    }

    /// @notice executes a repayment of a loan
    /// @param loanId the ID of the loan
    /// @param amount the amount to be repaid (expressed in the base amount of the asset - e.g., wei of ETH)
    function payLoan(uint256 loanId, uint256 amount) external {
        PersonalLoan storage loan = loansByID[loanId];
        if (!loan.repayable) {
            revert InvalidLoanState();
        }

        if (amount == 0 || loan.totalAmountRepaid + amount > loan.totalAmountLoaned) {
            revert InvalidPaymentAmount();
        }

        bool loanWillComplete = loan.totalAmountRepaid + amount == loan.totalAmountLoaned;

        emit LoanPaymentMade(loanId, amount);

        if (loanWillComplete) {
            emit LoanCompleted(loanId);
        }

        loan.totalAmountRepaid += amount;

        if (loanWillComplete) {
            loan.completed = true;
            loan.repayable = false;
        }

        bool transferSucceeded = ERC20(loan.loanedAsset).transferFrom(msg.sender, loan.lender, amount);
        if (!transferSucceeded) {
            revert TransferFailed();
        }
    }

    /// @notice cancels a loan that has not yet been executed
    /// @param loanId the ID of the loan
    function cancelPendingLoan(uint256 loanId) external {
        PersonalLoan storage loan = loansByID[loanId];

        if (loan.lender != msg.sender && loan.borrower != msg.sender) {
            revert LoanAuthorizationFailure();
        }

        if (loan.started) {
            revert InvalidLoanState();
        }

        address[] memory participants = new address[](2);
        participants[0] = loan.lender;
        participants[1] = loan.borrower;
        disassociateFromLoan(loanId, participants);

        delete loansByID[loanId];

        emit PendingLoanCanceled(loanId);
    }

    /// @notice gets the allowlist for the sender of whom can propose loans to the sender.
    /// @return the allowlist
    function getLoanProposalAllowlist(address listOwner) external view returns (address[] memory) {
        return loanProposalAllowlist[listOwner];
    }

    /// @notice gets all of the loans for the given address - pending, active, whether they be lender or borrower
    /// @return all of the loans for the sender
    function getLoans(address participant) external view returns (PersonalLoan[] memory) {
        uint256[] memory mappedLoanIds = participatingLoans[participant];
        uint256 loanCount = mappedLoanIds.length;
        if (loanCount == 0) {
            PersonalLoan[] memory noLoans = new PersonalLoan[](0);
            return noLoans;
        }

        uint256 nonZeroCount;
        for (uint256 i; i < loanCount; ++i) {
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
        for (uint256 i; i < loanCount; ++i) {
            if (mappedLoanIds[i] == 0) {
                /// skip loans that have been deleted
                continue;
            }
            userLoans[userLoansIndex] = loansByID[mappedLoanIds[i]];
            userLoansIndex++;
        }

        return userLoans;
    }

    /// @dev adds a loan proposal from the sender to the given borrower.
    /// @param borrower the address of the borrower
    /// @param loanedAsset the address of the loaned asset
    /// @param totalAmount the total amount of the loan (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @param alreadyPaidAmount the amount of the loan already paid (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @return uint256 ID of the proposed loan
    function addProposedLoan(
        address lender,
        address borrower,
        address loanedAsset,
        uint256 totalAmount,
        uint256 alreadyPaidAmount,
        bool imported
    ) private returns (uint256) {
        if (totalAmount == 0) {
            revert InvalidLoanAmount();
        }

        if (borrower == lender) {
            revert InvalidLoanRecipient();
        }

        if (loanedAsset == address(0)) {
            revert InvalidLoanAsset();
        }

        bool isAllowlisted;
        uint256 loanCount = loanProposalAllowlist[borrower].length;
        for (uint256 i; i < loanCount; ++i) {
            if (loanProposalAllowlist[borrower][i] == lender) {
                isAllowlisted = true;

                break;
            }
        }

        if (!isAllowlisted) {
            revert LenderNotAllowlisted({lender: lender});
        }

        uint256 loanId = loanIdBucket;
        loanIdBucket++;

        PersonalLoan memory newLoan;
        newLoan.loanId = loanId;
        newLoan.totalAmountLoaned = totalAmount;
        newLoan.totalAmountRepaid = alreadyPaidAmount;
        newLoan.borrower = borrower;
        newLoan.lender = lender;
        newLoan.loanedAsset = loanedAsset;
        newLoan.imported = imported;

        address[] memory loanParticipants = new address[](2);
        loanParticipants[0] = lender;
        loanParticipants[1] = borrower;
        associateToLoan(loanId, loanParticipants);

        loansByID[loanId] = newLoan;

        return loanId;
    }

    /// @notice associates the given participants to a loan, faciliating indexed lookups in the future
    /// @param loanId the ID of the loan
    /// @param participants the participants to be associated
    function associateToLoan(uint256 loanId, address[] memory participants) private {
        uint256 participantsCount = participants.length;
        for (uint256 i; i < participantsCount; ++i) {
            address participant = participants[i];
            participatingLoans[participant].push(loanId);

            emit LoanAssociated(loanId, participant);
        }
    }

    /// @notice disassociates the given participants from a loan
    /// @param loanId the ID of the loan
    /// @param participants the participants to be disassociated
    function disassociateFromLoan(uint256 loanId, address[] memory participants) private {
        uint256 participantsCount = participants.length;
        for (uint256 i; i < participantsCount; ++i) {
            address participant = participants[i];
            uint256[] memory loans = participatingLoans[participant];
            uint256 participantLoanCount = loans.length;
            for (uint256 j; j < participantLoanCount; ++j) {
                if (loans[j] == loanId) {
                    delete loans[j];

                    emit LoanDisassociated(loanId, participant);
                }
            }

            participatingLoans[participant] = loans;
        }
    }
}
