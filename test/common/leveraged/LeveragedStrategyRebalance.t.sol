// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";

import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";

import {LeveragedStrategySharedBase} from "./LeveragedStrategySharedBase.t.sol";

abstract contract LeveragedStrategyRebalance is LeveragedStrategySharedBase {
    function test_Rebalance_GetNetAssets_AfterDeposit() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 depositAmountInCollateral = oracleAdapter.convertAssetsToCollateral(depositAmount);

        _setupUserDeposit(user1, depositAmount);

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        assertEq(totalDebt, 0, "Debt should be zero before leverage");
        _assertApproxEqBps(netAssets, depositAmount, 10, "Net assets should be approx equal to deposit");
        _assertApproxEqBps(totalCollateral, depositAmountInCollateral, 10, "Collateral should equal deposit");
    }

    function test_Rebalance_GetNetAssets_AfterLeverage() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 depositAmountInCollateral = oracleAdapter.convertAssetsToCollateral(depositAmount);

        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            block.chainid,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        assertGt(totalCollateral, depositAmountInCollateral, "Collateral should increase from leverage");
        _assertApproxEqBps(netAssets, depositAmount, 10, "Net assets should be ~deposit");
        _assertApproxEqBps(totalDebt, debtAmount, 10, "Debt should be non-zero after leverage");
    }

    function test_Rebalance_LeverageUp() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        uint256 collateralBefore = strategy.getCollateralAmount();

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, swapData);

        uint256 collateralAfter = strategy.getCollateralAmount();
        uint256 debt = strategy.getDebtAmount();

        assertGt(collateralAfter, collateralBefore, "Collateral should increase");
        assertGt(debt, 0, "Should have debt");
    }

    function test_Rebalance_LeverageDown() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (, , uint256 debtBefore) = strategy.getNetAssets();
        uint256 deleverageAmount = debtBefore / 2;

        _mintAndApprove(address(debtToken), keeper, address(strategy), deleverageAmount);

        bytes memory swapData = _getParaswapSwapData(
            block.chainid,
            address(debtToken),
            address(collateralToken),
            deleverageAmount,
            "exactOut"
        );

        vm.prank(keeper);
        strategy.rebalance(deleverageAmount, false, swapData);

        (, , uint256 debtAfter) = strategy.getNetAssets();

        assertLt(debtAfter, debtBefore, "Debt should decrease");
    }

    function test_Rebalance_LeverageUp_AchievesTargetLtv() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

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

        uint256 actualLtv = strategy.getStrategyLtv();
        _assertApproxEqBps(actualLtv, TARGET_LTV_BPS, 10, "LTV should be near target");
    }

    function test_Rebalance_ZeroDebt_NoOp() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        _mintAndApprove(address(debtToken), keeper, address(strategy), 1000 * 1e6);

        bytes memory swapData = _getParaswapSwapData(
            CHAIN_ID,
            address(collateralToken),
            address(debtToken),
            1000 * 1e6,
            "exactOut"
        );

        uint256 keeperBalance = debtToken.balanceOf(keeper);

        vm.prank(keeper);
        strategy.rebalance(1000 * 1e6, false, swapData);

        (, , uint256 totalDebt) = strategy.getNetAssets();
        assertEq(totalDebt, 0, "Debt should still be zero");
        assertEq(keeperBalance, debtToken.balanceOf(keeper), "keeper balance should be the same");
    }

    function test_Rebalance_EmitsEvent() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = 1000 * 1e6;
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true);
        emit Rebalance(keeper, debtAmount, true);
        strategy.rebalance(debtAmount, true, swapData);
    }

    function test_Rebalance_UsingFlashLoan_LeverageUp() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, TARGET_LTV_BPS, strategy.oracleAdapter());

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        strategy.rebalanceUsingFlashLoan(debtAmount, true, swapData);

        assertGt(strategy.getDebtAmount(), 0, "Should have debt after flash loan leverage");
    }

    function test_Rebalance_UsingFlashLoan_LeverageDown() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssets, uint256 totalCollateral, uint256 debt) = strategy.getNetAssets();
        uint256 deleverageAmount = debt / 2;

        console.log("netAssets before", netAssets);
        console.log("totalCollateral before", totalCollateral);
        console.log("debt before", debt);
        console.log("deleverageAmount", deleverageAmount);

        bytes memory swapData;
        (bool isExactOutSwapEnabled, , , , ) = strategy.getLeveragedStrategyConfig();
        if (isExactOutSwapEnabled) {
            swapData = _getParaswapSwapData(
                CHAIN_ID,
                address(collateralToken),
                address(debtToken),
                deleverageAmount,
                "exactOut"
            );
        } else {
            swapData = _getKyberswapSwapData(CHAIN_ID, address(collateralToken), address(debtToken), deleverageAmount);
        }

        vm.prank(keeper);
        strategy.rebalanceUsingFlashLoan(deleverageAmount, false, swapData);

        uint256 debtAfter;
        (netAssets, totalCollateral, debtAfter) = strategy.getNetAssets();
        console.log("netAssets after", netAssets);
        console.log("totalCollateral after", totalCollateral);
        console.log("debt after", debtAfter);
        assertLt(debtAfter, debt, "Debt should decrease");
    }

    function test_Rebalance_UsingFlashLoan_EmitsEvent() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 flashLoanAmount = 2000 * 1e6;

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            flashLoanAmount
        );

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true);
        emit RebalanceUsingFlashLoan(keeper, flashLoanAmount, true);
        strategy.rebalanceUsingFlashLoan(flashLoanAmount, true, swapData);
    }

    function test_Rebalance_GetLeverage_AfterLeverageUp() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 leverage = _getCurrentLeverage();

        assertGt(leverage, 33000, "Leverage should be greater than 3.3x");
        assertLt(leverage, 34000, "Leverage should be less than 3.4x");
    }

    function test_Rebalance_GetStrategyLtv_AfterLeverageUp() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 ltv = strategy.getStrategyLtv();

        assertApproxEqRel(ltv, TARGET_LTV_BPS, 10e16, "LTV should be near target");
    }

    function test_Rebalance_EdgeCase_FreeFunds_RequiresDeleverage() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 shares = strategy.balanceOf(user1);
        uint256 withdrawShares = shares / 2;

        _requestRedeemAs(user1, withdrawShares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, withdrawShares);

        assertGt(assets, 0, "Should receive assets");

        (, , uint256 debtAfter) = strategy.getNetAssets();
        assertLt(
            debtAfter,
            (DEFAULT_DEPOSIT() * TARGET_LTV_BPS) / BPS_PRECISION,
            "Debt should be reduced after withdrawal"
        );
    }

    function test_Rebalance_EdgeCase_FullWithdrawAfterLeverage() public {
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

        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

        assertGt(assets, 0, "Should receive assets on full withdrawal");

        (uint256 netAssets, , ) = strategy.getNetAssets();
        assertLt(netAssets, depositAmount / 100, "Net assets should be near zero after full withdrawal");
    }

    function test_Rebalance_MaintainTargetLtv() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 initialLtv = strategy.getStrategyLtv();

        _simulateCollateralPriceChange(-1000);

        uint256 ltvAfterDrop = strategy.getStrategyLtv();
        assertGt(ltvAfterDrop, initialLtv, "LTV should increase after price drop");

        (uint256 netAssets, , uint256 currentDebt) = strategy.getNetAssets();
        uint256 targetDebt = LeverageLib.computeTargetDebt(netAssets, TARGET_LTV_BPS, strategy.oracleAdapter());

        uint256 deleverageAmount = currentDebt - targetDebt;

        bytes memory swapData = _getParaswapSwapData(
            CHAIN_ID,
            address(collateralToken),
            address(debtToken),
            deleverageAmount,
            "exactOut"
        );

        vm.prank(keeper);
        strategy.rebalanceUsingFlashLoan(deleverageAmount, false, swapData);

        uint256 ltvAfterRebalance = strategy.getStrategyLtv();
        assertApproxEqRel(ltvAfterRebalance, TARGET_LTV_BPS, 10e16, "LTV should be near target after rebalance");
    }

    function test_Rebalance_MultipleIterations() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount1 = LeverageLib.computeTargetDebt(depositAmount, 5000, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount1);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount1
        );

        vm.prank(keeper);
        strategy.rebalance(debtAmount1, true, swapData);

        (uint256 netAssets1, , ) = strategy.getNetAssets();

        uint256 additionalDebt = LeverageLib.computeTargetDebt(netAssets1, TARGET_LTV_BPS, strategy.oracleAdapter());
        (, , uint256 currentDebt) = strategy.getNetAssets();
        uint256 debtAmount2 = additionalDebt > currentDebt ? additionalDebt - currentDebt : 0;

        if (debtAmount2 > 0) {
            _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount2);

            bytes memory swapData2 = _getKyberswapSwapData(
                CHAIN_ID,
                address(debtToken),
                address(collateralToken),
                debtAmount2
            );

            vm.prank(keeper);
            strategy.rebalance(debtAmount2, true, swapData2);
        }

        uint256 finalLtv = strategy.getStrategyLtv();
        assertGt(finalLtv, 5000, "LTV should increase after second rebalance");
        assertApproxEqRel(finalLtv, TARGET_LTV_BPS, 1e15, "LTV should be near target");
    }
}
