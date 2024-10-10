// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import {JsonReadWriter, Environment} from "./helpers.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {YLAYArbitrumMigration} from "src/YLAYArbitrumMigration.sol";

/**
 *  source .env && FOUNDRY_PROFILE=arbitrum-tenderly forge script script/YLAYArbitrumMigrationDeploy.s.sol:YLAYArbitrumMigrationDeploy --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract YLAYArbitrumMigrationDeploy is Script {
    function run() external {
        Environment.setRpc(vm);

        JsonReadWriter json = new JsonReadWriter(vm, Environment.getContractsPath(vm));

        vm.startBroadcast(Environment.getPrivateKey(vm));

        address implementation = address(new YLAYArbitrumMigration());
        address proxy = address(new TransparentUpgradeableProxy(implementation, json.getAddress(".ProxyAdmin"), ""));

        vm.stopBroadcast();

        json.addProxy("YLAYArbitrumMigration", implementation, proxy);
    }
}
