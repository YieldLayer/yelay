// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "spool-staking-and-voting/VoSpoolRewards.sol";
import "src/interfaces/IsYLAYRewards.sol";

contract sYLAYRewards is VoSpoolRewards, IsYLAYRewards {
    /// @notice amount of tranches to mature to full power
    uint256 private constant FULL_POWER_TRANCHES_COUNT_YELAY = 52 * 4;

    constructor(address _spoolOwner, address _sYLAY, address _yelayStaking)
        VoSpoolRewards(_yelayStaking, IVoSPOOL(_sYLAY), ISpoolOwner(_spoolOwner), FULL_POWER_TRANCHES_COUNT_YELAY)
    {}
}
