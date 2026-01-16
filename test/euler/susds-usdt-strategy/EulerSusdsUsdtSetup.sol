// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Test.sol";
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

/// @title EulerSusdsUsdtSetup
/// @notice Euler-specific test setup inheriting from LeveragedStrategyBaseSetup
contract EulerSusdsUsdtSetup is LeveragedStrategyBaseSetup {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   STRATEGY-SPECIFIC CONSTANTS                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Tokens
    address public constant SUSDS_TOKEN = 0xdDb46999F8891663a8F2828d25298f70416d7610;
    address public constant USDS_TOKEN = 0x6491c05A82219b8D1479057361ff1654749b876b;
    address public constant USDT_TOKEN = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant USD_TOKEN = 0x0000000000000000000000000000000000000348; // synthetic USD representation

    // Euler contracts
    address public constant EVC = 0x6302ef0F34100CDDFb5489fbcB6eE1AA95CD1066;
    address public constant COLLATERAL_VAULT = 0x0EE8D628411F446BFbbe08BDeF53E42414C8fBC4;
    address public constant DEBT_VAULT = 0x37512F45B4ba8808910632323b73783Ca938CD51;
    // address public constant EULER_ORACLE_ROUTER = 0x94B6924796CcC98e5237615F8710Ef5732190F66;

    address public constant ASSET_TO_COLLATERAL_ORACLE = 0xC8228b83F1d97a431A48bd9Bc3e971c8b418d889;
    address public constant ASSET_TO_USD_ORACLE = 0xF5C2DfD1740D18aD7cf23FBA76cc11d877802937;
    address public constant DEBT_TO_USD_ORACLE = 0xbBC0166f5F14e9C4970c87bd5336e19Bc530FD74;

    // Token decimals
    uint8 public constant USDS_TOKEN_DECIMALS = 18;
    uint8 public constant SUSDS_TOKEN_DECIMALS = 18;
    uint8 public constant USDT_TOKEN_DECIMALS = 6;

    // Final strategy constants used throughout the tests
    address public constant ASSET_TOKEN = USDS_TOKEN;
    address public constant COLLATERAL_TOKEN = SUSDS_TOKEN;
    address public constant DEBT_TOKEN = USDT_TOKEN;

    uint8 public constant ASSET_DECIMALS = USDS_TOKEN_DECIMALS;
    uint8 public constant COLLATERAL_TOKEN_DECIMALS = SUSDS_TOKEN_DECIMALS;
    uint8 public constant DEBT_TOKEN_DECIMALS = USDT_TOKEN_DECIMALS;

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
        string memory chainUrl = vm.envString("RPC_CHAINID_42161");
        if (bytes(chainUrl).length == 0) {
            revert("RPC_CHAINID_42161 env var not set");
            chainUrl = "https://arbitrum-one-rpc.publicnode.com";
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
            ASSET_TO_COLLATERAL_ORACLE,
            ASSET_TO_USD_ORACLE,
            DEBT_TO_USD_ORACLE,
            ASSET_TOKEN,
            COLLATERAL_TOKEN,
            DEBT_TOKEN,
            USD_TOKEN
        );

        // Set base contract reference
        oracleAdapter = IOracleAdapter(address(eulerOracleAdapter));
    }

    function _setupSwapper() internal override {
        swapper = new CeresSwapper(CERES_DEPLOYER, KYBER_SCALE_HELPER, AUGUSTUS_REGISTRY);
    }

    function _deployStrategy() internal override {
        vm.startPrank(management);

        address deployedStrategy = address(
            new LeveragedEuler(
                ASSET_TOKEN, // asset token
                "Ceres Leveraged Euler Strategy", // name
                COLLATERAL_TOKEN, // collateral token (same as asset)
                DEBT_TOKEN, // debt token
                COLLATERAL_VAULT, // collateral vault
                DEBT_VAULT, // borrow vault
                address(evc), // vault connector
                address(swapper), // ceres swapper
                address(eulerOracleAdapter) // oracle adapter
            )
        );
        console.log("Strategy deployed at:", deployedStrategy);
        strategy = ILeveragedStrategy(deployedStrategy);

        strategy.setPerformanceFeeRecipient(feeReceiver);
        strategy.setKeeper(keeper);
        strategy.setEmergencyAdmin(management);

        vm.stopPrank();
    }

    function _initializeStrategy() internal override {
        vm.startPrank(management);

        // Set LTV parameters
        strategy.setTargetLtv(TARGET_LTV_BPS);
        strategy.setMaxSlippage(MAX_SLIPPAGE_BPS);
        strategy.setDepositLimit(DEPOSIT_LIMIT);
        strategy.setWithdrawLimit(WITHDRAW_LIMIT);

        // Add keeper role
        strategy.setKeeper(keeper);

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

    function _simulateInterestAccrual(
        uint256 interestRateBpsCollateral,
        uint256 interestRateBpsDebt,
        uint256 timeElapsed
    ) internal override {
        skip(timeElapsed);
    }

    function _simulatePriceChange(int256 percentChange) internal override {}

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    LABEL ADDRESSES                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _labelAddresses() internal override {
        vm.label(address(ASSET_TOKEN), "ASSET_TOKEN");
        vm.label(address(DEBT_TOKEN), "DEBT_TOKEN");
        vm.label(address(collateralVault), "Collateral Vault");
        vm.label(address(borrowVault), "Borrow Vault");
        vm.label(address(evc), "EVC");
        vm.label(address(ASSET_TO_COLLATERAL_ORACLE), "ASSET_TO_COLLATERAL_ORACLE");
        vm.label(address(ASSET_TO_USD_ORACLE), "ASSET_TO_USD_ORACLE");
        vm.label(address(DEBT_TO_USD_ORACLE), "DEBT_TO_USD_ORACLE");

        vm.label(address(eulerOracleAdapter), "Euler Oracle Adapter");
        vm.label(address(swapper), "Ceres Swapper");
        vm.label(address(strategy), "LeveragedEuler Strategy");
    }
}
