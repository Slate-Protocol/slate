// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StockLender} from "../../src/examples/StockLender.sol";
import {SlateTestDollar} from "../../src/testnet/SlateTestDollar.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {Test} from "forge-std/Test.sol";

/// Drives the lender with random sequences of every user action, price moves, feed outages and time passing.
/// Ghost counters record any action that succeeded when it should not have.
contract LenderHandler is Test {
    StockLender public lender;
    SlateTestDollar public usd;
    MockStockToken public stock;
    MockAggregator public feed;
    address[] public actors;

    uint256 public borrowedWithoutPrice;
    uint256 public leftOverLimit;
    uint256 public liquidatedHealthy;
    uint256 public liquidations;
    uint256 public borrows;

    constructor(StockLender lender_, SlateTestDollar usd_, MockStockToken stock_, MockAggregator feed_) {
        (lender, usd, stock, feed) = (lender_, usd_, stock_, feed_);
        for (uint256 i; i < 4; ++i) {
            address a = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(a);
            vm.startPrank(a);
            usd.approve(address(lender), type(uint256).max);
            stock.approve(address(lender), type(uint256).max);
            vm.stopPrank();
        }
    }

    /// Every actor starts with supply and collateral, so loans are possible from the first call.
    function seed() external {
        for (uint256 i; i < actors.length; ++i) {
            usd.mint(actors[i], 100_000e6);
            stock.mint(actors[i], 100e18);
            vm.startPrank(actors[i]);
            lender.supply(100_000e6);
            lender.deposit(address(stock), 100e18);
            vm.stopPrank();
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _priceUsable() internal view returns (bool ok) {
        (ok,,) = lender.priceOf(address(stock));
    }

    function supply(uint256 who, uint256 amount) external {
        address a = _actor(who);
        amount = bound(amount, 1, 1_000_000e6);
        usd.mint(a, amount);
        vm.prank(a);
        lender.supply(amount);
    }

    function withdrawSupply(uint256 who, uint256 amount) external {
        address a = _actor(who);
        amount = bound(amount, 1, 2_000_000e6);
        vm.prank(a);
        try lender.withdrawSupply(amount) {} catch {}
    }

    function deposit(uint256 who, uint256 amount) external {
        address a = _actor(who);
        amount = bound(amount, 1, 1000e18);
        stock.mint(a, amount);
        vm.prank(a);
        lender.deposit(address(stock), amount);
    }

    function withdraw(uint256 who, uint256 amount) external {
        address a = _actor(who);
        amount = bound(amount, 1, 1000e18);
        vm.prank(a);
        try lender.withdraw(address(stock), amount) {
            _checkWithinLimit(a);
        } catch {}
    }

    function borrow(uint256 who, uint256 amount) external {
        address a = _actor(who);
        (bool priced,, uint256 owed, uint256 limit,) = lender.positionOf(address(stock), a);
        // Mostly near the remaining limit, sometimes past it.
        amount = priced && limit > owed ? bound(amount, 1, (limit - owed) * 12 / 10 + 1) : bound(amount, 1, 1000e6);
        bool usable = _priceUsable();
        vm.prank(a);
        try lender.borrow(address(stock), amount) {
            ++borrows;
            if (!usable) ++borrowedWithoutPrice;
            _checkWithinLimit(a);
        } catch {}
    }

    function repay(uint256 who, uint256 target, uint256 amount) external {
        address a = _actor(who);
        amount = bound(amount, 1, 1_000_000e6);
        usd.mint(a, amount);
        vm.prank(a);
        try lender.repay(address(stock), _actor(target), amount) {} catch {}
    }

    function liquidate(uint256 who, uint256 target, uint256 amount) external {
        address a = _actor(who);
        address t = _actor(target);
        (bool ok,, uint256 debt,, uint256 threshold) = lender.positionOf(address(stock), t);
        amount = bound(amount, 1, debt + 1);
        usd.mint(a, amount);
        vm.prank(a);
        try lender.liquidate(address(stock), t, amount) {
            ++liquidations;
            if (!ok || debt <= threshold) ++liquidatedHealthy;
        } catch {}
    }

    /// A fresh price within 40% of the last one.
    function movePrice(uint256 price) external {
        uint256 last = uint256(feed.answer());
        feed.set(int256(bound(price, last * 6 / 10 + 1e6, last * 14 / 10 + 1e6)), block.timestamp);
    }

    /// The feed goes down one call in eight and comes back otherwise.
    function feedDown(uint256 seed) external {
        feed.setReverts(seed % 8 == 0);
    }

    function wait(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 75 minutes));
    }

    function _checkWithinLimit(address a) internal {
        (bool ok,, uint256 debt, uint256 limit,) = lender.positionOf(address(stock), a);
        if (debt > 0 && (!ok || debt > limit)) ++leftOverLimit;
    }
}

