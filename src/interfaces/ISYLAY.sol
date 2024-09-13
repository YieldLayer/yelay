// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "src/external/spool-staking-and-voting/interfaces/IVoSPOOL.sol";

interface ISYLAY is IVoSPOOL {
    function transferUser(address from, address to) external;
    function migrateUser(address user) external;
    function migrateGlobalTranches(uint256 endIndex) external;
}
