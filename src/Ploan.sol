/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {PersonalLoan} from "./PersonalLoan.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

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

/// @dev emitted when a loan is deleted
event LoanDeleted(uint256 indexed loanId, address indexed lender, address indexed borrower);

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

/// @dev raised when a caller is not an allowed pauser
/// @param pauser The address attempting the action
error NotAllowedPauser(address pauser);

/// @dev raised when a lender is not allowlisted to propose a loan to a user
/// @param lender the address of the lender
error LenderNotAllowlisted(address lender);

/// @dev raised when there is an authorization failure accessing a loan
error LoanAuthorizationFailure();

/// @dev raised when amountAlreadyPaid exceeds amountLoaned in importLoan
/// @param amountAlreadyPaid The amount already paid
/// @param amountLoaned The total loaned amount
error AlreadyPaidExceedsLoaned(uint256 amountAlreadyPaid, uint256 amountLoaned);

/// @dev raised when a caller is not allowed to manage entry points
/// @param caller The address attempting to manage entry points
error NotAllowedEntryPointManager(address caller);

/// @dev Emitted when a pauser is added or removed
/// @param pauser The address of the pauser
/// @param allowed Whether the pauser is allowed
event PauserAllowlistModified(address indexed pauser, bool indexed allowed);

/// @dev Emitted when an EntryPoint manager is added or removed
/// @param manager The address of the manager
/// @param allowed Whether the manager is allowed
event EntryPointManagerModified(address indexed manager, bool indexed allowed);

