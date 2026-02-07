// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title DeploymentConstantsEthereum
/// @notice Chain-specific constants for Ethereum mainnet deployments
/// @dev This contract contains addresses for deployed core contracts and common infrastructure
///      Update the core contract addresses after deploying RoleManager, CeresSwapper, and FlashLoanRouter
abstract contract DeploymentConstantsEthereum {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   CORE DEPLOYED CONTRACTS                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Common contracts used across strategies - need to be updated after deployment
    // If it is address(0) (not yet deployed), deployment scripts will revert
    address internal constant ROLE_MANAGER_ADDRESS = 0xA988271170293886868C06981b106b9beB96e450;
    address internal constant CERES_SWAPPER_ADDRESS = 0x1605041af13337394a1954a91c30E0a211890f18;
    address internal constant FLASH_LOAN_ROUTER_ADDRESS = 0x4783fE2E58E4F2471678f48b2A41689025B0a15E;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   THIRD PARTY CONTRACTS                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Kyberswap integration
    address internal constant KYBER_SCALE_HELPER = 0x2f577A41BeC1BE1152AeEA12e73b7391d15f655D;
    address internal constant KYBERSWAP_ROUTER = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;

    // Paraswap integration
    address internal constant AUGUSTUS_REGISTRY = 0xa68bEA62Dc4034A689AA0F58A76681433caCa663;
    address internal constant AUGUSTUS_SWAPPER = 0x6A000F20005980200259B80c5102003040001068;

    // Flash loan providers
    address internal constant SILO_USDC_FLASH_LOAN_PROVIDER = 0x90957Ad08D1EC15D4CCf5461444fFb0dC499EB2D;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   MANAGEMENT ADDRESSES                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Ceres deployer address
    address internal constant CERES_DEPLOYER = 0xB9F4A819183BeFC31E282BC02D33cc1ab985Aa03;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   ROLE CONSTANTS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    bytes32 internal constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 internal constant MANAGEMENT_ROLE = keccak256("MANAGEMENT_ROLE");

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   HELPER FUNCTIONS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Check if core contracts need to be deployed
    function isRoleManagerDeployed() internal pure returns (bool) {
        return ROLE_MANAGER_ADDRESS != address(0);
    }

    function isSwapperDeployed() internal pure returns (bool) {
        return CERES_SWAPPER_ADDRESS != address(0);
    }

    function isFlashLoanRouterDeployed() internal pure returns (bool) {
        return FLASH_LOAN_ROUTER_ADDRESS != address(0);
    }
}
