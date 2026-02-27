// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {IEVault} from "ceres-strategies/src/interfaces/euler/IEVault.sol";
import {StrategyOperations} from "./StrategyOperations.sol";
import {FormatUtils} from "../common/FormatUtils.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

/// @title UpdateTargetLtv
/// @notice Generic script to update the target LTV for any leveraged strategy
/// @dev Reads strategy address from STRATEGY_ADDRESS and new target LTV from NEW_TARGET_LTV env vars
/// @dev Usage: STRATEGY_ADDRESS=0x... NEW_TARGET_LTV=8300 forge script script/common/operations/UpdateTargetLtv.s.sol
contract GetData is StrategyOperations {
    using Math for uint256;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function run() external {
        // Get contract instances
        LeveragedEuler strategy = _getStrategy();
        uint16 BPS_PRECISION = 100_00;

        console.log("\n==============================================");
        console.log("==============================================");
        console.log("Strategy:", address(strategy));

        // ILeveragedEuler leveragedEuler = ILeveragedEuler(address(strategy));

        (address collateralVault, address _borrowVault, address vaultConnector) = strategy.getMarketDetails();
        console.log("Collateral Vault:", collateralVault);
        console.log("Borrow Vault:", _borrowVault);
        console.log("Vault Connector:", vaultConnector);

        IEVault borrowVault = IEVault(_borrowVault);

        console.log("\n==============================================");
        console.log("\nUSING LIQUIDATION LTV FLAG");
        console.log("\n==============================================");
        {
            (uint256 collateralValue, uint256 liabilityValue) = borrowVault.accountLiquidity(address(strategy), true);

            FormatUtils.log("Collateral Value:", collateralValue, 18);
            FormatUtils.log("Liability Value:", liabilityValue, 18);

            // Round-up the strategy LTV to be on the conservative side
            uint256 ltvBps = (liabilityValue.mulDiv(BPS_PRECISION, collateralValue, Math.Rounding.Ceil));

            console.log("LTV (using liquidation flag):", ltvBps, "bps");
        }

        console.log("\n==============================================");
        console.log("\nWITHOUT USING LIQUIDATION LTV FLAG");
        console.log("\n==============================================");

        {
            (uint256 collateralValue, uint256 liabilityValue) = borrowVault.accountLiquidity(address(strategy), false);

            FormatUtils.log("Collateral Value:", collateralValue, 18);
            FormatUtils.log("Liability Value:", liabilityValue, 18);

            // Round-up the strategy LTV to be on the conservative side
            uint256 ltvBps = (liabilityValue.mulDiv(BPS_PRECISION, collateralValue, Math.Rounding.Ceil));

            console.log("LTV (using liquidation flag):", ltvBps, "bps");
        }

        console.log("\n==============================================");
        console.log("\nUPDATED CALCULATION AND LTV");
        console.log("\n==============================================");

        {
            (uint256 collateralValue, uint256 liabilityValue) = borrowVault.accountLiquidity(address(strategy), true);

            FormatUtils.log("Collateral Value:", collateralValue, 18);
            FormatUtils.log("Liability Value:", liabilityValue, 18);

            uint256 maxLtv = borrowVault.LTVBorrow(collateralVault);
            console.log("Max LTV from vault (raw):", maxLtv);
            FormatUtils.log("Max LTV for collateral vault:", maxLtv, 4);

            // collateralValue returned by Euler is risk adjusted value
            // hence to calculate actual collateral value, it needs to be divided by collateralization ratio (LTV) of the market
            uint256 actualCollateralValue = collateralValue.mulDiv(BPS_PRECISION, maxLtv, Math.Rounding.Floor);

            // Round-up the strategy LTV to be on the conservative side
            uint256 ltvBps = liabilityValue.mulDiv(BPS_PRECISION, actualCollateralValue, Math.Rounding.Ceil);
            console.log("LTV (using adjusted collateral):", ltvBps, "bps");
        }

        // Log current state
        console.log("\n--- Current State ---");
        _logStrategyState(strategy);

        console.log("\n==============================================");
        console.log("==============================================");
    }
}
