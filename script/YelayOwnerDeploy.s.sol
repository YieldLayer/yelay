// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import {JsonReadWriter} from "./helpers.sol";

import {YelayOwner} from "src/YelayOwner.sol";

/**
 *  source .env && forge script script/YelayOwnerDeploy.s.sol:YelayOwnerDeploy --rpc-url=$MAINNET_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract YelayOwnerDeploy is Script {
    function run() external {
        JsonReadWriter json = new JsonReadWriter(vm, "deployment/mainnet.json");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        YelayOwner yelayOwner = new YelayOwner();
        vm.stopBroadcast();

        json.add("YelayOwner", address(yelayOwner));
    }
}
