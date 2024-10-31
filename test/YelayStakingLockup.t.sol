// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

import "forge-std/Test.sol";
import "spool/external/spool-core/SpoolOwner.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import "test/shared/Utilities.sol";
import {YLAY} from "src/YLAY.sol";
import {YelayOwner} from "src/YelayOwner.sol";
import {sYLAYRewards} from "src/sYLAYRewards.sol";
import {YelayRewardDistributor} from "src/YelayRewardDistributor.sol";
import {VoSPOOL, IVoSPOOL} from "spool/VoSPOOL.sol";
import {sYLAYPostMigration, IsYLAYPostMigration, IsYLAYBase} from "src/sYLAYPostMigration.sol";
import {YelayStakingPostMigration, IERC20} from "src/YelayStakingPostMigration.sol";
import {YelayMigrator} from "src/YelayMigrator.sol";

contract YelayStakingLockupTest is Test, Utilities {
    using ECDSA for bytes32;

    YelayOwner yelayOwner;
    YLAY yLAY;
    sYLAYPostMigration sYlay;
    YelayRewardDistributor rewardDistributor;
    YelayStakingPostMigration yelayStaking;
    YelayMigrator yelayMigrator;
    sYLAYRewards sYlayRewards;

    IERC20 rewardToken1;
    IERC20 rewardToken2;

    address deployer;
    address owner;
    address pauser;
    address stakeForWallet;
    address stakeForWallet2;
    address user1;
    uint256 user1Pk;
    address user2;
    uint256 user2Pk;

    // variables set in modifers
    uint256 rewardAmount;
    uint32 rewardDuration;
    uint112 rewardPerTranche;
    uint8 toTranche;

    function contractDeployment() public {
        // Step 1: Get the deployer's nonce and calculate future addresses
        deployer = address(this); // The deployer is the test contract
        yelayOwner = new YelayOwner();

        uint256 deployerNonce = vm.getNonce(deployer);

        // Compute precomputed addresses based on the current nonce
        address precomputedYLAYImplementationAddress = vm.computeCreateAddress(deployer, deployerNonce);
        address precomputedYLAYAddress = vm.computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedSYLAYAddress = vm.computeCreateAddress(deployer, deployerNonce + 2);
        address precomputedRewardDistributorAddress = vm.computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedYelayStakingAddress = vm.computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedSYLAYRewardsAddress = vm.computeCreateAddress(deployer, deployerNonce + 5);

        // Step 2: Deploy YLAY at precomputedYLAYAddress
        new YLAY(yelayOwner, address(0));
        yLAY = YLAY(address(new ERC1967Proxy(precomputedYLAYImplementationAddress, "")));
        assert(address(yLAY) == precomputedYLAYAddress);

        // Step 3: Deploy sYlay at precomputedSYLAYAddress
        sYlay = new sYLAYPostMigration(yelayOwner);
        assert(address(sYlay) == precomputedSYLAYAddress);

        // Step 4: Deploy YelayRewardDistributor at precomputedRewardDistributorAddress
        rewardDistributor = new YelayRewardDistributor(yelayOwner);
        assert(address(rewardDistributor) == precomputedRewardDistributorAddress);

        // Step 5: Deploy YelayStaking at precomputedYelayStakingAddress
        yelayStaking = new YelayStakingPostMigration(
            address(yLAY),
            address(sYlay),
            precomputedSYLAYRewardsAddress,
            address(rewardDistributor),
            address(yelayOwner)
        );
        assert(address(yelayStaking) == precomputedYelayStakingAddress);

        // Step 6: Deploy sYlayRewards at precomputedSYLAYRewardsAddress
        sYlayRewards = new sYLAYRewards(address(yelayStaking), address(sYlay), address(yelayOwner));
        assert(address(sYlayRewards) == precomputedSYLAYRewardsAddress);

        // Step 7: Initialize the contracts
        yLAY.initialize();
        yelayStaking.initialize();

        rewardToken1 = IERC20(address(new MockToken("TEST", "TEST")));
        rewardToken2 = IERC20(address(new MockToken("TEST", "TEST")));
    }

    function contractSetup() public {
        deal(address(yLAY), address(this), 100000000 ether);
        deal(address(yLAY), owner, 100000000 ether);
        deal(address(yLAY), user1, 100000000 ether);
        deal(address(yLAY), user2, 100000000 ether);
        deal(address(yLAY), stakeForWallet, 100000000 ether);
        deal(address(yLAY), stakeForWallet2, 100000000 ether);

        // Set pauser, distributor, and gradual minter permissions
        rewardDistributor.setPauser(pauser, true);
        rewardDistributor.setDistributor(address(yelayStaking), true);
        sYlay.setGradualMinter(address(yelayStaking), true);

        // Set the staking permissions for different wallets
        yelayStaking.setCanStakeFor(stakeForWallet, true);
        yelayStaking.setCanStakeFor(stakeForWallet2, true);

        // Approve maximum tokens for staking from various users
        yLAY.approve(address(yelayStaking), type(uint256).max);
        vm.prank(owner);
        yLAY.approve(address(yelayStaking), type(uint256).max);
        vm.prank(user1);
        yLAY.approve(address(yelayStaking), type(uint256).max);
        vm.prank(user2);
        yLAY.approve(address(yelayStaking), type(uint256).max);
        vm.prank(stakeForWallet);
        yLAY.approve(address(yelayStaking), type(uint256).max);
        vm.prank(stakeForWallet2);
        yLAY.approve(address(yelayStaking), type(uint256).max);

        // Transfer tokens to reward distributor
        rewardToken1.transfer(address(rewardDistributor), 100000 ether);
        rewardToken2.transfer(address(rewardDistributor), 100000 ether);
        deal(address(yLAY), address(rewardDistributor), 100000 ether);
    }

    function setUp() public {
        uint256 mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), 20734806);
        vm.selectFork(mainnetForkId);

        deployer = address(0x1);
        owner = address(0x2);
        pauser = address(0x3);
        stakeForWallet = address(0x4);
        stakeForWallet2 = address(0x5);
        (user1, user1Pk) = makeAddrAndKey("user1");
        (user2, user2Pk) = makeAddrAndKey("user2");

        contractDeployment();

        contractSetup();
    }

    /* ---------------------------------------------------------
    |                  Scenario A                              |
    ------------------------------------------------------------
    | week |        action              | sYLAY (user balance) |
    |-----------------------------------------------------------
    |     1| user stakes 1000           | 0                    |
    |    45| start                      | 211.53846            |
    |    45| locks for 100 weeks        | 692.30769            |
    |   145| lock ends (no user action) | 692.30769            |  
    |   160| start                      | 692.30769            |
    |   160| continue lock for 40 weeks | 956.73076            | 
    |   200| lock ends (no user action) | 956.73076            |   
    |   203| start                      | 956.73076            |     
    |   203| unstake 1000               | 0                    |
    --------------------------------------------------------- */

    function test_shouldSatisfyScenarioA() public {
        // user stakes 1000
        uint256 lockTranche = sYlay.getCurrentTrancheIndex();

        vm.prank(user1);
        yelayStaking.stake(1000 ether);
        assertEq(yelayStaking.balances(user1), 1000 ether);
        assertEq(sYlay.balanceOf(user1), 0);

        vm.warp(block.timestamp + 44 weeks); // week 45
        assertApproxEqRel(sYlay.balanceOf(user1), 211.53846 ether, 1e10);

        // locks for 100 weeks
        uint256 deadline = sYlay.getCurrentTrancheIndex() + 100;
        vm.prank(user1);
        yelayStaking.lockTranche(IsYLAYBase.UserTranchePosition(1, 0), deadline);
        assertApproxEqRel(sYlay.balanceOf(user1), 692.30769 ether, 1e10);

        vm.prank(user1);
        vm.expectRevert("sYLAY::migrateToLockup: Tranche already locked");
        yelayStaking.lockTranche(IsYLAYBase.UserTranchePosition(1, 0), deadline);

        // lock ends (no user action)
        vm.warp(block.timestamp + 100 weeks); // week 145
        assertApproxEqRel(sYlay.balanceOf(user1), 692.30769 ether, 1e10);

        vm.warp(block.timestamp + 15 weeks); // week 160

        // continue lock for 40 more weeks
        uint256 deadline2 = sYlay.getCurrentTrancheIndex() + 40;
        vm.prank(user1);
        vm.expectRevert("sYLAY::continueLockup: Lockup period exceeds a total of 4 years");
        sYlay.continueLockup(lockTranche, deadline2 + 208);
        vm.prank(user1);
        sYlay.continueLockup(lockTranche, deadline2);
        assertApproxEqRel(sYlay.balanceOf(user1), 956.73076 ether, 1e10);

        //// lock ends (no user action)
        vm.warp(block.timestamp + 40 weeks); // week 200
        assertApproxEqRel(sYlay.balanceOf(user1), 956.73076 ether, 1e10);

        vm.warp(block.timestamp + 3 weeks); // week 203
        assertApproxEqRel(sYlay.balanceOf(user1), 956.73076 ether, 1e10);

        // unstake 1000
        uint256 balanceBefore = yLAY.balanceOf(user1);
        vm.prank(user1);
        yelayStaking.unstake(1000 ether);
        uint256 received = yLAY.balanceOf(user1) - balanceBefore;
        assertEq(yelayStaking.balances(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(received, 1000 ether);
    }

    /* -----------------------------------------------------------------------------------------------------
    |                           Scenario B                                                                |
    |-------------------------------------------------------------------------------------------------------
    |- stake 3 times: 10k 15k 20k, at 3 different points (week 10, week 20, week 30).                      | 
    |- lock each for 30 weeks.                                                                             |      
    |- skip forward to unlock the first 2 stakes.                                                          |       
    |- unstake.                                                                                            |      
    |- ensure sylay balance is only the sYLAY from the 3rd lock; ie. all sYLAY burned from other locks.    |       
    ----------------------------------------------------------------------------------------------------- */

    function test_shouldSatisfyScenarioB() public {
        // stake 10k
        vm.prank(user1);
        yelayStaking.stake(10000 ether);
        assertEq(yelayStaking.balances(user1), 10000 ether);

        // lock for 30 weeks
        uint256 deadline = sYlay.getCurrentTrancheIndex() + 30;
        vm.prank(user1);
        yelayStaking.lockTranche(IsYLAYBase.UserTranchePosition(1, 0), deadline);

        vm.warp(block.timestamp + 10 weeks);

        // stake 15k
        vm.prank(user1);
        yelayStaking.stake(15000 ether);
        assertEq(yelayStaking.balances(user1), 25000 ether);

        // lock for 30 weeks
        deadline = sYlay.getCurrentTrancheIndex() + 30;
        vm.prank(user1);
        yelayStaking.lockTranche(IsYLAYBase.UserTranchePosition(1, 1), deadline);

        vm.warp(block.timestamp + 10 weeks);

        // stake 20k
        vm.prank(user1);
        yelayStaking.stake(20000 ether);
        assertEq(yelayStaking.balances(user1), 45000 ether);

        // lock for 30 weeks
        deadline = sYlay.getCurrentTrancheIndex() + 208;
        vm.prank(user1);
        yelayStaking.lockTranche(IsYLAYBase.UserTranchePosition(1, 2), deadline);

        // skip forward to unlock the first 2 stakes
        vm.warp(block.timestamp + 30 weeks);

        // unstake
        uint256 balanceBefore = yLAY.balanceOf(user1);
        vm.prank(user1);
        yelayStaking.unstake(25000 ether);
        uint256 received = yLAY.balanceOf(user1) - balanceBefore;
        assertEq(received, 25000 ether);
        assertEq(yelayStaking.balances(user1), 20000 ether);
        assertEq(sYlay.balanceOf(user1), 20000 ether);
    }

    /* -----------------------------------------------------
    |                   Scenario C                         |
    |-------------------------------------------------------
    |- stake 123.123123123123123123                        | 
    |- lock for 100 weeks                                  |      
    |- after 100 weeks, lock ends                          |       
    |- in another 2 weeks, unstake, passing full amount    |      
    |- ensure I get full amount back                       |       
    ------------------------------------------------------ */
    function test_shouldSatisfyScenarioC() public {
        uint256 amount = 123.123123123123123123 ether;
        vm.prank(user1);
        yelayStaking.stake(123.123123123123123123 ether);
        assertEq(yelayStaking.balances(user1), amount);
        assertEq(sYlay.balanceOf(user1), 0);

        // lock for 100 weeks
        uint256 deadline = sYlay.getCurrentTrancheIndex() + 100;
        vm.prank(user1);
        yelayStaking.lockTranche(IsYLAYBase.UserTranchePosition(1, 0), deadline);

        // lock ends (no user action)
        vm.warp(block.timestamp + 100 weeks); // week 145

        // unstake amount
        uint256 balanceBefore = yLAY.balanceOf(user1);
        vm.prank(user1);
        yelayStaking.unstake(amount);
        uint256 received = yLAY.balanceOf(user1) - balanceBefore;
        assertEq(yelayStaking.balances(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(received, amount);

        uint256 lockTranche = sYlay.getCurrentTrancheIndex();
        vm.prank(user1);
        vm.expectRevert("sYLAY::mintLockup: Invalid deadline");
        yelayStaking.lock(amount, lockTranche + 209);

        uint256 lockAmount = amount / 2;
        vm.prank(user1);
        yelayStaking.lock(lockAmount, lockTranche + 100);

        vm.prank(user1);
        vm.expectRevert("sYLAY::mintLockup: Lockup position already exists with different deadline");
        yelayStaking.lock(amount, lockTranche + 101);

        vm.prank(user1);
        yelayStaking.lock(amount - lockAmount, lockTranche + 100);

        // lock ends (no user action)
        vm.warp(block.timestamp + 100 weeks);

        // unstake amount
        balanceBefore = yLAY.balanceOf(user1);
        vm.prank(user1);
        yelayStaking.unstake(amount);
        received = yLAY.balanceOf(user1) - balanceBefore;
        assertEq(yelayStaking.balances(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(received, amount);
    }

    /* -------------------------------------------------------------
    |                  Scenario D                                  |
    ----------------------------------------------------------------
    | week |        action                  | sYLAY (user balance) |
    |------|--------------------------------|----------------------|
    |     1| user stakes 10000              | 0                    |
    |    10| start                          | 432.69230            |
    |    10| user locks 10000 for 100 weeks | 5240.38460           |
    |    60| user unstakes 15000; fail      | 7644.23076           |
    |   110| lock ends (no user action)     | 10048.07692          |
    |   120| start                          | 10528.84615          |
    |   120| continue lockup for 10 weeks   | 11057.69229          |
    |   130| start                          | 11490.38461          |
    |   130| user unstakes 15000/5000       | 0                    |
    |   234| start                          | 2500/7500            |  
    |   234| unstake 5000/15000             | 0                    |  
    ------------------------------------------------------------- */
    function test_shouldSatisfyScenarioD() public {
        // user stakes 10000
        vm.prank(user1);
        yelayStaking.stake(10000 ether);
        assertEq(yelayStaking.balances(user1), 10000 ether);
        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(sYlay.totalSupply(), 0);

        vm.warp(block.timestamp + 9 weeks); // week 10
        assertApproxEqRel(sYlay.balanceOf(user1), 432.6923 ether, 1e11);

        // user locks 10000 for 100 weeks
        uint256 start = sYlay.getCurrentTrancheIndex();
        uint256 deadline = start + 100;
        vm.prank(user1);
        yelayStaking.lock(10000 ether, deadline);
        assertApproxEqRel(sYlay.balanceOf(user1), 5240.3846 ether, 1e10);
        assertApproxEqRel(sYlay.totalSupply(), 5240.3846 ether, 1e10);

        vm.warp(block.timestamp + 50 weeks); // week 60
        // user unstakes 10000; fail
        vm.prank(user1);
        vm.expectRevert("YelayStaking::unstake: Unavailable amount requested");
        yelayStaking.unstake(15000 ether);
        assertApproxEqRel(sYlay.balanceOf(user1), 7644.23076 ether, 1e10);
        assertApproxEqRel(sYlay.totalSupply(), 7644.23076 ether, 1e10);

        vm.warp(block.timestamp + 50 weeks); // week 110
        assertApproxEqRel(sYlay.balanceOf(user1), 10048.07692 ether, 1e10);
        assertApproxEqRel(sYlay.totalSupply(), 10048.07692 ether, 1e10);

        vm.warp(block.timestamp + 10 weeks); // week 120
        assertApproxEqRel(sYlay.balanceOf(user1), 10528.84615 ether, 1e10);
        assertApproxEqRel(sYlay.totalSupply(), 10528.84615 ether, 1e10);

        // continue lockup for 10 weeks
        uint256 deadline2 = sYlay.getCurrentTrancheIndex() + 10;

        vm.prank(user1);
        vm.expectRevert("sYLAY::continueLockup: No lockup position found");
        sYlay.continueLockup(start + 1, deadline2);

        vm.prank(user1);
        vm.expectRevert("sYLAY::continueLockup: Lockup deadline should be in the future");
        sYlay.continueLockup(start, deadline2 - 20);

        vm.prank(user1);
        sYlay.continueLockup(start, deadline2);

        assertApproxEqRel(sYlay.balanceOf(user1), 11490.38461 ether, 1e10);
        assertApproxEqRel(sYlay.totalSupply(), 11490.38461 ether, 1e10);

        // start
        vm.warp(block.timestamp + 10 weeks); // week 130
        assertApproxEqRel(sYlay.balanceOf(user1), 11971.15384 ether, 1e10);
        assertApproxEqRel(sYlay.totalSupply(), 11971.15384 ether, 1e10);

        uint256 snapshot = vm.snapshot();

        // user unstakes 15000
        vm.prank(user1);
        yelayStaking.unstake(15000 ether);
        assertEq(yelayStaking.balances(user1), 5000 ether);
        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(sYlay.totalSupply(), 0);

        vm.warp(block.timestamp + 104 weeks); // week 234
        assertEq(yelayStaking.balances(user1), 5000 ether);
        assertEq(sYlay.balanceOf(user1), 2500 ether);
        assertEq(sYlay.totalSupply(), 2500 ether);

        // unstake 5000
        vm.prank(user1);
        yelayStaking.unstake(5000 ether);
        assertEq(yelayStaking.balances(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(sYlay.totalSupply(), 0);

        vm.revertTo(snapshot);

        // user unstakes 5000
        vm.prank(user1);
        yelayStaking.unstake(5000 ether);
        assertEq(yelayStaking.balances(user1), 15000 ether);
        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(sYlay.totalSupply(), 0);

        vm.warp(block.timestamp + 104 weeks); // week 234
        assertEq(yelayStaking.balances(user1), 15000 ether);
        assertEq(sYlay.balanceOf(user1), 7500 ether);
        assertEq(sYlay.totalSupply(), 7500 ether);

        // unstake 5000
        vm.prank(user1);
        yelayStaking.unstake(15000 ether);
        assertEq(yelayStaking.balances(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(sYlay.totalSupply(), 0);
    }

    function test_shouldFailToExecute() public {
        vm.prank(user1);
        vm.expectRevert("YelayStaking::_stake: Cannot stake 0");
        yelayStaking.stake(0);

        vm.prank(user1);
        vm.expectRevert("YelayStaking::_lock: Cannot lock 0");
        yelayStaking.lock(0, 0);

        vm.prank(user1);
        vm.expectRevert("YelayStaking::unstake: Unavailable amount requested");
        yelayStaking.unstake(0);
    }
}
