// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";
import {IOracleAdapter} from "ceres-strategies/src/interfaces/periphery/IOracleAdapter.sol";

import {StrategyOperations} from "./StrategyOperations.sol";
import {FormatUtils} from "../../common/FormatUtils.sol";

/// @title Rebalance_LeverageDown
/// @notice Script to leverage down (deleverage) the USDf-sUSDf-USDC strategy
/// @dev Sells collateral to repay debt and reduce leverage
contract Rebalance_LeverageDown is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Set to true to use Paraswap (exactOut), false to use Kyberswap (exactIn)
    // For leverage down, exactOut is preferred to ensure exact debt repayment
    bool constant EXACT_OUT_AVAILABLE = false;

    // Set to true to use flash loans, false to supply debt tokens directly
    bool constant USE_FLASH_LOAN = true;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        console.log("==============================================");
        console.log("Leverage Down Rebalance");
        console.log("==============================================");
        console.log("Strategy:", LEVERAGED_EULER_STRATEGY_ADDRESS);
        console.log("Use Flash Loan:", USE_FLASH_LOAN);
        console.log("Exact Out Available:", EXACT_OUT_AVAILABLE);

        // Get contract instances
        LeveragedEuler strategy = LeveragedEuler(LEVERAGED_EULER_STRATEGY_ADDRESS);

        uint256 managementPrivateKey = vm.envUint("MANAGEMENT_PVT_KEY");
        vm.startBroadcast(managementPrivateKey);

        strategy.setTargetLtv(50_00); // 50%

        vm.stopBroadcast();

        // Log current state
        console.log("\n--- Current State: Before rebalance ---");
        _logStrategyState(strategy);

        uint256 targetDebt;
        uint16 targetLtvBps = strategy.targetLtvBps();

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        FormatUtils.logWithSymbol("Net assets", netAssets, 18, "USDf");
        FormatUtils.logWithSymbol("Total Collateral", totalCollateral, 18, "sUSDf");
        FormatUtils.logWithSymbol("Total Debt", totalDebt, 6, "USDC");

        // Calculate target debt amount
        targetDebt = LeverageLib.computeTargetDebt(netAssets, targetLtvBps, strategy.oracleAdapter());

        console.log("Target debt amount:", targetDebt);

        uint256 deleverageAmountDebt = totalDebt > targetDebt ? totalDebt - targetDebt : 0;
        if (deleverageAmountDebt == 0) {
            revert("Leverage down not done, already at or below target LTV");
        }

        // Convert debt amount to collateral amount for the swap
        IOracleAdapter oracleAdapter = strategy.oracleAdapter();
        uint256 deleverageAmountInCollateral = oracleAdapter.convertDebtToCollateral(deleverageAmountDebt);

        console.log("Current debt:", totalDebt);
        console.log("Deleverage amount (debtToken):", deleverageAmountDebt);
        console.log("Deleverage amount (collateralToken):", deleverageAmountInCollateral);

        // Get swap data - for leverage down we swap collateral to debt
        bytes memory swapData = _getSwapData(
            address(COLLATERAL_TOKEN),
            address(DEBT_TOKEN),
            deleverageAmountInCollateral,
            false
        );

        uint256 keeperPrivateKey = vm.envUint("KEEPER_PVT_KEY");
        vm.startBroadcast(keeperPrivateKey);

        if (USE_FLASH_LOAN) {
            // Use flash loan to rebalance
            console.log("\nExecuting rebalanceUsingFlashLoan...");
            strategy.rebalanceUsingFlashLoan(deleverageAmountDebt, false, swapData);
        } else {
            // Supply debt tokens directly (for debt repayment buffer)
            console.log("\nSupplying debt tokens to strategy through keeper...");

            // Approve strategy to pull debt tokens
            IERC20(DEBT_TOKEN).approve(address(strategy), deleverageAmountDebt);

            console.log("Executing rebalance...");
            strategy.rebalance(deleverageAmountDebt, false, swapData);
        }

        vm.stopBroadcast();

        // Log new state
        console.log("\n--- New State ---");
        _logStrategyState(strategy);

        console.log("\n==============================================");
        console.log("Leverage Down Complete!");
        console.log("==============================================");
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
