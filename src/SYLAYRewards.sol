// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./YelayOwnable.sol";

import "./interfaces/IsYLAYRewards.sol";
import "./interfaces/IsYLAYBase.sol";

/**
 * @notice Implementation of the {IsYLAYRewards} interface.
 *
 * @dev
 * This contract implements the logic to calculate and distribute
 * YLAY token rewards to according to users gradual sYLAY balance.
 * sYLAY Voting Token (sYLAY) is an inflationary token as it
 * increases power over the period of 3 years.
 *
 * This contract assumes only YLAY Staking is updating gradual mint, as
 * well as that the sYLAY state has not been updated prior calling
 * the updateRewards function.
 *
 * Only sYLAY can add, update and end rewards.
 * Only YLAY Staking contract can update this contract.
 */
contract sYLAYRewards is YelayOwnable, IsYLAYRewards {
    /* ========== STRUCTS ========== */

    /**
     * @notice Defines amount of emitted rewards per tranche for a range of tranches
     * @member fromTranche marks first tranche the reward rate is valid for
     * @member toTranche marks tranche index when the reward becomes invalid (when `toTranche` is reached, the configuration is no more valid)
     * @member rewardPerTranche amount of emitted rewards per tranche
     */
    struct sYLAYRewardRate {
        uint8 fromTranche;
        uint8 toTranche;
        uint112 rewardPerTranche; // rewards per tranche
    }

    /**
     * @notice struct solding two sYLAYRewardRate structs
     * @dev made to pack multiple structs in one word
     * @member zero sYLAYRewardRate at position 0
     * @member one sYLAYRewardRate at position 1
     */
    struct sYLAYRewardRates {
        sYLAYRewardRate zero;
        sYLAYRewardRate one;
    }

    /**
     * @notice sYLAY reward state for user
     * @member lastRewardRateIndex last reward rate index user has used (refers to sYLAYRewardConfiguration.sYlayRewardRates mapping and sYLAYRewardRates index)
     * @member earned total rewards user has accumulated
     */
    struct sYLAYRewardUser {
        uint8 lastRewardRateIndex;
        uint248 earned;
    }

    /**
     * @notice sYLAY reward configuration
     * @member rewardRatesIndex last set reward rate index for sYlayRewardRates mapping (acts similar to an array length parameter)
     * @member hasRewards flag marking if the contract is emitting rewards for new tranches
     * @member lastSetRewardTranche last reward tranche index we've set the congiguration for
     */
    struct sYLAYRewardConfiguration {
        uint240 rewardRatesIndex;
        bool hasRewards;
        uint8 lastSetRewardTranche;
    }

    /* ========== CONSTANTS ========== */

    /// @notice amount of tranches to mature to full power
    uint256 private constant FULL_POWER_TRANCHES_COUNT = 52 * 4;

    /// @notice number of tranche amounts stored in one 256bit word
    uint256 private constant TRANCHES_PER_WORD = 5;

    /* ========== STATE VARIABLES ========== */

    /// @notice Yelay staking contract
    /// @dev Controller of this contract
    address public immutable yelayStaking;

    /// @notice sYLAY Voting Token (sYLAY) implementation
    IsYLAYBase public immutable sYlay;

    /// @notice Vault reward token incentive configuration
    sYLAYRewardConfiguration public sYlayRewardConfig;

    /// @notice Reward of YLAY token distribution per tranche
    /// @dev We save all reward updates so we can apply it to a user even if the configuration changes after
    mapping(uint256 => sYLAYRewardRates) public sYlayRewardRates;

    /// @notice Stores values for user rewards
    mapping(address => sYLAYRewardUser) public userRewards;

    /// @notice Stores values for global gradual sYLAY power for every tranche
    /// @dev Only stores if the reward is active. We store 5 values per word.
    mapping(uint256 => uint256) private _tranchePowers;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Sets the immutable values
     *
     * @param _yelayStaking Yelay staking contract
     * @param _sYlay sYLAY contract
     * @param _yelayOwner sYLAY owner contract
     */
    constructor(address _yelayStaking, address _sYlay, address _yelayOwner) YelayOwnable(IYelayOwner(_yelayOwner)) {
        yelayStaking = _yelayStaking;
        sYlay = IsYLAYBase(_sYlay);
    }

    /* ========== REWARD CONFIGURATION ========== */

    /**
     * @notice Update YLAY rewards distributed relative to sYLAY power
     * @dev We distribute `rewardPerTranche` rewards every tranche up to `toTranche` index
     *
     * Requirements:
     *
     * - the caller must be the sYLAY
     * - reward per tranche must be more than 0
     * - last reward shouldn't be set after first gradual power starts maturing
     * - reward must be set for the future tranches
     *
     * @param toTranche update to `toTranche` index
     * @param rewardPerTranche amount of YLAY token rewards distributed every tranche
     */
    function updatesYLAYRewardRate(uint8 toTranche, uint112 rewardPerTranche) external onlyOwner {
        require(rewardPerTranche > 0, "sYLAYRewards::updatesYLAYRewardRate: Cannot update reward rate to 0");
        // cannot add rewards after first tranche is fully-matured (3 years)
        require(
            toTranche <= FULL_POWER_TRANCHES_COUNT,
            "sYLAYRewards::updatesYLAYRewardRate: Cannot set rewards after power starts maturing"
        );

        uint8 currentTrancheIndex = uint8(sYlay.getCurrentTrancheIndex());
        require(
            toTranche > currentTrancheIndex,
            "sYLAYRewards::updatesYLAYRewardRate: Cannot set rewards for finished tranches"
        );

        uint256 rewardRatesIndex = sYlayRewardConfig.rewardRatesIndex;

        sYLAYRewardRate memory sYlayRewardRate = sYLAYRewardRate(currentTrancheIndex, toTranche, rewardPerTranche);

        if (rewardRatesIndex == 0) {
            sYlayRewardRates[0].one = sYlayRewardRate;
            rewardRatesIndex = 1;
        } else {
            sYLAYRewardRate storage previousRewardRate = _getRewardRate(rewardRatesIndex);

            // update previous reward rate if still active to end at current index
            if (previousRewardRate.toTranche > currentTrancheIndex) {
                // if current rewards did not start yet, overwrite them and return
                if (previousRewardRate.fromTranche == currentTrancheIndex) {
                    _setRewardRate(sYlayRewardRate, rewardRatesIndex);
                    sYlayRewardConfig = sYLAYRewardConfiguration(uint240(rewardRatesIndex), true, toTranche);
                    return;
                }

                previousRewardRate.toTranche = currentTrancheIndex;
            }

            unchecked {
                rewardRatesIndex++;
            }

            // set the new reward rate
            _setRewardRate(sYlayRewardRate, rewardRatesIndex);
        }

        // store update to reward configuration
        sYlayRewardConfig = sYLAYRewardConfiguration(uint240(rewardRatesIndex), true, toTranche);

        emit RewardRateUpdated(sYlayRewardRate.fromTranche, sYlayRewardRate.toTranche, sYlayRewardRate.rewardPerTranche);
    }

    /**
     * @notice End YLAY rewards at current index
     * @dev
     *
     * Requirements:
     *
     * - the caller must be the sYLAY
     * - reward must be active
     */
    function endsYLAYReward() external onlyOwner {
        uint8 currentTrancheIndex = uint8(sYlay.getCurrentTrancheIndex());
        uint256 rewardRatesIndex = sYlayRewardConfig.rewardRatesIndex;

        require(rewardRatesIndex > 0, "sYLAYRewards::endsYLAYReward: No rewards configured");

        sYLAYRewardRate storage currentRewardRate = _getRewardRate(rewardRatesIndex);

        require(
            currentRewardRate.toTranche > currentTrancheIndex, "sYLAYRewards::endsYLAYReward: Rewards already ended"
        );

        emit RewardEnded(
            rewardRatesIndex, currentRewardRate.fromTranche, currentRewardRate.toTranche, currentTrancheIndex
        );

        // if current rewards did not start yet, remove them
        if (currentRewardRate.fromTranche == currentTrancheIndex) {
            _resetRewardRate(rewardRatesIndex);
            unchecked {
                rewardRatesIndex--;
            }

            if (rewardRatesIndex == 0) {
                sYlayRewardConfig = sYLAYRewardConfiguration(0, false, 0);
                return;
            }
        } else {
            currentRewardRate.toTranche = currentTrancheIndex;
        }

        sYlayRewardConfig = sYLAYRewardConfiguration(uint240(rewardRatesIndex), false, currentTrancheIndex);
    }

    /* ========== REWARD UPDATES ========== */

    /**
     * @notice Return user rewards earned value and reset it to 0.
     * @dev
     * The rewards are then processed by the Yelay staking contract.
     *
     * Requirements:
     *
     * - the caller must be the Yelay staking contract
     *
     * @param user User to flush
     */
    function flushRewards(address user) external override onlyYelayStaking returns (uint256) {
        uint256 userEarned = userRewards[user].earned;
        if (userEarned > 0) {
            userRewards[user].earned = 0;
        }

        return userEarned;
    }

    /**
     * @notice Update rewards for a user.
     * @dev
     * This has to be called before we update the gradual power storage in
     * the sYLAY contract for the contract to work as indended.
     * We update the global values if new indexes have passed between our last call.
     *
     * Requirements:
     *
     * - the caller must be the Yelay staking contract
     *
     * @param user User to update
     */
    function updateRewards(address user) external override onlyYelayStaking returns (uint256) {
        if (sYlayRewardConfig.rewardRatesIndex == 0) return 0;

        // if rewards are not active do not the gradual amounts
        if (sYlayRewardConfig.hasRewards) {
            _storesYlayForNewIndexes();
        }

        _updateUsersYlayRewards(user);

        return userRewards[user].earned;
    }

    /**
     * @notice Store total gradual sYLAY amount for every new tranche index since last call.
     * @dev
     * This function assumes that the sYLAY state has not been
     * updated prior to calling this function.
     *
     * We retrieve the not updated state from sYLAY contract, simulate
     * gradual increase of shares for every new tranche and store the
     * value for later use.
     */
    function _storesYlayForNewIndexes() private {
        // check if there are any active rewards
        uint256 lastFinishedTrancheIndex = sYlay.getLastFinishedTrancheIndex();
        IsYLAYBase.GlobalGradual memory global = sYlay.getNotUpdatedGlobalGradual();

        // return if no new indexes passed
        if (global.lastUpdatedTrancheIndex >= lastFinishedTrancheIndex) {
            return;
        }

        uint256 lastSetRewardTranche = sYlayRewardConfig.lastSetRewardTranche;
        uint256 trancheIndex = global.lastUpdatedTrancheIndex;
        do {
            // if there are no more rewards return as we don't need to store anything
            if (trancheIndex >= lastSetRewardTranche) {
                // update config hasRewards to false if rewards are not active
                sYlayRewardConfig.hasRewards = false;
                return;
            }

            trancheIndex++;

            global.totalRawUnmaturedVotingPower += global.totalMaturingAmount;

            // store gradual power for `trancheIndex` to `_tranchePowers`
            _storeTranchePowerForIndex(
                _getMaturingVotingPowerFromRaw(global.totalRawUnmaturedVotingPower), trancheIndex
            );
        } while (trancheIndex < lastFinishedTrancheIndex);
    }

    /**
     * @notice Update user reward earnings for every new tranche index since the last update
     * @dev
     * This function assumes that the sYLAY state has not been
     * updated prior to calling this function.
     *
     * _storesYlayForNewIndexes function should be called before
     * to store the global state.
     *
     * We use very similar techniques as sYLAY to calculate
     * user gradual voting power for every index
     */
    function _updateUsersYlayRewards(address user) private {
        IsYLAYBase.UserGradual memory userGradual = sYlay.getNotUpdatedUserGradual(user);
        if (userGradual.maturingAmount == 0) {
            userRewards[user].lastRewardRateIndex = uint8(sYlayRewardConfig.rewardRatesIndex);
            return;
        }

        uint256 lastFinishedTrancheIndex = sYlay.getLastFinishedTrancheIndex();
        uint256 trancheIndex = userGradual.lastUpdatedTrancheIndex;

        // update user if tranche indexes have passed since last user update
        if (trancheIndex < lastFinishedTrancheIndex) {
            sYLAYRewardUser memory sYlayRewardUser = userRewards[user];

            // map the configured reward rates since last time we used it
            sYLAYRewardRate[] memory sYlayRewardRatesArray =
                _getRewardRatesForIndex(sYlayRewardUser.lastRewardRateIndex);

            // `sYlayRewardRatesArray` array index we're currently using
            // to retrieve the reward rate belonging to `trancheIndex`
            // when we reach `rewardRate.toTranche`, we increment `vsrrI`,
            // and use the updated reward rate to store the reward for
            // the corresponding index.
            uint256 vsrrI = 0;
            sYLAYRewardRate memory rewardRate = sYlayRewardRatesArray[0];

            do {
                unchecked {
                    trancheIndex++;
                }

                // if current reward rate is not valid anymore try getting the next one
                if (trancheIndex >= rewardRate.toTranche) {
                    unchecked {
                        vsrrI++;
                    }

                    // check if we reached last element in the array
                    if (vsrrI < sYlayRewardRatesArray.length) {
                        rewardRate = sYlayRewardRatesArray[vsrrI];
                    } else {
                        // if last tranche in an array, there are no more configured rewards
                        // break the loop to save on gas
                        break;
                    }
                }

                // add user maturingAmount for every index
                userGradual.rawUnmaturedVotingPower += userGradual.maturingAmount;

                if (trancheIndex >= rewardRate.fromTranche) {
                    // get actual voting power from raw unmatured voting power
                    uint256 userPower = _getMaturingVotingPowerFromRaw(userGradual.rawUnmaturedVotingPower);

                    // get tranche power for `trancheIndex`
                    // we stored it when callint _storesYlayForNewIndexes function
                    uint256 tranchePowerAtIndex = getTranchePower(trancheIndex);

                    // calculate users earned rewards for index based on
                    // 1. reward rate for `trancheIndex`
                    // 2. user power for `trancheIndex`
                    // 3. global tranche power for `trancheIndex`
                    if (tranchePowerAtIndex > 0) {
                        sYlayRewardUser.earned +=
                            uint248((rewardRate.rewardPerTranche * userPower) / tranchePowerAtIndex);
                    }
                }

                // update rewards until we reach last finished tranche index
            } while (trancheIndex < lastFinishedTrancheIndex);

            // store the updated user value
            sYlayRewardUser.lastRewardRateIndex = uint8(sYlayRewardConfig.rewardRatesIndex);
            userRewards[user] = sYlayRewardUser;

            emit UserRewardUpdated(user, sYlayRewardUser.lastRewardRateIndex, sYlayRewardUser.earned);
        }
    }

    /* ========== HELPERS ========== */

    /**
     * @notice Store the new reward rate to `sYlayRewardRates` mapping
     *
     * @param sYlayRewardRate struct to store
     * @param rewardRatesIndex reward rates intex to use when storing the `sYlayRewardRate`
     */
    function _setRewardRate(sYLAYRewardRate memory sYlayRewardRate, uint256 rewardRatesIndex) private {
        uint256 arrayIndex = rewardRatesIndex / 2;
        uint256 position = rewardRatesIndex % 2;

        if (position == 0) {
            sYlayRewardRates[arrayIndex].zero = sYlayRewardRate;
        } else {
            sYlayRewardRates[arrayIndex].one = sYlayRewardRate;
        }
    }

    /**
     * @notice Reset the storage the `sYlayRewardRates` for `rewardRatesIndex` index
     *
     * @param rewardRatesIndex index to reset the storage for
     */
    function _resetRewardRate(uint256 rewardRatesIndex) private {
        _setRewardRate(sYLAYRewardRate(0, 0, 0), rewardRatesIndex);
    }

    /**
     * @notice Retrieve the reward rate for index from storage
     *
     * @param rewardRatesIndex index to retrieve for
     * @return sYlayRewardRate storage pointer to the desired reward rate struct
     */
    function _getRewardRate(uint256 rewardRatesIndex) private view returns (sYLAYRewardRate storage) {
        uint256 arrayIndex = rewardRatesIndex / 2;
        uint256 position = rewardRatesIndex % 2;

        if (position == 0) {
            return sYlayRewardRates[arrayIndex].zero;
        } else {
            return sYlayRewardRates[arrayIndex].one;
        }
    }

    /**
     * @notice Returns all reward rates in an array between last user update and now
     * @dev Returns an array for simpler access when updating user reward rates for indexes
     *
     * @param userLastRewardRateIndex last index user updated
     * @return sYlayRewardRatesArray memory array of reward rates
     */
    function _getRewardRatesForIndex(uint256 userLastRewardRateIndex) private view returns (sYLAYRewardRate[] memory) {
        if (userLastRewardRateIndex == 0) userLastRewardRateIndex = 1;

        uint256 lastRewardRateIndex = sYlayRewardConfig.rewardRatesIndex;
        uint256 newRewardRatesCount = lastRewardRateIndex - userLastRewardRateIndex + 1;
        sYLAYRewardRate[] memory sYlayRewardRatesArray = new sYLAYRewardRate[](newRewardRatesCount);

        uint256 j = 0;
        for (uint256 i = userLastRewardRateIndex; i <= lastRewardRateIndex; i++) {
            sYlayRewardRatesArray[j] = _getRewardRate(i);
            unchecked {
                j++;
            }
        }

        return sYlayRewardRatesArray;
    }

    /**
     * @notice Store global gradual tranche `power` at tranche `index`
     * @dev
     * We know the `power` is always represented with 48bits or less.
     * We use this information to store 5 `power` values of consecutive
     * indexes per word.
     *
     * @param power global gradual tranche power at `index`
     * @param index tranche index at which to store
     */
    function _storeTranchePowerForIndex(uint256 power, uint256 index) private {
        uint256 arrayindex = index / TRANCHES_PER_WORD;

        uint256 globalTranchesPosition = index % TRANCHES_PER_WORD;

        if (globalTranchesPosition == 1) {
            power = power << 48;
        } else if (globalTranchesPosition == 2) {
            power = power << 96;
        } else if (globalTranchesPosition == 3) {
            power = power << 144;
        } else if (globalTranchesPosition == 4) {
            power = power << 192;
        }

        unchecked {
            _tranchePowers[arrayindex] += power;
        }
    }

    /**
     * @notice Retrieve global gradual tranche power at `index`
     * @dev Same, but reversed, mechanism is used to retrieve the power at index
     *
     * @param index tranche index at which to retrieve the power value
     * @return power global gradual tranche power at `index`
     */
    function getTranchePower(uint256 index) public view returns (uint256) {
        uint256 arrayindex = index / TRANCHES_PER_WORD;

        uint256 powers = _tranchePowers[arrayindex];

        uint256 globalTranchesPosition = index % TRANCHES_PER_WORD;

        if (globalTranchesPosition == 0) {
            return (powers << 208) >> 208;
        } else if (globalTranchesPosition == 1) {
            return (powers << 160) >> 208;
        } else if (globalTranchesPosition == 2) {
            return (powers << 112) >> 208;
        } else if (globalTranchesPosition == 3) {
            return (powers << 64) >> 208;
        } else {
            return (powers << 16) >> 208;
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

    /* ========== RESTRICTION FUNCTIONS ========== */

    /**
     * @dev Ensures the caller is the YLAY Staking contract
     */
    function _onlyYelayStaking() private view {
        require(msg.sender == yelayStaking, "sYLAYRewards::_onlyYelayStaking: Insufficient Privileges");
    }

    /* ========== MODIFIERS ========== */

    /**
     * @dev Throws if the caller is not the YLAY Staking contract
     */
    modifier onlyYelayStaking() {
        _onlyYelayStaking();
        _;
    }
}
