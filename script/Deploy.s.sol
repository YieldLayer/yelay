// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Script} from "forge-std/Script.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {JsonReadWriter} from "./helpers.sol";

import {YLAY} from "src/YLAY.sol";
import {YelayOwner, IYelayOwner} from "src/YelayOwner.sol";
import {sYLAY, IsYLAY} from "src/sYLAY.sol";
import {sYLAYRewards} from "src/sYLAYRewards.sol";
import {YelayMigrator} from "src/YelayMigrator.sol";
import {YelayStaking} from "src/YelayStaking.sol";
import {YelayRewardDistributor} from "src/YelayRewardDistributor.sol";
import {ConversionLib} from "src/libraries/ConversionLib.sol";

/**
 *  source .env && forge script script/Deploy.s.sol:Deploy --rpc-url=$MAINNET_RPC_URL --with-gas-price 2000000000 --slow --broadcast --legacy --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract Deploy is Script {
    address deployerAddress;

    YelayOwner yelayOwner;
    address proxyAdmin;
    address spool;
    address spoolStaking;
    address voSpool;

    YLAY ylay;

    struct Args {
        address sYlayRewardsImpl;
        address sYlayRewardsAddr;
        address yelayMigratorImpl;
        address yelayMigratorAddr;
        address yelayStakingImpl;
        address yelayStakingAddr;
        address sYlayImpl;
        address sYlayAddr;
        address yelayRewardDistributorImpl;
        address yelayRewardDistributorAddr;
    }

    function run() external {
        deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY"));

        JsonReadWriter json = new JsonReadWriter(vm, "deployment/mainnet.json");

        yelayOwner = YelayOwner(json.getAddress(".YelayOwner"));
        proxyAdmin = json.getAddress(".ProxyAdmin");
        spool = json.getAddress(".SPOOL");
        spoolStaking = json.getAddress(".SpoolStaking");
        voSpool = json.getAddress(".voSpool");
        ylay = YLAY(json.getAddress(".YLAY.proxy"));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        Args memory args = Args(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );

        args.sYlayRewardsImpl = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress));
        args.sYlayRewardsAddr = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 1);
        args.yelayMigratorImpl = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 2);
        args.yelayMigratorAddr = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 3);
        args.yelayStakingImpl = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 4);
        args.yelayStakingAddr = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 5);
        args.sYlayImpl = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 6);
        args.sYlayAddr = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 7);
        args.yelayRewardDistributorImpl = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 8);
        args.yelayRewardDistributorAddr = vm.computeCreateAddress(deployerAddress, vm.getNonce(deployerAddress) + 9);

        {
            new sYLAYRewards(args.yelayStakingAddr, address(args.sYlayAddr), address(yelayOwner));
            address sYlayRewards = address(new TransparentUpgradeableProxy(args.sYlayRewardsImpl, proxyAdmin, ""));
            assert(sYlayRewards == args.sYlayRewardsAddr);
        }

        new YelayMigrator(address(yelayOwner), ylay, IsYLAY(args.sYlayAddr), args.yelayStakingAddr, spool);
        address yelayMigrator = address(new TransparentUpgradeableProxy(args.yelayMigratorImpl, proxyAdmin, ""));
        assert(
            ProxyAdmin(proxyAdmin).getProxyImplementation(TransparentUpgradeableProxy(payable(yelayMigrator)))
                == args.yelayMigratorImpl
        );
        assert(address(yelayMigrator) == args.yelayMigratorAddr);
        assert(address(YelayMigrator(yelayMigrator).SPOOL()) == spool);

        new YelayStaking(
            address(yelayOwner),
            address(ylay),
            address(args.sYlayAddr),
            address(args.sYlayRewardsAddr),
            args.yelayRewardDistributorAddr,
            spoolStaking,
            args.yelayMigratorAddr
        );
        YelayStaking yelayStaking =
            YelayStaking(address(new TransparentUpgradeableProxy(args.yelayStakingImpl, address(proxyAdmin), "")));
        assert(address(yelayStaking) == args.yelayStakingAddr);
        assert(address(yelayStaking.migrator()) == address(yelayMigrator));

        new sYLAY(address(yelayOwner), voSpool, args.yelayMigratorAddr);
        sYLAY sYlay = sYLAY(address(new TransparentUpgradeableProxy(args.sYlayImpl, address(proxyAdmin), "")));
        assert(address(sYlay) == args.sYlayAddr);
        assert(sYlay.migrator() == args.yelayMigratorAddr);

        new YelayRewardDistributor(yelayOwner);
        YelayRewardDistributor yelayRewardDistributor = YelayRewardDistributor(
            address(new TransparentUpgradeableProxy(args.yelayRewardDistributorImpl, address(proxyAdmin), ""))
        );
        assert(address(yelayRewardDistributor) == args.yelayRewardDistributorAddr);
        address finalYlayImpl = address(new YLAY(yelayOwner, args.yelayMigratorAddr));

        vm.stopBroadcast();

        json.addProxy("sYLAYRewards", args.sYlayRewardsImpl, args.sYlayRewardsAddr);
        json.addProxy("YelayMigrator", args.yelayMigratorImpl, args.yelayMigratorAddr);
        json.addProxy("YelayStaking", args.yelayStakingImpl, args.yelayStakingAddr);
        json.addProxy("sYLAY", args.sYlayImpl, args.sYlayAddr);
        json.addProxy("YelayRewardsDistributor", args.yelayRewardDistributorImpl, args.yelayRewardDistributorAddr);
        json.addProxy("YLAY", finalYlayImpl, address(ylay));
    }
}
