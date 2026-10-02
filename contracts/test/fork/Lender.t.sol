// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StockLender} from "../../src/examples/StockLender.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {IERC8056} from "../../src/interfaces/IERC8056.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {FeedStatus, ISlateFeed} from "../../src/interfaces/ISlateFeed.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {SignedSource} from "../../src/sources/SignedSource.sol";
import {SolidityReportVerifier} from "../../src/sources/SolidityReportVerifier.sol";
import {ForkTest} from "./Fork.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Robinhood Chain testnet: the lender on Slate's deployed TSLA feed, with the deployed TESTUSD as the loan asset.
/// The feed is live, so the test asserts whatever it is serving: a loan at exactly the limit when it serves a price,
/// a refusal when it does not.
contract RobinhoodTestnetLenderForkTest is ForkTest {
    address internal constant TSLA = 0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E;
    ISlateFeed internal constant TSLA_FEED = ISlateFeed(0x5A9cD81b257a073802E9A039e7877A604964aa84);
    IERC20 internal constant TESTUSD = IERC20(0x239f410D4D2152ba890F378f6B4Aa103B9ea7FEF);

    StockLender internal lender;
    address internal alice = makeAddr("alice");

    function setUp() public {
        _fork("rh_testnet");
        lender = new StockLender(TESTUSD, address(this));
        lender.listMarket(TSLA, TSLA_FEED, 5000, 6500, 500, 3 days);
        deal(address(TESTUSD), address(this), 100_000e6);
        TESTUSD.approve(address(lender), type(uint256).max);
        lender.supply(100_000e6);
        deal(TSLA, alice, 1e18);
        vm.startPrank(alice);
        IERC20(TSLA).approve(address(lender), 1e18);
        lender.deposit(TSLA, 1e18);
        vm.stopPrank();
    }

    function test_lendsAgainstTheLiveFeed_orRefusesWithIt() public {
        FeedStatus status = TSLA_FEED.status();
        (bool ok, uint256 value, uint256 maxBorrow) = lender.quote(TSLA, 1e18);
        bool serving = status == FeedStatus.OK || status == FeedStatus.MARKET_CLOSED;
        assertEq(ok, serving);

        vm.startPrank(alice);
        if (!serving) {
            vm.expectRevert(abi.encodeWithSelector(StockLender.PriceUnavailable.selector, TSLA));
            lender.borrow(TSLA, 1);
            return;
        }
        (, int256 answer,,,) = TSLA_FEED.latestRoundData();
        assertEq(value, uint256(answer) / 100); // 8 dp USD → 6 dp TESTUSD, one token
        lender.borrow(TSLA, maxBorrow);
        vm.expectRevert(abi.encodeWithSelector(StockLender.ExceedsLimit.selector, maxBorrow + 1, maxBorrow));
        lender.borrow(TSLA, 1);
        vm.stopPrank();
        assertEq(TESTUSD.balanceOf(alice), maxBorrow);
    }
}

/// Robinhood Chain mainnet: a loan in real Paxos USDG against the real CRWD token, which has no Chainlink feed and a
/// 4x multiplier, priced by a SlateFeed through nothing but `latestRoundData()`.
contract RobinhoodMainnetLenderForkTest is ForkTest {
    address internal constant CRWD = 0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931;
    IERC20 internal constant USDG = IERC20(0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168);

    StockLender internal lender;
    SlateFeed internal feed;
    address internal alice = makeAddr("alice");

    function setUp() public {
        _fork("rh_mainnet");
        Signer[] memory s = _signers(3);
        address[] memory addrs = new address[](3);
        for (uint256 i; i < 3; ++i) {
            addrs[i] = s[i].addr;
        }
        SignedSource src = new SignedSource(new SolidityReportVerifier(), address(this), addrs, 2, 50, 1000, 60);
        feed = new SlateFeed(
            SlateFeed.Config({
                token: CRWD,
                model: MultiplierModel.ERC8056,
                source: src,
                feedId: bytes32("CRWD/USD"),
                maxAge: 40 minutes,
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

        lender = new StockLender(USDG, address(this));
        lender.listMarket(CRWD, AggregatorV3Interface(address(feed)), 4000, 6000, 800, 3 days);
        deal(address(USDG), address(this), 10_000e6);
        USDG.approve(address(lender), type(uint256).max);
        lender.supply(10_000e6);
    }

    function test_usdgLoanAgainstRealCrwd() public {
        assertEq(IERC8056(CRWD).uiMultiplier(), 4e18);
        deal(CRWD, alice, 1e18);
        vm.startPrank(alice);
        IERC20(CRWD).approve(address(lender), 1e18);
        lender.deposit(CRWD, 1e18);
        (bool ok, uint256 value, uint256 maxBorrow) = lender.quote(CRWD, 1e18);
        assertTrue(ok);
        assertEq(value, 1059.92e6); // $264.98 a share, four shares a token
        assertEq(maxBorrow, 423.968e6); // 40% LTV
        lender.borrow(CRWD, maxBorrow);
        vm.stopPrank();
        assertEq(USDG.balanceOf(alice), 423.968e6);
        assertEq(IERC20(CRWD).balanceOf(address(lender)), 1e18);
    }
}
