// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/src/Test.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {LibError} from "ceres-strategies/src/libraries/LibError.sol";
import {ILeveragedStrategy} from "ceres-strategies/src/interfaces/strategies/ILeveragedStrategy.sol";

import {LeveragedStrategyBaseSetup} from "./LeveragedStrategyBaseSetup.sol";

/// @title LeveragedStrategyTest
/// @notice Abstract test contract containing all common invariant tests for LeveragedStrategy implementations
/// @dev Protocol-specific test contracts should inherit from this AND their protocol's TestSetup
abstract contract LeveragedStrategyTest is LeveragedStrategyBaseSetup {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  SETUP VERIFICATION TESTS                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_SetupStrategy_IsValid() public view {
        assertTrue(address(0) != address(strategy), "Strategy should be deployed");
        assertEq(strategy.asset(), address(assetToken), "Asset should match");
        assertEq(strategy.management(), management, "Management should match");
        assertEq(strategy.performanceFeeRecipient(), feeReceiver, "Fee receiver should match");
        assertEq(strategy.keeper(), keeper, "Keeper should match");
    }

    function test_InitialValues_LeveragedStrategy() public view {
        assertEq(address(strategy.COLLATERAL_TOKEN()), address(assetToken), "COLLATERAL_TOKEN mismatch");
        assertEq(address(strategy.DEBT_TOKEN()), address(debtToken), "DEBT_TOKEN mismatch");
        assertTrue(strategy.IS_ASSET_COLLATERAL(), "IS_ASSET_COLLATERAL should be true");
        assertEq(strategy.BPS_PRECISION(), 100_00, "BPS_PRECISION mismatch");

        assertEq(address(strategy.oracleAdapter()), address(oracleAdapter), "oracleAdapter mismatch");
        assertEq(address(strategy.swapper()), address(swapper), "swapper mismatch");

        ILeveragedStrategy.StrategyConfig memory config = strategy.config();
        assertEq(config.targetLtvBps, TARGET_LTV_BPS, "targetLtvBps mismatch");
        assertEq(config.maxSlippageBps, MAX_SLIPPAGE_BPS, "maxSlippageBps mismatch");
        assertEq(config.depositLimit, DEPOSIT_LIMIT, "depositLimit mismatch");
        assertEq(config.withdrawLimit, WITHDRAW_LIMIT, "withdrawLimit mismatch");
    }

    function test_InitialValues_BaseStrategy() public view {
        assertEq(address(strategy.asset()), address(assetToken), "asset mismatch");
        assertEq(strategy.tokenizedStrategyAddress(), TOKENIZED_STRATEGY_IMPL, "tokenizedStrategyAddress mismatch");

        assertTrue(management != address(0), "management should not be zero");
        assertEq(strategy.management(), management, "management address mismatch");

        assertTrue(keeper != address(0), "keeper should not be zero");
        assertEq(strategy.keeper(), keeper, "keeper address mismatch");

        assertEq(strategy.pendingManagement(), address(0), "pendingManagement should be zero");
        assertEq(strategy.emergencyAdmin(), management, "emergencyAdmin mismatch");
        assertEq(strategy.performanceFeeRecipient(), feeReceiver, "performanceFeeRecipient mismatch");
        assertEq(strategy.performanceFee(), 1000, "performanceFee should be 1000 (10%)");
        assertFalse(strategy.isShutdown(), "strategy should not be shutdown");

        assertEq(strategy.totalSupply(), 0, "totalSupply should be 0");
        assertEq(strategy.totalAssets(), 0, "totalAssets should be 0");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    DEPOSIT TESTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Deposit_Basic() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();

        _mintAndApprove(address(assetToken), user1, address(strategy), depositAmount);

        vm.prank(user1);
        uint256 shares = strategy.deposit(depositAmount, user1);

        assertEq(shares, depositAmount, "Shares should equal deposit for first deposit");
        assertEq(strategy.balanceOf(user1), shares, "User balance should match shares");

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();
        assertEq(netAssets, depositAmount, "Net assets should match deposit");
        assertEq(totalCollateral, depositAmount, "Collateral should match deposit");
        assertEq(totalDebt, 0, "Debt should be 0");
    }

    function test_Deposit_Basic_MultipleUsers() public {
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 deposit2 = DEFAULT_DEPOSIT() * 2;

        uint256 shares1 = _setupUserDeposit(user1, deposit1);
        uint256 shares2 = _setupUserDeposit(user2, deposit2);

        assertEq(strategy.balanceOf(user1), shares1, "User1 shares mismatch");
        assertEq(strategy.balanceOf(user2), shares2, "User2 shares mismatch");
        assertEq(strategy.totalAssets(), deposit1 + deposit2, "Total assets mismatch");
    }

    function test_Deposit_AssetsDeployedAsCollateral() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 collateral = strategy.getCollateralAmount();
        assertEq(collateral, depositAmount, "Collateral should be deposited to protocol");
    }

    function testFuzz_Deposit(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e16, DEPOSIT_LIMIT);

        _mintAndApprove(address(assetToken), user1, address(strategy), depositAmount);

        vm.prank(user1);
        uint256 shares = strategy.deposit(depositAmount, user1);

        assertGt(shares, 0, "Should receive shares");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    WITHDRAW TESTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Withdraw_Basic() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 withdrawAmount = depositAmount / 2;

        vm.prank(user1);
        strategy.withdraw(withdrawAmount, user1, user1);

        assertEq(assetToken.balanceOf(user1), withdrawAmount, "User should receive withdrawn amount");
    }

    function test_Withdraw_Partial() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 withdrawShares = shares / 4; // 25%

        vm.prank(user1);
        uint256 assets = strategy.redeem(withdrawShares, user1, user1);

        assertApproxEqRel(assets, depositAmount / 4, 1e15, "Should receive ~25% of assets");
        assertEq(strategy.balanceOf(user1), shares - withdrawShares, "Remaining shares mismatch");
    }

    function test_Withdraw_AllShares() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        vm.prank(user1);
        uint256 assets = strategy.redeem(shares, user1, user1);

        assertApproxEqRel(assets, depositAmount, 1e15, "Should receive all deposited assets");
        assertEq(strategy.balanceOf(user1), 0, "Should have no remaining shares");
    }

    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawPercent) public {
        depositAmount = bound(depositAmount, 1000 * 1e18, 100_000 * 1e18);
        withdrawPercent = bound(withdrawPercent, 10, 100);

        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 withdrawShares = (shares * withdrawPercent) / 100;

        vm.prank(user1);
        uint256 assets = strategy.redeem(withdrawShares, user1, user1);

        assertGt(assets, 0, "Should receive assets");
        assertApproxEqRel(assets, (depositAmount * withdrawPercent) / 100, 1e16, "Should receive proportional assets");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  NET ASSETS TESTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_GetNetAssets_AfterDeposit() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        assertEq(netAssets, depositAmount, "Net assets should equal deposit");
        assertEq(totalCollateral, depositAmount, "Collateral should equal deposit");
        assertEq(totalDebt, 0, "Debt should be zero before leverage");
    }

    function test_GetNetAssets_AfterLeverage() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);

        console.log("debtAmount", debtAmount);

        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory res = _getParaswapSwapData(
            block.chainid,
            address(debtToken),
            address(collateralToken),
            debtAmount,
            "exactIn"
        );

        console.log("Swap Data");
        console.logBytes(res);
        revert("test swap");

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        assertApproxEqRel(netAssets, depositAmount, 1e15, "Net assets should be ~deposit");
        assertGt(totalCollateral, depositAmount, "Collateral should increase from leverage");
        assertApproxEqRel(totalDebt, debtAmount, 1e15, "Debt should be non-zero after leverage");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  REBALANCE TESTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Rebalance_LeverageUp() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        uint256 collateralBefore = strategy.getCollateralAmount();

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

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

        vm.prank(keeper);
        strategy.rebalance(deleverageAmount, false, "");

        (, , uint256 debtAfter) = strategy.getNetAssets();

        assertLt(debtAfter, debtBefore, "Debt should decrease");
    }

    function test_Rebalance_LeverageUp_AchievesTargetLtv() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

        uint256 actualLtv = strategy.getStrategyLtv();
        // Allow 0.1% tolerance
        _assertApproxEqBps(actualLtv, TARGET_LTV_BPS, 10, "LTV should be near target");
    }

    function test_Rebalance_ZeroDebt_NoOp() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        // Try to leverage down when there's no debt
        _mintAndApprove(address(debtToken), keeper, address(strategy), 1000 * 1e6);

        uint256 keeperBalance = debtToken.balanceOf(keeper);

        vm.prank(keeper);
        strategy.rebalance(1000 * 1e6, false, "");

        // Should not revert and debt should still be zero
        (, , uint256 totalDebt) = strategy.getNetAssets();
        assertEq(totalDebt, 0, "Debt should still be zero");
        assertEq(keeperBalance, debtToken.balanceOf(keeper), "keeper balance should be the same");
    }

    function test_Rebalance_EmitsEvent() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = 1000 * 1e6;
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true);
        emit Rebalance(keeper, debtAmount, true);
        strategy.rebalance(debtAmount, true, "");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                            FLASH LOAN REBALANCE TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_RebalanceUsingFlashLoan_LeverageUp() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);

        vm.prank(keeper);
        strategy.rebalanceUsingFlashLoan(debtAmount, true, "");

        assertGt(strategy.getDebtAmount(), 0, "Should have debt after flash loan leverage");
    }

    function test_RebalanceUsingFlashLoan_LeverageDown() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (, , uint256 debtBefore) = strategy.getNetAssets();
        uint256 deleverageAmount = debtBefore / 2;

        vm.prank(keeper);
        strategy.rebalanceUsingFlashLoan(deleverageAmount, false, "");

        (, , uint256 debtAfter) = strategy.getNetAssets();
        assertLt(debtAfter, debtBefore, "Debt should decrease");
    }

    function test_RebalanceUsingFlashLoan_EmitsEvent() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 flashLoanAmount = 2000 * 1e6;

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true);
        emit RebalanceUsingFlashLoan(keeper, flashLoanAmount, true);
        strategy.rebalanceUsingFlashLoan(flashLoanAmount, true, "");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  LEVERAGE RATIO TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_GetLeverage_AfterLeverageUp() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 leverage = strategy.getLeverage();

        // At 70% LTV, leverage should be approximately 3.33x (33333 BPS)
        assertGt(leverage, 33000, "Leverage should be greater than 3.3x");
        assertLt(leverage, 34000, "Leverage should be less than 3.4x");
    }

    function test_GetStrategyLtv_AfterLeverageUp() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 ltv = strategy.getStrategyLtv();

        // LTV should be near target
        assertApproxEqRel(ltv, TARGET_LTV_BPS, 10e16, "LTV should be near target");
    }

    function testFuzz_Leverage(uint256 depositAmount, uint16 ltvBps) public {
        depositAmount = bound(depositAmount, SMALL_DEPOSIT() / 10, LARGE_DEPOSIT() * 10);
        ltvBps = uint16(bound(ltvBps, 1000, 8000)); // 10% to 80%

        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, ltvBps);
        if (debtAmount > 0) {
            _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

            vm.prank(keeper);
            strategy.rebalance(debtAmount, true, "");

            uint256 actualLtv = strategy.getStrategyLtv();
            assertApproxEqRel(actualLtv, ltvBps, 10e16, "LTV should be near target");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              PROFIT SCENARIO TESTS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Profit_CollateralPriceIncrease() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate 10% price increase
        _simulatePriceChange(10);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase with price");
    }

    function test_Profit_WithdrawAfterPriceIncrease() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Setup leverage
        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);
        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

        // Price increases 20%
        _simulatePriceChange(20);

        vm.prank(keeper);
        strategy.report();
        skip(strategy.profitMaxUnlockTime());

        uint256 withdrawShares = shares / 4;
        vm.prank(user1);
        uint256 assets = strategy.redeem(withdrawShares, user1, user1);

        assertGt(assets, 0, "Should receive assets after price increase");
        assertGt(assets, depositAmount / 4, "Should receive more than initial deposit proportionally");
    }

    function testFuzz_PriceChange(int256 priceChangePercent) public {
        priceChangePercent = bound(priceChangePercent, -25, 50);

        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        _simulatePriceChange(priceChangePercent);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        if (priceChangePercent > 0) {
            assertGt(netAssetsAfter, netAssetsBefore, "Should gain on price increase");
        } else if (priceChangePercent < 0) {
            assertLt(netAssetsAfter, netAssetsBefore, "Should lose on price decrease");
        }

        // Should still be solvent for reasonable price changes
        assertGt(netAssetsAfter, 0, "Should remain solvent");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                               LOSS SCENARIO TESTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Loss_CollateralPriceDecrease() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate 10% price decrease
        _simulatePriceChange(-10);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertLt(netAssetsAfter, netAssetsBefore, "Net assets should decrease with price drop");
    }

    function test_Loss_LeveragedLossesAmplified() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate 10% price decrease
        _simulatePriceChange(-10);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        uint256 lossPercent = ((netAssetsBefore - netAssetsAfter) * 100) / netAssetsBefore;

        // With 70% LTV (~3.33x leverage), 10% price drop should cause ~33% loss
        assertGt(lossPercent, 20, "Leveraged losses should exceed unleveraged");
        assertLt(lossPercent, 40, "Leveraged losses should exceed unleveraged");
    }

    function test_Loss_ApproachingLiquidation() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        // Simulate significant price drop (15%)
        _simulatePriceChange(-15);

        uint256 currentLtv = strategy.getStrategyLtv();

        // LTV should increase significantly due to price drop
        assertGt(currentLtv, TARGET_LTV_BPS, "LTV should increase after price drop");

        // Strategy should still have positive net assets (not liquidated)
        (uint256 netAssets, , ) = strategy.getNetAssets();
        assertGt(netAssets, 0, "Should still have positive net assets");
    }

    function test_Loss_StillSolvent() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        // Simulate 12% price drop
        _simulatePriceChange(-12);

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        uint256 collateralValue = oracleAdapter.convertCollateralToDebt(totalCollateral);

        assertGt(netAssets, 0, "Net assets should be positive");
        assertGt(collateralValue, totalDebt, "Collateral value should exceed debt");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  EDGE CASE TESTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_EdgeCase_OraclePriceVolatility() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        // Rapid price changes
        _simulatePriceChange(5);
        (uint256 netAssets1, , ) = strategy.getNetAssets();

        _simulatePriceChange(-8);
        (uint256 netAssets2, , ) = strategy.getNetAssets();

        _simulatePriceChange(3);
        (uint256 netAssets3, , ) = strategy.getNetAssets();

        // Strategy should handle volatility without reverting
        assertGt(netAssets1, 0, "Should have positive assets after +5%");
        assertGt(netAssets2, 0, "Should have positive assets after -8%");
        assertGt(netAssets3, 0, "Should have positive assets after +3%");
    }

    function test_EdgeCase_FreeFunds_RequiresDeleverage() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 shares = strategy.balanceOf(user1);
        uint256 withdrawShares = shares / 2;

        // Withdrawing should trigger deleveraging
        vm.prank(user1);
        uint256 assets = strategy.redeem(withdrawShares, user1, user1);

        assertGt(assets, 0, "Should receive assets");

        // Debt should be reduced
        (, , uint256 debtAfter) = strategy.getNetAssets();
        assertLt(
            debtAfter,
            (DEFAULT_DEPOSIT() * TARGET_LTV_BPS) / BPS_PRECISION,
            "Debt should be reduced after withdrawal"
        );
    }

    function test_EdgeCase_FullWithdrawAfterLeverage() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Setup leverage
        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);
        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

        // Full withdrawal
        vm.prank(user1);
        uint256 assets = strategy.redeem(shares, user1, user1);

        assertGt(assets, 0, "Should receive assets on full withdrawal");

        // Strategy should be mostly empty
        (uint256 netAssets, , ) = strategy.getNetAssets();
        assertLt(netAssets, depositAmount / 100, "Net assets should be near zero after full withdrawal");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              ACCESS CONTROL TESTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function testRevert_Rebalance_NotKeeper() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint256 debtAmount = strategy.computeTargetDebt(DEFAULT_DEPOSIT(), TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), user1, address(strategy), debtAmount);

        vm.prank(user1);
        vm.expectRevert();
        strategy.rebalance(debtAmount, true, "");
    }

    function testRevert_RebalanceUsingFlashLoan_NotKeeper() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        vm.prank(user1);
        vm.expectRevert();
        strategy.rebalanceUsingFlashLoan(1e6, true, "");
    }

    function testRevert_Slippage_Exceeded() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        // Set low slippage tolerance
        vm.prank(management);
        strategy.setMaxSlippage(10); // 0.1%

        uint256 debtAmount = strategy.computeTargetDebt(DEFAULT_DEPOSIT(), TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        vm.prank(keeper);
        vm.expectRevert();
        strategy.rebalance(debtAmount, true, "");
    }

    function testRevert_SwapAndDepositCollateral_AssetIsCollateral() public {
        // In our setup, asset == collateral, so this should revert
        vm.prank(keeper);
        vm.expectRevert(LibError.InvalidAction.selector);
        strategy.swapAndDepositCollateral(1000 * 1e18, "");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              ADMIN FUNCTION TESTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_SetTargetLtv_Success() public {
        uint16 newLtv = 6000; // 60%

        vm.prank(management);
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.TargetLtvUpdated(TARGET_LTV_BPS, newLtv);
        strategy.setTargetLtv(newLtv);

        ILeveragedStrategy.StrategyConfig memory config = strategy.config();
        assertEq(config.targetLtvBps, newLtv, "Target LTV should be updated");
    }

    function test_SetMaxSlippage_Success() public {
        uint16 newSlippage = 100; // 1%

        vm.prank(management);
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.MaxSlippageUpdated(MAX_SLIPPAGE_BPS, newSlippage);
        strategy.setMaxSlippage(newSlippage);

        ILeveragedStrategy.StrategyConfig memory config = strategy.config();
        assertEq(config.maxSlippageBps, newSlippage, "Max slippage should be updated");
    }

    function test_SetDepositAndWithdrawLimit_Success() public {
        uint96 newDepositLimit = 5_000_000 * 1e18;
        uint96 newWithdrawLimit = 1_000_000 * 1e18;

        vm.startPrank(management);
        strategy.setDepositLimit(newDepositLimit);
        strategy.setWithdrawLimit(newWithdrawLimit);
        vm.stopPrank();

        ILeveragedStrategy.StrategyConfig memory config = strategy.config();
        assertEq(config.depositLimit, newDepositLimit, "Deposit limit should be updated");
        assertEq(config.withdrawLimit, newWithdrawLimit, "Withdraw limit should be updated");
    }

    function test_SetStrategyConfig_Success() public {
        ILeveragedStrategy.StrategyConfig memory newConfig = ILeveragedStrategy.StrategyConfig({
            targetLtvBps: 6500,
            maxSlippageBps: 75,
            reserved: 0,
            depositLimit: 2_000_000 * 1e18,
            withdrawLimit: 500_000 * 1e18
        });

        vm.prank(management);
        strategy.setStrategyConfig(newConfig);

        ILeveragedStrategy.StrategyConfig memory config = strategy.config();
        assertEq(config.targetLtvBps, newConfig.targetLtvBps, "Config targetLtvBps mismatch");
        assertEq(config.maxSlippageBps, newConfig.maxSlippageBps, "Config maxSlippageBps mismatch");
        assertEq(config.depositLimit, newConfig.depositLimit, "Config depositLimit mismatch");
        assertEq(config.withdrawLimit, newConfig.withdrawLimit, "Config withdrawLimit mismatch");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          ORACLE/SWAPPER UPDATE TESTS (2-step)                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_SetOracleAdapter_TwoStepProcess() public {
        address newAdapter = address(0x123);
        address oldAdapter = address(strategy.oracleAdapter());

        // Step 1: Request oracle adapter update
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.OracleUpdateRequested(newAdapter, block.timestamp + strategy.DELAY());
        vm.prank(management);
        strategy.requestOracleAdapterUpdate(newAdapter);

        // Verify pending state
        ILeveragedStrategy.PendingConfig memory pending = strategy.pendingConfig();
        assertEq(pending.proposedOracleAdapter, newAdapter, "Proposed oracle adapter should be set");

        // Oracle adapter should not be updated yet
        assertEq(address(strategy.oracleAdapter()), oldAdapter, "Oracle adapter should not be updated yet");

        // Step 2: Wait for delay period and execute
        vm.warp(block.timestamp + strategy.DELAY());

        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.OracleAdapterSet(oldAdapter, newAdapter);
        vm.prank(management);
        strategy.executeOracleAdapterUpdate();

        assertEq(address(strategy.oracleAdapter()), newAdapter, "Oracle adapter should be updated");
    }

    function test_SetSwapper_TwoStepProcess() public {
        address newSwapper = address(0x456);
        address oldSwapper = address(strategy.swapper());

        // Step 1: Request swapper update
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.SwapperUpdateRequested(newSwapper, block.timestamp + strategy.DELAY());
        vm.prank(management);
        strategy.requestSwapperUpdate(newSwapper);

        // Swapper should not be updated yet
        assertEq(address(strategy.swapper()), oldSwapper, "Swapper should not be updated yet");

        // Step 2: Wait for delay period and execute
        vm.warp(block.timestamp + strategy.DELAY());

        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.SwapperSet(oldSwapper, newSwapper);
        vm.prank(management);
        strategy.executeSwapperUpdate();

        assertEq(address(strategy.swapper()), newSwapper, "Swapper should be updated");
    }

    function test_CancelPendingOracleAdapter_Success() public {
        address newAdapter = address(0x123);

        vm.prank(management);
        strategy.requestOracleAdapterUpdate(newAdapter);

        vm.prank(management);
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.PendingRequestCancelled(newAdapter);
        strategy.cancelPendingOracleAdapter();

        ILeveragedStrategy.PendingConfig memory pending = strategy.pendingConfig();
        assertEq(pending.proposedOracleAdapter, address(0), "Proposed oracle adapter should be cleared");
    }

    function test_CancelPendingSwapper_Success() public {
        address newSwapper = address(0x456);

        vm.prank(management);
        strategy.requestSwapperUpdate(newSwapper);

        vm.prank(management);
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.PendingRequestCancelled(newSwapper);
        strategy.cancelPendingSwapper();

        ILeveragedStrategy.PendingConfig memory pending = strategy.pendingConfig();
        assertEq(pending.proposedSwapper, address(0), "Proposed swapper should be cleared");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          ADMIN FUNCTION REVERT TESTS                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function testRevert_SetTargetLtv_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.setTargetLtv(6000);
    }

    function testRevert_SetTargetLtv_InvalidValue() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidValue.selector);
        strategy.setTargetLtv(10000); // 100%
    }

    function testRevert_SetMaxSlippage_InvalidValue() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidValue.selector);
        strategy.setMaxSlippage(10001); // > 100%
    }

    function testRevert_SetOracleAdapter_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.requestOracleAdapterUpdate(address(0x123));
    }

    function testRevert_SetSwapper_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.requestSwapperUpdate(address(0x123));
    }

    function testRevert_RequestOracleAdapterUpdate_ZeroAddress() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidAddress.selector);
        strategy.requestOracleAdapterUpdate(address(0));
    }

    function testRevert_RequestSwapperUpdate_ZeroAddress() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidAddress.selector);
        strategy.requestSwapperUpdate(address(0));
    }

    function testRevert_ExecuteOracleAdapterUpdate_BeforeDelay() public {
        vm.prank(management);
        strategy.requestOracleAdapterUpdate(address(0x123));

        vm.prank(management);
        vm.expectRevert(LibError.NotReady.selector);
        strategy.executeOracleAdapterUpdate();
    }

    function testRevert_ExecuteSwapperUpdate_BeforeDelay() public {
        vm.prank(management);
        strategy.requestSwapperUpdate(address(0x456));

        vm.prank(management);
        vm.expectRevert(LibError.NotReady.selector);
        strategy.executeSwapperUpdate();
    }

    function testRevert_RequestOracleAdapterUpdate_PendingExists() public {
        vm.prank(management);
        strategy.requestOracleAdapterUpdate(address(0x123));

        vm.prank(management);
        vm.expectRevert(LibError.PendingActionExists.selector);
        strategy.requestOracleAdapterUpdate(address(0x789));
    }

    function testRevert_RequestSwapperUpdate_PendingExists() public {
        vm.prank(management);
        strategy.requestSwapperUpdate(address(0x456));

        vm.prank(management);
        vm.expectRevert(LibError.PendingActionExists.selector);
        strategy.requestSwapperUpdate(address(0x789));
    }

    function testRevert_ExecuteOracleAdapterUpdate_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.executeOracleAdapterUpdate();
    }

    function testRevert_ExecuteSwapperUpdate_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.executeSwapperUpdate();
    }

    function testRevert_CancelPendingOracleAdapter_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.cancelPendingOracleAdapter();
    }

    function testRevert_CancelPendingSwapper_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.cancelPendingSwapper();
    }

    function testRevert_RescueTokens_StrategyTokens() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidToken.selector);
        strategy.rescueTokens(address(assetToken));

        vm.prank(management);
        vm.expectRevert(LibError.InvalidToken.selector);
        strategy.rescueTokens(address(debtToken));
    }

    function testRevert_Deposit_ExceedsLimit() public {
        uint256 excessDeposit = DEPOSIT_LIMIT + 200 * 1e18;
        _mintAndApprove(address(assetToken), user1, address(strategy), excessDeposit);

        vm.prank(user1);
        vm.expectRevert();
        strategy.deposit(excessDeposit, user1);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              RESCUE TOKENS TEST                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_RescueTokens_NonStrategyToken() public {
        IERC20 randomToken = IERC20(makeAddr("randomToken"));

        deal(address(randomToken), address(strategy), 1000 * 1e18);

        uint256 balanceBefore = randomToken.balanceOf(management);

        vm.prank(management);
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.TokensRecovered(address(randomToken), 1000 * 1e18);
        strategy.rescueTokens(address(randomToken));

        uint256 balanceAfter = randomToken.balanceOf(management);
        assertEq(balanceAfter - balanceBefore, 1000 * 1e18, "Should receive rescued tokens");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                         FUNCTION SIGNATURE COLLISION TESTS                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_FunctionCollisions() public {
        uint256 wad = 1e18;
        vm.expectRevert("initialized");
        strategy.initialize(address(assetToken), "name", management, feeReceiver, keeper);

        // Check view functions
        assertEq(strategy.convertToAssets(wad), wad, "convert to assets");
        assertEq(strategy.convertToShares(wad), wad, "convert to shares");
        assertEq(strategy.previewDeposit(wad), wad, "preview deposit");
        assertEq(strategy.previewMint(wad), wad, "preview mint");
        assertEq(strategy.previewWithdraw(wad), wad, "preview withdraw");
        assertEq(strategy.previewRedeem(wad), wad, "preview redeem");
        assertEq(strategy.totalAssets(), 0, "total assets");
        assertEq(strategy.totalSupply(), 0, "total supply");
        assertEq(strategy.unlockedShares(), 0, "unlocked shares");
        assertEq(strategy.asset(), address(assetToken), "asset");
        assertEq(strategy.apiVersion(), "3.0.4", "api");
        assertEq(strategy.MAX_FEE(), 5_000, "max fee");
        assertEq(strategy.fullProfitUnlockDate(), 0, "unlock date");
        assertEq(strategy.profitUnlockingRate(), 0, "unlock rate");
        assertGt(strategy.lastReport(), 0, "last report");
        assertEq(strategy.pricePerShare(), 10 ** IERC20Metadata(address(assetToken)).decimals(), "pps");
        assertTrue(!strategy.isShutdown());
        assertEq(
            strategy.symbol(),
            string(abi.encodePacked("ys", IERC20Metadata(address(assetToken)).symbol())),
            "symbol"
        );
        assertEq(strategy.decimals(), IERC20Metadata(address(assetToken)).decimals(), "decimals");

        // Assure modifiers are working
        vm.startPrank(user1);
        vm.expectRevert("!management");
        strategy.setPendingManagement(user1);
        vm.expectRevert("!pending");
        strategy.acceptManagement();
        vm.expectRevert("!management");
        strategy.setKeeper(user1);
        vm.expectRevert("!management");
        strategy.setEmergencyAdmin(user1);
        vm.expectRevert("!management");
        strategy.setPerformanceFee(uint16(2_000));
        vm.expectRevert("!management");
        strategy.setPerformanceFeeRecipient(user1);
        vm.expectRevert("!management");
        strategy.setProfitMaxUnlockTime(1);
        vm.stopPrank();

        // Assure checks are being used
        vm.startPrank(strategy.management());
        vm.expectRevert("Cannot be self");
        strategy.setPerformanceFeeRecipient(address(strategy));
        vm.expectRevert("too long");
        strategy.setProfitMaxUnlockTime(type(uint256).max);
        vm.stopPrank();

        // Mint some shares to the user for transfer tests
        _setupUserDeposit(user1, wad);
        assertEq(strategy.balanceOf(address(user1)), wad, "balance");
        vm.prank(user1);
        strategy.transfer(keeper, wad);
        assertEq(strategy.balanceOf(user1), 0, "second balance");
        assertEq(strategy.balanceOf(keeper), wad, "keeper balance");
        assertEq(strategy.allowance(keeper, user1), 0, "allowance");
        vm.prank(keeper);
        assertTrue(strategy.approve(user1, wad), "approval");
        assertEq(strategy.allowance(keeper, user1), wad, "second allowance");
        vm.prank(user1);
        assertTrue(strategy.transferFrom(keeper, user1, wad), "transfer from");
        assertEq(strategy.balanceOf(user1), wad, "second balance");
        assertEq(strategy.balanceOf(keeper), 0, "keeper balance");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              OPERATION TESTS                                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Operation(uint256 _amount) public {
        vm.assume(_amount > 10_000 && _amount < DEPOSIT_LIMIT);

        // Deposit into strategy
        _setupUserDeposit(user1, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = assetToken.balanceOf(user1);

        // Withdraw all funds
        vm.prank(user1);
        strategy.redeem(_amount, user1, user1);

        assertGe(assetToken.balanceOf(user1), balanceBefore + _amount, "!final balance");
    }

    function test_ProfitableReport(uint256 _amount, uint16 _profitFactor) public {
        vm.assume(_amount > 10_000 && _amount < DEPOSIT_LIMIT);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, BPS_PRECISION));

        // Deposit into strategy
        _setupUserDeposit(user1, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Simulate earning interest by increasing asset balance
        uint256 toAirdrop = (_amount * _profitFactor) / BPS_PRECISION;
        _mintTokens(address(assetToken), address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = assetToken.balanceOf(user1);

        // Withdraw all funds
        vm.prank(user1);
        strategy.redeem(_amount, user1, user1);

        assertGe(assetToken.balanceOf(user1), balanceBefore + _amount, "!final balance");
    }

    function test_ProfitableReport_WithFees(uint256 _amount, uint16 _profitFactor) public {
        vm.assume(_amount > 10_000 && _amount < DEPOSIT_LIMIT);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, BPS_PRECISION));

        // Set performance fee to 10%
        vm.prank(management);
        strategy.setPerformanceFee(1_000);

        // Deposit into strategy
        _setupUserDeposit(user1, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Simulate earning interest
        uint256 toAirdrop = (_amount * _profitFactor) / BPS_PRECISION;

        _mintTokens(address(assetToken), address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / BPS_PRECISION;

        assertEq(strategy.balanceOf(feeReceiver), expectedShares);

        uint256 balanceBefore = assetToken.balanceOf(user1);

        // Withdraw all funds
        vm.prank(user1);
        strategy.redeem(_amount, user1, user1);

        assertGe(assetToken.balanceOf(user1), balanceBefore + _amount, "!final balance");

        vm.prank(feeReceiver);
        strategy.redeem(expectedShares, feeReceiver, feeReceiver);

        assertEq(strategy.totalAssets(), 0, "!strategy total assets");
        assertEq(strategy.totalSupply(), 0, "!strategy total supply");

        assertGe(assetToken.balanceOf(feeReceiver), expectedShares, "!perf fee out");
    }

    function test_TendTrigger(uint256 _amount) public {
        vm.assume(_amount > 10_000 && _amount < DEPOSIT_LIMIT);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        _setupUserDeposit(user1, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                         MULTI-STEP LIFECYCLE TESTS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_FullLifecycle_DepositLeverageHarvestWithdraw() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();

        // 1. Deposit
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // 2. Leverage up
        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);
        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

        // 3. Price increases (bull market)
        _simulatePriceChange(15);

        // 4. Report profits
        vm.prank(keeper);
        strategy.report();
        skip(strategy.profitMaxUnlockTime());

        // 5. Withdraw with profit
        vm.prank(user1);
        uint256 assets = strategy.redeem(shares, user1, user1);

        assertGt(assets, depositAmount, "Should profit from leveraged position");
    }

    function test_MultiUser_DifferentEntryPrices() public {
        // User1 enters at initial price
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 shares1 = _setupUserDeposit(user1, deposit1);

        // Setup leverage
        uint256 debtAmount = strategy.computeTargetDebt(deposit1, TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);
        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

        // Price increases 10%
        _simulatePriceChange(10);

        // User2 enters at higher price
        uint256 deposit2 = DEFAULT_DEPOSIT();
        _setupUserDeposit(user2, deposit2);

        // Rebalance for new deposits
        (uint256 netAssets, , uint256 currentDebt) = strategy.getNetAssets();
        uint256 newTargetDebt = strategy.computeTargetDebt(netAssets, TARGET_LTV_BPS);
        if (newTargetDebt > currentDebt) {
            uint256 additionalDebt = newTargetDebt - currentDebt;
            _mintAndApprove(address(debtToken), keeper, address(strategy), additionalDebt);
            vm.prank(keeper);
            strategy.rebalance(additionalDebt, true, "");
        }

        vm.prank(keeper);
        strategy.report();
        skip(strategy.profitMaxUnlockTime());

        // User1 should have more value per share (entered at lower price)
        uint256 pps = strategy.pricePerShare();
        uint256 user1Value = (shares1 * pps) / 1e18;

        assertGt(user1Value, deposit1, "User1 should have gains (early entry)");
    }

    function test_Rebalance_MaintainTargetLtv() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 initialLtv = strategy.getStrategyLtv();

        // Price drops, LTV increases
        _simulatePriceChange(-10);

        uint256 ltvAfterDrop = strategy.getStrategyLtv();
        assertGt(ltvAfterDrop, initialLtv, "LTV should increase after price drop");

        // Deleverage to bring LTV back to target
        (uint256 netAssets, , uint256 currentDebt) = strategy.getNetAssets();
        uint256 targetDebt = strategy.computeTargetDebt(netAssets, TARGET_LTV_BPS);

        uint256 deleverageAmount = currentDebt - targetDebt;

        vm.prank(keeper);
        strategy.rebalanceUsingFlashLoan(deleverageAmount, false, "");

        uint256 ltvAfterRebalance = strategy.getStrategyLtv();
        assertApproxEqRel(ltvAfterRebalance, TARGET_LTV_BPS, 10e16, "LTV should be near target after rebalance");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                           INTEREST ACCRUAL PROFIT TESTS                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test profit from collateral yield accrual
    function test_Profit_CollateralYieldAccrual() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate 10% APY on collateral, 5% APY on debt over 1 year
        _simulateInterestAccrual(1000, 500, 365 days);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase from yield");
    }

    /// @notice Test net profit when yield exceeds debt interest
    function test_Profit_YieldExceedsDebtInterest() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();
        uint256 ppsBeforeReport = strategy.pricePerShare();

        // Simulate high collateral yield (15% APY) vs low debt interest (3% APY)
        _simulateInterestAccrual(1500, 300, 180 days);

        // Trigger report to realize profits
        vm.prank(keeper);
        strategy.report();

        // Wait for profit to unlock
        skip(strategy.profitMaxUnlockTime());

        uint256 ppsAfterReport = strategy.pricePerShare();
        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase");
        assertGe(ppsAfterReport, ppsBeforeReport, "PPS should increase or stay same after profit");
    }

    /// @notice Test that profit reporting updates total assets
    function test_Profit_Report_UpdatesTotalAssets() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 totalAssetsBefore = strategy.totalAssets();

        // Simulate profit
        _simulateInterestAccrual(1000, 200, 90 days);

        vm.prank(keeper);
        strategy.report();

        uint256 totalAssetsAfter = strategy.totalAssets();

        assertGt(totalAssetsAfter, totalAssetsBefore, "Total assets should increase after report");
    }

    /// @notice Test share price increases after profit
    function test_Profit_SharePriceIncreases() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 ppsBefore = strategy.pricePerShare();

        // Simulate significant profit
        _simulateInterestAccrual(2000, 300, 365 days);

        vm.prank(keeper);
        strategy.report();

        // Wait for profit to unlock
        skip(strategy.profitMaxUnlockTime());

        uint256 ppsAfter = strategy.pricePerShare();

        assertGt(ppsAfter, ppsBefore, "Share price should increase");
    }

    /// @notice Test user withdraws and receives profit share
    function test_Profit_WithdrawAfterProfit() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Setup leverage
        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);
        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

        // Simulate profit
        _simulateInterestAccrual(1500, 300, 180 days);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(loss, 0, "loss should be 0");
        assertGt(profit, 0, "!profit");

        // Wait for profit unlock
        skip(strategy.profitMaxUnlockTime());

        // Withdraw all
        vm.prank(user1);
        uint256 assets = strategy.redeem(shares, user1, user1);

        assertGt(assets, depositAmount, "User should receive more than deposited");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                           INTEREST ACCRUAL LOSS TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test loss when debt interest exceeds yield
    function test_Loss_DebtInterestExceedsYield() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate low collateral yield (2% APY) vs high debt interest (10% APY)
        _simulateInterestAccrual(200, 1000, 365 days);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertLt(netAssetsAfter, netAssetsBefore, "Net assets should decrease from net negative yield");
    }

    /// @notice Test share price decreases after loss
    function test_Loss_SharePriceDecreases() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 ppsBefore = strategy.pricePerShare();

        // Simulate loss (debt interest > yield)
        _simulateInterestAccrual(100, 1500, 365 days);

        vm.prank(keeper);
        strategy.report();

        uint256 ppsAfter = strategy.pricePerShare();

        assertLt(ppsAfter, ppsBefore, "Share price should decrease after loss");
    }

    /// @notice Test user withdraws with reduced value after loss
    function test_Loss_WithdrawAfterLoss() public virtual {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Setup leverage
        uint256 debtAmount = strategy.computeTargetDebt(depositAmount, TARGET_LTV_BPS);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);
        vm.prank(keeper);
        strategy.rebalance(debtAmount, true, "");

        // Simulate loss
        _simulateInterestAccrual(100, 1200, 180 days);

        vm.prank(keeper);
        strategy.report();

        // Withdraw all
        vm.prank(user1);
        uint256 assets = strategy.redeem(shares, user1, user1);

        assertLt(assets, depositAmount, "User should receive less than deposited after loss");
    }

    /// @notice Test strategy remains solvent after partial loss
    function test_Loss_PartialLoss_StillSolvent() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());
        (uint256 netAssetsBefore, uint256 totalCollateralBefore, uint256 totalDebtBefore) = strategy.getNetAssets();

        // Simulate moderate loss
        _simulateInterestAccrual(100, 800, 180 days);

        (uint256 netAssetsAfter, uint256 totalCollateralAfter, uint256 totalDebtAfter) = strategy.getNetAssets();

        assertGt(netAssetsAfter, 0, "Strategy should still have positive net assets");
        assertLt(netAssetsAfter, netAssetsBefore, "Net assets should decrease");

        assertEq(totalCollateralBefore, totalCollateralAfter, "Collateral should remain same");
        assertGt(totalDebtAfter, totalDebtBefore, "Debt should increase due to interest");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                           ADDITIONAL EDGE CASE TESTS                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test handling of zero deposit amount
    function testRevert_Deposit_ZeroAmount() public {
        _mintAndApprove(address(assetToken), user1, address(strategy), 0);

        vm.prank(user1);
        vm.expectRevert();
        strategy.deposit(0, user1);
    }

    /// @notice Test minimum viable deposit
    function test_EdgeCase_MinimumDeposit() public {
        uint256 minDeposit = 1e15; // Small amount

        _mintAndApprove(address(assetToken), user1, address(strategy), minDeposit);

        vm.prank(user1);
        uint256 shares = strategy.deposit(minDeposit, user1);

        assertGt(shares, 0, "Should receive shares for minimum deposit");
    }

    /// @notice Test deposit at exact limit
    function test_EdgeCase_MaxDeposit_AtLimit() public {
        // Deposit exactly at limit
        _mintAndApprove(address(assetToken), user1, address(strategy), DEPOSIT_LIMIT);

        vm.prank(user1);
        uint256 shares = strategy.deposit(DEPOSIT_LIMIT, user1);

        assertGt(shares, 0, "Should accept deposit at limit");
        assertEq(strategy.availableDepositLimit(user1), 0, "No more deposits should be available");
    }

    /// @notice Test withdraw more than balance
    function testRevert_Withdraw_MoreThanBalance() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        vm.prank(user1);
        vm.expectRevert();
        strategy.withdraw(depositAmount * 2, user1, user1);
    }

    /// @notice Test multiple rebalance iterations
    function test_Rebalance_MultipleIterations() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        // First leverage up to 50% LTV
        uint256 debtAmount1 = strategy.computeTargetDebt(depositAmount, 5000);
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount1);

        vm.prank(keeper);
        strategy.rebalance(debtAmount1, true, "");

        (uint256 netAssets1, , ) = strategy.getNetAssets();

        // Second leverage up to higher LTV
        uint256 additionalDebt = strategy.computeTargetDebt(netAssets1, TARGET_LTV_BPS);
        (, , uint256 currentDebt) = strategy.getNetAssets();
        uint256 debtAmount2 = additionalDebt > currentDebt ? additionalDebt - currentDebt : 0;

        if (debtAmount2 > 0) {
            _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount2);

            vm.prank(keeper);
            strategy.rebalance(debtAmount2, true, "");
        }

        uint256 finalLtv = strategy.getStrategyLtv();
        assertGt(finalLtv, 5000, "LTV should increase after second rebalance");
        assertApproxEqRel(finalLtv, TARGET_LTV_BPS, 1e15, "LTV should be near target");
    }

    /// @notice Test emergency shutdown scenario
    function test_Shutdown_EmergencyWithdraw() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        // Shutdown strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        assertTrue(strategy.isShutdown(), "Strategy should be shutdown");

        // User should still be able to withdraw
        uint256 shares = strategy.balanceOf(user1);
        vm.prank(user1);
        uint256 assets = strategy.redeem(shares, user1, user1);

        assertGt(assets, 0, "User should receive assets after shutdown");
    }
}
