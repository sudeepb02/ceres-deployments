// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {DeploymentConstantsUsdfEthereum} from "./DeploymentConstantsUsdfEthereum.sol";

/// @title Deploy05_LeveragedEulerStrategy
/// @notice Deploys the LeveragedEuler strategy for USDf-sUSDf-USDC
/// @dev This is the main strategy contract
contract Deploy05_LeveragedEulerStrategy is Script, DeploymentConstantsUsdfEthereum {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    bool constant VERIFY_CONTRACT = false;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN DEPLOYMENT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external returns (address) {
        console.log("==============================================");
        console.log("Deploying LeveragedEuler Strategy");
        console.log("==============================================");
        console.log("Strategy Name:", STRATEGY_NAME);
        console.log("Strategy Symbol:", STRATEGY_SYMBOL);
        console.log("Asset Token:", ASSET_TOKEN);
        console.log("Collateral Token:", COLLATERAL_TOKEN);
        console.log("Debt Token:", DEBT_TOKEN);
        console.log("Collateral Vault:", COLLATERAL_VAULT);
        console.log("Debt Vault:", DEBT_VAULT);
        console.log("EVC:", EVC);

        // Check dependencies
        if (!isRoleManagerDeployed()) {
            console.log("\nERROR: RoleManager not deployed yet!");
            console.log("Please deploy RoleManager first (Deploy01_RoleManager)");
            revert("RoleManager not deployed");
        }

        console.log("RoleManager:", ROLE_MANAGER_ADDRESS);

        // Check if already deployed
        if (LEVERAGED_EULER_STRATEGY_ADDRESS != address(0)) {
            console.log("\nLeveragedEuler Strategy already deployed at:", LEVERAGED_EULER_STRATEGY_ADDRESS);
            console.log("Skipping deployment...");
            return LEVERAGED_EULER_STRATEGY_ADDRESS;
        }

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("\nDeployer Address:", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "LeveragedEuler.sol:LeveragedEuler",
            deployerAddress,
            abi.encodeCall(
                LeveragedEuler.initialize,
                (
                    ASSET_TOKEN,
                    STRATEGY_NAME,
                    STRATEGY_SYMBOL,
                    COLLATERAL_TOKEN,
                    DEBT_TOKEN,
                    COLLATERAL_VAULT,
                    DEBT_VAULT,
                    EVC,
                    ROLE_MANAGER_ADDRESS
                )
            )
        );

        LeveragedEuler strategy = LeveragedEuler(proxy);

        console.log("\nLeveragedEuler Strategy deployed at:", address(strategy));

        vm.stopBroadcast();

        // Verify
        if (VERIFY_CONTRACT) {
            console.log("\nVerifying contract...");
            _verifyContract(address(strategy));
        }

        console.log("\n==============================================");
        console.log("Deployment complete!");
        console.log("==============================================");
        console.log("\nIMPORTANT: Update LEVERAGED_EULER_STRATEGY_ADDRESS in DeploymentConstantsUsdfEthereum.sol:");
        console.log("address internal constant LEVERAGED_EULER_STRATEGY_ADDRESS =", address(strategy), ";");
        console.log("\nNEXT STEPS:");
        console.log("1. Update the address in DeploymentConstantsUsdfEthereum.sol");
        console.log("2. Run Deploy06_ConfigureStrategy to initialize the strategy");

        return address(strategy);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   VERIFICATION                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _verifyContract(address strategy) internal {
        try vm.parseBytes(vm.envString("ETHERSCAN_API_KEY")) {
            string[] memory args = new string[](7);
            args[0] = "forge";
            args[1] = "verify-contract";
            args[2] = vm.toString(strategy);
            args[3] = "LeveragedEuler";
            args[4] = "--constructor-args";
            args[5] = vm.toString(
                abi.encode(
                    ASSET_TOKEN,
                    STRATEGY_NAME,
                    STRATEGY_SYMBOL,
                    COLLATERAL_TOKEN,
                    DEBT_TOKEN,
                    COLLATERAL_VAULT,
                    DEBT_VAULT,
                    EVC,
                    ROLE_MANAGER_ADDRESS
                )
            );
            args[6] = "--watch";

            vm.ffi(args);
            console.log("Contract verified successfully");
        } catch {
            console.log("Verification skipped (ETHERSCAN_API_KEY not set)");
        }
    }
}
