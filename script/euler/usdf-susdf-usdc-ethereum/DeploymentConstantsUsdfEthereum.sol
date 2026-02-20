// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {DeploymentConstants} from "../../common/DeploymentConstants.sol";
import {FlashLoanRouter} from "ceres-strategies/src/periphery/FlashLoanRouter.sol";

/// @title DeploymentConstantsUsdfEthereum
/// @notice Strategy-specific constants for USDf-sUSDf-USDC Euler strategy on Ethereum
/// @dev Contains all addresses and parameters specific to this strategy
abstract contract DeploymentConstantsUsdfEthereum is DeploymentConstants {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   STRATEGY TOKENS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Asset and collateral tokens
    address internal constant USDF_TOKEN = 0xFa2B947eEc368f42195f24F36d2aF29f7c24CeC2;
    address internal constant SUSDF_TOKEN = 0xc8CF6D7991f15525488b2A83Df53468D682Ba4B0;
    address internal constant USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USD_TOKEN = 0x0000000000000000000000000000000000000348; // synthetic USD representation

    // Token decimals
    uint8 internal constant USDF_TOKEN_DECIMALS = 18;
    uint8 internal constant SUSDF_TOKEN_DECIMALS = 18;
    uint8 internal constant USDC_TOKEN_DECIMALS = 6;

    // Strategy token assignments
    address internal constant ASSET_TOKEN = USDF_TOKEN;
    address internal constant COLLATERAL_TOKEN = SUSDF_TOKEN;
    address internal constant DEBT_TOKEN = USDC_TOKEN;

    uint8 internal constant ASSET_DECIMALS = USDF_TOKEN_DECIMALS;
    uint8 internal constant COLLATERAL_TOKEN_DECIMALS = SUSDF_TOKEN_DECIMALS;
    uint8 internal constant DEBT_TOKEN_DECIMALS = USDC_TOKEN_DECIMALS;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   EULER PROTOCOL                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Euler Vault Connector
    address internal constant EVC = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;

    // Euler Vaults
    address internal constant COLLATERAL_VAULT = 0x2F849ba554C1ea2eDe9C240Bbe9d247dd6eC8A6B;
    address internal constant DEBT_VAULT = 0x3573A84Bee11D49A1CbCe2b291538dE7a7dD81c6;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   ORACLES                                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Euler oracle addresses
    address internal constant ASSET_TO_COLLATERAL_ORACLE = 0x1ada463F00833545b33A1B6551d0954Ba32be1fc;
    address internal constant ASSET_TO_USD_ORACLE = 0xEd8e9151602E40233D358d6C323d9F9717a1bec4;
    address internal constant DEBT_TO_USD_ORACLE = 0xD35657aE033A86FFa8fc6Bc767C5eb57C7c3D4B8;

    uint256 internal constant ORACLE_PRECISION = 1e18;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   FLASH LOANS                                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Flash loan configuration
    address internal constant FLASH_LOAN_PROVIDER = SILO_USDC_FLASH_LOAN_PROVIDER;
    FlashLoanRouter.FlashSource internal constant FLASH_LOAN_SOURCE = FlashLoanRouter.FlashSource.ERC3156; // Using ERC3156 flash loan provider (Silo)

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   STRATEGY PARAMETERS                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Strategy metadata
    string internal constant STRATEGY_NAME = "Ceres Leveraged Euler Strategy";
    string internal constant STRATEGY_SYMBOL = "ceres-USDf-LeveragedEuler";

    // LTV parameters
    uint16 internal constant TARGET_LTV_BPS = 7000; // 70%
    uint16 internal constant MAX_SLIPPAGE_BPS = 25; // 0.25%
    uint16 internal constant MAX_LOSS_BPS = 200; // 2%

    // Limits
    uint96 internal constant DEPOSIT_LIMIT = 1000 * 1e18; // 1k USDf
    uint128 internal constant REDEEM_LIMIT_SHARES = type(uint128).max;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   DEPLOYED CONTRACTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Strategy-specific deployed contracts (update after deployment)
    address internal constant EULER_ORACLE_ADAPTER_ADDRESS = 0x7BD5628E3E452bD21B83E20bcdC25F00CbB68BC7;

    address internal constant LEVERAGED_EULER_STRATEGY_ADDRESS_OLD = 0xc36376C13B7Fba83359d4C8bafF7868eDca65EE3;
    address internal constant LEVERAGED_EULER_STRATEGY_ADDRESS = address(0);
}
