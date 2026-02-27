// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";
import {StrategyOperations} from "./StrategyOperations.sol";
import {FormatUtils} from "../common/FormatUtils.sol";

/// @title RebalanceLeverageUp
/// @notice Generic script to leverage up (increase leverage) for any leveraged strategy
/// @dev Reads strategy address from STRATEGY_ADDRESS env var
/// @dev Optional: Set USE_FLASH_LOAN=false to supply debt tokens directly
/// @dev Usage: STRATEGY_ADDRESS=0x... forge script script/common/operations/RebalanceLeverageUp.s.sol
contract RebalanceLeverageUp is StrategyOperations {
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
        console.log("Leverage Up Rebalance");
        console.log("==============================================");
        console.log("Strategy:", address(strategy));
        console.log("Use Flash Loan:", useFlashLoan);

        (, uint16 targetLtvBps, , , , ) = strategy.getLeveragedStrategyConfig();

        // Log current state
        console.log("\n--- Current State: Before rebalance ---");
        _logStrategyState(strategy);

        uint256 targetDebt;
        (, uint256 netAssets, , , uint256 marketDebt, ) = strategy.getNetAssets();

        targetDebt = LeverageLib.computeTargetDebt(netAssets, targetLtvBps, strategy.oracleAdapter());
        console.log("Target debt amount:", targetDebt);

        uint256 debtAmount = targetDebt > marketDebt ? targetDebt - marketDebt : 0;
        if (debtAmount == 0) revert("Leverage up not possible, already at or above target LTV");

        FormatUtils.logWithSymbol(
            "Additional Debt to borrow:",
            debtAmount,
            IERC20Metadata(debt).decimals(),
            "DebtTokens"
        );

        bytes memory swapData = _getSwapData(strategy, debt, collateral, debtAmount, true);

        uint256 keeperPrivateKey = vm.envUint("KEEPER_PVT_KEY");
        vm.startBroadcast(keeperPrivateKey);

        if (useFlashLoan) {
            // Use flash loan to rebalance
            console.log("\nExecuting rebalanceUsingFlashLoan...");
            strategy.rebalanceUsingFlashLoan(debtAmount, true, swapData);
        } else {
            // Supply debt tokens directly
            console.log("\nSupplying debt tokens to strategy through keeper...");

            // Approve strategy to pull debt tokens
            IERC20(debt).approve(address(strategy), debtAmount);

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
    /// @dev Uses EXACT_OUT_AVAILABLE env var to determine provider (defaults to Kyberswap)
    function _shouldUseParaswap(bool /* isLeverageUp */) internal view override returns (bool) {
        try vm.envBool("EXACT_OUT_AVAILABLE") returns (bool exactOutAvailable) {
            return exactOutAvailable;
        } catch {
            return false;
        }
    }
}
