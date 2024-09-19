// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/IYelayOwner.sol";

abstract contract YelayOwnable {
    IYelayOwner internal immutable yelayOwner;

    constructor(IYelayOwner _yelayOwner) {
        require(
            address(_yelayOwner) != address(0), "YelayOwnable::constructor: Yelay owner contract address cannot be 0"
        );

        yelayOwner = _yelayOwner;
    }

    function isYelayOwner() internal view returns (bool) {
        return yelayOwner.isYelayOwner(msg.sender);
    }

    modifier onlyOwner() {
        require(isYelayOwner(), "YelayOwnable::onlyOwner: Caller is not the Yelay owner");
        _;
    }
}
