// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import {LibError} from "ceres-strategies/src/libraries/LibError.sol";
import {ILeveragedStrategy} from "ceres-strategies/src/interfaces/strategies/ILeveragedStrategy.sol";

import {MockERC20} from "test/common/MockERC20.sol";

import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";

import {LeveragedStrategySharedBase} from "./LeveragedStrategySharedBase.t.sol";

abstract contract LeveragedStrategyAdminAccess is LeveragedStrategySharedBase {
    function testRevert_Admin_Rebalance_NotKeeper() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint256 debtAmount = LeverageLib.computeTargetDebt(DEFAULT_DEPOSIT(), TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), user1, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(user1);
        vm.expectRevert();
        strategy.rebalance(debtAmount, true, swapData);
    }

    function testRevert_Admin_RebalanceUsingFlashLoan_NotKeeper() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        vm.prank(user1);
        vm.expectRevert();
        strategy.rebalanceUsingFlashLoan(1e6, true, "");
    }

    function testRevert_Admin_Slippage_Exceeded() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        vm.prank(management);
        (, uint16 performanceFeeBps_, uint16 maxLossBps_, , , ) = _baseConfig();
        strategy.updateConfig(0, performanceFeeBps_, maxLossBps_);

        uint256 debtAmount = LeverageLib.computeTargetDebt(DEFAULT_DEPOSIT(), TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        bytes memory swapData = _getKyberswapSwapData(
            CHAIN_ID,
            address(debtToken),
            address(collateralToken),
            debtAmount
        );

        vm.prank(keeper);
        vm.expectRevert();
        strategy.rebalance(debtAmount, true, swapData);
    }

    function testRevert_Admin_SwapAndDepositCollateral() public {
        if (_isAssetCollateral()) {
            vm.prank(keeper);
            vm.expectRevert(LibError.InvalidAction.selector);
            strategy.swapAndDepositCollateral(1000 * 1e18, "");
        } else {
            uint256 depositAmount = DEFAULT_DEPOSIT();
            _mintAndApprove(address(assetToken), user1, address(strategy), depositAmount);

            vm.prank(user1);
            strategy.deposit(depositAmount, user1);

            uint256 strategyAssetBalanceBefore = _balance(address(assetToken), address(strategy));
            uint256 strategyCollateralBalanceBefore = strategy.getCollateralAmount();

            _swapAssetsAndDepositCollateral(strategyAssetBalanceBefore);

            assertEq(_balance(address(assetToken), address(strategy)), 0, "Asset balance should be zero");
            assertGt(
                strategy.getCollateralAmount(),
                strategyCollateralBalanceBefore,
                "Collateral balance should increase"
            );
        }
    }

    function test_Admin_SetTargetLtv_Success() public {
        uint16 newLtv = 6000;

        vm.prank(management);
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.TargetLtvUpdated(newLtv);
        strategy.setTargetLtv(newLtv);

        assertEq(_targetLtvBps(), newLtv, "Target LTV should be updated");
    }

    function test_Admin_SetMaxSlippage_Success() public {
        uint16 newSlippage = 100;

        (, uint16 performanceFeeBps_, uint16 maxLossBps_, , , ) = _baseConfig();
        vm.prank(management);
        strategy.updateConfig(newSlippage, performanceFeeBps_, maxLossBps_);

        assertEq(_maxSlippageBps(), newSlippage, "Max slippage should be updated");
    }

    function test_Admin_SetDepositAndRedeemLimit_Success() public {
        uint128 newDepositLimit = 5_000_000 * 1e18;
        uint128 newRedeemLimitShares = 1_000_000 * 1e18;

        vm.prank(management);
        strategy.setDepositWithdrawLimits(newDepositLimit, newRedeemLimitShares, 0);

        (uint128 depositLimit_, uint128 redeemLimitShares_, ) = _depositWithdrawLimits();
        assertEq(depositLimit_, newDepositLimit, "Deposit limit should be updated");
        assertEq(redeemLimitShares_, newRedeemLimitShares, "redeem limit should be updated");
    }

    function test_Admin_SetOracleAdapter_TwoStepProcess() public {
        address newAdapter = address(0x123);
        address oldAdapter = address(strategy.oracleAdapter());
        bytes32 oracleKey = strategy.ORACLE_KEY();

        vm.expectEmit(true, true, false, true);
        emit ILeveragedStrategy.UpdateRequested(oracleKey, newAdapter, block.timestamp + strategy.DELAY());
        vm.prank(management);
        strategy.requestUpdate(oracleKey, newAdapter);

        (address proposedAddress, uint64 readyTimestamp) = strategy.pendingUpdates(oracleKey);
        assertEq(proposedAddress, newAdapter, "Proposed oracle adapter should be set");
        assertEq(readyTimestamp, block.timestamp + strategy.DELAY(), "Ready timestamp should be set");

        assertEq(address(strategy.oracleAdapter()), oldAdapter, "Oracle adapter should not be updated yet");

        vm.warp(block.timestamp + strategy.DELAY() + 1);

        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.UpdateExecuted(oracleKey, oldAdapter, newAdapter);
        vm.prank(management);
        strategy.executeUpdate(oracleKey);

        assertEq(address(strategy.oracleAdapter()), newAdapter, "Oracle adapter should be updated");
    }

    function test_Admin_SetSwapper_TwoStepProcess() public {
        address newSwapper = address(0x456);
        address oldSwapper = _swapperAddress();
        bytes32 swapperKey = strategy.SWAPPER_KEY();

        vm.expectEmit(true, true, false, true);
        emit ILeveragedStrategy.UpdateRequested(swapperKey, newSwapper, block.timestamp + strategy.DELAY());
        vm.prank(management);
        strategy.requestUpdate(swapperKey, newSwapper);

        assertEq(_swapperAddress(), oldSwapper, "Swapper should not be updated yet");

        vm.warp(block.timestamp + strategy.DELAY() + 1);

        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.UpdateExecuted(swapperKey, oldSwapper, newSwapper);
        vm.prank(management);
        strategy.executeUpdate(swapperKey);

        assertEq(_swapperAddress(), newSwapper, "Swapper should be updated");
    }

    function test_Admin_CancelPendingOracleAdapter_Success() public {
        address newAdapter = address(0x123);
        bytes32 oracleKey = strategy.ORACLE_KEY();

        vm.prank(management);
        strategy.requestUpdate(oracleKey, newAdapter);

        vm.prank(management);
        vm.expectEmit(true, true, false, true);
        emit ILeveragedStrategy.UpdateCancelled(oracleKey, newAdapter);
        strategy.cancelUpdate(oracleKey);

        (address proposedAddress, ) = strategy.pendingUpdates(oracleKey);
        assertEq(proposedAddress, address(0), "Proposed oracle adapter should be cleared");
    }

    function test_Admin_CancelPendingSwapper_Success() public {
        address newSwapper = address(0x456);
        bytes32 swapperKey = strategy.SWAPPER_KEY();

        vm.prank(management);
        strategy.requestUpdate(swapperKey, newSwapper);

        vm.prank(management);
        vm.expectEmit(true, true, false, true);
        emit ILeveragedStrategy.UpdateCancelled(swapperKey, newSwapper);
        strategy.cancelUpdate(swapperKey);

        (address proposedAddress, ) = strategy.pendingUpdates(swapperKey);
        assertEq(proposedAddress, address(0), "Proposed swapper should be cleared");
    }

    function testRevert_Admin_SetTargetLtv_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.setTargetLtv(6000);
    }

    function testRevert_Admin_SetTargetLtv_InvalidLtv() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidLtv.selector);
        strategy.setTargetLtv(10000);
    }

    function testRevert_Admin_SetMaxSlippage_InvalidValue() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidValue.selector);
        (, uint16 performanceFeeBps_, uint16 maxLossBps_, , , ) = _baseConfig();
        strategy.updateConfig(10001, performanceFeeBps_, maxLossBps_);
    }

    function testRevert_Admin_SetOracleAdapter_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0x123));
    }

    function testRevert_Admin_SetSwapper_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0x456));
    }

    function testRevert_Admin_RequestOracleAdapterUpdate_ZeroAddress() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidAddress.selector);
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0));
    }

    function testRevert_Admin_RequestSwapperUpdate_ZeroAddress() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidAddress.selector);
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0));
    }

    function testRevert_Admin_ExecuteOracleAdapterUpdate_BeforeDelay() public {
        vm.prank(management);
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0x123));

        vm.prank(management);
        vm.expectRevert(LibError.NotReady.selector);
        strategy.executeUpdate(strategy.ORACLE_KEY());
    }

    function testRevert_Admin_ExecuteSwapperUpdate_BeforeDelay() public {
        vm.prank(management);
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0x456));

        vm.prank(management);
        vm.expectRevert(LibError.NotReady.selector);
        strategy.executeUpdate(strategy.SWAPPER_KEY());
    }

    function testRevert_Admin_RequestOracleAdapterUpdate_PendingExists() public {
        vm.prank(management);
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0x123));

        vm.prank(management);
        vm.expectRevert(LibError.PendingActionExists.selector);
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0x789));
    }

    function testRevert_Admin_RequestSwapperUpdate_PendingExists() public {
        vm.prank(management);
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0x456));

        vm.prank(management);
        vm.expectRevert(LibError.PendingActionExists.selector);
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0x789));
    }

    function testRevert_Admin_ExecuteOracleAdapterUpdate_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.executeUpdate(strategy.ORACLE_KEY());
    }

    function testRevert_Admin_ExecuteSwapperUpdate_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.executeUpdate(strategy.SWAPPER_KEY());
    }

    function testRevert_Admin_CancelPendingOracleAdapter_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.cancelUpdate(strategy.ORACLE_KEY());
    }

    function testRevert_Admin_CancelPendingSwapper_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.cancelUpdate(strategy.SWAPPER_KEY());
    }

    function testRevert_Admin_RescueTokens_StrategyTokens() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidToken.selector);
        strategy.rescueTokens(address(assetToken));

        vm.prank(management);
        vm.expectRevert(LibError.InvalidToken.selector);
        strategy.rescueTokens(address(debtToken));
    }

    function testRevert_Admin_Deposit_ExceedsLimit() public {
        uint256 excessDeposit = DEPOSIT_LIMIT + 200 * 1e18;
        _mintAndApprove(address(assetToken), user1, address(strategy), excessDeposit);

        vm.prank(user1);
        vm.expectRevert();
        strategy.deposit(excessDeposit, user1);
    }

    function test_Admin_RescueTokens_NonStrategyToken() public {
        IERC20 randomToken = IERC20(address(new MockERC20("Random USD", "rUSD", 18)));

        deal(address(randomToken), address(strategy), 1000 * 1e18);

        uint256 balanceBefore = randomToken.balanceOf(management);

        vm.prank(management);
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.TokensRecovered(address(randomToken), 1000 * 1e18);
        strategy.rescueTokens(address(randomToken));

        uint256 balanceAfter = randomToken.balanceOf(management);
        assertEq(balanceAfter - balanceBefore, 1000 * 1e18, "Should receive rescued tokens");
    }
}
