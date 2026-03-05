// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {LeveragedStrategyTest} from "../../common/LeveragedStrategyTest.sol";
import {LeveragedStrategyBaseSetup} from "../../common/LeveragedStrategyBaseSetup.sol";

import {WethAgethWethSetup} from "./WethAgethWethSetup.sol";

/// @title WethAgethWethStrategy
/// @notice Runs all common LeveragedStrategy invariant tests against WETH-agETH-WETH Leveraged Strategy
/// on Silo Ethereum market
/// @dev Inherits from both LeveragedStrategyTest (tests) and WethAgethWethSetup (setup)
contract WethAgethWethStrategy is LeveragedStrategyTest, WethAgethWethSetup {
    /// @notice Use WethAgethWethSetup's setUp which calls all the abstract implementations
    function setUp() public override(LeveragedStrategyBaseSetup, WethAgethWethSetup) {
        WethAgethWethSetup.setUp();
    }

    // Default test amounts (helper functions to account for different decimals)
    function DEFAULT_DEPOSIT() internal view override returns (uint256) {
        return 1e18; // 1 ETH
    }

    function LARGE_DEPOSIT() internal view override returns (uint256) {
        return 100 * 1e18; // 100 ETH
    }

    function SMALL_DEPOSIT() internal view override returns (uint256) {
        return 1e16; // 0.01 ETH
    }
}
