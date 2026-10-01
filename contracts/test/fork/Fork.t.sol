// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {SlateQuotedFeed} from "../../src/feeds/SlateQuotedFeed.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {IERC8056} from "../../src/interfaces/IERC8056.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus, Quote} from "../../src/interfaces/ISlateFeed.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {ChainlinkSource} from "../../src/sources/ChainlinkSource.sol";
import {SignedSource} from "../../src/sources/SignedSource.sol";
import {SolidityReportVerifier} from "../../src/sources/SolidityReportVerifier.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {ReportBuilder} from "../unit/SignedSource.t.sol";

/// @dev Runs against live public RPCs. Enable with SLATE_FORK=1.
abstract contract ForkTest is ReportBuilder {
    /// @dev `chain` names an rpc_endpoints entry; SLATE_FORK_URL_<chain> overrides it (for example with a
    ///      local anvil fork when a public endpoint rejects Foundry's client).
    function _fork(string memory chain) internal {
        if (!vm.envOr("SLATE_FORK", false)) vm.skip(true);
        vm.createSelectFork(vm.envOr(string.concat("SLATE_FORK_URL_", chain), chain));
        // Robinhood's public endpoints are load-balanced and a lagging node may not have `latest` yet, so stay a
        // few blocks back. Arbitrum's public endpoint prunes state that quickly, so it stays at `latest`.
        if (keccak256(bytes(chain)) != keccak256("arbitrum")) vm.rollFork(block.number - 20);
        calendar = new USMarketCalendar(address(this));
    }

    USMarketCalendar internal calendar;

    function _feed(address token, MultiplierModel model, ChainlinkSource src, uint32 maxAge, Session session)
        internal
        returns (SlateFeed)
    {
        return new SlateFeed(
            SlateFeed.Config({
                token: token,
                model: model,
                source: src,
                feedId: bytes32(0),
                maxAge: maxAge,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: true,
                calendar: calendar,
                session: session,
                description: "fork"
            })
        );
    }
}

contract RobinhoodMainnetForkTest is ForkTest {
    address internal constant CRWD = 0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931;
    address internal constant AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    AggregatorV3Interface internal constant AAPL_USD =
        AggregatorV3Interface(0x6B22A786bAa607d76728168703a39Ea9C99f2cD0);
    AggregatorV3Interface internal constant USDG_USD =
        AggregatorV3Interface(0x61B7e5650328764B076A108EFF5fa7282a1B9aD2);

    function setUp() public {
        _fork("rh_mainnet");
    }

    /// CRWD: no Chainlink feed, multiplier 4e18 after the 2026-07-02 split. A signed $264.98 share price
    /// prices one token at $1,059.92, as Robinhood's own API does (`tokenBid`).
    function test_crwd_signedPriceTimesRealMultiplier() public {
        assertEq(IERC8056(CRWD).uiMultiplier(), 4e18);
        Signer[] memory s = _signers(3);
        address[] memory addrs = new address[](3);
        for (uint256 i; i < 3; ++i) {
            addrs[i] = s[i].addr;
        }
        SignedSource src = new SignedSource(new SolidityReportVerifier(), address(this), addrs, 2, 50, 1000, 60);
        SlateFeed feed = new SlateFeed(
            SlateFeed.Config({
                token: CRWD,
                model: MultiplierModel.ERC8056,
                source: src,
                feedId: bytes32("CRWD/USD"),
                maxAge: 15 minutes,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: true,
                calendar: calendar,
                session: Session.EXTENDED,
                description: "CRWD / USD"
            })
        );
        src.submit(
            bytes32("CRWD/USD"),
            _report(src.domainSeparator(), bytes32("CRWD/USD"), s, _same(3, 26_498_000_000), uint64(block.timestamp))
        );
        Quote memory q = feed.latestQuote();
        assertEq(uint8(q.status), uint8(FeedStatus.OK));
        assertEq(q.answer, 105_992_000_000);
    }

    /// Robinhood's Chainlink feed already includes AAPL's multiplier; Slate must pass it through unchanged.
    function test_aapl_totalReturnFeedPassesThroughExactly() public {
        SlateFeed feed = _feed(
            AAPL,
            MultiplierModel.ERC8056,
            new ChainlinkSource(AAPL_USD, PriceKind.TOTAL_RETURN),
            4 days,
            Session.EXTENDED
        );
        (, int256 chainlink,,,) = AAPL_USD.latestRoundData();
        (Quote memory q, int256 sharePrice, uint256 multiplier) = feed.latestDetail();
        assertEq(q.answer, chainlink);
        assertEq(multiplier, IERC8056(AAPL).uiMultiplier());
        assertLt(sharePrice, chainlink); // multiplier > 1 after reinvested dividends
    }

    function test_aapl_inUsdg() public {
        SlateFeed usd = _feed(
            AAPL,
            MultiplierModel.ERC8056,
            new ChainlinkSource(AAPL_USD, PriceKind.TOTAL_RETURN),
            4 days,
            Session.EXTENDED
        );
        SlateQuotedFeed usdg = new SlateQuotedFeed(usd, USDG_USD, 25 hours, "AAPL / USDG");
        (, int256 usdgPrice,,,) = USDG_USD.latestRoundData();
        Quote memory q = usdg.latestQuote();
        assertEq(q.answer, usd.latestQuote().answer * 1e8 / usdgPrice);
        assertApproxEqRel(q.answer, usd.latestQuote().answer, 0.01e18); // a dollar stablecoin
    }

    function test_poke_onRealTokenWithNothingPending() public {
        SlateFeed feed = _feed(
            AAPL,
            MultiplierModel.ERC8056,
            new ChainlinkSource(AAPL_USD, PriceKind.TOTAL_RETURN),
            4 days,
            Session.EXTENDED
        );
        assertFalse(feed.poke());
    }
}

