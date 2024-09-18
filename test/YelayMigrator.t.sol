// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {SPOOL} from "../src/SPOOL.sol";
import {SpoolOwner} from "spool/external/spool-core/SpoolOwner.sol";
import {IERC20} from "spool/external/@openzeppelin/token/ERC20/IERC20.sol";
import {VoSPOOL, Tranche} from "spool/VoSPOOL.sol";
import {RewardDistributor} from "spool/RewardDistributor.sol";
import {SpoolStaking} from "spool/SpoolStaking.sol";
import {SpoolStaking2} from "../src/upgrade/SpoolStaking2.sol";
import {VoSpoolRewards, VoSpoolRewardUser} from "spool/VoSpoolRewards.sol";

import "../src/external/spool-core/interfaces/ISpoolOwner.sol";

import {YLAY} from "../src/YLAY.sol";
import {YelayOwner, IYelayOwner} from "../src/YelayOwner.sol";
import {SYLAY} from "../src/SYLAY.sol";
import {SYLAYRewards} from "../src/SYLAYRewards.sol";
import {YelayMigrator} from "../src/YelayMigrator.sol";
import {YelayStaking} from "../src/YelayStaking.sol";

contract YelayMigratorTest is Test {
    address owner = address(0x01);
    address user1 = address(0x02);
    address user2 = address(0x03);

    uint256 user1Balance = 10_000e18;
    uint256 user1Stake1 = 1000e18;
    uint256 user1Stake2 = 400e18;

    uint256 user2Balance = 4_000e18;
    uint256 user2Stake = 900e18;

    ProxyAdmin proxyAdmin;
    SPOOL spool;
    SpoolOwner spoolOwner;
    VoSPOOL voSpool;
    RewardDistributor rewardDistributor;
    SpoolStaking spoolStaking;
    VoSpoolRewards voSpoolRewards;

    YelayOwner ylayOwner;
    YLAY ylay;
    SYLAY sYlay;
    SYLAYRewards sYlayRewards;
    YelayMigrator yelayMigrator;
    YelayStaking yelayStaking;

    function setUp() external {
        vm.warp(1726571314);

        vm.startPrank(owner);

        proxyAdmin = new ProxyAdmin();

        spool = new SPOOL(owner, owner);

        spoolOwner = new SpoolOwner();

        voSpool = new VoSPOOL(spoolOwner, block.timestamp + 100);

        rewardDistributor = new RewardDistributor(spoolOwner);

        address spoolStakingImpl = vm.computeCreateAddress(owner, vm.getNonce(owner));
        address spoolStakingAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 1);
        address voSpoolRewardsImpl = vm.computeCreateAddress(owner, vm.getNonce(owner) + 2);
        address voSpoolRewardsAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 3);

        new SpoolStaking(
            IERC20(address(spool)), voSpool, VoSpoolRewards(voSpoolRewardsAddr), rewardDistributor, spoolOwner
        );
        spoolStaking = SpoolStaking(address(new TransparentUpgradeableProxy(spoolStakingImpl, address(proxyAdmin), "")));

        new VoSpoolRewards(spoolStakingAddr, voSpool, spoolOwner);
        voSpoolRewards =
            VoSpoolRewards(address(new TransparentUpgradeableProxy(voSpoolRewardsImpl, address(proxyAdmin), "")));

        assert(address(spoolStaking.voSpoolRewards()) == voSpoolRewardsAddr);
        assert(address(voSpoolRewards.spoolStaking()) == spoolStakingAddr);

        spoolStaking.initialize();

        rewardDistributor.setDistributor(address(spoolStaking), true);
        spool.transfer(address(rewardDistributor), 2_000_000e18);

        voSpool.setGradualMinter(address(spoolStaking), true);
        // TODO: need to set minter as well? https://etherscan.io/address/0x08772c1872c997Fec8dA3c7f36C1FC28EBE72E97#code

        voSpoolRewards.updateVoSpoolRewardRate(14, 184615384615384615384615);

        spool.transfer(address(0xdead), 70_000_000e18);

        spool.transfer(user1, user1Balance + user1Stake1 + user1Stake2);
        spool.transfer(user2, user2Balance + user2Stake);

        spoolStaking.addToken(IERC20(address(spool)), 157248000, 10_000e18);
        voSpoolRewards.updateVoSpoolRewardRate(156, 100e18);

        ylayOwner = new YelayOwner();

        address sYlayImpl = address(new SYLAY(ISpoolOwner(address(spoolOwner)), address(voSpool)));
        sYlay = SYLAY(address(new TransparentUpgradeableProxy(sYlayImpl, address(proxyAdmin), "")));

        address ylayImpl = vm.computeCreateAddress(owner, vm.getNonce(owner));
        // address ylayAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 1);
        address sYlayRewardsImpl = vm.computeCreateAddress(owner, vm.getNonce(owner) + 2);
        address sYlayRewardsAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 3);
        address yelayMigratorImpl = vm.computeCreateAddress(owner, vm.getNonce(owner) + 4);
        address yelayMigratorAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 5);
        address yelayStakingImpl = vm.computeCreateAddress(owner, vm.getNonce(owner) + 6);
        address yelayStakingAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 7);

        new YLAY(ylayOwner, YelayMigrator(yelayMigratorAddr));
        ylay = YLAY(address(new ERC1967Proxy(ylayImpl, "")));

        new SYLAYRewards(address(spoolOwner), address(sYlay), yelayStakingAddr);
        sYlayRewards = SYLAYRewards(address(new TransparentUpgradeableProxy(sYlayRewardsImpl, address(proxyAdmin), "")));
        assert(address(sYlayRewards) == sYlayRewardsAddr);

        new YelayMigrator(address(spoolOwner), ylay, sYlay, yelayStakingAddr, address(spool));
        yelayMigrator =
            YelayMigrator(address(new TransparentUpgradeableProxy(yelayMigratorImpl, address(proxyAdmin), "")));
        assert(
            proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(yelayMigrator))))
                == yelayMigratorImpl
        );
        assert(address(yelayMigrator) == yelayMigratorAddr);
        assert(address(yelayMigrator.SPOOL()) == address(spool));

        new YelayStaking(
            address(spoolOwner),
            address(ylay),
            address(sYlay),
            address(sYlayRewards),
            // TODO: add RewardDistributor
            address(0x11),
            address(spoolStaking),
            yelayMigratorAddr
        );
        yelayStaking = YelayStaking(address(new TransparentUpgradeableProxy(yelayStakingImpl, address(proxyAdmin), "")));
        assert(address(yelayStaking) == yelayStakingAddr);
        assert(address(yelayStaking.migrator()) == address(yelayMigrator));

        sYlay.setGradualMinter(address(yelayStaking), true);
        ylay.initialize();

        vm.stopPrank();
    }

    function test_scenario() external {
        vm.assertEq(voSpool.getTrancheIndex(block.timestamp), 1);

        vm.startPrank(user1);
        spool.approve(address(spoolStaking), type(uint256).max);
        spoolStaking.stake(user1Stake1);
        vm.stopPrank();

        vm.warp(block.timestamp + 4 weeks);

        vm.assertEq(voSpool.getTrancheIndex(block.timestamp), 5);

        vm.startPrank(user1);
        spoolStaking.stake(user1Stake2);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 weeks);

        vm.assertEq(voSpool.getTrancheIndex(block.timestamp), 10);

        vm.startPrank(user2);
        spool.approve(address(spoolStaking), type(uint256).max);
        spoolStaking.stake(user2Stake);
        vm.stopPrank();

        vm.warp(block.timestamp + 148 weeks);

        vm.assertEq(voSpool.getTrancheIndex(block.timestamp), 158);

        assertEq(voSpool.getUserGradualVotingPower(user1) / 10 ** 12, 1392_307692);
        assertEq(voSpool.getUserGradualVotingPower(user2) / 10 ** 12, 853_846153);

        // check SPOOL rewards
        assertEq(spoolStaking.earned(IERC20(address(spool)), user1) / 1e16, 3811_03);
        assertEq(spoolStaking.earned(IERC20(address(spool)), user2) / 1e16, 2227_42);

        // check voSPOOL rewards
        vm.startPrank(user1);
        assertEq(spoolStaking.getUpdatedVoSpoolRewardAmount() / 1e16, 10414_50);
        vm.stopPrank();
        vm.startPrank(user2);
        assertEq(spoolStaking.getUpdatedVoSpoolRewardAmount() / 1e16, 5085_49);
        vm.stopPrank();

        vm.startPrank(owner);
        spool.pause();

        // owner of Yelay can migrate for user
        {
            address[] memory claimants = new address[](1);
            claimants[0] = user1;
            yelayMigrator.migrateBalance(claimants);

            // owner cannot claim second time
            vm.expectRevert("YelayMigrator:migrateBalance: User already migrated");
            yelayMigrator.migrateBalance(claimants);
        }
        vm.stopPrank();
        // user cannot claim second time
        vm.startPrank(user1);
        vm.expectRevert("YelayMigrator:migrateBalance: User already migrated");
        yelayMigrator.migrateBalance();
        vm.stopPrank();

        // user itself can migrate as well
        vm.startPrank(user2);
        yelayMigrator.migrateBalance();
        vm.stopPrank();

        uint256 user1YlayBalanceBeforeRewards = ylay.balanceOf(user1);
        uint256 user2YlayBalanceBeforeRewards = ylay.balanceOf(user2);

        {
            vm.assertNotEq(sYlay.getTrancheIndex(block.timestamp), 158);
            vm.startPrank(owner);
            yelayMigrator.migrateGlobal();
            yelayMigrator.migrateGlobalTranches(voSpool.getCurrentTrancheIndex());
            vm.stopPrank();
            vm.assertEq(sYlay.getTrancheIndex(block.timestamp), 158);
        }

        vm.startPrank(owner);
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(spoolStaking))),
            address(
                new SpoolStaking2(
                    address(spool),
                    address(voSpool),
                    address(voSpoolRewards),
                    address(rewardDistributor),
                    address(spoolOwner)
                )
            )
        );
        vm.stopPrank();

        // spoolStaking = SpoolStaking(address(new TransparentUpgradeableProxy(spoolStakingImpl, address(proxyAdmin), "")));

        // owner of Yelay can migrate for user
        {
            vm.startPrank(owner);
            address[] memory claimants = new address[](2);
            claimants[0] = user1;
            claimants[1] = user2;
            yelayMigrator.migrateStake(claimants);

            // owner cannot claim second time
            vm.expectRevert("YelayMigrator:_migrateStake: Staker already migrated");
            yelayMigrator.migrateStake(claimants);
            vm.stopPrank();
        }

        uint256 user1YlayBalanceAfterRewards = ylay.balanceOf(user1);
        uint256 user2YlayBalanceAfterRewards = ylay.balanceOf(user2);

        // check rewards
        assertEq((user1YlayBalanceAfterRewards - user1YlayBalanceBeforeRewards) / 10 ** 16, 27221_69 + 74389_30);
        assertEq((user2YlayBalanceAfterRewards - user2YlayBalanceBeforeRewards) / 10 ** 16, 15910_17 + 36324_99);

        assertApproxEqAbs(yelayStaking.balances(user1), 10_000e18, 10000);
        assertEq(yelayStaking.balances(user2) / 10 ** 16, 6428_57);

        // console.log(sYlay.getLastFinishedTrancheIndex());

        // TODO: balances are slightly less than voting power!
        // voting power does not grow with the time
        // voting power equals the maximum so it should be less!
        // seems
        console.log("Stake balances");
        console.log(yelayStaking.balances(user1));
        console.log(yelayStaking.balances(user2));

        console.log("Voting power Yelay");
        console.log(sYlay.getUserGradualVotingPower(user1));
        console.log(sYlay.getUserGradualVotingPower(user2));

        // TODO: Only after 55 weeks it will get 100% mature, why?
        // vm.warp(block.timestamp + 55 weeks);
        vm.warp(block.timestamp + 80 weeks);

        // TODO: shouldn't it be equal to FULL_POWER_TRANCHES_COUNT ?
        // vm.assertEq(sYlay.getTrancheIndex(block.timestamp), 52 * 4);

        // console.log("Voting power Yelay");
        console.log(sYlay.getUserGradualVotingPower(user1));
        console.log(sYlay.getUserGradualVotingPower(user2));

        // console.log("voSpool indexedGlobalTranches");
        // {
        //     (Tranche memory zero, Tranche memory one, Tranche memory two, Tranche memory three, Tranche memory four) =
        //         voSpool.indexedGlobalTranches(0);
        //     console.log("0 index");
        //     console.log(zero.amount);
        //     console.log(one.amount);
        //     console.log(two.amount);
        //     console.log(three.amount);
        //     console.log(four.amount);
        // }
        // {
        //     (Tranche memory zero, Tranche memory one, Tranche memory two, Tranche memory three, Tranche memory four) =
        //         voSpool.indexedGlobalTranches(1);
        //     console.log("1 index");
        //     console.log(zero.amount);
        //     console.log(one.amount);
        //     console.log(two.amount);
        //     console.log(three.amount);
        //     console.log(four.amount);
        // }
        // {
        //     (Tranche memory zero, Tranche memory one, Tranche memory two, Tranche memory three, Tranche memory four) =
        //         voSpool.indexedGlobalTranches(2);
        //     console.log("2 index");
        //     console.log(zero.amount);
        //     console.log(one.amount);
        //     console.log(two.amount);
        //     console.log(three.amount);
        //     console.log(four.amount);
        // }

        // console.log("sYLAY indexedGlobalTranches");
        // {
        //     (
        //         SYLAY.Tranche memory zero,
        //         SYLAY.Tranche memory one,
        //         SYLAY.Tranche memory two,
        //         SYLAY.Tranche memory three,
        //         SYLAY.Tranche memory four
        //     ) = sYlay.indexedGlobalTranches(0);
        //     console.log("0 index");
        //     console.log(zero.amount);
        //     console.log(one.amount);
        //     console.log(two.amount);
        //     console.log(three.amount);
        //     console.log(four.amount);
        // }
        // {
        //     (
        //         SYLAY.Tranche memory zero,
        //         SYLAY.Tranche memory one,
        //         SYLAY.Tranche memory two,
        //         SYLAY.Tranche memory three,
        //         SYLAY.Tranche memory four
        //     ) = sYlay.indexedGlobalTranches(1);
        //     console.log("1 index");
        //     console.log(zero.amount);
        //     console.log(one.amount);
        //     console.log(two.amount);
        //     console.log(three.amount);
        //     console.log(four.amount);
        // }
        // {
        //     (
        //         SYLAY.Tranche memory zero,
        //         SYLAY.Tranche memory one,
        //         SYLAY.Tranche memory two,
        //         SYLAY.Tranche memory three,
        //         SYLAY.Tranche memory four
        //     ) = sYlay.indexedGlobalTranches(2);
        //     console.log("2 index");
        //     console.log(zero.amount);
        //     console.log(one.amount);
        //     console.log(two.amount);
        //     console.log(three.amount);
        //     console.log(four.amount);
        // }
        // {
        //     (Tranche memory zero, Tranche memory one, Tranche memory two, Tranche memory three, Tranche memory four) =
        //         sYlay.indexedGlobalTranches(0);
        //     console.log(zero.amount);
        //     console.log(one.amount);
        //     console.log(two.amount);
        //     console.log(three.amount);
        //     console.log(four.amount);
        // }
        // console.log(voSpool.indexedGlobalTranches(0));
        // console.log(sYlay.indexedGlobalTranches(0));

        assertGt(ylay.balanceOf(address(yelayStaking)), 0);

        {
            // user can unstake the whole balance
            uint256 stakeBalance = yelayStaking.balances(user1);
            uint256 ylayBalance = ylay.balanceOf(user1);
            assertGt(stakeBalance, 0);
            assertGt(ylayBalance, 0);

            vm.startPrank(user1);
            yelayStaking.unstake(stakeBalance);
            vm.stopPrank();

            assertEq(yelayStaking.balances(user1), 0);
            assertEq(sYlay.getUserGradualVotingPower(user1), 0);
            assertEq(ylay.balanceOf(user1), ylayBalance + stakeBalance);

            vm.warp(block.timestamp + 55 weeks);
            assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        }

        vm.startPrank(user2);
        yelayStaking.unstake(yelayStaking.balances(user2));
        vm.stopPrank();

        assertEq(ylay.balanceOf(address(yelayStaking)), 0);

        // uint256 user1Balance = spool.balanceOf(user1);

        // user1Balance += spoolRewardsUser1;

        // {
        //     vm.startPrank(user2);
        //     uint256 earned = spoolStaking.getUpdatedVoSpoolRewardAmount();
        //     console.log(earned / 10 ** 12);
        //     vm.stopPrank();
        //     user1Balance += earned;
        // }

        // console.log(spoolStaking.earned(IERC20(address(spool)), user1));
        // console.log(spoolStaking.earned(IERC20(address(spool)), user2));

        // {
        //     IERC20[] memory tokens = new IERC20[](1);
        //     tokens[0] = IERC20(address(spool));
        //     vm.startPrank(user1);
        //     spoolStaking.getRewards(tokens, true);
        //     vm.stopPrank();
        // }

        // assertEq(spool.balanceOf(user1), user1Balance);
        // {
        //     IERC20[] memory tokens = new IERC20[](1);
        //     tokens[0] = IERC20(address(spool));
        //     vm.startPrank(user2);
        //     spoolStaking.getRewards(tokens, false);
        //     vm.stopPrank();
        // }

        // {
        //    ( uint48 maturedVotingPower,
        //     uint48 maturingAmount,
        //     uint56 rawUnmaturedVotingPower,
        //     UserTranchePosition oldestTranchePosition,
        //     UserTranchePosition latestTranchePosition,
        //     uint16 lastUpdatedTrancheIndex) = voSpool.getUserGradual();
        // }

        // console.log("==========");
        // console.log(spool.balanceOf(user1));
        // console.log(spoolStaking.balances(user1));
        // console.log(spoolStaking.earned(IERC20(address(spool)), user1));
        // {
        //     (uint8 lastRewardRateIndex, uint248 earned) = voSpoolRewards.userRewards(user1);
        //     console.log(lastRewardRateIndex);
        //     console.log(earned);
        // }

        // console.log("==========");
        // console.log(spool.balanceOf(user1));
        // console.log(spoolStaking.balances(user1));
        // console.log(spoolStaking.earned(IERC20(address(spool)), user1));
        // {
        //     (uint8 lastRewardRateIndex, uint248 earned) = voSpoolRewards.userRewards(user1);
        //     console.log(lastRewardRateIndex);
        //     console.log(earned);
        // }

        // vm.startPrank(user1);
        // spoolStaking.compound(true);
        // vm.stopPrank();

        // console.log("==========");
        // console.log(spool.balanceOf(user1));
        // console.log(spoolStaking.balances(user1));
        // console.log(spoolStaking.earned(IERC20(address(spool)), user1));
        // {
        //     (uint8 lastRewardRateIndex, uint248 earned) = voSpoolRewards.userRewards(user1);
        //     console.log(lastRewardRateIndex);
        //     console.log(earned);
        // }

        // vm.startPrank(user2);
        // spool.approve(address(spoolStaking), type(uint256).max);
        // spoolStaking.stake(user2Stake);
        // vm.stopPrank();
    }
}
