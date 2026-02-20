// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {StrategyOperations} from "./StrategyOperations.sol";
import {FormatUtils} from "../common/FormatUtils.sol";

/// @title HarvestAndReport
/// @notice Generic script to harvest rewards and report to vault for any strategy
/// @dev Reads strategy address from STRATEGY_ADDRESS env var
/// @dev Usage: STRATEGY_ADDRESS=0x... forge script script/common/operations/HarvestAndReport.s.sol
contract HarvestAndReport is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = _getStrategy();

        uint8 decimals = strategy.decimals();
        uint256 pps = strategy.convertToAssets(10 ** decimals);

        console.log("\n==============================================");
        console.log("Harvest and Report");
        console.log("==============================================");
        console.log("Strategy:", address(strategy));
        FormatUtils.logWithSymbol("PricePerShare Before:", pps, decimals, "");

        // Log current state
        console.log("\n--- Current State ---");
        _logStrategyState(strategy);

        // Get private key from environment
        uint256 managementPvtKey = vm.envUint("MANAGEMENT_PVT_KEY");
        vm.startBroadcast(managementPvtKey);

        console.log("\nHarvesting rewards and reporting to vault...");
        strategy.harvestAndReport();

        vm.stopBroadcast();

        pps = strategy.convertToAssets(10 ** decimals);
        FormatUtils.logWithSymbol("PricePerShare After:", pps, decimals, "");

        // Log new state
        console.log("\n--- New State ---");
        _logStrategyState(strategy);

        console.log("\n==============================================");
        console.log("Strategy Reported Successfully!");
        console.log("==============================================");
    }
}
