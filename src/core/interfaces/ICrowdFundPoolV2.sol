// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ICrowdFundPoolV2 {
    struct ContractProposal {
        address owner;
        uint256 term;
        uint256 interestRateAPR;
        uint256 deadline;
        string[] assignmentStrings;
        uint256 startTime;
        uint256 depositedAmount;
        uint256 backingFunds;
        uint256 status;
        uint256[] tokenIds;
        uint256 numberTokens;
    }

    struct UserDeposit {
        uint256 amount;
        uint256 proposalIndex;
        uint256 interestTime;
    }

    //Events
    /// @dev   The event for when a manager creates a proposal.
    /// @param proposalIndex: the proposal that was created
    /// @param owner: the proposal creator's address
    /// @param numberTokens: the number of tokens for for this proposal
    /// @param deadline: the deadline in blocktime seconds for this proposal to be filled.
    event ProposalCreated(uint256 indexed proposalIndex, address indexed owner, uint256 numberTokens, uint256 deadline);

    /// @dev   The event for when a proposal is canceled by its creator
    /// @param proposalIndex: the proposal that was canceled
    /// @param owner: The creator's address
    event ProposalCanceled(uint256 indexed proposalIndex, address indexed owner);

    /// @dev   The event for when a proposal is finished by its creator
    /// @param proposalIndex: the proposal that was finished
    /// @param owner: the creator of the proposal
    event ProposalFinished(uint256 indexed proposalIndex, address indexed owner);

    /// @dev   The event for when a user submits a deposit towards a proposal
    /// @param proposalIndex: the proposal this deposit was made towards
    /// @param user: the user address that submitted this deposit
    /// @param amount: the amount of HyPC the user deposited to this proposal.
    event DepositCreated(uint256 indexed proposalIndex, address indexed user, uint256 amount);

    /// @dev   The event for when a user withdraws a previously created deposit
    /// @param depositIndex: the user's deposit index that was withdrawn
    /// @param user: the user's address
    /// @param amount: the amount of HyPC that was withdrawn.
    event WithdrawDeposit(uint256 indexed depositIndex, address indexed user, uint256 amount);

    /// @dev   The event for when a user updates their deposit and gets interest.
    /// @param depositIndex: the deposit index for this user
    /// @param user: the address of the user
    /// @param interestChange: the amount of HyPC interest given to this user for this update.
    event UpdateDeposit(uint256 indexed depositIndex, address indexed user, uint256 interestChange);

    /// @dev   The event for when a user transfers their deposit to another user.
    /// @param depositIndex: the deposit index for this user
    /// @param user: the address of the user
    /// @param to: the address that this deposit was sent to
    /// @param amount: the amount of HyPC in this deposit.
    event TransferDeposit(uint256 indexed depositIndex, address indexed user, address indexed to, uint256 amount);

    /// @dev   The event for when a manager changes the assigned string of a token in a proposal.
    /// @param proposalIndex: Index of the changed proposal.
    /// @param owner: the address of the proposal's owner.
    /// @param assignment: string that the proposal's assignment was changed to
    /// @param assignmentRef: String reference to the value of assignment
    event AssignmentChanged(
        uint256 indexed proposalIndex,
        address indexed owner,
        string indexed assignment,
        uint256 tokenIndex,
        string assignmentRef
    );

    // @dev The event for a token swap.
    // @param user: Address of the user calling the swap function.
    // @param proposalIndex: proposal which tokens will be used.
    // @param tokensToSwap: amount of tokens to swap.
    event TokensSwaped(address indexed user, uint256 indexed proposalIndex, uint256 tokensToSwap);

    /// @dev   The event for when tokens has been redeemed.
    /// @param user: Address of the user redeeming the tokens
    /// @param proposalIndex: Index of the proposal from where the tokens will be redeemed
    /// @param redeemedTokens: Amount of tokens redeemed.
    event TokensRedeemed(address indexed user, uint256 indexed proposalIndex, uint256 redeemedTokens);

    /// @dev   The event for when pool fee has been set.
    /// @param poolFee: Index of the changed proposal.
    event PoolFeeSet(uint256 indexed poolFee);

    /// @notice Allows the owner of the pool to set the fee on proposal creation.
    /// @param  fee: the fee in HyPC to charge the proposal creator on creation.
    function setPoolFee(uint256 fee) external;

    /**
        @notice Allows someone to create a proposal to have HyPC pooled together to swap for a c_HyPC token and
                have that token be given a specified assignment string. The creator specifies the term length
                for this proposal and supplies an amount of HyPC to act as interest for the depositors of the
                proposal.
        @param  termNum: either 0, 1, or 2, corresponding to 18 months, 24 months or 36 months respectively.
        @param  backingFunds: the amount of HyPC that the creator puts up to create the proposal, which acts
                as the interest to give to the depositors during the course of the proposal's term.
        @param  numberTokens: the number of c_HyPC that this proposals is for.
        @param  deadline: the block timestamp that this proposal must be filled by in order to be started.
        @param  specifiedFee: The fee that the creator expects to pay per token
        @dev    The specifiedFee parameter is used to prevent a pool owner from front-running a transaction
                to increase the poolFee after a creator has submitted a transaction.
        @dev    The interest rate calculation for the variable interestRateAPR is described in the contract's
                comment section. The only difference here is that there is an extra term in the numerator of
                SIX_DECIMALS since we can't have floating point numbers by default in solidity.
    */
    function createProposal(
        uint256 termNum,
        uint256 backingFunds,
        uint256 numberTokens,
        uint256 deadline,
        uint256 specifiedFee
    ) external;

    /**
        @notice Lets a user creates a deposit for a pending proposal and submit the specified amount of 
                HyPC to back it.

        @param  proposalIndex: the proposal index that the user wants to back.
        @param  amount: the amount of HyPC the user wishes to deposit towards this proposal.
    */
    function createDeposit(uint256 proposalIndex, uint256 amount) external;

    /**
        @notice Lets a user that owns a deposit for a proposal to transfer the ownership of that
                deposit to another user. This is useful for liquidity since deposit can be tied up for
                fairly long periods of time.
        @param  depositIndex: the index of this users deposits array that they wish to transfer.
        @param  to: the address of the user to send this deposit to
        @dev    Deposit objects are deleted from the deposits array after being transferred. The deposit is 
                deleted and the last entry of the array is copied to that index so the array can be decreased
                in length, so we can avoid iterating through the array.
    */
    function transferDeposit(uint256 depositIndex, address to) external;

    /**
        @notice Marks a proposal as started after it has received enough HyPC. At this point the proposal swaps
                the HyPC for c_HyPC and sets the timestamp for the length of the term and interest payment
                periods.
        @param  proposalIndex: the proposal to start.
    */
    function startProposal(uint256 proposalIndex) external;

    function swapTokens(uint256 proposalIndex, uint256 tokensToSwap) external;

    function redeemTokens(uint256 proposalIndex, uint256 tokensToRedeem) external;

    /**
        @notice If a proposal hasn't been started yet, then the creator can cancel it and get back their
                backing HyPC. Users who have deposited can then withdraw their deposits with the withdrawDeposit
                function given below.
        @param  proposalIndex: the proposal index to be cancel.
    */
    function cancelProposal(uint256 proposalIndex) external;

    /**
        @notice Allows a user to withdraw their deposit from a proposal if that proposal has been canceled,
                passed its deadline, has not been started yet, or has come to term. For the case of a proposal
                that has come to term, then the user has to update their deposit to claim any remaining 
                interest first, and all of the proposal's tokens need to be redeemed.
        @param  depositIndex: the index of this user's deposits array that they wish to withdraw.
    */
    function withdrawDeposit(uint256 depositIndex) external;

    /**
        @notice Updates a user's deposit and sends them the accumulated interest from the amount of two week
                periods that have passed.
        @param  depositIndex: the index of this user's deposits array that they wish to update.
        @dev    The interestChange variable takes the user's deposit amount and multiplies it by the 
                proposal's calculated interestRateAPR to get the the yearly interest for this deposit with
                6 extra decimal places. It divides this by the number of periods in a year to get the interest
                from one two-week period, and multiplies it by the number of two week periods that have passed
                since this function was called to account for periods that were previously skipped. Finally,
                it divides the result by SIX_DECIMALS to remove the extra decimal places.
    */
    function updateDeposit(uint256 depositIndex) external;

    /**
        @notice This completes the proposal after it has come to term, allowing the underlying c_HyPC to be
                redeemed by the contract so it can be given back to the depositors.
        @param  proposalIndex: the proposal's index to complete.
    */
    function completeProposal(uint256 proposalIndex) external;

    /**
        @notice This allows the creator of a completed proposal to claim any left over backingFunds interest
                after all users have withdrawn their deposits from this proposal.
        @param  proposalIndex: the proposal's index to be finished.
    */
    function finishProposal(uint256 proposalIndex) external;

    /**
        @notice This allows a proposal creator to change the assignment of a c_HyPC token that was swapped for
                in a fulfilled proposal.
        @param  proposalIndex: the proposal's index to have its c_HyPC assignment changed.
        @param  tokenIndex: the index for the token inside the proposal.tokenIds array.
    */
    function changeAssignment(uint256 proposalIndex, uint256 tokenIndex, string memory assignmentString) external;

    /**
        @notice This allows a receving user of a deposit or proposal to first register their address so they
                can receive the deposit/proposal. This is a safeguard against the sender from fat-fingering
                their address and sending it an invalid address.
    */
    function addToTransferRegistry() external;

    /**
        @notice This deletes a user from the transferRegistry. Mostly not needed, but is here for completeness.
    */
    function removeFromTransferRegistry() external;

    //Getters
    /**
        @notice Returns a user's deposits
        @param  user: the user's address.
    */
    function getUserDeposits(address user) external;

    /**
        @notice Returns a specific deposit for a user
        @param user: the user's address
        @param depositIndex: the user's deposit index to be returned.
    */
    function getDeposit(address user, uint256 depositIndex) external;

    /**
        @notice Returns the length of a user's deposits array
        @param  user: the user's address
    */
    function getDepositsLength(address user) external;

    /**
        @notice Returns the proposal object at the given index.
        @param  proposalIndex: the proposal's index to be returned
    */
    function getProposal(uint256 proposalIndex) external;

    /**
        @notice Returns the total number of proposals submitted to the contract so far.
    */
    function getProposalsLength() external;

    /**
        @notice Returns the number of tokens swapped for in the given proposal.
        @param  proposalIndex: the proposal's index to be used.
    */
    function getProposalTokensLength(uint256 proposalIndex) external;

    /**
        @notice Returns the tokenId for a tokenIndex in the proposal's tokenIds array.
        @param  proposalIndex: the proposal's index to be used.
        @param  tokenIndex: the index of the tokenIds array inside the proposal to return.
    */
    function getProposalTokenId(uint256 proposalIndex, uint256 tokenIndex) external;

    /**
        @notice Returns the assignmentString for an tokenIndex in the proposal's tokenIds array.
        @param  proposalIndex: the proposal's index to be used.
        @param  tokenIndex: the index of the assignmentStrings array inside the proposal to return.
    */
    function getProposalAssignmentString(uint256 proposalIndex, uint256 tokenIndex) external;
}
