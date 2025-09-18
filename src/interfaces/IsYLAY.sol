// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./migration/IsYLAYBase.sol";

/**
 * @title Staked YLAY interface
 */
interface IsYLAY is IsYLAYBase {
    function migrateToLockup(address to, UserTranchePosition memory userTranchePosition, uint256 lockTranches)
        external
        returns (uint256 amount);

    function mintLockup(address to, uint256 amount, uint256 lockTranches) external returns (uint256);

    function continueLockup(uint256 lockTranche, uint256 numTranches) external;

    function burnLockups(address to) external returns (uint256 amount);

    event TrancheMigration(address indexed user, uint256 amount, uint256 index, uint256 rawUnmaturedVotingPower);

    event LockupMinted(address indexed to, uint256 amount, uint256 power, uint256 startTranche, uint256 endTranche);

    event LockupBurned(address indexed to, uint256 lockTranche);

    event LockupContinued(address indexed to, uint256 lockTranche, uint256 addedPower, uint256 endTranche);

    event UserTransferred(address indexed from, address indexed to);
}
