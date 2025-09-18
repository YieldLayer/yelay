// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import {JsonReadWriter, Environment} from "./helpers.sol";

import {YelayStaking} from "src/YelayStaking.sol";
import {sYLAY} from "src/sYLAY.sol";
import {IYelayOwner} from "src/interfaces/IYelayOwner.sol";

/**
 *  source .env && FOUNDRY_PROFILE=mainnet forge script script/TransferUserRemovalUpgrade.s.sol:TransferUserRemovalUpgrade --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 */
contract TransferUserRemovalUpgrade is Script {
    function run() external {
        Environment.setRpc(vm);

        JsonReadWriter json = new JsonReadWriter(vm, Environment.getContractsPath(vm));

        vm.startBroadcast(Environment.getPrivateKey(vm));
        YelayStaking yelayStaking = new YelayStaking(
            json.getAddress(".YLAY.proxy"),
            json.getAddress(".sYLAY.proxy"),
            json.getAddress(".sYLAYRewards.proxy"),
            json.getAddress(".YelayRewardsDistributor.proxy"),
            json.getAddress(".YelayOwner")
        );
        sYLAY sylay = new sYLAY(IYelayOwner(json.getAddress(".YelayOwner")));
        vm.stopBroadcast();

        json.addProxy("YelayStaking", address(sylay), json.getAddress(".YelayStaking.proxy"));
        json.addProxy("sYLAY", address(yelayStaking), json.getAddress(".sYLAY.proxy"));
    }
}
