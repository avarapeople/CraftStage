// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

import { DataTypes } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { AavePoolBase } from "./AavePoolBase.sol";

/**
 * @title AaveInvestment
 * @dev A contract that enables investing and withdrawing funds into/from Aave protocol.
 */
contract AaveInvestment is Ownable, AavePoolBase {
    using SafeERC20 for IERC20;

    /// @dev Error thrown when there is insufficient balance to withdraw.
    error InsufficientBalanceToWithdraw();

    /// @dev The token being invested in Aave.
    address public immutable token;

    /// @dev The address of the corresponding aToken in Aave.
    address public immutable aaveLp;

    /**
     * @dev Initializes the AaveInvestment contract.
     * @param _addressProvider The address of the Aave Pool Addresses Provider contract.
     * @param _token The token being invested in Aave.
     */
    constructor(
        IPoolAddressesProvider _addressProvider,
        address _token
    ) AavePoolBase(_addressProvider) {
        if (_token == address(0)) revert InputIsZero("TOKEN");
        token = _token;
        DataTypes.ReserveData memory reserve = pool.getReserveData(token);
        aaveLp = reserve.aTokenAddress;
    }

    /**
     * @dev Invests the specified amount of tokens into Aave.
     * @param _amount The amount of tokens to invest.
     */
    function invest(uint256 _amount) external payable onlyOwner {
        address _token = token;
        IPool _pool = pool;
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        address onBehalfOf = address(this);
        IERC20(_token).safeApprove(address(_pool), _amount);
        _pool.supply(_token, getBalance(_token), onBehalfOf, uint16(0));
    }

    /**
     * @dev Withdraws the specified amount of tokens from Aave.
     * @param _amount The amount of tokens to withdraw.
     */
    function withdraw(uint256 _amount) external onlyOwner {
        uint256 aaveLpBalance = getBalance(aaveLp);
        if (aaveLpBalance < _amount) revert InsufficientBalanceToWithdraw();
        address to = msg.sender;
        pool.withdraw(token, _amount, to);
    }

    /**
     * @dev Retrieves the total balance of aTokens held by this contract.
     * @return The total balance of aTokens.
     */
    function getTotalAaveLpBalance() public view returns (uint256) {
        return getBalance(aaveLp);
    }

    /**
     * @dev Retrieves the balance of the specified token held by this contract.
     * @param _token The address of the token.
     * @return The balance of the token.
     */
    function getBalance(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
