// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

// import "src/external/spool-staking-and-voting/SpoolStaking.sol";
import "src/interfaces/IsYLAY.sol";
import "src/libraries/ConversionLib.sol";

import "forge-std/console.sol";

import {SpoolStaking2, IERC20, RewardConfiguration} from "./upgrade/SpoolStaking2.sol";

contract YelayStaking is SpoolStaking2 {
    /* ========== STATE VARIABLES ========== */

    /// @notice The interface for staked YLAY (sYLAY) tokens.
    IsYLAY public immutable sYLAY;

    /// @notice The SpoolStaking contract, used for migration purposes.
    SpoolStaking2 public immutable spoolStaking;

    /// @notice The total amount of SPOOL tokens that have been migrated to YLAY staking.
    uint256 private _totalStakedSPOOLMigrated;

    /// @notice The ERC20 interface for the SPOOL token used for spool staking.
    IERC20 public immutable SPOOL;

    /// @notice The address of the migrator contract responsible for migration.
    address public immutable migrator;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor to initialize the YelayStaking contract.
     * @param _spoolOwner The address of the owner for the SpoolOwnable contract.
     * @param _YLAY The address of the YLAY token.
     * @param _sYLAY The address of the sYLAY (staked YLAY) contract.
     * @param _rewardDistributor The address of the reward distributor contract.
     * @param _spoolStaking The address of the SpoolStaking contract.
     * @param _migrator The address of the contract responsible for migration.
     */
    constructor(
        address _spoolOwner,
        address _YLAY,
        address _sYLAY,
        address _sYLAYRewards,
        address _rewardDistributor,
        address _spoolStaking,
        address _migrator
    ) SpoolStaking2(_YLAY, _sYLAY, _sYLAYRewards, _rewardDistributor, _spoolOwner) {
        sYLAY = IsYLAY(_sYLAY);
        spoolStaking = SpoolStaking2(_spoolStaking);
        SPOOL = spoolStaking.stakingToken();
        migrator = _migrator;
    }

    /* ========== MIGRATION FUNCTIONS ========== */

    /**
     * @notice Migrates a user's staked SPOOL to YLAY.
     * @dev This function can only be called by the migrator contract.
     * It converts the user's SPOOL staked amount to YLAY and handles rewards migration.
     * @param user The address of the user whose staked balance is being migrated.
     * @return yelayStaked The amount of YLAY tokens staked after migration.
     * @return yelayRewards The amount of YLAY rewards migrated from SPOOL rewards.
     */
    function migrateUser(address user) external onlyMigrator returns (uint256 yelayStaked, uint256 yelayRewards) {
        uint256 spoolStaked = spoolStaking.balances(user);
        // console.log(spoolStaked);
        yelayStaked = ConversionLib.convert(spoolStaked);

        unchecked {
            _totalStakedSPOOLMigrated += spoolStaked;
        }

        _migrateUser(user, yelayStaked);

        // Handle staking rewards migration.
        // Note: voSPOOL rewards are not migrated. Upgrades to SpoolStaking/voSPOOLRewards are needed for full reward migration.
        uint256 userSpoolRewards = spoolStaking.earned(SPOOL, user);
        uint256 userVoSpoolRewards = spoolStaking.getUpdatedVoSpoolRewardAmount(user);
        // console.log("userSpoolRewards");
        // console.log(userSpoolRewards);
        // console.log("userVoSpoolRewards");
        // console.log(userVoSpoolRewards);
        yelayRewards = ConversionLib.convert(userSpoolRewards + userVoSpoolRewards);
    }

    /* ========== TRANSFER FUNCTIONS ========== */

    /**
     * @notice Transfers the staking balance and rewards of one user to another.
     * @dev This function is non-reentrant and updates rewards before transferring.
     * @param to The address of the recipient to whom the staking data is transferred.
     */
    function transferUser(address to) external nonReentrant updateRewards(msg.sender) {
        balances[to] = balances[msg.sender];
        canStakeFor[to] = canStakeFor[msg.sender];
        stakedBy[to] = stakedBy[msg.sender];

        delete balances[msg.sender];
        delete canStakeFor[msg.sender];
        delete stakedBy[msg.sender];

        uint256 rewardTokensCount = rewardTokens.length;
        for (uint256 i; i < rewardTokensCount; i++) {
            RewardConfiguration storage config = rewardConfiguration[rewardTokens[i]];

            config.rewards[to] = config.rewards[msg.sender];
            config.userRewardPerTokenPaid[to] = config.userRewardPerTokenPaid[msg.sender];

            delete config.rewards[msg.sender];
            delete config.userRewardPerTokenPaid[msg.sender];
        }

        sYLAY.transferUser(msg.sender, to);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Internal function to handle the migration of a user's staking balance.
     * @param account The address of the user whose balance is being migrated.
     * @param amount The amount of YLAY tokens being migrated.
     */
    function _migrateUser(address account, uint256 amount) private {
        unchecked {
            totalStaked = totalStaked += amount;
        }
        balances[account] = amount;

        emit Staked(account, amount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Checks if the migration process is complete.
     * @dev The migration is considered complete when all staked SPOOL tokens have been migrated to YLAY.
     * @return True if the migration is complete, false otherwise.
     */
    function migrationComplete() external view returns (bool) {
        return _totalStakedSPOOLMigrated == spoolStaking.totalStaked();
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Ensures that the function can only be called by the migrator.
     */
    modifier onlyMigrator() {
        require(msg.sender == migrator, "YelayStaking: caller not migrator");
        _;
    }
}