contract StockLenderInvariantTest is Test {
    StockLender internal lender;
    SlateTestDollar internal usd;
    MockStockToken internal stock;
    MockAggregator internal feed;
    LenderHandler internal handler;

    function setUp() public {
        vm.warp(1_790_780_400);
        usd = new SlateTestDollar(address(this));
        stock = new MockStockToken("Stock", "STK");
        feed = new MockAggregator(8);
        feed.set(100e8, block.timestamp);
        lender = new StockLender(usd, address(this));
        lender.listMarket(address(stock), feed, 5000, 6500, 500, 1 hours);
        handler = new LenderHandler(lender, usd, stock, feed);
        usd.transferOwnership(address(handler)); // the handler mints the loan asset for its actors
        handler.seed();

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = LenderHandler.supply.selector;
        selectors[1] = LenderHandler.withdrawSupply.selector;
        selectors[2] = LenderHandler.deposit.selector;
        selectors[3] = LenderHandler.withdraw.selector;
        selectors[4] = LenderHandler.borrow.selector;
        selectors[5] = LenderHandler.repay.selector;
        selectors[6] = LenderHandler.liquidate.selector;
        selectors[7] = LenderHandler.movePrice.selector;
        selectors[8] = LenderHandler.feedDown.selector;
        selectors[9] = LenderHandler.wait.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// The loan asset the lender holds is exactly what was supplied less what is lent out.
    function invariant_cashMatchesTheBooks() public view {
        assertEq(usd.balanceOf(address(lender)), lender.totalSupplied() - lender.totalDebt());
        assertLe(lender.totalDebt(), lender.totalSupplied());
    }

    /// Collateral held equals the sum of positions; debt and supply totals equal their parts.
    function invariant_totalsEqualTheirParts() public view {
        uint256 collateral;
        uint256 debt;
        uint256 supplied;
        for (uint256 i; i < handler.actorCount(); ++i) {
            address a = handler.actors(i);
            (uint256 c, uint256 d) = lender.positions(address(stock), a);
            collateral += c;
            debt += d;
            supplied += lender.supplied(a);
        }
        assertEq(collateral, lender.totalCollateral(address(stock)));
        assertEq(collateral, stock.balanceOf(address(lender)));
        assertEq(debt, lender.totalDebt());
        assertEq(supplied, lender.totalSupplied());
    }

    /// No borrow without a usable price; no borrow or withdrawal leaves a position over its limit; no liquidation of
    /// a healthy position or without a price.
    function invariant_noRiskWithoutAPrice() public view {
        assertEq(handler.borrowedWithoutPrice(), 0);
        assertEq(handler.leftOverLimit(), 0);
        assertEq(handler.liquidatedHealthy(), 0);
    }

    /// Logs what the last run reached (loans made, liquidations after prices fell), as a sanity check on the handler.
    function afterInvariant() public {
        emit log_named_uint("borrows", handler.borrows());
        emit log_named_uint("liquidations", handler.liquidations());
    }
}
