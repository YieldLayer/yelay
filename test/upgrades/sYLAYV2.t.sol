// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

import {IYelayOwner} from "src/interfaces/IYelayOwner.sol";
import {YelayStaking} from "src/YelayStaking.sol";
import {sYLAY} from "src/sYLAY.sol";

contract sYLAYV2Test is Test {
    address owner = 0x4e736b96920a0f305022CBaAea493Ce7e49Eee6C;
    ProxyAdmin proxyAdmin = ProxyAdmin(0x51c8FA2c1F093AC643f6431766b1c227d869Cb6F);
    YelayStaking yelayStaking = YelayStaking(0x8e933387AFc6F0F67588e5Dac33EBa97eF988C69);
    sYLAY sylay = sYLAY(0xC0F7B477e05B29097546dAae2E3dF2decBeB405d);
    IERC20 ylay = IERC20(0xAEe5913FFd19dBcA4Fd1eF6F3925ed0414407d37);

    function setUp() public {
        uint256 mainnetForkId = vm.createFork(vm.rpcUrl("mainnet"), 23268420);
        vm.selectFork(mainnetForkId);
    }

    function test_upgrade_and_unstake() external {
        address user = 0xe058564c235f06f5dF394B68bE97dc4867f64c89;
        sYLAY newsYLAY = new sYLAY(IYelayOwner(0xAB865D95A574511a6c893C38A4D892275ca70570));

        uint256 stakingAmount = yelayStaking.balances(user);
        uint256 balanceBefore = ylay.balanceOf(user);

        assertGt(stakingAmount, 0, "Non zero staking amount");

        vm.startPrank(user);
        vm.expectRevert();
        yelayStaking.unstake(stakingAmount);
        vm.stopPrank();

        assertEq(ylay.balanceOf(user), balanceBefore, "No YLAY balance change");

        assertNotEq(
            proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(sylay)))), address(newsYLAY)
        );

        vm.startPrank(owner);
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(sylay))), address(newsYLAY));
        vm.stopPrank();

        assertEq(
            proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(sylay)))), address(newsYLAY)
        );

        vm.startPrank(user);
        yelayStaking.unstake(stakingAmount);
        vm.stopPrank();

        uint256 balanceAfter = ylay.balanceOf(user);

        assertEq(balanceAfter - balanceBefore, stakingAmount, "All YLAY is unstaked");
    }
}
