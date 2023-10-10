// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IFlashLoanSimpleReceiver } from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

/**
 * @title FlashLoanSimpleReceiverBase
 * @dev Base contract that provides access to the Aave Pool Addresses Provider and the Aave Pool contract for flash loan receivers.
 */
abstract contract FlashLoanSimpleReceiverBase is IFlashLoanSimpleReceiver {
    /// @dev Error thrown when an input parameter is zero.
    error InputIsZero(string name);

    /// @dev The Aave Pool Addresses Provider contract address.
    IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;

    /// @dev The Aave Pool contract address.
    IPool public immutable override POOL;

    /**
     * @dev Initializes the FlashLoanSimpleReceiverBase contract.
     * @param provider The address of the Aave Pool Addresses Provider.
     */
    constructor(IPoolAddressesProvider provider) {
        if (address(provider) == address(0)) revert InputIsZero("PROVIDER");
        ADDRESSES_PROVIDER = provider;
        POOL = IPool(provider.getPool());
    }
}
