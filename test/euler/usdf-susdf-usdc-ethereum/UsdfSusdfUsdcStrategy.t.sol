// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {LeveragedStrategyTest} from "../../common/LeveragedStrategyTest.sol";
import {LeveragedStrategyBaseSetup} from "../../common/LeveragedStrategyBaseSetup.sol";

import {UsdfSusdfUsdcSetup} from "./UsdfSusdfUsdcSetup.sol";

/// @title EulerLeveragedStrategyTest
/// @notice Runs all common LeveragedStrategy invariant tests against LeveragedEuler
/// @dev Inherits from both LeveragedStrategyTest (tests) and UsdfSusdfUsdcSetup (setup)
contract UsdfSusdfUsdcStrategyTest is LeveragedStrategyTest, UsdfSusdfUsdcSetup {
    /// @notice Use UsdfSusdfUsdcSetup's setUp which calls all the abstract implementations
    function setUp() public override(LeveragedStrategyBaseSetup, UsdfSusdfUsdcSetup) {
        UsdfSusdfUsdcSetup.setUp();
    }
}
