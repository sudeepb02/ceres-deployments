// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {LeveragedEulerV1} from "ceres-strategies-latest/src/strategies-v1/LeveragedEulerV1.sol";
import {LeveragedEuler} from "ceres-strategies-latest/src/strategies/LeveragedEuler.sol";

import {IEVault} from "ceres-strategies/src/interfaces/euler/IEVault.sol";
import {StrategyOperations} from "../../operations/StrategyOperations.sol";
import {FormatUtils} from "../../common/FormatUtils.sol";

import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

import {Options, Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title Upgrade contracts to latest version
contract Upgrade07_LeveragedEuler is StrategyOperations {
    using Math for uint256;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Initial deployed Leveraged Euler strategy proxy address
        address strategyProxy = 0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E;
        LeveragedEulerV1 strategy = LeveragedEulerV1(strategyProxy);

        address implAddrV1 = Upgrades.getImplementationAddress(strategyProxy);
        address adminAddr = Upgrades.getAdminAddress(strategyProxy);

        console.log("\n==============================================");
        console.log("Upgrading Leveraged Euler Strategy to latest version");
        console.log("==============================================");
        console.log("Strategy Proxy:", strategyProxy);
        console.log("Current Implementation (V1):", implAddrV1);
        console.log("Admin Address:", adminAddr);

        if (adminAddr == address(0)) {
            console.log("No admin found for the proxy. Cannot proceed with upgrade.");
            return;
        }

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("\nDeployer Address:", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        Options memory opts;
        opts.referenceContract = "LeveragedEulerV1.sol:LeveragedEulerV1";

        // Validate upgrade
        Upgrades.validateUpgrade("LeveragedEuler.sol:LeveragedEuler", opts);

        Upgrades.upgradeProxy(strategyProxy, "LeveragedEuler.sol", "");

        vm.stopBroadcast();

        address implAddrV2 = Upgrades.getImplementationAddress(strategyProxy);
        console.log("New Implementation (V2):", implAddrV2);

        require(implAddrV2 != implAddrV1, "Upgrade failed: Implementation address did not change");
        console.log("Upgrade successful: Implementation address updated");
    }
}
