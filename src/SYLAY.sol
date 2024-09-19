// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./sYLAYBase.sol";
import "./libraries/ConversionLib.sol";

import "./interfaces/IsYLAY.sol";
import "./interfaces/IYelayOwner.sol";

contract sYLAY is sYLAYBase, IsYLAY {
    /// @dev Reference to the original VoSPOOL contract used for migration.
    // to avoid type conflicts we are using sYLAYBase type
    sYLAYBase public immutable voSPOOL;

    /// @dev migrator address
    address public immutable migrator;

    /// @custom:storage-location erc7201:yelay.storage.sYLAYMigrationStorage
    struct sYLAYMigrationStorage {
        /// @dev Tracks the last global tranche index migrated from VoSPOOL.
        uint256 lastGlobalIndexVoSPOOLMigrated;
        /// @dev the last global tranche index from VoSPOOL to be migrated.
        uint256 lastGlobalIndexVoSPOOL;
        /// @notice The total amount of instant power migrated
        uint256 totalInstantPowerMigrated;
        /// @notice The total amount of instant power to migrate
        uint256 totalInstantPowerToMigrate;
        /// @notice The total maturing amount migrated
        uint256 totalMaturingAmountMigrated;
        /// @notice The total maturing amount to migrate
        uint256 totalMaturingAmountToMigrate;
        /// @dev flag to allow migration
        bool initialized;
    }

    // keccak256(abi.encode(uint256(keccak256("yelay.storage.sYLAYMigrationStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant sYLAYMigrationStorageLocation =
        0xddee74f4743e1a8cba1606768246b9b579e6a45986d386fa68f075c332fe5000;

    function _getsYLAYMigrationStorageLocation() private pure returns (sYLAYMigrationStorage storage $) {
        assembly {
            $.slot := sYLAYMigrationStorageLocation
        }
    }

    /* ========== EVENTS ========== */

    event GlobalTranchesMigrated(uint256 indexed lastGlobalIndexMigrated);
    event UserMigrated(address indexed user);
    event UserTransferred(address indexed from, address indexed to);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the sYLAY contract for staking YLAY tokens.
     * @param _yelayOwner The address of the contract owner.
     * @param _voSPOOL The address of the VoSPOOL contract for migration.
     */
    constructor(address _yelayOwner, address _voSPOOL, address _migrator) sYLAYBase(IYelayOwner(_yelayOwner)) {
        voSPOOL = sYLAYBase(_voSPOOL);
        migrator = _migrator;
    }

    function migrateInitial() external onlyMigrator {
        firstTrancheStartTime = voSPOOL.firstTrancheStartTime();

        GlobalGradual memory voGlobalGradual = voSPOOL.getNotUpdatedGlobalGradual();
        _globalGradual = GlobalGradual(
            ConversionLib.convertAmount(voGlobalGradual.totalMaturedVotingPower),
            ConversionLib.convertAmount(voGlobalGradual.totalMaturingAmount),
            ConversionLib.convertPower(voGlobalGradual.totalRawUnmaturedVotingPower),
            voGlobalGradual.lastUpdatedTrancheIndex
        );

        totalInstantPower = ConversionLib.convert(voSPOOL.totalInstantPower());

        sYLAYMigrationStorage storage $ = _getsYLAYMigrationStorageLocation();
        $.lastGlobalIndexVoSPOOL = voSPOOL.getLastFinishedTrancheIndex();
        $.totalInstantPowerToMigrate = voSPOOL.totalInstantPower();
        $.totalMaturingAmountToMigrate = voGlobalGradual.totalMaturingAmount;
        $.initialized = true;
    }

    /* ========== MIGRATION FUNCTIONS ========== */

    /**
     * @notice Migrates global tranches from VoSPOOL up to the specified end index.
     * @dev Converts the VoSPOOL tranche data into the format used by SYLAY.
     * @param endIndex The tranche index to which global tranches will be migrated.
     */
    function migrateGlobalTranches(uint256 endIndex) external migrationInProgress onlyMigrator {
        sYLAYMigrationStorage storage $ = _getsYLAYMigrationStorageLocation();
        _whenInitialized($);
        if (_globalMigrationComplete()) return;

        for (uint256 i = $.lastGlobalIndexVoSPOOLMigrated; i < endIndex; i++) {
            (Tranche memory zero, Tranche memory one, Tranche memory two, Tranche memory three, Tranche memory four) =
                voSPOOL.indexedGlobalTranches(i);
            (uint48 a, uint48 b, uint48 c, uint48 d, uint48 e) =
                ConversionLib.convertAmount(zero.amount, one.amount, two.amount, three.amount, four.amount);
            indexedGlobalTranches[i] = GlobalTranches(Tranche(a), Tranche(b), Tranche(c), Tranche(d), Tranche(e));
        }

        $.lastGlobalIndexVoSPOOLMigrated += endIndex * TRANCHES_PER_WORD;
        emit GlobalTranchesMigrated($.lastGlobalIndexVoSPOOLMigrated);
    }

    /**
     * @notice Migrates a user's gradual staking from VoSPOOL to SYLAY.
     * @dev Transfers user tranche data and power from VoSPOOL to SYLAY.
     * @param user The address of the user being migrated.
     */
    function migrateUser(address user) external migrationInProgress onlyMigrator {
        sYLAYMigrationStorage storage $ = _getsYLAYMigrationStorageLocation();
        _whenInitialized($);
        uint256 userPower = voSPOOL.userInstantPower(user);
        userInstantPower[user] = ConversionLib.convert(userPower);
        UserGradual memory userGradual = voSPOOL.getNotUpdatedUserGradual(user);

        // Store user gradual information
        _userGraduals[user] = UserGradual(
            ConversionLib.convertAmount(userGradual.maturedVotingPower),
            ConversionLib.convertAmount(userGradual.maturingAmount),
            ConversionLib.convertPower(userGradual.rawUnmaturedVotingPower),
            userGradual.oldestTranchePosition,
            userGradual.latestTranchePosition,
            userGradual.lastUpdatedTrancheIndex
        );

        unchecked {
            $.totalInstantPowerMigrated += userPower;
            $.totalMaturingAmountMigrated += userGradual.maturingAmount;
        }

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
    function transferUser(address from, address to) external onlyGradualMinter {
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
    function _updateUserTranches(address user, uint256 index) private {
        (UserTranche memory zero, UserTranche memory one, UserTranche memory two, UserTranche memory three) =
            voSPOOL.userTranches(user, index);
        (uint48 a, uint48 b, uint48 c, uint48 d) =
            ConversionLib.convertAmount(zero.amount, one.amount, two.amount, three.amount);
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
    function migrationComplete() external view returns (bool) {
        return !_migrationInProgressInternal() && _globalMigrationComplete();
    }

    /**
     * @notice Checks if the migration process is still ongoing.
     * @return True if the migration is still in progress, false otherwise.
     */
    function _migrationInProgressInternal() private view returns (bool) {
        sYLAYMigrationStorage storage $ = _getsYLAYMigrationStorageLocation();
        return $.totalInstantPowerMigrated != $.totalInstantPowerToMigrate
            || $.totalMaturingAmountMigrated != $.totalMaturingAmountToMigrate;
    }

    /**
     * @notice Checks if the global migration has been completed.
     * @return True if global migration is complete, false otherwise.
     */
    function _globalMigrationComplete() private view returns (bool) {
        sYLAYMigrationStorage storage $ = _getsYLAYMigrationStorageLocation();
        return ($.lastGlobalIndexVoSPOOLMigrated >= $.lastGlobalIndexVoSPOOL);
    }

    function _whenInitialized(sYLAYMigrationStorage storage $) private view {
        require($.initialized, "sYLAY: Not initialized");
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Ensures that the migration process is in progress.
     */
    modifier migrationInProgress() {
        require(_migrationInProgressInternal(), "SYLAY: migration period ended");
        _;
    }

    /**
     * @notice Ensures that the function can only be called by the migrator.
     */
    modifier onlyMigrator() {
        require(msg.sender == migrator, "sYLAY: caller not migrator");
        _;
    }
}
