// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import {JsonReadWriter} from "./helpers.sol";

import {SpoolStakingMigration} from "src/upgrade/SpoolStakingMigration.sol";

/**
 *  source .env && forge script script/SpoolStakingUpgrade.s.sol:SpoolStakingUpgrade --rpc-url=$MAINNET_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract SpoolStakingUpgrade is Script {
    function run() external {
        JsonReadWriter json = new JsonReadWriter(vm, "deployment/mainnet.json");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address spoolStakingImplementation = address(
            // TODO: double check all addresses!
            new SpoolStakingMigration(
                json.getAddress(".SPOOL"),
                json.getAddress(".voSpool"),
                json.getAddress(".voSpoolRewards"),
                json.getAddress(".RewardsDistributor"),
                json.getAddress(".SpoolOwner")
            )
        );
        vm.stopBroadcast();

        json.add("SpoolStakingMigrationImplementation", spoolStakingImplementation);
    }
}
