// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./YelayOwnable.sol";
import "./interfaces/IsYLAY.sol";

/**
 * @title Staked YLAY Implementation
 *
 * @notice The staked YLAY pseudo-ERC20 Implementation
 *
 * An untransferable token implementation meant to be used by the
 * Yelay to mint the voting equivalent of the staked token.
 *
 * @dev
 * Users voting power consists of instant and gradual (maturing) voting power.
 * sYLAY contract assumes voting power comes from vesting or staking YLAY tokens.
 * As YLAY tokens have a maximum supply of 210,000,000 * 10**18, we consider this
 * limitation when storing data (e.g. storing amount divided by 10**12) to save on gas.
 *
 * Instant voting power can be used in the full amount as soon as minted.
 *
 * Gradual voting power:
 *      Matures linearly over 208 weeks (4 years) up to the minted amount.
 *      If a user burns gradual voting power, all accumulated voting power is
 *      reset to zero. In case there is some amount left, it'll take another 3
 *      years to achieve fully-matured power. Only gradual voting power is reset
 *      and not instant one.
 *      Gradual voting power updates at every new tranche, which lasts one week.
 *
 * Contract consists of:
 *      - CONSTANTS
 *      - STATE VARIABLES
 *      - CONSTRUCTOR
 *      - IERC20 FUNCTIONS
 *      - INSTANT POWER FUNCTIONS
 *      - GRADUAL POWER FUNCTIONS
 *          - GRADUAL POWER: VIEW FUNCTIONS
 *          - GRADUAL POWER: MINT FUNCTIONS
 *          - GRADUAL POWER: BURN FUNCTIONS
 *          - GRADUAL POWER: UPDATE GLOBAL FUNCTIONS
 *          - GRADUAL POWER: UPDATE USER FUNCTIONS
 *          - GRADUAL POWER: GLOBAL HELPER FUNCTIONS
 *          - GRADUAL POWER: USER HELPER FUNCTIONS
 *          - GRADUAL POWER: HELPER FUNCTIONS
 *      - OWNER FUNCTIONS
 *      - RESTRICTION FUNCTIONS
 *      - MODIFIERS
 */
