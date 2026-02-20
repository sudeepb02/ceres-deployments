// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CeresSwapper} from "ceres-strategies/src/periphery/CeresSwapper.sol";
import {DeploymentConstants} from "../common/DeploymentConstants.sol";

/// @title Deploy02_CeresSwapper
/// @notice Deploys the CeresSwapper contract
/// @dev CeresSwapper is used across multiple strategies
contract Deploy02_CeresSwapper is Script, DeploymentConstants {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    bool constant VERIFY_CONTRACT = false;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN DEPLOYMENT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        console.log("==============================================");
        console.log("Deploying CeresSwapper");
        console.log("==============================================");
        console.log("Deployer:", CERES_DEPLOYER);
        console.log("Kyber Scale Helper:", KYBER_SCALE_HELPER);
        console.log("Augustus Registry:", AUGUSTUS_REGISTRY);

        // Check if already deployed
        if (isSwapperDeployed()) {
            console.log("\nCeresSwapper already deployed at:", CERES_SWAPPER_ADDRESS);
            console.log("Skipping deployment...");
            return;
        }

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        CeresSwapper swapper = new CeresSwapper(CERES_DEPLOYER, KYBER_SCALE_HELPER, AUGUSTUS_REGISTRY);

        console.log("\nCeresSwapper deployed at:", address(swapper));

        vm.stopBroadcast();

        // Verify
        if (VERIFY_CONTRACT) {
            console.log("\nVerifying contract...");
            _verifyContract(address(swapper));
        }

        console.log("\n==============================================");
        console.log("Deployment complete!");
        console.log("==============================================");
        console.log("\nIMPORTANT: Update CERES_SWAPPER_ADDRESS in DeploymentConstants.sol:");
        console.log("address internal constant CERES_SWAPPER_ADDRESS =", address(swapper), ";");
        console.log("\nNOTE: Swap providers will be configured in the strategy-specific configuration script");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   VERIFICATION                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _verifyContract(address swapper) internal {
        try vm.parseBytes(vm.envString("ETHERSCAN_API_KEY")) {
            string[] memory args = new string[](7);
            args[0] = "forge";
            args[1] = "verify-contract";
            args[2] = vm.toString(swapper);
            args[3] = "CeresSwapper";
            args[4] = "--constructor-args";
            args[5] = vm.toString(abi.encode(CERES_DEPLOYER, KYBER_SCALE_HELPER, AUGUSTUS_REGISTRY));
            args[6] = "--watch";

            vm.ffi(args);
            console.log("Contract verified successfully");
        } catch {
            console.log("Verification skipped (ETHERSCAN_API_KEY not set)");
        }
    }
}
