// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

/**
 * @title AavePoolBase
 * @dev Base contract that provides access to the Aave Pool contract.
 */
abstract contract AavePoolBase {
    /// @dev Error thrown when an input parameter is zero.
    error InputIsZero(string name);

    /// @dev The Aave Pool contract address.
    IPool public immutable pool;

    /**
     * @dev Initializes the AavePoolBase contract.
     * @param provider The address of the Aave Pool Addresses Provider.
     */
    constructor(IPoolAddressesProvider provider) {
        if (address(provider) == address(0)) revert InputIsZero("PROVIDER");
        pool = IPool(provider.getPool());
    }
}
