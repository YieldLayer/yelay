// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IYelayStakingBase.sol";

interface IYelayStakingPostMigration is IYelayStakingBase {
    event LockedTranche(address indexed user, uint256 amount, uint256 deadline);

    event Locked(address indexed user, uint256 amount, uint256 deadline);
}
