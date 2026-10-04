// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus, Quote} from "../../src/interfaces/ISlateFeed.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

/// @dev Drives a SlateFeed configured like CRWD's on mainnet (maxAge 40 min, 30 min grace, 5% large change,
///      serves the last price while the market is closed, 24/5 session, the real on-chain calendar) through random
///      share prices of any age, scheduled multiplier changes (splits, reverse splits, small adjustments,
///      overwritten schedules), poke() calls or their absence, pauses and time jumps across weekends.
///
///      The handler keeps the token's true multiplier history, which the chain itself does not: a token reports
///      only its latest switch. After every action it reads the feed the way a lending market does and records any
///      served price that is not share price × the multiplier truly in force when that price was observed.
contract SlateFeedHandler is Test {
    uint256 internal constant ONE = 1e18;

    SlateFeed public immutable feed;
    MockStockToken public immutable token;
    MockPriceSource public immutable source;

    struct Switch {
        uint256 at;
        uint256 multiplier;
    }

    Switch[] internal history;
    int256 internal sharePrice; // 8 decimals, as the source holds it
    uint256 internal observedAt;
    bool internal paused;

    // Violations: each must stay zero.
    uint256 public servedWrongMultiplier;
    uint256 public servedNonPositive;
    uint256 public servedWithRefusingStatus;
    uint256 public servedStaleWhileOpen;
    uint256 public servedWhilePaused;
    uint256 public refusedWithServingStatus;
    /// Known gap, disclosed (docs: Security and limitations): a price observed before a switch that a later schedule
    /// has hidden from the token. Counted separately so every other wrong multiplier still fails the run.
    uint256 public servedWrongMultiplierHiddenSwitch;

    // Coverage: proof the run reached the cases that matter.
    uint256 public served;
    uint256 public servedAcrossASwitch; // price observed before the token's latest switch, still served correctly
    uint256 public refusedStraddle;
    uint256 public refusedCorporateAction;
    uint256 public refusedStale;
    uint256 public servedMarketClosed;
    uint256 public switches;

    // The first violation, kept for diagnosis.
    struct Case {
        uint256 now_;
        uint256 observed;
        int256 share;
        int256 answer;
        uint256 expected;
        uint256 feedMultiplier;
        uint256 trueMultiplier;
        uint256 tokenCurrent;
        uint256 tokenEffectiveAt;
        uint256 snapOld;
        uint256 snapAt;
        uint8 status;
        uint256 historyLength;
    }

    Case internal firstBad;

    constructor(SlateFeed feed_, MockStockToken token_, MockPriceSource source_) {
        feed = feed_;
        token = token_;
        source = source_;
        history.push(Switch(0, ONE));
    }

    /// The multiplier truly in force at `t`, from the full history.
    function multiplierAt(uint256 t) public view returns (uint256 m) {
        m = ONE;
        for (uint256 i; i < history.length; ++i) {
            if (history[i].at <= t) m = history[i].multiplier;
        }
    }

    /// Mostly fresh prices (as the publisher posts them), sometimes old ones, sometimes slightly in the future.
    function setPrice(uint64 price, uint32 age, uint8 mode) external {
        sharePrice = int256(bound(price, 1e8, 1e12)); // $1 to $10,000 a share
        mode = uint8(bound(mode, 0, 5));
        if (mode <= 3) observedAt = block.timestamp - bound(age, 0, feed.maxAge());
        else if (mode == 4) observedAt = block.timestamp - bound(age, 0, 3 days);
        else observedAt = block.timestamp + bound(age, 0, 60);
        source.set(sharePrice, 8, observedAt);
        _check();
    }

    function schedule(uint8 kind, uint64 small, uint32 delay) external {
        kind = uint8(bound(kind, 0, 5));
        uint256 m = multiplierAt(block.timestamp);
        uint256 next;
        if (kind == 0) next = m * 4; // 4:1 split
        else if (kind == 1) next = m / 4; // 1:4 reverse split
        else if (kind == 2) next = m * 2;
        else if (kind == 3) next = m;
        else next = m + (m * bound(small, 1, 300)) / 10_000; // small adjustments, 0.01% to 3%, as the census shows
        if (next == 0 || next > 1e24) return;
        uint256 at = block.timestamp + bound(delay, 0, 1 hours);
        // A new schedule overwrites any pending one, exactly as Robinhood's token does.
        while (history.length > 1 && history[history.length - 1].at > block.timestamp) history.pop();
        token.updateMultiplier(next, at);
        history.push(Switch(at, next));
        ++switches;
        _check();
    }

    function poke() external {
        feed.poke();
        _check();
    }

    function pause(bool on) external {
        paused = on;
        token.setOraclePaused(on);
        _check();
    }

    /// Minutes to hours: prices age, staged switches take effect, sessions close.
    function warp(uint32 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 6 hours));
        _check();
    }

    /// Across a weekend or a holiday.
    function jump(uint32 dt) external {
        vm.warp(block.timestamp + bound(dt, 1 days, 3 days));
        _check();
    }

    /// Whether a switch after `t` has already happened but is no longer the one the token reports.
    function _switchHidden(uint256 t) internal view returns (bool) {
        for (uint256 i; i < history.length; ++i) {
            uint256 at = history[i].at;
            if (at > t && at <= block.timestamp && at != token.effectiveAt()) return true;
        }
        return false;
    }

    function _check() internal {
        (Quote memory q,,) = feed.latestDetail();
        bool serves = q.status == FeedStatus.OK || q.status == FeedStatus.MARKET_CLOSED; // allowMarketClosed is true
        try feed.latestRoundData() returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80) {
            ++served;
            if (!serves) ++servedWithRefusingStatus;
            if (answer <= 0) ++servedNonPositive;
            if (paused) ++servedWhilePaused;
            uint256 t = updatedAt; // = min(observedAt, now)
            uint256 expected = (uint256(sharePrice) * multiplierAt(t)) / ONE;
            if (uint256(answer) != expected && _switchHidden(t)) {
                ++servedWrongMultiplierHiddenSwitch;
            } else if (uint256(answer) != expected) {
                if (servedWrongMultiplier == 0) _keep(t, answer, expected, uint8(q.status));
                ++servedWrongMultiplier;
            }
            if (q.status == FeedStatus.OK && block.timestamp - t > feed.maxAge()) ++servedStaleWhileOpen;
            if (q.status == FeedStatus.MARKET_CLOSED) ++servedMarketClosed;
            if (t < token.effectiveAt() && token.effectiveAt() <= block.timestamp) ++servedAcrossASwitch;
        } catch {
            if (serves) ++refusedWithServingStatus;
            if (q.status == FeedStatus.STRADDLE) ++refusedStraddle;
            if (q.status == FeedStatus.CORPORATE_ACTION) ++refusedCorporateAction;
            if (q.status == FeedStatus.STALE) ++refusedStale;
        }
    }

    function _keep(uint256 t, int256 answer, uint256 expected, uint8 status) internal {
        (, int256 sp, uint256 fm) = feed.latestDetail();
        (uint96 so,, uint64 sa) = feed.snapshot();
        firstBad = Case(
            block.timestamp,
            t,
            sp,
            answer,
            expected,
            fm,
            multiplierAt(t),
            token.uiMultiplier(),
            token.effectiveAt(),
            so,
            sa,
            status,
            history.length
        );
    }

    function logFirstBad() external view {
        Case memory c = firstBad;
        console.log("now", c.now_, "observed", c.observed);
        console.logInt(c.share);
        console.logInt(c.answer);
        console.log("expected", c.expected, "status", c.status);
        console.log("feed multiplier", c.feedMultiplier, "true multiplier", c.trueMultiplier);
        console.log("token current", c.tokenCurrent, "token effectiveAt", c.tokenEffectiveAt);
        console.log("snapshot old", c.snapOld, "snapshot at", c.snapAt);
        console.log("history length", c.historyLength);
    }
}

