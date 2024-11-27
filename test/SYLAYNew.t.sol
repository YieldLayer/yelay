// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "spool/external/spool-core/SpoolOwner.sol";

import {MockToken} from "test/mocks/MockToken.sol";
import "test/shared/Utilities.sol";
import "src/YLAY.sol";
import {VoSPOOL} from "spool/VoSPOOL.sol";
import {SpoolStaking} from "spool/SpoolStaking.sol";
import {sYLAY, IsYLAYBase} from "src/sYLAY.sol";
import {sYLAYRewards} from "src/sYLAYRewards.sol";
import {YelayOwner} from "src/YelayOwner.sol";
import {YelayRewardDistributor} from "src/YelayRewardDistributor.sol";
import {YelayStaking} from "src/migration/YelayStaking.sol";
import "src/YelayMigrator.sol";
import "src/libraries/ConversionLib.sol";

contract SYLAYNewTest is Test, Utilities {
    // new
    YelayOwner yelayOwner;
    sYLAY sYlay;

    address deployer;
    address owner = address(0x01);
    address gradualMinter = address(0x02);
    address user1 = address(0x03);
    address user2 = address(0x04);

    function setUp() public {
        vm.startPrank(owner);
        yelayOwner = new YelayOwner();
        sYlay = new sYLAY(yelayOwner);
        sYlay.setGradualMinter(gradualMinter, true);
        vm.stopPrank();
    }

    function test_transferUserNormal() public {
        // ARRANGE
        uint256 mintAmount = 1000 ether; // Mint amount for user1

        uint256 currentTranche = sYlay.getCurrentTrancheIndex();

        // Mint gradual for user1
        vm.prank(gradualMinter);
        sYlay.mintLockup(user1, mintAmount, currentTranche + 5);

        // Pass half the maturity time
        uint256 weeksToPass = 208 / 2;
        vm.warp(block.timestamp + (1 weeks * weeksToPass));

        vm.prank(gradualMinter);
        sYlay.transferUser(user1, user2);

        vm.prank(user1);
        vm.expectRevert("sYLAY::continueLockup: No lockup position found");
        sYlay.continueLockup(currentTranche, currentTranche + 100);
    }
}
