// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IsYLAYBase.sol";

interface IsYLAY is IsYLAYBase {
    function transferUser(address from, address to) external;
    function migrateInitial() external;
    function migrateUser(address user) external;
    function migrateGlobalTranches(uint256 endIndex) external;
}
