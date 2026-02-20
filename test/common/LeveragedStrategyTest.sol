// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {LeveragedStrategyRebalance} from "./leveraged/LeveragedStrategyRebalance.t.sol";
import {LeveragedStrategyAdminAccess} from "./leveraged/LeveragedStrategyAdminAccess.t.sol";
import {LeveragedStrategyPnl} from "./leveraged/LeveragedStrategyPnl.t.sol";
import {LeveragedStrategyFuzz} from "./leveraged/LeveragedStrategyFuzz.t.sol";

/// @title LeveragedStrategyTest
/// @notice Aggregates all shared leveraged strategy test categories into a single inheritance entrypoint
abstract contract LeveragedStrategyTest is
    LeveragedStrategyRebalance,
    LeveragedStrategyAdminAccess,
    LeveragedStrategyPnl,
    LeveragedStrategyFuzz
{}
