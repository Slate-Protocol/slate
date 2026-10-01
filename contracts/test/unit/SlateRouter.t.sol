// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateBasket} from "../../src/basket/SlateBasket.sol";
import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {SlateNavFeed} from "../../src/feeds/SlateNavFeed.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus, ISlateFeed} from "../../src/interfaces/ISlateFeed.sol";
import {ISwapVenue} from "../../src/interfaces/ISwapVenue.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {SlateRouter} from "../../src/router/SlateRouter.sol";
import {SlateTestDollar} from "../../src/testnet/SlateTestDollar.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockVenue} from "../mocks/MockVenue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

contract SlateRouterTest is Test {
    uint256 internal constant N = 3;
    uint256 internal constant BAND = 300; // 3%
    uint256 internal constant BIG = 5_000_000e6; // a generous maxCashIn; the router pulls it and refunds the rest

    USMarketCalendar internal calendar;
    SlateBasket internal basket;
    SlateNavFeed internal nav;
    SlateTestDollar internal cash;
    MockVenue internal venue;
    SlateRouter internal router;
    MockStockToken[] internal tokens;
    MockPriceSource[] internal sources;
    address internal alice = makeAddr("alice");

    // Token prices in USD (8 dp). Token 0 is CRWD-like: $264.98 a share, 4 shares a token.
    int256[N] internal sharePrices = [int256(26_498_000_000), 100e8, 50e8];
    uint256[N] internal tokenPrices = [uint256(105_992_000_000), 100e8, 50e8];

    function setUp() public {
        vm.warp(1_790_780_400);
        calendar = new USMarketCalendar(address(this));
        cash = new SlateTestDollar(address(this));
        venue = new MockVenue();

        IERC20[] memory c = new IERC20[](N);
        uint256[] memory units = new uint256[](N);
        ISlateFeed[] memory f = new ISlateFeed[](N);
        for (uint256 i; i < N; ++i) {
            MockStockToken t = new MockStockToken("T", "T");
            MockPriceSource s = new MockPriceSource(PriceKind.RAW_UNDERLYING);
            tokens.push(t);
            sources.push(s);
            c[i] = t;
            units[i] = 0.5e18 * (i + 1);
            f[i] = _feed(address(t), s);
        }
        tokens[0].updateMultiplier(4e18);
        vm.warp(block.timestamp + 31 minutes);
        for (uint256 i; i < N; ++i) {
            sources[i].set(sharePrices[i], 8, block.timestamp);
            venue.setRate(address(tokens[i]), tokenPrices[i] / 100); // 8 dp USD → 6 dp TESTUSD, at the feed price
        }

        basket = new SlateBasket("Slate Basket", "SLATE-3", c, units);
        nav = new SlateNavFeed(basket, f, true, "SLATE-3 NAV / USD");
        router = new SlateRouter(nav, cash, AggregatorV3Interface(address(0)), 0, BAND);

        cash.mint(alice, 10_000_000e6);
        vm.prank(alice);
        cash.approve(address(router), type(uint256).max);
    }

    function _feed(address token, MockPriceSource src) internal returns (ISlateFeed) {
        return new SlateFeed(
            SlateFeed.Config({
                token: token,
                model: MultiplierModel.ERC8056,
                source: src,
                feedId: bytes32("X"),
                maxAge: 15 minutes,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: true,
                calendar: calendar,
                session: Session.EXTENDED,
                description: "x"
            })
        );
    }

    function _legs() internal view returns (SlateRouter.Leg[] memory legs) {
        legs = new SlateRouter.Leg[](N);
        for (uint256 i; i < N; ++i) {
            legs[i] = SlateRouter.Leg({venue: ISwapVenue(address(venue)), route: ""});
        }
    }

    function _create(uint256 shares, uint256 maxCash) internal returns (uint256) {
        vm.prank(alice);
        return router.createWithCash(shares, alice, _legs(), maxCash, block.timestamp);
    }

    // --------------------------------------------------------------------------------------------

    function test_fairCash_isTheNavInCash() public view {
        (uint256 total, uint256[] memory amounts) = router.fairCash(2e18);
        assertEq(amounts[0], 1e18);
        // 1 × $1,059.92 + 2 × $100 + 3 × $50
        assertEq(total, 1059.92e6 + 200e6 + 150e6);
    }

    function test_createWithCash_atTheFeedPrice_spendsFairCashAndRefundsTheRest() public {
        (uint256 fair,) = router.fairCash(2e18);
        uint256 before = cash.balanceOf(alice);
        uint256 spent = _create(2e18, fair + 100e6);
        assertEq(spent, fair);
        assertEq(cash.balanceOf(alice), before - fair);
        assertEq(basket.balanceOf(alice), 2e18 - basket.MINIMUM_SHARES());
        assertEq(cash.balanceOf(address(router)), 0);
        for (uint256 i; i < N; ++i) {
            assertEq(tokens[i].balanceOf(address(router)), 0);
        }
        (, int256 navAnswer,,,) = nav.latestRoundData();
        assertEq(navAnswer, 52_996_000_000 + 100e8 + 75e8); // per share: 0.5 × 1,059.92 + 1 × 100 + 1.5 × 50
    }

    function test_createWithCash_secondCreationIsProRata() public {
        _create(2e18, BIG);
        (uint256 fair,) = router.fairCash(1e18);
        assertEq(_create(1e18, fair), fair);
        assertEq(basket.balanceOf(alice), 3e18 - basket.MINIMUM_SHARES());
    }

    function test_band_acceptsAFillAtTheEdge() public {
        venue.setRate(address(tokens[1]), 103e6); // +3.00%
        _create(2e18, BIG);
    }

    function test_band_refusesAnExpensiveFill() public {
        venue.setRate(address(tokens[1]), 103.01e6); // +3.01%
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.RouteRefused.selector, 1, 103.01e8, 100e8));
        _create(2e18, BIG);
    }

    /// The Robinhood Chain testnet case: a third-party pool sells TSLA 99.98% below the market. Cheap is not
    /// fair: a pool that far off is not the stock's market, and the router will not treat it as one.
    function test_band_refusesTheNinetyNinePointNineEightPercentPool() public {
        venue.setRate(address(tokens[1]), 0.02e6); // $0.02 against $100
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.RouteRefused.selector, 1, 0.02e8, 100e8));
        _create(2e18, BIG);
    }

    function test_band_usesTheMultiplier() public {
        // Priced as one share instead of four: the naive mistake, 75% under. Refused.
        venue.setRate(address(tokens[0]), 264.98e6);
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.RouteRefused.selector, 0, 264.98e8, 1059.92e8));
        _create(2e18, BIG);
    }

    function test_unusableFeed_stopsTheCreation() public {
        vm.warp(block.timestamp + 16 minutes); // stale (market open)
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.STALE));
        _create(2e18, BIG);
    }

    function test_corporateAction_stopsTheCreation() public {
        tokens[2].updateMultiplier(2e18); // a 2:1 split, effective now
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.CORPORATE_ACTION));
        _create(2e18, BIG);
    }

    function test_dust_isRefusedNotMispriced() public {
        // 1e9 share-wei: leg 0 is 5e8 token-wei, worth $0.00000053, and the venue rounds its charge up to $0.000001.
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.RouteRefused.selector, 0, 2000e8, 1059.92e8));
        _create(1e9, BIG);
    }

    function test_maxCashIn_isEnforced() public {
        (uint256 fair,) = router.fairCash(2e18);
        vm.expectRevert("venue: maxIn");
        _create(2e18, fair - 1);
    }

    function test_venueThatOverchargesIsMeasuredByBalance() public {
        venue.setOvercharge(50e6); // takes $50 more than its own quote on every leg
        // The router measures what left its balance, not what the venue reports: 4.7% over on leg 0.
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.RouteRefused.selector, 0, 1109.92e8, 1059.92e8));
        _create(2e18, BIG);
    }

    function test_venueThatOverchargesSlightly_isChargedForWhatItTook() public {
        venue.setOvercharge(1e6); // $1 per leg, within the band for every leg
        (uint256 fair,) = router.fairCash(2e18);
        uint256 before = cash.balanceOf(alice);
        uint256 spent = _create(2e18, BIG);
        assertEq(spent, fair + 3e6);
        assertEq(cash.balanceOf(alice), before - spent);
    }

    function test_shortFill_reverts() public {
        venue.setShortBy(1);
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.ShortFill.selector, 0, 1e18 - 1, 1e18));
        _create(2e18, BIG);
    }

    function test_deadline() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.Expired.selector, block.timestamp - 1));
        router.createWithCash(2e18, alice, _legs(), 1e12, block.timestamp - 1);
    }

    function test_legsMustMatchTheBasket() public {
        SlateRouter.Leg[] memory legs = new SlateRouter.Leg[](N - 1);
        vm.prank(alice);
        vm.expectRevert(SlateRouter.LengthMismatch.selector);
        router.createWithCash(2e18, alice, legs, 1e12, block.timestamp);
    }

    function test_constructor_bandLimits() public {
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.DeviationTooWide.selector, 0));
        new SlateRouter(nav, cash, AggregatorV3Interface(address(0)), 0, 0);
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.DeviationTooWide.selector, 2001));
        new SlateRouter(nav, cash, AggregatorV3Interface(address(0)), 0, 2001);
    }

    // ---- USDG: cash priced by a USDG/USD feed --------------------------------------------------

    function test_usdg_cashPriceScalesTheEffectivePrice() public {
        MockAggregator usdgUsd = new MockAggregator(8);
        usdgUsd.set(0.98e8, block.timestamp); // a depeg to $0.98
        SlateRouter r = new SlateRouter(nav, cash, usdgUsd, 1 days, BAND);
        vm.prank(alice);
        cash.approve(address(r), type(uint256).max);

        // Venue still charges $-denominated rates in cash units: 1 cash = $0.98 so every leg is 2% cheap. Fine.
        (uint256 fair,) = r.fairCash(2e18);
        assertEq(fair, 1_081_551_021 + 204_081_633 + 153_061_225); // each leg / 0.98, rounded up
        vm.prank(alice);
        r.createWithCash(2e18, alice, _legs(), BIG, block.timestamp);
    }

    function test_usdg_deeperDepegIsRefused() public {
        MockAggregator usdgUsd = new MockAggregator(8);
        usdgUsd.set(0.96e8, block.timestamp);
        SlateRouter r = new SlateRouter(nav, cash, usdgUsd, 1 days, BAND);
        vm.prank(alice);
        cash.approve(address(r), type(uint256).max);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SlateRouter.RouteRefused.selector, 0, 1017.5232e8, 1059.92e8));
        r.createWithCash(2e18, alice, _legs(), BIG, block.timestamp);
    }

    function test_usdg_staleCashPriceFailsClosed() public {
        MockAggregator usdgUsd = new MockAggregator(8);
        usdgUsd.set(1e8, block.timestamp - 1 days - 1);
        SlateRouter r = new SlateRouter(nav, cash, usdgUsd, 1 days, BAND);
        vm.expectRevert(SlateRouter.CashPriceUnavailable.selector);
        r.cashPrice();
    }

    // ---- invariant-style fuzz ------------------------------------------------------------------

    function testFuzz_routerNeverKeepsAnything(uint256 shares, uint256 bump) public {
        // From 0.01 shares up. Below that, one micro-dollar of rounding is a visible share of a leg's price and the
        // band refuses the dust, which is the right answer.
        shares = bound(shares, 0.01e18, 1000e18);
        bump = bound(bump, 0, 299); // within the band
        for (uint256 i; i < N; ++i) {
            venue.setRate(address(tokens[i]), tokenPrices[i] / 100 * (10_000 + bump) / 10_000);
        }
        uint256 before = cash.balanceOf(alice);
        uint256 spent = _create(shares, BIG);
        assertEq(cash.balanceOf(alice), before - spent);
        assertEq(cash.balanceOf(address(router)), 0);
        for (uint256 i; i < N; ++i) {
            assertEq(tokens[i].balanceOf(address(router)), 0);
            assertEq(tokens[i].allowance(address(router), address(basket)), 0);
        }
        assertEq(cash.allowance(address(router), address(venue)), 0);
    }
}
