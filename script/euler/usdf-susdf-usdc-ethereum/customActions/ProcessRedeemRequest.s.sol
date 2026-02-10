// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Script.sol";
import {LeveragedEuler} from "ceres-strategies/src/strategies/LeveragedEuler.sol";
import {ICeresBaseStrategy} from "ceres-strategies/src/interfaces/strategies/ICeresBaseStrategy.sol";
import {StrategyOperations} from "../StrategyOperations.sol";
import {FormatUtils} from "../../../common/FormatUtils.sol";

/// @title ProcessRedeemRequest
/// @notice Processes the current pending redeem request for the USDf-sUSDf-USDC strategy
/// @dev This script handles the async withdrawal flow by deleveraging and freeing assets as needed
contract ProcessRedeemRequest is StrategyOperations {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CONFIGURATION                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    bool constant EXACT_OUT_AVAILABLE = false;
    bool constant USE_FLASH_LOAN = true;

    // Tolerance for LTV checks (in bps)
    uint256 constant LTV_TOLERANCE_BPS = 50; // 0.5%

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MAIN EXECUTION                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    /// @notice Main execution function
    function run() external {
        // Load strategy
        LeveragedEuler strategy = LeveragedEuler(LEVERAGED_EULER_STRATEGY_ADDRESS);

        // Get keeper private key
        uint256 keeperPvtKey = vm.envUint("KEEPER_PVT_KEY");
        address keeper = vm.addr(keeperPvtKey);

        console.log("\n=== Processing Redeem Request ===");
        console.log("Strategy:", address(strategy));
        console.log("Keeper:", keeper);

        // Check if there's a pending request
        uint128 currentRequestId = strategy.currentRequestId();
        if (currentRequestId == 0) {
            console.log("\nNo pending requests to process (currentRequestId = 0)");
            return;
        }

        (uint128 totalShares, uint128 pps) = strategy.requestDetails(currentRequestId);

        ICeresBaseStrategy.RequestDetails memory request = ICeresBaseStrategy.RequestDetails({
            totalShares: totalShares,
            pricePerShare: pps
        });

        if (request.totalShares == 0) {
            console.log("\nNo pending requests to process (totalShares = 0)");
            return;
        }

        console.log("\nCurrent Request ID:", currentRequestId);
        FormatUtils.log("Total Shares:", request.totalShares, 18);
        FormatUtils.log("Price Per Share:", request.pricePerShare, 18);

        // Log strategy state before processing
        console.log("\n--- Strategy State BEFORE Processing ---");
        _logStrategyState(strategy);

        // Build extraData for processing
        bytes memory extraData = _buildProcessRequestData(strategy, currentRequestId, request);

        // Execute processCurrentRequest
        vm.startBroadcast(keeperPvtKey);
        strategy.processCurrentRequest(extraData);
        vm.stopBroadcast();

        console.log("\n Request processed successfully");

        // Log strategy state after processing
        console.log("\n--- Strategy State AFTER Processing ---");
        _logStrategyState(strategy);
    }

    /// @notice Overrides the parent function to use Paraswap for exactOut swaps during deleveraging
    /// @return shouldUse True if Paraswap should be used
    function _shouldUseParaswap(bool /* isLeverageUp */) internal view override returns (bool) {
        return EXACT_OUT_AVAILABLE;
    }
}
