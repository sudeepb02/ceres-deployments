// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {LibError} from "ceres-strategies/src/libraries/LibError.sol";
import {ILeveragedStrategy} from "ceres-strategies/src/interfaces/strategies/ILeveragedStrategy.sol";
import {ICeresBaseStrategy} from "ceres-strategies/src/interfaces/strategies/ICeresBaseStrategy.sol";
import {LeverageLib} from "ceres-strategies/src/libraries/LeverageLib.sol";

import {LeveragedStrategyBaseSetup} from "./LeveragedStrategyBaseSetup.sol";

import {MockERC20} from "test/common/MockERC20.sol";

/// @title LeveragedStrategyTest
/// @notice Abstract test contract containing all common invariant tests for LeveragedStrategy implementations
/// @dev Protocol-specific test contracts should inherit from this AND their protocol's TestSetup
abstract contract LeveragedStrategyTest is LeveragedStrategyBaseSetup {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         EVENTS                                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Async withdrawal events
    event RedeemRequest(
        address indexed controller,
        address indexed owner_,
        uint256 indexed requestId,
        address requester,
        uint256 shares
    );

    event RequestProcessed(uint256 indexed requestId, uint256 totalShares, uint256 pricePerShare);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  SETUP VERIFICATION TESTS                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_SetupStrategy_IsValid() public view {
        assertTrue(address(0) != address(strategy), "Strategy should be deployed");
        assertEq(strategy.asset(), address(assetToken), "Asset should match");
        (, , , , address performanceFeeRecipient_, ) = _baseConfig();
        assertEq(performanceFeeRecipient_, feeReceiver, "Fee receiver should match");
        assertTrue(roleManager.hasRole(MANAGEMENT_ROLE, management), "Management should match");
        assertTrue(roleManager.hasRole(KEEPER_ROLE, keeper), "Keeper should match");
    }

    function test_InitialValues_LeveragedStrategy() public view {
        assertEq(address(strategy.COLLATERAL_TOKEN()), address(collateralToken), "COLLATERAL_TOKEN mismatch");
        assertEq(address(strategy.DEBT_TOKEN()), address(debtToken), "DEBT_TOKEN mismatch");
        assertTrue(_isAssetCollateral(), "IS_ASSET_COLLATERAL should be true");
        assertEq(strategy.BPS_PRECISION(), 100_00, "BPS_PRECISION mismatch");

        assertEq(address(strategy.oracleAdapter()), address(oracleAdapter), "oracleAdapter mismatch");
        assertEq(_swapperAddress(), address(swapper), "swapper mismatch");

        assertEq(_targetLtvBps(), TARGET_LTV_BPS, "targetLtvBps mismatch");
        assertEq(_maxSlippageBps(), MAX_SLIPPAGE_BPS, "maxSlippageBps mismatch");
        (uint128 depositLimit_, uint128 redeemLimitShares_, ) = _depositWithdrawLimits();
        assertEq(depositLimit_, DEPOSIT_LIMIT, "depositLimit mismatch");
        assertEq(redeemLimitShares_, REDEEM_LIMIT_SHARES, "redeemLimit mismatch");
    }

    function test_InitialValues_BaseStrategy() public view {
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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    DEPOSIT TESTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Deposit_Basic() public {
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

        uint256 shares = strategy.balanceOf(user1);
        uint256 sharesToRedeem = shares / 2;

        // Phase 1: Request redeem
        _requestRedeemAs(user1, sharesToRedeem);

        // Phase 2: Process request
        _processCurrentRequest("");

        // Phase 3: Complete redeem
        uint256 assets = _redeemAs(user1, sharesToRedeem);

        assertApproxEqRel(assets, depositAmount / 2, 1e15, "User should receive ~half of deposited amount");
        assertEq(strategy.balanceOf(user1), shares - sharesToRedeem, "User should have remaining shares");
    }

    function test_Withdraw_Partial() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 sharesToRedeem = shares / 4; // 25%

        // Phase 1: Request redeem
        _requestRedeemAs(user1, sharesToRedeem);

        // Phase 2: Process request
        _processCurrentRequest("");

        // Phase 3: Complete redeem
        uint256 assets = _redeemAs(user1, sharesToRedeem);

        assertApproxEqRel(assets, depositAmount / 4, 1e15, "Should receive ~25% of assets");
        assertEq(strategy.balanceOf(user1), shares - sharesToRedeem, "Remaining shares mismatch");
    }

    function test_Withdraw_AllShares() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Phase 1: Request redeem
        _requestRedeemAs(user1, shares);

        // Phase 2: Process request
        _processCurrentRequest("");

        // Phase 3: Complete redeem
        uint256 assets = _redeemAs(user1, shares);

        assertApproxEqRel(assets, depositAmount, 1e15, "Should receive all deposited assets");
        assertEq(strategy.balanceOf(user1), 0, "Should have no remaining shares");
    }

    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawPercent) public {
        depositAmount = bound(depositAmount, 1000 * 1e18, 100_000 * 1e18);
        withdrawPercent = bound(withdrawPercent, 10, 100);

        uint256 shares = _setupUserDeposit(user1, depositAmount);
        uint256 sharesToRedeem = (shares * withdrawPercent) / 100;

        // Phase 1: Request redeem
        _requestRedeemAs(user1, sharesToRedeem);

        // Phase 2: Process request
        _processCurrentRequest("");

        // Phase 3: Complete redeem
        uint256 assets = _redeemAs(user1, sharesToRedeem);

        assertGt(assets, 0, "Should receive assets");
        assertApproxEqRel(assets, (depositAmount * withdrawPercent) / 100, 1e16, "Should receive proportional assets");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              ASYNC WITHDRAWAL TESTS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          PHASE 1: REQUEST REDEEM TESTS                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test basic redeem request functionality
    function test_RequestRedeem_Basic() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 sharesToRedeem = shares / 2;
        uint256 initialStrategyBalance = strategy.balanceOf(address(strategy));

        // Request redemption
        vm.expectEmit(true, true, true, true);
        emit RedeemRequest(user1, user1, 1, user1, sharesToRedeem);

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);

        // Verify request ID
        assertEq(requestId, 1, "First request should be requestId 1");

        // Verify shares transferred to strategy
        assertEq(
            strategy.balanceOf(address(strategy)),
            initialStrategyBalance + sharesToRedeem,
            "Shares should be transferred to strategy"
        );
        assertEq(strategy.balanceOf(user1), shares - sharesToRedeem, "User shares should decrease");

        // Verify user request state
        ICeresBaseStrategy.UserRedeemRequest memory userRequest = strategy.userRedeemRequests(user1);
        assertEq(userRequest.requestId, requestId, "User requestId should be set");
        assertEq(userRequest.shares, sharesToRedeem, "User shares should be recorded");

        // Verify request details
        ICeresBaseStrategy.RequestDetails memory details = strategy.requestDetails(requestId);
        assertEq(details.totalShares, sharesToRedeem, "Request totalShares should be updated");
        assertEq(details.pricePerShare, 0, "Request should not be processed yet");
    }

    /// @notice Test multiple users requesting in same batch
    function test_RequestRedeem_MultipleUsersInBatch() public {
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 deposit2 = DEFAULT_DEPOSIT() * 2;

        uint256 shares1 = _setupUserDeposit(user1, deposit1);
        uint256 shares2 = _setupUserDeposit(user2, deposit2);

        uint256 redeem1 = shares1 / 2;
        uint256 redeem2 = shares2 / 3;

        // Both users request in same batch (requestId 1)
        uint256 requestId1 = _requestRedeemAs(user1, redeem1);
        uint256 requestId2 = _requestRedeemAs(user2, redeem2);

        assertEq(requestId1, 1, "Should be requestId 1");
        assertEq(requestId1, requestId2, "Both should be in same requestId");

        // Verify batch total
        ICeresBaseStrategy.RequestDetails memory details = strategy.requestDetails(requestId1);
        assertEq(details.totalShares, redeem1 + redeem2, "Total shares should be sum of both requests");

        // Verify individual user states
        ICeresBaseStrategy.UserRedeemRequest memory user1Request = strategy.userRedeemRequests(user1);
        ICeresBaseStrategy.UserRedeemRequest memory user2Request = strategy.userRedeemRequests(user2);
        assertEq(user1Request.shares, redeem1, "User1 shares mismatch");
        assertEq(user2Request.shares, redeem2, "User2 shares mismatch");
    }

    /// @notice Test user requesting multiple times in same batch
    function test_RequestRedeem_IncrementalSameUser() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 firstRequest = shares / 4;
        uint256 secondRequest = shares / 4;

        // First request
        uint256 requestId1 = _requestRedeemAs(user1, firstRequest);

        // Second request (same batch)
        uint256 requestId2 = _requestRedeemAs(user1, secondRequest);

        assertEq(requestId1, requestId2, "Should be same requestId");

        // Verify cumulative shares
        ICeresBaseStrategy.UserRedeemRequest memory userRequest = strategy.userRedeemRequests(user1);
        assertEq(userRequest.shares, firstRequest + secondRequest, "Shares should accumulate");

        // Verify batch total
        ICeresBaseStrategy.RequestDetails memory details = strategy.requestDetails(requestId1);
        assertEq(details.totalShares, firstRequest + secondRequest, "Batch total should include both requests");
    }

    /// @notice Test reverting when user has existing pending request in different batch
    function testRevert_RequestRedeem_ExistingPendingRequest() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Request in batch 1
        _requestRedeemAs(user1, shares / 4);

        // Process batch 1 (moves to batch 2)
        _processCurrentRequest("");

        // Don't claim yet - user still has pending request in batch 1

        // Try to request in batch 2 (should fail because batch 1 not claimed)
        vm.expectRevert(LibError.ExistingPendingRedeemRequest.selector);
        _requestRedeemAs(user1, shares / 4);
    }

    /// @notice Test reverting when requesting more shares than owned
    function testRevert_RequestRedeem_InsufficientShares() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        vm.expectRevert();
        _requestRedeemAs(user1, shares * 2);
    }

    /// @notice Test reverting when requesting zero shares
    function testRevert_RequestRedeem_ZeroShares() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        vm.expectRevert(LibError.ZeroShares.selector);
        _requestRedeemAs(user1, 0);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                        PHASE 2: PROCESS REQUEST TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test processing request sets pricePerShare
    function test_ProcessRequest_SetsPricePerShare() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 requestId = _requestRedeemAs(user1, shares / 2);

        // Before processing
        uint128 pricePerShareBefore = strategy.requestDetails(requestId).pricePerShare;
        assertEq(pricePerShareBefore, 0, "Price per share should be 0 before processing");

        // Process
        vm.expectEmit(true, false, false, false);
        emit RequestProcessed(requestId, 0, 0); // We'll check actual values separately
        _processCurrentRequest("");

        // After processing
        uint128 pricePerShareAfter = strategy.requestDetails(requestId).pricePerShare;
        assertGt(pricePerShareAfter, 0, "Price per share should be set after processing");
    }

    /// @notice Test processing with idle funds (no deleverage needed)
    function test_ProcessRequest_WithIdleFunds() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 shares = strategy.balanceOf(user1);
        uint256 sharesToRedeem = shares / 4; // Only 25%, plenty of idle funds

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);

        uint128 reserveBefore = strategy.withdrawalReserve();

        // Process (should use idle funds)
        _processCurrentRequest("");

        uint128 reserveAfter = strategy.withdrawalReserve();

        // Verify withdrawal reserve increased
        assertGt(reserveAfter, reserveBefore, "Withdrawal reserve should increase");

        // Verify requestId incremented
        assertEq(strategy.currentRequestId(), requestId + 1, "Current requestId should increment");
    }

    /// @notice Test processing increments currentRequestId
    function test_ProcessRequest_IncrementsRequestId() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint256 currentIdBefore = strategy.currentRequestId();

        _requestRedeemAs(user1, strategy.balanceOf(user1) / 2);
        _processCurrentRequest("");

        uint256 currentIdAfter = strategy.currentRequestId();

        assertEq(currentIdAfter, currentIdBefore + 1, "CurrentRequestId should increment");
    }

    /// @notice Test reverting when trying to process with no requests
    function testRevert_ProcessRequest_NoRequestsToProcess() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        _requestRedeemAs(user1, strategy.balanceOf(user1) / 2);

        // Process existing request
        _processCurrentRequest("");

        // Try to process again without any new requests
        vm.expectRevert(LibError.NoRequestsToProcess.selector);
        vm.prank(keeper);
        strategy.processCurrentRequest("");
    }

    /// @notice Test only keeper can process requests
    function testRevert_ProcessRequest_OnlyKeeper() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        _requestRedeemAs(user1, strategy.balanceOf(user1) / 2);

        // Non-keeper tries to process
        vm.expectRevert();
        vm.prank(user1);
        strategy.processCurrentRequest("");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                        PHASE 3: COMPLETE REDEEM TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test completing redeem after processing
    function test_CompleteRedeem_AfterProcessing() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        uint256 sharesToRedeem = shares / 2;

        // Request and process
        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint256 reserveBefore = strategy.withdrawalReserve();
        uint256 strategySharesBefore = strategy.balanceOf(address(strategy));

        // Complete redeem
        uint256 assetsReceived = _redeemAs(user1, sharesToRedeem);

        // Verify assets received
        assertGt(assetsReceived, 0, "Should receive assets");
        assertApproxEqRel(assetsReceived, depositAmount / 2, 1e15, "Should receive ~half of deposit");

        // Verify shares burned from strategy
        assertEq(
            strategy.balanceOf(address(strategy)),
            strategySharesBefore - sharesToRedeem,
            "Shares should be burned from strategy"
        );

        // Verify withdrawal reserve decreased
        assertLt(strategy.withdrawalReserve(), reserveBefore, "Withdrawal reserve should decrease");

        // Verify user balance
        assertApproxEqRel(assetToken.balanceOf(user1), assetsReceived, 1e15, "User should have received assets");
    }

    /// @notice Test reverting when trying to redeem before processing
    function testRevert_CompleteRedeem_NotYetProcessed() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        // Request but don't process
        _requestRedeemAs(user1, shares / 2);

        // Try to redeem
        vm.expectRevert(LibError.WithdrawalNotReady.selector);
        _redeemAs(user1, shares / 2);
    }

    /// @notice Test reverting when trying to redeem more than processed
    function testRevert_CompleteRedeem_ExceedsProcessedAmount() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint256 requestedShares = shares / 2;

        // Request and process
        _requestRedeemAs(user1, requestedShares);
        _processCurrentRequest("");

        // Try to redeem more than requested
        vm.expectRevert();
        _redeemAs(user1, requestedShares * 2);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                    VIEW FUNCTIONS & STATE TESTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          VIEW FUNCTION: pendingRedeemRequest                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test pendingRedeemRequest returns correct shares before processing
    function test_PendingRedeemRequest_BeforeProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);

        // Should return requested shares since not yet processed
        uint256 pending = strategy.pendingRedeemRequest(requestId, user1);
        assertEq(pending, sharesToRedeem, "Should return pending shares");
    }

    /// @notice Test pendingRedeemRequest returns 0 after processing
    function test_PendingRedeemRequest_AfterProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        // Should return 0 since request is processed
        uint256 pending = strategy.pendingRedeemRequest(requestId, user1);
        assertEq(pending, 0, "Should return 0 after processing");
    }

    /// @notice Test pendingRedeemRequest for multiple users in same batch
    function test_PendingRedeemRequest_MultipleUsers() public {
        uint256 shares1 = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 shares2 = _setupUserDeposit(user2, DEFAULT_DEPOSIT() * 2);

        uint256 redeem1 = shares1 / 2;
        uint256 redeem2 = shares2 / 3;

        uint256 requestId = _requestRedeemAs(user1, redeem1);
        _requestRedeemAs(user2, redeem2); // Same batch

        // Both should show their respective pending amounts
        assertEq(strategy.pendingRedeemRequest(requestId, user1), redeem1, "User1 pending mismatch");
        assertEq(strategy.pendingRedeemRequest(requestId, user2), redeem2, "User2 pending mismatch");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          VIEW FUNCTION: claimableRedeemRequest                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test claimableRedeemRequest returns 0 before processing
    function test_ClaimableRedeemRequest_BeforeProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 requestId = _requestRedeemAs(user1, shares / 2);

        // Should return 0 since not processed yet
        uint256 claimable = strategy.claimableRedeemRequest(requestId, user1);
        assertEq(claimable, 0, "Should return 0 before processing");
    }

    /// @notice Test claimableRedeemRequest returns shares after processing
    function test_ClaimableRedeemRequest_AfterProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        // Should return claimable shares
        uint256 claimable = strategy.claimableRedeemRequest(requestId, user1);
        assertEq(claimable, sharesToRedeem, "Should return claimable shares");
    }

    /// @notice Test claimableRedeemRequest returns 0 after claiming
    function test_ClaimableRedeemRequest_AfterClaiming() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        uint256 requestId = _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");
        _redeemAs(user1, sharesToRedeem);

        // Should return 0 since already claimed
        uint256 claimable = strategy.claimableRedeemRequest(requestId, user1);
        assertEq(claimable, 0, "Should return 0 after claiming");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          VIEW FUNCTION: maxRedeem                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test maxRedeem returns 0 before processing
    function test_MaxRedeem_BeforeProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        _requestRedeemAs(user1, shares / 2);

        // Should return 0 since not processed
        uint256 maxRedeemable = strategy.maxRedeem(user1);
        assertEq(maxRedeemable, 0, "Should return 0 before processing");
    }

    /// @notice Test maxRedeem returns shares after processing
    function test_MaxRedeem_AfterProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        // Should return redeemable shares
        uint256 maxRedeemable = strategy.maxRedeem(user1);
        assertEq(maxRedeemable, sharesToRedeem, "Should return redeemable shares");
    }

    /// @notice Test maxRedeem returns 0 when no pending request
    function test_MaxRedeem_NoPendingRequest() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        // No request made
        uint256 maxRedeemable = strategy.maxRedeem(user1);
        assertEq(maxRedeemable, 0, "Should return 0 with no request");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          VIEW FUNCTION: maxWithdraw                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test maxWithdraw returns 0 before processing
    function test_MaxWithdraw_BeforeProcessing() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        _requestRedeemAs(user1, shares / 2);

        // Should return 0 since not processed
        uint256 maxWithdrawable = strategy.maxWithdraw(user1);
        assertEq(maxWithdrawable, 0, "Should return 0 before processing");
    }

    /// @notice Test maxWithdraw returns assets after processing
    function test_MaxWithdraw_AfterProcessing() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        // Should return withdrawable assets
        uint256 maxWithdrawable = strategy.maxWithdraw(user1);
        assertGt(maxWithdrawable, 0, "Should return withdrawable assets");
        assertApproxEqRel(maxWithdrawable, depositAmount / 2, 1e15, "Should be ~half of deposit");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          WITHDRAWAL RESERVE ACCOUNTING TESTS                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test withdrawalReserve increases when request is processed
    function test_WithdrawalReserve_IncreasesOnProcess() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        uint128 reserveBefore = strategy.withdrawalReserve();

        _requestRedeemAs(user1, strategy.balanceOf(user1) / 2);
        _processCurrentRequest("");

        uint128 reserveAfter = strategy.withdrawalReserve();

        assertGt(reserveAfter, reserveBefore, "Withdrawal reserve should increase");
    }

    /// @notice Test withdrawalReserve decreases when request is redeemed
    function test_WithdrawalReserve_DecreasesOnRedeem() public {
        uint256 shares = _setupUserDeposit(user1, DEFAULT_DEPOSIT());
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        uint128 reserveBefore = strategy.withdrawalReserve();

        _redeemAs(user1, sharesToRedeem);

        uint128 reserveAfter = strategy.withdrawalReserve();

        assertLt(reserveAfter, reserveBefore, "Withdrawal reserve should decrease");
    }

    /// @notice Test withdrawalReserve with multiple outstanding processed requests
    function test_WithdrawalReserve_MultipleOutstanding() public {
        uint256 deposit = DEFAULT_DEPOSIT();

        // Batch 1: User1 requests
        uint256 shares1 = _setupUserDeposit(user1, deposit);
        _requestRedeemAs(user1, shares1 / 2);
        _processCurrentRequest("");

        uint128 reserveAfter1 = strategy.withdrawalReserve();
        assertGt(reserveAfter1, 0, "Reserve should be non-zero after first batch");

        // Batch 2: User2 requests
        uint256 shares2 = _setupUserDeposit(user2, deposit);
        _requestRedeemAs(user2, shares2 / 3);
        _processCurrentRequest("");

        uint128 reserveAfter2 = strategy.withdrawalReserve();
        assertGt(reserveAfter2, reserveAfter1, "Reserve should increase with second batch");

        // User1 claims - reserve should decrease but still > 0 (user2 hasn't claimed)
        _redeemAs(user1, shares1 / 2);

        uint128 reserveAfter3 = strategy.withdrawalReserve();
        assertLt(reserveAfter3, reserveAfter2, "Reserve should decrease after user1 claim");
        assertGt(reserveAfter3, 0, "Reserve should still be positive (user2 unclaimed)");

        // User2 claims - reserve should go to ~0
        _redeemAs(user2, shares2 / 3);

        uint128 reserveAfter4 = strategy.withdrawalReserve();
        assertLt(reserveAfter4, reserveAfter3, "Reserve should decrease after user2 claim");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          MULTI-USER ASYNC SCENARIOS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test multiple users in same batch get same pricePerShare
    function test_MultiUser_SameBatch_SamePricePerShare() public {
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 deposit2 = DEFAULT_DEPOSIT() * 2;

        uint256 shares1 = _setupUserDeposit(user1, deposit1);
        uint256 shares2 = _setupUserDeposit(user2, deposit2);

        // Both request in same batch
        uint256 requestId = _requestRedeemAs(user1, shares1 / 2);
        _requestRedeemAs(user2, shares2 / 2);

        _processCurrentRequest("");

        // Both should have same pricePerShare
        uint128 pricePerShare = strategy.requestDetails(requestId).pricePerShare;
        assertGt(pricePerShare, 0, "Price per share should be set");

        // User1 claims
        uint256 assets1 = _redeemAs(user1, shares1 / 2);

        // User2 claims later
        uint256 assets2 = _redeemAs(user2, shares2 / 2);

        // Both should get proportional assets based on same price
        assertApproxEqRel(assets1, deposit1 / 2, 1e15, "User1 should get ~half deposit");
        assertApproxEqRel(assets2, deposit2 / 2, 1e15, "User2 should get ~half deposit");
    }

    /// @notice Test user can request new batch after claiming previous
    function test_MultiUser_SequentialRequestsAfterClaim() public {
        uint256 deposit = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, deposit);

        // Batch 1: Request and complete
        uint256 requestId1 = _requestRedeemAs(user1, shares / 4);
        _processCurrentRequest("");
        _redeemAs(user1, shares / 4);

        // Now user1 can request again (batch 2)
        uint256 requestId2 = _requestRedeemAs(user1, shares / 4);
        _processCurrentRequest("");

        assertEq(requestId2, 2, "Should be batch 2");
        assertNotEq(requestId1, requestId2, "Should be different batches");

        // Should be able to claim batch 2
        uint256 assets = _redeemAs(user1, shares / 4);
        assertGt(assets, 0, "Should receive assets from batch 2");
    }

    /// @notice Test partial redemption from processed request
    function test_EdgeCase_PartialRedemption() public {
        uint256 deposit = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, deposit);
        uint256 sharesToRedeem = shares / 2;

        _requestRedeemAs(user1, sharesToRedeem);
        _processCurrentRequest("");

        // Redeem only half of what was requested
        uint256 partialShares = sharesToRedeem / 2;
        uint256 assets1 = _redeemAs(user1, partialShares);
        assertGt(assets1, 0, "Should receive assets from partial redeem");

        // Redeem remaining
        uint256 remainingShares = sharesToRedeem - partialShares;
        uint256 assets2 = _redeemAs(user1, remainingShares);
        assertGt(assets2, 0, "Should receive remaining assets");

        // Total should approximate half of deposit
        assertApproxEqRel(assets1 + assets2, deposit / 2, 1e15, "Total should be ~half deposit");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  NET ASSETS TESTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_GetNetAssets_AfterDeposit() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 depositAmountInCollateral = oracleAdapter.convertAssetsToCollateral(depositAmount);

        _setupUserDeposit(user1, depositAmount);

        (uint256 netAssets, uint256 totalCollateral, uint256 totalDebt) = strategy.getNetAssets();

        assertEq(totalDebt, 0, "Debt should be zero before leverage");
        _assertApproxEqBps(netAssets, depositAmount, 10, "Net assets should be approx equal to deposit");
        _assertApproxEqBps(totalCollateral, depositAmountInCollateral, 10, "Collateral should equal deposit");
    }

    function test_GetNetAssets_AfterLeverage() public {
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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  REBALANCE TESTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Rebalance_LeverageUp() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        _setupUserDeposit(user1, depositAmount);

        uint256 debtAmount = LeverageLib.computeTargetDebt(depositAmount, TARGET_LTV_BPS, strategy.oracleAdapter());
        _mintAndApprove(address(debtToken), keeper, address(strategy), debtAmount);

        uint256 collateralBefore = strategy.getCollateralAmount();

        bytes memory swapData = _getKyberswapSwapData(
            block.chainid,
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
        // Allow 0.1% tolerance
        _assertApproxEqBps(actualLtv, TARGET_LTV_BPS, 10, "LTV should be near target");
    }

    function test_Rebalance_ZeroDebt_NoOp() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        // Try to leverage down when there's no debt
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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                            FLASH LOAN REBALANCE TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_RebalanceUsingFlashLoan_LeverageUp() public {
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

    function test_RebalanceUsingFlashLoan_LeverageDown() public {
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

        // (, , uint256 debtAfter) = strategy.getNetAssets();

        uint256 debtAfter;
        (netAssets, totalCollateral, debtAfter) = strategy.getNetAssets();
        console.log("netAssets after", netAssets);
        console.log("totalCollateral after", totalCollateral);
        console.log("debt after", debtAfter);
        assertLt(debtAfter, debt, "Debt should decrease");
    }

    function test_RebalanceUsingFlashLoan_EmitsEvent() public {
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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  LEVERAGE RATIO TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_GetLeverage_AfterLeverageUp() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 leverage = _getCurrentLeverage();

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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              PROFIT SCENARIO TESTS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_Profit_CollateralPriceIncrease() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate 10% price increase for Collateral token (1000 BPS = 10%)
        _simulateCollateralPriceChange(1000);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase with price");
    }

    function test_Profit_WithdrawAfterPriceIncrease() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Setup leverage
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

        // Price increases 20%
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
        _simulateCollateralPriceChange(-1000);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertLt(netAssetsAfter, netAssetsBefore, "Net assets should decrease with price drop");
    }

    function test_Loss_LeveragedLossesAmplified() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate 10% price decrease
        _simulateCollateralPriceChange(-1000);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        uint256 lossPercent = ((netAssetsBefore - netAssetsAfter) * 100) / netAssetsBefore;

        // With 70% LTV (~3.33x leverage), 10% price drop should cause ~33% loss
        assertGt(lossPercent, 20, "Leveraged losses should exceed unleveraged");
        assertLt(lossPercent, 40, "Leveraged losses should exceed unleveraged");
    }

    function test_Loss_ApproachingLiquidation() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        // Simulate significant price drop (15%)
        _simulateCollateralPriceChange(-1500);

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
        _simulateCollateralPriceChange(-1200);

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
        _simulateCollateralPriceChange(500);
        (uint256 netAssets1, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(-800);
        (uint256 netAssets2, , ) = strategy.getNetAssets();

        _simulateCollateralPriceChange(300);
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

        // Withdrawing should trigger deleveraging via async flow
        _requestRedeemAs(user1, withdrawShares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, withdrawShares);

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

        // Full withdrawal via async flow
        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

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

    function testRevert_RebalanceUsingFlashLoan_NotKeeper() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        vm.prank(user1);
        vm.expectRevert();
        strategy.rebalanceUsingFlashLoan(1e6, true, "");
    }

    function testRevert_Slippage_Exceeded() public {
        _setupUserDeposit(user1, DEFAULT_DEPOSIT());

        // Set slippage to zero, as actual swaps have non-zero slippage, so the tx should revert
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

    function testRevert_SwapAndDepositCollateral() public {
        // If Asset is collateral, then swapAndDepositCollateral function should revert
        if (_isAssetCollateral()) {
            vm.prank(keeper);
            vm.expectRevert(LibError.InvalidAction.selector);
            strategy.swapAndDepositCollateral(1000 * 1e18, "");
        } else {
            uint256 depositAmount = DEFAULT_DEPOSIT();
            // If Asset is not collateral, deposit assets to strategy and test swapAndDepositCollateral
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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              ADMIN FUNCTION TESTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_SetTargetLtv_Success() public {
        uint16 newLtv = 6000; // 60%

        vm.prank(management);
        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.TargetLtvUpdated(newLtv);
        strategy.setTargetLtv(newLtv);

        assertEq(_targetLtvBps(), newLtv, "Target LTV should be updated");
    }

    function test_SetMaxSlippage_Success() public {
        uint16 newSlippage = 100; // 1%

        vm.prank(management);
        (, uint16 performanceFeeBps_, uint16 maxLossBps_, , , ) = _baseConfig();
        strategy.updateConfig(newSlippage, performanceFeeBps_, maxLossBps_);

        assertEq(_maxSlippageBps(), newSlippage, "Max slippage should be updated");
    }

    function test_SetDepositAndRedeemLimit_Success() public {
        uint128 newDepositLimit = 5_000_000 * 1e18;
        uint128 newRedeemLimitShares = 1_000_000 * 1e18;

        vm.prank(management);
        strategy.setDepositWithdrawLimits(newDepositLimit, newRedeemLimitShares, 0);

        (uint128 depositLimit_, uint128 redeemLimitShares_, ) = _depositWithdrawLimits();
        assertEq(depositLimit_, newDepositLimit, "Deposit limit should be updated");
        assertEq(redeemLimitShares_, newRedeemLimitShares, "redeem limit should be updated");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          ORACLE/SWAPPER UPDATE TESTS (2-step)                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_SetOracleAdapter_TwoStepProcess() public {
        address newAdapter = address(0x123);
        address oldAdapter = address(strategy.oracleAdapter());
        bytes32 oracleKey = strategy.ORACLE_KEY();

        // Step 1: Request oracle adapter update
        vm.expectEmit(true, true, false, true);
        emit ILeveragedStrategy.UpdateRequested(oracleKey, newAdapter, block.timestamp + strategy.DELAY());
        vm.prank(management);
        strategy.requestUpdate(oracleKey, newAdapter);

        // Verify pending state
        (address proposedAddress, uint64 readyTimestamp) = strategy.pendingUpdates(oracleKey);
        assertEq(proposedAddress, newAdapter, "Proposed oracle adapter should be set");
        assertEq(readyTimestamp, block.timestamp + strategy.DELAY(), "Ready timestamp should be set");

        // Oracle adapter should not be updated yet
        assertEq(address(strategy.oracleAdapter()), oldAdapter, "Oracle adapter should not be updated yet");

        // Step 2: Wait for delay period and execute
        vm.warp(block.timestamp + strategy.DELAY() + 1);

        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.UpdateExecuted(oracleKey, oldAdapter, newAdapter);
        vm.prank(management);
        strategy.executeUpdate(oracleKey);

        assertEq(address(strategy.oracleAdapter()), newAdapter, "Oracle adapter should be updated");
    }

    function test_SetSwapper_TwoStepProcess() public {
        address newSwapper = address(0x456);
        address oldSwapper = _swapperAddress();
        bytes32 swapperKey = strategy.SWAPPER_KEY();

        // Step 1: Request swapper update
        vm.expectEmit(true, true, false, true);
        emit ILeveragedStrategy.UpdateRequested(swapperKey, newSwapper, block.timestamp + strategy.DELAY());
        vm.prank(management);
        strategy.requestUpdate(swapperKey, newSwapper);

        // Swapper should not be updated yet
        assertEq(_swapperAddress(), oldSwapper, "Swapper should not be updated yet");

        // Step 2: Wait for delay period and execute
        vm.warp(block.timestamp + strategy.DELAY() + 1);

        vm.expectEmit(true, true, true, true);
        emit ILeveragedStrategy.UpdateExecuted(swapperKey, oldSwapper, newSwapper);
        vm.prank(management);
        strategy.executeUpdate(swapperKey);

        assertEq(_swapperAddress(), newSwapper, "Swapper should be updated");
    }

    function test_CancelPendingOracleAdapter_Success() public {
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

    function test_CancelPendingSwapper_Success() public {
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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          ADMIN FUNCTION REVERT TESTS                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function testRevert_SetTargetLtv_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.setTargetLtv(6000);
    }

    function testRevert_SetTargetLtv_InvalidLtv() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidLtv.selector);
        strategy.setTargetLtv(10000); // 100%
    }

    function testRevert_SetMaxSlippage_InvalidValue() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidValue.selector);
        (, uint16 performanceFeeBps_, uint16 maxLossBps_, , , ) = _baseConfig();
        strategy.updateConfig(10001, performanceFeeBps_, maxLossBps_); // > 100%
    }

    function testRevert_SetOracleAdapter_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0x123));
    }

    function testRevert_SetSwapper_NotManagement() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0x456));
    }

    function testRevert_RequestOracleAdapterUpdate_ZeroAddress() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidAddress.selector);
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0));
    }

    function testRevert_RequestSwapperUpdate_ZeroAddress() public {
        vm.prank(management);
        vm.expectRevert(LibError.InvalidAddress.selector);
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0));
    }

    function testRevert_ExecuteOracleAdapterUpdate_BeforeDelay() public {
        vm.prank(management);
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0x123));

        vm.prank(management);
        vm.expectRevert(LibError.NotReady.selector);
        strategy.executeUpdate(strategy.ORACLE_KEY());
    }

    function testRevert_ExecuteSwapperUpdate_BeforeDelay() public {
        vm.prank(management);
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0x456));

        vm.prank(management);
        vm.expectRevert(LibError.NotReady.selector);
        strategy.executeUpdate(strategy.SWAPPER_KEY());
    }

    function testRevert_RequestOracleAdapterUpdate_PendingExists() public {
        vm.prank(management);
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0x123));

        vm.prank(management);
        vm.expectRevert(LibError.PendingActionExists.selector);
        strategy.requestUpdate(strategy.ORACLE_KEY(), address(0x789));
    }

    function testRevert_RequestSwapperUpdate_PendingExists() public {
        vm.prank(management);
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0x456));

        vm.prank(management);
        vm.expectRevert(LibError.PendingActionExists.selector);
        strategy.requestUpdate(strategy.SWAPPER_KEY(), address(0x789));
    }

    function testRevert_ExecuteOracleAdapterUpdate_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.executeUpdate(strategy.ORACLE_KEY());
    }

    function testRevert_ExecuteSwapperUpdate_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.executeUpdate(strategy.SWAPPER_KEY());
    }

    function testRevert_CancelPendingOracleAdapter_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.cancelUpdate(strategy.ORACLE_KEY());
    }

    function testRevert_CancelPendingSwapper_NoPending() public {
        vm.prank(management);
        vm.expectRevert(LibError.NoPendingActionExists.selector);
        strategy.cancelUpdate(strategy.SWAPPER_KEY());
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
        (uint256 profit, uint256 loss) = strategy.harvestAndReport();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 balanceBefore = assetToken.balanceOf(user1);

        // Withdraw all funds using async flow
        _requestRedeemAs(user1, _amount);
        _processCurrentRequest("");
        _redeemAs(user1, _amount);

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
        (uint256 profit, uint256 loss) = strategy.harvestAndReport();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        uint256 balanceBefore = assetToken.balanceOf(user1);

        // Withdraw all funds using async flow
        _requestRedeemAs(user1, _amount);
        _processCurrentRequest("");
        _redeemAs(user1, _amount);

        assertGe(assetToken.balanceOf(user1), balanceBefore + _amount, "!final balance");
    }

    function test_ProfitableReport_WithFees(uint256 _amount, uint16 _profitFactor) public {
        vm.assume(_amount > 10_000 && _amount < DEPOSIT_LIMIT);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, BPS_PRECISION));

        // Set performance fee to 10%
        vm.prank(management);
        (uint16 maxSlippageBps, , uint16 maxLossBps, , , ) = strategy.getBaseStrategyConfig();
        strategy.updateConfig(maxSlippageBps, 1_000, maxLossBps);

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
        (uint256 profit, uint256 loss) = strategy.harvestAndReport();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / BPS_PRECISION;

        assertEq(strategy.balanceOf(feeReceiver), expectedShares);

        uint256 balanceBefore = assetToken.balanceOf(user1);

        // Withdraw all funds using async flow
        _requestRedeemAs(user1, _amount);
        _processCurrentRequest("");
        _redeemAs(user1, _amount);

        assertGe(assetToken.balanceOf(user1), balanceBefore + _amount, "!final balance");

        // Withdraw fee receiver shares using async flow
        _requestRedeemAs(feeReceiver, expectedShares);
        _processCurrentRequest("");
        _redeemAs(feeReceiver, expectedShares);

        assertEq(strategy.totalAssets(), 0, "!strategy total assets");
        assertEq(strategy.totalSupply(), 0, "!strategy total supply");

        assertGe(assetToken.balanceOf(feeReceiver), expectedShares, "!perf fee out");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                         MULTI-STEP LIFECYCLE TESTS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_FullLifecycle_DepositLeverageHarvestWithdraw() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();

        // 1. Deposit
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // 2. Leverage up
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

        // 3. Price increases (bull market)
        _simulateCollateralPriceChange(1500);

        // 4. Report profits
        vm.prank(keeper);
        strategy.harvestAndReport();

        // 5. Withdraw with profit via async flow
        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

        assertGt(assets, depositAmount, "Should profit from leveraged position");
    }

    function test_MultiUser_DifferentEntryPrices() public {
        // User1 enters at initial price
        uint256 deposit1 = DEFAULT_DEPOSIT();
        uint256 shares1 = _setupUserDeposit(user1, deposit1);

        // Setup leverage
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

        // Price increases 10%
        _simulateCollateralPriceChange(1000);

        // User2 enters at higher price
        uint256 deposit2 = DEFAULT_DEPOSIT();
        _setupUserDeposit(user2, deposit2);

        // Rebalance for new deposits
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

        // User1 should have more value per share (entered at lower price)
        uint256 user1Value = strategy.convertToAssets(shares1);

        assertGt(user1Value, deposit1, "User1 should have gains (early entry)");
    }

    function test_Rebalance_MaintainTargetLtv() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 initialLtv = strategy.getStrategyLtv();

        // Price drops, LTV increases
        _simulateCollateralPriceChange(-1000);

        uint256 ltvAfterDrop = strategy.getStrategyLtv();
        assertGt(ltvAfterDrop, initialLtv, "LTV should increase after price drop");

        // Deleverage to bring LTV back to target
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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                           INTEREST ACCRUAL PROFIT TESTS                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test profit from collateral yield accrual
    function test_Profit_CollateralYieldAccrual() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate 10% APY on collateral, 5% APY on debt over 1 year
        _simulateCollateralPriceChange(500); // 5% net

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase from yield");
    }

    /// @notice Test net profit when yield exceeds debt interest
    function test_Profit_YieldExceedsDebtInterest() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();
        uint256 ppsBeforeReport = strategy.convertToAssets(ONE_SHARE_UNIT());

        // Simulate high collateral yield (15% APY) vs low debt interest (3% APY)
        _simulateCollateralPriceChange(1200); // net 12%

        // Trigger report to realize profits
        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 ppsAfterReport = strategy.convertToAssets(ONE_SHARE_UNIT());
        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertGt(netAssetsAfter, netAssetsBefore, "Net assets should increase");
        assertGe(ppsAfterReport, ppsBeforeReport, "PPS should increase or stay same after profit");
    }

    /// @notice Test that profit reporting updates total assets
    function test_Profit_Report_UpdatesTotalAssets() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 totalAssetsBefore = strategy.totalAssets();

        _simulateCollateralPriceChange(1000); //10%

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 totalAssetsAfter = strategy.totalAssets();

        assertGt(totalAssetsAfter, totalAssetsBefore, "Total assets should increase after report");
    }

    function test_Profit_SharePriceIncreases() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 ppsBefore = strategy.convertToAssets(ONE_SHARE_UNIT());

        _simulateCollateralPriceChange(2000); //20%

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 ppsAfter = strategy.convertToAssets(ONE_SHARE_UNIT());
        assertGt(ppsAfter, ppsBefore, "Share price should increase");
    }

    /// @notice Test user withdraws and receives profit share
    function test_Profit_WithdrawAfterProfit() public {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Setup leverage
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

        _simulateCollateralPriceChange(1500); // 15%

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.harvestAndReport();

        assertEq(loss, 0, "loss should be 0");
        assertGt(profit, 0, "!profit");

        // Withdraw all via async flow
        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

        assertGt(assets, depositAmount, "User should receive more than deposited");
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                           INTEREST ACCRUAL LOSS TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test loss when debt interest exceeds yield
    function test_Loss_DebtInterestExceedsYield() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        (uint256 netAssetsBefore, , ) = strategy.getNetAssets();

        // Simulate low collateral yield (2% APY) and high debt interest (10% APY)
        // by reducing the price of collateral
        _simulateCollateralPriceChange(-800);

        (uint256 netAssetsAfter, , ) = strategy.getNetAssets();

        assertLt(netAssetsAfter, netAssetsBefore, "Net assets should decrease from net negative yield");
    }

    /// @notice Test share price decreases after loss
    function test_Loss_SharePriceDecreases() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());

        uint256 ppsBefore = strategy.convertToAssets(ONE_SHARE_UNIT());

        _simulateCollateralPriceChange(-200); // 2%

        vm.prank(keeper);
        strategy.harvestAndReport();

        uint256 ppsAfter = strategy.convertToAssets(ONE_SHARE_UNIT());

        assertLt(ppsAfter, ppsBefore, "Share price should decrease after loss");
    }

    /// @notice Test user withdraws with reduced value after loss
    function test_Loss_WithdrawAfterLoss() public virtual {
        uint256 depositAmount = DEFAULT_DEPOSIT();
        uint256 shares = _setupUserDeposit(user1, depositAmount);

        // Setup leverage
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

        // Simulate loss
        _simulateCollateralPriceChange(-10_00);

        vm.prank(keeper);
        strategy.harvestAndReport();

        // Withdraw all
        _requestRedeemAs(user1, shares);
        _processCurrentRequest("");
        uint256 assets = _redeemAs(user1, shares);

        assertLt(assets, depositAmount, "User should receive less than deposited after loss");
    }

    /// @notice Test strategy remains solvent after partial loss
    function test_Loss_PartialLoss_StillSolvent() public {
        _setupInitialLeveragePosition(DEFAULT_DEPOSIT());
        (uint256 netAssetsBefore, uint256 totalCollateralBefore, uint256 totalDebtBefore) = strategy.getNetAssets();

        _simulateCollateralPriceChange(-500); // -5%

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
        assertEq(strategy.maxDeposit(user1), 0, "No more deposits should be available");
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

        // Second leverage up to higher LTV
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
