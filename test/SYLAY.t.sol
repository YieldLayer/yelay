// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "spool-core/SpoolOwner.sol";

import "test/mocks/MockToken.sol";
import "test/shared/Utilities.sol";
import "src/YLAY.sol";
import {VoSPOOL} from "spool/VoSPOOL.sol";
import "spool-staking-and-voting/RewardDistributor.sol";
import "spool-staking-and-voting/SpoolStaking.sol";
import {sYLAY, IsYLAYBase} from "src/sYLAY.sol";
import "src/YelayOwner.sol";
import {YelayStaking} from "src/YelayStaking.sol";
import "src/YelayMigrator.sol";
import "src/libraries/ConversionLib.sol";

contract SYLAYTest is Test, Utilities {
    // known addresses
    // TODO as constants
    SpoolStaking spoolStaking = SpoolStaking(0xc3160C5cc63B6116DD182faA8393d3AD9313e213);
    IERC20PausableOwnable SPOOL = IERC20PausableOwnable(0x40803cEA2b2A32BdA1bE61d3604af6a814E70976);
    VoSPOOL voSPOOL = VoSPOOL(0xaF56D16a7fe479F2fcD48FF567fF589CB2d2a0E9);

    // new
    YelayOwner yelayOwner;
    ISpoolOwner spoolOwner;
    YLAY yLAY;
    sYLAY sYlay;
    RewardDistributor rewardDistributor;
    YelayStaking yelayStaking;
    YelayMigrator yelayMigrator;

    IERC20 rewardToken1;
    IERC20 rewardToken2;

    address deployer;
    address owner;
    address minter;
    address gradualMinter;
    address user1;
    address user2;
    address user3;
    address user4;

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

        // Step 2: Deploy SpoolOwner at precomputedYLAYAddress
        spoolOwner = new SpoolOwner();
        assert(address(spoolOwner) == precomputedSpoolOwnerAddress);

        // Step 3: Deploy YLAY at precomputedYLAYAddress
        new YLAY(yelayOwner, precomputedMigratorAddress);
        yLAY = YLAY(address(new ERC1967Proxy(precomputedYLAYImplementationAddress, "")));
        assert(address(yLAY) == precomputedYLAYAddress);

        // Step 4: Deploy sYLAY at precomputedSYLAYAddress
        // sYlay = new sYLAY(address(yelayOwner), address(voSPOOL), precomputedMigratorAddress);
        sYlay = new sYLAY(address(yelayOwner), address(voSPOOL));
        assert(address(sYlay) == precomputedSYLAYAddress);

        // Step 5: Deploy RewardDistributor at precomputedRewardDistributorAddress
        rewardDistributor = new RewardDistributor(spoolOwner);
        assert(address(rewardDistributor) == precomputedRewardDistributorAddress);

        // Step 6: Deploy YelayStaking at precomputedYelayStakingAddress
        yelayStaking = new YelayStaking(
            address(spoolOwner),
            address(yLAY),
            address(sYlay),
            // TODO: add sYlayRewards
            address(0x10),
            address(rewardDistributor),
            address(spoolStaking),
            precomputedMigratorAddress
        );
        assert(address(yelayStaking) == precomputedYelayStakingAddress);

        // Step 7: Deploy Migrator at precomputedMigratorAddress
        yelayMigrator = new YelayMigrator(address(spoolOwner), yLAY, sYlay, address(yelayStaking), address(SPOOL));
        assert(address(yelayMigrator) == precomputedMigratorAddress);

        yLAY.initialize();
        yelayStaking.initialize();

        // TODO:
        sYlay.initialize();

        rewardToken1 = IERC20(new MockToken("TEST", "TEST"));
        rewardToken2 = IERC20(new MockToken("TEST", "TEST"));
    }

    function contractSetup() public {
        sYlay.setGradualMinter(gradualMinter, true);
        // migrate all global tranches from voSPOOL to sYLAY.
        uint256 numIndexes = (voSPOOL.getCurrentTrancheIndex() / 5) + 1;
        console.log("num indexes: ", numIndexes);
        uint256 _gasBefore = gasleft();
        vm.prank(gradualMinter);
        sYlay.migrateGlobalTranches(numIndexes);
        console.log("fully migrated: ", sYlay.migrationComplete());
        uint256 _gasUsed = _gasBefore - gasleft();
        console.log("Gas used for migrateGlobalTranches: ", _gasUsed);
    }

    function setUp() public {
        uint256 mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), 20734806);
        vm.selectFork(mainnetForkId);

        deployer = address(0x1);
        owner = address(0x2);
        minter = address(0x3);
        gradualMinter = address(0x4);
        user1 = address(0x6);
        user2 = address(0x7);
        user3 = address(0x8);
        user4 = address(0x9);

        contractDeployment();

        contractSetup();
    }

    /* ---------------------------------
    Section 1: Deployment Verification
    ---------------------------------- */
    function test_sYLAYDeploymentVerify() public view {
        // ASSERT - ERC20 values
        assertEq(sYlay.name(), "Staked Yelay");
        assertEq(sYlay.symbol(), "sYLAY");
        assertEq(sYlay.decimals(), 18);
        assertEq(sYlay.balanceOf(user1), 0);

        // ASSERT - Gradual power constants
        assertEq(sYlay.FULL_POWER_TRANCHES_COUNT(), 52 * 4);
        assertEq(sYlay.TRANCHE_TIME(), 1 weeks);
        assertEq(sYlay.FULL_POWER_TIME(), 1 weeks * (52 * 4));

        // ASSERT - Tranche timing
        assertEq(sYlay.firstTrancheStartTime(), voSPOOL.firstTrancheStartTime());
        assertEq(sYlay.getNextTrancheEndTime(), voSPOOL.getNextTrancheEndTime());
        assertEq(sYlay.getCurrentTrancheIndex(), voSPOOL.getCurrentTrancheIndex());
    }

    /* ---------------------------------
    Section 2: Gradual Voting Power
    ---------------------------------- */
    // Modifier for setting up the gradual voting power tests
    modifier setUpGradualVotingPower() {
        // Deploy contracts and set the gradual minter
        spoolOwner = new SpoolOwner();

        // Set gradual minter
        sYlay.setGradualMinter(gradualMinter, true);

        _;
    }

    /// @notice Gradual voting power
    function test_mintGradualPowerToUser() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        uint256 totalSupplyBefore = sYlay.totalSupply();

        // ACT
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);

        // ASSERT
        assertEq(sYlay.getUserGradualVotingPower(user1), 0); // User should have 0 power at first
        assertEq(sYlay.totalInstantPower(), ConversionLib.convert(voSPOOL.totalInstantPower())); // Total instant power should be 0
        assertEq(sYlay.balanceOf(user1), 0); // User should have 0 balance initially
        assertEq(sYlay.totalSupply(), totalSupplyBefore); // Supply should not have changed initially
    }

    /// @notice Mint gradual power to user, user should have 1/208th power after a week
    function test_mintGradualPowerAfterOneWeek() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        // ACT
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);

        // Simulate the passage of one week
        vm.warp(block.timestamp + 1 weeks);

        // ASSERT
        uint256 expectedMaturedAmount = getVotingPowerForTranchesPassed(mintAmount, 1); // Assume this utility function exists

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount);
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmount);
    }

    /// @notice Mint gradual power to user, user should have 52/208th power after 52 weeks
    function test_mintGradualPowerAfter52Weeks() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        // ACT
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);

        // Simulate the passage of 52 weeks
        vm.warp(block.timestamp + 52 weeks);

        // ASSERT
        uint256 expectedMaturedAmount = getVotingPowerForTranchesPassed(mintAmount, 52); // Assume this utility function exists

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount);
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmount);
    }

    /// @notice Mint gradual power to user, user should have full power after 208 weeks
    function test_mintGradualPowerAfterFullPeriod() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        // ACT
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);

        // Simulate the passage of 208 weeks
        vm.warp(block.timestamp + 208 weeks);

        // ASSERT
        assertEq(sYlay.getUserGradualVotingPower(user1), mintAmount);
        assertEq(sYlay.balanceOf(user1), mintAmount);
    }

    /// @notice Mint gradual power to user, user should have full power after 209 weeks
    function test_mintGradualPowerAfter209Weeks() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        // ACT
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);

        // Simulate the passage of 209 weeks
        vm.warp(block.timestamp + 209 weeks);

        // ASSERT
        assertEq(sYlay.getUserGradualVotingPower(user1), mintAmount);
        assertEq(sYlay.balanceOf(user1), mintAmount);
    }

    /// @notice Mint gradual power to user, user should have full power after 208 weeks and on
    function test_mintGradualPowerAfter208WeeksAndBeyond() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        // ACT
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);

        // Simulate the passage of 232 weeks (beyond the full power period)
        vm.warp(block.timestamp + 232 weeks);

        // ASSERT
        assertEq(sYlay.getUserGradualVotingPower(user1), mintAmount);
        assertEq(sYlay.balanceOf(user1), mintAmount);
    }

    /// @notice Should mint gradual power to multiple users
    function test_mintGradualPowerToMultipleUsers() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount1 = 1000 ether; // Mint amount for user1
        uint256 mintAmount2 = 2000 ether; // Mint amount for user2
        uint256 mintAmount3 = 3000 ether; // Mint amount for user3

        // ACT
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount1);
        sYlay.mintGradual(user2, mintAmount2);
        sYlay.mintGradual(user3, mintAmount3);
        vm.stopPrank();

        // Simulate the passage of 52 weeks
        vm.warp(block.timestamp + 52 weeks);

        // ASSERT
        uint256 expectedMaturedAmount1 = getVotingPowerForTranchesPassed(mintAmount1, 52);
        uint256 expectedMaturedAmount2 = getVotingPowerForTranchesPassed(mintAmount2, 52);
        uint256 expectedMaturedAmount3 = getVotingPowerForTranchesPassed(mintAmount3, 52);

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount1);
        assertEq(sYlay.getUserGradualVotingPower(user2), expectedMaturedAmount2);
        assertEq(sYlay.getUserGradualVotingPower(user3), expectedMaturedAmount3);
    }

    /// @notice Wait 200 weeks, then mint gradual power to multiple users
    function test_wait200WeeksThenMintGradualPowerToMultipleUsers() public setUpGradualVotingPower {
        // ARRANGE
        console.log("currentTrancheIndex: ", sYlay.getCurrentTrancheIndex());
        vm.warp(block.timestamp + 200 weeks); // Simulate the passage of 200 weeks

        uint256 mintAmount1 = 1000 ether; // Mint amount for user1
        uint256 mintAmount2 = 2000 ether; // Mint amount for user2
        uint256 mintAmount3 = 3000 ether; // Mint amount for user3

        //// ACT
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount1);
        sYlay.mintGradual(user2, mintAmount2);
        sYlay.mintGradual(user3, mintAmount3);
        vm.stopPrank();

        // Simulate the passage of 52 weeks
        vm.warp(block.timestamp + 52 weeks);

        //// ASSERT
        uint256 expectedMaturedAmount1 = getVotingPowerForTranchesPassed(mintAmount1, 52);
        uint256 expectedMaturedAmount2 = getVotingPowerForTranchesPassed(mintAmount2, 52);
        uint256 expectedMaturedAmount3 = getVotingPowerForTranchesPassed(mintAmount3, 52);

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount1);
        assertEq(sYlay.getUserGradualVotingPower(user2), expectedMaturedAmount2);
        assertEq(sYlay.getUserGradualVotingPower(user3), expectedMaturedAmount3);
    }

    /// @notice Mint gradual power to user over multiple periods
    function test_mintGradualPowerOverMultiplePeriods() public setUpGradualVotingPower {
        // ARRANGE
        vm.warp(block.timestamp + 200 weeks); // Simulate the passage of 200 weeks

        uint256 mintAmount = 1000 ether; // Mint amount in ether
        uint256 weeksPassed = 52;

        // ACT
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + weeksPassed * 1 weeks);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + weeksPassed * 1 weeks);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + weeksPassed * 1 weeks);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + weeksPassed * 1 weeks);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + weeksPassed * 1 weeks);
        vm.stopPrank();

        // ASSERT
        uint256 expectedMaturedAmount1 = getVotingPowerForTranchesPassed(mintAmount, weeksPassed);
        uint256 expectedMaturedAmount2 = getVotingPowerForTranchesPassed(mintAmount, weeksPassed * 2);
        uint256 expectedMaturedAmount3 = getVotingPowerForTranchesPassed(mintAmount, weeksPassed * 3);
        uint256 expectedMaturedAmount4 = getVotingPowerForTranchesPassed(mintAmount, weeksPassed * 4);
        uint256 expectedMaturedAmount5 = getVotingPowerForTranchesPassed(mintAmount, weeksPassed * 5);

        uint256 expectedMaturedAmountTotal = expectedMaturedAmount1 + expectedMaturedAmount2 + expectedMaturedAmount3
            + expectedMaturedAmount4 + expectedMaturedAmount5;

        assertApproxEqAbs(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmountTotal, 1);
        assertApproxEqAbs(sYlay.balanceOf(user1), expectedMaturedAmountTotal, 1);
    }

    /// @notice Mint gradual power to user over multiple periods and wait for all to mature, should have full power in amount of all mints
    function test_mintGradualPowerMultiplePeriodsAndWaitForFullMaturity() public setUpGradualVotingPower {
        // ARRANGE
        vm.warp(block.timestamp + 104 weeks); // Simulate the passage of 104 weeks

        uint256 mintAmount = 1000 ether; // Mint amount in ether

        // ACT
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + 52 weeks);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + 52 weeks);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + 52 weeks);
        sYlay.mintGradual(user1, mintAmount);
        vm.warp(block.timestamp + 52 weeks);
        sYlay.mintGradual(user1, mintAmount);
        vm.stopPrank();

        // Simulate the passage of 4 years (full maturity period)
        vm.warp(block.timestamp + 208 weeks);

        vm.prank(gradualMinter);
        sYlay.updateVotingPower();

        //// ASSERT
        uint256 expectedMaturedAmount = mintAmount * 5;

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount);
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmount);
    }

    /// @notice Mint 0 gradual power to user, should return without action
    function test_mintZeroGradualPowerToUser() public setUpGradualVotingPower {
        // ARRANGE
        // ACT
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, 0);

        // ASSERT
        // User gradual power details
        IsYLAYBase.UserGradual memory userGradual = sYlay.getUserGradual(user1);

        assertEq(userGradual.maturingAmount, 0);
        assertEq(userGradual.rawUnmaturedVotingPower, 0);
        assertEq(userGradual.maturedVotingPower, 0);

        // Global gradual power details
        IsYLAYBase.GlobalGradual memory globalGradual = sYlay.getGlobalGradual();
        assertEq(globalGradual.totalMaturedVotingPower, 0);
    }

    /// @notice Mint and burn gradual power to user, user and global gradual should change values accordingly
    function test_mintAndBurnGradualPower() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether
        IsYLAYBase.GlobalGradual memory globalGradual = sYlay.getGlobalGradual();
        uint256 totalMaturingAmountBefore = globalGradual.totalMaturingAmount;
        uint256 totalRawUnmaturedVotingPowerBefore = globalGradual.totalRawUnmaturedVotingPower;
        uint256 totalMaturedVotingPowerBefore = globalGradual.totalMaturedVotingPower;
        uint256 lastUpdatedTrancheIndexBefore = globalGradual.lastUpdatedTrancheIndex;

        // ACT - mint gradual 3 times
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        sYlay.mintGradual(user1, mintAmount);
        sYlay.mintGradual(user1, mintAmount);
        vm.stopPrank();

        // ASSERT - Initial gradual values
        uint256 userAmount = trim(mintAmount * 3);

        // User gradual checks
        IsYLAYBase.UserGradual memory userGradual = sYlay.getUserGradual(user1);
        assertEq(userGradual.maturingAmount, userAmount);
        assertEq(userGradual.rawUnmaturedVotingPower, 0);
        assertEq(userGradual.maturedVotingPower, 0);
        assertEq(userGradual.lastUpdatedTrancheIndex, lastUpdatedTrancheIndexBefore);

        // Global gradual checks
        globalGradual = sYlay.getGlobalGradual();
        assertEq(globalGradual.totalMaturingAmount, totalMaturingAmountBefore + userAmount);
        assertEq(globalGradual.totalRawUnmaturedVotingPower, totalRawUnmaturedVotingPowerBefore);
        assertEq(globalGradual.totalMaturedVotingPower, totalMaturedVotingPowerBefore);
        assertEq(globalGradual.lastUpdatedTrancheIndex, lastUpdatedTrancheIndexBefore);

        //// ARRANGE - pass 52 weeks
        uint256 weeksPassed = 52;
        vm.warp(block.timestamp + (weeksPassed * 1 weeks));

        //// ASSERT - User gradual after 52 weeks
        userGradual = sYlay.getUserGradual(user1);
        assertEq(userGradual.maturingAmount, userAmount);
        assertEq(userGradual.rawUnmaturedVotingPower, userAmount * weeksPassed);
        assertEq(userGradual.maturedVotingPower, 0);
        assertEq(userGradual.lastUpdatedTrancheIndex, lastUpdatedTrancheIndexBefore + 52);

        //// Global gradual after 52 weeks
        globalGradual = sYlay.getGlobalGradual();
        assertEq(globalGradual.totalMaturingAmount, totalMaturingAmountBefore + userAmount);
        assertEq(globalGradual.totalMaturedVotingPower, 0);
        assertEq(globalGradual.lastUpdatedTrancheIndex, lastUpdatedTrancheIndexBefore + 52);

        //// ACT - Mint gradual one more time
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        vm.stopPrank();
        uint256 userAmount2 = userAmount + trim(mintAmount);

        //// ASSERT - User gradual after minting again
        userGradual = sYlay.getUserGradual(user1);
        assertEq(userGradual.maturingAmount, userAmount2);
        assertEq(userGradual.rawUnmaturedVotingPower, userAmount * weeksPassed);
        assertEq(userGradual.maturedVotingPower, 0);
        assertEq(userGradual.lastUpdatedTrancheIndex, lastUpdatedTrancheIndexBefore + 52);

        //// Global gradual after minting again
        globalGradual = sYlay.getGlobalGradual();
        assertEq(globalGradual.totalMaturingAmount, totalMaturingAmountBefore + userAmount2);
        assertEq(globalGradual.totalMaturedVotingPower, 0);
        assertEq(globalGradual.lastUpdatedTrancheIndex, lastUpdatedTrancheIndexBefore + 52);
    }

    /// @notice Burn all gradual power from user, all gradual user power should reset
    function test_burnAllGradualPower() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        // Start minting gradual power
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 52 weeks);

        // ACT - Burn all gradual power
        vm.prank(gradualMinter);
        sYlay.burnGradual(user1, mintAmount, false);
        vm.warp(block.timestamp + 52 weeks);

        // ASSERT - All values should reset
        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);
    }

    /// @notice Burn all gradual power from user (using burnAll flag), all gradual user power should reset
    function test_burnAllGradualPowerUsingBurnAllFlag() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        // Start minting gradual power
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 52 weeks);

        // ACT - Burn all gradual power using the burnAll flag
        vm.prank(gradualMinter);
        sYlay.burnGradual(user1, 0, true);
        vm.warp(block.timestamp + 52 weeks);

        // ASSERT - All values should reset
        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);
    }

    /// @notice Burn gradual power from user in same tranche as mint multiple times, all gradual user power should reset and start accumulating again
    function test_burnGradualPowerInSameTrancheMultipleTimes() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether
        uint256 burnAmount = mintAmount / 2; // Half of mint amount for burning

        // ACT - Mint and burn gradual power multiple times
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        sYlay.burnGradual(user1, burnAmount, false);
        sYlay.mintGradual(user1, mintAmount);
        sYlay.burnGradual(user1, mintAmount, false);
        sYlay.mintGradual(user1, mintAmount);
        sYlay.burnGradual(user1, mintAmount, false);
        vm.stopPrank();

        // ASSERT - All values should reset
        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);

        // ARRANGE - Wait for 52 weeks to pass to accumulate power
        uint256 weeksPassed = 52;
        vm.warp(block.timestamp + weeksPassed * 1 weeks);
        vm.prank(gradualMinter);
        sYlay.updateVotingPower();

        // ASSERT - Check gradual power accumulation after 52 weeks
        uint256 expectedMaturedAmount = getVotingPowerForTranchesPassed(mintAmount - burnAmount, weeksPassed);

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount);
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmount);
    }

    /// @notice Burn half gradual power from user, all gradual user power should reset and start accumulating again
    function test_burnHalfGradualPower() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 52 weeks);

        uint256 burnAmount = mintAmount / 2;

        // ACT - Burn half gradual power
        vm.prank(gradualMinter);
        sYlay.burnGradual(user1, burnAmount, false);

        // ASSERT - All values should reset after burning half
        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);

        // ARRANGE - Wait for 52 weeks to pass to accumulate power again
        uint256 weeksPassed = 52;
        vm.warp(block.timestamp + weeksPassed * 1 weeks);
        vm.prank(gradualMinter);
        sYlay.updateVotingPower();

        // ASSERT - Gradual voting power should accumulate again
        uint256 expectedMaturedAmount = getVotingPowerForTranchesPassed(mintAmount - burnAmount, weeksPassed);

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount);
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmount);
    }

    /// @notice Burn gradual power from user (round up amount), burn amount should round up by 1
    function test_burnGradualPowerRoundUp() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether
        IsYLAYBase.GlobalGradual memory globalGradual = sYlay.getGlobalGradual();
        uint256 totalMaturingAmountBefore = globalGradual.totalMaturingAmount;

        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 52 weeks);

        globalGradual = sYlay.getGlobalGradual();

        uint256 burnAmount = (mintAmount / 2) + 1; // Round up

        // ACT - Burn gradual power with round up
        vm.prank(gradualMinter);
        sYlay.burnGradual(user1, burnAmount, false);

        // ASSERT - User gradual and global gradual should reflect rounded up amount
        uint256 burnAmountRoundUp = trim(burnAmount) + 1;
        uint256 userAmountTrimmed = trim(mintAmount) - burnAmountRoundUp;

        // User gradual
        IsYLAYBase.UserGradual memory userGradual = sYlay.getUserGradual(user1);
        assertEq(userGradual.maturingAmount, userAmountTrimmed);

        // Global gradual
        globalGradual = sYlay.getGlobalGradual();
        console.log("totalMaturingAmountBefore");
        console.log(totalMaturingAmountBefore);
        console.log("globalGradual.totalMaturingAmount");
        console.log(globalGradual.totalMaturingAmount);
        console.log("userAmountTrimmed");
        console.log(userAmountTrimmed);
        // console.log(globalGradual.totalMaturingAmount + userAmountTrimmed);
        // TODO: something has changed here!
        assertEq(globalGradual.totalMaturingAmount, totalMaturingAmountBefore + userAmountTrimmed);
    }

    /// @notice Mint gradual to user 1 and 2, burn gradual from user 1, user 2 power should stay the same
    function test_burnGradualUser1User2PowerUnchanged() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        sYlay.mintGradual(user2, mintAmount);
        vm.stopPrank();

        uint256 weeksPassed = 52;
        vm.warp(block.timestamp + weeksPassed * 1 weeks);

        uint256 burnAmount = mintAmount / 2;

        // ACT - Burn gradual from user 1
        vm.prank(gradualMinter);
        sYlay.burnGradual(user1, burnAmount, false);
        uint256 user1PowerAmount = mintAmount - burnAmount;

        // ASSERT - User 2 power remains unchanged, user 1 power resets
        uint256 user2expectedMaturedAmount52Weeks = getVotingPowerForTranchesPassed(mintAmount, weeksPassed);

        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.getUserGradualVotingPower(user2), user2expectedMaturedAmount52Weeks);

        assertEq(sYlay.balanceOf(user1), 0);
        assertEq(sYlay.balanceOf(user2), user2expectedMaturedAmount52Weeks);

        // ARRANGE - Wait for 52 weeks for power accumulation
        vm.warp(block.timestamp + weeksPassed * 1 weeks);
        vm.prank(gradualMinter);
        sYlay.updateVotingPower();

        // ASSERT - Check both users' accumulated power after 52 more weeks
        uint256 user1expectedMaturedAmount52Weeks = getVotingPowerForTranchesPassed(user1PowerAmount, weeksPassed);
        uint256 user2expectedMaturedAmount104Weeks = getVotingPowerForTranchesPassed(mintAmount, weeksPassed * 2);

        assertEq(sYlay.getUserGradualVotingPower(user1), user1expectedMaturedAmount52Weeks);
        assertEq(sYlay.getUserGradualVotingPower(user2), user2expectedMaturedAmount104Weeks);

        assertEq(sYlay.balanceOf(user1), user1expectedMaturedAmount52Weeks);
        assertEq(sYlay.balanceOf(user2), user2expectedMaturedAmount104Weeks);

        // ARRANGE - Wait for both users' power to fully mature
        vm.warp(block.timestamp + 156 weeks); // Advance 3 years
        vm.prank(gradualMinter);
        sYlay.updateVotingPower();

        // ASSERT - Final fully-matured values for user 1 and user 2
        uint256 user2PowerAmount = mintAmount;

        assertEq(sYlay.getUserGradualVotingPower(user1), user1PowerAmount);
        assertEq(sYlay.getUserGradualVotingPower(user2), user2PowerAmount);

        assertEq(sYlay.balanceOf(user1), user1PowerAmount);
        assertEq(sYlay.balanceOf(user2), user2PowerAmount);
    }

    /// @notice Burn gradual power from user multiple times, all gradual user power should reset and start accumulating again every time
    function test_burnGradualPowerMultipleTimes() public setUpGradualVotingPower {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount in ether

        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);

        vm.warp(block.timestamp + 156 weeks); // Simulate the passage of 3 years

        uint256 burnAmount = mintAmount / 10;

        // ACT - Burn gradual partial amount
        vm.prank(gradualMinter);
        sYlay.burnGradual(user1, burnAmount, false);

        // ASSERT - After first burn, all power should reset
        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);

        // ARRANGE - Wait for 60 weeks to pass
        vm.warp(block.timestamp + 60 weeks);

        //// ACT - Burn gradual partial amount two more times
        vm.startPrank(gradualMinter);
        sYlay.burnGradual(user1, burnAmount, false);
        sYlay.burnGradual(user1, burnAmount, false);
        vm.stopPrank();

        //// ASSERT - All values should reset again
        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);

        // ARRANGE - Wait for 1 week to pass
        uint256 weeksPassed1 = 1;
        vm.warp(block.timestamp + weeksPassed1 * 1 weeks);

        // ASSERT - Check accumulated power after burns
        uint256 userAmountAfterBurn = mintAmount - burnAmount * 3;
        uint256 expectedMaturedAmount1 = getVotingPowerForTranchesPassed(userAmountAfterBurn, weeksPassed1);

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount1);
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmount1);

        // ACT - Mint gradual 2000
        uint256 mintAmount2 = 2000 ether;
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount2);

        // ASSERT - Power should remain unchanged immediately after mint
        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmount1);
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmount1);

        // ARRANGE - Pass 207 weeks
        uint256 weeksPassed207 = 207;
        vm.warp(block.timestamp + weeksPassed207 * 1 weeks);

        // ASSERT - Check accumulated power after 207 weeks
        uint256 expectedMaturedAmount2 =
            getVotingPowerForTranchesPassed(userAmountAfterBurn, weeksPassed1 + weeksPassed207);
        uint256 expectedMaturedAmount3 = getVotingPowerForTranchesPassed(mintAmount2, weeksPassed207);
        uint256 expectedMaturedAmountTotal1 = expectedMaturedAmount2 + expectedMaturedAmount3;

        assertEq(sYlay.getUserGradualVotingPower(user1), expectedMaturedAmountTotal1);
        assertEq(sYlay.balanceOf(user1), expectedMaturedAmountTotal1);

        // ARRANGE - Pass 1 more week
        vm.warp(block.timestamp + 1 weeks);

        // ASSERT - Fully matured user power after another week
        uint256 userAmountEnd1 = userAmountAfterBurn + mintAmount2;
        assertEq(sYlay.getUserGradualVotingPower(user1), userAmountEnd1);
        assertEq(sYlay.balanceOf(user1), userAmountEnd1);

        // ACT - Burn gradual partial amount (100)
        vm.prank(gradualMinter);
        sYlay.burnGradual(user1, burnAmount, false);

        //// ASSERT - Power reset after burn
        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);

        //// ARRANGE - Wait for power to fully mature
        vm.warp(block.timestamp + 208 weeks); // Simulate 4 more years
        vm.prank(gradualMinter);
        sYlay.updateUserVotingPower(user1);

        //// ASSERT - Final power values after full maturation post-burn
        uint256 userAmountEnd2 = userAmountEnd1 - burnAmount;
        assertEq(sYlay.getUserGradualVotingPower(user1), userAmountEnd2);
        assertEq(sYlay.balanceOf(user1), userAmountEnd2);

        //// ACT - Burn all gradual power
        vm.prank(gradualMinter);
        sYlay.burnGradual(user1, 0, true);

        //// ARRANGE - Wait for power to fully mature again
        vm.warp(block.timestamp + 208 weeks); // Simulate 4 more years

        //// ASSERT - All power reset after burning all
        assertEq(sYlay.getUserGradualVotingPower(user1), 0);
        assertEq(sYlay.balanceOf(user1), 0);
    }

    /// @notice Test get tranche index and time view functions
    function test_getTrancheIndexAndTimeViewFunctions() public setUpGradualVotingPower {
        // ARRANGE
        uint256 firstTrancheStartTime = sYlay.firstTrancheStartTime();
        uint256 currentTrancheIndex = sYlay.getCurrentTrancheIndex();
        uint256 currentTrancheTime = sYlay.getTrancheEndTime(currentTrancheIndex);

        uint256 blockTimestamp = block.timestamp;

        // ASSERT - Revert if time is before the first tranche start time
        vm.expectRevert("sYLAY::getTrancheIndex: Time must be more or equal to the first tranche time");
        sYlay.getTrancheIndex(firstTrancheStartTime - 1 weeks);

        // ARRANGE - Pass 1 week
        uint256 weeksPassed1 = 1;
        vm.warp(block.timestamp + weeksPassed1 * 1 weeks);

        // ACT / ASSERT - Check tranche index and end time after 1 week
        blockTimestamp = block.timestamp;
        uint256 index = sYlay.getTrancheIndex(blockTimestamp);
        assertEq(index, currentTrancheIndex + weeksPassed1);

        // ARRANGE - Pass 50 weeks
        uint256 weeksPassed50 = 50;
        vm.warp(block.timestamp + weeksPassed50 * 1 weeks);

        //// ACT / ASSERT - Check tranche index and end time after 50 more weeks
        blockTimestamp = block.timestamp;
        index = sYlay.getTrancheIndex(blockTimestamp);
        assertEq(index, currentTrancheIndex + (weeksPassed1 + weeksPassed50));

        uint256 trancheEndTime = sYlay.getTrancheEndTime(currentTrancheIndex + (weeksPassed1 + weeksPassed50));
        assertEq(trancheEndTime, currentTrancheTime + (1 weeks * (weeksPassed1 + weeksPassed50)));
    }

    /// @notice Mint and burn as a user, should revert
    function test_mintAndBurnAsUserShouldRevert() public setUpGradualVotingPower {
        // ARRANGE
        uint256 amount = 1000 ether; // Mint amount in ether

        // ACT / ASSERT - Attempt to mint and burn without minter privileges
        vm.expectRevert("sYLAY::_onlyGradualMinter: Insufficient Privileges");
        sYlay.mintGradual(user2, amount);

        vm.expectRevert("sYLAY::_onlyGradualMinter: Insufficient Privileges");
        sYlay.burnGradual(user2, amount, false);
    }

    /* ---------------------------------
    Section 3: Contract Owner Functions
    ---------------------------------- */

    /// @notice Should add minting rights
    function test_addMintingRights() public {
        // ARRANGE
        assertFalse(sYlay.minters(minter));

        // ACT
        sYlay.setMinter(minter, true);

        // ASSERT
        assertTrue(sYlay.minters(minter));
        assertTrue(sYlay.gradualMinters(gradualMinter));
    }

    /// @notice Should remove minting rights
    function test_removeMintingRights() public {
        // ARRANGE
        sYlay.setMinter(minter, true);
        sYlay.setGradualMinter(gradualMinter, true);

        // ACT
        sYlay.setMinter(minter, false);
        sYlay.setGradualMinter(gradualMinter, false);

        // ASSERT
        assertFalse(sYlay.minters(minter));
        assertFalse(sYlay.gradualMinters(gradualMinter));
    }

    /// @notice Set minter as zero address, should revert
    function test_setMinterAsZeroAddressShouldRevert() public {
        // ACT / ASSERT
        vm.expectRevert("sYLAY::setMinter: minter cannot be the zero address");
        sYlay.setMinter(address(0), true);

        vm.expectRevert("sYLAY::setGradualMinter: gradual minter cannot be the zero address");
        sYlay.setGradualMinter(address(0), true);
    }

    /// @notice Set minter as user, should revert
    function test_setMinterAsUserShouldRevert() public {
        // ACT / ASSERT
        vm.prank(user1);
        vm.expectRevert("YelayOwnable::onlyOwner: Caller is not the Yelay owner");
        sYlay.setMinter(minter, true);

        vm.prank(user1);
        vm.expectRevert("YelayOwnable::onlyOwner: Caller is not the Yelay owner");
        sYlay.setGradualMinter(gradualMinter, true);
    }

    /* -------------------------------------------
    Section 4: Contract ERC20 prohibited functions
    ---------------------------------------------- */
    /// @notice Test prohibited actions, should revert
    function test_prohibitedERC20ActionsShouldRevert() public {
        // ACT / ASSERT - Prohibited transfer
        vm.expectRevert("sYLAY::transfer: Prohibited Action");
        sYlay.transfer(address(0), 100);

        // ACT / ASSERT - Prohibited transferFrom
        vm.expectRevert("sYLAY::transferFrom: Prohibited Action");
        sYlay.transferFrom(address(0), address(0), 100);

        // ACT / ASSERT - Prohibited approve
        vm.expectRevert("sYLAY::approve: Prohibited Action");
        sYlay.approve(address(0), 100);

        // ACT / ASSERT - Prohibited allowance
        vm.expectRevert("sYLAY::allowance: Prohibited Action");
        sYlay.allowance(address(0), address(0));
    }

    /* -------------------------------------------
    Section 5: User Transfer
    ---------------------------------------------- */

    /// @notice Test transferUser functionality with normal flow
    function test_transferUserNormal() public {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount for user1

        // Mint gradual for user1
        vm.prank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);

        // Pass half the maturity time
        uint256 weeksToPass = 208 / 2;
        vm.warp(block.timestamp + (1 weeks * weeksToPass));

        // Update user1's power
        vm.prank(gradualMinter);
        sYlay.updateUserVotingPower(user1);

        // Check user1's gradual amounts before transfer
        IsYLAYBase.UserGradual memory user1Gradual = sYlay.getUserGradual(user1);
        uint256 user1MaturingAmount = user1Gradual.maturingAmount;
        uint256 user1RawUnmaturedVotingPower = user1Gradual.rawUnmaturedVotingPower;
        assertEq(user1MaturingAmount, trim(mintAmount));
        assertEq(user1RawUnmaturedVotingPower, trim(mintAmount) * weeksToPass);

        // ACT - Transfer user data from user1 to user2
        vm.expectRevert("sYLAY::_onlyGradualMinter: Insufficient Privileges");
        sYlay.transferUser(user1, user2);

        IsYLAYBase.UserGradual memory user1GradualBefore = sYlay.getUserGradual(user1);
        vm.prank(gradualMinter);
        sYlay.transferUser(user1, user2);

        // ASSERT - Verify user1 has nothing and user2 has the same amounts
        IsYLAYBase.UserGradual memory user1GradualAfter = sYlay.getNotUpdatedUserGradual(user1);
        assertEq(user1GradualAfter.maturedVotingPower, 0);
        assertEq(user1GradualAfter.maturingAmount, 0);
        assertEq(user1GradualAfter.rawUnmaturedVotingPower, 0);
        assertEq(user1GradualAfter.lastUpdatedTrancheIndex, 0);

        IsYLAYBase.UserGradual memory user2Gradual = sYlay.getUserGradual(user2);
        assertEq(user2Gradual.maturedVotingPower, user1GradualBefore.maturedVotingPower);
        assertEq(user2Gradual.maturingAmount, user1GradualBefore.maturingAmount);
        assertEq(user2Gradual.rawUnmaturedVotingPower, user1GradualBefore.rawUnmaturedVotingPower);
        assertEq(user2Gradual.lastUpdatedTrancheIndex, user1GradualBefore.lastUpdatedTrancheIndex);

        //// ARRANGE - Pass additional time (10 weeks)
        uint256 additionalWeeks = 10;
        vm.warp(block.timestamp + (1 weeks * additionalWeeks));

        //// ACT - Update user2's power after additional time
        vm.prank(gradualMinter);
        sYlay.updateUserVotingPower(user2);

        //// ASSERT - Verify user2's power updates accordingly
        user2Gradual = sYlay.getUserGradual(user2);
        assertEq(user2Gradual.maturingAmount, trim(mintAmount));
        assertEq(user2Gradual.rawUnmaturedVotingPower, trim(mintAmount) * (weeksToPass + additionalWeeks));
    }

    /// @notice Test transferUser should fail if the target user already exists or the source user does not exist
    function test_transferUserFail() public {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount for user1 and user2

        // Mint gradual for user1 and user2
        vm.startPrank(gradualMinter);
        sYlay.mintGradual(user1, mintAmount);
        sYlay.mintGradual(user2, mintAmount);
        vm.stopPrank();

        // ACT / ASSERT - Attempt to transfer from user1 to user2 (user2 already exists)
        vm.startPrank(gradualMinter);
        vm.expectRevert("sYLAY::migrate: User already exists");
        sYlay.transferUser(user1, user2); // Should revert because user2 already exists
        vm.stopPrank();

        // Mint gradual for user3 (exist) and leave user4 empty (does not exist)
        vm.prank(gradualMinter);
        sYlay.mintGradual(user3, mintAmount);

        // ACT / ASSERT - Attempt to transfer from user4 to user3 (user4 does not exist)
        vm.startPrank(gradualMinter);
        vm.expectRevert("sYLAY::migrate: User does not exist");
        sYlay.transferUser(user4, user3); // Should revert because user4 does not exist
        vm.stopPrank();
    }
}
