// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script, console} from "forge-std/src/Script.sol";
import {EulerAdapterTypeOne as EulerOracleAdapter} from "ceres-strategies/src/periphery/EulerAdapterTypeOne.sol";
import {DeploymentConstantsUsdfEthereum} from "./DeploymentConstantsUsdfEthereum.sol";

/// @title Deploy04_EulerOracleAdapter
/// @notice Deploys the Euler Oracle Adapter for USDf-sUSDf-USDC strategy
/// @dev This adapter is specific to this strategy's oracle configuration
contract Deploy04_EulerOracleAdapter is Script, DeploymentConstantsUsdfEthereum {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    bool constant VERIFY_CONTRACT = false;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN DEPLOYMENT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external returns (address) {
        console.log("==============================================");
        console.log("Deploying Euler Oracle Adapter Type 1 for USDf-sUSDf-USDC Strategy");
        console.log("==============================================");
        console.log("Asset Token:", ASSET_TOKEN);
        console.log("Collateral Token:", COLLATERAL_TOKEN);
        console.log("Debt Token:", DEBT_TOKEN);
        console.log("Asset to Collateral Oracle:", ASSET_TO_COLLATERAL_ORACLE);
        console.log("Asset to USD Oracle:", ASSET_TO_USD_ORACLE);
        console.log("Debt to USD Oracle:", DEBT_TO_USD_ORACLE);

        // Check if already deployed
        if (EULER_ORACLE_ADAPTER_ADDRESS != address(0)) {
            console.log("\nEuler Oracle Adapter already deployed at:", EULER_ORACLE_ADAPTER_ADDRESS);
            console.log("Skipping deployment...");
            return EULER_ORACLE_ADAPTER_ADDRESS;
        }

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EulerOracleAdapter oracleAdapter = new EulerOracleAdapter(
            ORACLE_PRECISION,
            ASSET_TO_COLLATERAL_ORACLE,
            ASSET_TO_USD_ORACLE,
            DEBT_TO_USD_ORACLE,
            ASSET_TOKEN,
            COLLATERAL_TOKEN,
            DEBT_TOKEN,
            USD_TOKEN
        );

        console.log("\nEuler Oracle Adapter deployed at:", address(oracleAdapter));

        // Log oracle prices
        console.log("\nOracle Prices:");
        console.log("  Collateral price in Asset:", oracleAdapter.getCollateralPriceInAssetToken());
        console.log("  Asset price in USD:", oracleAdapter.getAssetPriceInUsd());
        console.log("  Debt price in USD:", oracleAdapter.getDebtPriceInUsd());

        vm.stopBroadcast();

        // Verify
        if (VERIFY_CONTRACT) {
            console.log("\nVerifying contract...");
            _verifyContract(address(oracleAdapter));
        }

        console.log("\n==============================================");
        console.log("Deployment complete!");
        console.log("==============================================");
        console.log("\nIMPORTANT: Update EULER_ORACLE_ADAPTER_ADDRESS in DeploymentConstantsUsdfEthereum.sol:");
        console.log("address internal constant EULER_ORACLE_ADAPTER_ADDRESS =", address(oracleAdapter), ";");

        return address(oracleAdapter);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   VERIFICATION                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _verifyContract(address oracleAdapter) internal {
        try vm.parseBytes(vm.envString("ETHERSCAN_API_KEY")) {
            string[] memory args = new string[](7);
            args[0] = "forge";
            args[1] = "verify-contract";
            args[2] = vm.toString(oracleAdapter);
            args[3] = "EulerAdapterTypeOne";
            args[4] = "--constructor-args";
            args[5] = vm.toString(
                abi.encode(
                    ORACLE_PRECISION,
                    ASSET_TO_COLLATERAL_ORACLE,
                    ASSET_TO_USD_ORACLE,
                    DEBT_TO_USD_ORACLE,
                    ASSET_TOKEN,
                    COLLATERAL_TOKEN,
                    DEBT_TOKEN,
                    USD_TOKEN
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
