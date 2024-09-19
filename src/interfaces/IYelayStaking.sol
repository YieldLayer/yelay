// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IYelayStakingBase.sol";

interface IYelayStaking is IYelayStakingBase {
    function transferUser(address from, address to) external;
    function migrateUser(address user) external returns (uint256 yelayStaked, uint256 yelayRewards);
}
