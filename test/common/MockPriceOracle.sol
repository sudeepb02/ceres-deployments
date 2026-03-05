pragma solidity 0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibError} from "ceres-strategies/src/libraries/LibError.sol";

import "forge-std/console2.sol";

/// @title MockPriceOracle
/// @notice Mock oracle for testing price changes
/// @dev Uses basis points for percentage changes: +500 = +5%, -500 = -5%
contract MockPriceOracle {
    uint256 public immutable BASE_TO_QUOTE_PRICE;
    uint256 public immutable QUOTE_TO_BASE_PRICE;

    address public immutable BASE_TOKEN;
    address public immutable QUOTE_TOKEN;

    // Immutable so that vm.mockFunction (which runs code in callee's storage context) reads the
    // correct value from bytecode rather than from the callee's storage slot.
    int256 public immutable PERCENTAGE_CHANGE_BPS;

    int256 private constant BPS_DENOMINATOR = 10000;

    error InvalidBaseOrQuote();

    constructor(uint256 baseToQuotePrice, uint256 quoteToBasePrice, address baseToken, address quoteToken, int256 percentageChangeBps) {
        // Quote to base price might be zero if the oracle does not support reverse pricing, e.g Euler ERC4626 oracles
        if (baseToQuotePrice == 0) revert LibError.InvalidPrice();
        if (baseToken == address(0) || quoteToken == address(0)) revert InvalidBaseOrQuote();

        BASE_TO_QUOTE_PRICE = baseToQuotePrice;
        QUOTE_TO_BASE_PRICE = quoteToBasePrice;
        BASE_TOKEN = baseToken;
        QUOTE_TOKEN = quoteToken;
        PERCENTAGE_CHANGE_BPS = percentageChangeBps;

        console2.log("MockPriceOracle initialized with BASE_TO_QUOTE_PRICE:", BASE_TO_QUOTE_PRICE);
        console2.log("MockPriceOracle initialized with QUOTE_TO_BASE_PRICE:", QUOTE_TO_BASE_PRICE);
        console2.log("MockPriceOracle initialized with PERCENTAGE_CHANGE_BPS:", PERCENTAGE_CHANGE_BPS);
    }

    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256 outAmount) {
        int256 price;

        // Validate token pair matches configured tokens
        if (base == BASE_TOKEN && quote == QUOTE_TOKEN) {
            price = int256(BASE_TO_QUOTE_PRICE);
        } else if (base == QUOTE_TOKEN && quote == BASE_TOKEN) {
            price = int256(QUOTE_TO_BASE_PRICE);
        } else {
            revert InvalidBaseOrQuote();
        }

        // Calculate adjusted price: basePrice * (10000 + percentChangeBps) / 10000
        // This handles both positive and negative percentage changes
        int256 adjustedPriceSigned = (price * (BPS_DENOMINATOR + PERCENTAGE_CHANGE_BPS)) / BPS_DENOMINATOR;

        // Safety check
        require(adjustedPriceSigned > 0, "MockPriceOracle: adjusted price must be > 0");

        uint256 tokenPrice = uint256(adjustedPriceSigned);

        if (tokenPrice == 0) {
            revert LibError.InvalidPrice();
        }

        outAmount = (inAmount * tokenPrice) / (10 ** IERC20Metadata(base).decimals());
    }
}
