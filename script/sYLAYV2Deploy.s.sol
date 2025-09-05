// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {Environment} from "./helpers.sol";

import {sYLAY} from "src/sYLAY.sol";
import {IYelayOwner} from "src/interfaces/IYelayOwner.sol";

/**
 *  source .env && FOUNDRY_PROFILE=mainnet forge script script/sYLAYV2Deploy.s.sol:sYLAYV2Deploy --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 */
contract sYLAYV2Deploy is Script {
    function run() external {
        Environment.setRpc(vm);

        vm.startBroadcast(Environment.getPrivateKey(vm));
        sYLAY sylay = new sYLAY(IYelayOwner(0xAB865D95A574511a6c893C38A4D892275ca70570));
        vm.stopBroadcast();

        console.log("sYLAY V2", address(sylay));
    }
}
