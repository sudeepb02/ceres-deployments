// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {ICeresBaseStrategy} from "ceres-strategies/src/interfaces/strategies/ICeresBaseStrategy.sol";
import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";
import {CeresSwapper} from "ceres-strategies/src/periphery/CeresSwapper.sol";
import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";
import {FormatUtils} from "../common/FormatUtils.sol";

/// @title StrategyOperations
/// @notice Generic base contract with common operations for strategy operational scripts
/// @dev Contains reusable helper functions for swap data fetching, idle asset deposits, and logging
/// @dev Strategy-agnostic - reads all configuration from the strategy contract itself
abstract contract StrategyOperations is Script {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   STRATEGY ACCESS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Get the strategy address from environment variable
    /// @return strategy The strategy contract instance
    function _getStrategy() internal view returns (LeveragedEuler strategy) {
        address strategyAddress = vm.envAddress("STRATEGY_ADDRESS");
        require(strategyAddress != address(0), "STRATEGY_ADDRESS not set");
        return LeveragedEuler(strategyAddress);
    }

    /// @notice Get token addresses from the strategy
    /// @param strategy The strategy contract
    /// @return asset The asset token address
    /// @return collateral The collateral token address
    /// @return debt The debt token address
    function _getTokens(
        LeveragedEuler strategy
    ) internal view returns (address asset, address collateral, address debt) {
        asset = strategy.asset();
        collateral = address(strategy.COLLATERAL_TOKEN());
        debt = address(strategy.DEBT_TOKEN());
    }

    /// @notice Get periphery contract addresses from the strategy
    /// @param strategy The strategy contract
    /// @return swapper The CeresSwapper address
    /// @return flashLoanRouter The FlashLoanRouter address
    function _getPeripheryContracts(
        LeveragedEuler strategy
    ) internal view returns (address swapper, address flashLoanRouter) {
        (, , , swapper, flashLoanRouter) = strategy.getLeveragedStrategyConfig();
    }

    function _isAssetCollateral(LeveragedEuler strategy) internal view returns (bool) {
        (address asset, address collateral, ) = _getTokens(strategy);
        return asset == collateral;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   DEPOSIT IDLE ASSETS                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deposits idle assets (if any) before leveraging up
    /// @dev Swaps asset tokens to collateral and deposits them into the vault
    /// @param strategy The strategy contract
    function _depositIdleAssets(LeveragedEuler strategy) internal {
        (address asset, address collateral, ) = _getTokens(strategy);

        if (_isAssetCollateral(strategy)) {
            console.log("\nAsset is collateral - no swap needed before deposit");
            return;
        }

        // Get current asset balance and withdrawal reserve
        uint256 assetBalance = IERC20(asset).balanceOf(address(strategy));
        uint256 withdrawalReserve = strategy.withdrawalReserve();

        console.log("\n--- Checking for Idle Assets ---");
        uint8 assetDecimals = IERC20Metadata(asset).decimals();

        FormatUtils.logWithSymbol("Asset balance:     ", assetBalance, assetDecimals, "AssetTokens");
        FormatUtils.logWithSymbol("Withdrawal reserve:", withdrawalReserve, assetDecimals, "AssetTokens");

        // Calculate available assets for deposit
        if (assetBalance > withdrawalReserve) {
            uint256 idleAssets = assetBalance - withdrawalReserve;
            FormatUtils.logWithSymbol("Idle assets to deposit:", idleAssets, assetDecimals, "AssetTokens");

            if (idleAssets > 0) {
                console.log("\nSwapping and depositing idle assets...");

                // Get swap data for asset -> collateral
                bytes memory assetToCollateralSwapData = _getSwapData(strategy, asset, collateral, idleAssets, true);

                // Execute swapAndDepositCollateral
                strategy.swapAndDepositCollateral(idleAssets, assetToCollateralSwapData);

                console.log("Idle assets deposited successfully");
            }
        } else {
            console.log("No idle assets to deposit");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   SWAP DATA HELPERS                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Get swap data from aggregator based on configuration
    /// @param strategy The strategy contract
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    /// @param amount Amount to swap (debt amount for leverage down, will be converted internally if needed)
    /// @param isLeverageUp True for leverage up (exactIn), false for leverage down (exactOut if available)
    /// @return swapData Encoded swap calldata
    function _getSwapData(
        LeveragedEuler strategy,
        address fromToken,
        address toToken,
        uint256 amount,
        bool isLeverageUp
    ) internal returns (bytes memory swapData) {
        console.log("\nFetching swap data...");
        console.log("From:", fromToken);
        console.log("To:", toToken);
        console.log("Amount (input):", amount);

        // Determine which aggregator and swap type to use
        bool useParaswap = _shouldUseParaswap(isLeverageUp);

        uint256 swapAmount = amount;
        (address swapper, ) = _getPeripheryContracts(strategy);

        if (useParaswap) {
            // Use Paraswap
            // Leverage up: exactIn (spend exact debt/asset, get collateral)
            // Leverage down: exactOut (sell collateral, get exact debt)
            string memory swapType = isLeverageUp ? "exactIn" : "exactOut";
            swapData = _getParaswapSwapData(fromToken, toToken, swapAmount, swapType, swapper);
            console.log("Using Paraswap (", swapType, ")");
        } else {
            // Use Kyberswap (always exactIn)
            swapData = _getKyberswapSwapData(fromToken, toToken, swapAmount, swapper);
            console.log("Using Kyberswap (exactIn)");
        }

        console.log("Swap data length:", swapData.length);
    }

    /// @notice Determine if Paraswap should be used
    /// @dev Override this in child contracts to customize swap provider selection
    /// @param isLeverageUp True for leverage up, false for leverage down
    /// @return true if Paraswap should be used, false for Kyberswap
    function _shouldUseParaswap(bool isLeverageUp) internal view virtual returns (bool) {
        // Default to Kyberswap for all operations, override in child if needed
        return false;
    }

    /// @notice Get Kyberswap swap data (exactIn)
    function _getKyberswapSwapData(
        address fromToken,
        address toToken,
        uint256 amount,
        address swapper
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](8);
        inputs[0] = "node";
        inputs[1] = "script/js/kyber/printKyberswapSwapData.js";
        inputs[2] = vm.toString(block.chainid);
        inputs[3] = vm.toString(fromToken);
        inputs[4] = vm.toString(toToken);
        inputs[5] = vm.toString(amount);
        inputs[6] = vm.toString(swapper);
        inputs[7] = "exactIn";

        return vm.ffi(inputs);
    }

    /// @notice Get Paraswap swap data (supports exactIn/exactOut)
    function _getParaswapSwapData(
        address fromToken,
        address toToken,
        uint256 amount,
        string memory swapType,
        address swapper
    ) internal returns (bytes memory) {
        uint8 fromTokenDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toTokenDecimals = IERC20Metadata(toToken).decimals();

        string[] memory inputs = new string[](10);
        inputs[0] = "node";
        inputs[1] = "script/js/paraswap/printParaswapSwapData.js";
        inputs[2] = vm.toString(block.chainid);
        inputs[3] = vm.toString(fromToken);
        inputs[4] = vm.toString(toToken);
        inputs[5] = vm.toString(amount);
        inputs[6] = vm.toString(swapper);
        inputs[7] = swapType;
        inputs[8] = vm.toString(fromTokenDecimals);
        inputs[9] = vm.toString(toTokenDecimals);

        return vm.ffi(inputs);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   LOGGING HELPERS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Log current strategy state
    function _logStrategyState(LeveragedEuler strategy) internal view {
        (address asset, address collateral, address debt) = _getTokens(strategy);

        uint8 decimals = strategy.decimals();
        uint8 assetDecimals = IERC20Metadata(asset).decimals();

        (uint256 netAssets, uint256 collateralAmount, uint256 debtAmount) = strategy.getNetAssets();
        uint256 ltv = strategy.getStrategyLtv();
        (, uint16 targetLtv, , , ) = strategy.getLeveragedStrategyConfig();
        uint256 withdrawalReserve = strategy.withdrawalReserve();
        uint256 currentRequestId = strategy.currentRequestId();

        console.log("\n--- Strategy State ---");
        FormatUtils.logWithSymbol("Total Assets:      ", strategy.totalAssets(), assetDecimals, "AssetTokens");
        FormatUtils.logWithSymbol("Total Supply:      ", strategy.totalSupply(), decimals, "shares");
        FormatUtils.logWithSymbol(
            "PricePerShare:     ",
            strategy.convertToAssets(10 ** decimals),
            assetDecimals,
            "AssetTokens"
        );

        FormatUtils.logWithSymbol("Net Assets:        ", netAssets, assetDecimals, "AssetTokens");
        FormatUtils.logWithSymbol(
            "Collateral Amount: ",
            collateralAmount,
            IERC20Metadata(collateral).decimals(),
            "CollateralTokens"
        );
        FormatUtils.logWithSymbol("Debt Amount:       ", debtAmount, IERC20Metadata(debt).decimals(), "DebtTokens");
        FormatUtils.logWithSymbol("Withdrawal Reserve:", withdrawalReserve, assetDecimals, "AssetTokens");
        console.log("Current Request ID:", currentRequestId);

        FormatUtils.logBps("Current LTV:       ", ltv);
        FormatUtils.logBps("Target LTV:        ", targetLtv);

        console.log("----------------------");
    }

    /// @notice Log strategy configuration
    function _logStrategyConfig(LeveragedEuler strategy) internal view {
        (address asset, , ) = _getTokens(strategy);

        uint8 decimals = strategy.decimals();
        uint8 assetDecimals = IERC20Metadata(asset).decimals();

        uint128 withdrawalReserve = strategy.withdrawalReserve();
        uint128 currentRequestId = strategy.currentRequestId();
        (uint128 depositLimit, uint128 redeemLimitShares, uint128 minDepositAmount) = strategy.getDepositWithdrawLimits();
        (
            uint16 maxSlippageBps,
            uint16 performanceFeeBps,
            uint16 maxLossBps,
            uint48 lastReportTimestamp,
            address performanceFeeRecipient,
        ) = strategy.getBaseStrategyConfig();

        console.log("\n--- Strategy Config ---");
        FormatUtils.logWithSymbol("Withdrawal Reserve:", withdrawalReserve, assetDecimals, "AssetTokens");
        console.log("Current Request ID:", currentRequestId);
        FormatUtils.logWithSymbol("Deposit Limit:     ", depositLimit, assetDecimals, "AssetTokens");
        FormatUtils.logWithSymbol("Redeem Limit (shares):", redeemLimitShares, decimals, "ShareTokens");
        FormatUtils.logWithSymbol("Min Deposit Amount:", minDepositAmount, assetDecimals, "AssetTokens");

        FormatUtils.logBps("Max Slippage Bps:       ", maxSlippageBps);
        FormatUtils.logBps("Performance Fee Bps:    ", performanceFeeBps);
        FormatUtils.logBps("Max Loss Bps:           ", maxLossBps);
        console.log("Last Report Timestamp:         ", lastReportTimestamp);
        console.log("Performance Fee Recipient:     ", performanceFeeRecipient);

        console.log("----------------------");
    }

    /// @notice Assert LTV is near target with tolerance
    function _assertLtvNearTarget(
        uint256 actualLtv,
        uint256 targetLtv,
        uint256 toleranceBps,
        string memory context
    ) internal view {
        uint256 diff = actualLtv > targetLtv ? actualLtv - targetLtv : targetLtv - actualLtv;

        if (diff <= toleranceBps) {
            console.log("[OK]", context, "- LTV is within tolerance");
            console.log("     Actual bps:", actualLtv);
            console.log("     Target bps:", targetLtv);
            console.log("     Diff bps:", diff);
        } else {
            console.log("[WARNING]", context, "- LTV outside tolerance");
            console.log("     Actual bps:", actualLtv);
            console.log("     Target bps:", targetLtv);
            console.log("     Diff bps:", diff);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                               WITHDRAWAL / REDEEM HELPERS                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Builds the extraData parameter for processCurrentRequest
    /// @param strategy The strategy contract
    /// @param requestId The current request ID
    /// @param request The request details
    /// @return extraData Encoded swap data for deleveraging and asset conversion
    function _buildProcessRequestData(
        LeveragedEuler strategy,
        uint128 requestId,
        ICeresBaseStrategy.RequestDetails memory request
    ) internal returns (bytes memory extraData) {
        (address asset, address collateral, address debt) = _getTokens(strategy);

        // If asset is collateral, no swaps needed
        if (_isAssetCollateral(strategy)) {
            console.log("\nAsset is collateral - no swaps needed");
            return "";
        }

        uint256 amountToFree;
        uint256 expectedAssets;
        bytes memory collateralToAssetSwapData = "";

        // Code block to prevent stack too deep error
        {
            uint8 assetDecimals = IERC20Metadata(asset).decimals();

            // Calculate expected assets from shares
            expectedAssets = strategy.convertToAssets(request.totalShares);
            FormatUtils.logWithSymbol("\nExpected assets to withdraw:", expectedAssets, assetDecimals, "AssetTokens");

            // Get current idle assets (balance - withdrawal reserve)
            uint256 assetBalance = IERC20(asset).balanceOf(address(strategy));
            uint256 withdrawalReserve = strategy.withdrawalReserve();
            uint256 idleAssets = assetBalance > withdrawalReserve ? assetBalance - withdrawalReserve : 0;

            FormatUtils.logWithSymbol("Asset balance:        ", assetBalance, assetDecimals, "AssetTokens");
            FormatUtils.logWithSymbol("Withdrawal reserve:   ", withdrawalReserve, assetDecimals, "AssetTokens");
            FormatUtils.logWithSymbol("Idle assets:          ", idleAssets, assetDecimals, "AssetTokens");

            // Calculate how much more assets we need
            amountToFree = expectedAssets > idleAssets ? expectedAssets - idleAssets : 0;
            FormatUtils.logWithSymbol("Additional assets needed:", amountToFree, assetDecimals, "AssetTokens");
        }

        // Build collateral -> asset swap data if needed
        if (amountToFree > 0) {
            uint256 amountInCollateral = strategy.oracleAdapter().convertAssetsToCollateral(amountToFree);
            FormatUtils.logWithSymbol(
                "\nAmount to free in collateral:",
                amountInCollateral,
                IERC20Metadata(collateral).decimals(),
                "Collateral Tokens"
            );

            console.log("\nFetching collateral -> asset swap data...");
            collateralToAssetSwapData = _getSwapData(
                strategy,
                collateral,
                asset,
                amountInCollateral,
                false // leverageDown
            );
        }

        // Calculate rebalance amount (debt to repay)
        uint256 rebalanceAmount = _getRebalanceAmountForWithdraw(strategy, expectedAssets);
        FormatUtils.logWithSymbol(
            "\nDebt to repay (rebalance amount):",
            rebalanceAmount,
            IERC20Metadata(debt).decimals(),
            "Debt Tokens"
        );

        // Build flash loan swap data if rebalancing is needed
        bytes memory flashLoanSwapData = "";
        if (rebalanceAmount > 0) {
            uint256 rebalanceAmountInCollateral = strategy.oracleAdapter().convertDebtToCollateral(rebalanceAmount);
            FormatUtils.logWithSymbol(
                "Rebalance amount in collateral:",
                rebalanceAmountInCollateral,
                IERC20Metadata(collateral).decimals(),
                "Collateral Tokens"
            );

            // Use exactIn for collateral -> asset (Kyberswap)
            console.log("\nFetching deleverage swap data (collateral -> debt)...");
            flashLoanSwapData = _getSwapData(strategy, collateral, debt, rebalanceAmountInCollateral, false);
        }

        // Encode extraData
        extraData = abi.encode(flashLoanSwapData, collateralToAssetSwapData);
        console.log("\nExtraData built successfully");
    }

    /// @notice Calculates how much debt needs to be repaid for a withdrawal
    /// @param strategy The strategy contract
    /// @param withdrawAmount The amount of assets to withdraw
    /// @return rebalanceAmount The amount of debt to repay
    function _getRebalanceAmountForWithdraw(
        LeveragedEuler strategy,
        uint256 withdrawAmount
    ) internal view returns (uint256 rebalanceAmount) {
        (address asset, , address debt) = _getTokens(strategy);

        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        uint8 debtDecimals = IERC20Metadata(debt).decimals();

        (uint256 netAssets, , uint256 totalDebt) = strategy.getNetAssets();

        console.log("\n--- Calculating Rebalance Amount ---");
        FormatUtils.logWithSymbol("Net assets:     ", netAssets, assetDecimals, "AssetTokens");
        FormatUtils.logWithSymbol("Total debt:     ", totalDebt, debtDecimals, "DebtTokens");
        FormatUtils.logWithSymbol("Withdraw amount:", withdrawAmount, assetDecimals, "AssetTokens");

        // Cap withdraw amount at net assets
        if (withdrawAmount > netAssets) {
            withdrawAmount = netAssets;
            FormatUtils.logWithSymbol(
                "Capped withdraw amount to net assets:",
                withdrawAmount,
                assetDecimals,
                "AssetTokens"
            );
        }

        // Calculate target debt after withdrawal
        (, uint16 targetLtvBps, , , ) = strategy.getLeveragedStrategyConfig();
        uint256 targetDebt = LeverageLib.computeTargetDebt(netAssets - withdrawAmount, targetLtvBps, strategy.oracleAdapter());

        FormatUtils.logWithSymbol("Target debt after withdrawal:", targetDebt, debtDecimals, "DebtTokens");

        // Rebalance amount is the difference between current and target debt
        rebalanceAmount = totalDebt > targetDebt ? totalDebt - targetDebt : 0;
        FormatUtils.logWithSymbol("Calculated rebalance amount: ", rebalanceAmount, debtDecimals, "DebtTokens");

        return rebalanceAmount;
    }
}
