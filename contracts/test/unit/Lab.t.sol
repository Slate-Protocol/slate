// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus, ISlateFeed, Quote} from "../../src/interfaces/ISlateFeed.sol";
import {LabSplitSource} from "../../src/lab/LabSplitSource.sol";
import {NaiveMultiplierFeed} from "../../src/lab/NaiveMultiplierFeed.sol";
import {SlateLabStock} from "../../src/lab/SlateLabStock.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {MockPriceSource} from "../mocks/MockPriceSource.sol";
import {Test} from "forge-std/Test.sol";

contract SlateLabStockTest is Test {
    SlateLabStock internal stock;
    address internal alice = makeAddr("alice");

    event UIMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier, uint256 effectiveAtTimestamp);

    function setUp() public {
        vm.warp(1_790_780_400);
        stock = new SlateLabStock("Slate Lab Stock", "LAB");
    }

    function test_startsAtOne() public view {
        assertEq(stock.uiMultiplier(), 1e18);
        assertEq(stock.newUIMultiplier(), 1e18);
        assertEq(stock.effectiveAt(), 0);
        assertFalse(stock.oraclePaused());
    }

    function test_schedule_eventAtStaging_switchSilentlyAtEffectiveAt() public {
        uint256 at = block.timestamp + 1 hours;
        vm.expectEmit(address(stock));
        emit UIMultiplierUpdated(1e18, 4e18, at);
        vm.prank(alice);
        stock.scheduleCorporateAction(4e18, at);

        assertEq(stock.uiMultiplier(), 1e18);
        assertEq(stock.newUIMultiplier(), 4e18);
        vm.warp(at - 1);
        assertEq(stock.uiMultiplier(), 1e18);
        vm.recordLogs();
        vm.warp(at);
        assertEq(stock.uiMultiplier(), 4e18); // no transaction, no event: it just changes
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_schedule_effectiveNowSwitchesImmediately() public {
        stock.scheduleCorporateAction(2e18, block.timestamp);
        assertEq(stock.uiMultiplier(), 2e18);
    }

    function test_schedule_chainsFromTheMultiplierInForce() public {
        stock.scheduleCorporateAction(4e18, block.timestamp + 1 minutes);
        vm.warp(block.timestamp + 10 minutes);
        vm.expectEmit(address(stock));
        emit UIMultiplierUpdated(4e18, 2e18, block.timestamp + 1 hours);
        stock.scheduleCorporateAction(2e18, block.timestamp + 1 hours);
        assertEq(stock.uiMultiplier(), 4e18);
    }

    function test_schedule_replacingAPendingActionKeepsTheCurrentMultiplier() public {
        stock.scheduleCorporateAction(4e18, block.timestamp + 1 hours);
        vm.warp(block.timestamp + 10 minutes);
        stock.scheduleCorporateAction(3e18, block.timestamp + 1 hours);
        assertEq(stock.uiMultiplier(), 1e18);
        vm.warp(block.timestamp + 1 hours);
        assertEq(stock.uiMultiplier(), 3e18);
    }

    function test_schedule_bounds() public {
        vm.expectRevert(abi.encodeWithSelector(SlateLabStock.MultiplierOutOfRange.selector, 0.01e18 - 1));
        stock.scheduleCorporateAction(0.01e18 - 1, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(SlateLabStock.MultiplierOutOfRange.selector, 100e18 + 1));
        stock.scheduleCorporateAction(100e18 + 1, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(SlateLabStock.EffectiveTimeOutOfRange.selector, block.timestamp - 1));
        stock.scheduleCorporateAction(2e18, block.timestamp - 1);
        uint256 tooLate = block.timestamp + 1 days + 1;
        vm.expectRevert(abi.encodeWithSelector(SlateLabStock.EffectiveTimeOutOfRange.selector, tooLate));
        stock.scheduleCorporateAction(2e18, tooLate);
        stock.scheduleCorporateAction(0.01e18, block.timestamp);
        assertEq(stock.uiMultiplier(), 0.01e18);
    }

    function test_schedule_cooldownIsGlobal() public {
        vm.prank(alice);
        stock.scheduleCorporateAction(2e18, block.timestamp + 1 hours);
        uint256 next = block.timestamp + 10 minutes;
        vm.warp(next - 1);
        vm.expectRevert(abi.encodeWithSelector(SlateLabStock.Cooldown.selector, next));
        stock.scheduleCorporateAction(3e18, block.timestamp + 1 hours);
        vm.warp(next);
        stock.scheduleCorporateAction(3e18, block.timestamp + 1 hours);
    }

    function test_faucet_oncePerDayPerAccount() public {
        vm.prank(alice);
        stock.faucet();
        assertEq(stock.balanceOf(alice), 100e18);
        uint256 next = block.timestamp + 1 days;
        vm.expectRevert(abi.encodeWithSelector(SlateLabStock.Cooldown.selector, next));
        vm.prank(alice);
        stock.faucet();
        stock.faucet(); // someone else is unaffected
        vm.warp(next);
        vm.prank(alice);
        stock.faucet();
        assertEq(stock.balanceOf(alice), 200e18);
    }
}

