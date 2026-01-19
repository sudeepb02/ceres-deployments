// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test, console, console2} from "forge-std/src/Test.sol";

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ILeveragedStrategy} from "ceres-strategies/src/interfaces/strategies/ILeveragedStrategy.sol";
import {IOracleAdapter} from "ceres-strategies/src/interfaces/periphery/IOracleAdapter.sol";
import {ICeresSwapper} from "ceres-strategies/src/interfaces/periphery/ICeresSwapper.sol";

import {CeresSwapper} from "ceres-strategies/src/periphery/CeresSwapper.sol";
import {TokenizedStrategyFactory, TokenizedStrategy} from "ceres-strategies/src/periphery/TokenizedStrategyFactory.sol";

/// @title LeveragedStrategyBaseSetup
/// @notice Common test infrastructure for all LeveragedStrategy implementations
/// @dev Protocol-specific test setups should inherit from this and implement abstract functions
abstract contract LeveragedStrategyBaseSetup is Test {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CONSTANTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    address public constant CERES_DEPLOYER = 0xB9F4A819183BeFC31E282BC02D33cc1ab985Aa03;

    uint256 constant BPS_PRECISION = 10_000;

    // LTV parameters - common across all protocols
    uint16 constant TARGET_LTV_BPS = 7000; // 70%
    uint256 constant MAX_LTV_BPS = 7500; // 75%
    uint256 constant MIN_LTV_BPS = 6500; // 65%
    uint16 constant MAX_SLIPPAGE_BPS = 25; // 0.25%
    uint96 constant DEPOSIT_LIMIT = 10_000_000 * 1e18; // 10 million
    uint96 constant WITHDRAW_LIMIT = type(uint96).max;

    // Common contract addresses
    address public constant KYBER_SCALE_HELPER = 0x2f577A41BeC1BE1152AeEA12e73b7391d15f655D;
    address public constant KYBERSWAP_ROUTER_AVAX = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;

    
    address public constant AUGUSTUS_SWAPPER_V6 = 0x6A000F20005980200259B80c5102003040001068;
    address public constant AUGUSTUS_REGISTRY = 0xdC6E2b14260F972ad4e5a31c68294Fba7E720701;
    address public constant AUGUSTUS_REGISTRY_AVAX = 0xfD1E5821F07F1aF812bB7F3102Bfd9fFb279513a;

    // Default test amounts (helper functions to account for different decimals)
    function DEFAULT_DEPOSIT() internal view returns (uint256) {
        return 10_000 * 10 ** IERC20Metadata(address(assetToken)).decimals();
    }

    function LARGE_DEPOSIT() internal view returns (uint256) {
        return 1_000_000 * 10 ** IERC20Metadata(address(assetToken)).decimals();
    }

    function SMALL_DEPOSIT() internal view returns (uint256) {
        return 100 * 10 ** IERC20Metadata(address(assetToken)).decimals();
    }

    /**
     * @dev This is the address of the TokenizedStrategy implementation
     * contract that will be used by all strategies to handle the
     * accounting, logic, storage etc.
     */
    address internal constant TOKENIZED_STRATEGY_IMPL = 0xD377919FA87120584B21279a491F82D5265A139c;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CONTRACTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Core strategy - set by protocol-specific setup
    ILeveragedStrategy public strategy;

    // Oracle adapter - set by protocol-specific setup
    IOracleAdapter public oracleAdapter;

    // Swapper - set by protocol-specific setup
    CeresSwapper public swapper;

    // Asset token - set by protocol-specific setup
    IERC20 public assetToken;

    // Collateral token- set by protocol-specific setup
    IERC20 public collateralToken;

    // Debt token - set by protocol-specific setup
    IERC20 public debtToken;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    TEST ACCOUNTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    address public management;
    address public keeper;
    address public user1;
    address public user2;
    address public feeReceiver;
    address public liquidityProvider;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       EVENTS                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Re-declare events for expectEmit
    event Rebalance(address indexed keeper, uint256 debtAmount, bool isLeverageUp);
    event RebalanceUsingFlashLoan(address indexed keeper, uint256 debtAmount, bool isLeverageUp);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       SETUP                                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function setUp() public virtual {
        // Setup test accounts
        management = CERES_DEPLOYER;
        keeper = makeAddr("keeper");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        liquidityProvider = makeAddr("liquidityProvider");
        feeReceiver = makeAddr("feeReceiver");

        // Ensure TokenizedStrategy implementation exists
        _ensureTokenizedStrategyImplementation();

        // Protocol-specific setup (implemented by child contracts)
        _setStrategyTokens();

        _setupProtocolContracts();
        _setupOracleAdapter();
        _setupSwapper();
        _deployStrategy();
        _initializeStrategy();
        _addProtocolLiquidity();
        _labelAddresses();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              ABSTRACT FUNCTIONS (Protocol-specific)                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Set asset, collateral and debt tokens for the protocol
    function _setStrategyTokens() internal virtual;

    /// @notice Setup protocol-specific contracts (Morpho, Euler vaults, Silo, etc.)
    function _setupProtocolContracts() internal virtual;

    /// @notice Setup the oracle adapter
    function _setupOracleAdapter() internal virtual;

    /// @notice Setup the swapper with exchange rates
    function _setupSwapper() internal virtual;

    /// @notice Deploy the protocol-specific strategy
    function _deployStrategy() internal virtual;

    /// @notice Initialize the strategy with configuration
    function _initializeStrategy() internal virtual;

    /// @notice Add liquidity to protocol for borrowing
    function _addProtocolLiquidity() internal virtual;

    /// @notice Label addresses for debugging
    function _labelAddresses() internal virtual;

    /// @notice Simulate interest accrual (protocol-specific)
    /// @param interestRateBpsCollateral Collateral yield in BPS
    /// @param interestRateBpsDebt Debt interest in BPS
    /// @param timeElapsed Time elapsed in seconds
    function _simulateInterestAccrual(
        uint256 interestRateBpsCollateral,
        uint256 interestRateBpsDebt,
        uint256 timeElapsed
    ) internal virtual;

    /// @notice Simulate price change (protocol-specific due to oracle differences)
    /// @param percentChange Percent change (positive or negative)
    function _simulatePriceChange(int256 percentChange) internal virtual;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  COMMON HELPER FUNCTIONS                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Mint tokens to an address
    function _mintTokens(address token, address to, uint256 amount) internal {
        deal(token, to, amount);
    }

    /// @notice Mint and approve tokens
    function _mintAndApprove(address token, address owner, address spender, uint256 amount) internal {
        deal(token, owner, amount);
        vm.prank(owner);
        IERC20(token).approve(spender, amount);
    }

    /// @notice Setup user with tokens and deposits to strategy
    function _setupUserDeposit(address user, uint256 depositAmount) internal returns (uint256 shares) {
        _mintAndApprove(address(assetToken), user, address(strategy), depositAmount);

        vm.prank(user);
        shares = strategy.deposit(depositAmount, user);
    }

    /// @notice Setup strategy with initial leverage position
    function _setupInitialLeveragePosition(uint256 initialDeposit) internal {
        // User deposits initial funds
        _setupUserDeposit(user1, initialDeposit);

        // Asset and collateral are same (IS_ASSET_COLLATERAL = true)
        uint256 debtAmount = strategy.computeTargetDebt(initialDeposit, TARGET_LTV_BPS);

        // Mint debt tokens for keeper to perform initial leverage
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        // bytes memory swapData = _getParaswapSwapData(
        //     block.chainid,
        //     address(debtToken),
        //     address(collateralToken),
        //     debtAmount,
        //     "exactIn"
        // );
        bytes memory swapData = _getKyberswapSwapData(
            block.chainid,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        // Keeper performs initial leverage
        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);
    }

    /// @notice Helper to get balance
    function _balance(address token, address account) internal view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    /// @notice Get strategy's current leverage ratio
    function _getCurrentLeverage() internal view returns (uint256 leverageRatio) {
        (uint256 netAssets, uint256 totalCollateral, ) = strategy.getNetAssets();

        if (netAssets == 0) return 0;

        // Leverage = (Collateral / NetAssets)
        // Convert to BPS: leverage * 10000
        uint256 collateralInAssets = oracleAdapter.convertCollateralToAssets(totalCollateral);
        leverageRatio = (collateralInAssets * BPS_PRECISION) / netAssets;
    }

    /// @notice Calculate expected LTV
    function _calculateLtv(uint256 collateralAmount, uint256 debtAmount) internal view returns (uint256 ltv) {
        if (collateralAmount == 0) return 0;

        uint256 collateralValue = oracleAdapter.convertCollateralToDebt(collateralAmount);
        ltv = (debtAmount * BPS_PRECISION) / collateralValue;
    }

    /// @notice Helper to assert approximate equality with basis points tolerance
    function _assertApproxEqBps(uint256 a, uint256 b, uint256 toleranceBps, string memory message) internal pure {
        uint256 diff = a > b ? a - b : b - a;
        uint256 tolerance = (b * toleranceBps) / BPS_PRECISION;

        if (diff > tolerance) {
            revert(message);
        }
    }

    /// @notice Get strategy state for debugging
    function _logStrategyState(string memory label) internal view {
        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();
        uint256 leverage = _getCurrentLeverage();
        uint256 ltv = _calculateLtv(totalCollateral, totalDebt);

        console2.log("=== Strategy State:", label, "===");
        console2.log("Net Assets:", netAssets);
        console2.log("Total Collateral:", totalCollateral);
        console2.log("Total Debt:", totalDebt);
        console2.log("Leverage Ratio (BPS):", leverage);
        console2.log("LTV (BPS):", ltv);
        console2.log("Asset Balance:", _balance(address(assetToken), address(strategy)));
        console2.log("Debt Balance:", _balance(address(debtToken), address(strategy)));
        console2.log("=====================================");
    }

    /// @dev Ensures the shared TokenizedStrategy implementation is available for delegatecalls.
    function _ensureTokenizedStrategyImplementation() internal {
        address impl = TOKENIZED_STRATEGY_IMPL;
        uint256 size;
        assembly {
            size := extcodesize(impl)
        }

        if (size == 0) {
            TokenizedStrategyFactory factory = new TokenizedStrategyFactory(management, 0, management);
            TokenizedStrategy deployedImpl = TokenizedStrategy(factory.deployImplementation());
            bytes memory runtimeCode = address(deployedImpl).code;
            vm.etch(impl, runtimeCode);
            vm.label(impl, "TokenizedStrategyImplementation");
            assembly {
                size := extcodesize(impl)
            }
        }
        assertGt(size, 0, "!TokenizedStrategy");
    }

    /*//////////////////////////////////////////////////////////////
                        AGGREGATOR HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Build swap calldata via node helper scripts (Kyber/Paraswap)
    function _getAggregatorSwapData(
        string memory script,
        uint256 chainId,
        address fromToken,
        address toToken,
        uint256 amount,
        address swapperAddress,
        string memory swapType,
        uint8 fromTokenDecimals,
        uint8 toTokenDecimals
    ) internal returns (bytes memory) {}

    /// @notice Build Kyberswap swap data (exactIn)
    function _getKyberswapSwapData(
        uint256 chainId,
        address fromToken,
        address toToken,
        uint256 amount
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](8);
        inputs[0] = "node";
        inputs[1] = "script/js/kyber/printKyberswapSwapData.js";
        inputs[2] = vm.toString(chainId);
        inputs[3] = vm.toString(fromToken);
        inputs[4] = vm.toString(toToken);
        inputs[5] = vm.toString(amount);
        inputs[6] = vm.toString(address(swapper));
        inputs[7] = "exactIn";

        return vm.ffi(inputs);
    }

    /// @notice Build Paraswap swap data (supports exactIn/exactOut)
    function _getParaswapSwapData(
        uint256 chainId,
        address fromToken,
        address toToken,
        uint256 amount,
        string memory swapType
    ) internal returns (bytes memory) {
        console.log("Getting Paraswap swap data:");
        console.log("Chain ID:", chainId);
        console.log("From Token:", fromToken);
        console.log("To Token:", toToken);
        console.log("Amount:", amount);
        console.log("Swap Type:", swapType);

        uint8 fromTokenDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toTokenDecimals = IERC20Metadata(toToken).decimals();

        string[] memory inputs = new string[](10);
        inputs[0] = "node";
        inputs[1] = "script/js/paraswap/printParaswapSwapData.js";
        inputs[2] = vm.toString(chainId);
        inputs[3] = vm.toString(fromToken);
        inputs[4] = vm.toString(toToken);
        inputs[5] = vm.toString(amount);
        inputs[6] = vm.toString(address(swapper));
        inputs[7] = swapType;
        inputs[8] = vm.toString(fromTokenDecimals);
        inputs[9] = vm.toString(toTokenDecimals);

        return vm.ffi(inputs);
    }

    /// @notice Rebalance using Kyberswap aggregator (exactIn only)
    function _rebalanceWithKyberAggregator(uint256 chainId, uint256 debtAmount) internal {
        // Kyber path is exactIn: DEBT -> COLLATERAL for leverage up
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            chainId,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);
    }

    /// @notice Rebalance using Paraswap aggregator (exactIn for leverage up, exactOut for leverage down)
    function _rebalanceWithParaswapAggregator(uint256 chainId, uint256 debtAmount, bool isLeverageUp) internal {
        // Strategy expects debt tokens transferred from caller
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        address fromToken = isLeverageUp ? address(debtToken) : address(collateralToken);
        address toToken = isLeverageUp ? address(collateralToken) : address(debtToken);
        string memory swapType = isLeverageUp ? "exactIn" : "exactOut";

        bytes memory swapData = _getParaswapSwapData(chainId, fromToken, toToken, debtAmount, swapType);

        vm.prank(keeper);
        strategy.rebalance(debtAmount, isLeverageUp, swapData);
    }
}