contract RobinhoodTestnetForkTest is ForkTest {
    address internal constant TSLA = 0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E;

    function setUp() public {
        _fork("rh_testnet");
    }

    /// Robinhood's testnet tokens are an older implementation with no `oraclePaused()`.
    function test_testnetTokenWithoutPauseFlag() public {
        (bool ok,) = TSLA.staticcall(abi.encodeWithSignature("oraclePaused()"));
        assertFalse(ok);
        SignedSource src = new SignedSource(new SolidityReportVerifier(), address(this), _addrs(), 1, 50, 1000, 60);
        SlateFeed feed = new SlateFeed(
            SlateFeed.Config({
                token: TSLA,
                model: MultiplierModel.ERC8056,
                source: src,
                feedId: bytes32("TSLA/USD"),
                maxAge: 15 minutes,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: true,
                calendar: calendar,
                session: Session.EXTENDED,
                description: "TSLA / USD"
            })
        );
        Signer[] memory s = _signers(1);
        src.submit(
            bytes32("TSLA/USD"),
            _report(src.domainSeparator(), bytes32("TSLA/USD"), s, _same(1, 35_411_000_000), uint64(block.timestamp))
        );
        assertEq(uint8(feed.status()), uint8(FeedStatus.OK));
        assertEq(feed.latestQuote().answer, 35_411_000_000);
    }

    function _addrs() private returns (address[] memory a) {
        Signer[] memory s = _signers(1);
        a = new address[](1);
        a[0] = s[0].addr;
    }
}

contract ArbitrumOneForkTest is ForkTest {
    AggregatorV3Interface internal constant TSLA_USD =
        AggregatorV3Interface(0x3609baAa0a9b1f0FE4d6CC01884585d0e191C3E3);

    function setUp() public {
        _fork("arbitrum");
    }

    /// Chainlink's raw TSLA feed on Arbitrum One, applied to an ERC-8056 token after a 4:1 split.
    function test_rawChainlinkFeedTimesMultiplier() public {
        MockStockToken lab = new MockStockToken("Slate Lab TSLA", "labTSLA");
        lab.updateMultiplier(4e18);
        vm.warp(block.timestamp + 31 minutes);
        SlateFeed feed = _feed(
            address(lab),
            MultiplierModel.ERC8056,
            new ChainlinkSource(TSLA_USD, PriceKind.RAW_UNDERLYING),
            4 days,
            Session.REGULAR
        );
        (, int256 raw,,,) = TSLA_USD.latestRoundData();
        assertEq(feed.latestQuote().answer, raw * 4);
    }
}
