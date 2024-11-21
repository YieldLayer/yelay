// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./migration/IYelayStakingBase.sol";

interface IYelayStaking is IYelayStakingBase {
    event LockedTranche(address indexed user, uint256 trimmedAmount, uint256 deadline);

    event Locked(address indexed user, uint256 amount, uint256 deadline);

    event CanLockForSet(address indexed account, bool canLockFor);
}
