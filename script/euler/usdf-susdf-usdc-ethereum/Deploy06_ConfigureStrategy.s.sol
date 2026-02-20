// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {CeresSwapper} from "ceres-strategies/src/periphery/CeresSwapper.sol";
import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";
import {DeploymentConstantsUsdfEthereum} from "./DeploymentConstantsUsdfEthereum.sol";

/// @title Deploy06_ConfigureStrategy
/// @notice Configures and initializes the USDf-sUSDf-USDC Euler strategy
/// @dev This script performs all necessary configuration including:
///      - Setting up swap providers on CeresSwapper
///      - Configuring flash loan routing
///      - Setting strategy parameters (oracle, swapper, flash loan router)
///      - Setting LTV parameters and limits
///      - Setting fee recipient
contract Deploy06_ConfigureStrategy is Script, DeploymentConstantsUsdfEthereum {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    bool constant VERIFY_CONTRACT = false; // No new contracts deployed in this script
    uint16 constant PERFORMANCE_FEE_BPS = 15_00;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN CONFIGURATION                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get environment variables
        address management = vm.envAddress("DEPLOYER_ADDRESS");
        // address feeReceiver = vm.envAddress("FEE_RECEIVER_ADDRESS");
        address feeReceiver = management;

        console.log("==============================================");
        console.log("Configuring USDf-sUSDf-USDC Euler Strategy");
        console.log("==============================================");
        console.log("Management:", management);
        console.log("Fee Receiver:", feeReceiver);

        // Verify all contracts are deployed
        _verifyDeployments();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get contract instances
        CeresSwapper swapper = CeresSwapper(CERES_SWAPPER_ADDRESS);
        FlashLoanRouter flashLoanRouter = FlashLoanRouter(FLASH_LOAN_ROUTER_ADDRESS);
        LeveragedEuler strategy = LeveragedEuler(LEVERAGED_EULER_STRATEGY_ADDRESS);

        // Step 1: Configure swap providers
        console.log("\n1. Configuring swap providers...");
        _configureSwapProviders(swapper);

        // Step 2: Configure flash loan routing
        console.log("\n2. Configuring flash loan routing...");
        _configureFlashLoanRouting(flashLoanRouter, address(strategy));

        // Step 3: Set periphery contracts on strategy
        console.log("\n3. Setting periphery contracts on strategy...");
        _setPeripheryContracts(strategy);

        // Step 4: Set strategy parameters
        console.log("\n4. Setting strategy parameters...");
        _setStrategyParameters(strategy, feeReceiver);

        vm.stopBroadcast();

        console.log("\n==============================================");
        console.log("Configuration complete!");
        console.log("==============================================");
        console.log("\nStrategy is now ready for deposits!");
        console.log("Strategy address:", address(strategy));

        // Log final configuration
        _logFinalConfiguration(strategy);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   VERIFICATION                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _verifyDeployments() internal view {
        console.log("\nVerifying all contracts are deployed...");

        require(isRoleManagerDeployed(), "RoleManager not deployed");
        console.log("  [OK] RoleManager:", ROLE_MANAGER_ADDRESS);

        require(isSwapperDeployed(), "CeresSwapper not deployed");
        console.log("  [OK] CeresSwapper:", CERES_SWAPPER_ADDRESS);

        require(isFlashLoanRouterDeployed(), "FlashLoanRouter not deployed");
        console.log("  [OK] FlashLoanRouter:", FLASH_LOAN_ROUTER_ADDRESS);

        require(EULER_ORACLE_ADAPTER_ADDRESS != address(0), "Euler Oracle Adapter not deployed");
        console.log("  [OK] Euler Oracle Adapter:", EULER_ORACLE_ADAPTER_ADDRESS);

        require(LEVERAGED_EULER_STRATEGY_ADDRESS != address(0), "LeveragedEuler Strategy not deployed");
        console.log("  [OK] LeveragedEuler Strategy:", LEVERAGED_EULER_STRATEGY_ADDRESS);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   SWAP CONFIGURATION                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _configureSwapProviders(CeresSwapper swapper) internal {
        // Configure Kyberswap as the swap provider for all pairs
        CeresSwapper.SwapProvider memory kyberswapProvider = CeresSwapper.SwapProvider({
            swapType: CeresSwapper.SwapType.KYBERSWAP_AGGREGATOR,
            router: KYBERSWAP_ROUTER
        });

        // Set swap providers for all token pairs
        // Collateral <-> Debt
        swapper.setSwapProvider(COLLATERAL_TOKEN, DEBT_TOKEN, kyberswapProvider);
        console.log("  Set swap provider for Collateral -> Debt (Kyberswap)");

        swapper.setSwapProvider(DEBT_TOKEN, COLLATERAL_TOKEN, kyberswapProvider);
        console.log("  Set swap provider for Debt -> Collateral (Kyberswap)");

        // Asset <-> Collateral
        swapper.setSwapProvider(ASSET_TOKEN, COLLATERAL_TOKEN, kyberswapProvider);
        console.log("  Set swap provider for Asset -> Collateral (Kyberswap)");

        swapper.setSwapProvider(COLLATERAL_TOKEN, ASSET_TOKEN, kyberswapProvider);
        console.log("  Set swap provider for Collateral -> Asset (Kyberswap)");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   FLASH LOAN CONFIGURATION                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _configureFlashLoanRouting(FlashLoanRouter flashLoanRouter, address strategy) internal {
        flashLoanRouter.setFlashConfig(
            strategy,
            FlashLoanRouter.FlashSource(FLASH_LOAN_SOURCE),
            FLASH_LOAN_PROVIDER,
            true // enabled
        );
        console.log("  Flash loan routing configured:");
        console.log("    Source: ERC3156");
        console.log("    Provider:", FLASH_LOAN_PROVIDER);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   STRATEGY CONFIGURATION                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _setPeripheryContracts(LeveragedEuler strategy) internal {
        // Set oracle adapter
        strategy.requestUpdate(strategy.ORACLE_KEY(), EULER_ORACLE_ADAPTER_ADDRESS);
        console.log("  Set Oracle Adapter:", EULER_ORACLE_ADAPTER_ADDRESS);

        // Set swapper
        strategy.requestUpdate(strategy.SWAPPER_KEY(), CERES_SWAPPER_ADDRESS);
        console.log("  Set Swapper:", CERES_SWAPPER_ADDRESS);

        // Set flash loan router
        strategy.requestUpdate(strategy.FLASH_LOAN_ROUTER_KEY(), FLASH_LOAN_ROUTER_ADDRESS);
        console.log("  Set Flash Loan Router:", FLASH_LOAN_ROUTER_ADDRESS);
    }

    function _setStrategyParameters(LeveragedEuler strategy, address feeReceiver) internal {
        // Set fee recipient
        strategy.setPerformanceFeeRecipient(feeReceiver);
        console.log("  Performance fee recipient:", feeReceiver);

        // Set base config
        strategy.updateConfig(MAX_SLIPPAGE_BPS, PERFORMANCE_FEE_BPS, MAX_LOSS_BPS);
        console.log("  Max slippage:", MAX_SLIPPAGE_BPS, "bps");
        console.log("  Performance fee:", PERFORMANCE_FEE_BPS, "bps");
        console.log("  Max loss:", MAX_LOSS_BPS, "bps");

        // Set target LTV
        strategy.setTargetLtv(TARGET_LTV_BPS);
        console.log("  Target LTV:", TARGET_LTV_BPS, "bps");

        // Set deposit/redeem limits
        strategy.setDepositWithdrawLimits(DEPOSIT_LIMIT, REDEEM_LIMIT_SHARES, 0);
        console.log("  Deposit limit:", DEPOSIT_LIMIT);
        console.log("  Redeem limit shares:", REDEEM_LIMIT_SHARES);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   LOGGING                                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _logFinalConfiguration(LeveragedEuler strategy) internal view {
        console.log("\n==============================================");
        console.log("Final Strategy Configuration:");
        console.log("==============================================");
        console.log("Asset Token:", ASSET_TOKEN);
        console.log("Collateral Token:", COLLATERAL_TOKEN);
        console.log("Debt Token:", DEBT_TOKEN);
        // console.log("Target LTV:", TARGET_LTV_BPS, "bps (", TARGET_LTV_BPS / 100, "%)");
        // console.log("Max Slippage:", MAX_SLIPPAGE_BPS, "bps (", MAX_SLIPPAGE_BPS / 100, "%)");
        // console.log("Max Loss:", MAX_LOSS_BPS, "bps (", MAX_LOSS_BPS / 100, "%)");
        console.log("Deposit Limit:", DEPOSIT_LIMIT / 1e18, "tokens");
        console.log("==============================================");
    }
}
