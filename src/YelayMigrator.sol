// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./YelayOwnable.sol";
import "./libraries/ConversionLib.sol";

import "./interfaces/IERC20PausableOwnable.sol";
import "./interfaces/migration/IsYLAY.sol";
import "./interfaces/IYelayMigrator.sol";
import "./interfaces/migration/IYelayStaking.sol";
import "./interfaces/IYLAY.sol";

contract YelayMigrator is YelayOwnable, IYelayMigrator {
    /* ========== STATE VARIABLES ========== */

    /// @notice Pausable and ownable ERC20 interface for the SPOOL token.
    IERC20PausableOwnable public immutable SPOOL;

    /// @notice Interface for YLAY token.
    IYLAY public immutable YLAY;

    /// @notice Immutable interface for Yelay staking contract.
    IYelayStaking public immutable yelayStaking;

    /// @notice Immutable interface for sYLAY (staked YLAY).
    IsYLAY public immutable sYLAY;

    /// @notice Mapping to track addresses that are blocklisted from migration.
    mapping(address => bool) public blocklist;

    /// @notice Mapping to track addresses that have migrated their token balance.
    mapping(address => bool) public migratedBalance;

    /// @notice Mapping to track addresses that have migrated their stake.
    mapping(address => bool) public migratedStake;

    /* ========== EVENTS ========== */

    /// @notice Event emitted when a balance is migrated.
    event BalanceMigrated(address indexed claimant, uint256 spoolAmount, uint256 ylayAmount);

    /// @notice Event emitted when a stake is migrated.
    event StakeMigrated(address indexed claimant, uint256 ylayAmount, uint256 ylayRewards);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor to initialize the YelayMigrator contract.
     * @param _yelayOwner The address of the owner for SpoolOwnable.
     * @param _YLAY The address of the YLAY token contract.
     * @param _sYLAY The address of the sYLAY (staked YLAY) contract.
     * @param _yelayStaking The address of the Yelay staking contract.
     * @param _SPOOL The address of the SPOOL token contract.
     */
    constructor(address _yelayOwner, IYLAY _YLAY, IsYLAY _sYLAY, address _yelayStaking, address _SPOOL)
        YelayOwnable(IYelayOwner(_yelayOwner))
    {
        YLAY = _YLAY;
        sYLAY = _sYLAY;
        yelayStaking = IYelayStaking(_yelayStaking);
        SPOOL = IERC20PausableOwnable(_SPOOL);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Updates the blocklist status of users.
     * @param users The addresses of the users to be updated.
     * @param sets A boolean indicating whether to add (true) or remove (false) users from the blocklist.
     */
    function updateBlocklist(address[] calldata users, bool[] calldata sets) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            blocklist[users[i]] = sets[i];
        }
    }

    /**
     * @notice Migrate initial state on sYLAY
     */
    function migrateInitial() external onlyOwner spoolPaused {
        sYLAY.migrateInitial();
    }

    /**
     * @notice Migrate global tranches for sYLAY up to the given endIndex.
     * @param endIndex The index up to which tranches should be migrated.
     */
    function migrateGlobalTranches(uint256 endIndex) external onlyOwner spoolPaused {
        sYLAY.migrateGlobalTranches(endIndex);
    }

    /**
     * @notice Migrate the SPOOL token balance of claimants to YLAY tokens.
     * @dev This function checks if the claimants are blocklisted or have already migrated.
     * It calculates the YLAY amount using conversion and marks the claimant as migrated.
     * @param claimants An array of addresses of the claimants whose balances will be migrated.
     */
    function migrateBalance(address[] calldata claimants) external onlyOwner spoolPaused {
        for (uint256 i = 0; i < claimants.length; i++) {
            _migrateBalance(claimants[i]);
        }
    }

    /**
     * @notice Allows individual claimants to migrate their own SPOOL balance to YLAY.
     */
    function migrateBalance() external spoolPaused {
        _migrateBalance(msg.sender);
    }

    /**
     * @notice Migrate the staked SPOOL to Yelay staking for multiple users.
     * @param claimants An array of addresses of the users whose staked balances will be migrated.
     */
    function migrateStake(address[] calldata claimants) external onlyOwner spoolPaused {
        uint256 yelayToStake;
        for (uint256 i = 0; i < claimants.length; i++) {
            yelayToStake += _migrateStake(claimants[i]);
        }

        // Transfer the cumulative staking balance to the yelayStaking contract
        YLAY.claim(address(yelayStaking), yelayToStake);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Internal function to handle stake migration for a given user.
     * @param staker The address of the staker.
     * @return yelayToStake The total YLAY amount to be staked after migration.
     */
    function _migrateStake(address staker) private returns (uint256) {
        require(!migratedStake[staker], "YelayMigrator:_migrateStake: Staker already migrated");
        migratedStake[staker] = true;

        (uint256 yelayStaked, uint256 yelayRewards) = yelayStaking.migrateUser(staker);

        if (yelayRewards > 0) {
            // Send claimed rewards directly to the user
            YLAY.claim(staker, yelayRewards);
        }

        sYLAY.migrateUser(staker);

        emit StakeMigrated(staker, yelayStaked, yelayRewards);

        return yelayStaked;
    }

    /**
     * @notice Internal function to handle balance migration for a given user.
     * @param claimant The address of the claimant.
     */
    function _migrateBalance(address claimant) private {
        require(!blocklist[claimant], "YelayMigrator:_migrateBalance: User is blocklisted");
        require(!migratedBalance[claimant], "YelayMigrator:migrateBalance: User already migrated");
        migratedBalance[claimant] = true;

        uint256 spoolBalance = SPOOL.balanceOf(claimant);
        uint256 ylayAmount = ConversionLib.convert(spoolBalance);

        YLAY.claim(claimant, ylayAmount);

        emit BalanceMigrated(claimant, spoolBalance, ylayAmount);
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Modifier to ensure that the SPOOL contract is paused
     */
    modifier spoolPaused() {
        require(SPOOL.paused(), "YelayMigrator:spoolPaused: SPOOL is enabled");
        _;
    }
}
