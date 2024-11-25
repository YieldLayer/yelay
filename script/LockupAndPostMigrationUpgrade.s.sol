// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {JsonReadWriter, Environment} from "./helpers.sol";

import {IYelayOwner} from "src/YelayOwner.sol";
import {YelayStaking} from "src/YelayStaking.sol";
import {sYLAY} from "src/sYLAY.sol";

/**
 *  source .env && FOUNDRY_PROFILE=mainnet forge script LockupAndPostMigrationUpgrade --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 */
contract LockupAndPostMigrationUpgrade is Script {
    function run() external {
        Environment.setRpc(vm);

        JsonReadWriter json = new JsonReadWriter(vm, Environment.getContractsPath(vm));

        address yelayStaking_proxy = json.getAddress(".YelayStaking.proxy");
        address sYlay_proxy = json.getAddress(".sYLAY.proxy");
        IYelayOwner yelayOwner = IYelayOwner(json.getAddress(".YelayOwner"));

        vm.startBroadcast(Environment.getPrivateKey(vm));
        // deploy new implementations
        address yelayStaking_implementation = address(
            new YelayStaking(
                json.getAddress(".YLAY.proxy"),
                sYlay_proxy,
                json.getAddress(".sYLAYRewards.proxy"),
                json.getAddress(".YelayRewardsDistributor.proxy"),
                address(yelayOwner)
            )
        );
        address sYlay_implementation = address(new sYLAY(yelayOwner));
        vm.stopBroadcast();

        // update JSON
        json.addProxy("YelayStaking", yelayStaking_implementation, yelayStaking_proxy);
        json.addProxy("sYLAY", sYlay_implementation, sYlay_proxy);

        // Finally, upgrade on proxies (Performed by multisig): proxyAdmin.upgrade(proxy, implementation) for both
    }
}
