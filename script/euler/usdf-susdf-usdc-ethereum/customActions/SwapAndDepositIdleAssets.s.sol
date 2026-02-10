// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {StrategyOperations} from "../StrategyOperations.sol";

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

        // Log current state
        console.log("\n--- Current State ---");
        _logStrategyState(strategy);

        uint256 keeperPvtKey = vm.envUint("KEEPER_PVT_KEY");
        vm.startBroadcast(keeperPvtKey);

        _depositIdleAssets(strategy);

        vm.stopBroadcast();

        // Log new state
        console.log("\n--- New State ---");
        _logStrategyState(strategy);
    }
}
