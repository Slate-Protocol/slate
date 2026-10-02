// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {StockLender} from "../../src/examples/StockLender.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {LabSplitSource} from "../../src/lab/LabSplitSource.sol";
import {NaiveMultiplierFeed} from "../../src/lab/NaiveMultiplierFeed.sol";
import {SlateLabStock} from "../../src/lab/SlateLabStock.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {SlateTestDollar} from "../../src/testnet/SlateTestDollar.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";

abstract contract LenderBase is Test {
    SlateTestDollar internal usd; // 6 decimals, stands in for a dollar stablecoin
    StockLender internal lender;
    address internal supplier = makeAddr("supplier");
    address internal alice = makeAddr("alice");
    address internal liquidator = makeAddr("liquidator");

    function _lender() internal {
        usd = new SlateTestDollar(address(this));
        lender = new StockLender(usd, address(this));
        usd.mint(supplier, 1_000_000e6);
        usd.mint(liquidator, 1_000_000e6);
        vm.prank(supplier);
        usd.approve(address(lender), type(uint256).max);
        vm.prank(supplier);
        lender.supply(1_000_000e6);
        vm.prank(liquidator);
        usd.approve(address(lender), type(uint256).max);
    }

    function _deposit(address who, MockStockToken token, uint256 amount) internal {
        token.mint(who, amount);
        vm.startPrank(who);
        token.approve(address(lender), amount);
        lender.deposit(address(token), amount);
        vm.stopPrank();
    }
}

