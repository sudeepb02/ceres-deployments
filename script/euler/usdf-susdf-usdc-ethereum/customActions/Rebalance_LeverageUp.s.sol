// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";

import {StrategyOperations} from "../StrategyOperations.sol";
import {FormatUtils} from "../../../common/FormatUtils.sol";

/// @title Rebalance_LeverageUp
/// @notice Script to leverage up the USDf-sUSDf-USDC strategy
/// @dev Borrows more debt and swaps it for collateral to increase leverage
contract Rebalance_LeverageUp is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Set to true to use Paraswap (exactIn), false to use Kyberswap (exactIn)
    // For leverage up, both use exactIn, but you can toggle based on preference
    bool constant EXACT_OUT_AVAILABLE = false;

    // Set to true to use flash loans, false to supply debt tokens directly
    bool constant USE_FLASH_LOAN = true;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        console.log("==============================================");
        console.log("Leverage Up Rebalance");
        console.log("==============================================");
        console.log("Strategy:", LEVERAGED_EULER_STRATEGY_ADDRESS);
        console.log("Use Flash Loan:", USE_FLASH_LOAN);
        console.log("Exact Out Available:", EXACT_OUT_AVAILABLE);

        // Get contract instances
        LeveragedEuler strategy = LeveragedEuler(LEVERAGED_EULER_STRATEGY_ADDRESS);
        uint16 targetLtvBps = strategy.targetLtvBps();

        uint256 targetDebt;
        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        FormatUtils.logWithSymbol("Net assets", netAssets, 18, "USDf");
        FormatUtils.logWithSymbol("Total Collateral", totalCollateral, 18, "sUSDf");
        FormatUtils.logWithSymbol("Total Debt", totalDebt, 6, "USDC");

        // Calculate target debt amount
        targetDebt = LeverageLib.computeTargetDebt(netAssets, targetLtvBps, strategy.oracleAdapter());

        console.log("Target debt amount:", targetDebt);

        uint256 debtAmount = targetDebt > totalDebt ? targetDebt - totalDebt : 0;
        if (debtAmount == 0) {
            revert("Leverage up not possible, already at or above target LTV");
        }

        // Log current state
        console.log("\n--- Current State ---");
        _logStrategyState(strategy);

        uint256 keeperPrivateKey = vm.envUint("KEEPER_PVT_KEY");
        vm.startBroadcast(keeperPrivateKey);

        bytes memory swapData = _getSwapData(address(DEBT_TOKEN), address(COLLATERAL_TOKEN), debtAmount, true);

        if (USE_FLASH_LOAN) {
            // Use flash loan to rebalance
            console.log("\nExecuting rebalanceUsingFlashLoan...");
            strategy.rebalanceUsingFlashLoan(debtAmount, true, swapData);
        } else {
            // Supply debt tokens directly
            console.log("\nSupplying debt tokens to strategy...");

            // Approve strategy to pull debt tokens
            IERC20(DEBT_TOKEN).approve(address(strategy), debtAmount);

            console.log("Executing rebalance...");
            strategy.rebalance(debtAmount, true, swapData);
        }

        vm.stopBroadcast();

        // Log new state
        console.log("\n--- New State ---");
        _logStrategyState(strategy);

        console.log("\n==============================================");
        console.log("Leverage Up Complete!");
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
