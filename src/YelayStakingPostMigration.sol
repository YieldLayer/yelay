// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/draft-EIP712.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import "./YelayOwnable.sol";
import "./libraries/SafeCast.sol";

import "./interfaces/IYelayStakingPostMigration.sol";
import "./interfaces/IsYLAYRewards.sol";
import "./interfaces/IsYLAYPostMigration.sol";
import "./interfaces/IRewardDistributor.sol";

/**
 * @notice Implementation of the {IYelayStakingBase} interface.
 *
 * @dev
 * An adaptation of the Synthetix StakingRewards contract to support multiple tokens:
 *
 * https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
 *
 * At stake, gradual sYLAY (Yelay Voting Token) is minted and accumulated every week.
 * At unstake all sYLAY is burned. The maturing process of sYLAY restarts.
 */
contract YelayStakingPostMigration is ReentrancyGuardUpgradeable, YelayOwnable, IYelayStakingPostMigration, EIP712 {
    using SafeERC20 for IERC20;

    /* ========== STRUCTS ========== */

    // The reward configuration struct, containing all the necessary data of a typical Synthetix StakingReward contract
    struct RewardConfiguration {
        uint32 rewardsDuration;
        uint32 periodFinish;
        uint192 rewardRate; // rewards per second multiplied by accuracy
        uint32 lastUpdateTime;
        uint224 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
    }

    /* ========== CONSTANTS ========== */

    /// @notice Multiplier used when dealing reward calculations
    uint256 private constant REWARD_ACCURACY = 1e18;

    /* ========== STATE VARIABLES ========== */

    /// @notice YLAY token address
    IERC20 public immutable stakingToken;

    /// @notice sYLAY token address
    IsYLAYPostMigration public immutable sYlay;

    /// @notice sYLAY token rewards address
    IsYLAYRewards public immutable sYlayRewards;

    /// @notice Yelay reward distributor
    IRewardDistributor public immutable rewardDistributor;

    /// @notice Reward token configurations
    mapping(IERC20 => RewardConfiguration) public rewardConfiguration;

    /// @notice Reward tokens
    IERC20[] public rewardTokens;

    /// @notice Blacklisted force-removed tokens
    mapping(IERC20 => bool) public tokenBlacklist;

    /// @notice Total YLAY staked
    uint256 public totalStaked;

    /// @notice Account YLAY staked balance
    mapping(address => uint256) public balances;

    /// @notice Whitelist showing if address can stake for another address
    mapping(address => bool) public canStakeFor;

    /// @notice Mapping showing if and what address staked for another address
    /// @dev if address is 0, noone staked for address (or unstaking was permitted)
    mapping(address => address) public stakedBy;

    /// @notice Total YLAY locked. subset of totalStaked
    uint256 public totalLocked;

    /// @notice Account YLAY locked balance. subset of balances
    mapping(address => uint256) public locked;

    bytes32 private constant _TRANSFER_USER_TYPEHASH = keccak256("TransferUser(address to, uint256 deadline)");

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Sets the immutable values
     *
     * @param _stakingToken YLAY token
     * @param _sYlay Yelay voting token (sYLAY)
     * @param _sYlayRewards sYLAY rewards contract
     * @param _rewardDistributor reward distributor contract
     * @param _yelayOwner Yelay owner contract
     */
    constructor(
        address _stakingToken,
        address _sYlay,
        address _sYlayRewards,
        address _rewardDistributor,
        address _yelayOwner
    ) YelayOwnable(IYelayOwner(_yelayOwner)) EIP712("YelayStaking", "1.0.0") {
        stakingToken = IERC20(_stakingToken);
        sYlay = IsYLAYPostMigration(_sYlay);
        sYlayRewards = IsYLAYRewards(_sYlayRewards);
        rewardDistributor = IRewardDistributor(_rewardDistributor);
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __ReentrancyGuard_init();
    }

    /* ========== VIEWS ========== */

    function lastTimeRewardApplicable(IERC20 token) public view returns (uint32) {
        return uint32(_min(block.timestamp, rewardConfiguration[token].periodFinish));
    }

    function rewardPerToken(IERC20 token) public view returns (uint224) {
        RewardConfiguration storage config = rewardConfiguration[token];

        if (totalStaked == 0) return config.rewardPerTokenStored;

        uint256 timeDelta = lastTimeRewardApplicable(token) - config.lastUpdateTime;

        if (timeDelta == 0) return config.rewardPerTokenStored;

        return SafeCast.toUint224(config.rewardPerTokenStored + ((timeDelta * config.rewardRate) / totalStaked));
    }

    function earned(IERC20 token, address account) public view returns (uint256) {
        RewardConfiguration storage config = rewardConfiguration[token];

        uint256 accountStaked = balances[account];

        if (accountStaked == 0) return config.rewards[account];

        uint256 userRewardPerTokenPaid = config.userRewardPerTokenPaid[account];

        return ((accountStaked * (rewardPerToken(token) - userRewardPerTokenPaid)) / REWARD_ACCURACY)
            + config.rewards[account];
    }

    function rewardTokensCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Returns the struct hash for hashTypedDataV4
     */
    function structHash(address from, uint256 deadline) public pure returns (bytes32) {
        return keccak256(abi.encode(_TRANSFER_USER_TYPEHASH, from, deadline));
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Transfers the staking balance and rewards of one user to another.
     * @dev This function is non-reentrant and updates rewards before transferring.
     * @param to The address of the recipient to whom the staking data is transferred.
     */
    function transferUser(address to, uint256 deadline, bytes memory signature)
        external
        nonReentrant
        updateRewards(msg.sender)
    {
        require(deadline > block.timestamp, "YelayStaking::transferUser: deadline has passed");

        bytes32 hash_ = _hashTypedDataV4(structHash(msg.sender, deadline));
        address signer = ECDSA.recover(hash_, signature);

        require(signer == to, "YelayStaking::transferUser: invalid signature");

        balances[to] = balances[msg.sender];
        canStakeFor[to] = canStakeFor[msg.sender];
        stakedBy[to] = stakedBy[msg.sender];
        locked[to] = locked[msg.sender];

        delete balances[msg.sender];
        delete canStakeFor[msg.sender];
        delete stakedBy[msg.sender];
        delete locked[msg.sender];

        uint256 _rewardTokensCount = rewardTokens.length;
        for (uint256 i; i < _rewardTokensCount; i++) {
            RewardConfiguration storage config = rewardConfiguration[rewardTokens[i]];

            config.rewards[to] = config.rewards[msg.sender];
            config.userRewardPerTokenPaid[to] = config.userRewardPerTokenPaid[msg.sender];

            delete config.rewards[msg.sender];
            delete config.userRewardPerTokenPaid[msg.sender];
        }

        sYlay.transferUser(msg.sender, to);
    }

    /**
     * @notice Stake YLAY tokens and start earning sYLAY gradually.
     * @param amount The amount of YLAY to stake.
     */
    function stake(uint256 amount) public virtual nonReentrant updateRewards(msg.sender) {
        _stake(msg.sender, amount);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function _stake(address account, uint256 amount) private {
        require(amount > 0, "YelayStaking::_stake: Cannot stake 0");

        unchecked {
            totalStaked += amount;
            balances[account] += amount;
        }

        // mint gradual sYLAY for the account
        sYlay.mintGradual(account, amount);
    }

    /*
       @notice Compounds YLAY rewards, and sYLAY rewards (if requested)
       @param doCompoundsYlayRewards If true, compounds sYLAY rewards also.
    */
    function compound(bool doCompoundsYlayRewards) external nonReentrant {
        // collect YLAY earned fom Yelay rewards and stake them
        uint256 reward = _getRewardForCompound(msg.sender, doCompoundsYlayRewards);

        if (reward > 0) {
            // update user rewards before staking
            _updateYelayRewards(msg.sender);

            // update user sYLAY based reward before staking
            // skip updating sYLAY reward if we compounded form it as it's already updated
            if (!doCompoundsYlayRewards) {
                _updatesYlayReward(msg.sender);
            }

            // stake collected reward
            _stake(msg.sender, reward);
            // move compounded YLAY reward to this contract
            rewardDistributor.payReward(address(this), stakingToken, reward);
        }
    }

    /**
     * @notice Unstake YLAY tokens, burn sYLAY and transfer YLAY back to the user.
     * @dev remints any available YLAY that was not withdrawn.
     * @param amount The amount of YLAY to unstake.
     */
    function unstake(uint256 amount) public nonReentrant notStakedBy updateRewards(msg.sender) {
        // burn unlocked locks and get available amount to unstake now
        uint256 amountUnlocked = sYlay.burnLockups(msg.sender);
        uint256 available = balances[msg.sender] - (locked[msg.sender] - amountUnlocked);
        require(amount > 0 && amount <= available, "YelayStaking::unstake: Unavailable amount requested");

        // update state
        unchecked {
            totalLocked -= amountUnlocked;
            locked[msg.sender] -= amountUnlocked;
            totalStaked -= amount;
            balances[msg.sender] -= amount;
        }

        // burn gradual sYLAY for the sender
        if (balances[msg.sender] == 0) {
            sYlay.burnGradual(msg.sender, 0, true);
        } else {
            uint256 amountToBurn = (amountUnlocked >= amount) ? 0 : amount - amountUnlocked;
            uint256 amountToMint = (amountUnlocked >= amount) ? amountUnlocked - amount : 0;
            sYlay.burnGradual(msg.sender, amountToBurn, false);
            sYlay.mintGradual(msg.sender, amountToMint);
        }

        // transfer amount to user
        stakingToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Lock YLAY tokens and receive corresponding sYLAY for lock period chosen.
     * @param amount The amount of YLAY to lock.
     * @param deadline The deadline for the lock. must be in the future.
     */
    function lock(uint256 amount, uint256 deadline) external nonReentrant {
        _lock(msg.sender, amount, deadline);
    }

    function _lock(address account, uint256 amount, uint256 deadline) private {
        require(amount > 0, "YelayStaking::_lock: Cannot lock 0");

        uint256 trimmedAmount = sYlay.mintLockup(account, amount, deadline);

        unchecked {
            totalLocked += trimmedAmount;
            locked[msg.sender] += trimmedAmount;
            totalStaked += amount;
            balances[msg.sender] += amount;
        }

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(account, amount, deadline);
    }

    /**
     * @notice Lock an existing gradual position with YLAY tokens, and receive corresponding sYLAY for lock period
     *            chosen.
     * @param position The position to lock.
     * @param deadline The deadline for the lock. must be in the future.
     */
    function lockTranche(IsYLAYPostMigration.UserTranchePosition calldata position, uint256 deadline)
        external
        nonReentrant
    {
        uint256 trimmedAmount = sYlay.migrateToLockup(msg.sender, position, deadline);

        unchecked {
            totalLocked += trimmedAmount;
            locked[msg.sender] += trimmedAmount;
        }

        emit LockedTranche(msg.sender, trimmedAmount, deadline);
    }

    function _getRewardForCompound(address account, bool doCompoundsYlayRewards)
        internal
        updateReward(stakingToken, account)
        returns (uint256 reward)
    {
        RewardConfiguration storage config = rewardConfiguration[stakingToken];

        reward = config.rewards[account];
        if (reward > 0) {
            config.rewards[account] = 0;
            emit RewardCompounded(msg.sender, reward);
        }

        if (doCompoundsYlayRewards) {
            _updatesYlayReward(account);
            uint256 sYlayreward = sYlayRewards.flushRewards(account);

            if (sYlayreward > 0) {
                reward += sYlayreward;
                emit VoRewardCompounded(msg.sender, reward);
            }
        }
    }

    function getRewards(IERC20[] memory tokens, bool doClaimsYlayRewards) external nonReentrant notStakedBy {
        for (uint256 i; i < tokens.length; i++) {
            _getReward(tokens[i], msg.sender);
        }

        if (doClaimsYlayRewards) {
            _getsYlayRewards(msg.sender);
        }
    }

    function getActiveRewards(bool doClaimsYlayRewards) external nonReentrant notStakedBy {
        _getActiveRewards(msg.sender);

        if (doClaimsYlayRewards) {
            _getsYlayRewards(msg.sender);
        }
    }

    function getUpdatedsYlayRewardAmount() external returns (uint256 rewards) {
        // update rewards
        rewards = sYlayRewards.updateRewards(msg.sender);
        // update and store users sYLAY
        sYlay.updateUserVotingPower(msg.sender);
    }

    function _getActiveRewards(address account) internal {
        uint256 _rewardTokensCount = rewardTokens.length;
        for (uint256 i; i < _rewardTokensCount; i++) {
            _getReward(rewardTokens[i], account);
        }
    }

    function _getReward(IERC20 token, address account) internal updateReward(token, account) {
        RewardConfiguration storage config = rewardConfiguration[token];

        require(config.rewardsDuration != 0, "YelayStaking::_getReward: Bad reward token");

        uint256 reward = config.rewards[account];
        if (reward > 0) {
            config.rewards[account] = 0;
            rewardDistributor.payReward(account, token, reward);
            emit RewardPaid(token, account, reward);
        }
    }

    function _getsYlayRewards(address account) internal {
        _updatesYlayReward(account);
        uint256 reward = sYlayRewards.flushRewards(account);

        if (reward > 0) {
            rewardDistributor.payReward(account, stakingToken, reward);
            emit sYLAYRewardPaid(stakingToken, account, reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Stake YLAY tokens for another address.
     * @param account The address for which the YLAY tokens are staked.
     * @param amount The amount of YLAY to stake.
     */
    function stakeFor(address account, uint256 amount)
        public
        virtual
        nonReentrant
        canStakeForAddress(account)
        updateRewards(account)
    {
        _stake(account, amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        stakedBy[account] = msg.sender;

        emit StakedFor(account, msg.sender, amount);
    }

    /**
     * @notice Lock YLAY tokens for an address.
     * @param account The address for which the YLAY tokens are locked.
     * @param amount The amount of YLAY to lock.
     * @param deadline The deadline for the lock. must be in the future.
     */
    function lockFor(address account, uint256 amount, uint256 deadline) external nonReentrant {
        _lock(account, amount, deadline);
    }

    /**
     * @notice Allow unstake for `allowFor` address
     * @dev
     *
     * Requirements:
     *
     * - the caller must be the Yelay or address that staked for `allowFor` address
     *
     * @param allowFor address to allow unstaking for
     */
    function allowUnstakeFor(address allowFor) external {
        require(
            (canStakeFor[msg.sender] && stakedBy[allowFor] == msg.sender) || isYelayOwner(),
            "YelayStaking::allowUnstakeFor: Cannot allow unstaking for address"
        );
        // reset address to 0 to allow unstaking
        stakedBy[allowFor] = address(0);

        emit UnstakeAllowed(allowFor, msg.sender);
    }

    /**
     * @notice Allows a new token to be added to the reward system
     *
     * @dev
     * Emits an {TokenAdded} event indicating the newly added reward token
     * and configuration
     *
     * Requirements:
     *
     * - the caller must be the reward Yelay
     * - the reward duration must be non-zero
     * - the token must not have already been added
     *
     */
    function addToken(IERC20 token, uint32 rewardsDuration, uint256 reward) external onlyOwner {
        RewardConfiguration storage config = rewardConfiguration[token];

        require(!tokenBlacklist[token], "YelayStaking::addToken: Cannot add blacklisted token");
        require(rewardsDuration != 0, "YelayStaking::addToken: Reward duration cannot be 0");
        require(config.lastUpdateTime == 0, "YelayStaking::addToken: Token already added");

        rewardTokens.push(token);

        config.rewardsDuration = rewardsDuration;

        if (reward > 0) {
            _notifyRewardAmount(token, reward);
        }
    }

    function notifyRewardAmount(IERC20 token, uint32 _rewardsDuration, uint256 reward) external onlyOwner {
        RewardConfiguration storage config = rewardConfiguration[token];
        config.rewardsDuration = _rewardsDuration;
        require(rewardConfiguration[token].lastUpdateTime != 0, "YelayStaking::notifyRewardAmount: Token not yet added");
        _notifyRewardAmount(token, reward);
    }

    function _notifyRewardAmount(IERC20 token, uint256 reward) private updateReward(token, address(0)) {
        RewardConfiguration storage config = rewardConfiguration[token];

        require(
            config.rewardPerTokenStored + (reward * REWARD_ACCURACY) <= type(uint192).max,
            "YelayStaking::_notifyRewardAmount: Reward amount too big"
        );

        uint32 newPeriodFinish = uint32(block.timestamp) + config.rewardsDuration;

        if (block.timestamp >= config.periodFinish) {
            config.rewardRate = SafeCast.toUint192((reward * REWARD_ACCURACY) / config.rewardsDuration);
            emit RewardAdded(token, reward, config.rewardsDuration);
        } else {
            uint256 remaining = config.periodFinish - block.timestamp;
            uint256 leftover = remaining * config.rewardRate;
            uint192 newRewardRate = SafeCast.toUint192((reward * REWARD_ACCURACY + leftover) / config.rewardsDuration);

            config.rewardRate = newRewardRate;
            emit RewardUpdated(token, reward, leftover, config.rewardsDuration, newPeriodFinish);
        }

        config.lastUpdateTime = uint32(block.timestamp);
        config.periodFinish = newPeriodFinish;
    }

    // End rewards emission earlier
    function updatePeriodFinish(IERC20 token, uint32 timestamp) external onlyOwner updateReward(token, address(0)) {
        if (rewardConfiguration[token].lastUpdateTime > timestamp) {
            rewardConfiguration[token].periodFinish = rewardConfiguration[token].lastUpdateTime;
        } else {
            rewardConfiguration[token].periodFinish = timestamp;
        }

        emit PeriodFinishUpdated(token, rewardConfiguration[token].periodFinish);
    }

    /**
     * @notice Remove reward from vault rewards configuration.
     * @dev
     * Used to sanitize vault and save on gas, after the reward has ended.
     * Users will be able to claim rewards
     *
     * Requirements:
     *
     * - the caller must be the Yelay owner or Yelay
     * - cannot claim vault underlying token
     * - cannot only execute if the reward finished
     *
     * @param token Token address to remove
     */
    function removeReward(IERC20 token) external onlyOwner onlyFinished(token) updateReward(token, address(0)) {
        _removeReward(token);
    }

    /**
     * @notice Allow an address to stake for another address.
     * @dev
     * Requirements:
     *
     * - the caller must be the distributor
     *
     * @param account Address to allow
     * @param _canStakeFor True to allow, false to remove allowance
     */
    function setCanStakeFor(address account, bool _canStakeFor) external onlyOwner {
        canStakeFor[account] = _canStakeFor;
        emit CanStakeForSet(account, _canStakeFor);
    }

    function recoverERC20(IERC20 tokenAddress, uint256 tokenAmount, address recoverTo) external onlyOwner {
        require(tokenAddress != stakingToken, "YelayStaking::recoverERC20: Cannot withdraw the staking token");
        tokenAddress.safeTransfer(recoverTo, tokenAmount);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @notice Syncs rewards across all tokens of the system
     *
     * This function is meant to be invoked every time the instant deposit
     * of a user changes.
     */
    function _updateRewards(address account) private {
        // update YLAY based rewards
        _updateYelayRewards(account);

        // update sYLAY based reward
        _updatesYlayReward(account);
    }

    function _updateYelayRewards(address account) private {
        uint256 _rewardTokensCount = rewardTokens.length;

        // update YLAY based rewards
        for (uint256 i; i < _rewardTokensCount; i++) {
            _updateReward(rewardTokens[i], account);
        }
    }

    function _updateReward(IERC20 token, address account) private {
        RewardConfiguration storage config = rewardConfiguration[token];
        config.rewardPerTokenStored = rewardPerToken(token);
        config.lastUpdateTime = lastTimeRewardApplicable(token);
        if (account != address(0)) {
            config.rewards[account] = earned(token, account);
            config.userRewardPerTokenPaid[account] = config.rewardPerTokenStored;
        }
    }

    /**
     * @notice Update rewards collected from account sYLAY
     * @dev
     * First we update rewards calling `sYlayRewards.updateRewards`
     * - Here we only simulate the reward accumulated over tranches
     * Then we update and store users power by calling sYLAY contract
     * - Here we actually store the udated values.
     * - If store wouldn't happen, next time we'd simulate the same sYLAY tranches again
     */
    function _updatesYlayReward(address account) private {
        // update rewards
        sYlayRewards.updateRewards(account);
        // update and store users sYLAY
        sYlay.updateUserVotingPower(account);
    }

    function _removeReward(IERC20 token) private {
        uint256 _rewardTokensCount = rewardTokens.length;
        for (uint256 i; i < _rewardTokensCount; i++) {
            if (rewardTokens[i] == token) {
                rewardTokens[i] = rewardTokens[_rewardTokensCount - 1];

                rewardTokens.pop();
                emit RewardRemoved(token);
                break;
            }
        }
    }

    function _onlyFinished(IERC20 token) private view {
        require(
            block.timestamp > rewardConfiguration[token].periodFinish,
            "YelayStaking::_onlyFinished: Reward not finished"
        );
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? b : a;
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(IERC20 token, address account) {
        _updateReward(token, account);
        _;
    }

    modifier updateRewards(address account) {
        _updateRewards(account);
        _;
    }

    modifier canStakeForAddress(address account) {
        // verify sender can stake for
        require(
            canStakeFor[msg.sender] || isYelayOwner(),
            "YelayStaking::canStakeForAddress: Cannot stake for other addresses"
        );

        // if address already staked, verify further
        if (balances[account] > 0) {
            // verify address was staked by some other address
            require(stakedBy[account] != address(0), "YelayStaking::canStakeForAddress: Address already staked");

            // verify address was staked by the sender or sender is the Yelay owner
            require(
                stakedBy[account] == msg.sender || isYelayOwner(),
                "YelayStaking::canStakeForAddress: Address staked by another address"
            );
        }
        _;
    }

    modifier notStakedBy() {
        require(stakedBy[msg.sender] == address(0), "YelayStaking::notStakedBy: Cannot withdraw until allowed");
        _;
    }

    modifier onlyFinished(IERC20 token) {
        _onlyFinished(token);
        _;
    }
}
