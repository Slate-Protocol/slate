// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// The published package, imported the way an integrator imports it.
import {AggregatorV3Interface, SlatePrice} from "@slate-protocol/contracts/SlatePrice.sol";
import {FeedStatus, ISlateFeed, Quote} from "@slate-protocol/contracts/interfaces/ISlateFeed.sol";

import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {MockAggregator} from "../mocks/MockAggregator.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

/// The five-line integration from the README and the docs, as a contract.
contract Integrator {
    function valueOf(address slateFeed, uint256 amount) external view returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(slateFeed);
        (bool ok, uint256 price,,) = SlatePrice.tryRead(feed, 3 days);
        if (!ok) revert("no price: pause, don't guess");
        uint256 usd = SlatePrice.value(amount, 18, price, 8, 6);
        return usd;
    }
}

contract SlatePriceTest is Test {
    MockStockToken internal crwd;
    MockPriceSource internal source;
    SlateFeed internal feed;
    Integrator internal integrator;

    function setUp() public {
        vm.warp(1_790_780_400); // a weekday, market open
        crwd = new MockStockToken("CRWD", "CRWD");
        crwd.updateMultiplier(4e18);
        vm.warp(block.timestamp + 31 minutes);
        source = new MockPriceSource(PriceKind.RAW_UNDERLYING);
        source.set(26_498_000_000, 8, block.timestamp);
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
        integrator = new Integrator();
    }

    function test_readme_valuesTokensThroughASlateFeed() public view {
        assertEq(integrator.valueOf(address(feed), 2e18), 2119.84e6); // two tokens at $264.98 × 4
    }

    function test_readme_refusesDuringASplit() public {
        crwd.updateMultiplier(16e18, block.timestamp + 60);
        vm.warp(block.timestamp + 61);
        vm.expectRevert(bytes("no price: pause, don't guess"));
        integrator.valueOf(address(feed), 1e18);

        (bool ok,,, SlatePrice.Reason reason) = SlatePrice.tryRead(AggregatorV3Interface(address(feed)), 3 days);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(SlatePrice.Reason.REFUSED));
        (FeedStatus s, Quote memory q) = SlatePrice.status(ISlateFeed(address(feed)));
        assertEq(uint8(s), uint8(FeedStatus.STRADDLE));
        assertEq(uint8(q.status), uint8(FeedStatus.STRADDLE));
    }

    function test_tryRead_reasons() public {
        MockAggregator agg = new MockAggregator(8);
        agg.set(100e8, block.timestamp);
        (bool ok, uint256 price, uint256 at, SlatePrice.Reason reason) =
            SlatePrice.tryRead(AggregatorV3Interface(address(agg)), 1 hours);
        assertTrue(ok);
        assertEq(price, 100e8);
        assertEq(at, block.timestamp);
        assertEq(uint8(reason), uint8(SlatePrice.Reason.NONE));

        vm.warp(block.timestamp + 1 hours + 1);
        (ok,,, reason) = SlatePrice.tryRead(AggregatorV3Interface(address(agg)), 1 hours);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(SlatePrice.Reason.TOO_OLD));

        agg.set(0, block.timestamp);
        (ok,,, reason) = SlatePrice.tryRead(AggregatorV3Interface(address(agg)), 1 hours);
        assertEq(uint8(reason), uint8(SlatePrice.Reason.NON_POSITIVE));

        agg.setReverts(true);
        (ok,,, reason) = SlatePrice.tryRead(AggregatorV3Interface(address(agg)), 1 hours);
        assertEq(uint8(reason), uint8(SlatePrice.Reason.REFUSED));
    }

    function test_read_revertsWithTheReason() public {
        MockAggregator agg = new MockAggregator(8);
        agg.setReverts(true);
        vm.expectRevert(abi.encodeWithSelector(SlatePrice.NoPrice.selector, address(agg), SlatePrice.Reason.REFUSED));
        this.readExternal(AggregatorV3Interface(address(agg)));
    }

    function readExternal(AggregatorV3Interface agg) external view returns (uint256 price) {
        (price,) = SlatePrice.read(agg, 1 hours);
    }

    /// A result too large for 256 bits reverts rather than wrapping.
    function test_value_revertsOnOverflow() public {
        vm.expectRevert(bytes("SlatePrice: overflow"));
        this.valueExternal(type(uint160).max, 0, type(uint128).max, 0, 18);
    }

    function valueExternal(uint256 amount, uint8 tokenDec, uint256 price, uint8 feedDec, uint8 outDec)
        external
        pure
        returns (uint256)
    {
        return SlatePrice.value(amount, tokenDec, price, feedDec, outDec);
    }

    /// Whether a × b ÷ d fits in 256 bits: the high word of the 512-bit product is below d.
    function _fits(uint256 a, uint256 b, uint256 d) internal pure returns (bool) {
        uint256 lo;
        uint256 hi;
        assembly ("memory-safe") {
            let mm := mulmod(a, b, not(0))
            lo := mul(a, b)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
        return hi < d;
    }

    /// `value` must agree with OpenZeppelin's mulDiv everywhere the result fits, including products wider than 256 bits.
    function testFuzz_value_matchesOpenZeppelin(
        uint256 amount,
        uint256 price,
        uint8 tokenDec,
        uint8 feedDec,
        uint8 outDec
    ) public pure {
        tokenDec = uint8(bound(tokenDec, 0, 18));
        feedDec = uint8(bound(feedDec, 0, 18));
        outDec = uint8(bound(outDec, 0, 18));
        price = bound(price, 1, type(uint128).max);
        amount = bound(amount, 0, type(uint160).max);
        uint256 d = 10 ** (uint256(tokenDec) + feedDec);
        vm.assume(_fits(amount, price * 10 ** outDec, d)); // the true result fits in 256 bits
        uint256 expected = Math.mulDiv(amount, price * 10 ** outDec, d);
        assertEq(SlatePrice.value(amount, tokenDec, price, feedDec, outDec), expected);
    }
}