/// The lender on its own, against a plain Chainlink-style feed.
contract StockLenderTest is LenderBase {
    MockStockToken internal stock;
    MockAggregator internal feed;

    function setUp() public {
        vm.warp(1_790_780_400);
        _lender();
        stock = new MockStockToken("Stock", "STK");
        feed = new MockAggregator(8);
        feed.set(100e8, block.timestamp); // $100 a token
        lender.listMarket(address(stock), feed, 5000, 6500, 500, 1 hours);
    }

    // --- listing ---

    function test_list_onlyOwner() public {
        MockStockToken other = new MockStockToken("O", "O");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        lender.listMarket(address(other), feed, 5000, 6500, 500, 1 hours);
    }

    function test_list_rejectsBadParameters() public {
        MockStockToken other = new MockStockToken("O", "O");
        vm.expectRevert(StockLender.BadParameters.selector); // LTV at or above the liquidation threshold
        lender.listMarket(address(other), feed, 6500, 6500, 500, 1 hours);
        vm.expectRevert(StockLender.BadParameters.selector); // threshold x (1 + bonus) above 100%
        lender.listMarket(address(other), feed, 5000, 9600, 500, 1 hours);
        vm.expectRevert(StockLender.BadParameters.selector);
        lender.listMarket(address(other), AggregatorV3Interface(address(0)), 5000, 6500, 500, 1 hours);
        vm.expectRevert(StockLender.BadParameters.selector);
        lender.listMarket(address(other), feed, 5000, 6500, 500, 0);
        vm.expectRevert(StockLender.BadParameters.selector);
        lender.listMarket(address(usd), feed, 5000, 6500, 500, 1 hours);
        vm.expectRevert(abi.encodeWithSelector(StockLender.AlreadyListed.selector, address(stock)));
        lender.listMarket(address(stock), feed, 5000, 6500, 500, 1 hours);
    }

    function test_unlisted_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(StockLender.NotListed.selector, address(0xBEEF)));
        lender.deposit(address(0xBEEF), 1);
        vm.expectRevert(abi.encodeWithSelector(StockLender.NotListed.selector, address(0xBEEF)));
        lender.priceOf(address(0xBEEF));
    }

    // --- suppliers ---

    function test_supply_andWithdrawOnlyFromCash() public {
        _deposit(alice, stock, 10e18);
        vm.prank(alice);
        lender.borrow(address(stock), 400e6);
        assertEq(lender.cash(), 1_000_000e6 - 400e6);

        vm.prank(supplier);
        vm.expectRevert(
            abi.encodeWithSelector(StockLender.InsufficientLiquidity.selector, 1_000_000e6, 1_000_000e6 - 400e6)
        );
        lender.withdrawSupply(1_000_000e6);

        vm.prank(supplier);
        lender.withdrawSupply(1_000_000e6 - 400e6);
        assertEq(usd.balanceOf(supplier), 1_000_000e6 - 400e6);
        assertEq(lender.cash(), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StockLender.InsufficientSupply.selector, 1, 0));
        lender.withdrawSupply(1);
    }

    // --- borrowing ---

    function test_borrow_upToTheLimit() public {
        _deposit(alice, stock, 10e18); // $1,000 of collateral, 50% LTV
        vm.startPrank(alice);
        lender.borrow(address(stock), 500e6);
        vm.expectRevert(abi.encodeWithSelector(StockLender.ExceedsLimit.selector, 500e6 + 1, 500e6));
        lender.borrow(address(stock), 1);
        vm.stopPrank();
        assertEq(usd.balanceOf(alice), 500e6);
        (bool ok, uint256 c, uint256 d, uint256 limit, uint256 threshold) = lender.positionOf(address(stock), alice);
        assertTrue(ok);
        assertEq(c, 10e18);
        assertEq(d, 500e6);
        assertEq(limit, 500e6);
        assertEq(threshold, 650e6);
    }

    function test_quote() public view {
        (bool ok, uint256 value, uint256 maxBorrow) = lender.quote(address(stock), 3e18);
        assertTrue(ok);
        assertEq(value, 300e6);
        assertEq(maxBorrow, 150e6);
    }

    function test_borrow_cannotExceedCash() public {
        _deposit(alice, stock, 100_000e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StockLender.InsufficientLiquidity.selector, 1_000_001e6, 1_000_000e6));
        lender.borrow(address(stock), 1_000_001e6);
    }

    // --- no price, no risk-taking; repaying still works ---

    function test_feedReverts_blocksBorrowWithdrawAndLiquidate_butNotRepayOrDeposit() public {
        _deposit(alice, stock, 10e18);
        vm.prank(alice);
        lender.borrow(address(stock), 300e6);
        feed.setReverts(true);

        (bool ok,,) = lender.priceOf(address(stock));
        assertFalse(ok);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StockLender.PriceUnavailable.selector, address(stock)));
        lender.borrow(address(stock), 1);
        vm.expectRevert(abi.encodeWithSelector(StockLender.PriceUnavailable.selector, address(stock)));
        lender.withdraw(address(stock), 1);
        vm.stopPrank();
        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(StockLender.PriceUnavailable.selector, address(stock)));
        lender.liquidate(address(stock), alice, 1);

        _deposit(alice, stock, 1e18);
        vm.startPrank(alice);
        usd.approve(address(lender), 300e6);
        assertEq(lender.repay(address(stock), alice, type(uint256).max), 300e6);
        lender.withdraw(address(stock), 11e18); // no debt, so no price needed
        vm.stopPrank();
        assertEq(stock.balanceOf(alice), 11e18);
    }

    function test_staleOrNonPositive_isNoPrice() public {
        _deposit(alice, stock, 10e18);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StockLender.PriceUnavailable.selector, address(stock)));
        lender.borrow(address(stock), 1);

        feed.set(0, block.timestamp);
        (bool ok,,) = lender.priceOf(address(stock));
        assertFalse(ok);
        feed.set(-1, block.timestamp);
        (ok,,) = lender.priceOf(address(stock));
        assertFalse(ok);
    }

    function test_withdraw_mustStayWithinTheLimit() public {
        _deposit(alice, stock, 10e18);
        vm.startPrank(alice);
        lender.borrow(address(stock), 400e6);
        vm.expectRevert(abi.encodeWithSelector(StockLender.ExceedsLimit.selector, 400e6, 350e6));
        lender.withdraw(address(stock), 3e18); // 7 tokens left: limit $350
        lender.withdraw(address(stock), 2e18); // 8 tokens left: limit $400
        vm.stopPrank();
        assertEq(stock.balanceOf(alice), 2e18);
    }

    // --- liquidation ---

    function test_liquidate_onlyWhenUnhealthy_withBonus() public {
        _deposit(alice, stock, 10e18);
        vm.prank(alice);
        lender.borrow(address(stock), 500e6);

        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(StockLender.Healthy.selector, 500e6, 650e6));
        lender.liquidate(address(stock), alice, 100e6);

        feed.set(70e8, block.timestamp); // collateral $700, threshold $455 < debt $500
        vm.prank(liquidator);
        (uint256 repaid, uint256 seized) = lender.liquidate(address(stock), alice, 100e6);
        assertEq(repaid, 100e6);
        assertEq(seized, 1.5e18); // $105 at $70
        assertEq(stock.balanceOf(liquidator), 1.5e18);
        (, uint256 c, uint256 d,,) = lender.positionOf(address(stock), alice);
        assertEq(c, 8.5e18);
        assertEq(d, 400e6);
    }

    function test_liquidate_capsAtCollateral_leavingBadDebt() public {
        _deposit(alice, stock, 10e18);
        vm.prank(alice);
        lender.borrow(address(stock), 500e6);
        feed.set(40e8, block.timestamp); // collateral $400 against $500 of debt

        vm.prank(liquidator);
        (uint256 repaid, uint256 seized) = lender.liquidate(address(stock), alice, type(uint256).max);
        assertEq(seized, 10e18);
        assertEq(repaid, 380_952_381); // $400 / 1.05, rounded up
        (, uint256 c, uint256 d,,) = lender.positionOf(address(stock), alice);
        assertEq(c, 0);
        assertEq(d, 500e6 - 380_952_381);
        assertEq(lender.totalDebt(), d);
    }

    function testFuzz_borrowNeverExceedsTheLimit(uint96 collateral, uint64 price, uint96 amount) public {
        collateral = uint96(bound(collateral, 1, 1e30));
        price = uint64(bound(price, 1, 1e14));
        amount = uint96(bound(amount, 1, 1_000_000e6));
        feed.set(int256(uint256(price)), block.timestamp);
        _deposit(alice, stock, collateral);
        uint256 limit = uint256(collateral) * price * 1e6 / 1e26 * 5000 / 10_000;
        vm.prank(alice);
        if (amount > limit) {
            vm.expectRevert(abi.encodeWithSelector(StockLender.ExceedsLimit.selector, amount, limit));
        }
        lender.borrow(address(stock), amount);
    }
}

