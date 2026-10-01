// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateBasket} from "../../src/basket/SlateBasket.sol";
import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {SlateNavFeed} from "../../src/feeds/SlateNavFeed.sol";
import {SlateQuotedFeed} from "../../src/feeds/SlateQuotedFeed.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus, ISlateFeed, Quote} from "../../src/interfaces/ISlateFeed.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

contract SlateBasketTest is Test {
    uint256 internal constant N = 5;
    SlateBasket internal basket;
    MockStockToken[] internal tokens;
    uint256[] internal units;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.warp(1_790_780_400);
        IERC20[] memory c = new IERC20[](N);
        string[5] memory syms = ["TSLA", "AMZN", "AMD", "PLTR", "NFLX"];
        for (uint256 i; i < N; ++i) {
            MockStockToken t = new MockStockToken(syms[i], syms[i]);
            tokens.push(t);
            c[i] = t;
            units.push((i + 1) * 0.1e18); // arbitrary per-share amounts
        }
        basket = new SlateBasket("Slate Basket 5", "SLATE-5", c, units);
        for (uint256 i; i < N; ++i) {
            tokens[i].mint(alice, 1_000_000e18);
            tokens[i].mint(bob, 1_000_000e18);
            vm.prank(alice);
            tokens[i].approve(address(basket), type(uint256).max);
            vm.prank(bob);
            tokens[i].approve(address(basket), type(uint256).max);
        }
    }

    function _max() internal pure returns (uint256[] memory m) {
        m = new uint256[](N);
        for (uint256 i; i < N; ++i) {
            m[i] = type(uint256).max;
        }
    }

    function _zeros() internal pure returns (uint256[] memory) {
        return new uint256[](N);
    }

    function _create(address who, uint256 shares) internal returns (uint256[] memory amounts) {
        vm.prank(who);
        amounts = basket.create(shares, who, _max());
    }

    function _redeem(address who, uint256 shares) internal returns (uint256[] memory amounts) {
        vm.prank(who);
        amounts = basket.redeem(shares, who, _zeros());
    }

    // ---------------------------------------------------------------- construction

    function test_constructor_validates() public {
        IERC20[] memory c = new IERC20[](2);
        uint256[] memory u = new uint256[](2);
        (c[0], c[1], u[0], u[1]) = (tokens[0], tokens[0], 1, 1);
        vm.expectRevert(abi.encodeWithSelector(SlateBasket.DuplicateConstituent.selector, address(tokens[0])));
        new SlateBasket("x", "x", c, u);
        c[1] = tokens[1];
        u[1] = 0;
        vm.expectRevert(SlateBasket.ZeroAmount.selector);
        new SlateBasket("x", "x", c, u);
        vm.expectRevert(SlateBasket.NoConstituents.selector);
        new SlateBasket("x", "x", new IERC20[](0), new uint256[](0));
        vm.expectRevert(SlateBasket.LengthMismatch.selector);
        new SlateBasket("x", "x", c, new uint256[](1));
    }

    // ---------------------------------------------------------------- create and redeem

    function test_firstCreate_usesUnitAmounts_andLocksMinimum() public {
        uint256[] memory amounts = _create(alice, 10e18);
        for (uint256 i; i < N; ++i) {
            assertEq(amounts[i], units[i] * 10);
            assertEq(tokens[i].balanceOf(address(basket)), units[i] * 10);
        }
        assertEq(basket.totalSupply(), 10e18);
        assertEq(basket.balanceOf(basket.DEAD()), basket.MINIMUM_SHARES());
        assertEq(basket.balanceOf(alice), 10e18 - basket.MINIMUM_SHARES());
    }

    function test_firstCreate_mustExceedMinimum() public {
        uint256 min = basket.MINIMUM_SHARES();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SlateBasket.FirstCreationTooSmall.selector, min + 1));
        basket.create(min, alice, _max());
    }

    function test_laterCreate_isProRataAndRoundsUp() public {
        _create(alice, 10e18);
        tokens[0].mint(address(basket), 1); // a donation makes holdings indivisible
        uint256[] memory q = basket.quoteCreate(3e18);
        uint256[] memory amounts = _create(bob, 3e18);
        for (uint256 i; i < N; ++i) {
            assertEq(amounts[i], q[i]);
        }
        assertEq(amounts[0], (units[0] * 10 + 1) * 3e18 / 10e18 + 1); // rounded up
        assertEq(basket.balanceOf(bob), 3e18);
    }

    function test_redeem_isProRataAndRoundsDown() public {
        _create(alice, 10e18);
        tokens[0].mint(address(basket), 1);
        uint256 before = tokens[0].balanceOf(alice);
        uint256[] memory amounts = _redeem(alice, 3e18);
        assertEq(amounts[0], (units[0] * 10 + 1) * 3e18 / 10e18); // rounded down
        assertEq(tokens[0].balanceOf(alice) - before, amounts[0]);
        assertEq(basket.balanceOf(alice), 7e18 - basket.MINIMUM_SHARES());
    }

    function test_slippageBounds() public {
        _create(alice, 10e18);
        uint256[] memory max = _max();
        max[2] = 1;
        vm.prank(bob);
        vm.expectPartialRevert(SlateBasket.AboveMaximum.selector);
        basket.create(1e18, bob, max);

        uint256[] memory min = _zeros();
        min[1] = type(uint256).max;
        vm.prank(alice);
        vm.expectPartialRevert(SlateBasket.BelowMinimum.selector);
        basket.redeem(1e18, alice, min);
    }

    function test_rejectsZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(SlateBasket.ZeroShares.selector);
        basket.create(0, alice, _max());
    }

    /// A split changes what each raw token is worth, never how many the basket holds or owes.
    function test_multiplierChange_doesNotMoveHoldings() public {
        _create(alice, 10e18);
        uint256[] memory before = basket.holdings();
        tokens[0].updateMultiplier(4e18);
        uint256[] memory afterSplit = basket.holdings();
        assertEq(afterSplit[0], before[0]);
        assertEq(basket.quoteRedeem(1e18)[0], before[0] * 1e18 / basket.totalSupply());
    }

    // ---------------------------------------------------------------- invariants (fuzzed sequences)

    /// Backing per share never decreases, whatever sequence of creates and redeems runs.
    function testFuzz_backingPerShareNeverDecreases(uint256 seed) public {
        _create(alice, 10e18);
        uint256[] memory last = _backing();
        for (uint256 step; step < 24; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step)));
            address who = r % 2 == 0 ? alice : bob;
            uint256 bal = basket.balanceOf(who);
            if (r % 3 == 0 && bal > 0) {
                _redeem(who, bound(r >> 8, 1, bal));
            } else {
                _create(who, bound(r >> 8, 1, 50e18));
            }
            uint256[] memory now_ = _backing();
            for (uint256 i; i < N; ++i) {
                assertGe(now_[i], last[i]);
            }
            last = now_;
        }
    }

    /// Creating and immediately redeeming never returns more of any constituent than it took.
    function testFuzz_roundTripNeverProfits(uint256 first, uint256 shares, uint256 donation) public {
        _create(alice, bound(first, 1e18, 1000e18));
        tokens[1].mint(address(basket), bound(donation, 0, 1e18));
        shares = bound(shares, 1, 1000e18);
        uint256[] memory paid = _create(bob, shares);
        uint256[] memory back = _redeem(bob, shares);
        for (uint256 i; i < N; ++i) {
            assertLe(back[i], paid[i]);
        }
    }

    function _backing() internal view returns (uint256[] memory b) {
        uint256[] memory h = basket.holdings();
        b = new uint256[](N);
        for (uint256 i; i < N; ++i) {
            b[i] = h[i] * 1e36 / basket.totalSupply();
        }
    }
}

