# Generic Strategy Operations Scripts

This directory contains **reusable, strategy-agnostic** operational scripts for managing leveraged strategies. These scripts work with any strategy that implements the `LeveragedEuler` interface.

## Overview

All operational scripts are designed to be **generic** and **environment-variable driven**. They dynamically read configuration from the strategy contract itself, eliminating the need for strategy-specific constants or duplicated code.

## Architecture

```
script/operations/
├── StrategyOperations.sol          # Base contract with reusable helper functions
├── UpdateTargetLtv.s.sol           # Update target LTV parameter
├── HarvestAndReport.s.sol          # Harvest rewards and report to vault
├── SwapAndDepositIdleAssets.s.sol  # Deposit idle assets into the vault
├── ProcessRedeemRequest.s.sol      # Process async withdrawal requests
├── RebalanceLeverageUp.s.sol       # Increase leverage to target LTV
├── RebalanceLeverageDown.s.sol     # Decrease leverage to target LTV
└── FlashLoanProviderUpdate.s.sol   # Update flash loan provider configuration
```

## Key Features

✅ **Strategy-agnostic** - Works with any leveraged strategy  
✅ **Single source of truth** - One implementation for all strategies  
✅ **Environment-variable driven** - No hard-coded addresses  
✅ **Type-safe** - Uses strategy interfaces  
✅ **Easy to maintain** - Fix bugs once, benefit all strategies  
✅ **Flexible** - Override behavior when needed

## Common Environment Variables

All scripts require at minimum:

```bash
STRATEGY_ADDRESS=0x...          # The strategy contract address
PRIVATE_KEY=0x...               # Deployer/admin private key (for config updates)
MANAGEMENT_PVT_KEY=0x...        # Management role private key
KEEPER_PVT_KEY=0x...            # Keeper role private key
```

## Script Usage

### 1. Update Target LTV

Updates the target LTV (Loan-to-Value) ratio for the strategy.

**Required Environment Variables:**

- `STRATEGY_ADDRESS` - Strategy contract address
- `NEW_TARGET_LTV` - New target LTV in basis points (e.g., 8300 = 83%)
- `MANAGEMENT_PVT_KEY` - Management role private key

**Usage:**

```bash
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
NEW_TARGET_LTV=8300 \
forge script script/common/operations/UpdateTargetLtv.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

---

### 2. Harvest and Report

Harvests rewards from the yield protocol and reports performance to the vault.

**Required Environment Variables:**

- `STRATEGY_ADDRESS` - Strategy contract address
- `MANAGEMENT_PVT_KEY` - Management role private key

**Usage:**

```bash
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
forge script script/common/operations/HarvestAndReport.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

---

### 3. Swap and Deposit Idle Assets

Swaps idle asset tokens to collateral and deposits them into the vault.

**Required Environment Variables:**

- `STRATEGY_ADDRESS` - Strategy contract address
- `KEEPER_PVT_KEY` - Keeper role private key

**Usage:**

```bash
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
forge script script/common/operations/SwapAndDepositIdleAssets.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

---

### 4. Process Redeem Request

Processes pending async withdrawal requests by deleveraging and freeing assets.

**Required Environment Variables:**

- `STRATEGY_ADDRESS` - Strategy contract address
- `KEEPER_PVT_KEY` - Keeper role private key

**Optional Environment Variables:**

- `EXACT_OUT_AVAILABLE` - Set to `true` to use Paraswap exactOut swaps (default: `false`, uses Kyberswap)

**Usage:**

```bash
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
forge script script/common/operations/ProcessRedeemRequest.s.sol \
    --rpc-url $RPC_URL \
    --broadcast

# With exactOut swaps (if Paraswap supports it)
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
EXACT_OUT_AVAILABLE=true \
forge script script/common/operations/ProcessRedeemRequest.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

---

### 5. Rebalance Leverage Up

Increases leverage by borrowing more debt and swapping to collateral.

**Required Environment Variables:**

- `STRATEGY_ADDRESS` - Strategy contract address
- `KEEPER_PVT_KEY` - Keeper role private key

**Optional Environment Variables:**

- `USE_FLASH_LOAN` - Set to `false` to supply debt tokens directly (default: `true`)
- `EXACT_OUT_AVAILABLE` - Set to `true` to use Paraswap (default: `false`, uses Kyberswap)

**Usage:**

