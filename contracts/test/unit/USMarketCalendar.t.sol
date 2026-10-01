// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus} from "../../src/interfaces/ISlateFeed.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Expected timestamps were computed independently from the IANA tz database (America/New_York) and
///      NYSE's published holiday calendar; the comments give the New York local time.
contract USMarketCalendarTest is Test {
    USMarketCalendar internal cal;

    function setUp() public {
        vm.warp(1_790_780_400); // Wed 30 Sep 2026
        cal = new USMarketCalendar(address(this));
    }

    function _closed(uint256 ts, Session s) internal view returns (uint256) {
        return cal.closedSince(ts, s);
    }

    // ---------------------------------------------------------------- holidays

    function test_thanksgiving2026_closedAllDay_regularAndExtended() public view {
        uint256 thanksgivingNoon = 1_795_712_400; // Thu 26 Nov 2026 12:00
        assertEq(_closed(thanksgivingNoon, Session.REGULAR), 1_795_640_400); // Wed 25 Nov 16:00
        assertEq(_closed(thanksgivingNoon, Session.EXTENDED), 1_795_654_800); // Wed 25 Nov 20:00
    }

    function test_dayAfterThanksgiving2026_isAnEarlyClose() public view {
        assertEq(_closed(1_795_789_800, Session.REGULAR), 0); // Fri 27 Nov 09:30, open
        assertEq(_closed(1_795_802_340, Session.REGULAR), 0); // 12:59, open
        assertEq(_closed(1_795_802_400, Session.REGULAR), 1_795_802_400); // 13:00, closed
        assertEq(_closed(1_795_802_400, Session.EXTENDED), 0); // late session runs to 17:00
        assertEq(_closed(1_795_816_800, Session.EXTENDED), 1_795_816_800); // 17:00, closed
    }

    function test_goodFriday2026_closed_thenReopensSundayEvening() public view {
        uint256 goodFridayNoon = 1_775_232_000; // Fri 3 Apr 2026 12:00
        assertEq(_closed(goodFridayNoon, Session.REGULAR), 1_775_160_000); // Thu 2 Apr 16:00
        assertEq(_closed(goodFridayNoon, Session.EXTENDED), 1_775_174_400); // Thu 2 Apr 20:00
        assertEq(_closed(1_775_433_600, Session.EXTENDED), 0); // Sun 5 Apr 20:00, Monday's session opens
        assertEq(_closed(1_775_482_200, Session.REGULAR), 0); // Mon 6 Apr 09:30
    }

    function test_juneteenth_2026_and_observed2027() public view {
        assertEq(_closed(1_781_884_800, Session.REGULAR), 1_781_812_800); // Fri 19 Jun 2026 -> Thu 18 Jun 16:00
        assertEq(_closed(1_813_334_400, Session.REGULAR), 1_813_262_400); // Fri 18 Jun 2027 (observed) -> Thu 17 Jun 16:00
    }

    function test_july3_2028_earlyClose_thenIndependenceDay() public view {
        assertEq(_closed(1_846_256_340, Session.REGULAR), 0); // Mon 3 Jul 2028 12:59, open
        assertEq(_closed(1_846_256_400, Session.REGULAR), 1_846_256_400); // 13:00, closed
        assertEq(_closed(1_846_270_800, Session.EXTENDED), 1_846_270_800); // 17:00, late session over
        assertEq(_closed(1_846_339_200, Session.REGULAR), 1_846_256_400); // Tue 4 Jul 12:00, still Monday's close
        assertEq(_closed(1_846_416_600, Session.REGULAR), 0); // Wed 5 Jul 09:30
    }

    function test_holidayMonday_closedSinceFridayClose() public view {
        assertEq(_closed(1_768_842_000, Session.REGULAR), 1_768_597_200); // MLK Mon 19 Jan 2026 -> Fri 16 Jan 16:00
    }

    // ---------------------------------------------------------------- daylight saving

    function test_dstTransitionDays() public view {
        assertEq(uint256(20_520 + 4) % 7, 0); // 2026-03-08 is a Sunday
        assertFalse(cal.isDst(20_520, 1 hours + 59 minutes));
        assertTrue(cal.isDst(20_520, 3 hours));
        assertTrue(cal.isDst(20_758, 1 hours + 30 minutes)); // 2026-11-01 01:30, first pass, still EDT
        assertFalse(cal.isDst(20_758, 2 hours));
        assertTrue(cal.isDst(20_891, 12 hours)); // 2027-03-14
        assertFalse(cal.isDst(21_129, 12 hours)); // 2027-11-07
        assertTrue(cal.isDst(21_255, 12 hours)); // 2028-03-12
        assertFalse(cal.isDst(21_493, 12 hours)); // 2028-11-05
        assertFalse(cal.isDst(20_890, 12 hours)); // 2027-03-13, day before
    }

    /// Spring forward: Friday closes at 16:00 EST (21:00 UTC); Monday opens at 09:30 EDT (13:30 UTC).
    function test_springForwardWeekend2026() public view {
        assertEq(_closed(1_773_014_400 - 1, Session.REGULAR), 1_772_830_800); // Sun 8 Mar 19:59 -> Fri 16:00 EST
        assertEq(_closed(1_773_014_400, Session.EXTENDED), 0); // Sun 8 Mar 20:00 EDT, extended opens
        assertEq(_closed(1_773_063_000, Session.REGULAR), 0); // Mon 9 Mar 09:30 EDT
        assertEq(_closed(1_773_063_000 - 1, Session.REGULAR), 1_772_830_800);
    }

    /// Fall back: Friday closes at 16:00 EDT (20:00 UTC); Monday opens at 09:30 EST (14:30 UTC).
    function test_fallBackWeekend2026() public view {
        assertEq(_closed(1_793_581_200 - 1, Session.EXTENDED), 1_793_390_400 + 4 hours); // Fri 30 Oct 20:00 EDT
        assertEq(_closed(1_793_581_200, Session.EXTENDED), 0); // Sun 1 Nov 20:00 EST
        assertEq(_closed(1_793_629_800, Session.REGULAR), 0); // Mon 2 Nov 09:30 EST
        assertEq(_closed(1_793_629_800 - 1, Session.REGULAR), 1_793_390_400); // Fri 30 Oct 16:00 EDT
    }

    // ---------------------------------------------------------------- coverage and maintenance

    function test_beyondCoverage_weekdaysAreTradingDays() public view {
        assertEq(cal.coveredThrough(), 21_549); // 2028-12-31
        assertTrue(cal.isTradingDay(21_564)); // MLK Day 2029, not yet loaded
    }

    function test_setDays_futureOnly_onlyOwner() public {
        uint256[] memory d = new uint256[](1);
        d[0] = 21_564;
        cal.setDays(d, USMarketCalendar.DayKind.HOLIDAY);
        assertFalse(cal.isTradingDay(21_564));

        d[0] = 20_726; // today, Wed 30 Sep 2026
        vm.expectRevert(abi.encodeWithSelector(USMarketCalendar.DayAlreadyStarted.selector, 20_726));
        cal.setDays(d, USMarketCalendar.DayKind.HOLIDAY);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        cal.setDays(d, USMarketCalendar.DayKind.HOLIDAY);
    }

    function test_extendCoverage_isMonotonic() public {
        cal.extendCoverage(21_914);
        assertEq(cal.coveredThrough(), 21_914);
        vm.expectRevert(USMarketCalendar.CoverageCannotShrink.selector);
        cal.extendCoverage(21_914);
    }

    // ---------------------------------------------------------------- wired into SlateFeed

    /// The bug this calendar fixes: on Thanksgiving a Wednesday-evening price is closed, not stale.
    function test_slateFeed_reportsThanksgivingAsMarketClosed() public {
        MockPriceSource src = new MockPriceSource(PriceKind.RAW_UNDERLYING);
        SlateFeed feed = new SlateFeed(
            SlateFeed.Config({
                token: address(new MockStockToken("CrowdStrike", "CRWD")),
                model: MultiplierModel.ERC8056,
                source: src,
                feedId: bytes32("CRWD/USD"),
                maxAge: 15 minutes,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: true,
                calendar: cal,
                session: Session.EXTENDED,
                description: "CRWD / USD"
            })
        );
        vm.warp(1_795_654_800 - 5 minutes); // Wed 25 Nov 2026 19:55
        src.set(26_498_000_000, 8, block.timestamp);
        vm.warp(1_795_712_400); // Thanksgiving noon
        assertEq(uint8(feed.status()), uint8(FeedStatus.MARKET_CLOSED));
        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, 26_498_000_000);

        vm.warp(1_795_789_800); // Fri 27 Nov 09:30: the session is open again and the price is old
        assertEq(uint8(feed.status()), uint8(FeedStatus.STALE));
    }
}
