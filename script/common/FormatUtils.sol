// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/src/console2.sol";
import {Vm} from "forge-std/src/Vm.sol";

/// @title FormatUtils
/// @notice Simple helper library to format numbers with decimals for console logging
/// @dev Prevents precision loss while displaying numbers in human-readable format
library FormatUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Logs with default 4 digit precision
    /// @param label The label to display
    /// @param value The raw value (e.g., in wei or smallest token unit)
    /// @param decimals The number of decimal places (e.g., 18 for ETH, 6 for USDC)
    function log(string memory label, uint256 value, uint8 decimals) internal view {
        log(label, value, decimals, 4);
    }

    /// @notice Logs with custom precision
    /// @param label The label to display
    /// @param value The raw value (e.g., in wei or smallest token unit)
    /// @param decimals The number of decimal places (e.g., 18 for ETH, 6 for USDC)
    /// @param displayPrecision Number of decimal digits to display
    function log(string memory label, uint256 value, uint8 decimals, uint8 displayPrecision) internal view {
        uint256 divisor = 10 ** decimals;
        uint256 integerPart = value / divisor;
        uint256 fractionalPart = value % divisor;

        console2.log(
            string(
                abi.encodePacked(
                    label,
                    " ",
                    vm.toString(integerPart),
                    ".",
                    _limitPrecision(vm.toString(fractionalPart), decimals, displayPrecision)
                )
            )
        );
    }

    /// @notice Logs with a token symbol (default 4 digit precision)
    /// @param label The label to display
    /// @param value The raw value to format
    /// @param decimals The number of decimal places
    /// @param symbol The token symbol (e.g., "ETH", "USDC")
    function logWithSymbol(string memory label, uint256 value, uint8 decimals, string memory symbol) internal view {
        logWithSymbol(label, value, decimals, symbol, 4);
    }

    /// @notice Logs with a token symbol and custom precision
    /// @param label The label to display
    /// @param value The raw value to format
    /// @param decimals The number of decimal places
    /// @param symbol The token symbol (e.g., "ETH", "USDC")
    /// @param displayPrecision Number of decimal digits to display
    function logWithSymbol(
        string memory label,
        uint256 value,
        uint8 decimals,
        string memory symbol,
        uint8 displayPrecision
    ) internal view {
        uint256 divisor = 10 ** decimals;
        uint256 integerPart = value / divisor;
        uint256 fractionalPart = value % divisor;

        console2.log(
            string(
                abi.encodePacked(
                    label,
                    " ",
                    vm.toString(integerPart),
                    ".",
                    _limitPrecision(vm.toString(fractionalPart), decimals, displayPrecision),
                    " ",
                    symbol
                )
            )
        );
    }

    /// @notice Logs a percentage value in basis points
    /// @param label The label to display
    /// @param bps The value in basis points (e.g., 7500 = 75%)
    function logBps(string memory label, uint256 bps) internal view {
        uint256 percentage = bps / 100;
        uint256 fractional = bps % 100;

        console2.log(
            string(
                abi.encodePacked(label, " ", vm.toString(percentage), ".", _padLeft(vm.toString(fractional), 2), "%")
            )
        );
    }

    /// @notice Pads a string with leading zeros to reach target length
    /// @param str The string to pad
    /// @param targetLength The desired length
    /// @return Padded string
    function _padLeft(string memory str, uint256 targetLength) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= targetLength) return str;

        bytes memory result = new bytes(targetLength);
        uint256 padding = targetLength - strBytes.length;

        for (uint256 i = 0; i < padding; i++) {
            result[i] = "0";
        }
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[padding + i] = strBytes[i];
        }

        return string(result);
    }

    /// @notice Pads fractional part and limits to display precision
    /// @param fractionalStr The fractional part as string
    /// @param totalDecimals Total decimal places in the value
    /// @param displayPrecision Number of digits to display
    /// @return Formatted fractional part
    function _limitPrecision(
        string memory fractionalStr,
        uint256 totalDecimals,
        uint256 displayPrecision
    ) private pure returns (string memory) {
        // First pad to full length
        string memory padded = _padLeft(fractionalStr, totalDecimals);
        bytes memory paddedBytes = bytes(padded);

        // Then limit to display precision
        if (displayPrecision >= paddedBytes.length) {
            return padded;
        }

        bytes memory result = new bytes(displayPrecision);
        for (uint256 i = 0; i < displayPrecision; i++) {
            result[i] = paddedBytes[i];
        }

        return string(result);
    }
}
