// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "spool/SpoolStaking.sol";

contract SpoolStaking2 is SpoolStaking {
    constructor(
        address _stakingToken,
        address _voSpool,
        address _voSpoolRewards,
        address _rewardDistributor,
        address _spoolOwner
    )
        SpoolStaking(
            IERC20(_stakingToken),
            IVoSPOOL(_voSpool),
            IVoSpoolRewards(_voSpoolRewards),
            IRewardDistributor(_rewardDistributor),
            ISpoolOwner(_spoolOwner)
        )
    {}

    // TODO: is it ok to leave it without access control?
    function getUpdatedVoSpoolRewardAmount(address user) external returns (uint256 rewards) {
        // update rewards
        rewards = voSpoolRewards.updateRewards(user);
        // update and store users voSPOOL
        voSpool.updateUserVotingPower(user);
    }
}
