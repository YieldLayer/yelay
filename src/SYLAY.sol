// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "spool-staking-and-voting/VoSPOOL.sol";
import "src/interfaces/ISYLAY.sol";
import "src/libraries/ConversionLib.sol";

contract SYLAY is VoSPOOL, ISYLAY {
    /* ========== STATE VARIABLES ========== */

    /// @notice Reference to the original VoSPOOL contract used for migration.
    VoSPOOL public immutable voSPOOL;

    /// @notice Tracks the last global tranche index migrated from VoSPOOL.
    uint256 private _lastGlobalIndexVoSPOOLMigrated;

    /// @notice the last global tranche index from VoSPOOL to be migrated.
    uint256 private _lastGlobalIndexVoSPOOL;

    /* ========== EVENTS ========== */

    event GlobalTranchesMigrated(uint256 indexed lastGlobalIndexMigrated);
    event UserMigrated(address indexed user);
    event UserTransferred(address indexed from, address indexed to);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the SYLAY contract for staking YLAY tokens.
     * @param _spoolOwner The address of the contract owner.
     * @param _voSPOOL The address of the VoSPOOL contract for migration.
     */
    constructor(ISpoolOwner _spoolOwner, VoSPOOL _voSPOOL) 
    VoSPOOL(
        _spoolOwner,
        10 ** 13, // Trim size for YELAY
        52 * 4,   // Full power tranches count for YELAY
        "Yelay Staking Token",
        "sYLAY"
    ) {
        firstTrancheStartTime = _voSPOOL.firstTrancheStartTime();

        GlobalGradual memory voGlobalGradual = _voSPOOL.getNotUpdatedGlobalGradual();
        _globalGradual = GlobalGradual(
            0,
            ConversionLib.convertAmount(voGlobalGradual.totalMaturingAmount),
            ConversionLib.convertPower(voGlobalGradual.totalRawUnmaturedVotingPower),
            voGlobalGradual.lastUpdatedTrancheIndex
        );

        _lastGlobalIndexVoSPOOL = _voSPOOL.getLastFinishedTrancheIndex();
        voSPOOL = _voSPOOL;
    }

    /* ========== MIGRATION FUNCTIONS ========== */

    /**
     * @notice Migrates global tranches from VoSPOOL up to the specified end index.
     * @dev Converts the VoSPOOL tranche data into the format used by SYLAY.
     * @param endIndex The tranche index to which global tranches will be migrated.
     */
    function migrateGlobalTranches(uint256 endIndex) 
        external 
        onlyGradualMinter 
        migrationInProgress 
    {
        if (_globalMigrationComplete()) return;

        for (uint i = _lastGlobalIndexVoSPOOLMigrated; i < endIndex; i++) {
            (Tranche memory zero, Tranche memory one, Tranche memory two, Tranche memory three, Tranche memory four) = voSPOOL.indexedGlobalTranches(i);
            (uint48 a, uint48 b, uint48 c, uint48 d, uint48 e) = ConversionLib.convertAmount(zero.amount, one.amount, two.amount, three.amount, four.amount);
            indexedGlobalTranches[i] = GlobalTranches(
                Tranche(a),
                Tranche(b),
                Tranche(c),
                Tranche(d),
                Tranche(e)
            );
        }

        _lastGlobalIndexVoSPOOLMigrated += endIndex * TRANCHES_PER_WORD;
        emit GlobalTranchesMigrated(_lastGlobalIndexVoSPOOLMigrated);
    }

    /**
     * @notice Migrates a user's gradual staking from VoSPOOL to SYLAY.
     * @dev Transfers user tranche data and power from VoSPOOL to SYLAY.
     * @param user The address of the user being migrated.
     */
    function migrateUser(address user) 
        external 
        onlyGradualMinter 
        migrationInProgress 
    {
        UserGradual memory userGradual = voSPOOL.getNotUpdatedUserGradual(user);

        // Store user gradual information
        _userGraduals[user] = UserGradual(
            0,
            ConversionLib.convertAmount(userGradual.maturingAmount),
            ConversionLib.convertPower(userGradual.rawUnmaturedVotingPower),
            userGradual.oldestTranchePosition,
            userGradual.latestTranchePosition,
            userGradual.lastUpdatedTrancheIndex
        );

        // Migrate user's tranches
        uint256 fromIndex = userGradual.oldestTranchePosition.arrayIndex;
        if (fromIndex == 0) return;

        uint256 toIndex = userGradual.latestTranchePosition.arrayIndex;

        for (uint256 i = fromIndex; i <= toIndex; i++) {
            _updateUserTranches(user, i);
        }

        emit UserMigrated(user);
    }

    /* ========== TRANSFER FUNCTIONS ========== */

    /**
     * @notice Transfers user data (staking and graduals) from one address to another.
     * @param from The address of the user from whom data is being transferred.
     * @param to The address of the recipient user.
     */
    function transferUser(address from, address to) 
        external 
        onlyGradualMinter 
    {
        require(_userGraduals[from].lastUpdatedTrancheIndex != 0, "sYLAY::migrate: User does not exist");
        require(_userGraduals[to].lastUpdatedTrancheIndex == 0, "sYLAY::migrate: User already exists");

        UserGradual memory _userGradual = _userGraduals[from];

        // Migrate user tranches
        if (_hasTranches(_userGradual)) {
            uint256 fromIndex = _userGradual.oldestTranchePosition.arrayIndex;
            uint256 toIndex = _userGradual.latestTranchePosition.arrayIndex;

            for (uint256 i = fromIndex; i <= toIndex; i++) {
                userTranches[to][i] = userTranches[from][i];
                delete userTranches[from][i];
            }
        }

        // Migrate user gradual and instant power
        _userGraduals[to] = _userGraduals[from];
        delete _userGraduals[from];

        userInstantPower[to] = userInstantPower[from];
        delete userInstantPower[from];

        emit UserTransferred(from, to);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Internal function to update a user's tranches during migration.
     * @param user The address of the user.
     * @param index The tranche index to be updated.
     */
    function _updateUserTranches(address user, uint256 index) 
        private 
    {
        (UserTranche memory zero, UserTranche memory one, UserTranche memory two, UserTranche memory three) = voSPOOL.userTranches(user, index);
        (uint48 a, uint48 b, uint48 c, uint48 d) = ConversionLib.convertAmount(zero.amount, one.amount, two.amount, three.amount);
        userTranches[user][index] = UserTranches(
            UserTranche(a, zero.index),
            UserTranche(b, one.index),
            UserTranche(c, two.index),
            UserTranche(d, three.index)
        );
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Checks if the migration is complete for both global and user tranches.
     * @return True if the migration is complete, false otherwise.
     */
    function migrationComplete() 
        external 
        view 
        returns (bool) 
    {
        return !_migrationInProgressInternal() && _globalMigrationComplete();
    }

    /**
     * @notice Checks if the migration process is still ongoing.
     * @return True if the migration is still in progress, false otherwise.
     */
    function _migrationInProgressInternal() 
        private 
        view 
        returns (bool) 
    {
        return getLastFinishedTrancheIndex() == _lastGlobalIndexVoSPOOL;
    }

    /**
     * @notice Checks if the global migration has been completed.
     * @return True if global migration is complete, false otherwise.
     */
    function _globalMigrationComplete() 
        private 
        view 
        returns (bool) 
    {
        return (_lastGlobalIndexVoSPOOLMigrated >= _lastGlobalIndexVoSPOOL);
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Ensures that the migration process is in progress.
     */
    modifier migrationInProgress() {
        _migrationInProgress();
        _;
    }

    /**
     * @notice Checks if the migration is still in progress and reverts if it has ended.
     */
    function _migrationInProgress() 
        private 
        view 
    {
        require(_migrationInProgressInternal(), "SYLAY: migration period ended");
    }
}