```bash
# With flash loan (recommended)
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
forge script script/common/operations/RebalanceLeverageUp.s.sol \
    --rpc-url $RPC_URL \
    --broadcast

# Without flash loan (keeper must have debt tokens)
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
USE_FLASH_LOAN=false \
forge script script/common/operations/RebalanceLeverageUp.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

---

### 6. Rebalance Leverage Down

Decreases leverage by selling collateral to repay debt.

**Required Environment Variables:**

- `STRATEGY_ADDRESS` - Strategy contract address
- `KEEPER_PVT_KEY` - Keeper role private key

**Optional Environment Variables:**

- `NEW_TARGET_LTV` - Update target LTV before deleveraging (in basis points)
- `MANAGEMENT_PVT_KEY` - Required if `NEW_TARGET_LTV` is set
- `USE_FLASH_LOAN` - Set to `false` to supply debt tokens directly (default: `true`)
- `EXACT_OUT_AVAILABLE` - Set to `true` to use Paraswap exactOut (default: `false`, uses Kyberswap)

**Usage:**

```bash
# Deleverage to current target LTV
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
forge script script/common/operations/RebalanceLeverageDown.s.sol \
    --rpc-url $RPC_URL \
    --broadcast

# Update target LTV and deleverage in one transaction
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
NEW_TARGET_LTV=5000 \
forge script script/common/operations/RebalanceLeverageDown.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

---

### 7. Flash Loan Provider Update

Updates the flash loan provider configuration for the strategy.

**Required Environment Variables:**

- `STRATEGY_ADDRESS` - Strategy contract address
- `PRIVATE_KEY` - Deployer/admin private key
- `FLASH_LOAN_PROVIDER` - Flash loan provider address
- `FLASH_LOAN_SOURCE` - Flash loan source type (0=ERC3156, 1=BALANCER)

**Optional Environment Variables:**

- `FLASH_LOAN_ENABLED` - Enable/disable flash loans (default: `true`)

**Usage:**

```bash
# Update to Silo USDC flash loan provider (ERC3156)
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
FLASH_LOAN_PROVIDER=0x90957Ad08D1EC15D4CCf5461444fFb0dC499EB2D \
FLASH_LOAN_SOURCE=0 \
forge script script/common/operations/FlashLoanProviderUpdate.s.sol \
    --rpc-url $RPC_URL \
    --broadcast

# Disable flash loans
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
FLASH_LOAN_PROVIDER=0x90957Ad08D1EC15D4CCf5461444fFb0dC499EB2D \
FLASH_LOAN_SOURCE=0 \
FLASH_LOAN_ENABLED=false \
forge script script/common/operations/FlashLoanProviderUpdate.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
```

---

## Debug Mode (Simulation)

To simulate any script without broadcasting:

```bash
STRATEGY_ADDRESS=0x... \
OTHER_ENV_VARS=... \
forge script script/common/operations/ScriptName.s.sol \
    --rpc-url $RPC_URL
```

## Custom Swap Provider

By default, all scripts use **Kyberswap** for swaps. To use **Paraswap** (when exactOut is needed), override in child contracts or set environment variables as documented above.

## Extending Functionality

To customize behavior for specific strategies, create a strategy-specific contract that extends the generic one:

```solidity
// script/euler/usdf-susdf-usdc-ethereum/customActions/CustomRebalance.s.sol
import { RebalanceLeverageUp } from "../../../common/operations/RebalanceLeverageUp.s.sol";

contract CustomRebalance is RebalanceLeverageUp {
  // Override virtual functions to customize behavior
  function _shouldUseParaswap(
    bool isLeverageUp
  ) internal view override returns (bool) {
    return true; // Always use Paraswap
  }
}
```

## Migration from Strategy-Specific Scripts

Old strategy-specific scripts (e.g., `script/euler/usdf-susdf-usdc-ethereum/customActions/*.s.sol`) can now be replaced with these generic scripts. Simply use the appropriate environment variables instead of hard-coded constants.

**Example Migration:**

**Before:**

```bash
forge script script/euler/usdf-susdf-usdc-ethereum/customActions/UpdateTargetLtv.s.sol \
    --rpc-url $RPC_URL --broadcast
```

**After:**

```bash
STRATEGY_ADDRESS=0x6b6341D8eF10adeB87f2aa193207F6053CD87C5E \
NEW_TARGET_LTV=8300 \
forge script script/common/operations/UpdateTargetLtv.s.sol \
    --rpc-url $RPC_URL --broadcast
```

## Notes

- All scripts use **FFI** to fetch swap data from external APIs (Kyberswap/Paraswap)
- Ensure `ffi = true` is set in `foundry.toml`
- Scripts automatically read token addresses, oracles, and periphery contracts from the strategy
- Logging is comprehensive and includes before/after state comparisons
- All amounts are logged with proper decimals and symbols for readability

## Support

For issues or questions, refer to the main strategy documentation or contact the Ceres development team.
