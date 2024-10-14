// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import "src/YLAYArbitrumMigration.sol";

contract YLAYArbitrumTest is Test {
    event Lock(address indexed sender, address indexed receiver, uint256 amount);

    YLAYArbitrumMigration ylayArbitrumMigration;

    address spoolHolder = 0x835785C823e3c19c37cb6e2C616C278738947978;

    function setUp() public {
        uint256 arbitrumForkId = vm.createFork(vm.rpcUrl("arbitrum"), 256836081);
        vm.selectFork(arbitrumForkId);

        address impl = address(new YLAYArbitrumMigration());
        ylayArbitrumMigration = YLAYArbitrumMigration(address(new TransparentUpgradeableProxy(impl, address(0x01), "")));
    }

    function test_scenario() external {
        IERC20 spool = ylayArbitrumMigration.SPOOL();
        uint256 balance = spool.balanceOf(spoolHolder);

        assertEq(spool.balanceOf(address(ylayArbitrumMigration)), 0);
        assertGt(spool.balanceOf(spoolHolder), 0);

        uint256 firstAmount = 100;
        uint256 secondAmount = balance - firstAmount;
        address secondReceiver = address(0x02);

        vm.startPrank(spoolHolder);
        spool.approve(address(ylayArbitrumMigration), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit Lock(spoolHolder, spoolHolder, firstAmount);
        ylayArbitrumMigration.lock(spoolHolder, firstAmount);

        assertEq(spool.balanceOf(address(ylayArbitrumMigration)), firstAmount);

        vm.expectEmit(true, true, true, true);
        emit Lock(spoolHolder, secondReceiver, secondAmount);
        ylayArbitrumMigration.lock(secondReceiver, secondAmount);

        assertEq(spool.balanceOf(address(ylayArbitrumMigration)), balance);
        assertEq(spool.balanceOf(spoolHolder), 0);
    }
}
