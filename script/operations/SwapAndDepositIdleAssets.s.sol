// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {StrategyOperations} from "./StrategyOperations.sol";

/// @title SwapAndDepositIdleAssets
/// @notice Generic script to swap and deposit idle assets for any strategy
/// @dev Reads strategy address from STRATEGY_ADDRESS env var
/// @dev Usage: STRATEGY_ADDRESS=0x... forge script script/common/operations/SwapAndDepositIdleAssets.s.sol
contract SwapAndDepositIdleAssets is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = _getStrategy();

        console.log("\n==============================================");
        console.log("Swap and Deposit Idle Assets");
        console.log("==============================================");
        console.log("Strategy:", address(strategy));

        // Log current state
        console.log("\n--- Current State ---");
        _logStrategyState(strategy);

        // Get private key from environment
        uint256 keeperPvtKey = vm.envUint("KEEPER_PVT_KEY");
        vm.startBroadcast(keeperPvtKey);

        _depositIdleAssets(strategy);

        vm.stopBroadcast();

        // Log new state
        console.log("\n--- New State ---");
        _logStrategyState(strategy);

        console.log("\n==============================================");
        console.log("Idle Assets Deposited Successfully!");
        console.log("==============================================");
    }
}
