// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IYelayOwner {
    function isYelayOwner(address user) external view returns (bool);
}
