 // // SPDX-License-Identifier: BUSL-1.1
// pragma solidity 0.8.28;

// import {LeveragedStrategyTest} from "../../common/LeveragedStrategyTest.sol";
// import {LeveragedStrategyBaseSetup} from "../../common/LeveragedStrategyBaseSetup.sol";

// import {WethAgethWethSetup} from "./WethAgethWethSetup.sol";

// /// @title WethAgethWethStrategy
// /// @notice Runs all common LeveragedStrategy invariant tests against WETH-agETH-WETH Leveraged Strategy
// /// on Silo Ethereum market
// /// @dev Inherits from both LeveragedStrategyTest (tests) and WethAgethWethSetup (setup)
// contract WethAgethWethStrategy is LeveragedStrategyTest, WethAgethWethSetup {
//     /// @notice Use WethAgethWethSetup's setUp which calls all the abstract implementations
//     function setUp() public override(LeveragedStrategyBaseSetup, WethAgethWethSetup) {
//         WethAgethWethSetup.setUp();
//     }
// }
