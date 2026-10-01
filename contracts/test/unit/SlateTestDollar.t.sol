// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateTestDollar} from "../../src/testnet/SlateTestDollar.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";

contract SlateTestDollarTest is Test {
    SlateTestDollar internal usd;
    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");

    function setUp() public {
        vm.warp(1_790_780_400);
        usd = new SlateTestDollar(owner);
    }

    /// The name and symbol must never be confusable with USDG or TrueUSD (TUSD).
    function test_identity() public view {
        assertEq(usd.name(), "Slate Test Dollar");
        assertEq(usd.symbol(), "TESTUSD");
        assertEq(usd.decimals(), 6);
    }

    function test_faucet_oncePerDay() public {
        vm.startPrank(user);
        usd.faucet();
        assertEq(usd.balanceOf(user), 10_000e6);
        vm.expectRevert(abi.encodeWithSelector(SlateTestDollar.FaucetCooldown.selector, block.timestamp + 1 days));
        usd.faucet();
        vm.warp(block.timestamp + 1 days);
        usd.faucet();
        assertEq(usd.balanceOf(user), 20_000e6);
        vm.stopPrank();
    }

    function test_mint_onlyOwner() public {
        vm.prank(owner);
        usd.mint(user, 1e12);
        assertEq(usd.balanceOf(user), 1e12);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        usd.mint(user, 1);
    }
}
