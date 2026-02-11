// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";
import {StrategyOperations} from "./StrategyOperations.sol";

/// @title FlashLoanProviderUpdate
/// @notice Generic script to update flash loan provider configuration for any strategy
/// @dev Reads strategy address from STRATEGY_ADDRESS env var
/// @dev Reads flash loan config from FLASH_LOAN_PROVIDER and FLASH_LOAN_SOURCE env vars
/// @dev Usage: STRATEGY_ADDRESS=0x... FLASH_LOAN_PROVIDER=0x... FLASH_LOAN_SOURCE=0 forge script script/common/operations/FlashLoanProviderUpdate.s.sol
contract FlashLoanProviderUpdate is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = _getStrategy();

        console.log("\n==============================================");
        console.log("Flash Loan Provider Configuration Update");
        console.log("==============================================");
        console.log("Strategy:", address(strategy));

        // Log current state
        console.log("\n--- Current Strategy State ---");
        _logStrategyState(strategy);

        // Get flash loan router from strategy
        (, address flashLoanRouterAddress) = _getPeripheryContracts(strategy);
        FlashLoanRouter flashLoanRouter = FlashLoanRouter(flashLoanRouterAddress);

        console.log("\nFlash Loan Router Address:", address(flashLoanRouter));

        // Get current flash loan config
        (FlashLoanRouter.FlashSource currentSource, address currentLender, bool currentEnabled) = flashLoanRouter
            .flashConfig(address(strategy));
        console.log("\nCurrent Flash Loan Config:");
        console.log("  Provider:", currentLender);
        console.log("  Source:", uint8(currentSource));
        console.log("  Is Active:", currentEnabled);

        // Get new configuration from environment variables
        address newProvider = vm.envAddress("FLASH_LOAN_PROVIDER");
        uint8 sourceUint = uint8(vm.envUint("FLASH_LOAN_SOURCE"));

        FlashLoanRouter.FlashSource newSource = FlashLoanRouter.FlashSource(sourceUint);

        // Enabled flag (default: true)
        bool enabled = true;
        try vm.envBool("FLASH_LOAN_ENABLED") returns (bool _enabled) {
            enabled = _enabled;
        } catch {}
        console.log("\nNew Flash Loan Config:");
        console.log("  Provider:", newProvider);
        console.log("  Source:", uint8(newSource));
        console.log("  Is Active:", enabled);

        // Execute update
        uint256 deployerPvtKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPvtKey);

        flashLoanRouter.setFlashConfig(address(strategy), newSource, newProvider, enabled);

        vm.stopBroadcast();

        // Log new state
        console.log("\n--- Updated Configuration ---");
        (FlashLoanRouter.FlashSource updatedSource, address updatedLender, bool updatedEnabled) = flashLoanRouter
            .flashConfig(address(strategy));
        console.log("Flash Loan Config for Strategy:");
        console.log("  Provider:", updatedLender);
        console.log("  Source:", uint8(updatedSource));
        console.log("  Is Active:", updatedEnabled);

        console.log("\n==============================================");
        console.log("Flash Loan Provider Updated Successfully!");
        console.log("==============================================");
    }
}
