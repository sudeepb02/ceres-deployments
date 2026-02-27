// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";
import {IOracleAdapter} from "ceres-strategies/src/interfaces/periphery/IOracleAdapter.sol";
import {StrategyOperations} from "./StrategyOperations.sol";
import {FormatUtils} from "../common/FormatUtils.sol";

/// @title RebalanceLeverageDown
/// @notice Generic script to leverage down (deleverage/reduce leverage) for any leveraged strategy
/// @dev Reads strategy address from STRATEGY_ADDRESS env var
/// @dev Optional: Set USE_FLASH_LOAN=false to supply debt tokens directly
/// @dev Optional: Set NEW_TARGET_LTV to update target before deleveraging
/// @dev Usage: STRATEGY_ADDRESS=0x... forge script script/common/operations/RebalanceLeverageDown.s.sol
contract RebalanceLeverageDown is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = _getStrategy();
        (address asset, address collateral, address debt) = _getTokens(strategy);

        // Determine if using flash loan (default: true)
        bool useFlashLoan = true;

        try vm.envBool("USE_FLASH_LOAN") returns (bool _useFlashLoan) {
            useFlashLoan = _useFlashLoan;
        } catch {}
        console.log("==============================================");
        console.log("Leverage Down Rebalance");
        console.log("==============================================");
        console.log("Strategy:", address(strategy));
        console.log("Use Flash Loan:", useFlashLoan);

        // Check if we should update target LTV first
        try vm.envUint("NEW_TARGET_LTV") returns (uint256 newTargetLtv) {
            if (newTargetLtv > 0 && newTargetLtv < 10000) {
                console.log("\nUpdating target LTV first...");
                FormatUtils.logBps("New Target LTV:", newTargetLtv);

                // Read current ltvBufferBps from strategy to preserve it
                (, , uint16 currentLtvBufferBps, , , ) = strategy.getLeveragedStrategyConfig();

                uint256 managementPrivateKey = vm.envUint("MANAGEMENT_PVT_KEY");
                vm.startBroadcast(managementPrivateKey);
                strategy.setTargetLtv(uint16(newTargetLtv), currentLtvBufferBps);
                vm.stopBroadcast();
            }
        } catch {}
        // Log current state
        console.log("\n--- Current State: Before rebalance ---");
        _logStrategyState(strategy);

        console.log("\n--- Strategy config ---");
        _logStrategyConfig(strategy);

        uint256 deleverageAmountDebt;
        uint256 deleverageAmountInCollateral;
        {
            uint256 targetDebt;
            (, uint16 targetLtvBps, , , , ) = strategy.getLeveragedStrategyConfig();

            (, uint256 netAssets, uint256 marketCollateral, , uint256 marketDebt, ) = strategy.getNetAssets();

            FormatUtils.logWithSymbol("Net assets", netAssets, IERC20Metadata(asset).decimals(), "Assets");
            FormatUtils.logWithSymbol(
                "Market Collateral",
                marketCollateral,
                IERC20Metadata(collateral).decimals(),
                "Collateral Tokens"
            );
            FormatUtils.logWithSymbol("Market Debt", marketDebt, IERC20Metadata(debt).decimals(), "DebtTokens");

            // Calculate target debt amount
            targetDebt = LeverageLib.computeTargetDebt(netAssets, targetLtvBps, strategy.oracleAdapter());

            console.log("Target debt amount:", targetDebt);

            deleverageAmountDebt = marketDebt > targetDebt ? marketDebt - targetDebt : 0;
            if (deleverageAmountDebt == 0) {
                revert("Leverage down not needed, already at or below target LTV");
            }

            // Convert debt amount to collateral amount for the swap
            IOracleAdapter oracleAdapter = strategy.oracleAdapter();
            deleverageAmountInCollateral = oracleAdapter.convertDebtToCollateral(deleverageAmountDebt);

            console.log("Current debt:", marketDebt);
            FormatUtils.logWithSymbol(
                "Deleverage amount (debt):",
                deleverageAmountDebt,
                IERC20Metadata(debt).decimals(),
                "DebtTokens"
            );
            FormatUtils.logWithSymbol(
                "Deleverage amount (collateral):",
                deleverageAmountInCollateral,
                IERC20Metadata(collateral).decimals(),
                "Collateral Tokens"
            );
        }

        // Get swap data - for leverage down we swap collateral to debt
        bytes memory swapData = _getSwapData(strategy, collateral, debt, deleverageAmountInCollateral, false);

        uint256 keeperPrivateKey = vm.envUint("KEEPER_PVT_KEY");
        vm.startBroadcast(keeperPrivateKey);

        if (useFlashLoan) {
            // Use flash loan to rebalance
            console.log("\nExecuting rebalanceUsingFlashLoan...");
            strategy.rebalanceUsingFlashLoan(deleverageAmountDebt, false, swapData);
        } else {
            // Supply debt tokens directly (for debt repayment buffer)
            console.log("\nSupplying debt tokens to strategy through keeper...");

            // Approve strategy to pull debt tokens
            IERC20(debt).approve(address(strategy), deleverageAmountDebt);

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
    /// @dev Uses EXACT_OUT_AVAILABLE env var to determine provider (defaults to Kyberswap)
    function _shouldUseParaswap(bool /* isLeverageUp */) internal view override returns (bool) {
        try vm.envBool("EXACT_OUT_AVAILABLE") returns (bool exactOutAvailable) {
            return exactOutAvailable;
        } catch {
            return false;
        }
    }
}
