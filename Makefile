.PHONY: test-avusd test-usds test-usdf size test

size:
	forge build --sizes

test:
	forge test

test-avusd:
	forge test --match-path "test/euler/avusd-savusd-usdc-avalanche/*.sol"

test-usds:
	forge test --match-path "test/euler/usds-susds-usdt-strategy/*.sol"

# USDF-sUSDF-USDC strategy ethereum tests

test-usdf-all:
	forge test --match-path "test/euler/usdf-susdf-usdc-ethereum/*.sol" --ffi

test-usdf-admin:
	forge test --match-path "test/euler/usdf-susdf-usdc-ethereum/*.sol" --ffi --mt Admin

test-usdf-fuzz:
	forge test --match-path "test/euler/usdf-susdf-usdc-ethereum/*.sol" --mt Fuzz --ffi

test-usdf-pnl:
	forge test --match-path "test/euler/usdf-susdf-usdc-ethereum/*.sol" --ffi --mt Pnl

test-usdf-rebalance:
	forge test --match-path "test/euler/usdf-susdf-usdc-ethereum/*.sol" --ffi --mt Rebalance

test-usdf-basic:
	forge test --match-path "test/euler/usdf-susdf-usdc-ethereum/*.sol" --ffi --mt Basic

# WETH-agETH-WETH strategy ethereum tests

test-ageth-all:
	forge test --match-path "test/silo/weth-ageth-weth-ethereum/*.sol" --ffi

test-ageth-admin:
	forge test --match-path "test/silo/weth-ageth-weth-ethereum/*.sol" --ffi --mt Admin

test-ageth-fuzz:
	forge test --match-path "test/silo/weth-ageth-weth-ethereum/*.sol" --mt Fuzz --ffi

test-ageth-pnl:
	forge test --match-path "test/silo/weth-ageth-weth-ethereum/*.sol" --ffi --mt Pnl

test-ageth-rebalance:
	forge test --match-path "test/silo/weth-ageth-weth-ethereum/*.sol" --ffi --mt Rebalance

test-ageth-basic:
	forge test --match-path "test/silo/weth-ageth-weth-ethereum/*.sol" --ffi --mt Basic