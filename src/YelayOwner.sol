// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./interfaces/IYelayOwner.sol";
import "openzeppelin-contracts/access/Ownable.sol";

/**
 * @notice Implementation of the {IYelayOwner} interface.
 *
 * @dev
 * This implementation acts as a simple central Yelay owner oracle.
 * All Yelay contracts should refer to this contract to check the owner of the Yelay.
 */
contract YelayOwner is IYelayOwner, Ownable {
    /* ========== VIEWS ========== */

    /**
     * @notice checks if input is the yelay owner contract.
     *
     * @param user the address to check
     *
     * @return isOwner returns true if user is the Yelay owner, else returns false.
     */
    function isYelayOwner(address user) external view override returns (bool isOwner) {
        if (user == owner()) {
            isOwner = true;
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice removed renounceOwnership function
     *
     * @dev
     * overrides OpenZeppelin renounceOwnership() function and reverts in all cases,
     * as Yelay ownership should never be renounced.
     */
    function renounceOwnership() public view override onlyOwner {
        revert("YelayOwner::renounceOwnership: Cannot renounce Yelay ownership");
    }
}
