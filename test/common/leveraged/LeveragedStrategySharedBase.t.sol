// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {LibError} from "ceres-strategies/src/libraries/LibError.sol";
import {ICeresBaseStrategy} from "ceres-strategies/src/interfaces/strategies/ICeresBaseStrategy.sol";

import {LeveragedStrategyBaseSetup} from "../LeveragedStrategyBaseSetup.sol";

abstract contract LeveragedStrategySharedBase is LeveragedStrategyBaseSetup {
    event RedeemRequest(
        address indexed controller,
        address indexed owner_,
        uint256 indexed requestId,
        address requester,
        uint256 shares
    );

    event RequestProcessed(uint256 indexed requestId, uint256 totalShares, uint256 pricePerShare);

    function test_Basic_SetupStrategy_IsValid() public view {
        assertTrue(address(0) != address(strategy), "Strategy should be deployed");
        assertEq(strategy.asset(), address(assetToken), "Asset should match");
        (, , , , address performanceFeeRecipient_, ) = _baseConfig();
        assertEq(performanceFeeRecipient_, feeReceiver, "Fee receiver should match");
        assertTrue(roleManager.hasRole(MANAGEMENT_ROLE, management), "Management should match");
        assertTrue(roleManager.hasRole(KEEPER_ROLE, keeper), "Keeper should match");
    }

    function test_Basic_InitialValues_LeveragedStrategy() public view {
        address _collateral = address(strategy.COLLATERAL_TOKEN());
        address _debt = address(strategy.DEBT_TOKEN());

        if (_collateral == _debt) {
            assertTrue(_isAssetCollateral(), "IS_ASSET_COLLATERAL should be true");
        } else {
            assertFalse(_isAssetCollateral(), "IS_ASSET_COLLATERAL should be true");
        }

        assertEq(_collateral, address(collateralToken), "COLLATERAL_TOKEN mismatch");
        assertEq(_debt, address(debtToken), "DEBT_TOKEN mismatch");
        assertEq(strategy.BPS_PRECISION(), 100_00, "BPS_PRECISION mismatch");

        assertEq(address(strategy.oracleAdapter()), address(oracleAdapter), "oracleAdapter mismatch");
        assertEq(_swapperAddress(), address(swapper), "swapper mismatch");

        assertEq(_targetLtvBps(), TARGET_LTV_BPS, "targetLtvBps mismatch");
        assertEq(_maxSlippageBps(), MAX_SLIPPAGE_BPS, "maxSlippageBps mismatch");
        (uint128 depositLimit_, uint128 redeemLimitShares_, ) = _depositWithdrawLimits();
        assertEq(depositLimit_, DEPOSIT_LIMIT, "depositLimit mismatch");
        assertEq(redeemLimitShares_, REDEEM_LIMIT_SHARES, "redeemLimit mismatch");
    }

    function test_Basic_InitialValues_BaseStrategy() public view {
        assertEq(address(strategy.asset()), address(assetToken), "asset mismatch");

        assertTrue(management != address(0), "management should not be zero");
        assertTrue(roleManager.hasRole(MANAGEMENT_ROLE, management), "Management should match");

        assertTrue(keeper != address(0), "keeper should not be zero");
        assertTrue(roleManager.hasRole(KEEPER_ROLE, keeper), "Keeper should match");

        (, uint16 performanceFeeBps_, , , address performanceFeeRecipient_, ) = _baseConfig();
        assertEq(performanceFeeRecipient_, feeReceiver, "performanceFeeRecipient mismatch");
        assertEq(performanceFeeBps_, 1500, "performanceFee should be 1500 (15%)");

        assertEq(strategy.totalSupply(), 0, "totalSupply should be 0");
        assertEq(strategy.totalAssets(), 0, "totalAssets should be 0");
    }

    function test_Basic_Deposit_Basic() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 depositAmountInCollateral = oracleAdapter.convertAssetsToCollateral(depositAmount);

        _mintAndApprove(address(assetToken), user1, address(strategy), depositAmount);

        vm.prank(user1);
        uint256 shares = strategy.deposit(depositAmount, user1);

        _swapAssetsAndDepositCollateral(depositAmount);

        assertEq(shares, depositAmount, "Shares should equal deposit for first deposit");
        assertEq(strategy.balanceOf(user1), shares, "User balance should match shares");

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();
        _assertApproxEqBps(netAssets, depositAmount, 10, "Net assets should match deposit");

        _assertApproxEqBps(totalCollateral, depositAmountInCollateral, 10, "Collateral should match deposit");
        assertEq(totalDebt, 0, "Debt should be 0");
    }

    function test_Basic_Deposit_Basic_MultipleUsers() public {
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 deposit2 = DEFAULT_DEPOSIT() * 2;

        uint256 shares1 = _setupUserDeposit(user1, deposit1);
        uint256 shares2 = _setupUserDeposit(user2, deposit2);

        assertEq(strategy.balanceOf(user1), shares1, "User1 shares mismatch");
        assertEq(strategy.balanceOf(user2), shares2, "User2 shares mismatch");
        assertEq(strategy.totalAssets(), deposit1 + deposit2, "Total assets mismatch");
    }

    function test_Basic_Deposit_AssetsDeployedAsCollateral() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 assetAmountInCollateral = oracleAdapter.convertAssetsToCollateral(depositAmount);

        uint256 collateralBefore = strategy.getCollateralAmount();

        _setupUserDeposit(user1, depositAmount);

        uint256 collateralAfter = strategy.getCollateralAmount();
        assertGt(collateralAfter, collateralBefore, "Collateral should be deposited to protocol");
        _assertApproxEqBps(
            collateralAfter,
            collateralBefore + assetAmountInCollateral,
            MAX_SLIPPAGE_BPS,
            "collateral amount mismatch"
        );
    }

    function test_Basic_Withdraw_Basic() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 shares = strategy.balanceOf(user1);
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, sharesToRedeem);

        assertApproxEqRel(assets, depositAmount / 2, 1e15, "User should receive ~half of deposited amount");
        assertEq(strategy.balanceOf(user1), shares - sharesToRedeem, "User should have remaining shares");
    }

    function test_Basic_Withdraw_Partial() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 sharesToRedeem = shares / 4;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, sharesToRedeem);

        assertApproxEqRel(assets, depositAmount / 4, 1e15, "Should receive ~25% of assets");
        assertEq(strategy.balanceOf(user1), shares - sharesToRedeem, "Remaining shares mismatch");
    }

    function test_Basic_Withdraw_AllShares() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

        assertApproxEqRel(assets, depositAmount, 1e15, "Should receive all deposited assets");
        assertEq(strategy.balanceOf(user1), 0, "Should have no remaining shares");
    }

    function test_Basic_RequestRedeem_Basic() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 sharesToRedeem = shares / 2;
        uint256 initialStrategyBalance = strategy.balanceOf(address(strategy));

        vm.expectEmit(true, true, true, true);
        emit RedeemRequest(user1, user1, 1, user1, sharesToRedeem);

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);

        assertEq(requestId, 1, "First request should be requestId 1");

        assertEq(
            strategy.balanceOf(address(strategy)),
            initialStrategyBalance + sharesToRedeem,
            "Shares should be transferred to strategy"
        );
        assertEq(strategy.balanceOf(user1), shares - sharesToRedeem, "User shares should decrease");

        ICeresBaseStrategy.UserRedeemRequest memory userRequest = strategy.userRedeemRequests(user1);
        assertEq(userRequest.requestId, requestId, "User requestId should be set");
        assertEq(userRequest.shares, sharesToRedeem, "User shares should be recorded");

        ICeresBaseStrategy.RequestDetails memory details = strategy.requestDetails(requestId);
        assertEq(details.totalShares, sharesToRedeem, "Request totalShares should be updated");
        assertEq(details.pricePerShare, 0, "Request should not be processed yet");
    }

    function test_Basic_RequestRedeem_MultipleUsersInBatch() public {
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 deposit2 = DEFAULT_DEPOSIT() * 2;

        uint256 shares1 = _setupUserDeposit(user1, deposit1);
        uint256 shares2 = _setupUserDeposit(user2, deposit2);

        uint256 redeem1 = shares1 / 2;
        uint256 redeem2 = shares2 / 3;

        uint256 requestId1 = _requestRedeemAs(user1, redeem1);
        uint256 requestId2 = _requestRedeemAs(user2, redeem2);

        assertEq(requestId1, 1, "Should be requestId 1");
        assertEq(requestId1, requestId2, "Both should be in same requestId");

        ICeresBaseStrategy.RequestDetails memory details = strategy.requestDetails(requestId1);
        assertEq(details.totalShares, redeem1 + redeem2, "Total shares should be sum of both requests");

        ICeresBaseStrategy.UserRedeemRequest memory user1Request = strategy.userRedeemRequests(user1);
        ICeresBaseStrategy.UserRedeemRequest memory user2Request = strategy.userRedeemRequests(user2);
        assertEq(user1Request.shares, redeem1, "User1 shares mismatch");
        assertEq(user2Request.shares, redeem2, "User2 shares mismatch");
    }

    function test_Basic_RequestRedeem_IncrementalSameUser() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 firstRequest = shares / 4;
        uint256 secondRequest = shares / 4;

        uint256 requestId1 = _requestRedeemAs(user1, firstRequest);
        uint256 requestId2 = _requestRedeemAs(user1, secondRequest);

        assertEq(requestId1, requestId2, "Should be same requestId");

        ICeresBaseStrategy.UserRedeemRequest memory userRequest = strategy.userRedeemRequests(user1);
        assertEq(userRequest.shares, firstRequest + secondRequest, "Shares should accumulate");

        ICeresBaseStrategy.RequestDetails memory details = strategy.requestDetails(requestId1);
        assertEq(details.totalShares, firstRequest + secondRequest, "Batch total should include both requests");
    }

    function testRevert_Basic_RequestRedeem_ExistingPendingRequest() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        _requestRedeemAs(user1, shares / 4);
        _processCurrentRequest("");

        vm.expectRevert(LibError.ExistingPendingRedeemRequest.selector);
        _requestRedeemAs(user1, shares / 4);
    }

    function testRevert_Basic_RequestRedeem_InsufficientShares() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        vm.expectRevert();
        _requestRedeemAs(user1, shares * 2);
    }

    function testRevert_Basic_RequestRedeem_ZeroShares() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        vm.expectRevert(LibError.ZeroShares.selector);
        _requestRedeemAs(user1, 0);
    }

    function test_Basic_ProcessRequest_SetsPricePerShare() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 requestId = _requestRedeemAs(user1, shares / 2);

        uint128 pricePerShareBefore = strategy.requestDetails(requestId).pricePerShare;
        assertEq(pricePerShareBefore, 0, "Price per share should be 0 before processing");

        vm.expectEmit(true, false, false, false);
        emit RequestProcessed(requestId, 0, 0);
        _processCurrentRequest("");

        uint128 pricePerShareAfter = strategy.requestDetails(requestId).pricePerShare;
        assertGt(pricePerShareAfter, 0, "Price per share should be set after processing");
    }

    function test_Basic_ProcessRequest_WithIdleFunds() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 shares = strategy.balanceOf(user1);
        uint256 sharesToRedeem = shares / 4;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);

        uint128 reserveBefore = strategy.withdrawalReserve();

        _processCurrentRequest("");

        uint128 reserveAfter = strategy.withdrawalReserve();

        assertGt(reserveAfter, reserveBefore, "Withdrawal reserve should increase");
        assertEq(strategy.currentRequestId(), requestId + 1, "Current requestId should increment");
    }

    function test_Basic_ProcessRequest_IncrementsRequestId() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint256 currentIdBefore = strategy.currentRequestId();

        _requestRedeemAs(user1, strategy.balanceOf(user1) / 2);
        _processCurrentRequest("");

        uint256 currentIdAfter = strategy.currentRequestId();

        assertEq(currentIdAfter, currentIdBefore + 1, "CurrentRequestId should increment");
    }

    function testRevert_Basic_ProcessRequest_NoRequestsToProcess() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        _requestRedeemAs(user1, strategy.balanceOf(user1) / 2);

        _processCurrentRequest("");

        vm.expectRevert(LibError.NoRequestsToProcess.selector);
        vm.prank(keeper);
        strategy.processCurrentRequest("");
    }

    function testRevert_Basic_ProcessRequest_OnlyKeeper() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        _requestRedeemAs(user1, strategy.balanceOf(user1) / 2);

        vm.expectRevert();
        vm.prank(user1);
        strategy.processCurrentRequest("");
    }

    function test_Basic_CompleteRedeem_AfterProcessing() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint256 reserveBefore = strategy.withdrawalReserve();
        uint256 strategySharesBefore = strategy.balanceOf(address(strategy));

        uint256 assetsReceived = _redeemAs(user1, sharesToRedeem);

        assertGt(assetsReceived, 0, "Should receive assets");
        assertApproxEqRel(assetsReceived, depositAmount / 2, 1e15, "Should receive ~half of deposit");

        assertEq(
            strategy.balanceOf(address(strategy)),
            strategySharesBefore - sharesToRedeem,
            "Shares should be burned from strategy"
        );

        assertLt(strategy.withdrawalReserve(), reserveBefore, "Withdrawal reserve should decrease");
        assertApproxEqRel(assetToken.balanceOf(user1), assetsReceived, 1e15, "User should have received assets");
    }

    function testRevert_Basic_CompleteRedeem_NotYetProcessed() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        _requestRedeemAs(user1, shares / 2);

        vm.expectRevert(LibError.WithdrawalNotReady.selector);
        _redeemAs(user1, shares / 2);
    }

    function testRevert_Basic_CompleteRedeem_ExceedsProcessedAmount() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint256 requestedShares = shares / 2;

        _requestRedeemAs(user1, requestedShares);
        _processCurrentRequest("");

        vm.expectRevert();
        _redeemAs(user1, requestedShares * 2);
    }

    function test_Basic_PendingRedeemRequest_BeforeProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);

        uint256 pending = strategy.pendingRedeemRequest(requestId, user1);
        assertEq(pending, sharesToRedeem, "Should return pending shares");
    }

    function test_Basic_PendingRedeemRequest_AfterProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint256 pending = strategy.pendingRedeemRequest(requestId, user1);
        assertEq(pending, 0, "Should return 0 after processing");
    }

    function test_Basic_PendingRedeemRequest_MultipleUsers() public {
        uint256 shares1 = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 shares2 = _setupUserDeposit(user2, DEFAULT_DEPOSIT() * 2);

        uint256 redeem1 = shares1 / 2;
        uint256 redeem2 = shares2 / 3;

        uint256 requestId = _requestRedeemAs(user1, redeem1);
        _requestRedeemAs(user2, redeem2);

        assertEq(strategy.pendingRedeemRequest(requestId, user1), redeem1, "User1 pending mismatch");
        assertEq(strategy.pendingRedeemRequest(requestId, user2), redeem2, "User2 pending mismatch");
    }

    function test_Basic_ClaimableRedeemRequest_BeforeProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 requestId = _requestRedeemAs(user1, shares / 2);

        uint256 claimable = strategy.claimableRedeemRequest(requestId, user1);
        assertEq(claimable, 0, "Should return 0 before processing");
    }

    function test_Basic_ClaimableRedeemRequest_AfterProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint256 claimable = strategy.claimableRedeemRequest(requestId, user1);
        assertEq(claimable, sharesToRedeem, "Should return claimable shares");
    }

    function test_Basic_ClaimableRedeemRequest_AfterClaiming() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");
        _redeemAs(user1, sharesToRedeem);

        uint256 claimable = strategy.claimableRedeemRequest(requestId, user1);
        assertEq(claimable, 0, "Should return 0 after claiming");
    }

    function test_Basic_MaxRedeem_BeforeProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        _requestRedeemAs(user1, shares / 2);

        uint256 maxRedeemable = strategy.maxRedeem(user1);
        assertEq(maxRedeemable, 0, "Should return 0 before processing");
    }

    function test_Basic_MaxRedeem_AfterProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint256 maxRedeemable = strategy.maxRedeem(user1);
        assertEq(maxRedeemable, sharesToRedeem, "Should return redeemable shares");
    }

    function test_Basic_MaxRedeem_NoPendingRequest() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint256 maxRedeemable = strategy.maxRedeem(user1);
        assertEq(maxRedeemable, 0, "Should return 0 with no request");
    }

    function test_Basic_MaxWithdraw_BeforeProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        _requestRedeemAs(user1, shares / 2);

        uint256 maxWithdrawable = strategy.maxWithdraw(user1);
        assertEq(maxWithdrawable, 0, "Should return 0 before processing");
    }

    function test_Basic_MaxWithdraw_AfterProcessing() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint256 maxWithdrawable = strategy.maxWithdraw(user1);
        assertGt(maxWithdrawable, 0, "Should return withdrawable assets");
        assertApproxEqRel(maxWithdrawable, depositAmount / 2, 1e15, "Should be ~half of deposit");
    }

    function test_Basic_WithdrawalReserve_IncreasesOnProcess() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint128 reserveBefore = strategy.withdrawalReserve();

        _requestRedeemAs(user1, strategy.balanceOf(user1) / 2);
        _processCurrentRequest("");

        uint128 reserveAfter = strategy.withdrawalReserve();

        assertGt(reserveAfter, reserveBefore, "Withdrawal reserve should increase");
    }

    function test_Basic_WithdrawalReserve_DecreasesOnRedeem() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint128 reserveBefore = strategy.withdrawalReserve();

        _redeemAs(user1, sharesToRedeem);

        uint128 reserveAfter = strategy.withdrawalReserve();

        assertLt(reserveAfter, reserveBefore, "Withdrawal reserve should decrease");
    }

    function test_Basic_WithdrawalReserve_MultipleOutstanding() public {
        uint256 deposit = DEFAULT_DEPOSIT();

        uint256 shares1 = _setupUserDeposit(user1, deposit);
        _requestRedeemAs(user1, shares1 / 2);
        _processCurrentRequest("");

        uint128 reserveAfter1 = strategy.withdrawalReserve();
        assertGt(reserveAfter1, 0, "Reserve should be non-zero after first batch");

        uint256 shares2 = _setupUserDeposit(user2, deposit);
        _requestRedeemAs(user2, shares2 / 3);
        _processCurrentRequest("");

        uint128 reserveAfter2 = strategy.withdrawalReserve();
        assertGt(reserveAfter2, reserveAfter1, "Reserve should increase with second batch");

        _redeemAs(user1, shares1 / 2);

        uint128 reserveAfter3 = strategy.withdrawalReserve();
        assertLt(reserveAfter3, reserveAfter2, "Reserve should decrease after user1 claim");
        assertGt(reserveAfter3, 0, "Reserve should still be positive (user2 unclaimed)");

        _redeemAs(user2, shares2 / 3);

        uint128 reserveAfter4 = strategy.withdrawalReserve();
        assertLt(reserveAfter4, reserveAfter3, "Reserve should decrease after user2 claim");
    }

    function test_Basic_MultiUser_SameBatch_SamePricePerShare() public {
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 deposit2 = DEFAULT_DEPOSIT() * 2;

        uint256 shares1 = _setupUserDeposit(user1, deposit1);
        uint256 shares2 = _setupUserDeposit(user2, deposit2);

        uint256 requestId = _requestRedeemAs(user1, shares1 / 2);
        _requestRedeemAs(user2, shares2 / 2);

        _processCurrentRequest("");

        uint128 pricePerShare = strategy.requestDetails(requestId).pricePerShare;
        assertGt(pricePerShare, 0, "Price per share should be set");

        uint256 assets1 = _redeemAs(user1, shares1 / 2);
        uint256 assets2 = _redeemAs(user2, shares2 / 2);

        assertApproxEqRel(assets1, deposit1 / 2, 1e15, "User1 should get ~half deposit");
        assertApproxEqRel(assets2, deposit2 / 2, 1e15, "User2 should get ~half deposit");
    }

    function test_Basic_MultiUser_SequentialRequestsAfterClaim() public {
        uint256 deposit = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, deposit);

        uint256 requestId1 = _requestRedeemAs(user1, shares / 4);
        _processCurrentRequest("");
        _redeemAs(user1, shares / 4);

        uint256 requestId2 = _requestRedeemAs(user1, shares / 4);
        _processCurrentRequest("");

        assertEq(requestId2, 2, "Should be batch 2");
        assertNotEq(requestId1, requestId2, "Should be different batches");

        uint256 assets = _redeemAs(user1, shares / 4);
        assertGt(assets, 0, "Should receive assets from batch 2");
    }

    function test_Basic_EdgeCase_PartialRedemption() public {
        uint256 deposit = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, deposit);
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint256 partialShares = sharesToRedeem / 2;
        uint256 assets1 = _redeemAs(user1, partialShares);
        assertGt(assets1, 0, "Should receive assets from partial redeem");

        uint256 remainingShares = sharesToRedeem - partialShares;
        uint256 assets2 = _redeemAs(user1, remainingShares);
        assertGt(assets2, 0, "Should receive remaining assets");

        assertApproxEqRel(assets1 + assets2, deposit / 2, 1e15, "Total should be ~half deposit");
    }

    function testRevert_Basic_Deposit_ZeroAmount() public {
        _mintAndApprove(address(assetToken), user1, address(strategy), 0);

        vm.prank(user1);
        vm.expectRevert();
        strategy.deposit(0, user1);
    }

    function test_Basic_EdgeCase_MinimumDeposit() public {
        uint256 minDeposit = 1e15;

        _mintAndApprove(address(assetToken), user1, address(strategy), minDeposit);

        vm.prank(user1);
        uint256 shares = strategy.deposit(minDeposit, user1);

        assertGt(shares, 0, "Should receive shares for minimum deposit");
    }

    function test_Basic_EdgeCase_MaxDeposit_AtLimit() public {
        _mintAndApprove(address(assetToken), user1, address(strategy), DEPOSIT_LIMIT);

        vm.prank(user1);
        uint256 shares = strategy.deposit(DEPOSIT_LIMIT, user1);

        assertGt(shares, 0, "Should accept deposit at limit");
        assertEq(strategy.maxDeposit(user1), 0, "No more deposits should be available");
    }

    function testRevert_Basic_Withdraw_MoreThanBalance() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        vm.prank(user1);
        vm.expectRevert();
        strategy.withdraw(depositAmount * 2, user1, user1);
    }
}
