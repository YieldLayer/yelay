// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import {JsonReadWriter, Environment} from "./helpers.sol";

import {YelayOwner} from "src/YelayOwner.sol";

/**
 *  source .env && FOUNDRY_PROFILE=local forge script script/YelayOwnerDeploy.s.sol:YelayOwnerDeploy --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract YelayOwnerDeploy is Script {
    function run() external {
        Environment.setRpc(vm);

        JsonReadWriter json = new JsonReadWriter(vm, Environment.getContractsPath(vm));

        vm.startBroadcast(Environment.getPrivateKey(vm));
        YelayOwner yelayOwner = new YelayOwner();
        yelayOwner.transferOwnership(json.getAddress(".yelayMultisig"));
        vm.stopBroadcast();

        json.add("YelayOwner", address(yelayOwner));
    }
}
