// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "spool/external/spool-core/SpoolOwner.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import "test/shared/Utilities.sol";
import {YLAY} from "src/YLAY.sol";
import {YelayOwner} from "src/YelayOwner.sol";
import {sYLAYRewards} from "src/sYLAYRewards.sol";
import {YelayRewardDistributor} from "src/YelayRewardDistributor.sol";
import {VoSPOOL, IVoSPOOL} from "spool/VoSPOOL.sol";
import {sYLAY, IsYLAYBase} from "src/sYLAY.sol";
import {YelayStaking, YelayStakingBase, IERC20} from "src/YelayStaking.sol";
import {YelayMigrator} from "src/YelayMigrator.sol";

contract YelayStakingTest is Test, Utilities {
    // known addresses
    // TODO as constants
    YelayStaking spoolStaking = YelayStaking(0xc3160C5cc63B6116DD182faA8393d3AD9313e213);
    IERC20 SPOOL = IERC20(0x40803cEA2b2A32BdA1bE61d3604af6a814E70976);
    VoSPOOL voSPOOL = VoSPOOL(0xaF56D16a7fe479F2fcD48FF567fF589CB2d2a0E9);

    // new
    ISpoolOwner spoolOwner;
    YelayOwner yelayOwner;
    YLAY yLAY;
    sYLAY sYlay;
    YelayRewardDistributor rewardDistributor;
    YelayStakingHarness yelayStaking;
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
    address user2;

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
        address precomputedSpoolOwnerAddress = vm.computeCreateAddress(deployer, deployerNonce);
        address precomputedYLAYImplementationAddress = vm.computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedYLAYAddress = vm.computeCreateAddress(deployer, deployerNonce + 2);
        address precomputedSYLAYAddress = vm.computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedRewardDistributorAddress = vm.computeCreateAddress(deployer, deployerNonce + 4);
        address precomputedYelayStakingAddress = vm.computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedMigratorAddress = vm.computeCreateAddress(deployer, deployerNonce + 6);
        address precomputedSYLAYRewardsAddress = vm.computeCreateAddress(deployer, deployerNonce + 7);

        // Step 2: Deploy SpoolOwner at precomputedYLAYAddress
        spoolOwner = new SpoolOwner();
        assert(address(spoolOwner) == precomputedSpoolOwnerAddress);

        // Step 3: Deploy YLAY at precomputedYLAYAddress
        new YLAY(yelayOwner, precomputedMigratorAddress);
        yLAY = YLAY(address(new ERC1967Proxy(precomputedYLAYImplementationAddress, "")));
        assert(address(yLAY) == precomputedYLAYAddress);

        // Step 4: Deploy sYlay at precomputedSYLAYAddress
        sYlay = new sYLAY(address(yelayOwner), address(voSPOOL), precomputedMigratorAddress);
        assert(address(sYlay) == precomputedSYLAYAddress);

        // Step 5: Deploy YelayRewardDistributor at precomputedRewardDistributorAddress
        rewardDistributor = new YelayRewardDistributor(yelayOwner);
        assert(address(rewardDistributor) == precomputedRewardDistributorAddress);

        // Step 6: Deploy YelayStaking at precomputedYelayStakingAddress
        yelayStaking = new YelayStakingHarness(
            address(yelayOwner),
            address(yLAY),
            address(sYlay),
            precomputedSYLAYRewardsAddress,
            address(rewardDistributor),
            address(spoolStaking),
            precomputedMigratorAddress
        );
        assert(address(yelayStaking) == precomputedYelayStakingAddress);

        // Step 7: Deploy Migrator at precomputedMigratorAddress
        yelayMigrator = new YelayMigrator(address(yelayOwner), yLAY, sYlay, address(yelayStaking), address(SPOOL));
        assert(address(yelayMigrator) == precomputedMigratorAddress);

        sYlayRewards = new sYLAYRewards(address(yelayStaking), address(sYlay), address(yelayOwner));
        assert(address(sYlayRewards) == precomputedSYLAYRewardsAddress);

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

        // simulate migration complete
    }

    function setUp() public {
        uint256 mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), 20734806);
        vm.selectFork(mainnetForkId);

        deployer = address(0x1);
        owner = address(0x2);
        pauser = address(0x3);
        stakeForWallet = address(0x4);
        stakeForWallet2 = address(0x5);
        user1 = address(0x6);
        user2 = address(0x7);

        contractDeployment();

        contractSetup();
    }

    /* ---------------------------------
    Section 1: Reward Configuration
    ---------------------------------- */

    function test_shouldAddOneToken() public {
        // ARRANGE
        rewardAmount = 10000 ether; // Reward amount in ether (adjust as per actual token decimals)
        rewardDuration = uint32(10 days);

        // ACT
        yelayStaking.addToken(rewardToken1, rewardDuration, rewardAmount);

        // ASSERT
        assertEq(yelayStaking.rewardTokensCount(), 1);
        assertEq(address(yelayStaking.rewardTokens(0)), address(rewardToken1));

        (uint256 rewardsDuration,, uint256 rewardRate,,) = yelayStaking.rewardConfiguration(rewardToken1);
        assertEq(rewardsDuration, rewardDuration);

        uint256 rewardRatePredicted = rewardAmount * 1e18 / rewardDuration; // Simulate calculation for reward rate
        assertApproxEqAbs(rewardRate, rewardRatePredicted, rewardRatePredicted / 10000); // Basis Points of 1 (0.01%)
    }

    function test_shouldAddTwoTokens() public {
        // ARRANGE
        rewardAmount = 10000 ether; // Reward amount in ether (adjust as per actual token decimals)
        rewardDuration = uint32(10 days); // 10 days

        // ACT
        yelayStaking.addToken(rewardToken1, rewardDuration, rewardAmount);
        yelayStaking.addToken(rewardToken2, rewardDuration, rewardAmount);

        // ASSERT
        assertEq(yelayStaking.rewardTokensCount(), 2);
        assertEq(address(yelayStaking.rewardTokens(0)), address(rewardToken1));
        assertEq(address(yelayStaking.rewardTokens(1)), address(rewardToken2));
    }

    ///* ---------------------------------
    //Section 3: Staking Operations
    //---------------------------------- */

    modifier setUpRewardRate() {
        rewardAmount = 10000 ether; // Reward amount in ether
        rewardDuration = 30 days;

        // Add reward token 1
        yelayStaking.addToken(rewardToken1, rewardDuration, rewardAmount);
        _;
    }

    function test_shouldStake() public setUpRewardRate {
        // ARRANGE
        uint256 stakeAmount = 1000 ether; // Amount to stake
        uint256 balanceBefore = yLAY.balanceOf(user1);

        // ACT
        vm.prank(user1); // Simulate user1 interaction
        yelayStaking.stake(stakeAmount);

        // ASSERT
        uint256 balanceAfter = yLAY.balanceOf(user1);
        uint256 user1BalanceDiff = balanceBefore - balanceAfter;
        assertEq(user1BalanceDiff, stakeAmount);
        assertEq(yelayStaking.balances(user1), stakeAmount);

        // Verify sYlay
        uint256 userAmount = trim(stakeAmount); // Assume trim() is a helper function, may need custom implementation
        IsYLAYBase.UserGradual memory userGradual = sYlay.getUserGradual(user1);
        assertEq(userGradual.maturingAmount, userAmount);

        // Advance time by one week
        vm.warp(block.timestamp + 1 weeks);

        // Verify sYlay after one week
        uint256 expectedMaturedAmount = getVotingPowerForTranchesPassed(stakeAmount, 1); // Assume this function exists
        uint256 sYLAYBalance = sYlay.balanceOf(user1);
        assertEq(sYLAYBalance, expectedMaturedAmount);
    }

    /// @notice Stake and wait, should receive sYlay after a week
    function test_stakeAndWait() public setUpRewardRate {
        // ARRANGE
        uint256 stakeAmount = 1000 ether; // Amount to stake

        // ACT
        vm.prank(user1); // Simulate user1 interaction
        yelayStaking.stake(stakeAmount);

        // Simulate waiting for a week
        vm.warp(block.timestamp + 1 weeks);

        // ASSERT
        // Reward 1
        uint256 earnedReward1 = yelayStaking.earned(rewardToken1, user1);
        uint256 expectedReward1 = rewardAmount * (7 days) / rewardDuration; // Calculating expected reward
        assertApproxEqAbs(earnedReward1, expectedReward1, expectedReward1 / 10000); // BasisPoints.Basis_1 (0.01%)
    }

    ///* ---------------------------------
    //Section 4: Compound
    //---------------------------------- */

    // Add YLAY reward token 1 and sYlay reward
    modifier setUpCompound() {
        rewardAmount = 10000 ether; // Reward amount in ether
        rewardDuration = uint32(10 days); // 10 days

        // Add YLAY reward token 1
        yelayStaking.addToken(IERC20(address(yLAY)), rewardDuration, rewardAmount);
        _;
    }

    /// @notice Should compound YLAY from YLAY rewards
    function test_shouldCompound() public setUpCompound {
        // ARRANGE
        uint256 stakeAmount = 100 ether; // Amount to stake
        uint256 balanceBefore = yLAY.balanceOf(user1);

        vm.prank(user1); // Simulate user1 interaction
        yelayStaking.stake(stakeAmount);

        // Simulate 4 weeks passing to accrue rewards
        vm.warp(block.timestamp + 4 weeks);

        // Calculate earned YLAY rewards
        uint256 yelayEarned = yelayStaking.earned(IERC20(address(yLAY)), user1);
        uint256 expectedYelayEarned = rewardAmount; // Expected reward amount

        assertApproxEqAbs(yelayEarned, expectedYelayEarned, expectedYelayEarned / 10000); // BasisPoints.Basis_1 (0.01%)

        // ACT - Compound the rewards
        vm.prank(user1); // Simulate user1 interaction
        yelayStaking.compound(false);

        //// ASSERT - Compounded amount and new balance
        uint256 compoundedAmount = yelayEarned;
        uint256 stakedPlusCompounded = stakeAmount + compoundedAmount;

        assertApproxEqAbs(yelayStaking.balances(user1), stakedPlusCompounded, stakedPlusCompounded / 10000); // BasisPoints.Basis_1

        //// Assert that rewards are reset after compounding
        assertEq(yelayStaking.earned(IERC20(address(yLAY)), user1), 0);

        // ACT - Unstake the compounded amount
        vm.prank(user1); // Simulate user1 interaction
        yelayStaking.unstake(stakedPlusCompounded);

        // ASSERT - Check that the user1's balance is correct after unstaking
        uint256 balanceAfter = yLAY.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, compoundedAmount); // Ensure the difference is the compounded amount
    }

    ///* ---------------------------------
    //Section 5: StakeFor
    //---------------------------------- */

    modifier setUpStakeFor() {
        rewardAmount = 10000 ether; // Reward amount in ether
        rewardDuration = uint32(30 days); // 30 days

        // Add reward token 1
        yelayStaking.addToken(rewardToken1, rewardDuration, rewardAmount);
        _;
    }

    /// @notice Should stake for user
    function test_shouldStakeForUser() public setUpStakeFor {
        // ARRANGE
        uint256 stakeAmount = 1000 ether; // Amount to stake
        uint256 balanceBefore = yLAY.balanceOf(stakeForWallet);

        // ACT
        vm.prank(stakeForWallet);
        yelayStaking.stakeFor(user1, stakeAmount);

        // ASSERT
        assertEq(yelayStaking.stakedBy(user1), stakeForWallet);

        uint256 balanceAfter = yLAY.balanceOf(stakeForWallet);
        uint256 user1balanceDiff = balanceBefore - balanceAfter;
        assertEq(user1balanceDiff, stakeAmount);
        assertEq(yelayStaking.balances(user1), stakeAmount);

        // Verify sYlay
        uint256 userAmount = trim(stakeAmount);
        IsYLAYBase.UserGradual memory userGradual = sYlay.getUserGradual(user1);
        assertEq(userGradual.maturingAmount, userAmount);

        // Simulate waiting one week
        vm.warp(block.timestamp + 1 weeks);

        // Verify sYlay after one week
        uint256 expectedMaturedAmount = getVotingPowerForTranchesPassed(stakeAmount, 1); // Assume utility function
        uint256 sYLAYBalance = sYlay.balanceOf(user1);
        assertEq(sYLAYBalance, expectedMaturedAmount);
    }

    /// @notice Stake for as owner and wait, should receive sYlay after a week
    function test_stakeForAsOwnerAndWait() public setUpStakeFor {
        // ARRANGE
        uint256 stakeAmount = 1000 ether; // Amount to stake

        // ACT
        yelayStaking.stakeFor(user1, stakeAmount);
        vm.warp(block.timestamp + 1 weeks); // Simulate waiting one week

        // ASSERT
        assertEq(yelayStaking.stakedBy(user1), address(this));

        // Reward 1
        uint256 earnedReward1 = yelayStaking.earned(rewardToken1, user1);
        uint256 expectedReward = (rewardAmount * 7 days) / rewardDuration; // Calculating expected reward
        assertApproxEqAbs(earnedReward1, expectedReward, expectedReward / 10000); // BasisPoints.Basis_1 (0.01%)
    }

    /// @notice Stake for by user, should revert
    function test_stakeForByUserShouldRevert() public setUpStakeFor {
        // ARRANGE & ACT
        vm.expectRevert("YelayStaking::canStakeForAddress: Cannot stake for other addresses");
        vm.prank(user1);
        yelayStaking.stakeFor(user2, 1000 ether);
    }

    /// @notice Stake for after user stake, should revert
    function test_stakeForAfterUserStakeShouldRevert() public setUpStakeFor {
        // ARRANGE
        vm.prank(user1);
        yelayStaking.stake(1000 ether);

        // ACT & ASSERT
        vm.expectRevert("YelayStaking::canStakeForAddress: Address already staked");
        yelayStaking.stakeFor(user1, 1000 ether);
    }

    /// @notice Stake for after stake by another address, should revert
    function test_stakeForAfterStakeByAnotherAddressShouldRevert() public setUpStakeFor {
        // ARRANGE
        vm.prank(stakeForWallet);
        yelayStaking.stakeFor(user1, 1000 ether);

        // ACT & ASSERT
        vm.expectRevert("YelayStaking::canStakeForAddress: Address staked by another address");
        vm.prank(stakeForWallet2);
        yelayStaking.stakeFor(user1, 1000 ether);
    }

    /// @notice Stake for as owner after stake for by another address, should pass
    function test_stakeForAsOwnerAfterStakeByAnotherAddressShouldPass() public setUpStakeFor {
        // ARRANGE
        vm.prank(stakeForWallet);
        yelayStaking.stakeFor(user1, 1000 ether);

        // ACT & ASSERT
        yelayStaking.stakeFor(user1, 1000 ether);
    }

    ///* ---------------------------------
    //Section 6: allowUnstakeFor
    //---------------------------------- */

    modifier setUpAllowUnstakeFor() {
        rewardAmount = 100000 ether; // Reward amount in ether
        rewardDuration = 30 days;

        // Add reward token 1
        yelayStaking.addToken(rewardToken1, rewardDuration, rewardAmount);
        _;
    }

    /// @notice Should allow unstaking after stake for user
    function test_shouldAllowUnstakingAfterStakeForUser() public setUpAllowUnstakeFor {
        // ARRANGE
        uint256 stakeAmount = 1000 ether; // Amount to stake

        vm.prank(stakeForWallet);
        yelayStaking.stakeFor(user1, stakeAmount);

        // ACT
        yelayStaking.allowUnstakeFor(user1);

        // ASSERT
        assertEq(yelayStaking.stakedBy(user1), address(0));
        vm.prank(user1);
        yelayStaking.unstake(stakeAmount);
    }

    /// @notice Should allow unstaking from Yelay after stake for user
    function test_shouldAllowUnstakingFromDAOAfterStakeForUser() public setUpAllowUnstakeFor {
        // ARRANGE
        uint256 stakeAmount = 1000 ether; // Amount to stake

        vm.prank(stakeForWallet);
        yelayStaking.stakeFor(user1, stakeAmount);

        // ACT
        vm.prank(stakeForWallet);
        yelayStaking.allowUnstakeFor(user1);

        // ASSERT
        assertEq(yelayStaking.stakedBy(user1), address(0));
        vm.prank(user1);
        yelayStaking.unstake(stakeAmount);
    }

    /// @notice Allow unstake for called by user, should revert
    function test_allowUnstakeForCalledByUserShouldRevert() public setUpAllowUnstakeFor {
        // ARRANGE
        vm.prank(stakeForWallet);
        yelayStaking.stakeFor(user1, 1000 ether);

        // ACT & ASSERT
        vm.expectRevert("YelayStaking::allowUnstakeFor: Cannot allow unstaking for address");
        vm.prank(user1);
        yelayStaking.allowUnstakeFor(user1);
    }

    /// @notice Allow unstake for called by different stake for wallet than staked for, should revert
    function test_allowUnstakeForCalledByDifferentStakeWalletShouldRevert() public setUpAllowUnstakeFor {
        // ARRANGE
        vm.prank(stakeForWallet);
        yelayStaking.stakeFor(user1, 1000 ether);

        // ACT & ASSERT
        vm.expectRevert("YelayStaking::allowUnstakeFor: Cannot allow unstaking for address");
        vm.prank(stakeForWallet2);
        yelayStaking.allowUnstakeFor(user1);
    }

    /// @notice Stake for as owner after stake for by another address, should pass
    function test_unstakeForAsOwnerAfterStakeByAnotherAddressShouldPass() public setUpAllowUnstakeFor {
        // ARRANGE
        vm.prank(stakeForWallet);
        yelayStaking.stakeFor(user1, 1000 ether);

        // ACT & ASSERT
        yelayStaking.allowUnstakeFor(user1);
    }

    ///* ---------------------------------
    //Section 7: getActiveRewards
    //---------------------------------- */

    modifier setUpGetActiveRewards() {
        rewardAmount = 100000 ether; // Reward amount in ether
        rewardDuration = 30 days;

        // Add reward token 1
        yelayStaking.addToken(rewardToken1, rewardDuration, rewardAmount);

        _;
    }

    /// @notice Stake and claim rewards after 5 weeks, should receive reward tokens
    function test_stakeAndClaimRewardsAfter5Weeks() public setUpGetActiveRewards {
        // ARRANGE
        uint256 stakeAmount = 1000 ether; // Amount to stake

        vm.prank(user1);
        yelayStaking.stake(stakeAmount);
        uint256 rewardTokenBefore = rewardToken1.balanceOf(user1);

        // Simulate passing of 5 weeks
        vm.warp(block.timestamp + 5 weeks);

        // ACT
        vm.prank(user1);
        yelayStaking.getActiveRewards(false);

        // ASSERT
        uint256 rewardTokenAfter = rewardToken1.balanceOf(user1);

        assertApproxEqAbs(rewardTokenAfter - rewardTokenBefore, rewardAmount, rewardAmount / 10000); // BasisPoints.Basis_1
    }

    ///* ---------------------------------
    //Section 8: unstake
    //---------------------------------- */

    // Modifier for the unstake test setup
    modifier setUpUnstake() {
        rewardAmount = 100000 ether; // Reward amount in ether
        rewardDuration = 30 days;

        // Add reward token 1
        yelayStaking.addToken(rewardToken1, rewardDuration, rewardAmount);

        // Simulate user1 interaction for staking and reward updates
        vm.prank(user1);

        _;
    }

    /// @notice Unstake after 5 weeks, should burn all sYlay
    function test_unstakeAfter5WeeksShouldBurnAllsYLAY() public setUpUnstake {
        // ARRANGE
        uint256 rewardTokenBefore = rewardToken1.balanceOf(user1);

        uint256 stakeAmount = 1000 ether; // Amount to stake
        vm.prank(user1);
        yelayStaking.stake(stakeAmount);

        // Simulate the passage of 5 weeks
        vm.warp(block.timestamp + 5 weeks);

        // Calculate expected matured amount for sYlay
        uint256 expectedMaturedAmount = getVotingPowerForTranchesPassed(stakeAmount, 5); // Assume utility function
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmount);

        // ACT - Unstake all
        vm.prank(user1);
        yelayStaking.unstake(stakeAmount);

        // ASSERT - After unstaking
        assertEq(yelayStaking.balances(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0); // sYlay balance should be 0

        // ACT - Claim rewards
        vm.prank(user1);
        yelayStaking.getActiveRewards(false);

        uint256 rewardTokenAfter = rewardToken1.balanceOf(user1);

        assertApproxEqAbs(rewardTokenAfter - rewardTokenBefore, rewardAmount, rewardAmount / 10000); // BasisPoints.Basis_1 (0.01%)
    }

    ///* ---------------------------------
    //Section 8: removeReward
    //---------------------------------- */

    // Modifier for the removeReward test setup
    modifier setUpRemoveReward() {
        rewardAmount = 100000 ether; // Reward amount in ether
        rewardDuration = 30 days;

        // Add 3 reward tokens
        yelayStaking.addToken(rewardToken1, rewardDuration, rewardAmount);
        yelayStaking.addToken(rewardToken2, rewardDuration, rewardAmount);
        yelayStaking.addToken(IERC20(address(yLAY)), rewardDuration, rewardAmount);

        _;
    }

    /// @notice Remove reward after the reward is finished, all rewards should still be claimable in full amount
    function test_removeRewardAfterFinishedShouldClaimFullAmount() public setUpRemoveReward {
        // ARRANGE
        vm.prank(user1);
        yelayStaking.stake(1000 ether);

        uint256 rewardToken1Before = rewardToken1.balanceOf(user1);
        uint256 rewardToken2Before = rewardToken2.balanceOf(user1);

        assertEq(yelayStaking.rewardTokensCount(), 3);

        // Simulate 5 weeks passing
        vm.warp(block.timestamp + 5 weeks);

        // ACT - remove reward token1
        yelayStaking.removeReward(rewardToken1);

        // ASSERT
        assertEq(yelayStaking.rewardTokensCount(), 2);
        // yLAY should be moved to index 0
        assertEq(address(yelayStaking.rewardTokens(0)), address(yLAY));
        assertEq(address(yelayStaking.rewardTokens(1)), address(rewardToken2));

        // Get all rewards
        vm.prank(user1);
        IERC20[] memory rewardTokens = new IERC20[](3);
        rewardTokens[0] = rewardToken1;
        rewardTokens[1] = rewardToken2;
        rewardTokens[2] = IERC20(address(yLAY));
        yelayStaking.getRewards(rewardTokens, false);

        uint256 rewardToken1After = rewardToken1.balanceOf(user1);
        uint256 rewardToken2After = rewardToken2.balanceOf(user1);

        assertApproxEqAbs(rewardToken1After - rewardToken1Before, rewardAmount, rewardAmount / 10000); // BasisPoints.Basis_1
        assertApproxEqAbs(rewardToken2After - rewardToken2Before, rewardAmount, rewardAmount / 10000); // BasisPoints.Basis_1
    }

    /// @notice End rewards early and remove reward
    function test_endRewardsEarlyAndRemoveReward() public setUpRemoveReward {
        // ARRANGE

        vm.prank(user1);
        yelayStaking.stake(1000 ether);

        assertEq(yelayStaking.rewardTokensCount(), 3);

        // Simulate 1 week passing
        vm.warp(block.timestamp + 5 weeks);

        // ACT - end rewards early and remove reward token1
        yelayStaking.updatePeriodFinish(rewardToken1, 0);
        yelayStaking.removeReward(rewardToken1);

        // ASSERT
        assertEq(yelayStaking.rewardTokensCount(), 2);
        // yLAY should be moved to index 0
        assertEq(address(yelayStaking.rewardTokens(0)), address(yLAY));
        assertEq(address(yelayStaking.rewardTokens(1)), address(rewardToken2));
    }

    ///* ---------------------------------
    //Section 9: removeReward
    //---------------------------------- */
    /// @notice Test transferUser functionality with reward rate setup
    function test_transferUser() public setUpRewardRate {
        // ARRANGE
        uint256 stakeAmount = 1000 ether; // Amount to stake

        // User1 stakes some amount
        vm.prank(user1);
        yelayStaking.stake(stakeAmount);

        // Simulate passing of 5 weeks to accumulate rewards
        vm.warp(block.timestamp + 5 weeks);

        // get user1 maturingAmount before
        IsYLAYBase.UserGradual memory user1Gradual = sYlay.getUserGradual(user1);
        IsYLAYBase.UserGradual memory user2Gradual;
        uint256 maturingAmountBefore = user1Gradual.maturingAmount;

        // Get current balances, canStakeFor, and stakedBy for user1 before transfer
        uint256 user1BalanceBefore = yelayStaking.balances(user1);
        bool user1CanStakeFor = yelayStaking.canStakeFor(user1);
        address user1StakedBy = yelayStaking.stakedBy(user1);

        // Accumulated rewards for user1
        uint256 earnedRewardToken1Before = yelayStaking.earned(rewardToken1, user1);

        // ACT - Transfer user1 data to user2
        vm.prank(user1);
        yelayStaking.transferUser(user2);

        // ASSERT - Verify user2 has all the data from user1
        assertEq(yelayStaking.balances(user2), user1BalanceBefore);
        assertEq(yelayStaking.canStakeFor(user2), user1CanStakeFor);
        assertEq(yelayStaking.stakedBy(user2), user1StakedBy);

        //// Check that user2 has the rewards transferred
        uint256 earnedRewardToken1AfterTransfer = yelayStaking.earned(rewardToken1, user2);
        assertEq(earnedRewardToken1AfterTransfer, earnedRewardToken1Before);

        //// Verify user1 has no data
        assertEq(yelayStaking.balances(user1), 0);
        assertEq(yelayStaking.stakedBy(user1), address(0));
        assertEq(yelayStaking.canStakeFor(user1), false);

        //// Assert user1 rewards are cleared
        uint256 earnedRewardToken1After = yelayStaking.earned(rewardToken1, user1);
        assertEq(earnedRewardToken1After, 0);

        //// Verify sYlay transfer was also done
        user1Gradual = sYlay.getUserGradual(user1);
        user2Gradual = sYlay.getUserGradual(user2);

        assertEq(user1Gradual.maturingAmount, 0);
        assertEq(user2Gradual.maturingAmount, maturingAmountBefore);
    }
}

contract YelayStakingHarness is YelayStaking {

    constructor(
        address _owner,
        address _yLAY,
        address _sYlay,
        address _sYlayRewards,
        address _rewardDistributor,
        address _spoolStaking,
        address _migrator
    ) YelayStaking(_owner, _yLAY, _sYlay, _sYlayRewards, _rewardDistributor, _spoolStaking, _migrator) {}

    function stake(uint256 amount) public override {
        YelayStakingBase.stake(amount);
    }

    function stakeFor(address user, uint256 amount) public override {
        YelayStakingBase.stakeFor(user, amount);
    }
}
