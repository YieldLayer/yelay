// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";

library ConversionLib {
    // 1_000_000_000 (yelaySupply) * 10 ** 18 / 140_000_000 (spoolSupply because 70_000_000 were sent to 0xdead address) with 18 decimals of precision
    uint256 public constant CONVERSION_RATE = 7142857142857142857;
    uint256 private constant TRIM_SIZE_VOSPOOL = 10 ** 12;
    uint256 private constant TRIM_SIZE_YELAY = 10 ** 13;

    /**
     * @notice Helper function to convert SPOOL amount to YLAY amount with rounding mechanics.
     * @dev Implements RoundingMode.HALF_DOWN. If the value is exactly halfway, it rounds down.
     * @param spoolAmount The amount of SPOOL tokens to be converted.
     * @return The equivalent amount of YLAY tokens after conversion and rounding.
     */
    function convert(uint256 spoolAmount) internal pure returns (uint256) {
        if (spoolAmount == 0) {
            return 0;
        }
        return _applyConversion(spoolAmount);
    }

    function convertAmount(uint48 _a, uint48 _b, uint48 _c, uint48 _d)
        internal
        pure
        returns (uint48 a, uint48 b, uint48 c, uint48 d)
    {
        a = uint48(_convertTrimmed(_a));
        b = uint48(_convertTrimmed(_b));
        c = uint48(_convertTrimmed(_c));
        d = uint48(_convertTrimmed(_d));
    }

    function convertAmount(uint48 _a, uint48 _b, uint48 _c, uint48 _d, uint48 _e)
        internal
        pure
        returns (uint48 a, uint48 b, uint48 c, uint48 d, uint48 e)
    {
        a = uint48(_convertTrimmed(_a));
        b = uint48(_convertTrimmed(_b));
        c = uint48(_convertTrimmed(_c));
        d = uint48(_convertTrimmed(_d));
        e = uint48(_convertTrimmed(_e));
    }

    /**
     * @notice Converts the trimmed amount into an equivalent amount based on the conversion rate for amount.
     * @param trimmedAmount The trimmed amount to be converted.
     * @return The converted amount after untrimming and applying the conversion rate.
     */
    function convertAmount(uint48 trimmedAmount) internal pure returns (uint48) {
        return uint48(_convertTrimmed(trimmedAmount));
    }

    /**
     * @notice Converts the trimmed power into an equivalent amount based on the conversion rate.
     * @param trimmedPower The trimmed power to be converted.
     * @return The converted power after untrimming and applying the conversion rate.
     */
    function convertPower(uint56 trimmedPower) internal pure returns (uint56) {
        return _convertTrimmed(trimmedPower);
    }

    /**
     * @notice Converts the trimmed into an equivalent amount based on the conversion rate.
     * @param trimmed The trimmed amount to be converted.
     * @return The converted power after untrimming, applying the conversion rate, and retrimming.
     */
    function _convertTrimmed(uint56 trimmed) internal pure returns (uint56) {
        if (trimmed == 0) {
            return 0;
        }
        // Untrim the amount based on the VoSPOOL trim size
        uint256 untrimmed = _untrim(trimmed, TRIM_SIZE_VOSPOOL);

        // scale the amount by the conversion rate
        uint256 untrimmedConverted = _applyConversion(untrimmed);

        // retrim the amount based on the YLAY trim size
        return _trim(untrimmedConverted, TRIM_SIZE_YELAY);
    }

    function _untrim(uint256 trimmedAmount, uint256 trimSize) private pure returns (uint256 untrimmedAmount) {
        unchecked {
            untrimmedAmount = trimmedAmount * trimSize;
        }
    }

    function _trim(uint256 untrimmedAmount, uint256 trimSize) private pure returns (uint56 trimmedAmount) {
        unchecked {
            trimmedAmount = uint56(untrimmedAmount / trimSize);
        }

        // Check if we need to adjust the converted value due to rounding
        uint256 raw = trimmedAmount * trimSize;
        if (raw < untrimmedAmount) {
            unchecked {
                trimmedAmount++;
            }
        }
    }

    /**
     * @dev Shared logic to apply conversion and rounding mechanics.
     * @param amount The amount to be converted.
     * @return The converted amount after applying the rate and rounding.
     */
    function _applyConversion(uint256 amount) private pure returns (uint256) {
        // Multiply by the conversion rate
        uint256 multiplied = amount * CONVERSION_RATE;

        // Apply rounding: (value + half) / 1e18. If exactly halfway, rounds down.
        uint256 half = 1e18 / 2;
        if (multiplied % 1e18 > half) {
            return (multiplied + half) / 1e18;
        } else {
            return multiplied / 1e18;
        }
    }
}
