/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

//// @title A contract for managing personal loans
//// @author 0x9134fc7112b478e97eE6F0E6A7bf81EcAfef19ED
contract Ploan is Initializable {
    /// @notice the ID of the next loan
    uint256 public loanIdBucket;
    /// @notice all of the loans
    mapping(uint256 loanId => PersonalLoan loan) public loansByID;
    /// @notice all of the loan proposal allowlists
    mapping(address allowlistOwner => address[] allowlist) public loanProposalAllowlist;
    /// @notice all of the loan participants
    mapping(address loanParticipant => uint256[] loanIds) public participatingLoans;
    /// @notice whether the contract has been initialized
    bool initialized;

    /// @notice constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice initialize the contract
    function initialize() public initializer {
        require(!initialized, "Contract has already been initialized");

        loanIdBucket = 1;

        initialized = true;
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

    /// @notice commits the sender (who is the borrower) to the loan, signaling that they wish to proceed with the loan
    /// @param loanId the ID of the loan
    function commitToLoan(uint256 loanId) public {
        PersonalLoan memory loan = loansByID[loanId];
        require(loan.borrower == msg.sender, "Only the borrower can commit to the loan");

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

    /// @notice executes a loan, transferring the asset from the lender to the borrower
    /// @param loanId the ID of the loan
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

    /// @notice cancels a loan
    /// @param loanId the ID of the loan
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

    /// @notice executes a repayment of a loan
    /// @param loanId the ID of the loan
    /// @param amount the amount to be repaid (expressed in the base amount of the asset - e.g., wei of ETH)
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
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            participatingLoans[participant].push(loanId);
        }
    }

    /// @notice disassociates the given participants from a loan
    /// @param loanId the ID of the loan
    /// @param participants the participants to be disassociated
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

    /// @dev represents a loan
    struct PersonalLoan {
        uint256 loanId; /// the ID of the loan
        uint256 totalAmountLoaned; /// the total amount of the asset that was loaned
        uint256 totalAmountRepaid; /// the total amount of the asset that has been repaid
        address borrower; /// the address to whom the amount is loaned
        address lender; /// the address that loaned the asset
        address loanedAsset; /// the address of the loaned asset
        bool borrowerCommitted; /// true if the borrower has committed the loan; the loan has not necessarily been executed yet
        bool canceled; /// true if the loan was canceled before it could be executed
        bool completed; /// true if the loan has been fully paid off
        bool started; /// true if the loan has been executed by the lender, transferring assets to the borrower
        bool repayable; /// true if the loan can be repaid
    }
}
