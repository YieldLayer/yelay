// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract YLAYArbitrumMigration {
    using SafeERC20 for IERC20;

    IERC20 public constant SPOOL = IERC20(0xECA14F81085e5B8d1c9D32Dcb596681574723561);

    event Lock(address indexed sender, address indexed receiver, uint256 amount);

    function lock(address receiver, uint256 amount) external {
        SPOOL.safeTransferFrom(msg.sender, address(this), amount);
        emit Lock(msg.sender, receiver, amount);
    }
}
