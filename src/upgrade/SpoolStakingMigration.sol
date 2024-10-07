// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./SpoolStaking.sol";

contract SpoolStakingMigration is SpoolStaking {
    bool public stakingAllowed;

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

    function setStakingAllowed(bool value) external onlyOwner {
        stakingAllowed = value;
    }

    function stake(uint256 amount) public override {
        require(stakingAllowed, "SpoolStaking::stake staking is not allowed");
        super.stake(amount);
    }

    function stakeFor(address account, uint256 amount) public override {
        require(stakingAllowed, "SpoolStaking::stake staking is not allowed");
        super.stakeFor(account, amount);
    }

    function getUpdatedVoSpoolRewardAmount(address user) external returns (uint256 rewards) {
        // update rewards
        rewards = voSpoolRewards.updateRewards(user);
        // update and store users voSPOOL
        voSpool.updateUserVotingPower(user);
    }
}
