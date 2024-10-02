// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import {JsonReadWriter} from "./helpers.sol";

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {YelayOwner} from "src/YelayOwner.sol";
import {YLAY} from "src/YLAY.sol";

/**
 *  source .env && forge script script/YLAYInitialDeploy.s.sol:YLAYInitialDeploy --rpc-url=$MAINNET_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract YLAYInitialDeploy is Script {
    function run() external {
        JsonReadWriter json = new JsonReadWriter(vm, "deployment/mainnet.json");

        YelayOwner yelayOwner = YelayOwner(json.getAddress(".YelayOwner"));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address ylayImpl = address(new YLAY(yelayOwner, address(0)));
        address ylay = address(new ERC1967Proxy(ylayImpl, ""));

        vm.stopBroadcast();

        json.addProxy("YLAY", ylayImpl, ylay);
    }
}
