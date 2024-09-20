// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "src/YLAY.sol";
import "src/interfaces/IYelayOwner.sol";

contract YLAY2 is YLAY {
    constructor(IYelayOwner _yelayOwner, address _migrator) YLAY(_yelayOwner, _migrator) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}
