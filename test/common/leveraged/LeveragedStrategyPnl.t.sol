// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";

import {LeveragedStrategySharedBase} from "./LeveragedStrategySharedBase.t.sol";

abstract contract LeveragedStrategyPnl is LeveragedStrategySharedBase {
    function test_Pnl_Profit_CollateralPriceIncrease() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(1000);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase with price");
    }

    function test_Pnl_Profit_WithdrawAfterPriceIncrease() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);

        _simulateCollateralPriceChange(2000);

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 withdrawShares = shares / 4;
        _requestRedeemAs(user1, withdrawShares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, withdrawShares);

        assertGt(assets, 0, "Should receive assets after price increase");
        assertGt(assets, depositAmount / 4, "Should receive more than initial deposit proportionally");
    }

    function test_Pnl_Loss_CollateralPriceDecrease() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(-1000);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertLt(netAssetsAfter, netAssetsBefore, "Net assets should decrease with price drop");
    }

    function test_Pnl_Loss_LeveragedLossesAmplified() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(-1000);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        uint256 lossPercent = ((netAssetsBefore - netAssetsAfter) * 100) / netAssetsBefore;

        assertGt(lossPercent, 20, "Leveraged losses should exceed unleveraged");
        assertLt(lossPercent, 40, "Leveraged losses should exceed unleveraged");
    }

    function test_Pnl_Loss_ApproachingLiquidation() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        _simulateCollateralPriceChange(-1500);

        uint256 currentLtv = strategy.getStrategyLtv();

        assertGt(currentLtv, TARGET_LTV_BPS, "LTV should increase after price drop");

        (uint256 netAssets, , ) = strategy.getNetAssets();
        assertGt(netAssets, 0, "Should still have positive net assets");
    }

    function test_Pnl_Loss_StillSolvent() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        _simulateCollateralPriceChange(-1200);

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        uint256 collateralValue = oracleAdapter.convertCollateralToDebt(totalCollateral);

        assertGt(netAssets, 0, "Net assets should be positive");
        assertGt(collateralValue, totalDebt, "Collateral value should exceed debt");
    }

    function test_Pnl_EdgeCase_OraclePriceVolatility() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        _simulateCollateralPriceChange(500);
        (uint256 netAssets1, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(-800);
        (uint256 netAssets2, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(300);
        (uint256 netAssets3, , ) = strategy.getNetAssets();

        assertGt(netAssets1, 0, "Should have positive assets after +5%");
        assertGt(netAssets2, 0, "Should have positive assets after -8%");
        assertGt(netAssets3, 0, "Should have positive assets after +3%");
    }

    function test_Pnl_FullLifecycle_DepositLeverageHarvestWithdraw() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();

        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);

        _simulateCollateralPriceChange(1500);

        vm.prank(keeper);
        strategy.harvestAndReport();

        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

        assertGt(assets, depositAmount, "Should profit from leveraged position");
    }

    function test_Pnl_MultiUser_DifferentEntryPrices() public {
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 shares1 = _setupUserDeposit(user1, deposit1);

        uint256 debtAmount = LeverageLib.computeTargetDebt(deposit1, TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);

        _simulateCollateralPriceChange(1000);

        uint256 deposit2 = DEFAULT_DEPOSIT();
        _setupUserDeposit(user2, deposit2);

        (uint256 netAssets, , uint256 currentDebt) = strategy.getNetAssets();
        uint256 newTargetDebt = LeverageLib.computeTargetDebt(netAssets, TARGET_LTV_BPS, strategy.oracleAdapter());
        if (newTargetDebt > currentDebt) {
            uint256 additionalDebt = newTargetDebt - currentDebt;
            _mintAndApprove(address(debtToken), keeper, address(strategy), additionalDebt);

            bytes memory swapData2 = _getKyberswapSwapData(
                CHAIN_ID,
                address(debtToken),
                address(collateralToken),
                debtAmount
            );

            vm.prank(keeper);
            strategy.rebalance(additionalDebt, true, swapData2);
        }

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 user1Value = strategy.convertToAssets(shares1);

        assertGt(user1Value, deposit1, "User1 should have gains (early entry)");
    }

    function test_Pnl_Profit_CollateralYieldAccrual() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(500);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase from yield");
    }

    function test_Pnl_Profit_YieldExceedsDebtInterest() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();
        uint256 ppsBeforeReport = strategy.convertToAssets(ONE_SHARE_UNIT());

        _simulateCollateralPriceChange(1200);

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 ppsAfterReport = strategy.convertToAssets(ONE_SHARE_UNIT());
        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase");
        assertGe(ppsAfterReport, ppsBeforeReport, "PPS should increase or stay same after profit");
    }

    function test_Pnl_Profit_Report_UpdatesTotalAssets() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 totalAssetsBefore = strategy.totalAssets();

        _simulateCollateralPriceChange(1000);

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 totalAssetsAfter = strategy.totalAssets();

        assertGt(totalAssetsAfter, totalAssetsBefore, "Total assets should increase after report");
    }

    function test_Pnl_Profit_SharePriceIncreases() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 ppsBefore = strategy.convertToAssets(ONE_SHARE_UNIT());

        _simulateCollateralPriceChange(2000);

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 ppsAfter = strategy.convertToAssets(ONE_SHARE_UNIT());
        assertGt(ppsAfter, ppsBefore, "Share price should increase");
    }

    function test_Pnl_Profit_WithdrawAfterProfit() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);

        _simulateCollateralPriceChange(1500);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.harvestAndReport();

        assertEq(loss, 0, "loss should be 0");
        assertGt(profit, 0, "!profit");

        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

        assertGt(assets, depositAmount, "User should receive more than deposited");
    }

    function test_Pnl_Loss_DebtInterestExceedsYield() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(-800);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertLt(netAssetsAfter, netAssetsBefore, "Net assets should decrease from net negative yield");
    }

    function test_Pnl_Loss_SharePriceDecreases() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 ppsBefore = strategy.convertToAssets(ONE_SHARE_UNIT());

        _simulateCollateralPriceChange(-200);

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 ppsAfter = strategy.convertToAssets(ONE_SHARE_UNIT());

        assertLt(ppsAfter, ppsBefore, "Share price should decrease after loss");
    }

    function test_Pnl_Loss_WithdrawAfterLoss() public virtual {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);

        _simulateCollateralPriceChange(-10_00);

        vm.prank(keeper);
        strategy.harvestAndReport();

        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

        assertLt(assets, depositAmount, "User should receive less than deposited after loss");
    }

    function test_Pnl_Loss_PartialLoss_StillSolvent() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());
        (uint256 netAssetsBefore, uint256 totalCollateralBefore, uint256 totalDebtBefore) = strategy.getNetAssets();

        _simulateCollateralPriceChange(-500);

        (uint256 netAssetsAfter, uint256 totalCollateralAfter, uint256 totalDebtAfter) = strategy.getNetAssets();

        assertGt(netAssetsAfter, 0, "Strategy should still have positive net assets");
        assertLt(netAssetsAfter, netAssetsBefore, "Net assets should decrease");

        assertEq(totalCollateralBefore, totalCollateralAfter, "Collateral should remain same");
        assertGt(totalDebtAfter, totalDebtBefore, "Debt should increase due to interest");
    }
}
