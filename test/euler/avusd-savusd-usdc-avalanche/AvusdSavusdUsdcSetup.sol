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

/// @title AvusdSavusdUsdcSetup
/// @notice Euler-specific test setup inheriting from LeveragedStrategyBaseSetup
contract AvusdSavusdUsdcSetup is LeveragedStrategyBaseSetup {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   STRATEGY-SPECIFIC CONSTANTS                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Tokens
    address public constant AVUSD_TOKEN = 0x24dE8771bC5DdB3362Db529Fc3358F2df3A0E346;
    address public constant SAVUSD_TOKEN = 0x06d47F3fb376649c3A9Dafe069B3D6E35572219E;
    address public constant USDC_TOKEN = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address public constant USD_TOKEN = 0x0000000000000000000000000000000000000348; // synthetic USD representation

    // Euler contracts
    address public constant EVC = 0xddcbe30A761Edd2e19bba930A977475265F36Fa1;
    address public constant COLLATERAL_VAULT = 0xbaC3983342b805E66F8756E265b3B0DdF4B685Fc; // Collateral vault
    address public constant DEBT_VAULT = 0x37ca03aD51B8ff79aAD35FadaCBA4CEDF0C3e74e; // Debt vault

    address public constant COLLATERAL_TO_ASSET_ORACLE = 0x3d14C2c22fFfB6fD00759451A7656A052B705B98;
    address public constant ASSET_TO_USD_ORACLE = 0xB92B9341be191895e8C68b170aC4528839fFe0b2;
    address public constant DEBT_TO_USD_ORACLE = 0x997d72fb46690f304C7DB92df9AA823323fb23B2;

    address public constant KYBER_SCALE_HELPER = KYBER_SCALE_HELPER_AVAX;
    address public constant KYBERSWAP_ROUTER = KYBERSWAP_ROUTER_AVAX;
    address public constant AUGUSTUS_REGISTRY = AUGUSTUS_REGISTRY_AVAX;
    address public constant AUGUSTUS_SWAPPER = AUGUSTUS_SWAPPER_AVAX;

    address public constant EULER_FLASH_LOAN_PROVIDER = address(0); // TODO: Populate this address

    // Token decimals
    uint8 public constant AVUSD_TOKEN_DECIMALS = 18;
    uint8 public constant SAVUSD_TOKEN_DECIMALS = 18;
    uint8 public constant USDC_TOKEN_DECIMALS = 6;

    // Final strategy constants used throughout the tests
    address public constant ASSET_TOKEN = AVUSD_TOKEN;
    address public constant COLLATERAL_TOKEN = SAVUSD_TOKEN;
    address public constant DEBT_TOKEN = USDC_TOKEN;

    uint8 public constant ASSET_DECIMALS = AVUSD_TOKEN_DECIMALS;
    uint8 public constant COLLATERAL_TOKEN_DECIMALS = SAVUSD_TOKEN_DECIMALS;
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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   SETUP OVERRIDE                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Setup function - calls parent setUp which invokes all abstract implementations
    function setUp() public virtual override {
        string memory chainUrl = vm.envString("RPC_CHAINID_43114");
        if (bytes(chainUrl).length == 0) {
            revert("RPC_CHAINID_43114 env var not set");
            chainUrl = "https://1rpc.io/avax/c";
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
    }

    function _setupSwapper() internal override {
        swapper = new CeresSwapper(CERES_DEPLOYER, KYBER_SCALE_HELPER, AUGUSTUS_REGISTRY);

        CeresSwapper.SwapProvider memory kyberswapProvider = CeresSwapper.SwapProvider({
            swapType: CeresSwapper.SwapType.KYBERSWAP_AGGREGATOR,
            router: KYBERSWAP_ROUTER
        });

        CeresSwapper.SwapProvider memory paraswapProvider = CeresSwapper.SwapProvider({
            swapType: CeresSwapper.SwapType.PARASWAP_AGGREGATOR,
            router: AUGUSTUS_SWAPPER
        });

        vm.startPrank(management);
        swapper.setSwapProvider(address(collateralToken), address(debtToken), paraswapProvider);
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
                    "ceres-avUSD-USDC",
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
        flashLoanRouter.setFlashConfig(
            address(strategy),
            FlashLoanRouter.FlashSource.EULER,
            address(borrowVault),
            true
        );
    }

    function _initializeStrategy() internal override {
        vm.startPrank(management);

        // Set periphery contracts, for initial setup there is no timelock
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(eulerOracleAdapter));
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(swapper));
        strategy.requestUpdate(strategy.FLASH_LOAN_ROUTER_KEY(), address(flashLoanRouter));

        // Set LTV parameters
        strategy.setTargetLtv(TARGET_LTV_BPS, LTV_BUFFER_BPS);
        strategy.updateConfig(MAX_SLIPPAGE_BPS, 15_00, 0);
        strategy.setDepositWithdrawLimits(DEPOSIT_LIMIT, REDEEM_LIMIT_SHARES, 0);

        // Paraswap exactOut is registered for collateral->debt swaps in _setupSwapper,
        // so enable exactOut mode to keep swap data generation and router selection in sync.
        strategy.setExactOutSwapEnabled(true);

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
        // Deploy a fresh mock with the percentage change baked in as an immutable.
        // This is required because vm.mockFunction executes the mock's bytecode in the storage
        // context of the callee (Euler Router). Immutables are embedded in bytecode so they are
        // unaffected by the storage context switch, whereas mutable state variables would read
        // from the callee's storage slots and return unexpected values.
        MockPriceOracle mockOracle = new MockPriceOracle(
            eulerOracleAdapter.getCollateralPriceInAssetToken(),
            0,
            COLLATERAL_TOKEN,
            ASSET_TOKEN,
            percentChange
        );
        vm.mockFunction(
            COLLATERAL_TO_ASSET_ORACLE,
            address(mockOracle),
            abi.encodeWithSelector(IEulerOracle.getQuote.selector)
        );
    }

    function tearDown() public virtual {
        vm.clearMockedCalls();
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
