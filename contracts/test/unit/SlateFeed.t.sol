// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus, ISlateFeed, Quote} from "../../src/interfaces/ISlateFeed.sol";
import {MarketSession} from "../../src/libraries/MarketSession.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {MockLegacyStockToken, MockRebasingToken, MockStockToken} from "../mocks/MockStockToken.sol";
import {Test} from "forge-std/Test.sol";

contract SlateFeedTest is Test {
    uint256 internal constant WED_1500 = 1_790_780_400; // Wed 30 Sep 2026 15:00 UTC
    uint256 internal constant FRI_2359 = 1_790_985_540; // Fri 2 Oct 2026 23:59 UTC
    uint256 internal constant SAT_1200 = 1_791_028_800; // Sat 3 Oct 2026 12:00 UTC

    uint32 internal constant MAX_AGE = 15 minutes;
    uint32 internal constant GRACE = 30 minutes;
    uint16 internal constant LARGE_BPS = 500;

    MockStockToken internal crwd;
    MockPriceSource internal raw;
    MockPriceSource internal tr;
    SlateFeed internal feed;

    function setUp() public {
        vm.warp(WED_1500);
        crwd = new MockStockToken("CrowdStrike", "CRWD");
        raw = new MockPriceSource(PriceKind.RAW_UNDERLYING);
        tr = new MockPriceSource(PriceKind.TOTAL_RETURN);
        feed = _feed(address(crwd), MultiplierModel.ERC8056, raw, false);
    }

    function _feed(address token, MultiplierModel model, MockPriceSource src, bool allowClosed)
        internal
        returns (SlateFeed)
    {
        return new SlateFeed(
            SlateFeed.Config({
                token: token,
                model: model,
                source: src,
                feedId: bytes32("CRWD/USD"),
                maxAge: MAX_AGE,
                corporateActionGrace: GRACE,
                largeChangeBps: LARGE_BPS,
                allowMarketClosed: allowClosed,
                description: "CRWD / USD"
            })
        );
    }

    function _quote(SlateFeed f) internal view returns (Quote memory) {
        return f.latestQuote();
    }

    // ---------------------------------------------------------------- configuration

    function test_constructor_rejectsZeroAddresses() public {
        vm.expectRevert(SlateFeed.ZeroAddress.selector);
        _feed(address(0), MultiplierModel.ERC8056, raw, false);
    }

    function test_constructor_rejectsTotalReturnOnRebasingToken() public {
        MockRebasingToken reb = new MockRebasingToken();
        vm.expectRevert(SlateFeed.UnsupportedCombination.selector);
        _feed(address(reb), MultiplierModel.REBASING, tr, false);
    }

    function test_multiplierApplied_onlyForRawErc8056() public {
        assertTrue(feed.multiplierApplied());
        assertFalse(_feed(address(crwd), MultiplierModel.ERC8056, tr, false).multiplierApplied());
        assertFalse(_feed(address(crwd), MultiplierModel.NONE, raw, false).multiplierApplied());
        assertFalse(_feed(address(new MockRebasingToken()), MultiplierModel.REBASING, raw, false).multiplierApplied());
    }

    function test_aggregatorMetadata() public {
        assertEq(feed.decimals(), 8);
        assertEq(feed.version(), 1);
        assertEq(feed.description(), "CRWD / USD");
        vm.expectRevert(ISlateFeed.NoHistory.selector);
        feed.getRoundData(1);
    }

    // ---------------------------------------------------------------- pricing

    /// The headline case: CRWD has no Chainlink feed and sits at a 4x multiplier after its 4:1 split.
    function test_raw_appliesMultiplier_crwdAt4x() public {
        crwd.updateMultiplier(4e18);
        vm.warp(block.timestamp + GRACE + 1);
        raw.set(26_498_000_000, 8, block.timestamp);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();
        assertEq(answer, 105_992_000_000);
        assertEq(roundId, block.timestamp);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, roundId);
        (, int256 sharePrice, uint256 multiplier) = feed.latestDetail();
        assertEq(sharePrice, 26_498_000_000);
        assertEq(multiplier, 4e18);
    }

    /// Robinhood's Chainlink feeds already include the multiplier; applying it again is the double-count bug.
    function testFuzz_totalReturn_neverAppliesMultiplier(uint64 multiplier, uint64 price) public {
        multiplier = uint64(bound(multiplier, 1e15, 1e19));
        price = uint64(bound(price, 1, type(uint64).max));
        SlateFeed f = _feed(address(crwd), MultiplierModel.ERC8056, tr, false);
        crwd.updateMultiplier(multiplier);
        vm.warp(block.timestamp + 1);
        tr.set(int256(uint256(price)), 8, block.timestamp);
        (Quote memory q, int256 sharePrice,) = f.latestDetail();
        assertEq(q.answer, int256(uint256(price)));
        assertEq(sharePrice, int256(uint256(price) * 1e18 / multiplier));
    }

    function testFuzz_rebasing_neverAppliesMultiplier(uint64 multiplier) public {
        MockRebasingToken reb = new MockRebasingToken();
        reb.setMultiplier(bound(multiplier, 1, 1e20));
        SlateFeed f = _feed(address(reb), MultiplierModel.REBASING, raw, false);
        raw.set(100e8, 8, block.timestamp);
        assertEq(_quote(f).answer, 100e8);
    }

    function test_normalizesSourceDecimals() public {
        raw.set(264.98e18, 18, block.timestamp);
        assertEq(_quote(feed).answer, 26_498_000_000);
        raw.set(264_980_000, 6, block.timestamp);
        assertEq(_quote(feed).answer, 26_498_000_000);
    }

    function test_noData_whenEmptyNonPositiveOrAbsurdDecimals() public {
        assertEq(uint8(feed.status()), uint8(FeedStatus.NO_DATA));
        raw.set(0, 8, block.timestamp);
        assertEq(uint8(feed.status()), uint8(FeedStatus.NO_DATA));
        raw.set(-1, 8, block.timestamp);
        assertEq(uint8(feed.status()), uint8(FeedStatus.NO_DATA));
        raw.set(1, 37, block.timestamp);
        assertEq(uint8(feed.status()), uint8(FeedStatus.NO_DATA));
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.NO_DATA));
        feed.latestRoundData();
    }

    function test_futureObservationIsClampedToNow() public {
        raw.set(100e8, 8, block.timestamp + 30);
        assertEq(_quote(feed).observedAt, block.timestamp);
    }

    // ---------------------------------------------------------------- oracle pause

    function test_oraclePaused_failsClosed() public {
        raw.set(100e8, 8, block.timestamp);
        crwd.setOraclePaused(true);
        assertEq(uint8(feed.status()), uint8(FeedStatus.ORACLE_PAUSED));
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.ORACLE_PAUSED));
        feed.latestRoundData();
    }

    function test_oraclePaused_appliesToTotalReturnSourcesToo() public {
        SlateFeed f = _feed(address(crwd), MultiplierModel.ERC8056, tr, false);
        tr.set(100e8, 8, block.timestamp);
        crwd.setOraclePaused(true);
        assertEq(uint8(f.status()), uint8(FeedStatus.ORACLE_PAUSED));
    }

    /// Robinhood's testnet tokens have no `oraclePaused()` at all.
    function test_tokenWithoutPauseFlag_isSupported() public {
        MockLegacyStockToken tsla = new MockLegacyStockToken("Tesla", "TSLA");
        SlateFeed f = _feed(address(tsla), MultiplierModel.ERC8056, raw, false);
        raw.set(35_411_000_000, 8, block.timestamp);
        assertEq(uint8(f.status()), uint8(FeedStatus.OK));
        assertEq(_quote(f).answer, 35_411_000_000);
    }

    // ---------------------------------------------------------------- multiplier timing

    function test_pendingChange_usesCurrentMultiplierUntilItSwitches() public {
        uint256 e = block.timestamp + 1 hours;
        crwd.updateMultiplier(4e18, e);
        raw.set(1000e8, 8, block.timestamp);
        assertEq(_quote(feed).answer, 1000e8);
        assertEq(uint8(feed.status()), uint8(FeedStatus.OK));
    }

    function test_dividend_poked_isExactAcrossTheSwitch() public {
        uint256 e = block.timestamp + 10 minutes;
        crwd.updateMultiplier(1.002211e18, e); // ORCL's 2026-07-27 dividend
        assertTrue(feed.poke());
        raw.set(120e8, 8, e - 1);
        vm.warp(e + 1);
        Quote memory q = _quote(feed);
        assertEq(uint8(q.status), uint8(FeedStatus.OK));
        assertEq(q.answer, 120e8); // priced with the multiplier in force when observed: 1.0
    }

    function test_dividend_unpoked_straddleThenCorporateActionThenOk() public {
        uint256 e = block.timestamp + 10 minutes;
        crwd.updateMultiplier(1.002211e18, e);
        raw.set(120e8, 8, e - 1);
        vm.warp(e + 1);
        assertEq(uint8(feed.status()), uint8(FeedStatus.STRADDLE));

        raw.set(120e8, 8, block.timestamp);
        assertEq(uint8(feed.status()), uint8(FeedStatus.CORPORATE_ACTION)); // unmeasured: treated as large

        vm.warp(e + GRACE);
        raw.set(120e8, 8, block.timestamp);
        assertEq(uint8(feed.status()), uint8(FeedStatus.OK));
        assertEq(_quote(feed).answer, 120.26532e8);
    }

    function test_split_poked_holdsThroughGraceAndStaysContinuous() public {
        uint256 e = block.timestamp + 12 hours;
        crwd.updateMultiplier(4e18, e);
        assertTrue(feed.poke());
        raw.set(1000e8, 8, e - 1);
        vm.warp(e - 1);
        assertEq(_quote(feed).answer, 1000e8);

        vm.warp(e + 5 minutes);
        assertEq(uint8(feed.status()), uint8(FeedStatus.CORPORATE_ACTION));
        raw.set(250e8, 8, block.timestamp); // the market has split, but we are inside the grace window
        assertEq(uint8(feed.status()), uint8(FeedStatus.CORPORATE_ACTION));
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.CORPORATE_ACTION));
        feed.latestRoundData();

        vm.warp(e + GRACE);
        raw.set(250e8, 8, block.timestamp);
        assertEq(uint8(feed.status()), uint8(FeedStatus.OK));
        assertEq(_quote(feed).answer, 1000e8); // continuous: 250 * 4 == 1000 * 1
    }

    /// `updateMultiplier(uint256)` switches in the same block it is staged, so it can never be poked.
    function test_immediateSwitch_cannotBeSnapshotted_failsClosed() public {
        raw.set(1000e8, 8, block.timestamp);
        vm.warp(block.timestamp + 1);
        crwd.updateMultiplier(4e18);
        assertFalse(feed.poke());
        assertEq(uint8(feed.status()), uint8(FeedStatus.STRADDLE));
    }

    function test_restagedAfterPoke_oldSnapshotIsIgnored() public {
        uint256 e1 = block.timestamp + 1 hours;
        crwd.updateMultiplier(1.001e18, e1);
        feed.poke();
        uint256 e2 = block.timestamp + 2 hours;
        crwd.updateMultiplier(1.001e18, e2);
        raw.set(100e8, 8, e2 - 1);
        vm.warp(e2 + 1);
        assertEq(uint8(feed.status()), uint8(FeedStatus.STRADDLE));
    }

    function test_poke_onlyRecordsAPendingSwitch() public {
        assertFalse(feed.poke());
        crwd.updateMultiplier(2e18, block.timestamp + 1 hours);
        vm.expectEmit(address(feed));
        emit SlateFeed.MultiplierSnapshot(1e18, 2e18, uint64(block.timestamp + 1 hours));
        assertTrue(feed.poke());
        (uint96 oldM, uint96 newM, uint64 e) = feed.snapshot();
        assertEq(oldM, 1e18);
        assertEq(newM, 2e18);
        assertEq(e, block.timestamp + 1 hours);
        vm.warp(block.timestamp + 1 hours);
        assertFalse(feed.poke());
        assertFalse(_feed(address(crwd), MultiplierModel.NONE, raw, false).poke());
    }

    /// Whatever the split ratio, a poked feed is continuous across it once the grace window has passed.
    function testFuzz_split_isContinuous(uint32 ratioBps, uint64 prePrice) public {
        ratioBps = uint32(bound(ratioBps, 1000, 1_000_000)); // 1:10 reverse split .. 100:1 split
        prePrice = uint64(bound(prePrice, 1e8, 1e14));
        uint256 newM = uint256(ratioBps) * 1e14;
        uint256 e = block.timestamp + 1 hours;
        crwd.updateMultiplier(newM, e);
        feed.poke();
        raw.set(int256(uint256(prePrice)), 8, e - 1);
        int256 before = _quote(feed).answer;

        vm.warp(e + GRACE);
        raw.set(int256(uint256(prePrice) * 1e18 / newM), 8, block.timestamp);
        Quote memory q = _quote(feed);
        assertEq(uint8(q.status), uint8(FeedStatus.OK));
        assertApproxEqRel(q.answer, before, 1e14); // within 0.01%: rounding of the post-split share price
    }

    // ---------------------------------------------------------------- staleness and sessions

    function test_staleOnAWeekday() public {
        raw.set(100e8, 8, block.timestamp);
        vm.warp(block.timestamp + MAX_AGE + 1);
        assertEq(uint8(feed.status()), uint8(FeedStatus.STALE));
    }

    function test_marketClosed_servedOnlyWhenAllowed() public {
        SlateFeed lenient = _feed(address(crwd), MultiplierModel.ERC8056, raw, true);
        vm.warp(FRI_2359);
        raw.set(100e8, 8, block.timestamp);
        vm.warp(SAT_1200);
        assertEq(uint8(feed.status()), uint8(FeedStatus.MARKET_CLOSED));
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.MARKET_CLOSED));
        feed.latestRoundData();
        (, int256 answer,,,) = lenient.latestRoundData();
        assertEq(answer, 100e8);
    }

    function test_marketClosed_requiresAPriceFromBeforeTheClose() public {
        vm.warp(FRI_2359 - 2 hours);
        raw.set(100e8, 8, block.timestamp);
        vm.warp(SAT_1200);
        assertEq(uint8(feed.status()), uint8(FeedStatus.STALE));
    }
}

contract MarketSessionTest is Test {
    function test_knownTimestamps() public pure {
        assertEq(MarketSession.closedSince(1_790_985_540), 0); // Fri 23:59 UTC
        assertEq(MarketSession.closedSince(1_790_985_600), 1_790_985_600); // Sat 00:00 UTC
        assertEq(MarketSession.closedSince(1_791_158_340), 1_790_985_600); // Sun 23:59 UTC
        assertEq(MarketSession.closedSince(1_791_158_400), 0); // Mon 00:00 UTC
        assertEq(MarketSession.closedSince(1_790_780_400), 0); // Wed 15:00 UTC
    }

    function testFuzz_closedSinceIsASaturdayMidnightWithinTwoDays(uint64 ts) public pure {
        uint256 since = MarketSession.closedSince(ts);
        if (since == 0) return;
        assertLe(since, ts);
        assertLt(ts - since, 2 days);
        assertEq((since / 1 days + 4) % 7, 6); // day-of-week with Sunday = 0 is Saturday
        assertEq(since % 1 days, 0);
    }
}