/// A SlateFeed on a token whose multiplier is 4: the lender values a token, not a share.
contract StockLenderSlateFeedTest is LenderBase {
    MockStockToken internal crwd;
    MockPriceSource internal source;
    SlateFeed internal feed;

    function setUp() public {
        vm.warp(1_790_780_400); // a weekday, market open
        _lender();
        crwd = new MockStockToken("CRWD", "CRWD");
        crwd.updateMultiplier(4e18); // the split, well before the price below
        vm.warp(block.timestamp + 31 minutes);
        source = new MockPriceSource(PriceKind.RAW_UNDERLYING);
        source.set(26_498_000_000, 8, block.timestamp); // a share
        feed = new SlateFeed(
            SlateFeed.Config({
                token: address(crwd),
                model: MultiplierModel.ERC8056,
                source: source,
                feedId: bytes32(0),
                maxAge: 15 minutes,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: true,
                calendar: new USMarketCalendar(address(this)),
                session: Session.EXTENDED,
                description: "CRWD / USD"
            })
        );
        lender.listMarket(address(crwd), feed, 5000, 6500, 500, 3 days);
    }

    function test_valuesATokenAtFourShares() public view {
        (bool ok, uint256 value, uint256 maxBorrow) = lender.quote(address(crwd), 1e18);
        assertTrue(ok);
        assertEq(value, 1059.92e6);
        assertEq(maxBorrow, 529.96e6);
    }

    function test_staleWhileOpen_isRefusedByTheFeed_evenWithALongLenderBound() public {
        vm.warp(block.timestamp + 16 minutes);
        (bool ok,,) = lender.priceOf(address(crwd));
        assertFalse(ok); // the feed says STALE and reverts; the lender's 3-day bound never comes into it
    }
}

