// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title TimeLock
 * @author Sidoux
 * @dev A Solidity contract implementing a time lock controller for delaying and controlling contract executions.
 * This contract extends the TimelockController contract from the OpenZeppelin library.
 */
contract TimeLock is TimelockController {
    /**
     * @dev Constructor function.
     * Initializes the TimeLock contract with specified parameters for timelock functionality.
     * @param minDelay The minimum delay time in seconds for executing a proposal.
     * @param proposers The list of addresses allowed to propose.
     * @param executors The list of addresses allowed to execute.
     * @param admin The address with administrative privileges for configuring the time lock.
     */
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
