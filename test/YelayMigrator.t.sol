// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {SPOOL} from "../src/SPOOL.sol";
import {SpoolOwner, ISpoolOwner} from "spool/external/spool-core/SpoolOwner.sol";
import {IERC20} from "spool/external/@openzeppelin/token/ERC20/IERC20.sol";
import {VoSPOOL, Tranche, UserTranche} from "spool/VoSPOOL.sol";
import {RewardDistributor} from "spool/RewardDistributor.sol";
import {SpoolStaking} from "spool/SpoolStaking.sol";
import {SpoolStakingMigration} from "../src/upgrade/SpoolStakingMigration.sol";
import {VoSpoolRewards, VoSpoolRewardUser} from "spool/VoSpoolRewards.sol";

import {YLAY} from "../src/YLAY.sol";
import {YelayOwner, IYelayOwner} from "../src/YelayOwner.sol";
import {sYLAY, IsYLAY} from "../src/sYLAY.sol";
import {sYLAYRewards} from "../src/sYLAYRewards.sol";
import {YelayMigrator} from "../src/YelayMigrator.sol";
import {YelayStaking} from "../src/YelayStaking.sol";
import {YelayRewardDistributor} from "../src/YelayRewardDistributor.sol";
import {ConversionLib} from "../src/libraries/ConversionLib.sol";

