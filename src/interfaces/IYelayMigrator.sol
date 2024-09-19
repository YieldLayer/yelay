// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IYelayMigrator {
    /**
     * @notice Updates the blocklist status of a user.
     * @param users The addresses of the users to be updated.
     * @param sets A boolean indicating whether to add (true) or remove (false) the user from the blocklist.
     */
    function updateBlocklist(address[] calldata users, bool[] calldata sets) external;

    /**
     * @notice Migrate SPOOL tokens to YLAY tokens with rounding mechanics.
     * @dev This function checks if the claimants are blocklisted or have already migrated.
     *      It then calculates the YLAY amount using the conversion rate and rounding mechanics,
     *      marks the claimant as migrated, emits a TokensMigrated event, and calls the claim function on the YLAY token.
     * @param claimants An array of addresses of the claimants.
     */
    function migrateBalance(address[] calldata claimants) external;

    /**
     * @notice Migrate SPOOL staked to YLAY staking.
     * @param stakers An array of addresses of the stakers.
     */
    function migrateStake(address[] calldata stakers) external;
}
