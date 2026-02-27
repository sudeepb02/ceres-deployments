// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {StrategyOperations} from "./StrategyOperations.sol";
import {FormatUtils} from "../common/FormatUtils.sol";

/// @title UpdateTargetLtv
/// @notice Generic script to update the target LTV for any leveraged strategy
/// @dev Reads strategy address from STRATEGY_ADDRESS and new target LTV from NEW_TARGET_LTV env vars
/// @dev Usage: STRATEGY_ADDRESS=0x... NEW_TARGET_LTV=8300 forge script script/common/operations/UpdateTargetLtv.s.sol
contract UpdateTargetLtv is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = _getStrategy();

        // Get new target LTV from environment variable (in bps, e.g., 8300 = 83%)
        uint16 newTargetLtv = uint16(vm.envUint("NEW_TARGET_LTV"));
        require(newTargetLtv > 0 && newTargetLtv < 10000, "Invalid target LTV");

        // Read current ltvBufferBps from strategy; allow optional override via env var
        (, , uint16 currentLtvBufferBps, , , ) = strategy.getLeveragedStrategyConfig();
        uint16 ltvBufferBps = currentLtvBufferBps;
        try vm.envUint("LTV_BUFFER_BPS") returns (uint256 envBuffer) {
            if (envBuffer > 0 && envBuffer < 10000) ltvBufferBps = uint16(envBuffer);
        } catch {}
        console.log("\n==============================================");
        console.log("Update Target LTV");
        console.log("==============================================");
        console.log("Strategy:", address(strategy));
        FormatUtils.logBps("New Target LTV:", newTargetLtv);
        FormatUtils.logBps("LTV Buffer:", ltvBufferBps);

        // Log current state
        console.log("\n--- Current State ---");
        _logStrategyState(strategy);

        // Get private key from environment
        uint256 managementPvtKey = vm.envUint("MANAGEMENT_PVT_KEY");
        vm.startBroadcast(managementPvtKey);

        // Set target LTV
        strategy.setTargetLtv(newTargetLtv, ltvBufferBps);

        vm.stopBroadcast();

        // Log new state
        console.log("\n--- New State ---");
        _logStrategyState(strategy);

        console.log("\n==============================================");
        console.log("Target LTV Updated Successfully!");
        console.log("==============================================");
    }
}
