// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {OracleLib, AggregatorV3Interface} from "../libraries/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {StableCookie} from "./StableCookie.sol";

/**
 * @title CookieStore
 * @author Sidoux
 */

contract CookieStore is ReentrancyGuard, AccessControl {
    error CookieStore__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error CookieStore__NeedsMoreThanZero();
    error CookieStore__TokenNotAllowed(address token);
    error CookieStore__TransferFailed();
    error CookieStore__BreaksHealthFactor(uint256 healthFactorValue);
    error CookieStore__MintFailed();
    error CookieStore__HealthFactorOk();
    error CookieStore__HealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;

    StableCookie private immutable i_CKI;

    bytes32 public constant ADD_TOKEN_COLLATERAL_ROLE = keccak256("ADD_TOKEN_COLLATERAL_ROLE");

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    /// @dev percentage of discount when liquidating
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @dev Token address to price feed address
    mapping(address collateralToken => address priceFeed) private priceFeeds;
    /// @dev Amount of collateral deposited by user in a specific token
    mapping(address user => mapping(address collateralToken => uint256 amount)) private collateralDeposited;
    /// @dev Amount of CKI minted by user
    mapping(address user => uint256 amount) private CKIMinted;
    address[] public authorizedCollateralTokens;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert CookieStore__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (priceFeeds[token] == address(0)) {
            revert CookieStore__TokenNotAllowed(token);
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address CKIAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADD_TOKEN_COLLATERAL_ROLE, msg.sender);

        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert CookieStore__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            authorizedCollateralTokens.push(tokenAddresses[i]);
        }
        i_CKI = StableCookie(CKIAddress);
    }

    /**
     * @dev Adds a new token collateral for tracking with its corresponding price feed address.
     * Only callable by accounts with the ADD_TOKEN_COLLATERAL_ROLE.
     * @param tokenAddresses The address of the collateral token to add.
     * @param priceFeedAddresses The address of the price feed contract corresponding to the collateral token.
     */
    function addTokenCollateral(address tokenAddresses, address priceFeedAddresses)
        external
        onlyRole(ADD_TOKEN_COLLATERAL_ROLE)
    {
        // Set the price feed address for the specified collateral token
        priceFeeds[tokenAddresses] = priceFeedAddresses;
        // Add the collateral token address to the list of authorized collateral tokens
        authorizedCollateralTokens.push(tokenAddresses);
    }

    /**
     * @dev Deposits collateral and mints CKI tokens in a single transaction.
     * Calls the depositCollateral and mintCKI functions sequentially.
     * @param tokenCollateralAddress The address of the collateral token to deposit.
     * @param amountCollateral The amount of collateral tokens to deposit.
     * @param amountCKIToMint The amount of CKI tokens to mint.
     */
    function depositCollateralAndMintCKI(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountCKIToMint
    ) external {
        // Deposit the specified amount of collateral tokens
        depositCollateral(tokenCollateralAddress, amountCollateral);
        // Mint the specified amount of CKI tokens
        mintCKI(amountCKIToMint);
    }

    /**
     * @dev Redeems collateral for CKI tokens in a single transaction.
     * Requires that the amount of collateral to redeem is greater than zero.
     * @param tokenCollateralAddress The address of the collateral token to redeem.
     * @param amountCollateral The amount of collateral tokens to redeem.
     * @param amountCKIToBurn The amount of CKI tokens to burn.
     */
    function redeemCollateralForCKI(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountCKIToBurn)
        external
        moreThanZero(amountCollateral)
    {
        // Burn the specified amount of CKI tokens
        _burnCKI(amountCKIToBurn, msg.sender, msg.sender);
        // Redeem the specified amount of collateral tokens for CKI tokens
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        // Check and revert the transaction if the user's health factor is broken
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev Redeems collateral tokens in exchange for CKI tokens.
     * Requires that the amount of collateral to redeem is greater than zero.
     * Prevents reentrancy using the nonReentrant modifier.
     * @param tokenCollateralAddress The address of the collateral token to redeem.
     * @param amountCollateral The amount of collateral tokens to redeem.
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        // Redeem the specified amount of collateral tokens for CKI tokens
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        // Check and revert the transaction if the user's health factor is broken
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev Burns a specified amount of CKI tokens.
     * Calls the _burnCKI function and checks for the user's health factor after burning.
     * Requires that the amount of CKI tokens to burn is greater than zero.
     * @param amount The amount of CKI tokens to burn.
     */
    function burnCKI(uint256 amount) external moreThanZero(amount) {
        // Burn the specified amount of CKI tokens
        _burnCKI(amount, msg.sender, msg.sender);
        // Check and revert the transaction if the user's health factor is broken after burning
        // Note: This check might be unnecessary if the health factor isn't expected to break during token burning.
        // revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev Liquidates an insolvent user by using collateral to cover their debt.
     * The liquidator burns their own CKI tokens to cover the user's debt and receives a bonus collateral amount.
     * @param collateral The ERC20 token address of the collateral used for liquidation.
     * @param user The address of the insolvent user with a health factor below 1e18.
     * @param debtToCover The amount of CKI tokens to burn in order to cover the user's debt.
     *
     * @notice You can partially liquidate a user.
     * @notice The liquidator receives a 10% LIQUIDATION_BONUS for taking the user's funds.
     * @notice This function assumes that the protocol will be approximately 150% overcollateralized to work effectively.
     * @notice If the protocol is only 100% collateralized, it may not be able to liquidate users effectively.
     * For example, if the price of the collateral plummets before liquidation occurs.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= 1e18) {
            revert CookieStore__HealthFactorOk();
        }
        // If covering 100 CKI, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 CKI
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        // Burn CKI equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnCKI(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert CookieStore__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev Mints a specified amount of CKI tokens to the caller's account.
     * The caller's health factor is checked before and after minting.
     * @param amountCKIToMint The amount of CKI tokens to mint.
     *
     * @notice The amount to mint must be greater than zero.
     * @notice Prevents reentrancy using the nonReentrant modifier.
     */
    function mintCKI(uint256 amountCKIToMint) public moreThanZero(amountCKIToMint) nonReentrant {
        // Increase the caller's minted CKI balance
        CKIMinted[msg.sender] += amountCKIToMint;
        // Check and revert the transaction if the caller's health factor is broken
        revertIfHealthFactorIsBroken(msg.sender);
        // Mint the specified amount of CKI tokens for the caller
        bool minted = i_CKI.mint(msg.sender, amountCKIToMint);

        if (minted != true) {
            revert CookieStore__MintFailed();
        }
    }

    /**
     * @dev Deposits collateral tokens to the contract
     * The transferred collateral tokens are added to the user's collateral balance.
     * @param tokenCollateralAddress The address of the collateral token being deposited.
     * @param amountCollateral The amount of collateral tokens to deposit.
     *
     * @notice The amount of collateral to deposit must be greater than zero.
     * @notice Prevents reentrancy using the nonReentrant modifier.
     * @notice Checks if the provided collateral token address is allowed for deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        // Increase the user's collateral balance for the specified token
        collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // Transfer the collateralized tokens from the user to the contract
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert CookieStore__TransferFailed();
        }
    }

    /**
     * @dev Redeems collateral tokens from the contract and updates user collateral balances.
     * Transfers redeemed collateral tokens from 'from' to 'to'.
     * @param tokenCollateralAddress The address of the collateral token being redeemed.
     * @param amountCollateral The amount of collateral tokens to redeem.
     * @param from The address of the user whose collateral is being redeemed.
     * @param to The address to which the redeemed collateral tokens are transferred.
     */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        // Decrease the 'from' user's collateral balance for the specified token
        collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // Transfer the redeemed collateral tokens from the contract to 'to'
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert CookieStore__TransferFailed();
        }
    }

    /**
     * @dev Burns a specified amount of CKI tokens and updates the user's minted CKI balance.
     * The specified amount of CKI tokens are burned from the 'CKIFrom' account on behalf of 'onBehalfOf'.
     * @param amountCKIToBurn The amount of CKI tokens to burn.
     * @param onBehalfOf The address on whose behalf the CKI tokens are being burned.
     * @param CKIFrom The address from which the CKI tokens are being transferred and burned.
     */
    function _burnCKI(uint256 amountCKIToBurn, address onBehalfOf, address CKIFrom) private {
        // Decrease the 'onBehalfOf' user's minted CKI balance
        CKIMinted[onBehalfOf] -= amountCKIToBurn;
        // Transfer the specified amount of CKI tokens from 'CKIFrom' to the contract and burn them
        bool success = i_CKI.transferFrom(CKIFrom, address(this), amountCKIToBurn);
        if (!success) {
            revert CookieStore__TransferFailed();
        }
        // Burn the transferred CKI tokens
        i_CKI.burn(amountCKIToBurn);
    }

    /**
     * @dev Retrieves the account information for a given user.
     * @param user The address of the user for whom to retrieve the account information.
     * @return totalCKIMinted The total amount of CKI tokens minted by the user.
     * @return collateralValueInUsd The total collateral value in USD for the user's account.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalCKIMinted, uint256 collateralValueInUsd)
    {
        // Retrieve the total amount of CKI tokens minted by the user
        totalCKIMinted = CKIMinted[user];
        // Retrieve the total collateral value in USD for the user's account
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @dev Calculates the health factor for a given user's account.
     * @param user The address of the user for whom to calculate the health factor.
     * @return healthFactor The calculated health factor for the user's account.
     */
    function _healthFactor(address user) private view returns (uint256) {
        // Retrieve the total minted CKI tokens and the collateral value in USD for the user's account
        (uint256 totalCKIMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // Calculate the health factor using the retrieved information
        return _calculateHealthFactor(totalCKIMinted, collateralValueInUsd);
    }

    /**
     * @dev Calculates the USD value of a given amount of a specific token using its price feed.
     * @param token The address of the token for which to calculate the USD value.
     * @param amount The amount of the token for which to calculate the USD value.
     * @return usdValue The calculated USD value of the specified token amount.
     */
    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / 1e18;
    }

    /**
     * @dev Calculates the health factor for a given user's account.
     * @param totalCKIMinted The total amount of CKI tokens minted by the user.
     * @param collateralValueInUsd The total collateral value in USD for the user's account.
     * @return healthFactor The calculated health factor for the user's account.
     */
    function _calculateHealthFactor(uint256 totalCKIMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        // If no CKI tokens are minted, health factor is set to the maximum value
        if (totalCKIMinted == 0) return type(uint256).max;
        // Calculate the collateral value adjusted for the liquidation threshold
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        // Calculate the health factor using the adjusted collateral value and total minted CKI tokens
        return (collateralAdjustedForThreshold * 1e18) / totalCKIMinted;
    }

    /**
     * @dev Reverts the transaction if the user's health factor is below 1e18.
     * Checks the user's health factor and reverts if it's insufficient.
     * @param user The address of the user whose health factor is being checked.
     */
    function revertIfHealthFactorIsBroken(address user) internal view {
        // Get the user's health factor
        uint256 userHealthFactor = _healthFactor(user);
        // Revert if the user's health factor is below 1
        if (userHealthFactor < 1e18) {
            revert CookieStore__BreaksHealthFactor(userHealthFactor);
        }
    }

    function calculateHealthFactor(uint256 totalCKIMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalCKIMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalCKIMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return collateralDeposited[user][token];
    }

    /**
     * @dev Calculates the total collateral value in USD for a given user's account.
     * @param user The address of the user for whom to calculate the collateral value.
     * @return totalCollateralValueInUsd The total value of all authorized collateral tokens deposited by the user in USD.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through all the authorized collateral tokens
        for (uint256 index = 0; index < authorizedCollateralTokens.length; index++) {
            // Get the address of the current authorized collateral token
            address token = authorizedCollateralTokens[index];
            // Retrieve the amount of the current collateral token deposited by the user
            uint256 amount = collateralDeposited[user][token];
            // Calculate the USD value of the current collateral amount
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * 1e18) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return 1e18;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return 1e18;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return authorizedCollateralTokens;
    }

    function getCKI() external view returns (address) {
        return address(i_CKI);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
