// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {StrategyOperations} from "../StrategyOperations.sol";
import {FormatUtils} from "../../../common/FormatUtils.sol";

import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";

/// @title SwapAndDepositIdleAssets
/// @notice Script to leverage up the USDf-sUSDf-USDC strategy
/// @dev Borrows more debt and swaps it for collateral to increase leverage
contract SwapAndDepositIdleAssets is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = LeveragedEuler(LEVERAGED_EULER_STRATEGY_ADDRESS);

        uint8 decimals = strategy.decimals();
        uint256 ONE_SHARE_UNIT = 10 ** decimals;

        uint256 pps = strategy.convertToAssets(ONE_SHARE_UNIT);

        console.log("\n==============================================");
        console.log("Harvest and report");
        console.log("==============================================");
        console.log("Strategy:", address(strategy));
        FormatUtils.logWithSymbol("PricePerShareBefore", pps, decimals, "USDf");

        // Log current state
        console.log("\n--- Current State ---");
        _logStrategyState(strategy);

        uint256 managementPvtKey = vm.envUint("MANAGEMENT_PVT_KEY");
        vm.startBroadcast(managementPvtKey);

        console.log("\nHarvesting rewards and reporting to vault...");
        strategy.harvestAndReport();

        vm.stopBroadcast();

        pps = strategy.convertToAssets(ONE_SHARE_UNIT);
        FormatUtils.logWithSymbol("PricePerShareAfter", pps, decimals, "USDf");

        // Log new state
        console.log("\n--- New State ---");
        _logStrategyState(strategy);

        console.log("\n==============================================");
        console.log("Strategy reported Successfully!");
        console.log("==============================================");
    }
}