contract SlateNavFeedTest is Test {
    uint256 internal constant N = 3;
    USMarketCalendar internal calendar;
    SlateBasket internal basket;
    MockStockToken[] internal tokens;
    MockPriceSource[] internal sources;
    ISlateFeed[] internal feeds;
    address internal alice = makeAddr("alice");

    function setUp() public {
        vm.warp(1_790_780_400);
        calendar = new USMarketCalendar(address(this));
        IERC20[] memory c = new IERC20[](N);
        uint256[] memory units = new uint256[](N);
        for (uint256 i; i < N; ++i) {
            MockStockToken t = new MockStockToken("T", "T");
            MockPriceSource s = new MockPriceSource(PriceKind.RAW_UNDERLYING);
            tokens.push(t);
            sources.push(s);
            feeds.push(_feed(address(t), s));
            c[i] = t;
            units[i] = 1e18;
            t.mint(alice, 1000e18);
        }
        basket = new SlateBasket("Slate Basket", "SLATE-3", c, units);
        for (uint256 i; i < N; ++i) {
            vm.prank(alice);
            tokens[i].approve(address(basket), type(uint256).max);
        }
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

    function _nav() internal returns (SlateNavFeed) {
        ISlateFeed[] memory f = new ISlateFeed[](N);
        for (uint256 i; i < N; ++i) {
            f[i] = feeds[i];
        }
        return new SlateNavFeed(basket, f, true, "SLATE-3 NAV / USD");
    }

    function _createOne() internal {
        uint256[] memory max = new uint256[](N);
        for (uint256 i; i < N; ++i) {
            max[i] = type(uint256).max;
        }
        vm.prank(alice);
        basket.create(1e18, alice, max);
    }

    function test_nav_sumsTokenPrices_withMultiplier() public {
        // CRWD-style: token 0 has a 4x multiplier and a $264.98 share price.
        tokens[0].updateMultiplier(4e18);
        vm.warp(block.timestamp + 31 minutes);
        sources[0].set(26_498_000_000, 8, block.timestamp);
        sources[1].set(100e8, 8, block.timestamp);
        sources[2].set(50e8, 8, block.timestamp);
        SlateNavFeed nav = _nav();
        _createOne();
        Quote memory q = nav.latestQuote();
        assertEq(uint8(q.status), uint8(FeedStatus.OK));
        assertEq(q.answer, 105_992_000_000 + 100e8 + 50e8); // one of each token per share
        (, int256 answer,,,) = nav.latestRoundData();
        assertEq(answer, q.answer);
    }

    function test_nav_worstStatusWins_andFailsClosed() public {
        for (uint256 i; i < N; ++i) {
            sources[i].set(100e8, 8, block.timestamp);
        }
        SlateNavFeed nav = _nav();
        _createOne();
        tokens[1].setOraclePaused(true);
        assertEq(uint8(nav.status()), uint8(FeedStatus.ORACLE_PAUSED));
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.ORACLE_PAUSED));
        nav.latestRoundData();
    }

    function test_nav_noDataWithoutSupplyOrPrice() public {
        SlateNavFeed nav = _nav();
        assertEq(uint8(nav.status()), uint8(FeedStatus.NO_DATA));
        _createOne();
        assertEq(uint8(nav.status()), uint8(FeedStatus.NO_DATA)); // no prices yet
    }

    function test_nav_observedAtIsTheOldest() public {
        sources[0].set(100e8, 8, block.timestamp - 60);
        sources[1].set(100e8, 8, block.timestamp - 10);
        sources[2].set(100e8, 8, block.timestamp);
        SlateNavFeed nav = _nav();
        _createOne();
        assertEq(nav.latestQuote().observedAt, block.timestamp - 60);
    }

    function test_nav_rejectsMiswiredFeeds() public {
        ISlateFeed[] memory f = new ISlateFeed[](N);
        (f[0], f[1], f[2]) = (feeds[1], feeds[0], feeds[2]);
        vm.expectRevert(
            abi.encodeWithSelector(SlateNavFeed.FeedTokenMismatch.selector, 0, address(tokens[1]), address(tokens[0]))
        );
        new SlateNavFeed(basket, f, true, "x");
    }

    function test_nav_inUsdg() public {
        for (uint256 i; i < N; ++i) {
            sources[i].set(100e8, 8, block.timestamp);
        }
        SlateNavFeed nav = _nav();
        _createOne();
        MockAggregator usdg = new MockAggregator(8);
        usdg.set(0.9998e8, block.timestamp);
        SlateQuotedFeed navUsdg = new SlateQuotedFeed(nav, usdg, 25 hours, "SLATE-3 NAV / USDG");
        assertEq(navUsdg.latestQuote().answer, int256(300e8) * 1e8 / 0.9998e8);
    }
}
