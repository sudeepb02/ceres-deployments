// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {LeveragedStrategyTest} from "../../common/LeveragedStrategyTest.sol";
import {LeveragedStrategyBaseSetup} from "../../common/LeveragedStrategyBaseSetup.sol";

import {AvusdSavusdUsdcSetup} from "./AvusdSavusdUsdcSetup.sol";

/// @title EulerLeveragedStrategyTest
/// @notice Runs all common LeveragedStrategy invariant tests against LeveragedEuler
/// @dev Inherits from both LeveragedStrategyTest (tests) and AvusdSavusdUsdcSetup (setup)
contract AvusdSavusdUsdcStrategy is LeveragedStrategyTest, AvusdSavusdUsdcSetup {
    /// @notice Use AvusdSavusdUsdcSetup's setUp which calls all the abstract implementations
    function setUp() public override(LeveragedStrategyBaseSetup, AvusdSavusdUsdcSetup) {
        AvusdSavusdUsdcSetup.setUp();
    }
}
