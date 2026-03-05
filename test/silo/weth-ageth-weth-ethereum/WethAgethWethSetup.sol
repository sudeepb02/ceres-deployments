// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {LeveragedStrategyBaseSetup} from "../../common/LeveragedStrategyBaseSetup.sol";

import {IOracleAdapter} from "ceres-strategies/src/interfaces/periphery/IOracleAdapter.sol";
import {ILeveragedStrategy} from "ceres-strategies/src/interfaces/strategies/ILeveragedStrategy.sol";

import {ISilo, ISiloConfig, ISiloLens, LeveragedSilo} from "ceres-strategies/src/strategies/LeveragedSilo.sol";
import {ISiloOracle} from "ceres-strategies/src/interfaces/silo/ISiloOracle.sol";
import {SiloAdapterTypeOne} from "ceres-strategies/src/periphery/SiloAdapterTypeOne.sol";

import {CeresSwapper} from "ceres-strategies/src/periphery/CeresSwapper.sol";
import {RoleManager} from "ceres-strategies/src/periphery/RoleManager.sol";
import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";

import {MockPriceOracle} from "test/common/MockPriceOracle.sol";

/// @title WethAgethWethSetup
/// @notice Silo-specific test setup inheriting from LeveragedStrategyBaseSetup
contract WethAgethWethSetup is LeveragedStrategyBaseSetup {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   STRATEGY-SPECIFIC CONSTANTS                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Tokens
    address public constant WETH_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant AGETH_TOKEN = 0xe1B4d34E8754600962Cd944B535180Bd758E6c2e;
    address public constant USD_TOKEN = 0x0000000000000000000000000000000000000348; // synthetic USD representation

    // Silo contracts
    address public constant SILO_LENS = SILO_LENS_ETHEREUM;
    address public constant SILO_CONFIG = 0xF8D32Da4Ad9378C3754CE846BE02654e52b2C09d;
    address public constant DEPOSIT_SILO = 0xe394050D179b72197A458Fdfb962Ae69908Aa5A0;
    address public constant BORROW_SILO = 0x5B3E7d6795bB8670A88d64BbF7ca1CCA69F1f69c;

    address public constant COLLATERAL_TO_ASSET_ORACLE = EULER_ROUTER_ETHEREUM;
    address public constant COLLATERAL_TO_DEBT_ORACLE = 0x69B19191DE88afE17c1Ae56af213C22D3EFD1607; // Deposit Silo

    address public constant KYBER_SCALE_HELPER = KYBER_SCALE_HELPER_ETHEREUM;
    address public constant KYBERSWAP_ROUTER = KYBERSWAP_ROUTER_ETHEREUM;
    address public constant AUGUSTUS_REGISTRY = AUGUSTUS_REGISTRY_ETHEREUM;
    address public constant AUGUSTUS_SWAPPER = AUGUSTUS_SWAPPER_ETHEREUM;

    FlashLoanRouter.FlashSource public FLASH_LOAN_SOURCE = FlashLoanRouter.FlashSource.ERC3156;
    address public constant FLASH_LOAN_PROVIDER = BORROW_SILO;

    // Token decimals
    uint8 public constant WETH_TOKEN_DECIMALS = 18;
    uint8 public constant AGETH_TOKEN_DECIMALS = 18;

    // Final strategy constants used throughout the tests
    address public constant ASSET_TOKEN = WETH_TOKEN;
    address public constant COLLATERAL_TOKEN = AGETH_TOKEN;
    address public constant DEBT_TOKEN = WETH_TOKEN;

    uint8 public constant ASSET_DECIMALS = WETH_TOKEN_DECIMALS;
    uint8 public constant COLLATERAL_TOKEN_DECIMALS = AGETH_TOKEN_DECIMALS;
    uint8 public constant DEBT_TOKEN_DECIMALS = WETH_TOKEN_DECIMALS;

    uint256 constant ORACLE_PRECISION = 1e18;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   SILO-SPECIFIC CONTRACTS                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Euler infrastructure
    ISilo public depositSilo;
    ISilo public borrowSilo;
    ISiloLens public siloLens;
    ISiloConfig public siloConfig;

    ISiloOracle public oracleDepositSilo;
    ISiloOracle public oracleBorrowSilo;

    SiloAdapterTypeOne public siloOracleAdapter;

    MockPriceOracle public mockCollateralToAssetOracle;
    MockPriceOracle public mockAssetToUsdOracle;
    MockPriceOracle public mockDebtToUsdOracle;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   SETUP OVERRIDE                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Setup function - calls parent setUp which invokes all abstract implementations
    function setUp() public virtual override {
        string memory chainUrl = vm.envString("RPC_CHAINID_1");
        if (bytes(chainUrl).length == 0) {
            revert("RPC_CHAINID_1 env var not set");
            chainUrl = "https://rpc.flashbots.net";
        }

        vm.createSelectFork(chainUrl);

        super.setUp();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                           IMPLEMENT ABSTRACT FUNCTIONS                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _setStrategyTokens() internal override {
        // Set base contract references
        assetToken = IERC20(ASSET_TOKEN);
        collateralToken = IERC20(COLLATERAL_TOKEN);
        debtToken = IERC20(DEBT_TOKEN);
    }

    function _setupProtocolContracts() internal override {
        siloLens = ISiloLens(SILO_LENS);
        siloConfig = ISiloConfig(SILO_CONFIG);

        depositSilo = ISilo(DEPOSIT_SILO);
        borrowSilo = ISilo(BORROW_SILO);

        oracleDepositSilo = ISiloOracle(siloConfig.getConfig(DEPOSIT_SILO).solvencyOracle);
        oracleBorrowSilo = ISiloOracle(siloConfig.getConfig(BORROW_SILO).solvencyOracle);

        console.log("Deposit silo oracle:", address(oracleDepositSilo));
        console.log("Borrow silo oracle:", address(oracleBorrowSilo));
    }

    function _setupOracleAdapter() internal override {
        siloOracleAdapter = new SiloAdapterTypeOne(
            ORACLE_PRECISION,
            address(oracleDepositSilo), // collateral to asset oracle: agETH -> WETH
            address(oracleDepositSilo), // collateral to debt oracle: agETH -> WETH
            ASSET_TOKEN,
            COLLATERAL_TOKEN,
            DEBT_TOKEN
        );

        // Set base contract reference
        oracleAdapter = IOracleAdapter(address(siloOracleAdapter));

        console.log("Euler Oracle Adapter deployed at:", address(siloOracleAdapter));

        // Setup mock oracle contracts for testing price changes
        // console.log("Setting up mock oracles for testing...");
    }

    function _setupSwapper() internal override {
        swapper = new CeresSwapper(CERES_DEPLOYER, KYBER_SCALE_HELPER, AUGUSTUS_REGISTRY);

        CeresSwapper.SwapProvider memory kyberswapProvider = CeresSwapper.SwapProvider({
            swapType: CeresSwapper.SwapType.KYBERSWAP_AGGREGATOR,
            router: KYBERSWAP_ROUTER
        });

        // CeresSwapper.SwapProvider memory paraswapProvider = CeresSwapper.SwapProvider({
        //     swapType: CeresSwapper.SwapType.PARASWAP_AGGREGATOR,
        //     router: AUGUSTUS_SWAPPER
        // });

        vm.startPrank(management);
        swapper.setSwapProvider(address(collateralToken), address(debtToken), kyberswapProvider);
        swapper.setSwapProvider(address(debtToken), address(collateralToken), kyberswapProvider);

        swapper.setSwapProvider(address(assetToken), address(collateralToken), kyberswapProvider);
        swapper.setSwapProvider(address(collateralToken), address(assetToken), kyberswapProvider);

        vm.stopPrank();
    }

    function _deployRoleManager() internal override {
        roleManager = new RoleManager(2 days, management);

        vm.startPrank(management);
        roleManager.grantRole(MANAGEMENT_ROLE, management);
        roleManager.grantRole(KEEPER_ROLE, keeper);
        vm.stopPrank();
    }

    function _deployStrategy() internal override {
        vm.startPrank(management);

        address deployedStrategy = Upgrades.deployTransparentProxy(
            "LeveragedSilo.sol:LeveragedSilo",
            management,
            abi.encodeCall(
                LeveragedSilo.initialize,
                (
                    ASSET_TOKEN,
                    "Ceres Leveraged Silo Strategy",
                    "ceres-WETH-agETH-WETH",
                    COLLATERAL_TOKEN,
                    DEBT_TOKEN,
                    SILO_LENS,
                    SILO_CONFIG,
                    true,
                    address(roleManager)
                )
            )
        );
        console.log("Strategy deployed at:", deployedStrategy);
        strategy = ILeveragedStrategy(deployedStrategy);

        strategy.setPerformanceFeeRecipient(feeReceiver);

        vm.stopPrank();
    }

    function _deployFlashLoanRouter() internal override {
        vm.startPrank(management);
        flashLoanRouter = new FlashLoanRouter(address(roleManager));
        vm.stopPrank();
    }

    function _configureFlashLoanRouter() internal override {
        vm.prank(management);
        flashLoanRouter.setFlashConfig(address(strategy), FLASH_LOAN_SOURCE, FLASH_LOAN_PROVIDER, true);
    }

    function _initializeStrategy() internal override {
        vm.startPrank(management);

        // Set periphery contracts, for initial setup there is no timelock
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(siloOracleAdapter));
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(swapper));
        strategy.requestUpdate(strategy.FLASH_LOAN_ROUTER_KEY(), address(flashLoanRouter));

        // Set LTV parameters
        strategy.updateConfig(MAX_SLIPPAGE_BPS, DEFAULT_PERFORMANCE_FEE_BPS, MAX_LOSS_BPS);
        strategy.setTargetLtv(TARGET_LTV_BPS, LTV_BUFFER_BPS);
        strategy.setDepositWithdrawLimits(DEPOSIT_LIMIT, REDEEM_LIMIT_SHARES, 0);

        vm.stopPrank();
    }

    function _addProtocolLiquidity() internal override {
        // uint256 amountCollateralToken = 100_000_000 * 10 ** COLLATERAL_TOKEN_DECIMALS;
        // uint256 amountDebtToken = 500_000_000 * 10 ** DEBT_TOKEN_DECIMALS;
        // deal(COLLATERAL_TOKEN, liquidityProvider, amountCollateralToken);
        // deal(DEBT_TOKEN, liquidityProvider, amountDebtToken);
        // vm.startPrank(liquidityProvider);
        // collateralToken.approve(address(collateralVault), amountCollateralToken);
        // collateralVault.deposit(amountCollateralToken, liquidityProvider);
        // debtToken.approve(address(borrowVault), amountDebtToken);
        // borrowVault.deposit(amountDebtToken, liquidityProvider);
        // vm.stopPrank();
    }

    function _simulateCollateralPriceChange(int256 percentChange) internal override {
        // @todo
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    LABEL ADDRESSES                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _labelAddresses() internal override {
        vm.label(address(ASSET_TOKEN), "ASSET_TOKEN");
        vm.label(address(DEBT_TOKEN), "DEBT_TOKEN");
        vm.label(address(COLLATERAL_TOKEN), "COLLATERAL_TOKEN");
        vm.label(address(depositSilo), "Deposit Silo");
        vm.label(address(borrowSilo), "Borrow Silo");
        vm.label(address(siloLens), "Silo Lens");
        vm.label(address(siloConfig), "Silo Config");

        vm.label(address(oracleDepositSilo), "oracleDepositSilo");
        vm.label(address(oracleBorrowSilo), "oracleBorrowSilo");

        vm.label(address(siloOracleAdapter), "Silo Oracle Adapter");
        vm.label(address(swapper), "Ceres Swapper");
        vm.label(address(strategy), "LeveragedSilo Strategy");
    }
}
