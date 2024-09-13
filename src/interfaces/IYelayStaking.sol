// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "spool-staking-and-voting/interfaces/ISpoolStaking.sol";

interface IYelayStaking is ISpoolStaking {
    function transferUser(address from, address to) external;
    function migrateUser(address user) external returns(uint256 yelayStaked, uint256 yelayRewards);
}
