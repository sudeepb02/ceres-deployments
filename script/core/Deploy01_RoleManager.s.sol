// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RoleManager} from "ceres-strategies/src/periphery/RoleManager.sol";
import {DeploymentConstants} from "../common/DeploymentConstants.sol";

/// @title Deploy01_RoleManager
/// @notice Deploys the RoleManager contract
/// @dev This contract manages access control for strategies and can be reused across multiple strategies
contract Deploy01_RoleManager is Script, DeploymentConstants {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    bool constant VERIFY_CONTRACT = false;

    // RoleManager configuration
    uint48 constant ROLE_MANAGER_DELAY = 2 days;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN DEPLOYMENT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get environment variables
        address management = vm.envAddress("DEPLOYER_ADDRESS");
        address keeper = vm.envAddress("KEEPER_ADDRESS");

        console.log("==============================================");
        console.log("Deploying RoleManager");
        console.log("==============================================");
        console.log("Management address:", management);
        console.log("Keeper address:", keeper);
        console.log("Delay:", ROLE_MANAGER_DELAY);

        // Check if already deployed
        if (isRoleManagerDeployed()) {
            console.log("\nRoleManager already deployed at:", ROLE_MANAGER_ADDRESS);
            console.log("Skipping deployment...");
            return;
        }

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        RoleManager roleManager = new RoleManager(ROLE_MANAGER_DELAY, management);

        console.log("\nRoleManager deployed at:", address(roleManager));

        // Grant roles
        roleManager.grantRole(MANAGEMENT_ROLE, management);
        roleManager.grantRole(KEEPER_ROLE, keeper);

        console.log("Roles granted:");
        console.log("  - MANAGEMENT_ROLE to:", management);
        console.log("  - KEEPER_ROLE to:", keeper);

        vm.stopBroadcast();

        // Verify
        if (VERIFY_CONTRACT) {
            console.log("\nVerifying contract...");
            _verifyContract(address(roleManager), management);
        }

        console.log("\n==============================================");
        console.log("Deployment complete!");
        console.log("==============================================");
        console.log("\nIMPORTANT: Update ROLE_MANAGER_ADDRESS in DeploymentConstants.sol:");
        console.log("address internal constant ROLE_MANAGER_ADDRESS =", address(roleManager), ";");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   VERIFICATION                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _verifyContract(address roleManager, address management) internal {
        try vm.parseBytes(vm.envString("ETHERSCAN_API_KEY")) {
            string[] memory args = new string[](7);
            args[0] = "forge";
            args[1] = "verify-contract";
            args[2] = vm.toString(roleManager);
            args[3] = "RoleManager";
            args[4] = "--constructor-args";
            args[5] = vm.toString(abi.encode(ROLE_MANAGER_DELAY, management));
            args[6] = "--watch";

            vm.ffi(args);
            console.log("Contract verified successfully");
        } catch {
            console.log("Verification skipped (ETHERSCAN_API_KEY not set)");
        }
    }
}
