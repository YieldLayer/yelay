// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import {JsonReadWriter, Environment} from "./helpers.sol";

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {YelayOwner} from "src/YelayOwner.sol";
import {YLAY} from "src/YLAY.sol";

/**
 *  source .env && FOUNDRY_PROFILE=local forge script script/YLAYInitialDeploy.s.sol:YLAYInitialDeploy --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract YLAYInitialDeploy is Script {
    function run() external {
        Environment.setRpc(vm);

        JsonReadWriter json = new JsonReadWriter(vm, Environment.getContractsPath(vm));

        YelayOwner yelayOwner = YelayOwner(json.getAddress(".YelayOwner"));

        vm.startBroadcast(Environment.getPrivateKey(vm));

        address ylayImpl = address(new YLAY(yelayOwner, address(0)));
        address ylay = address(new ERC1967Proxy(ylayImpl, ""));
        YLAY(ylay).initialize();

        vm.stopBroadcast();

        json.addProxy("YLAY", ylayImpl, ylay);
    }
}
