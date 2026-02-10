// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script, console} from "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {ICeresBaseStrategy} from "ceres-strategies/src/interfaces/strategies/ICeresBaseStrategy.sol";
import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";
import {DeploymentConstantsUsdfEthereum} from "./DeploymentConstantsUsdfEthereum.sol";
import {FormatUtils} from "../../common/FormatUtils.sol";

/// @title StrategyOperations
/// @notice Base contract with common operations for USDf-sUSDf-USDC strategy scripts
/// @dev Contains reusable helper functions for swap data fetching, idle asset deposits, and logging
abstract contract StrategyOperations is Script, DeploymentConstantsUsdfEthereum {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   DEPOSIT IDLE ASSETS                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deposits idle assets (if any) before leveraging up
    /// @dev Swaps asset tokens to collateral and deposits them into the vault
    /// @param strategy The strategy contract
    function _depositIdleAssets(LeveragedEuler strategy) internal {
        // Check if asset and collateral are the same
        bool isAssetCollateral = strategy.IS_ASSET_COLLATERAL();

        if (isAssetCollateral) {
            console.log("\nAsset is collateral - no swap needed before deposit");
            return;
        }

        // Get current asset balance and withdrawal reserve
        uint256 assetBalance = IERC20(ASSET_TOKEN).balanceOf(address(strategy));
        uint256 withdrawalReserve = strategy.withdrawalReserve();

        console.log("\n--- Checking for Idle Assets ---");
        FormatUtils.logWithSymbol("Asset balance:     ", assetBalance, 18, "sUSDf");
        FormatUtils.logWithSymbol("Withdrawal reserve:", withdrawalReserve, 18, "sUSDf");

        // Calculate available assets for deposit
        if (assetBalance > withdrawalReserve) {
            uint256 idleAssets = assetBalance - withdrawalReserve;
            FormatUtils.logWithSymbol("Idle assets to deposit:", idleAssets, 18, "sUSDf");

            if (idleAssets > 0) {
                console.log("\nSwapping and depositing idle assets...");

                // Get swap data for asset -> collateral
                bytes memory assetToCollateralSwapData = _getSwapData(
                    address(ASSET_TOKEN),
                    address(COLLATERAL_TOKEN),
                    idleAssets,
                    true
                );

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
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    /// @param amount Amount to swap (debt amount for leverage down, will be converted internally if needed)
    /// @param isLeverageUp True for leverage up (exactIn), false for leverage down (exactOut if available)
    /// @return swapData Encoded swap calldata
    function _getSwapData(
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

        if (useParaswap) {
            // Use Paraswap
            // Leverage up: exactIn (spend exact debt/asset, get collateral)
            // Leverage down: exactOut (sell collateral, get exact debt)
            string memory swapType = isLeverageUp ? "exactIn" : "exactOut";
            swapData = _getParaswapSwapData(fromToken, toToken, swapAmount, swapType);
            console.log("Using Paraswap (", swapType, ")");
        } else {
            // Use Kyberswap (always exactIn)
            swapData = _getKyberswapSwapData(fromToken, toToken, swapAmount);
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
    function _getKyberswapSwapData(address fromToken, address toToken, uint256 amount) internal returns (bytes memory) {
        string[] memory inputs = new string[](8);
        inputs[0] = "node";
        inputs[1] = "script/js/kyber/printKyberswapSwapData.js";
        inputs[2] = vm.toString(block.chainid);
        inputs[3] = vm.toString(fromToken);
        inputs[4] = vm.toString(toToken);
        inputs[5] = vm.toString(amount);
        inputs[6] = vm.toString(CERES_SWAPPER_ADDRESS);
        inputs[7] = "exactIn";

        return vm.ffi(inputs);
    }

    /// @notice Get Paraswap swap data (supports exactIn/exactOut)
    function _getParaswapSwapData(
        address fromToken,
        address toToken,
        uint256 amount,
        string memory swapType
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
        inputs[6] = vm.toString(CERES_SWAPPER_ADDRESS);
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
        uint8 decimals = strategy.decimals();
        uint256 ONE_SHARE_UNIT = 10 ** decimals;

        (uint256 netAssets, uint256 collateral, uint256 debt) = strategy.getNetAssets();
        uint256 ltv = strategy.getStrategyLtv();
        uint256 totalAssets = strategy.totalAssets();
        uint256 targetLtv = strategy.targetLtvBps();
        uint256 withdrawalReserve = strategy.withdrawalReserve();
        uint256 currentRequestId = strategy.currentRequestId();
        uint256 totalSupply = strategy.totalSupply();
        uint256 pricePerShare = strategy.convertToAssets(ONE_SHARE_UNIT);

        console.log("\n--- Strategy State ---");
        FormatUtils.logWithSymbol("Total Assets:      ", totalAssets, decimals, "USDf");
        FormatUtils.logWithSymbol("Total Supply:      ", totalSupply, decimals, "ceres-USDf");
        FormatUtils.logWithSymbol("PricePerShare      ", pricePerShare, decimals, "USDf");

        FormatUtils.logWithSymbol("Net Assets:        ", netAssets, decimals, "USDf");
        FormatUtils.logWithSymbol("Collateral Amount: ", collateral, decimals, "sUSDf");
        FormatUtils.logWithSymbol("Debt Amount:       ", debt, 6, "USDC");
        FormatUtils.logWithSymbol("Withdrawal Reserve:", withdrawalReserve, 18, "USDf");
        console.log("Current Request ID:", currentRequestId);

        FormatUtils.logBps("Current LTV:       ", ltv);
        FormatUtils.logBps("Target LTV:        ", targetLtv);

        console.log("----------------------");
    }

    function _logStrategyConfig(LeveragedEuler strategy) internal view {
        uint8 decimals = strategy.decimals();

        uint128 withdawalReserve = strategy.withdrawalReserve();
        uint128 currentRequestId = strategy.currentRequestId();
        uint128 depositLimit = strategy.depositLimit();
        uint128 redeemLimitShares = strategy.redeemLimitShares();

        uint128 snapshotPps = strategy.snapshotPricePerShare();
        uint128 minDepositAmount = strategy.minDepositAmount();

        uint16 maxSlippageBps = strategy.maxSlippageBps();
        uint16 performanceFeeBps = strategy.performanceFeeBps();
        uint16 maxLossBps = strategy.maxLossBps();
        uint48 lastReportTimestamp = strategy.lastReportTimestamp();
        address performanceFeeRecipient = strategy.performanceFeeRecipient();

        console.log("\n--- Strategy Config ---");
        FormatUtils.logWithSymbol("Withdrawal Reserve:", withdawalReserve, decimals, "USDf");
        console.log("Current Request ID:", currentRequestId);
        FormatUtils.logWithSymbol("Deposit Limit:     ", depositLimit, decimals, "USDf");
        FormatUtils.logWithSymbol("Redeem Limit (shares):", redeemLimitShares, decimals, "ceres-USDf");
        FormatUtils.logWithSymbol("Snapshot PPS:      ", snapshotPps, decimals, "USDf");
        FormatUtils.logWithSymbol("Min Deposit Amount:", minDepositAmount, decimals, "USDf");

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
        // If asset is collateral, no swaps needed
        if (strategy.IS_ASSET_COLLATERAL()) {
            console.log("\nAsset is collateral - no swaps needed");
            return "";
        }

        // Calculate expected assets from shares
        uint256 expectedAssets = strategy.convertToAssets(request.totalShares);
        FormatUtils.logWithSymbol("\nExpected assets to withdraw:", expectedAssets, 18, "sUSDf");

        // Get current idle assets (balance - withdrawal reserve)
        uint256 assetBalance = IERC20(ASSET_TOKEN).balanceOf(address(strategy));
        uint256 withdrawalReserve = strategy.withdrawalReserve();
        uint256 idleAssets = assetBalance > withdrawalReserve ? assetBalance - withdrawalReserve : 0;

        FormatUtils.logWithSymbol("Asset balance:        ", assetBalance, 18, "sUSDf");
        FormatUtils.logWithSymbol("Withdrawal reserve:   ", withdrawalReserve, 18, "sUSDf");
        FormatUtils.logWithSymbol("Idle assets:          ", idleAssets, 18, "sUSDf");

        // Calculate how much more assets we need
        uint256 amountToFree = expectedAssets > idleAssets ? expectedAssets - idleAssets : 0;
        FormatUtils.logWithSymbol("Additional assets needed:", amountToFree, 18, "sUSDf");

        // Build collateral -> asset swap data if needed
        bytes memory collateralToAssetSwapData = "";
        if (amountToFree > 0) {
            console.log("\nFetching collateral -> asset swap data...");
            collateralToAssetSwapData = _getSwapData(
                address(COLLATERAL_TOKEN),
                address(ASSET_TOKEN),
                amountToFree,
                false // Use exactIn for collateral -> asset (Kyberswap)
            );
        }

        // Calculate rebalance amount (debt to repay)
        uint256 rebalanceAmount = _getRebalanceAmountForWithdraw(strategy, expectedAssets);
        FormatUtils.logWithSymbol("\nDebt to repay (rebalance amount):", rebalanceAmount, 6, "USDC");

        // Build flash loan swap data if rebalancing is needed
        bytes memory flashLoanSwapData = "";
        if (rebalanceAmount > 0) {
            console.log("\nFetching deleverage swap data (collateral -> debt)...");
            flashLoanSwapData = _getSwapData(address(COLLATERAL_TOKEN), address(DEBT_TOKEN), rebalanceAmount, false);
        }

        // Encode extraData
        extraData = abi.encode(flashLoanSwapData, collateralToAssetSwapData);
        console.log("\n ExtraData built successfully");
    }

    /// @notice Calculates how much debt needs to be repaid for a withdrawal
    /// @param strategy The strategy contract
    /// @param withdrawAmount The amount of assets to withdraw
    /// @return rebalanceAmount The amount of debt to repay
    function _getRebalanceAmountForWithdraw(
        LeveragedEuler strategy,
        uint256 withdrawAmount
    ) internal view returns (uint256 rebalanceAmount) {
        (uint256 netAssets, , uint256 totalDebt) = strategy.getNetAssets();

        console.log("\n--- Calculating Rebalance Amount ---");
        FormatUtils.logWithSymbol("Net assets:     ", netAssets, 18, "sUSDf");
        FormatUtils.logWithSymbol("Total debt:     ", totalDebt, 6, "USDC");
        FormatUtils.logWithSymbol("Withdraw amount:", withdrawAmount, 18, "sUSDf");

        // Cap withdraw amount at net assets
        if (withdrawAmount > netAssets) {
            withdrawAmount = netAssets;
            FormatUtils.logWithSymbol("Capped withdraw amount to net assets:", withdrawAmount, 18, "sUSDf");
        }

        // Calculate target debt after withdrawal
        uint256 targetDebt = LeverageLib.computeTargetDebt(
            netAssets - withdrawAmount,
            strategy.targetLtvBps(),
            strategy.oracleAdapter()
        );

        FormatUtils.logWithSymbol("Target debt after withdrawal:", targetDebt, 6, "USDC");

        // Rebalance amount is the difference between current and target debt
        rebalanceAmount = totalDebt > targetDebt ? totalDebt - targetDebt : 0;
        FormatUtils.logWithSymbol("Calculated rebalance amount: ", rebalanceAmount, 6, "USDC");

        return rebalanceAmount;
    }
}