/// @title A contract for managing personal loans
/// @author Joshua Hyde
/// @custom:security-contact 0x9134fc7112b478e97eE6F0E6A7bf81EcAfef19ED
contract Ploan is Initializable, ReentrancyGuard, Pausable {
    /// @notice the ID of the next loan
    uint256 private loanIdBucket;
    /// @notice all of the loans
    mapping(uint256 loanId => PersonalLoan loan) private loansByID;
    /// @notice all of the loan proposal allowlists
    mapping(address allowlistOwner => address[] allowlist) private loanProposalAllowlist;
    /// @notice all of the loan participants
    mapping(address loanParticipant => uint256[] loanIds) private participatingLoans;

    /// @notice Allowlist for pauser addresses
    mapping(address pauserAddress => bool isPauser) private pauserAllowlist;
    // Mapping of allowed EntryPoints for ERC-4337
    mapping(address entryPointerManager => bool isEntryPointerManager) private _entryPoints;
    // Mapping of addresses allowed to manage EntryPoints
    mapping(address entryPointManager => bool isEntryPointerManager) private entryPointManagerAllowlist;

    // Storage gap for upgradeability
    // slither-disable-next-line unused-state,naming-convention
    uint256[47] private __gap;

    /// @notice Add an EntryPoint contract for ERC-4337 meta-transactions
    /// @param entryPoint The EntryPoint contract address to allow
    function addEntryPoint(address entryPoint) external {
        if (!entryPointManagerAllowlist[_msgSender()]) {
            revert NotAllowedEntryPointManager(_msgSender());
        }
        _entryPoints[entryPoint] = true;
    }

    /// @notice Remove an EntryPoint contract from the allowlist
    /// @param entryPoint The EntryPoint contract address to remove
    function removeEntryPoint(address entryPoint) external {
        if (!entryPointManagerAllowlist[_msgSender()]) {
            revert NotAllowedEntryPointManager(_msgSender());
        }
        _entryPoints[entryPoint] = false;
    }

    /// @notice Check if an address is an allowed EntryPoint
    /// @param entryPoint The address to check
    /// @return True if the address is an allowed EntryPoint
    function isEntryPoint(address entryPoint) external view returns (bool) {
        return _entryPoints[entryPoint];
    }

    /// @notice Add an address to the entry point manager allowlist (pauser only)
    /// @param manager The address to add as entry point manager
    /// @notice Add an address to the entry point manager allowlist (pauser only)
    /// @param manager The address to add as entry point manager
    function addEntryPointManager(address manager) external {
        if (!pauserAllowlist[_msgSender()]) {
            revert NotAllowedPauser(_msgSender());
        }
        entryPointManagerAllowlist[manager] = true;
        emit EntryPointManagerModified(manager, true);
    }

    /// @notice Remove an address from the entry point manager allowlist (pauser only)
    /// @param manager The address to remove as entry point manager
    /// @notice Remove an address from the entry point manager allowlist (pauser only)
    /// @param manager The address to remove as entry point manager
    function removeEntryPointManager(address manager) external {
        if (!pauserAllowlist[_msgSender()]) {
            revert NotAllowedPauser(_msgSender());
        }
        entryPointManagerAllowlist[manager] = false;
        emit EntryPointManagerModified(manager, false);
    }

    /// @notice Check if an address is an entry point manager
    /// @param manager The address to check
    /// @return True if the address is an entry point manager
    function isEntryPointManager(address manager) external view returns (bool) {
        return entryPointManagerAllowlist[manager];
    }

    /// @notice initialize the contract
    function initialize() external initializer {
        loanIdBucket = 1;
        pauserAllowlist[_msgSender()] = true; // deployer is initial pauser
        emit PauserAllowlistModified(_msgSender(), true);
    }

    /// @notice allows a user to be added to the loan proposal allowlist
    /// @param toAllow the address to be added
    function allowLoanProposal(address toAllow) external {
        address[] storage allowlist = loanProposalAllowlist[_msgSender()];
        uint256 allowlistLength = allowlist.length;
        for (uint256 i; i < allowlistLength; ++i) {
            if (allowlist[i] == toAllow) {
                return;
            }
        }

        emit LoanProposalAllowlistModified(_msgSender(), toAllow, true);

        if (allowlistLength > 0 && allowlist[allowlistLength - 1] == address(0)) {
            uint256 finalZeroedIndex = allowlistLength - 1;
            // Find the oldest zeroed-out entry and replace it
            while (finalZeroedIndex > 0) {
                if (allowlist[finalZeroedIndex - 1] != address(0)) {
                    break;
                }

                --finalZeroedIndex;
            }

            allowlist[finalZeroedIndex] = toAllow;
        } else {
            loanProposalAllowlist[_msgSender()].push(toAllow);
        }
    }

    /// @notice imports a pre-existing loan that, upon execution, will not transfer any assets, but merely create a record of the loan to be tracked within this app
    /// @param borrower the address of the borrower who is going to borrow the asset
    /// @param loanedAsset the address of the loaned asset being loaned
    /// @param amountLoaned the total amount of the loan (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @param amountAlreadyPaid the amount of the loan that has already been paid (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @return the ID of the proposed loan
    function importLoan(address borrower, address loanedAsset, uint256 amountLoaned, uint256 amountAlreadyPaid)
        external
        whenNotPaused
        returns (uint256)
    {
        if (amountAlreadyPaid > amountLoaned) {
            revert AlreadyPaidExceedsLoaned(amountAlreadyPaid, amountLoaned);
        }
        address lender = _msgSender();

        uint256 loanId = addProposedLoan(lender, borrower, loanedAsset, amountLoaned, amountAlreadyPaid, true);

        emit LoanImported(lender, borrower, loanedAsset, amountLoaned, amountAlreadyPaid, loanId);

        return loanId;
    }

    /// @notice creates a loan and returns the loan ID
    /// @param borrower the address of the borrower who is going to borrow the asset
    /// @param loanedAsset the address of the loaned asset being loaned
    /// @param amountLoaned the total amount of the loan (expressed in the base amount of the asset - e.g., wei of ETH)
    /// @return the ID of the proposed loan
    function proposeLoan(address borrower, address loanedAsset, uint256 amountLoaned)
        external
        whenNotPaused
        returns (uint256)
    {
        address lender = _msgSender();

        uint256 loanId = addProposedLoan(lender, borrower, loanedAsset, amountLoaned, 0, false);

        emit LoanProposed(lender, borrower, loanedAsset, amountLoaned, loanId);

        return loanId;
    }

    /// @notice commits the sender (who is the borrower) to the loan, signaling that they wish to proceed with the loan
    /// @param loanId the ID of the loan
    function commitToLoan(uint256 loanId) external whenNotPaused {
        PersonalLoan storage loan = loansByID[loanId];
        if (loan.borrower != _msgSender()) {
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
    function disallowLoanProposal(address toDisallow) external whenNotPaused {
        address[] storage allowlist = loanProposalAllowlist[_msgSender()];
        uint256 allowlistLength = allowlist.length;
        if (allowlistLength == 0) {
            return;
        }

        // the end of the array is zeroed out for deletions, so stop iterating if
        // the effective end of the list has been reached
        for (uint256 i; i < allowlistLength && allowlist[i] != address(0); ++i) {
            if (allowlist[i] == toDisallow) {
                allowlist[i] = allowlist[allowlistLength - 1];
                delete allowlist[allowlistLength - 1];
                --allowlistLength;

                emit LoanProposalAllowlistModified(_msgSender(), toDisallow, false);
            }
        }
    }

    /// @notice executes a loan, transferring the asset from the lender to the borrower
    /// @param loanId the ID of the loan
    function executeLoan(uint256 loanId) external nonReentrant whenNotPaused {
        PersonalLoan storage loan = loansByID[loanId];
        if (loan.lender != _msgSender()) {
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
            SafeERC20.safeTransferFrom(ERC20(loan.loanedAsset), _msgSender(), loan.borrower, loan.totalAmountLoaned);
        }
    }

    /// @notice cancels a loan
    /// @param loanId the ID of the loan
    function cancelLoan(uint256 loanId) external whenNotPaused {
        PersonalLoan storage loan = loansByID[loanId];
        if (loan.lender != _msgSender()) {
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
    function payLoan(uint256 loanId, uint256 amount) external nonReentrant whenNotPaused {
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

        SafeERC20.safeTransferFrom(ERC20(loan.loanedAsset), _msgSender(), loan.lender, amount);
    }

    /// @notice cancels a loan that has not yet been executed
    /// @param loanId the ID of the loan
    function cancelPendingLoan(uint256 loanId) external whenNotPaused {
        PersonalLoan memory loan = loansByID[loanId];

        if (loan.lender != _msgSender() && loan.borrower != _msgSender()) {
            revert LoanAuthorizationFailure();
        }

        if (loan.started) {
            revert InvalidLoanState();
        }

        emit PendingLoanCanceled(loanId);

        removeLoan(loan);
    }

    /// @notice gets the allowlist for the sender of whom can propose loans to the sender.
    /// @return the allowlist; this may include zeroed-out entries if addresses have been removed from the list.
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
        for (uint256 i; i < loanCount;) {
            if (mappedLoanIds[i] != 0) {
                unchecked {
                    ++nonZeroCount;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (nonZeroCount == 0) {
            PersonalLoan[] memory noLoans = new PersonalLoan[](0);
            return noLoans;
        }

        PersonalLoan[] memory userLoans = new PersonalLoan[](nonZeroCount);
        uint256 userLoansIndex;
        for (uint256 i; i < loanCount;) {
            if (mappedLoanIds[i] == 0) {
                /// skip loans that have been deleted
                unchecked {
                    ++i;
                }
                continue;
            }
            userLoans[userLoansIndex] = loansByID[mappedLoanIds[i]];
            unchecked {
                ++userLoansIndex;
            }
            unchecked {
                ++i;
            }
        }

        return userLoans;
    }

    /// @notice deletes a loan. The loan must either be canceled by the lender or completed by the borrower. A loan can only be deleted by the lender or borrower.
    function deleteLoan(uint256 loanId) external whenNotPaused {
        PersonalLoan memory loan = loansByID[loanId];

        if (loan.lender != _msgSender() && loan.borrower != _msgSender()) {
            revert LoanAuthorizationFailure();
        }

        if (!loan.canceled && !loan.completed) {
            revert InvalidLoanState();
        }

        emit LoanDeleted(loanId, loan.lender, loan.borrower);

        removeLoan(loan);
    }

    /**
     * @dev Adds a loan proposal from the sender to the given borrower.
     * @param lender The address of the lender.
     * @param borrower The address of the borrower.
     * @param loanedAsset The asset being loaned.
     * @param totalAmount The total amount of the loan.
     * @param alreadyPaidAmount The amount already paid.
     * @param imported Whether the loan was imported.
     * @return The ID of the proposed loan.
     */
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
        for (uint256 i; i < loanCount;) {
            if (loanProposalAllowlist[borrower][i] == lender) {
                isAllowlisted = true;

                break;
            }
            unchecked {
                ++i;
            }
        }

        if (!isAllowlisted) {
            revert LenderNotAllowlisted({lender: lender});
        }

        uint256 loanId = loanIdBucket;
        ++loanIdBucket;

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

    /**
     * @dev Associates the given participants to a loan, facilitating indexed lookups in the future.
     * @param loanId The ID of the loan.
     * @param participants The participants to be associated.
     */
    function associateToLoan(uint256 loanId, address[] memory participants) private {
        uint256 participantsCount = participants.length;
        for (uint256 i; i < participantsCount;) {
            address participant = participants[i];
            // see, first, if a zeroed-out slot can be reused
            uint256[] storage participantLoans = participatingLoans[participant];
            uint256 loanCount = participantLoans.length;
            if (loanCount > 0 && participantLoans[loanCount - 1] == 0) {
                uint256 finalZeroedOutIndex = loanCount - 1;
                while (finalZeroedOutIndex > 0 && participantLoans[finalZeroedOutIndex - 1] == 0) {
                    unchecked {
                        --finalZeroedOutIndex;
                    }
                }

                participantLoans[finalZeroedOutIndex] = loanId;
            } else {
                participantLoans.push(loanId);
            }

            emit LoanAssociated(loanId, participant);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Disassociates the given participants from a loan.
     * @param loanId The ID of the loan.
     * @param participants The participants to be disassociated.
     */
    function disassociateFromLoan(uint256 loanId, address[] memory participants) private {
        uint256 participantsCount = participants.length;
        for (uint256 i; i < participantsCount;) {
            address participant = participants[i];
            uint256[] memory loans = participatingLoans[participant];
            uint256 participantLoanCount = loans.length;
            // The end of the loan list will always be zeroed out, so stop if zero is encountered
            for (uint256 j; j < participantLoanCount && loans[j] != 0;) {
                if (loans[j] == loanId) {
                    loans[j] = loans[participantLoanCount - 1];
                    delete loans[j];
                    unchecked {
                        --participantLoanCount;
                    }

                    emit LoanDisassociated(loanId, participant);
                }
                unchecked {
                    ++j;
                }
            }

            participatingLoans[participant] = loans;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Removes all traces of a loan from within the storage in this contract.
     * @param loan The PersonalLoan struct to remove.
     */
    function removeLoan(PersonalLoan memory loan) private {
        address[] memory participants = new address[](2);
        participants[0] = loan.lender;
        participants[1] = loan.borrower;
        disassociateFromLoan(loan.loanId, participants);

        delete loansByID[loan.loanId];
    }

    /// @notice Pause contract in an emergency (only allowlisted pausers)
    function pause() external whenNotPaused {
        if (!pauserAllowlist[_msgSender()]) {
            revert NotAllowedPauser(_msgSender());
        }
        _pause();
    }

    /// @notice Unpause contract after emergency (only allowlisted pausers)
    function unpause() external whenPaused {
        if (!pauserAllowlist[_msgSender()]) {
            revert NotAllowedPauser(_msgSender());
        }
        _unpause();
    }

    /// @notice Add an address to the pauser allowlist (only existing pauser can add)
    /// @param pauser The address to add
    function addPauser(address pauser) external whenNotPaused {
        if (!pauserAllowlist[_msgSender()]) {
            revert NotAllowedPauser(_msgSender());
        }
        pauserAllowlist[pauser] = true;
        emit PauserAllowlistModified(pauser, true);
    }

    /// @notice Remove an address from the pauser allowlist (only existing pauser can remove)
    /// @param pauser The address to remove
    function removePauser(address pauser) external whenNotPaused {
        if (!pauserAllowlist[_msgSender()]) {
            revert NotAllowedPauser(_msgSender());
        }
        pauserAllowlist[pauser] = false;
        emit PauserAllowlistModified(pauser, false);
    }

    /// @notice Check if an address is a pauser
    /// @param pauser The address to check
    /// @return True if address is a pauser
    function isPauser(address pauser) external view returns (bool) {
        return pauserAllowlist[pauser];
    }

    /// @dev Returns the sender of the transaction, supporting ERC-4337 EntryPoints
    function _msgSender() internal view virtual override returns (address) {
        address sender_;
        if (_entryPoints[msg.sender]) {
            // solhint-disable-next-line avoid-low-level-calls
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // ERC-4337: sender is the first parameter of UserOperation (first 32 bytes after selector)
                sender_ := shr(96, calldataload(4)) // skip selector (4 bytes)
            }
        } else {
            sender_ = msg.sender;
        }
        return sender_;
    }
}
