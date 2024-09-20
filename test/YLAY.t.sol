    // SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "src/YLAY.sol";
import "./mocks/YLAY2.sol";
import "src/YelayOwner.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract YLAYTest is Test {
    YLAY ylay;
    YelayOwner yelayOwner;

    address migrator = address(0x01);
    address owner = address(0x02);

    function setUp() external {
        vm.startPrank(owner);
        yelayOwner = new YelayOwner();

        address yelayImpl = address(new YLAY(yelayOwner, migrator));
        ylay = YLAY(address(new ERC1967Proxy(yelayImpl, abi.encodeWithSelector(YLAY.initialize.selector))));
        vm.stopPrank();
    }

    function test_ylay() external {
        vm.expectRevert();
        ylay.initialize();

        uint256 totalSupply = 1_000_000_000e18;

        assertEq(ylay.totalSupply(), totalSupply);
        assertEq(ylay.balanceOf(address(ylay)), totalSupply);

        address yelayImpl2 = address(new YLAY2(yelayOwner, migrator));

        vm.expectRevert();
        ylay.upgradeTo(yelayImpl2);

        vm.startPrank(owner);
        ylay.upgradeTo(yelayImpl2);
        vm.stopPrank();

        assertEq(YLAY2(address(ylay)).version(), 2);

        vm.expectRevert();
        ylay.pause();

        vm.startPrank(owner);
        ylay.pause();
        vm.stopPrank();
        assertTrue(ylay.paused());

        vm.expectRevert();
        ylay.unpause();

        vm.startPrank(owner);
        ylay.unpause();
        vm.stopPrank();
        assertFalse(ylay.paused());

        vm.expectRevert();
        ylay.claim(address(this), 1);

        vm.startPrank(owner);
        ylay.claim(owner, 12);
        vm.stopPrank();
        assertEq(ylay.balanceOf(owner), 12);

        vm.startPrank(migrator);
        ylay.claim(migrator, 13);
        vm.stopPrank();
        assertEq(ylay.balanceOf(migrator), 13);

        assertEq(ylay.balanceOf(address(ylay)), totalSupply - 12 - 13);
    }
}
