// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {StrategyOperations} from "../StrategyOperations.sol";

import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";

/// @title FlashLoanProviderConfigUpdate
/// @notice Script to leverage up the USDf-sUSDf-USDC strategy
/// @dev Borrows more debt and swaps it for collateral to increase leverage
contract FlashLoanProviderConfigUpdate is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = LeveragedEuler(LEVERAGED_EULER_STRATEGY_ADDRESS);

        // Log current state
        console.log("\n--- Current State ---");
        _logStrategyState(strategy);

        FlashLoanRouter flashLoanRouter = FlashLoanRouter(FLASH_LOAN_ROUTER_ADDRESS);
        console.log("\nFlash Loan Router Address:", address(flashLoanRouter));

        (FlashLoanRouter.FlashSource source, address lender, bool enabled) = flashLoanRouter.flashConfig(
            address(strategy)
        );
        console.log("Flash Loan Config for Strategy:");
        console.log("  Provider:", lender);
        console.log("  Source:", uint8(source));
        console.log("  Is Active:", enabled);

        uint256 deployerPvtKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPvtKey);

        flashLoanRouter.setFlashConfig(
            address(strategy),
            FlashLoanRouter.FlashSource.ERC3156,
            SILO_USDC_FLASH_LOAN_PROVIDER,
            true
        );

        vm.stopBroadcast();

        // Log new state
        console.log("\n--- New State ---");
        _logStrategyState(strategy);

        (source, lender, enabled) = flashLoanRouter.flashConfig(address(strategy));
        console.log("Flash Loan Config for Strategy:");
        console.log("  Provider:", lender);
        console.log("  Source:", uint8(source));
        console.log("  Is Active:", enabled);
    }
}
