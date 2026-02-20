// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";

import {LeveragedStrategySharedBase} from "./LeveragedStrategySharedBase.t.sol";

abstract contract LeveragedStrategyFuzz is LeveragedStrategySharedBase {
    function testFuzz_Deposit(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e16, DEPOSIT_LIMIT);

        _mintAndApprove(address(assetToken), user1, address(strategy), depositAmount);

        vm.prank(user1);
        uint256 shares = strategy.deposit(depositAmount, user1);

        assertGt(shares, 0, "Should receive shares");
    }

    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawPercent) public {
        depositAmount = bound(depositAmount, 1000 * 1e18, 100_000 * 1e18);
        withdrawPercent = bound(withdrawPercent, 10, 100);

        uint256 shares = _setupUserDeposit(user1, depositAmount);
        uint256 sharesToRedeem = (shares * withdrawPercent) / 100;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, sharesToRedeem);

        assertGt(assets, 0, "Should receive assets");
        assertApproxEqRel(assets, (depositAmount * withdrawPercent) / 100, 1e16, "Should receive proportional assets");
    }

    function testFuzz_Leverage(uint256 depositAmount, uint16 ltvBps) public {
        depositAmount = bound(depositAmount, SMALL_DEPOSIT() / 10, LARGE_DEPOSIT() * 10);
        ltvBps = uint16(bound(ltvBps, 1000, 8000));

        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, ltvBps, strategy.oracleAdapter());
        if (debtAmount > 0) {
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
            assertApproxEqRel(actualLtv, ltvBps, 10e16, "LTV should be near target");
        }
    }

    function testFuzz_PriceChange(int256 priceChangePercentBps) public {
        priceChangePercentBps = bound(priceChangePercentBps, -25_00, 50_00);

        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(priceChangePercentBps);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        if (priceChangePercentBps > 0) {
            assertGt(netAssetsAfter, netAssetsBefore, "Should gain on price increase");
        } else if (priceChangePercentBps < 0) {
            assertLt(netAssetsAfter, netAssetsBefore, "Should lose on price decrease");
        }

        assertGt(netAssetsAfter, 0, "Should remain solvent");
    }

    function test_Operation(uint256 _amount) public {
        vm.assume(_amount > 10_000 && _amount < DEPOSIT_LIMIT);

        _setupUserDeposit(user1, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        skip(1 days);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.harvestAndReport();

        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 balanceBefore = assetToken.balanceOf(user1);

        _requestRedeemAs(user1, _amount);
        _processCurrentRequest("");
        _redeemAs(user1, _amount);

        assertGe(assetToken.balanceOf(user1), balanceBefore + _amount, "!final balance");
    }

    function test_ProfitableReport(uint256 _amount, uint16 _profitFactor) public {
        vm.assume(_amount > 10_000 && _amount < DEPOSIT_LIMIT);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, BPS_PRECISION));

        _setupUserDeposit(user1, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        skip(1 days);

        uint256 toAirdrop = (_amount * _profitFactor) / BPS_PRECISION;
        _mintTokens(address(assetToken), address(strategy), toAirdrop);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.harvestAndReport();

        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 balanceBefore = assetToken.balanceOf(user1);

        _requestRedeemAs(user1, _amount);
        _processCurrentRequest("");
        _redeemAs(user1, _amount);

        assertGe(assetToken.balanceOf(user1), balanceBefore + _amount, "!final balance");
    }

    function test_ProfitableReport_WithFees(uint256 _amount, uint16 _profitFactor) public {
        vm.assume(_amount > 10_000 && _amount < DEPOSIT_LIMIT);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, BPS_PRECISION));

        vm.prank(management);
        (uint16 maxSlippageBps, , uint16 maxLossBps, , , ) = strategy.getBaseStrategyConfig();
        strategy.updateConfig(maxSlippageBps, 1_000, maxLossBps);

        _setupUserDeposit(user1, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        skip(1 days);

        uint256 toAirdrop = (_amount * _profitFactor) / BPS_PRECISION;

        _mintTokens(address(assetToken), address(strategy), toAirdrop);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.harvestAndReport();

        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 expectedShares = (profit * 1_000) / BPS_PRECISION;

        assertEq(strategy.balanceOf(feeReceiver), expectedShares);

        uint256 balanceBefore = assetToken.balanceOf(user1);

        _requestRedeemAs(user1, _amount);
        _processCurrentRequest("");
        _redeemAs(user1, _amount);

        assertGe(assetToken.balanceOf(user1), balanceBefore + _amount, "!final balance");

        _requestRedeemAs(feeReceiver, expectedShares);
        _processCurrentRequest("");
        _redeemAs(feeReceiver, expectedShares);

        assertEq(strategy.totalAssets(), 0, "!strategy total assets");
        assertEq(strategy.totalSupply(), 0, "!strategy total supply");

        assertGe(assetToken.balanceOf(feeReceiver), expectedShares, "!perf fee out");
    }
}