/// The Lab story, with a lender on each feed: the same contract, the same token, two price sources.
contract StockLenderSplitTest is LenderBase {
    SlateLabStock internal stock;
    MockPriceSource internal tsla;
    LabSplitSource internal split;
    SlateFeed internal slateFeed;
    NaiveMultiplierFeed internal naiveFeed;
    StockLender internal naiveLender;

    function setUp() public {
        vm.warp(1_790_780_400);
        _lender();
        stock = new SlateLabStock("Slate Lab TSLA", "labTSLA");
        tsla = new MockPriceSource(PriceKind.RAW_UNDERLYING);
        tsla.set(1060e8, 8, block.timestamp);
        split = new LabSplitSource(tsla, bytes32("TSLA/USD"), stock);
        stock.setSplitSource(address(split));
        naiveFeed = new NaiveMultiplierFeed(split, stock);
        slateFeed = new SlateFeed(
            SlateFeed.Config({
                token: address(stock),
                model: MultiplierModel.ERC8056,
                source: split,
                feedId: bytes32(0),
                maxAge: 15 minutes,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: true,
                calendar: new USMarketCalendar(address(this)),
                session: Session.EXTENDED,
                description: "labTSLA / USD"
            })
        );
        lender.listMarket(address(stock), slateFeed, 5000, 6500, 500, 1 hours);

        naiveLender = new StockLender(usd, address(this));
        naiveLender.listMarket(address(stock), naiveFeed, 5000, 6500, 500, 1 hours);
        usd.mint(address(this), 1_000_000e6);
        usd.approve(address(naiveLender), type(uint256).max);
        naiveLender.supply(1_000_000e6);

        vm.startPrank(alice);
        stock.faucet(); // 100 labTSLA, but one is enough
        stock.approve(address(lender), 1e18);
        lender.deposit(address(stock), 1e18);
        stock.approve(address(naiveLender), 1e18);
        naiveLender.deposit(address(stock), 1e18);
        vm.stopPrank();
    }

    function test_beforeTheSplit_bothLendTheSame() public view {
        (, uint256 v1, uint256 b1) = lender.quote(address(stock), 1e18);
        (, uint256 v2, uint256 b2) = naiveLender.quote(address(stock), 1e18);
        assertEq(v1, 1060e6);
        assertEq(v2, 1060e6);
        assertEq(b1, b2);
    }

    /// A 4:1 split: the naive feed prices the token at 4x and its lender hands out more than the token is worth.
    function test_split_naiveLenderTakesBadDebt_slateLenderWaits() public {
        uint256 at = block.timestamp + 90;
        stock.scheduleCorporateAction(4e18, at);
        vm.warp(at + 1);

        vm.prank(alice);
        naiveLender.borrow(address(stock), 2120e6); // 50% of $4,240 for a token worth $1,060
        assertGt(usd.balanceOf(alice), 1060e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StockLender.PriceUnavailable.selector, address(stock)));
        lender.borrow(address(stock), 1);

        // After the grace window and a post-split print, the Slate-fed lender lends again at the true value.
        vm.warp(at + 31 minutes);
        tsla.set(1060e8, 8, block.timestamp);
        (bool ok, uint256 value, uint256 maxBorrow) = lender.quote(address(stock), 1e18);
        assertTrue(ok);
        assertEq(value, 1060e6);
        vm.prank(alice);
        lender.borrow(address(stock), maxBorrow);
    }

    /// A 1:4 reverse split: the naive feed prices the token at a quarter and its lender liquidates a healthy loan.
    function test_reverseSplit_naiveLenderLiquidatesAHealthyLoan_slateLenderDoesNot() public {
        vm.startPrank(alice);
        lender.borrow(address(stock), 500e6);
        naiveLender.borrow(address(stock), 500e6);
        vm.stopPrank();

        uint256 at = block.timestamp + 90;
        stock.scheduleCorporateAction(0.25e18, at);
        vm.warp(at + 1);

        vm.prank(liquidator);
        usd.approve(address(naiveLender), type(uint256).max);
        vm.prank(liquidator);
        (, uint256 seized) = naiveLender.liquidate(address(stock), alice, 500e6);
        assertEq(seized, 1e18); // the whole token, worth $1,060, for at most $252 of debt

        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(StockLender.PriceUnavailable.selector, address(stock)));
        lender.liquidate(address(stock), alice, 500e6);
    }
}
