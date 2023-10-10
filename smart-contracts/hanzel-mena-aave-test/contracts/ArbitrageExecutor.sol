// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { FlashLoanSimpleReceiverBase } from "./FlashLoanSimpleReceiverBase.sol";
import { IUniswapV2Pair } from "./interfaces/IUniswapPair.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapRouterV2.sol";

/**
 * @title ArbitrageExecutor
 * @dev A contract that executes flash loans and performs arbitrage operations between two tokens on Uniswap and Sushiswap.
 */
contract ArbitrageExecutor is Ownable, FlashLoanSimpleReceiverBase {
    using SafeERC20 for IERC20;

    /// @dev Error thrown when the minimum expected amount for a swap is insufficient.
    error InsufficientMinimum(string name);
    /// @dev Error thrown when the slippage value is invalid.
    error InvalidSlippage();
    /// @dev Error thrown when an unauthorized caller attempts to execute the flash loan.
    error InvalidCaller();

    /// @dev One hundred represented in wei
    uint256 constant ONE_HUNDRED = 100 ether;
    /// @dev The data of the flashloan
    FlashLoanData public flashLoanData;

    struct FlashLoanData {
        address token0;
        address token1;
        IERC20 token0Contract;
        IERC20 token1Contract;
        IUniswapV2Router02 uniswapRouter;
        IUniswapV2Router02 sushiswapRouter;
    }

    /**
     * @dev Initializes the ArbitrageExecutor contract.
     * @param _addressProvider The address of the Aave Pool Addresses Provider.
     * @param _uniswapRouter The address of the Uniswap V2 Router.
     * @param _sushiswapRouter The address of the Sushiswap V2 Router.
     * @param _token0 The address of the first token.
     * @param _token1 The address of the second token.
     */
    constructor(
        IPoolAddressesProvider _addressProvider,
        IUniswapV2Router02 _uniswapRouter,
        IUniswapV2Router02 _sushiswapRouter,
        IERC20 _token0,
        IERC20 _token1
    ) FlashLoanSimpleReceiverBase(_addressProvider) {
        if (address(_uniswapRouter) == address(0)) revert InputIsZero("UNISWAP_ROUTER");
        if (address(_sushiswapRouter) == address(0)) revert InputIsZero("SUSHISWAP_ROUTER");
        if (address(_token0) == address(0)) revert InputIsZero("TOKEN0");
        if (address(_token1) == address(0)) revert InputIsZero("TOKEN1");
        flashLoanData = FlashLoanData({
            token0: address(_token0),
            token1: address(_token1),
            token0Contract: _token0,
            token1Contract: _token1,
            uniswapRouter: _uniswapRouter,
            sushiswapRouter: _sushiswapRouter
        });
    }

    /**
     * @dev Executes a flash loan by borrowing the specified amount of an asset.
     * @param asset The address of the asset to be borrowed.
     * @param amount The amount of the asset to be borrowed.
     * @param minimumFirstSwap The minimum expected amount of the first swap.
     * @param minimumSecondSwap The minimum expected amount of the second swap.
     */
    function executeFlashLoan(
        address asset,
        uint256 amount,
        uint256 minimumFirstSwap,
        uint256 minimumSecondSwap
    ) external onlyOwner {
        bytes memory params = abi.encode(msg.sender, minimumFirstSwap, minimumSecondSwap);
        POOL.flashLoanSimple(address(this), asset, amount, params, 0);
    }

    /**
     * @dev Executes the flash loan operation after the contract has received the flash loaned amount.
     * @param asset The address of the flash loaned asset.
     * @param amount The amount of the flash loaned asset.
     * @param premium The premium fee for the flash loan.
     * @param initiator The address initiating the flash loan.
     * @param params The additional data parameters.
     * @return A boolean value indicating the success of the flash loan operation.
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (msg.sender != address(POOL)) revert InvalidCaller();
        FlashLoanData memory data = flashLoanData;

        (address investor, uint256 minimumFirstSwap, uint256 minimumSecondSwap) = abi.decode(
            params,
            (address, uint256, uint256)
        );
        data.token1Contract.safeApprove(address(data.sushiswapRouter), amount);
        address[] memory pathSushiswap = getPath(data.token1, data.token0);
        data.sushiswapRouter.swapExactTokensForTokens(
            amount,
            minimumFirstSwap,
            pathSushiswap,
            address(this),
            block.timestamp
        );
        uint256 uniswapObtainedToken0 = data.token0Contract.balanceOf(address(this));
        address[] memory pathUniswap = getPath(data.token0, data.token1);
        data.token0Contract.safeApprove(address(data.uniswapRouter), uniswapObtainedToken0);
        data.uniswapRouter.swapExactTokensForTokens(
            uniswapObtainedToken0,
            minimumSecondSwap,
            pathUniswap,
            address(this),
            block.timestamp
        );
        uint256 usdtFinalBalance = data.token1Contract.balanceOf(address(this));

        // Approve the LendingPool contract allowance to pull the owed amount
        uint256 amountOwed = amount + premium;
        data.token1Contract.safeApprove(address(POOL), amountOwed);
        data.token1Contract.safeTransfer(investor, usdtFinalBalance - amountOwed);
        return true;
    }

    /**
     * @dev Estimates the minimum amounts for the first and second swaps with a given borrowed amount and slippage.
     * @param borrowedAmount The amount of the flash loaned asset.
     * @param slippage The slippage tolerance percentage.
     * @return minimumFirstSwap The minimum expected amounts for the first swap.
     * @return minimumSecondSwap The minimum expected amounts for the second swaps.
     */
    function estimateSlippage(
        uint256 borrowedAmount,
        uint256 slippage
    ) external view returns (uint256 minimumFirstSwap, uint256 minimumSecondSwap) {
        if (slippage > ONE_HUNDRED) revert InvalidSlippage();
        FlashLoanData memory data = flashLoanData;
        uint256[] memory sushiAmountsOut = data.sushiswapRouter.getAmountsOut(
            borrowedAmount,
            getPath(data.token1, data.token0)
        );
        minimumFirstSwap = sushiAmountsOut[1] - ((sushiAmountsOut[1] * slippage) / ONE_HUNDRED);
        uint256[] memory uniswapAmountsOut = data.uniswapRouter.getAmountsOut(
            minimumFirstSwap,
            getPath(data.token0, data.token1)
        );
        minimumSecondSwap =
            uniswapAmountsOut[1] -
            ((uniswapAmountsOut[1] * slippage) / ONE_HUNDRED);
    }

    /**
     * @dev Retrieves the token path between two tokens for swapping.
     * @param from The address of the source token.
     * @param to The address of the target token.
     * @return The token path array.
     */
    function getPath(address from, address to) public pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = from;
        path[1] = to;
        return path;
    }
}
