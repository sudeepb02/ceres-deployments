// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {LeveragedStrategyBaseSetup} from "../../common/LeveragedStrategyBaseSetup.sol";

import {IEVault} from "ceres-strategies/src/interfaces/euler/IEVault.sol";
import {IEVC} from "ceres-strategies/src/interfaces/euler/IEVC.sol";
import {IEulerOracle} from "ceres-strategies/src/interfaces/euler/IEulerOracle.sol";
import {IOracleAdapter} from "ceres-strategies/src/interfaces/periphery/IOracleAdapter.sol";
import {ILeveragedStrategy} from "ceres-strategies/src/interfaces/strategies/ILeveragedStrategy.sol";

import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {EulerAdapterTypeOne as EulerOracleAdapter} from "ceres-strategies/src/periphery/EulerAdapterTypeOne.sol";
import {CeresSwapper} from "ceres-strategies/src/periphery/CeresSwapper.sol";
import {RoleManager} from "ceres-strategies/src/periphery/RoleManager.sol";
import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";

import {MockPriceOracle} from "test/common/MockPriceOracle.sol";

/// @title UsdfSusdfUsdcSetup
/// @notice Euler-specific test setup inheriting from LeveragedStrategyBaseSetup
contract UsdfSusdfUsdcSetup is LeveragedStrategyBaseSetup {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   STRATEGY-SPECIFIC CONSTANTS                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Tokens
    address public constant USDF_TOKEN = 0xFa2B947eEc368f42195f24F36d2aF29f7c24CeC2;
    address public constant SUSDF_TOKEN = 0xc8CF6D7991f15525488b2A83Df53468D682Ba4B0;
    address public constant USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USD_TOKEN = 0x0000000000000000000000000000000000000348; // synthetic USD representation

    // Euler contracts
    address public constant EVC = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;
    address public constant COLLATERAL_VAULT = 0x2F849ba554C1ea2eDe9C240Bbe9d247dd6eC8A6B;
    address public constant DEBT_VAULT = 0x3573A84Bee11D49A1CbCe2b291538dE7a7dD81c6;

    address public constant COLLATERAL_TO_ASSET_ORACLE = 0x1ada463F00833545b33A1B6551d0954Ba32be1fc;
    address public constant ASSET_TO_USD_ORACLE = 0xEd8e9151602E40233D358d6C323d9F9717a1bec4;
    address public constant DEBT_TO_USD_ORACLE = 0xD35657aE033A86FFa8fc6Bc767C5eb57C7c3D4B8;

    address public constant KYBER_SCALE_HELPER = KYBER_SCALE_HELPER_ETHEREUM;
    address public constant KYBERSWAP_ROUTER = KYBERSWAP_ROUTER_ETHEREUM;
    address public constant AUGUSTUS_REGISTRY = AUGUSTUS_REGISTRY_ETHEREUM;
    address public constant AUGUSTUS_SWAPPER = AUGUSTUS_SWAPPER_ETHEREUM;

    // address public constant EULER_FLASH_LOAN_PROVIDER = 0x3573A84Bee11D49A1CbCe2b291538dE7a7dD81c6; // Euler Debt vault
    FlashLoanRouter.FlashSource public FLASH_LOAN_SOURCE = FlashLoanRouter.FlashSource.ERC3156;
    address public constant FLASH_LOAN_PROVIDER = SILO_USDC_FLASH_LOAN_PROVIDER;

    // Token decimals
    uint8 public constant USDF_TOKEN_DECIMALS = 18;
    uint8 public constant SUSDF_TOKEN_DECIMALS = 18;
    uint8 public constant USDC_TOKEN_DECIMALS = 6;

    // Final strategy constants used throughout the tests
    address public constant ASSET_TOKEN = USDF_TOKEN;
    address public constant COLLATERAL_TOKEN = SUSDF_TOKEN;
    address public constant DEBT_TOKEN = USDC_TOKEN;

    uint8 public constant ASSET_DECIMALS = USDF_TOKEN_DECIMALS;
    uint8 public constant COLLATERAL_TOKEN_DECIMALS = SUSDF_TOKEN_DECIMALS;
    uint8 public constant DEBT_TOKEN_DECIMALS = USDC_TOKEN_DECIMALS;

    uint256 constant ORACLE_PRECISION = 1e18;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   EULER-SPECIFIC CONTRACTS                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Euler infrastructure
    IEVault public collateralVault;
    IEVault public borrowVault;
    IEVC public evc;

    // IEulerOracle public eulerOracle = IEulerOracle(EULER_ORACLE_ROUTER); // Euler oracle router address

    EulerOracleAdapter public eulerOracleAdapter;

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
        evc = IEVC(EVC);

        // Deploy EVaults
        collateralVault = IEVault(COLLATERAL_VAULT);

        borrowVault = IEVault(DEBT_VAULT);

        // Deploy oracle and set prices
        // eulerOracle = IEulerOracle(EULER_ORACLE_ROUTER);
    }

    function _setupOracleAdapter() internal override {
        eulerOracleAdapter = new EulerOracleAdapter(
            ORACLE_PRECISION,
            COLLATERAL_TO_ASSET_ORACLE,
            ASSET_TO_USD_ORACLE,
            DEBT_TO_USD_ORACLE,
            ASSET_TOKEN,
            COLLATERAL_TOKEN,
            DEBT_TOKEN,
            USD_TOKEN
        );

        // Set base contract reference
        oracleAdapter = IOracleAdapter(address(eulerOracleAdapter));

        console.log("Euler Oracle Adapter deployed at:", address(eulerOracleAdapter));

        // Setup mock oracle contracts for testing price changes
        console.log("Setting up mock oracles for testing...");

        {
            // Mock collateral to asset oracle
            mockCollateralToAssetOracle = new MockPriceOracle(
                eulerOracleAdapter.getCollateralPriceInAssetToken(),
                0,
                COLLATERAL_TOKEN,
                ASSET_TOKEN
            );
        }

        {
            // Mock asset to USD oracle
            mockAssetToUsdOracle = new MockPriceOracle(
                eulerOracleAdapter.getAssetPriceInUsd(),
                0,
                ASSET_TOKEN,
                USD_TOKEN
            );
        }

        {
            // Mock debt to USD oracle
            mockDebtToUsdOracle = new MockPriceOracle(eulerOracleAdapter.getDebtPriceInUsd(), 0, DEBT_TOKEN, USD_TOKEN);
        }
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
            "LeveragedEuler.sol:LeveragedEuler",
            management,
            abi.encodeCall(
                LeveragedEuler.initialize,
                (
                    ASSET_TOKEN,
                    "Ceres Leveraged Euler Strategy",
                    "ceres-USDf-sUSDf-USDC",
                    COLLATERAL_TOKEN,
                    DEBT_TOKEN,
                    COLLATERAL_VAULT,
                    DEBT_VAULT,
                    address(evc),
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
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(eulerOracleAdapter));
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(swapper));
        strategy.requestUpdate(strategy.FLASH_LOAN_ROUTER_KEY(), address(flashLoanRouter));

        // Set LTV parameters
        strategy.updateConfig(MAX_SLIPPAGE_BPS, 15_00, 5_00);
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
        vm.label(address(collateralVault), "Collateral Vault");
        vm.label(address(borrowVault), "Borrow Vault");
        vm.label(address(evc), "EVC");
        vm.label(address(COLLATERAL_TO_ASSET_ORACLE), "COLLATERAL_TO_ASSET_ORACLE");
        vm.label(address(ASSET_TO_USD_ORACLE), "ASSET_TO_USD_ORACLE");
        vm.label(address(DEBT_TO_USD_ORACLE), "DEBT_TO_USD_ORACLE");

        vm.label(address(eulerOracleAdapter), "Euler Oracle Adapter");
        vm.label(address(swapper), "Ceres Swapper");
        vm.label(address(strategy), "LeveragedEuler Strategy");
    }
}