contract SlateFeedInvariantTest is Test {
    SlateFeed internal feed;
    SlateFeedHandler internal handler;

    function setUp() public {
        vm.warp(1_790_780_400); // Wed 30 Sep 2026 15:00 UTC
        USMarketCalendar calendar = new USMarketCalendar(address(this));
        MockStockToken token = new MockStockToken("CrowdStrike", "CRWD");
        MockPriceSource source = new MockPriceSource(PriceKind.RAW_UNDERLYING);
        feed = new SlateFeed(
            SlateFeed.Config({
                token: address(token),
                model: MultiplierModel.ERC8056,
                source: source,
                feedId: bytes32("CRWD/USD"),
                maxAge: 2400,
                corporateActionGrace: 1800,
                largeChangeBps: 500,
                allowMarketClosed: true,
                calendar: calendar,
                session: Session.EXTENDED,
                description: "CRWD / USD"
            })
        );
        handler = new SlateFeedHandler(feed, token, source);
        targetContract(address(handler));
    }

    /// Whenever the feed serves a price, it is the share price × the multiplier truly in force when that price was
    /// observed: never the multiplier of a later switch, never a guess across one. The one disclosed exception, a
    /// switch hidden by a later schedule, is counted apart in servedWrongMultiplierHiddenSwitch.
    function invariant_servesOnlyTheMultiplierInForceAtObservation() public view {
        if (handler.servedWrongMultiplier() > 0) handler.logFirstBad();
        assertEq(handler.servedWrongMultiplier(), 0, "served a price with the wrong multiplier");
    }

    /// It serves only with a serving status (OK, or market closed where allowed), never while paused, never a
    /// non-positive answer, never a stale price while the market is open; and it never refuses with a serving status.
    function invariant_servesOnlyWhenItShould() public view {
        assertEq(handler.servedWithRefusingStatus(), 0, "served while its status says refuse");
        assertEq(handler.refusedWithServingStatus(), 0, "refused while its status says serve");
        assertEq(handler.servedWhilePaused(), 0, "served while the token's oracle is paused");
        assertEq(handler.servedNonPositive(), 0, "served a non-positive answer");
        assertEq(handler.servedStaleWhileOpen(), 0, "served a stale price with the market open");
    }

    /// Coverage, logged (not asserted: a short shrunk sequence may legitimately serve nothing). With
    /// INVARIANT_COVERAGE=1, each run's counts are appended to cache/invariant-coverage.csv for totals.
    function afterInvariant() external {
        console.log("served", handler.served(), "served across a switch", handler.servedAcrossASwitch());
        console.log("known gap hit (hidden switch)", handler.servedWrongMultiplierHiddenSwitch());
        if (vm.envOr("INVARIANT_COVERAGE", false)) {
            vm.writeLine(
                "cache/invariant-coverage.csv",
                string.concat(
                    vm.toString(handler.served()),
                    ",",
                    vm.toString(handler.servedAcrossASwitch()),
                    ",",
                    vm.toString(handler.servedMarketClosed()),
                    ",",
                    vm.toString(handler.refusedStraddle()),
                    ",",
                    vm.toString(handler.refusedCorporateAction()),
                    ",",
                    vm.toString(handler.refusedStale()),
                    ",",
                    vm.toString(handler.switches()),
                    ",",
                    vm.toString(handler.servedWrongMultiplierHiddenSwitch())
                )
            );
        }
    }
}