contract YelayMigratorTest is Test {
    address owner = address(0x01);
    address user1 = address(0x02);
    address user2 = address(0x03);
    address user3 = address(0x04);
    address user4 = address(0x05);

    uint256 user3InitialInstantPower = 70e18;
    uint256 user4InitialInstantPower = 20e18;

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
    SpoolStakingMigration spoolStaking;
    VoSpoolRewards voSpoolRewards;

    YelayOwner yelayOwner;
    YLAY ylay;
    sYLAY sYlay;
    sYLAYRewards sYlayRewards;
    YelayMigrator yelayMigrator;
    YelayStaking yelayStaking;
    YelayRewardDistributor yelayRewardDistributor;

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
        spoolStaking =
            SpoolStakingMigration(address(new TransparentUpgradeableProxy(spoolStakingImpl, address(proxyAdmin), "")));

        new VoSpoolRewards(spoolStakingAddr, voSpool, spoolOwner);
        voSpoolRewards =
            VoSpoolRewards(address(new TransparentUpgradeableProxy(voSpoolRewardsImpl, address(proxyAdmin), "")));

        assert(address(spoolStaking.voSpoolRewards()) == voSpoolRewardsAddr);
        assert(address(voSpoolRewards.spoolStaking()) == spoolStakingAddr);

        spoolStaking.initialize();

        rewardDistributor.setDistributor(address(spoolStaking), true);
        spool.transfer(address(rewardDistributor), 2_000_000e18);

        voSpool.setGradualMinter(address(spoolStaking), true);

        voSpoolRewards.updateVoSpoolRewardRate(14, 184615384615384615384615);

        spool.transfer(address(0xdead), 70_000_000e18);

        spool.transfer(user1, user1Balance + user1Stake1 + user1Stake2);
        spool.transfer(user2, user2Balance + user2Stake);

        spoolStaking.addToken(IERC20(address(spool)), 157248000, 10_000e18);
        voSpoolRewards.updateVoSpoolRewardRate(156, 100e18);

        yelayOwner = new YelayOwner();

        address ylayImpl = vm.computeCreateAddress(owner, vm.getNonce(owner));
        address ylayAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 1);
        address sYlayRewardsImpl = vm.computeCreateAddress(owner, vm.getNonce(owner) + 2);
        address sYlayRewardsAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 3);
        address yelayMigratorImpl = vm.computeCreateAddress(owner, vm.getNonce(owner) + 4);
        address yelayMigratorAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 5);
        address yelayStakingImpl = vm.computeCreateAddress(owner, vm.getNonce(owner) + 6);
        address yelayStakingAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 7);
        address sYlayImpl = vm.computeCreateAddress(owner, vm.getNonce(owner) + 8);
        address sYlayAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 9);
        address yelayRewardDistributorAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 10);

        new YLAY(yelayOwner, yelayMigratorAddr);
        ylay = YLAY(address(new ERC1967Proxy(ylayImpl, "")));
        assert(address(ylay) == ylayAddr);

        new sYLAYRewards(yelayStakingAddr, address(sYlayAddr), address(yelayOwner));
        sYlayRewards = sYLAYRewards(address(new TransparentUpgradeableProxy(sYlayRewardsImpl, address(proxyAdmin), "")));
        assert(address(sYlayRewards) == sYlayRewardsAddr);

        new YelayMigrator(address(yelayOwner), ylay, IsYLAY(sYlayAddr), yelayStakingAddr, address(spool));
        yelayMigrator =
            YelayMigrator(address(new TransparentUpgradeableProxy(yelayMigratorImpl, address(proxyAdmin), "")));
        assert(
            proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(yelayMigrator))))
                == yelayMigratorImpl
        );
        assert(address(yelayMigrator) == yelayMigratorAddr);
        assert(address(yelayMigrator.SPOOL()) == address(spool));

        new YelayStaking(
            address(yelayOwner),
            address(ylay),
            address(sYlayAddr),
            address(sYlayRewards),
            yelayRewardDistributorAddr,
            address(spoolStaking),
            yelayMigratorAddr
        );
        yelayStaking = YelayStaking(address(new TransparentUpgradeableProxy(yelayStakingImpl, address(proxyAdmin), "")));
        assert(address(yelayStaking) == yelayStakingAddr);
        assert(address(yelayStaking.migrator()) == address(yelayMigrator));

        new sYLAY(address(yelayOwner), address(voSpool), yelayMigratorAddr);
        sYlay = sYLAY(address(new TransparentUpgradeableProxy(sYlayImpl, address(proxyAdmin), "")));
        assert(address(sYlay) == sYlayAddr);
        assert(sYlay.migrator() == yelayMigratorAddr);

        yelayRewardDistributor = new YelayRewardDistributor(yelayOwner);
        assert(address(yelayRewardDistributor) == yelayRewardDistributorAddr);

        sYlay.setGradualMinter(address(yelayStaking), true);
        voSpool.setMinter(address(this), true);

        ylay.initialize();

        vm.stopPrank();
    }

    function test_migrationScenario() external {
        voSpool.mint(user3, user3InitialInstantPower);
        voSpool.mint(user4, user4InitialInstantPower);

        assertEq(voSpool.userInstantPower(user3), user3InitialInstantPower);
        assertEq(voSpool.userInstantPower(user4), user4InitialInstantPower);
        assertEq(voSpool.totalInstantPower(), user3InitialInstantPower + user4InitialInstantPower);
        assertEq(voSpool.totalSupply(), user3InitialInstantPower + user4InitialInstantPower);

        uint256 startingBlockTimestamp = block.timestamp;
        vm.assertEq(voSpool.getTrancheIndex(startingBlockTimestamp), 1);

        vm.startPrank(user1);
        spool.approve(address(spoolStaking), type(uint256).max);
        spoolStaking.stake(user1Stake1);
        vm.stopPrank();

        vm.warp(startingBlockTimestamp + 4 weeks);

        vm.assertEq(voSpool.getTrancheIndex(block.timestamp), 5);

        vm.startPrank(user1);
        spoolStaking.stake(user1Stake2);
        vm.stopPrank();

        vm.warp(startingBlockTimestamp + 9 weeks);

        assertEq(voSpool.getTrancheIndex(block.timestamp), 10);

        vm.startPrank(user2);
        spool.approve(address(spoolStaking), type(uint256).max);
        spoolStaking.stake(user2Stake);
        vm.stopPrank();

        vm.startPrank(owner);
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(spoolStaking))),
            address(
                new SpoolStakingMigration(
                    address(spool),
                    address(voSpool),
                    address(voSpoolRewards),
                    address(rewardDistributor),
                    address(spoolOwner)
                )
            )
        );
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        spoolStaking.setStakingAllowed(false);
        assertFalse(spoolStaking.stakingAllowed());
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("SpoolStaking::stake staking is not allowed");
        spoolStaking.stake(user1Stake2);
        vm.stopPrank();

        vm.warp(startingBlockTimestamp + 157 weeks);

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
            yelayMigrator.migrateInitial();
            assertTrue(sYlay.migrationInitiated());
            yelayMigrator.migrateGlobalTranches(voSpool.getCurrentTrancheIndex());
            vm.stopPrank();
            assertTrue(sYlay.globalMigrationComplete());
            vm.assertEq(sYlay.getTrancheIndex(block.timestamp), 158);
        }
        assertFalse(yelayStaking.migrationComplete());
        assertFalse(sYlay.migrationComplete());

        assertFalse(yelayStaking.migrationComplete());
        assertFalse(sYlay.migrationComplete());

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
        assertTrue(yelayStaking.migrationComplete());
        assertFalse(sYlay.migrationComplete());

        {
            vm.startPrank(owner);
            address[] memory claimants = new address[](2);
            claimants[0] = user3;
            claimants[1] = user4;
            yelayMigrator.migrateStake(claimants);
            vm.stopPrank();
        }

        assertTrue(yelayStaking.migrationComplete());
        assertTrue(sYlay.migrationComplete());

        assertEq(sYlay.totalInstantPower(), ConversionLib.convert(voSpool.totalInstantPower()));
        assertApproxEqAbs(
            sYlay.totalInstantPower(),
            ConversionLib.convert(voSpool.userInstantPower(user3))
                + ConversionLib.convert(voSpool.userInstantPower(user4)),
            1
        );
        assertEq(sYlay.userInstantPower(user3), ConversionLib.convert(voSpool.userInstantPower(user3)));
        assertEq(sYlay.userInstantPower(user4), ConversionLib.convert(voSpool.userInstantPower(user4)));

        _checkGlobalTranche(0);
        _checkGlobalTranche(1);
        _checkGlobalTranche(2);
        _checkGlobalTranche(3);

        _checkUserTranche(0, user1);
        _checkUserTranche(1, user1);
        _checkUserTranche(2, user1);
        _checkUserTranche(3, user1);

        _checkUserTranche(0, user2);
        _checkUserTranche(1, user2);
        _checkUserTranche(2, user2);
        _checkUserTranche(3, user2);

        uint256 user1YlayBalanceAfterRewards = ylay.balanceOf(user1);
        uint256 user2YlayBalanceAfterRewards = ylay.balanceOf(user2);

        // check rewards with precalculated ones
        assertEq((user1YlayBalanceAfterRewards - user1YlayBalanceBeforeRewards) / 10 ** 16, 27221_69 + 74389_30);
        assertEq((user2YlayBalanceAfterRewards - user2YlayBalanceBeforeRewards) / 10 ** 16, 15910_17 + 36324_99);

        uint256 user1StakingBalance = yelayStaking.balances(user1);
        uint256 user2StakingBalance = yelayStaking.balances(user2);
        assertEq(user1StakingBalance, ConversionLib.convert(spoolStaking.balances(user1)));
        assertEq(user2StakingBalance, ConversionLib.convert(spoolStaking.balances(user2)));

        assertLt(sYlay.getUserGradualVotingPower(user1), user1StakingBalance);
        assertLt(sYlay.getUserGradualVotingPower(user2), user2StakingBalance);

        {
            // user1 had his 2 stake on week 5, so on week 213 it should be fully matured
            vm.warp(startingBlockTimestamp + 211 weeks);
            assertEq(sYlay.getCurrentTrancheIndex(), 212);
            assertLt(sYlay.getUserGradualVotingPower(user1), user1StakingBalance);

            vm.warp(startingBlockTimestamp + 212 weeks);
            assertEq(sYlay.getCurrentTrancheIndex(), 213);
            assertGe(sYlay.getUserGradualVotingPower(user1), user1StakingBalance);
        }

        {
            // user2 had only 1 stake on week 10, so on week 218 it should be fully matured
            vm.warp(startingBlockTimestamp + 216 weeks);
            assertEq(sYlay.getCurrentTrancheIndex(), 217);
            assertLt(sYlay.getUserGradualVotingPower(user2), user2StakingBalance);

            vm.warp(startingBlockTimestamp + 217 weeks);
            assertEq(sYlay.getCurrentTrancheIndex(), 218);
            assertGe(sYlay.getUserGradualVotingPower(user2), user2StakingBalance);
        }

        assertGt(ylay.balanceOf(address(yelayStaking)), 0);

        // unstaking part
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

        vm.startPrank(owner);
        yelayStaking.setStakingStarted(true);
        vm.stopPrank();

        // new staking part
        uint256 user2SecondStake = 100e18;
        vm.startPrank(user2);
        ylay.approve(address(yelayStaking), type(uint256).max);
        yelayStaking.stake(user2SecondStake);
        vm.stopPrank();

        assertEq(yelayStaking.balances(user2), user2StakingBalance + user2SecondStake);

        vm.warp(block.timestamp + 207 weeks);
        assertLt(sYlay.getUserGradualVotingPower(user2), yelayStaking.balances(user2));
        vm.warp(block.timestamp + 1 weeks);
        assertGe(sYlay.getUserGradualVotingPower(user2), yelayStaking.balances(user2));

        vm.startPrank(user2);
        yelayStaking.unstake(yelayStaking.balances(user2));
        vm.stopPrank();

        assertEq(ylay.balanceOf(address(yelayStaking)), 0);

        vm.startPrank(user2);
        yelayStaking.stake(user2SecondStake);
        vm.stopPrank();

        assertEq(yelayStaking.balances(user2), user2SecondStake);
        vm.warp(block.timestamp + 208 weeks);
        assertEq(sYlay.getUserGradualVotingPower(user2), yelayStaking.balances(user2));
    }

    function _checkGlobalTranche(uint256 index) internal view {
        (Tranche memory zero, Tranche memory one, Tranche memory two, Tranche memory three, Tranche memory four) =
            voSpool.indexedGlobalTranches(index);
        (
            sYLAY.Tranche memory zero_,
            sYLAY.Tranche memory one_,
            sYLAY.Tranche memory two_,
            sYLAY.Tranche memory three_,
            sYLAY.Tranche memory four_
        ) = sYlay.indexedGlobalTranches(index);
        assertEq(ConversionLib.convertPower(zero.amount), zero_.amount);
        assertEq(ConversionLib.convertPower(one.amount), one_.amount);
        assertEq(ConversionLib.convertPower(two.amount), two_.amount);
        assertEq(ConversionLib.convertPower(three.amount), three_.amount);
        assertEq(ConversionLib.convertPower(four.amount), four_.amount);
    }

    function _checkUserTranche(uint256 index, address user) internal view {
        (UserTranche memory zero, UserTranche memory one, UserTranche memory two, UserTranche memory three) =
            voSpool.userTranches(user, index);
        (
            sYLAY.UserTranche memory zero_,
            sYLAY.UserTranche memory one_,
            sYLAY.UserTranche memory two_,
            sYLAY.UserTranche memory three_
        ) = sYlay.userTranches(user, index);
        assertEq(ConversionLib.convertPower(zero.amount), zero_.amount);
        assertEq(ConversionLib.convertPower(one.amount), one_.amount);
        assertEq(ConversionLib.convertPower(two.amount), two_.amount);
        assertEq(ConversionLib.convertPower(three.amount), three_.amount);

        assertEq(zero.index, zero_.index);
        assertEq(one.index, one_.index);
        assertEq(two.index, two_.index);
        assertEq(three.index, three_.index);
    }
}
