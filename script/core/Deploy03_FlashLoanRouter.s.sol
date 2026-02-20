// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RoleManager} from "ceres-strategies/src/periphery/RoleManager.sol";
import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";
import {DeploymentConstants} from "../common/DeploymentConstants.sol";

/// @title Deploy03_FlashLoanRouter
/// @notice Deploys the FlashLoanRouter contract
/// @dev This contract routes flash loans and can be reused across multiple strategies
contract Deploy03_FlashLoanRouter is Script, DeploymentConstants {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    bool constant VERIFY_CONTRACT = false;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN DEPLOYMENT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        console.log("==============================================");
        console.log("Deploying FlashLoanRouter");
        console.log("==============================================");

        // Check dependencies
        if (!isRoleManagerDeployed()) {
            console.log("\nERROR: RoleManager not deployed yet!");
            console.log("Please deploy RoleManager first (Deploy01_RoleManager)");
            revert("RoleManager not deployed");
        }

        console.log("RoleManager address:", ROLE_MANAGER_ADDRESS);

        // Check if already deployed
        if (isFlashLoanRouterDeployed()) {
            console.log("\nFlashLoanRouter already deployed at:", FLASH_LOAN_ROUTER_ADDRESS);
            console.log("Skipping deployment...");
            return;
        }

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FlashLoanRouter flashLoanRouter = new FlashLoanRouter(ROLE_MANAGER_ADDRESS);

        console.log("\nFlashLoanRouter deployed at:", address(flashLoanRouter));

        vm.stopBroadcast();

        // Verify
        if (VERIFY_CONTRACT) {
            console.log("\nVerifying contract...");
            _verifyContract(address(flashLoanRouter));
        }

        console.log("\n==============================================");
        console.log("Deployment complete!");
        console.log("==============================================");
        console.log("\nIMPORTANT: Update FLASH_LOAN_ROUTER_ADDRESS in DeploymentConstants.sol:");
        console.log("address internal constant FLASH_LOAN_ROUTER_ADDRESS =", address(flashLoanRouter), ";");
        console.log("\nNOTE: Flash loan configuration will be done in the strategy-specific configuration script");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   VERIFICATION                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _verifyContract(address flashLoanRouter) internal {
        try vm.parseBytes(vm.envString("ETHERSCAN_API_KEY")) {
            string[] memory args = new string[](7);
            args[0] = "forge";
            args[1] = "verify-contract";
            args[2] = vm.toString(flashLoanRouter);
            args[3] = "FlashLoanRouter";
            args[4] = "--constructor-args";
            args[5] = vm.toString(abi.encode(ROLE_MANAGER_ADDRESS));
            args[6] = "--watch";

            vm.ffi(args);
            console.log("Contract verified successfully");
        } catch {
            console.log("Verification skipped (ETHERSCAN_API_KEY not set)");
        }
    }
}
