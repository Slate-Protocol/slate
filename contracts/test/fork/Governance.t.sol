// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SignedSource} from "../../src/sources/SignedSource.sol";
import {ForkTest} from "./Fork.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// The decentralisation runbook, rehearsed against the live testnet contracts: the signer set only changes through the
/// 48-hour timelock, a new set (including an independent signer) takes effect after the delay, and the market calendar
/// moves under the same timelock.
contract RobinhoodTestnetGovernanceForkTest is ForkTest {
    SignedSource internal constant SOURCE = SignedSource(0x8B27311a3493a85E063f97e4bB59cf3a22aEA507);
    TimelockController internal constant TIMELOCK =
        TimelockController(payable(0xFc42883Ae9ac9FeCE9A3b656f30D356775Fe2270));
    USMarketCalendar internal constant CALENDAR = USMarketCalendar(0xf0b57272f1D69083019E8953B82bC128002D7526);
    address internal constant DEPLOYER = 0xBBfFdd1Baf34AeAb21F2fFdDfbd2b64489BD4999;
    bytes32 internal constant FEED = bytes32("GOV/USD"); // a feed id no live feed uses

    function setUp() public {
        _fork("rh_testnet");
    }

    function test_ownership_isTheTimelock_with48Hours() public view {
        assertEq(SOURCE.owner(), address(TIMELOCK));
        assertEq(TIMELOCK.getMinDelay(), 48 hours);
        assertTrue(TIMELOCK.hasRole(TIMELOCK.PROPOSER_ROLE(), DEPLOYER));
        assertTrue(TIMELOCK.hasRole(TIMELOCK.DEFAULT_ADMIN_ROLE(), address(TIMELOCK))); // roles change only via the delay
        assertFalse(TIMELOCK.hasRole(TIMELOCK.DEFAULT_ADMIN_ROLE(), DEPLOYER));
    }

    function test_runbook_addAnIndependentSigner() public {
        // Four keys: three stand in for Slate's, the fourth is the independent operator's. Quorum 3 of 4.
        Signer[] memory s = _signers(4);
        address[] memory next = new address[](4);
        for (uint256 i; i < 4; ++i) {
            next[i] = s[i].addr;
        }
        bytes memory call = abi.encodeCall(SignedSource.setSigners, (next, 3));
        bytes32 salt = keccak256(call);

        // Nobody but the timelock can set signers, not even the deployer.
        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEPLOYER));
        SOURCE.setSigners(next, 3);

        // Only a proposer can schedule.
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        TIMELOCK.schedule(address(SOURCE), 0, call, bytes32(0), salt, 48 hours);

        vm.prank(DEPLOYER);
        TIMELOCK.schedule(address(SOURCE), 0, call, bytes32(0), salt, 48 hours);

        // Not executable one second early.
        vm.warp(block.timestamp + 48 hours - 1);
        vm.prank(DEPLOYER);
        vm.expectRevert();
        TIMELOCK.execute(address(SOURCE), 0, call, bytes32(0), salt);

        vm.warp(block.timestamp + 1);
        vm.prank(DEPLOYER);
        TIMELOCK.execute(address(SOURCE), 0, call, bytes32(0), salt);
        assertEq(SOURCE.signers(), next);
        assertEq(SOURCE.quorum(), 3);

        // Two of Slate's three keys are no longer enough; with the independent signer, three of four are.
        Signer[] memory two = new Signer[](2);
        (two[0], two[1]) = (s[0], s[1]);
        bytes memory short = _report(SOURCE.domainSeparator(), FEED, two, _same(2, 100e8), uint64(block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(SignedSource.QuorumNotMet.selector, 2, 3));
        SOURCE.submit(FEED, short);

        Signer[] memory three = new Signer[](3);
        (three[0], three[1], three[2]) = (s[0], s[1], s[3]);
        SOURCE.submit(FEED, _report(SOURCE.domainSeparator(), FEED, three, _same(3, 100e8), uint64(block.timestamp)));
        assertEq(SOURCE.observe(FEED).price, 100e8);
    }

    function test_runbook_calendarUnderTheTimelock() public {
        bytes memory accept = abi.encodeWithSignature("acceptOwnership()");
        bytes32 salt = keccak256("slate: calendar under the timelock");
        bytes32 id = TIMELOCK.hashOperation(address(CALENDAR), 0, accept, bytes32(0), salt);
        // The handover may already be underway (or done) on the live chain; pick up from wherever it is.
        vm.startPrank(DEPLOYER);
        if (CALENDAR.owner() == DEPLOYER && CALENDAR.pendingOwner() != address(TIMELOCK)) {
            CALENDAR.transferOwnership(address(TIMELOCK));
        }
        if (!TIMELOCK.isOperation(id)) TIMELOCK.schedule(address(CALENDAR), 0, accept, bytes32(0), salt, 48 hours);
        if (!TIMELOCK.isOperationDone(id)) {
            vm.warp(TIMELOCK.getTimestamp(id));
            TIMELOCK.execute(address(CALENDAR), 0, accept, bytes32(0), salt);
        }
        vm.stopPrank();
        assertEq(CALENDAR.owner(), address(TIMELOCK));

        uint256[] memory day = new uint256[](1);
        day[0] = block.timestamp / 1 days + 30;
        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, DEPLOYER));
        CALENDAR.setDays(day, USMarketCalendar.DayKind.HOLIDAY);
    }
}
