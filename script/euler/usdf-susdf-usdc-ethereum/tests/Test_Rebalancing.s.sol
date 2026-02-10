// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";
import {StrategyOperations} from "./StrategyOperations.sol";

import {IOracleAdapter} from "ceres-strategies/src/interfaces/periphery/IOracleAdapter.sol";

/// @title Test_Rebalancing
/// @notice Test script to verify both leverage up and leverage down operations
/// @dev This script simulates a full rebalancing cycle:
///      1. Leverage up to target LTV
///      2. Leverage down to reduce LTV
contract Test_Rebalancing is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Test configuration
    bool constant EXACT_OUT_AVAILABLE = false;
    bool constant USE_FLASH_LOAN = true;

    // Tolerance for LTV checks (in bps)
    uint256 constant LTV_TOLERANCE_BPS = 50; // 0.5%

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN TEST                                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = LeveragedEuler(LEVERAGED_EULER_STRATEGY_ADDRESS);
        IERC20 assetToken = IERC20(ASSET_TOKEN);
        IERC20 debtToken = IERC20(DEBT_TOKEN);

        uint256 targetLtvBps = strategy.targetLtvBps();

        console.log("==============================================");
        console.log("REBALANCING TEST");
        console.log("==============================================");
        console.log("Strategy:", LEVERAGED_EULER_STRATEGY_ADDRESS);
        console.log("Target LTV:", targetLtvBps, "bps");
        console.log("Use Flash Loan:", USE_FLASH_LOAN);
        console.log("Exact Out Available:", EXACT_OUT_AVAILABLE);

        console.log("\n--- State before any operations---");
        _logStrategyState(strategy);

        uint256 keeperPrivateKey = vm.envUint("KEEPER_PVT_KEY");
        vm.startBroadcast(keeperPrivateKey);

        {
            console.log("\n==============================================");
            console.log("STEP 1: Leverage Up");
            console.log("==============================================");

            // Check and deposit any idle assets before leveraging up
            _depositIdleAssets(strategy);

            console.log("\n--- State after deposit idle assets---");
            _logStrategyState(strategy);

            uint256 targetDebt;
            (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();
            console.log("Net Assets:", netAssets / 1e18, "USDf");
            console.log("Total Collateral:", totalCollateral / 1e18, "USDf");
            console.log("Total Debt:", totalDebt / 1e6, "USDC");

            // Calculate target debt amount
            targetDebt = LeverageLib.computeTargetDebt(netAssets, targetLtvBps, strategy.oracleAdapter());

            console.log("Target debt amount:", targetDebt);

            uint256 rebalanceAmount = targetDebt > totalDebt ? targetDebt - totalDebt : 0;
            if (rebalanceAmount == 0) {
                revert("No rebalance needed, already at or above target LTV");
            }

            // Get swap data for leverage up: DEBT -> COLLATERAL
            bytes memory leverageUpSwapData = _getSwapData(
                address(DEBT_TOKEN),
                address(COLLATERAL_TOKEN),
                rebalanceAmount,
                true // isLeverageUp
            );

            if (USE_FLASH_LOAN) {
                console.log("Using flash loan for leverage up...");
                strategy.rebalanceUsingFlashLoan(rebalanceAmount, true, leverageUpSwapData);
            } else {
                console.log("Supplying debt tokens for leverage up...");
                // Keeper must have enough debt tokens for the rebalance
                debtToken.approve(address(strategy), rebalanceAmount);
                strategy.rebalance(rebalanceAmount, true, leverageUpSwapData);
            }

            console.log("\n--- State after leverage up---");
            _logStrategyState(strategy);

            // Verify LTV is near target
            uint256 currentLtv = strategy.getStrategyLtv();
            _assertLtvNearTarget(currentLtv, targetLtvBps, LTV_TOLERANCE_BPS, "After leverage up");
        }

        {
            console.log("\n==============================================");
            console.log("STEP 2: Leverage Down");
            console.log("==============================================");

            // Get current debt
            (, , uint256 currentDebt) = strategy.getNetAssets();
            uint256 deleverageAmountDebt = currentDebt / 2; // Reduce debt by 50%

            console.log("Current debt:", currentDebt);
            console.log("Deleverage amount (debtToken):", deleverageAmountDebt);

            // Convert debt amount to collateral amount for the swap
            IOracleAdapter oracleAdapter = strategy.oracleAdapter();
            uint256 deleverageAmountCollateral = oracleAdapter.convertDebtToCollateral(deleverageAmountDebt);

            console.log("Deleverage amount (collateralToken):", deleverageAmountCollateral);

            // Get swap data for leverage down: COLLATERAL -> DEBT
            bytes memory leverageDownSwapData = _getSwapData(
                address(COLLATERAL_TOKEN),
                address(DEBT_TOKEN),
                deleverageAmountCollateral, // in sUSDf (18 decimals)
                false
            );

            if (USE_FLASH_LOAN) {
                console.log("Using flash loan for leverage down...");
                // rebalanceUsingFlashLoan accepts the debt amount for flashLoan to the strategy
                strategy.rebalanceUsingFlashLoan(deleverageAmountDebt, false, leverageDownSwapData);
            } else {
                console.log("Supplying debt tokens for leverage down from Keeper address...");
                debtToken.approve(address(strategy), deleverageAmountDebt);
                strategy.rebalance(deleverageAmountDebt, false, leverageDownSwapData);
            }

            console.log("\n--- State after leverage down ---");
            _logStrategyState(strategy);

            // Verify debt decreased
            (, , uint256 finalDebt) = strategy.getNetAssets();
            require(finalDebt < currentDebt, "Debt should have decreased");
            console.log("\n[OK] Debt decreased from", currentDebt, "to", finalDebt);
        }
        vm.stopBroadcast();

        console.log("\n==============================================");
        console.log("TEST RESULTS: PASSED");
        console.log("==============================================");
        console.log("[OK] Leverage up achieved target LTV");
        console.log("[OK] Leverage down reduced debt");
        console.log("\nStrategy is functioning correctly!");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   SWAP PROVIDER SELECTION                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Override to customize swap provider selection
    /// @dev Uses EXACT_OUT_AVAILABLE constant to determine provider
    function _shouldUseParaswap(bool /* isLeverageUp */) internal pure override returns (bool) {
        return EXACT_OUT_AVAILABLE;
    }
}
