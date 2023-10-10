// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

/**
 * @title GovernorContract
 * @author Sidoux
 * @dev A Solidity contract implementing a governor with multiple extensions.
 *        - Governor: base contract
 *        - GovernorSettings: contract that manage the governance settings (_votingDelay, _votingPeriod, _proposalThreshold)
 *        - GovernorCountingSimple: contract to count votes
 *        - GovernorVotes: contract to help integration the ERC20 token
 *        - GovernorVotesQuorumFraction: contract to manage the quorum
 *        - GovernorTimelockControl: contract to manage time related actions
 * This contract combines various OpenZeppelin governor extensions to provide a comprehensive governance solution.
 */

contract GovernorContract is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /**
     * @dev Constructor function.
     * Initializes the GovernorContract with various parameters required for governance functionality.
     * @param _token The token contract used for voting.
     * @param _timelock The timelock contract used for controlling proposal execution.
     * @param _quorumPercentage The percentage of votes required to achieve a quorum.
     * @param _votingPeriod The duration of the voting period in blocks.
     * @param _votingDelay The delay before voting starts after proposing a new action, in blocks.
     */
    constructor(
        IVotes _token,
        TimelockController _timelock,
        uint256 _quorumPercentage,
        uint256 _votingPeriod,
        uint256 _votingDelay
    )
        Governor("GovernorContract")
        GovernorSettings(_votingDelay, _votingPeriod, 0)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(_quorumPercentage)
        GovernorTimelockControl(_timelock)
    {}

    /**
     * @dev Returns the voting delay configured for this governor contract.
     * @return The number of blocks as the voting delay.
     */
    function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /**
     * @dev Returns the voting period configured for this governor contract.
     * @return The number of blocks as the voting period.
     */
    function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /**
     * @dev Returns the quorum for a specific block number based on the configured quorum percentage.
     * @param blockNumber The block number for which to calculate the quorum.
     * @return The calculated quorum in number of votes.
     */
    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    /**
     * @dev Returns the number of votes an account has at a specific block number.
     * @param account The account for which to query the vote count.
     * @param blockNumber The block number at which to query the vote count.
     * @return The number of votes the account has.
     */
    function getVotes(address account, uint256 blockNumber)
        public
        view
        override(IGovernor, Governor)
        returns (uint256)
    {
        return super.getVotes(account, blockNumber);
    }

    /**
     * @dev Returns the state of a proposal based on its ID.
     * @param proposalId The ID of the proposal.
     * @return The state of the proposal
     * (Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed).
     */
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /**
     * @dev Creates a new proposal.
     * @param targets The list of target addresses for the proposal's actions.
     * @param values The list of values associated with the proposal's actions.
     * @param calldatas The list of calldata for the proposal's actions.
     * @param description The description of the proposal.
     * @return The ID of the newly created proposal.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, IGovernor) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    /**
     * @dev Returns the proposal threshold configured for this governor contract.
     * @return The proposal threshold value.
     */
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /**
     * @dev Executes a proposal's actions after it has been approved and the timelock has passed.
     * @param proposalId The ID of the proposal to execute.
     * @param targets The list of target addresses for the proposal's actions.
     * @param values The list of values associated with the proposal's actions.
     * @param calldatas The list of calldata for the proposal's actions.
     * @param descriptionHash The hash of the proposal's description.
     */
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Cancels a proposal's actions after it has been denied or canceled.
     * @param targets The list of target addresses for the proposal's actions.
     * @param values The list of values associated with the proposal's actions.
     * @param calldatas The list of calldata for the proposal's actions.
     * @param descriptionHash The hash of the proposal's description.
     * @return The ID of the canceled proposal.
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Returns the executor configured for this governor contract.
     * @return The address of the executor.
     */
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    /**
     * @dev Checks if the contract supports the specified interface.
     * @param interfaceId The interface ID to check.
     * @return A boolean indicating whether the contract supports the interface.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
