// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IYLAY {
    /**
     * @notice Claims YLAY tokens for a claimant.
     * @param claimant The address of the claimant.
     * @param amount The amount of YLAY tokens to transfer to the claimant.
     */
    function claim(address claimant, uint256 amount) external;

    /**
     * @notice Pauses all token transfers.
     * @dev Only callable by the contract owner.
     */
    function pause() external;

    /**
     * @notice Unpauses all token transfers.
     * @dev Only callable by the contract owner.
     */
    function unpause() external;
}
