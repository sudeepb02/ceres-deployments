// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {DeploymentConstantsEthereum} from "./DeploymentConstantsEthereum.sol";

/// @title DeploymentConstants
/// @notice Contract inherited by deployment scripts to access chain specific constants.
/// Replace with chain-specific constants for each deployment environment (e.g. DeploymentConstantsEthereum for Ethereum, etc.)
abstract contract DeploymentConstants is DeploymentConstantsEthereum {}
