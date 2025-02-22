// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IERC20PausableOwnable is IERC20 {
    function paused() external view returns (bool);
    function owner() external view returns (address);
}
