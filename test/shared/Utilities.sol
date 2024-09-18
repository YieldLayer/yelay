//// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

contract Utilities {
    uint256 public constant FULL_POWER_TRANCHES_COUNT = 52 * 4;
    uint256 public constant TRIM_SIZE = 10 ** 13;

    // Voting power calculations
    function getVotingPowerForTranchesPassed(uint256 amount, uint256 tranches) public pure returns (uint256) {
        if (tranches >= FULL_POWER_TRANCHES_COUNT) {
            return trim(amount) * TRIM_SIZE;
        }
        return (trim(amount) * TRIM_SIZE * tranches) / FULL_POWER_TRANCHES_COUNT;
    }

    function trim(uint256 amount) public pure returns (uint48) {
        return uint48(amount / TRIM_SIZE);
    }

    function getChainTimeInTwoDays() public view returns (uint256) {
        return block.timestamp + 2 days;
    }
}