/// The Corporate Action Lab's story, as deployed: a real share price that never splits (TSLA at $1,060 here),
/// a Lab token that does, and `LabSplitSource` making the underlying split with it.
contract NaiveVersusSlateTest is Test {
    SlateLabStock internal stock;
    MockPriceSource internal tsla;
    LabSplitSource internal split;
    NaiveMultiplierFeed internal naive;
    SlateFeed internal slate;
    uint256 internal splitAt;

    function setUp() public {
        vm.warp(1_790_780_400); // a weekday, market open
        stock = new SlateLabStock("Slate Lab TSLA", "labTSLA");
        tsla = new MockPriceSource(PriceKind.RAW_UNDERLYING);
        tsla.set(1060e8, 8, block.timestamp);
        split = new LabSplitSource(tsla, bytes32("TSLA/USD"), stock);
        stock.setSplitSource(address(split));
        naive = new NaiveMultiplierFeed(split, stock);
        slate = new SlateFeed(
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
        splitAt = block.timestamp + 5 minutes;
        stock.scheduleCorporateAction(4e18, splitAt);
    }

    function _answer(ISlateFeed f) internal view returns (int256 a) {
        (, a,,,) = f.latestRoundData();
    }

    function test_beforeTheSplit_bothAgree() public view {
        (, int256 n,,,) = naive.latestRoundData();
        assertEq(n, 1060e8);
        assertEq(_answer(slate), 1060e8);
    }

    function test_atTheSplit_naiveQuadruples_slateRefuses() public {
        vm.warp(splitAt + 1); // multiplier is 4; the last print is the pre-split $1,060 share price
        (, int256 n,,,) = naive.latestRoundData();
        assertEq(n, 4240e8); // 4x overpriced: borrow against it and walk away

        Quote memory q = slate.latestQuote();
        assertEq(uint8(q.status), uint8(FeedStatus.STRADDLE));
        vm.expectRevert(abi.encodeWithSelector(ISlateFeed.FeedUnavailable.selector, FeedStatus.STRADDLE));
        slate.latestRoundData();
    }

    function test_atTheSplit_withSnapshot_slateKnowsTheOldMultiplierButStillWaits() public {
        slate.poke(); // anyone can record the multiplier before it switches
        vm.warp(splitAt + 1);
        Quote memory q = slate.latestQuote();
        assertEq(uint8(q.status), uint8(FeedStatus.CORPORATE_ACTION));
        assertEq(q.answer, 1060e8); // the pre-split print priced at the pre-split multiplier
    }

    function test_afterTheGrace_bothAgreeAgain() public {
        vm.warp(splitAt + 31 minutes);
        tsla.set(1060e8, 8, block.timestamp); // a new print; the underlying now reads $265 a share
        assertEq(split.observe(0).price, 265e8);
        (, int256 n,,,) = naive.latestRoundData();
        assertEq(n, 1060e8);
        assertEq(_answer(slate), 1060e8);
    }

    function test_freshPriceInsideTheGrace_slateStillWaits() public {
        vm.warp(splitAt + 10 minutes);
        tsla.set(1060e8, 8, block.timestamp);
        assertEq(uint8(slate.status()), uint8(FeedStatus.CORPORATE_ACTION));
    }

    /// A real split's first print comes at the next open. Prints that land before `PRINT_DELAY` are not served.
    function test_printsBeforeTheDelay_areHeldBack() public {
        vm.warp(splitAt + 1);
        tsla.set(1060e8, 8, block.timestamp); // the publisher keeps signing
        (, int256 n,,,) = naive.latestRoundData();
        assertEq(n, 4240e8); // still the frozen pre-split print × 4
        vm.warp(splitAt + split.PRINT_DELAY());
        tsla.set(1060e8, 8, block.timestamp);
        (, n,,,) = naive.latestRoundData();
        assertEq(n, 1060e8);
    }

    function test_onlyTheLabFreezes_andTheSourceIsSetOnce() public {
        vm.expectRevert(LabSplitSource.OnlyLab.selector);
        split.freeze();
        vm.expectRevert(SlateLabStock.AlreadySet.selector);
        stock.setSplitSource(address(1));
    }

    function test_multiplierAt_tracksTheSchedule() public view {
        assertEq(stock.multiplierAt(splitAt - 1), 1e18);
        assertEq(stock.multiplierAt(splitAt), 4e18);
    }
}