contract sYLAY is YelayOwnable, IsYLAY, IERC20MetadataUpgradeable {
    /* ========== STRUCTS ========== */

    /**
     * @notice global tranche struct
     * @dev used so it can be passed through functions as a struct
     * @member amount amount minted in tranche
     */
    struct Tranche {
        uint48 amount;
    }

    /**
     * @notice global tranches struct holding 5 tranches
     * @dev made to pack multiple tranches in one word
     * @member zero tranche in pack at position 0
     * @member one tranche in pack at position 1
     * @member two tranche in pack at position 2
     * @member three tranche in pack at position 3
     * @member four tranche in pack at position 4
     */
    struct GlobalTranches {
        Tranche zero;
        Tranche one;
        Tranche two;
        Tranche three;
        Tranche four;
    }

    /**
     * @notice user tranche struct
     * @dev struct holds users minted amount at tranche at index
     * @member amount users amount minted at tranche
     * @member index tranche index
     */
    struct UserTranche {
        uint48 amount;
        uint16 index;
    }

    /**
     * @notice user tranches struct, holding 4 user tranches
     * @dev made to pack multiple tranches in one word
     * @member zero user tranche in pack at position 0
     * @member one user tranche in pack at position 1
     * @member two user tranche in pack at position 2
     * @member three user tranche in pack at position 3
     */
    struct UserTranches {
        UserTranche zero;
        UserTranche one;
        UserTranche two;
        UserTranche three;
    }

    /**
     * @notice user lockup struct
     * @dev struct holds users lockup staking power values
     * @member amount users amount locked
     * @member power users lockup power
     * @member start tranche index of lock start; either when migrated tranche was minted, or index of stake+lock
     * @member deadline tranche index of lock end. max 4 years from start.
     */
    struct UserLockup {
        uint48 amount;
        uint56 power;
        uint64 start;
        uint64 deadline;
    }

    /* ========== CONSTANTS ========== */

    /// @notice trim size value of the mint amount
    /// @dev we trim gradual mint amount by `TRIM_SIZE`, so it takes less storage
    uint256 internal constant TRIM_SIZE = 10 ** 13;
    /// @notice number of tranche amounts stored in one 256bit word
    uint256 internal constant TRANCHES_PER_WORD = 5;

    /// @notice duration of one tranche
    uint256 public constant TRANCHE_TIME = 1 weeks;
    /// @notice amount of tranches to mature to full power
    uint256 public constant FULL_POWER_TRANCHES_COUNT = 52 * 4;
    /// @notice time until gradual power is fully-matured
    /// @dev full power time is 208 weeks (approximately 4 years)
    uint256 public constant FULL_POWER_TIME = TRANCHE_TIME * FULL_POWER_TRANCHES_COUNT;

    /// @notice Token name full name
    string public constant name = "Staked Yelay";
    /// @notice Token symbol
    string public constant symbol = "sYLAY";
    /// @notice Token decimals
    uint8 public constant decimals = 18;

    /* ========== STATE VARIABLES ========== */

    /// @notice tranche time for index 1
    uint256 public firstTrancheStartTime;

    /// @notice mapping holding instant minting privileges for addresses
    mapping(address => bool) public minters;
    /// @notice mapping holding gradual minting privileges for addresses
    mapping(address => bool) public gradualMinters;

    /// @notice total instant voting power
    uint256 public totalInstantPower;
    /// @notice user instant voting power
    mapping(address => uint256) public userInstantPower;

    /// @notice global gradual power values
    GlobalGradual internal _globalGradual;
    /// @notice global tranches
    /// @dev mapping tranche index to a group of tranches (5 tranches per word)
    mapping(uint256 => GlobalTranches) public indexedGlobalTranches;

    /// @notice user gradual power values
    mapping(address => UserGradual) internal _userGraduals;
    /// @notice user tranches
    /// @dev mapping users to its tranches
    mapping(address => mapping(uint256 => UserTranches)) public userTranches;

    /// @notice total lockup power
    uint256 public totalLockupPower;

    /// @notice user lockup power
    mapping(address => uint256) public userLockupPower;

    /// @notice user lockup positions. address -> start tranche index -> lockup
    mapping(address => mapping(uint256 => UserLockup)) public userToTrancheIndexToLockup;

    /// @notice tightly packed lockup tranche indexes. 16 per word
    mapping(address => uint16[]) public userLockupIndexes;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Sets the value of _yelayOwner and first tranche end time
     * @dev With `_firstTrancheEndTime` you can set when the first tranche time
     * finishes and essentially users minted get the first foting power.
     * e.g. if we set it to Sunday 10pm and tranche time is 1 week,
     * all new tranches in the future will finish on Sunday 10pm and new
     * sYLAY power will mature and be accrued.
     *
     * Requirements:
     *
     * - first tranche time must be in the future
     * - first tranche time must must be less than full tranche time in the future
     *
     * @param _yelayOwner address
     */
    constructor(IYelayOwner _yelayOwner) YelayOwnable(_yelayOwner) {}

    /* ========== IERC20 FUNCTIONS ========== */

    /**
     * @notice Returns current total voting power
     */
    function totalSupply() external view override returns (uint256) {
        (GlobalGradual memory global,) = _getUpdatedGradual();
        return totalInstantPower + _getTotalGradualVotingPower(global) + _untrim(totalLockupPower);
    }

    /**
     * @notice Returns current user total voting power
     */
    function balanceOf(address account) external view override returns (uint256) {
        (UserGradual memory _userGradual,) = _getUpdatedGradualUser(account);

        return userInstantPower[account] + _getUserGradualVotingPower(_userGradual) + _untrim(userLockupPower[account]);
    }

    /**
     * @notice Returns current user lockups. easier access for integrations.
     */
    function userLockups(address account) external view returns (UserLockup[] memory lockups) {
        uint16[] memory userLockupIndexes_ = userLockupIndexes[account];
        lockups = new UserLockup[](userLockupIndexes_.length);
        for (uint256 i = 0; i < userLockupIndexes_.length; i++) {
            lockups[i] = userToTrancheIndexToLockup[account][userLockupIndexes_[i]];
        }
    }

    /**
     * @notice Returns current user tranches. easier access for integrations.
     */
    function updatedUserTranches(address account)
        external
        view
        returns (UserTranchePosition[] memory positions, UserTranche[] memory tranches)
    {
        (UserGradual memory _userGradual,) = _getUpdatedGradualUser(account);

        if (_hasTranches(_userGradual)) {
            UserTranchePosition memory position = _userGradual.oldestTranchePosition;
            uint256 totalTranches = _getTotalTranches(_userGradual);

            tranches = new UserTranche[](totalTranches);
            positions = new UserTranchePosition[](totalTranches);
            for (uint256 i; i < tranches.length; i++) {
                tranches[i] = _getUserTranche(account, position);
                positions[i] = position;

                position = _getNextUserTranchePosition(position);
            }
        }
    }

    /**
     * @dev Execution of function is prohibited to disallow token movement
     */
    function transfer(address, uint256) external pure override returns (bool) {
        revert("sYLAY::transfer: Prohibited Action");
    }

    /**
     * @dev Execution of function is prohibited to disallow token movement
     */
    function transferFrom(address, address, uint256) external pure override returns (bool) {
        revert("sYLAY::transferFrom: Prohibited Action");
    }

    /**
     * @dev Execution of function is prohibited to disallow token movement
     */
    function approve(address, uint256) external pure override returns (bool) {
        revert("sYLAY::approve: Prohibited Action");
    }

    /**
     * @dev Execution of function is prohibited to disallow token movement
     */
    function allowance(address, address) external pure override returns (uint256) {
        revert("sYLAY::allowance: Prohibited Action");
    }

    /* ========== INSTANT POWER FUNCTIONS ========== */

    /**
     * @notice Mints the provided amount as instant voting power.
     *
     * Requirements:
     *
     * - the caller must be the autorized
     *
     * @param to mint to user
     * @param amount mint amount
     */
    function mint(address to, uint256 amount) external onlyMinter {
        totalInstantPower += amount;
        unchecked {
            userInstantPower[to] += amount;
        }
        emit Minted(to, amount);
    }

    /**
     * @notice Burns the provided amount of instant power from the specified user.
     * @dev only instant power is removed, gradual power stays the same
     *
     * Requirements:
     *
     * - the caller must be the instant minter
     * - the user must posses at least the burning `amount` of instant voting power amount
     *
     * @param from burn from user
     * @param amount burn amount
     */
    function burn(address from, uint256 amount) external onlyMinter {
        require(userInstantPower[from] >= amount, "sYLAY:burn: User instant power balance too low");
        unchecked {
            userInstantPower[from] -= amount;
            totalInstantPower -= amount;
        }
        emit Burned(from, amount);
    }

    /* ========== GRADUAL POWER FUNCTIONS ========== */

    /* ---------- GRADUAL POWER: VIEW FUNCTIONS ---------- */

    /**
     * @notice returns updated total gradual voting power (fully-matured and maturing)
     *
     * @return totalGradualVotingPower total gradual voting power (fully-matured + maturing)
     */
    function getTotalGradualVotingPower() external view returns (uint256) {
        (GlobalGradual memory global,) = _getUpdatedGradual();
        return _getTotalGradualVotingPower(global);
    }

    /**
     * @notice returns updated global gradual struct
     *
     * @return global updated global gradual struct
     */
    function getGlobalGradual() external view returns (GlobalGradual memory) {
        (GlobalGradual memory global,) = _getUpdatedGradual();
        return global;
    }

    /**
     * @notice returns not updated global gradual struct
     *
     * @return global updated global gradual struct
     */
    function getNotUpdatedGlobalGradual() external view returns (GlobalGradual memory) {
        return _globalGradual;
    }

    /**
     * @notice returns updated user gradual voting power (fully-matured and maturing)
     *
     * @param user address holding voting power
     * @return userGradualVotingPower user gradual voting power (fully-matured + maturing)
     */
    function getUserGradualVotingPower(address user) external view returns (uint256) {
        (UserGradual memory _userGradual,) = _getUpdatedGradualUser(user);
        return _getUserGradualVotingPower(_userGradual);
    }

    /**
     * @notice returns updated user gradual struct
     *
     * @param user user address
     * @return _userGradual user updated gradual struct
     */
    function getUserGradual(address user) external view returns (UserGradual memory) {
        (UserGradual memory _userGradual,) = _getUpdatedGradualUser(user);
        return _userGradual;
    }

    /**
     * @notice returns not updated user gradual struct
     *
     * @param user user address
     * @return _userGradual user updated gradual struct
     */
    function getNotUpdatedUserGradual(address user) external view returns (UserGradual memory) {
        return _userGraduals[user];
    }

    /**
     * @notice Returns current active tranche index
     *
     * @return trancheIndex current tranche index
     */
    function getCurrentTrancheIndex() public view returns (uint16) {
        return _getTrancheIndex(block.timestamp);
    }

    /**
     * @notice Returns tranche index based on `time`
     * @dev `time` can be any time inside the tranche
     *
     * Requirements:
     *
     * - `time` must be equal to more than first tranche time
     *
     * @param time tranche time time to get the index for
     * @return trancheIndex tranche index at `time`
     */
    function getTrancheIndex(uint256 time) external view returns (uint256) {
        require(
            time >= firstTrancheStartTime,
            "sYLAY::getTrancheIndex: Time must be more or equal to the first tranche time"
        );

        return _getTrancheIndex(time);
    }

    /**
     * @notice Returns tranche index based at time
     *
     * @param time unix time
     * @return trancheIndex tranche index at `time`
     */
    function _getTrancheIndex(uint256 time) private view returns (uint16) {
        unchecked {
            return uint16(((time - firstTrancheStartTime) / TRANCHE_TIME) + 1);
        }
    }

    /**
     * @notice Returns next tranche end time
     *
     * @return trancheEndTime end time for next tranche
     */
    function getNextTrancheEndTime() external view returns (uint256) {
        return getTrancheEndTime(getCurrentTrancheIndex());
    }

    /**
     * @notice Returns tranche end time for tranche index
     *
     * @param trancheIndex tranche index
     * @return trancheEndTime end time for `trancheIndex`
     */
    function getTrancheEndTime(uint256 trancheIndex) public view returns (uint256) {
        return firstTrancheStartTime + trancheIndex * TRANCHE_TIME;
    }

    /**
     * @notice Returns last finished tranche index
     *
     * @return trancheIndex last finished tranche index
     */
    function getLastFinishedTrancheIndex() public view returns (uint16) {
        unchecked {
            return getCurrentTrancheIndex() - 1;
        }
    }

    /* ---------- LOCKUP POWER: FUNCTIONS ---------- */

    /**
     * @notice migrate user tranche to lockup
     * @dev user gradual power is reduced by the amount of the tranche and added to lockup system.
     * @param to user to migrate
     * @param userTranchePosition user tranche with amount
     * @param deadline tranche index of lock end
     */
    function migrateToLockup(address to, UserTranchePosition calldata userTranchePosition, uint256 deadline)
        external
        onlyGradualMinter
        updateGradual
        updateGradualUser(to)
        returns (uint256)
    {
        // get user tranche
        UserTranche storage tranche = _getUserTrancheStorage(to, userTranchePosition);

        // get global tranche
        Tranche storage globalTranche = _getTranche(tranche.index);

        // get amount and power earned for this tranche
        uint48 amount = tranche.amount;

        // ensure tranche has not already been locked
        require(amount > 0, "sYLAY::migrateToLockup: Tranche already locked");

        // ensure tranche has not matured
        uint16 lastMaturedIndex = _getLastMaturedIndex();
        require(lastMaturedIndex == 0 || tranche.index > lastMaturedIndex, "sYLAY::migrateToLockup: Tranche matured");

        uint56 rawUnmaturedVotingPower = uint56(amount * (getCurrentTrancheIndex() - tranche.index));

        // reduce user and global graduals
        _userGraduals[to].maturingAmount -= amount;
        _globalGradual.totalMaturingAmount -= amount;

        _userGraduals[to].rawUnmaturedVotingPower -= rawUnmaturedVotingPower;
        _globalGradual.totalRawUnmaturedVotingPower -= rawUnmaturedVotingPower;

        // reduce user and global tranches
        tranche.amount = 0;
        globalTranche.amount -= amount;

        _mintLockup(to, amount, tranche.index, deadline);

        emit TrancheMigration(to, amount, tranche.index, rawUnmaturedVotingPower);

        return _untrim(amount);
    }

    /*
     * @notice mint new lockup position
     * @dev mint new lockup position for user. This is new stake being introduced to the system.
     * @param to user to mint Lockup
     * @param amount amount to mint
     * @param deadline tranche index of lock end
     */
    function mintLockup(address to, uint256 amount, uint256 deadline) external onlyGradualMinter returns (uint256) {
        uint48 trimmedAmount = _trim(amount);
        _mintLockup(to, trimmedAmount, getCurrentTrancheIndex(), deadline);
        return _untrim(trimmedAmount);
    }

    function burnLockups(address to) external onlyGradualMinter returns (uint256 amount) {
        uint256 currentTrancheIndex = getCurrentTrancheIndex();
        uint16[] storage userLockupIndexes_ = userLockupIndexes[to];
        uint256 userLockupCount_ = userLockupIndexes_.length;
        for (uint256 i = 0; i < userLockupCount_;) {
            uint16 start = userLockupIndexes_[i];
            UserLockup memory userLockup = userToTrancheIndexToLockup[to][start];

            if (_validBurn(currentTrancheIndex, userLockup)) {
                amount += _burnLockup(userLockup, to, start);

                // modify the array: swap the current element with the last element and then delete it
                userLockupIndexes_[i] = userLockupIndexes_[userLockupCount_ - 1];
                userLockupIndexes_.pop();
                userLockupCount_--;
            } else {
                i++;
            }
        }

        return _untrim(amount);
    }

    function _burnLockup(UserLockup memory userLockup, address to, uint256 start) internal returns (uint256 amount) {
        // reduce global lockup powers
        unchecked {
            totalLockupPower -= userLockup.power;
            userLockupPower[to] -= userLockup.power;
        }

        amount = userLockup.amount;

        emit LockupBurned(to, start);

        // remove user position
        delete userToTrancheIndexToLockup[to][start];
    }

    function _validBurn(uint256 currentTrancheIndex, UserLockup memory userLockup) internal pure returns (bool) {
        // the lock should not be burned already, and the deadline of the lock should have passed
        return (userLockup.amount > 0 && currentTrancheIndex >= userLockup.deadline);
    }

    /**
     * @notice continue lockup position
     * @dev
     *  - continue lockup position for user. This is stake being prolonged in the system. Prolonging is allowed either during or after lock expiry.
     *  - unlike the other lockup functions, the user interacts with this function directly. There is no need to go through the gradual minter here.
     * @param start tranche index of the lockup
     * @param deadline tranche index of new lock end. Must be greater than the current deadline.
     */
    function continueLockup(uint256 start, uint256 deadline) external {
        UserLockup storage userLockup = userToTrancheIndexToLockup[msg.sender][start];
        // there should be lockup position to prolong
        require(userLockup.amount > 0, "sYLAY::continueLockup: No lockup position found");
        require(userLockup.deadline < deadline, "sYLAY::continueLockup: Lockup deadline should be in the future");

        // whole lockup period should not exceed 4 years
        require(
            (deadline - start) <= FULL_POWER_TRANCHES_COUNT,
            "sYLAY::continueLockup: Lockup period exceeds a total of 4 years"
        );

        // calculate added lockup power
        uint256 addedPower = userLockup.amount * (deadline - userLockup.deadline) / FULL_POWER_TRANCHES_COUNT;

        // update global lockup powers and adjust user specific lockup position
        unchecked {
            totalLockupPower += addedPower;
            userLockupPower[msg.sender] += addedPower;
            userLockup.power += uint56(addedPower);
            userLockup.deadline = uint64(deadline);
        }

        emit LockupContinued(msg.sender, start, addedPower, deadline);
    }

    function _mintLockup(address to, uint256 amount, uint256 start, uint256 deadline) internal {
        // total lockup should be less then whole period of 4 years
        uint256 period = deadline - start;
        UserLockup storage userLockup = userToTrancheIndexToLockup[to][start];

        if (userLockup.amount > 0) {
            // we allow to add to new position only with the same deadline
            require(
                userLockup.deadline == deadline,
                "sYLAY::mintLockup: Lockup position already exists with different deadline"
            );
        } else {
            require(
                deadline > getCurrentTrancheIndex() && period <= FULL_POWER_TRANCHES_COUNT,
                "sYLAY::mintLockup: Invalid deadline"
            );
            // new lockup position
            userLockupIndexes[to].push(uint16(start));
        }

        // calculate the user lockup power
        uint256 power = amount * period / FULL_POWER_TRANCHES_COUNT;

        // update globals
        unchecked {
            totalLockupPower += power;
            userLockupPower[to] += power;
        }

        // update user specific data
        userLockup.amount += uint48(amount);
        userLockup.power += uint56(power);
        userLockup.start = uint64(start);
        userLockup.deadline = uint64(deadline);

        emit LockupMinted(to, amount, power, start, deadline);
    }

    /* ---------- GRADUAL POWER: MINT FUNCTIONS ---------- */

    /**
     * @notice Mints the provided amount of tokens to the specified user to gradually mature up to the amount.
     * @dev Saves the amount to tranche user index, so the voting power starts maturing.
     *
     * Requirements:
     *
     * - the caller must be the autorized
     *
     * @param to gradual mint to user
     * @param amount gradual mint amount
     */
    function mintGradual(address to, uint256 amount) external onlyGradualMinter updateGradual updateGradualUser(to) {
        uint48 trimmedAmount = _trim(amount);
        _mintGradual(to, trimmedAmount);
        emit GradualMinted(to, amount);
    }

    /**
     * @notice Mints the provided amount of tokens to the specified user to gradually mature up to the amount.
     * @dev Saves the amount to tranche user index, so the voting power starts maturing.
     *
     * @param to gradual mint to user
     * @param trimmedAmount gradual mint trimmed amount
     */
    function _mintGradual(address to, uint48 trimmedAmount) private {
        if (trimmedAmount == 0) {
            return;
        }

        UserGradual memory _userGradual = _userGraduals[to];

        // add new maturing amount to user and global amount
        _userGradual.maturingAmount += trimmedAmount;
        _globalGradual.totalMaturingAmount += trimmedAmount;

        // add maturing amount to user tranche
        UserTranche memory latestTranche = _getUserTranche(to, _userGradual.latestTranchePosition);

        uint16 currentTrancheIndex = getCurrentTrancheIndex();

        bool isFirstGradualMint = !_hasTranches(_userGradual);

        // if latest user tranche is not current index, update latest
        // user can have first mint or last tranche deposited is finished
        if (isFirstGradualMint || latestTranche.index < currentTrancheIndex) {
            UserTranchePosition memory nextTranchePosition =
                _getNextUserTranchePosition(_userGradual.latestTranchePosition);

            // if first time gradual minting set oldest tranche position
            if (isFirstGradualMint) {
                _userGradual.oldestTranchePosition = nextTranchePosition;
            }

            // update latest tranche
            _userGradual.latestTranchePosition = nextTranchePosition;

            latestTranche = UserTranche(trimmedAmount, currentTrancheIndex);
        } else {
            // if user already minted in current tranche, add additional amount
            latestTranche.amount += trimmedAmount;
        }

        // update global tranche amount
        _addGlobalTranche(latestTranche.index, trimmedAmount);

        // store updated user values
        _setUserTranche(to, _userGradual.latestTranchePosition, latestTranche);
        _userGraduals[to] = _userGradual;
    }

    /**
     * @notice add `amount` to global tranche `index`
     *
     * @param index tranche index
     * @param amount amount to add
     */
    function _addGlobalTranche(uint256 index, uint48 amount) private {
        Tranche storage tranche = _getTranche(index);
        tranche.amount += amount;
    }

    /**
     * @notice sets updated `user` `tranche` at position
     *
     * @param user user address to set tranche
     * @param userTranchePosition position to set the `tranche` at
     * @param tranche updated `user` tranche
     */
    function _setUserTranche(address user, UserTranchePosition memory userTranchePosition, UserTranche memory tranche)
        private
    {
        UserTranches storage _userTranches = userTranches[user][userTranchePosition.arrayIndex];

        if (userTranchePosition.position == 0) {
            _userTranches.zero = tranche;
        } else if (userTranchePosition.position == 1) {
            _userTranches.one = tranche;
        } else if (userTranchePosition.position == 2) {
            _userTranches.two = tranche;
        } else {
            _userTranches.three = tranche;
        }
    }

    /* ========== GRADUAL POWER: TRANSFER FUNCTIONS ========== */

    /**
     * @notice Transfers user data (staking and graduals) from one address to another.
     * @param from The address of the user from whom data is being transferred.
     * @param to The address of the recipient user.
     */
    function transferUser(address from, address to) external onlyGradualMinter {
        require(_userExists(from), "sYLAY::migrate: User does not exist");
        require(!_userExists(to), "sYLAY::migrate: User already exists");

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

        // migrate user lockups
        uint16[] memory userLockupIndexesFrom = userLockupIndexes[from];
        for (uint256 i = 0; i < userLockupIndexesFrom.length; i++) {
            uint16 index = userLockupIndexesFrom[i];
            userToTrancheIndexToLockup[to][index] = userToTrancheIndexToLockup[from][index];
            delete userToTrancheIndexToLockup[from][index];
        }
        userLockupIndexes[to] = userLockupIndexesFrom;
        delete userLockupIndexes[from];

        // Migrate user gradual
        _userGraduals[to] = _userGraduals[from];
        delete _userGraduals[from];

        // migrate user powers
        userInstantPower[to] = userInstantPower[from];
        delete userInstantPower[from];

        userLockupPower[to] = userLockupPower[from];
        delete userLockupPower[from];

        emit UserTransferred(from, to);
    }

    /* ---------- GRADUAL POWER: BURN FUNCTIONS ---------- */

    /**
     * @notice Burns the provided amount of gradual power from the specified user.
     * @dev User loses all matured power accumulated till now.
     * Voting power starts maturing from the start if there is any amount left.
     *
     * Requirements:
     *
     * - the caller must be the gradual minter
     *
     * @param from burn from user
     * @param amount burn amount
     * @param burnAll true to burn all user amount
     */
    function burnGradual(address from, uint256 amount, bool burnAll)
        external
        onlyGradualMinter
        updateGradual
        updateGradualUser(from)
    {
        UserGradual memory _userGradual = _userGraduals[from];
        GlobalGradual memory global = _globalGradual;
        uint48 userTotalGradualAmount = _userGradual.maturedVotingPower + _userGradual.maturingAmount;

        // remove user matured power
        if (_userGradual.maturedVotingPower > 0) {
            _updateTotalMaturedVotingPower(global, _userGradual.maturedVotingPower);
            _userGradual.maturedVotingPower = 0;
        }

        // remove user maturing
        if (_userGradual.maturingAmount > 0) {
            _updateTotalMaturingAmount(global, _userGradual.maturingAmount);
            _userGradual.maturingAmount = 0;
        }

        // remove user unmatured power
        if (_userGradual.rawUnmaturedVotingPower > 0) {
            _updateTotalRawUnmaturedVotingPower(global, _userGradual.rawUnmaturedVotingPower);
            _userGradual.rawUnmaturedVotingPower = 0;
        }

        // if user has any tranches, remove all of them from user and global
        if (_hasTranches(_userGradual)) {
            uint256 fromIndex = _userGradual.oldestTranchePosition.arrayIndex;
            uint256 toIndex = _userGradual.latestTranchePosition.arrayIndex;

            // loop over user tranches and delete all of them
            for (uint256 i = fromIndex; i <= toIndex; i++) {
                // delete from global tranches
                _deleteUserTranchesFromGlobal(userTranches[from][i]);
                // delete user tranches
                delete userTranches[from][i];
            }
        }

        // reset oldest tranche (meaning user has no tranches)
        _userGradual.oldestTranchePosition = UserTranchePosition(0, 0);

        // apply changes to storage
        _userGraduals[from] = _userGradual;
        _globalGradual = global;

        emit GradualBurned(from, amount, burnAll);

        // if we don't burn all gradual amount, restart maturing
        if (!burnAll) {
            uint48 trimmedAmount = _trimRoundUp(amount);

            // if user still has some amount left, mint gradual from start
            if (userTotalGradualAmount > trimmedAmount) {
                unchecked {
                    uint48 userAmountLeft = userTotalGradualAmount - trimmedAmount;
                    // mint amount left
                    _mintGradual(from, userAmountLeft);
                }
            }
        }
    }

    /**
     * @notice remove user tranches amounts from global tranches
     * @dev remove for all four user tranches in the struct
     *
     * @param _userTranches user tranches
     */
    function _deleteUserTranchesFromGlobal(UserTranches memory _userTranches) private {
        _removeUserTrancheFromGlobal(_userTranches.zero);
        _removeUserTrancheFromGlobal(_userTranches.one);
        _removeUserTrancheFromGlobal(_userTranches.two);
        _removeUserTrancheFromGlobal(_userTranches.three);
    }

    /**
     * @notice remove user tranche amount from global tranche
     *
     * @param userTranche user tranche
     */
    function _removeUserTrancheFromGlobal(UserTranche memory userTranche) private {
        if (userTranche.amount > 0) {
            Tranche storage tranche = _getTranche(userTranche.index);
            tranche.amount -= userTranche.amount;
        }
    }

    /* ---------- GRADUAL POWER: UPDATE GLOBAL FUNCTIONS ---------- */

    /**
     * @notice updates global gradual voting power
     * @dev
     *
     * Requirements:
     *
     * - the caller must be the gradual minter
     */
    function updateVotingPower() external override onlyGradualMinter {
        _updateGradual();
    }

    /**
     * @notice updates global gradual voting power
     * @dev updates only if changes occured
     */
    function _updateGradual() private {
        (GlobalGradual memory global, bool didUpdate) = _getUpdatedGradual();

        if (didUpdate) {
            _globalGradual = global;
            emit GlobalGradualUpdated(
                global.lastUpdatedTrancheIndex,
                global.totalMaturedVotingPower,
                global.totalMaturingAmount,
                global.totalRawUnmaturedVotingPower
            );
        }
    }

    /**
     * @notice returns updated global gradual values
     * @dev the update is in-memory
     *
     * @return global updated GlobalGradual struct
     * @return didUpdate flag if `global` was updated
     */
    function _getUpdatedGradual() private view returns (GlobalGradual memory global, bool didUpdate) {
        uint256 lastFinishedTrancheIndex = getLastFinishedTrancheIndex();
        global = _globalGradual;

        // update gradual until we reach last finished index
        while (global.lastUpdatedTrancheIndex < lastFinishedTrancheIndex) {
            // increment index before updating so we calculate based on finished index
            global.lastUpdatedTrancheIndex++;
            _updateGradualForTrancheIndex(global);
            didUpdate = true;
        }
    }

    /**
     * @notice update global gradual values for tranche `index`
     * @dev the update is done in-memory on `global` struct
     *
     * @param global global gradual struct
     */
    function _updateGradualForTrancheIndex(GlobalGradual memory global) private view {
        // update unmatured voting power
        // every new tranche we add totalMaturingAmount to the _totalRawUnmaturedVotingPower
        global.totalRawUnmaturedVotingPower += global.totalMaturingAmount;

        // move newly matured voting power to matured
        // do only if contract is old enough so full power could be achieved
        if (global.lastUpdatedTrancheIndex >= FULL_POWER_TRANCHES_COUNT) {
            uint256 maturedIndex = global.lastUpdatedTrancheIndex - FULL_POWER_TRANCHES_COUNT + 1;

            uint48 newMaturedVotingPower = _getTranche(maturedIndex).amount;

            // if there is any new fully-matured voting power, update
            if (newMaturedVotingPower > 0) {
                // remove new fully matured voting power from non matured raw one
                uint56 newMaturedAsRawUnmatured = _getMaturedAsRawUnmaturedAmount(newMaturedVotingPower);
                _updateTotalRawUnmaturedVotingPower(global, newMaturedAsRawUnmatured);

                // remove new fully-matured power from maturing amount
                _updateTotalMaturingAmount(global, newMaturedVotingPower);
                // add new fully-matured voting power
                global.totalMaturedVotingPower += newMaturedVotingPower;
            }
        }
    }

    /* ---------- GRADUAL POWER: UPDATE USER FUNCTIONS ---------- */

    /**
     * @notice update gradual user voting power
     * @dev also updates global gradual voting power
     *
     * Requirements:
     *
     * - the caller must be the gradual minter
     *
     * @param user user address to update
     */
    function updateUserVotingPower(address user) external override onlyGradualMinter {
        _updateGradual();
        _updateGradualUser(user);
    }

    /**
     * @notice update gradual user struct storage
     *
     * @param user user address to update
     */
    function _updateGradualUser(address user) private {
        (UserGradual memory _userGradual, bool didUpdate) = _getUpdatedGradualUser(user);
        if (didUpdate) {
            _userGraduals[user] = _userGradual;
            emit UserGradualUpdated(
                user,
                _userGradual.lastUpdatedTrancheIndex,
                _userGradual.maturedVotingPower,
                _userGradual.maturingAmount,
                _userGradual.rawUnmaturedVotingPower
            );
        }
    }

    /**
     * @notice returns updated user gradual struct
     * @dev the update is returned in-memory
     * The update is done in 3 steps:
     * 1. check if user ia alreas, update last updated undex
     * 2. update voting power for tranches that have fully-matured (if any)
     * 3. update voting power for tranches that are still maturing
     *
     * @param user updated for user address
     * @return _userGradual updated user gradual struct
     * @return didUpdate flag if user gradual has updated
     */
    function _getUpdatedGradualUser(address user) private view returns (UserGradual memory, bool) {
        UserGradual memory _userGradual = _userGraduals[user];
        uint16 lastFinishedTrancheIndex = getLastFinishedTrancheIndex();

        // 1. if user already updated in this tranche index, skip
        if (_userGradual.lastUpdatedTrancheIndex == lastFinishedTrancheIndex) {
            return (_userGradual, false);
        }

        // update user if it has maturing power
        if (_hasTranches(_userGradual)) {
            // 2. update fully-matured tranches
            uint16 lastMaturedIndex = _getLastMaturedIndex();
            if (lastMaturedIndex > 0) {
                UserTranche memory oldestTranche = _getUserTranche(user, _userGradual.oldestTranchePosition);
                // update all fully-matured user tranches
                while (_hasTranches(_userGradual) && oldestTranche.index <= lastMaturedIndex) {
                    // mature
                    _matureOldestUsersTranche(_userGradual, oldestTranche);
                    // get new user oldest tranche
                    oldestTranche = _getUserTranche(user, _userGradual.oldestTranchePosition);
                }
            }

            // 3. update still maturing tranches
            if (_isMaturing(_userGradual, lastFinishedTrancheIndex)) {
                // get number of passed indexes
                uint56 indexesPassed = lastFinishedTrancheIndex - _userGradual.lastUpdatedTrancheIndex;

                // add new user matured power
                _userGradual.rawUnmaturedVotingPower += _userGradual.maturingAmount * indexesPassed;
                // last synced index
                _userGradual.lastUpdatedTrancheIndex = lastFinishedTrancheIndex;
            }
        }

        // update user last updated tranche index
        _userGradual.lastUpdatedTrancheIndex = lastFinishedTrancheIndex;

        return (_userGradual, true);
    }

    /**
     * @notice mature users oldest tranche, and update oldest with next user tranche
     * @dev this is called only if we know `oldestTranche` is mature
     * Updates are done im-memory
     *
     * @param _userGradual user gradual struct to update
     * @param oldestTranche users oldest struct (fully matured one)
     */
    function _matureOldestUsersTranche(UserGradual memory _userGradual, UserTranche memory oldestTranche)
        private
        pure
    {
        uint16 fullyMaturedFinishedIndex = _getFullyMaturedAtFinishedIndex(oldestTranche.index);

        uint48 newMaturedVotingPower = oldestTranche.amount;

        // add new matured voting power
        // calculate number of passed indexes between last update until fully matured index
        uint56 indexesPassed = fullyMaturedFinishedIndex - _userGradual.lastUpdatedTrancheIndex;
        _userGradual.rawUnmaturedVotingPower += _userGradual.maturingAmount * indexesPassed;

        // update new fully-matured voting power
        uint56 newMaturedAsRawUnmatured = _getMaturedAsRawUnmaturedAmount(newMaturedVotingPower);

        // update user gradual values in respect of new fully-matured amount
        // remove new fully matured voting power from non matured raw one
        _updateRawUnmaturedVotingPower(_userGradual, newMaturedAsRawUnmatured);
        // add new fully-matured voting power
        _userGradual.maturedVotingPower += newMaturedVotingPower;
        // remove new fully-matured power from maturing amount
        _updateMaturingAmount(_userGradual, newMaturedVotingPower);

        // add next tranche as oldest
        _setNextOldestUserTranchePosition(_userGradual);

        // update last updated index until fully matured index
        _userGradual.lastUpdatedTrancheIndex = fullyMaturedFinishedIndex;
    }

    /**
     * @notice returns index at which the maturing will finish
     * @dev
     * e.g. if FULL_POWER_TRANCHES_COUNT=2 and passing index=1,
     * maturing will complete at the end of index 2.
     * This is the index we return, similar to last finished index.
     *
     * @param index index from which to derive fully matured finished index
     */
    function _getFullyMaturedAtFinishedIndex(uint256 index) private pure returns (uint16) {
        return uint16(index + FULL_POWER_TRANCHES_COUNT - 1);
    }

    /**
     * @notice updates user oldest tranche position to next one in memory
     * @dev this is done after an oldest tranche position matures
     * If oldest tranch position is same as latest one, all user
     * tranches have matured. In this case we remove tranhe positions from the user
     *
     * @param _userGradual user gradual struct to update
     */
    function _setNextOldestUserTranchePosition(UserGradual memory _userGradual) private pure {
        // if oldest tranche is same as latest, this was the last tranche and we remove it from the user
        if (
            _userGradual.oldestTranchePosition.arrayIndex == _userGradual.latestTranchePosition.arrayIndex
                && _userGradual.oldestTranchePosition.position == _userGradual.latestTranchePosition.position
        ) {
            // reset user tranches as all of them matured
            _userGradual.oldestTranchePosition = UserTranchePosition(0, 0);
        } else {
            // set next user tranche as oldest
            _userGradual.oldestTranchePosition = _getNextUserTranchePosition(_userGradual.oldestTranchePosition);
        }
    }

    /* ---------- GRADUAL POWER: GLOBAL HELPER FUNCTIONS ---------- */

    /**
     * @notice returns total gradual voting power from `global`
     * @dev the returned amount is untrimmed
     *
     * @param global global gradual struct
     * @return totalGradualVotingPower total gradual voting power (fully-matured + maturing)
     */
    function _getTotalGradualVotingPower(GlobalGradual memory global) private pure returns (uint256) {
        return _untrim(global.totalMaturedVotingPower)
            + _getMaturingVotingPowerFromRaw(_untrim(global.totalRawUnmaturedVotingPower));
    }

    /**
     * @notice returns global tranche storage struct
     * @dev we return struct, so we can manipulate the storage in other functions
     *
     * @param index tranche index
     * @return tranche tranche storage struct
     */
    function _getTranche(uint256 index) private view returns (Tranche storage) {
        uint256 arrayindex = index / TRANCHES_PER_WORD;

        GlobalTranches storage globalTranches = indexedGlobalTranches[arrayindex];

        uint256 globalTranchesPosition = index % TRANCHES_PER_WORD;

        if (globalTranchesPosition == 0) {
            return globalTranches.zero;
        } else if (globalTranchesPosition == 1) {
            return globalTranches.one;
        } else if (globalTranchesPosition == 2) {
            return globalTranches.two;
        } else if (globalTranchesPosition == 3) {
            return globalTranches.three;
        } else {
            return globalTranches.four;
        }
    }

    /* ---------- GRADUAL POWER: USER HELPER FUNCTIONS ---------- */

    /**
     * @notice gets `user` `tranche` at position
     *
     * @param user user address to get tranche from
     * @param userTranchePosition position to get the `tranche` from
     * @return tranche `user` tranche
     */
    function _getUserTranche(address user, UserTranchePosition memory userTranchePosition)
        private
        view
        returns (UserTranche memory tranche)
    {
        UserTranches storage _userTranches = userTranches[user][userTranchePosition.arrayIndex];

        if (userTranchePosition.position == 0) {
            tranche = _userTranches.zero;
        } else if (userTranchePosition.position == 1) {
            tranche = _userTranches.one;
        } else if (userTranchePosition.position == 2) {
            tranche = _userTranches.two;
        } else {
            tranche = _userTranches.three;
        }
    }

    /**
     * @notice gets `user` `tranche` at position
     *
     * @param user user address to get tranche from
     * @param userTranchePosition position to get the `tranche` from
     * @return tranche `user` tranche (storage pointer)
     */
    function _getUserTrancheStorage(address user, UserTranchePosition memory userTranchePosition)
        private
        view
        returns (UserTranche storage tranche)
    {
        UserTranches storage _userTranches = userTranches[user][userTranchePosition.arrayIndex];

        if (userTranchePosition.position == 0) {
            tranche = _userTranches.zero;
        } else if (userTranchePosition.position == 1) {
            tranche = _userTranches.one;
        } else if (userTranchePosition.position == 2) {
            tranche = _userTranches.two;
        } else {
            tranche = _userTranches.three;
        }
    }

    /**
     * @notice return last matured tranche index
     *
     * @return lastMaturedIndex last matured tranche index
     */
    function _getLastMaturedIndex() private view returns (uint16 lastMaturedIndex) {
        uint256 currentTrancheIndex = getCurrentTrancheIndex();
        if (currentTrancheIndex > FULL_POWER_TRANCHES_COUNT) {
            unchecked {
                lastMaturedIndex = uint16(currentTrancheIndex - FULL_POWER_TRANCHES_COUNT);
            }
        }
    }

    /**
     * @notice returns the user gradual voting power (fully-matured and maturing)
     * @dev the returned amount is untrimmed
     *
     * @param _userGradual user gradual struct
     * @return userGradualVotingPower user gradual voting power (fully-matured + maturing)
     */
    function _getUserGradualVotingPower(UserGradual memory _userGradual) private pure returns (uint256) {
        return _untrim(_userGradual.maturedVotingPower)
            + _getMaturingVotingPowerFromRaw(_untrim(_userGradual.rawUnmaturedVotingPower));
    }

    /**
     * @notice Returns total tranches for user
     * @dev total tranches for user between oldest and latest position.
     * ((x2*4)+y2 - ((x1*4)+y1)) + 1
     * where: latest.arrayIndex = x2, latest.position = y2
     *        oldest.arrayIndex = x1, oldest.position = y1
     */
    function _getTotalTranches(UserGradual memory _userGradual) private pure returns (uint256) {
        UserTranchePosition memory oldest = _userGradual.oldestTranchePosition;
        UserTranchePosition memory latest = _userGradual.latestTranchePosition;
        return ((latest.arrayIndex * 4) + latest.position) - ((oldest.arrayIndex * 4) + oldest.position) + 1;
    }

    /**
     * @notice returns next user tranche position, based on current one
     *
     * @param currentTranchePosition current user tranche position
     * @return nextTranchePosition next tranche position of `currentTranchePosition`
     */
    function _getNextUserTranchePosition(UserTranchePosition memory currentTranchePosition)
        private
        pure
        returns (UserTranchePosition memory nextTranchePosition)
    {
        if (currentTranchePosition.arrayIndex == 0) {
            nextTranchePosition.arrayIndex = 1;
        } else {
            if (currentTranchePosition.position < 3) {
                nextTranchePosition.arrayIndex = currentTranchePosition.arrayIndex;
                nextTranchePosition.position = currentTranchePosition.position + 1;
            } else {
                nextTranchePosition.arrayIndex = currentTranchePosition.arrayIndex + 1;
            }
        }
    }

    /**
     * @notice check if user requires maturing
     *
     * @param _userGradual user gradual struct to update
     * @param lastFinishedTrancheIndex index of last finished tranche index
     * @return needsMaturing true if user needs maturing, else false
     */
    function _isMaturing(UserGradual memory _userGradual, uint256 lastFinishedTrancheIndex)
        private
        pure
        returns (bool)
    {
        return _userGradual.lastUpdatedTrancheIndex < lastFinishedTrancheIndex && _hasTranches(_userGradual);
    }

    /**
     * @notice check if user gradual has any non-matured tranches
     *
     * @param _userGradual user gradual struct
     * @return hasTranches true if user has non-matured tranches
     */
    function _hasTranches(UserGradual memory _userGradual) internal pure returns (bool hasTranches) {
        if (_userGradual.oldestTranchePosition.arrayIndex > 0) {
            hasTranches = true;
        }
    }

    /**
     * @notice check if user exists in the system.
     *
     * @param account user address to check
     * @return userExists true if user exists
     */
    function _userExists(address account) internal view returns (bool) {
        return _userGraduals[account].lastUpdatedTrancheIndex != 0 || userLockupPower[account] != 0
            || userInstantPower[account] != 0;
    }

    /* ---------- GRADUAL POWER: HELPER FUNCTIONS ---------- */

    /**
     * @notice return trimmed amount
     * @dev `amount` is trimmed by `TRIM_SIZE`.
     * This is done so the amount can be represented in 48bits.
     * This still gives us enough accuracy so the core logic is not affected.
     *
     * @param amount amount to trim
     * @return trimmedAmount amount divided by `TRIM_SIZE`
     */
    function _trim(uint256 amount) private pure returns (uint48) {
        return uint48(amount / TRIM_SIZE);
    }

    /**
     * @notice return trimmed amount rounding up if any dust left
     *
     * @param amount amount to trim
     * @return trimmedAmount amount divided by `TRIM_SIZE`, rounded up
     */
    function _trimRoundUp(uint256 amount) private pure returns (uint48 trimmedAmount) {
        trimmedAmount = _trim(amount);
        if (_untrim(trimmedAmount) < amount) {
            unchecked {
                trimmedAmount++;
            }
        }
    }

    /**
     * @notice untrim `trimmedAmount` in respect to `TRIM_SIZE`
     *
     * @param trimmedAmount amount previously trimemd
     * @return untrimmedAmount untrimmed amount
     */
    function _untrim(uint256 trimmedAmount) private pure returns (uint256) {
        unchecked {
            return trimmedAmount * TRIM_SIZE;
        }
    }

    /**
     * @notice calculates voting power from raw unmatured
     *
     * @param rawMaturingVotingPower raw maturing voting power amount
     * @return maturingVotingPower actual maturing power amount
     */
    function _getMaturingVotingPowerFromRaw(uint256 rawMaturingVotingPower) private pure returns (uint256) {
        return rawMaturingVotingPower / FULL_POWER_TRANCHES_COUNT;
    }

    /**
     * @notice Returns amount represented in raw unmatured value
     * @dev used to substract fully-matured amount from raw unmatured, when amount matures
     *
     * @param amount matured amount
     * @return asRawUnmatured `amount` multiplied by `FULL_POWER_TRANCHES_COUNT` (raw unmatured amount)
     */
    function _getMaturedAsRawUnmaturedAmount(uint48 amount) private pure returns (uint56) {
        unchecked {
            return uint56(amount * FULL_POWER_TRANCHES_COUNT);
        }
    }

    /**
     * @dev after migration there could be small discrepancy in absolute values
     */
    function _updateTotalRawUnmaturedVotingPower(GlobalGradual memory global, uint56 newMaturedAsRawUnmatured)
        private
        pure
    {
        if (global.totalRawUnmaturedVotingPower < newMaturedAsRawUnmatured) {
            global.totalRawUnmaturedVotingPower = 0;
        } else {
            global.totalRawUnmaturedVotingPower -= newMaturedAsRawUnmatured;
        }
    }

    /**
     * @dev after migration there could be small discrepancy in absolute values
     */
    function _updateTotalMaturedVotingPower(GlobalGradual memory global, uint48 maturedVotingPower) private pure {
        if (global.totalMaturedVotingPower < maturedVotingPower) {
            global.totalMaturedVotingPower = 0;
        } else {
            global.totalMaturedVotingPower -= maturedVotingPower;
        }
    }

    /**
     * @dev after migration there could be small discrepancy in absolute values
     */
    function _updateTotalMaturingAmount(GlobalGradual memory global, uint48 maturingAmount) private pure {
        if (global.totalMaturingAmount < maturingAmount) {
            global.totalMaturingAmount = 0;
        } else {
            global.totalMaturingAmount -= maturingAmount;
        }
    }

    /**
     * @dev after migration there could be small discrepancy in absolute values
     */
    function _updateRawUnmaturedVotingPower(UserGradual memory _userGradual, uint56 newMaturedAsRawUnmatured)
        private
        pure
    {
        if (_userGradual.rawUnmaturedVotingPower < newMaturedAsRawUnmatured) {
            _userGradual.rawUnmaturedVotingPower = 0;
        } else {
            _userGradual.rawUnmaturedVotingPower -= newMaturedAsRawUnmatured;
        }
    }

    /**
     * @dev after migration there could be small discrepancy in absolute values
     */
    function _updateMaturingAmount(UserGradual memory _userGradual, uint48 newMaturedVotingPower) private pure {
        if (_userGradual.maturingAmount < newMaturedVotingPower) {
            _userGradual.maturingAmount = 0;
        } else {
            _userGradual.maturingAmount -= newMaturedVotingPower;
        }
    }

    /* ========== OWNER FUNCTIONS ========== */

    /**
     * @notice Sets or resets the instant minter address
     *
     * Requirements:
     *
     * - the caller must be the owner of the contract
     * - the minter must not be the zero address
     *
     * @param _minter address to set
     * @param _set true to set, false to reset
     */
    function setMinter(address _minter, bool _set) external onlyOwner {
        require(_minter != address(0), "sYLAY::setMinter: minter cannot be the zero address");
        minters[_minter] = _set;
        emit MinterSet(_minter, _set);
    }

    /**
     * @notice Sets or resets the gradual minter address
     *
     * Requirements:
     *
     * - the caller must be the owner of the contract
     * - the minter must not be the zero address
     *
     * @param _gradualMinter address to set
     * @param _set true to set, false to reset
     */
    function setGradualMinter(address _gradualMinter, bool _set) external onlyOwner {
        require(_gradualMinter != address(0), "sYLAY::setGradualMinter: gradual minter cannot be the zero address");
        gradualMinters[_gradualMinter] = _set;
        emit GradualMinterSet(_gradualMinter, _set);
    }

    /* ========== RESTRICTION FUNCTIONS ========== */

    /**
     * @notice Ensures the caller is the instant minter
     */
    function _onlyMinter() private view {
        require(minters[msg.sender], "sYLAY::_onlyMinter: Insufficient Privileges");
    }

    /**
     * @notice Ensures the caller is the gradual minter
     */
    function _onlyGradualMinter() private view {
        require(gradualMinters[msg.sender], "sYLAY::_onlyGradualMinter: Insufficient Privileges");
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Throws if the caller is not the instant miter
     */
    modifier onlyMinter() {
        _onlyMinter();
        _;
    }

    /**
     * @notice Throws if the caller is not the gradual minter
     */
    modifier onlyGradualMinter() {
        _onlyGradualMinter();
        _;
    }

    /**
     * @notice Update global gradual values
     */
    modifier updateGradual() {
        _updateGradual();
        _;
    }

    /**
     * @notice Update user gradual values
     */
    modifier updateGradualUser(address user) {
        _updateGradualUser(user);
        _;
    }
}
