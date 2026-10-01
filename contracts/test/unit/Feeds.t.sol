// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {SlateFeedFactory} from "../../src/feeds/SlateFeedFactory.sol";
import {SlateQuotedFeed} from "../../src/feeds/SlateQuotedFeed.sol";
import {Observation, PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus, ISlateFeed, Quote} from "../../src/interfaces/ISlateFeed.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {ChainlinkSource} from "../../src/sources/ChainlinkSource.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {Test} from "forge-std/Test.sol";

contract ChainlinkSourceTest is Test {
    function test_observe_mapsLatestRound() public {
        MockAggregator agg = new MockAggregator(8);
        agg.set(33_412_768_601, 1_790_810_800);
        ChainlinkSource src = new ChainlinkSource(agg, PriceKind.TOTAL_RETURN);
        Observation memory o = src.observe(bytes32(0));
        assertEq(o.price, 33_412_768_601);
        assertEq(o.decimals, 8);
        assertEq(o.observedAt, 1_790_810_800);
        assertEq(uint8(src.kind(bytes32("anything"))), uint8(PriceKind.TOTAL_RETURN));
    }

    function test_observe_revertingAggregatorReadsAsNoData() public {
        MockAggregator agg = new MockAggregator(8);
        ChainlinkSource src = new ChainlinkSource(agg, PriceKind.RAW_UNDERLYING);
        agg.setReverts(true);
        assertEq(src.observe(bytes32(0)).observedAt, 0);
    }
}

contract SlateQuotedFeedTest is Test {
    MockPriceSource internal src;
    MockStockToken internal token;
    SlateFeed internal base;
    MockAggregator internal usdg;
    SlateQuotedFeed internal inUsdg;

    function setUp() public {
        vm.warp(1_790_780_400);
        src = new MockPriceSource(PriceKind.RAW_UNDERLYING);
        token = new MockStockToken("CrowdStrike", "CRWD");
        base = new SlateFeed(
            SlateFeed.Config({
                token: address(token),
                model: MultiplierModel.ERC8056,
                source: src,
                feedId: bytes32("CRWD/USD"),
                maxAge: 15 minutes,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: false,
                description: "CRWD / USD"
            })
        );
        usdg = new MockAggregator(8); // USDG / USD on Robinhood Chain uses 8 decimals
        inUsdg = new SlateQuotedFeed(base, usdg, 25 hours, "CRWD / USDG");
    }

    function test_requotesInUsdg() public {
        src.set(1000e8, 8, block.timestamp);
        usdg.set(0.9998e8, block.timestamp - 1 hours);
        Quote memory q = inUsdg.latestQuote();
        assertEq(uint8(q.status), uint8(FeedStatus.OK));
        assertEq(q.answer, 100_020_004_000); // 1000 / 0.9998, 8 decimals, rounded down
        assertEq(q.observedAt, block.timestamp - 1 hours); // the older of the two
        (, int256 answer,,,) = inUsdg.latestRoundData();
        assertEq(answer, q.answer);
    }

    function test_staleUsdgPrice_failsClosed() public {
        src.set(1000e8, 8, block.timestamp);
        usdg.set(1e8, block.timestamp - 25 hours - 1);
        assertEq(uint8(inUsdg.status()), uint8(FeedStatus.STALE));
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.STALE));
        inUsdg.latestRoundData();
    }

    function test_missingUsdgPrice_isNoData() public {
        src.set(1000e8, 8, block.timestamp);
        usdg.setReverts(true);
        assertEq(uint8(inUsdg.status()), uint8(FeedStatus.NO_DATA));
    }

    function test_baseStatusPassesThrough() public {
        src.set(1000e8, 8, block.timestamp);
        usdg.set(1e8, block.timestamp);
        token.setOraclePaused(true);
        assertEq(uint8(inUsdg.status()), uint8(FeedStatus.ORACLE_PAUSED));
    }
}

contract SlateFeedFactoryTest is Test {
    SlateFeedFactory internal factory;
    MockStockToken internal aapl;
    MockAggregator internal robinhoodFeed;

    function setUp() public {
        vm.warp(1_790_780_400);
        factory = new SlateFeedFactory();
        aapl = new MockStockToken("Apple", "AAPL");
        aapl.updateMultiplier(1.000566080061092436e18);
        vm.warp(block.timestamp + 1 hours);
        robinhoodFeed = new MockAggregator(8);
        robinhoodFeed.set(33_412_768_601, block.timestamp); // total return: multiplier already included
    }

    function _config(ChainlinkSource src) internal view returns (SlateFeed.Config memory) {
        return SlateFeed.Config({
            token: address(aapl),
            model: MultiplierModel.ERC8056,
            source: src,
            feedId: bytes32(0),
            maxAge: 1 days,
            corporateActionGrace: 30 minutes,
            largeChangeBps: 500,
            allowMarketClosed: true,
            description: "AAPL / USD"
        });
    }

    function test_deploy_isDeterministicAndBoundToCaller() public {
        SlateFeed.Config memory c = _config(new ChainlinkSource(robinhoodFeed, PriceKind.TOTAL_RETURN));
        address predicted = factory.predict(c, bytes32("aapl"), address(this));
        assertEq(address(factory.deploy(c, bytes32("aapl"))), predicted);
        assertTrue(factory.predict(c, bytes32("aapl"), makeAddr("someone else")) != predicted);
    }

    function test_calibration_acceptsACorrectlyDeclaredFeed() public {
        SlateFeed.Config memory c = _config(new ChainlinkSource(robinhoodFeed, PriceKind.TOTAL_RETURN));
        SlateFeed feed = factory.deployCalibrated(c, bytes32("aapl"), robinhoodFeed, 10);
        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, 33_412_768_601); // passed through unchanged
    }

    /// Declaring Robinhood's total-return feed as raw would apply the multiplier twice. At AAPL's 1.000566 the
    /// error is 5.7 bps, so a 1 bp calibration bound refuses to deploy it.
    function test_calibration_refusesTheDoubleCount() public {
        SlateFeed.Config memory c = _config(new ChainlinkSource(robinhoodFeed, PriceKind.RAW_UNDERLYING));
        vm.expectPartialRevert(SlateFeedFactory.CalibrationFailed.selector);
        factory.deployCalibrated(c, bytes32("aapl"), robinhoodFeed, 1);
    }
}
