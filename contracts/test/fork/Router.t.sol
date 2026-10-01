// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateBasket} from "../../src/basket/SlateBasket.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {SlateNavFeed} from "../../src/feeds/SlateNavFeed.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {ISlateFeed} from "../../src/interfaces/ISlateFeed.sol";
import {ISwapVenue} from "../../src/interfaces/ISwapVenue.sol";
import {IPoolManager, ISwapRouter02, PoolKey} from "../../src/interfaces/IUniswap.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {SlateRouter} from "../../src/router/SlateRouter.sol";
import {UniswapV3Venue} from "../../src/router/UniswapV3Venue.sol";
import {UniswapV4Venue} from "../../src/router/UniswapV4Venue.sol";
import {ChainlinkSource} from "../../src/sources/ChainlinkSource.sol";
import {SignedSource} from "../../src/sources/SignedSource.sol";
import {SolidityReportVerifier} from "../../src/sources/SolidityReportVerifier.sol";
import {SlateTestDollar} from "../../src/testnet/SlateTestDollar.sol";
import {SlateV4Seeder} from "../../src/testnet/SlateV4Seeder.sol";
import {ForkTest} from "./Fork.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

abstract contract RouterForkTest is ForkTest {
    address internal alice = makeAddr("alice");

    function _singleBasket(address token, ISlateFeed feed) internal returns (SlateBasket basket, SlateNavFeed nav) {
        IERC20[] memory c = new IERC20[](1);
        c[0] = IERC20(token);
        uint256[] memory units = new uint256[](1);
        units[0] = 1e18;
        basket = new SlateBasket("Slate Fork Basket", "SLATE-F", c, units);
        ISlateFeed[] memory f = new ISlateFeed[](1);
        f[0] = feed;
        nav = new SlateNavFeed(basket, f, true, "SLATE-F NAV / USD");
    }

    function _legs(ISwapVenue venue, bytes memory route) internal pure returns (SlateRouter.Leg[] memory legs) {
        legs = new SlateRouter.Leg[](1);
        legs[0] = SlateRouter.Leg({venue: venue, route: route});
    }

    /// @dev Calls `createWithCash` and returns the `RouteRefused` payload, failing on any other outcome.
    function _expectRefused(SlateRouter router, uint256 shares, SlateRouter.Leg[] memory legs, uint256 maxCash)
        internal
        returns (uint256 effective, uint256 feedPrice)
    {
        vm.prank(alice);
        (bool ok, bytes memory err) = address(router)
            .call(abi.encodeCall(SlateRouter.createWithCash, (shares, alice, legs, maxCash, block.timestamp)));
        assertFalse(ok, "route was not refused");
        assertEq(bytes4(err), SlateRouter.RouteRefused.selector);
        assembly {
            err := add(err, 4)
        }
        (, effective, feedPrice) = abi.decode(err, (uint256, uint256, uint256));
    }
}

/// Robinhood Chain testnet: the official Uniswap v4 PoolManager, and a third-party v3 deployment whose TSLA pool
/// is 99.98% off the market.
contract RobinhoodTestnetRouterForkTest is RouterForkTest {
    address internal constant TSLA = 0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E;
    IPoolManager internal constant POOL_MANAGER = IPoolManager(0x8366a39CC670B4001A1121B8F6A443A643e40951);
    // Third-party Uniswap v3 clone (not Uniswap Labs): factory 0x911b4000D3422F482F4062a913885f7b035382Df.
    ISwapRouter02 internal constant THIRD_PARTY_ROUTER = ISwapRouter02(0x3Ce954107b1A675826B33bF23060Dd655e3758fE);
    address internal constant THIRD_PARTY_USDC = 0xbf4479C07Dc6fdc6dAa764A0ccA06969e894275F; // 18 dp
    int192 internal constant TSLA_PRICE = 35_411_000_000; // $354.11, signed by the test's own signer

    SlateFeed internal feed;
    SlateBasket internal basket;
    SlateNavFeed internal nav;

    function setUp() public {
        _fork("rh_testnet");
        Signer[] memory s = _signers(1);
        address[] memory addrs = new address[](1);
        addrs[0] = s[0].addr;
        SignedSource src = new SignedSource(new SolidityReportVerifier(), address(this), addrs, 1, 50, 1000, 60);
        feed = new SlateFeed(
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
        src.submit(
            bytes32("TSLA/USD"),
            _report(src.domainSeparator(), bytes32("TSLA/USD"), s, _same(1, TSLA_PRICE), uint64(block.timestamp))
        );
        (basket, nav) = _singleBasket(TSLA, feed);
    }

    /// The refused route, against a real deployed pool: the third-party v3 TSLA/USDC pool sells TSLA for about
    /// $0.067. A router that trusts the pool fills there; Slate's refuses.
    function test_thirdPartyV3Pool_isRefused() public {
        SlateRouter router = new SlateRouter(nav, IERC20(THIRD_PARTY_USDC), AggregatorV3Interface(address(0)), 0, 300);
        deal(THIRD_PARTY_USDC, alice, 1000e18);
        vm.prank(alice);
        IERC20(THIRD_PARTY_USDC).approve(address(router), type(uint256).max);

        SlateRouter.Leg[] memory legs = _legs(new UniswapV3Venue(THIRD_PARTY_ROUTER), abi.encode(uint24(3000)));
        (uint256 effective, uint256 feedPrice) = _expectRefused(router, 2e18, legs, 1000e18);
        console.log("third-party pool, USD per TSLA (8 dp):", effective);
        console.log("Slate TSLA price  (8 dp):", feedPrice);
        assertEq(feedPrice, uint256(int256(TSLA_PRICE)));
        assertLt(effective * 1000, feedPrice); // more than 99.9% off
    }

    /// The honest path, against the official PoolManager: open a TESTUSD/TSLA v4 pool at the Slate price, buy
    /// through it, and create basket shares.
    function test_officialV4Pool_createsAtTheSlatePrice() public {
        (SlateTestDollar testusd, SlateRouter router, UniswapV4Venue venue, bytes memory route) = _v4Setup(TSLA_PRICE);

        (uint256 fair,) = router.fairCash(2e18);
        vm.prank(alice);
        uint256 spent = router.createWithCash(2e18, alice, _legs(venue, route), fair * 2, block.timestamp);

        console.log("fair TESTUSD (6 dp):", fair);
        console.log("spent TESTUSD (6 dp):", spent);
        assertGt(spent, fair); // pool fee and price impact
        assertLt(spent, fair * 1006 / 1000); // 0.3% fee + under 0.3% impact on a deep pool
        assertEq(basket.balanceOf(alice), 2e18 - basket.MINIMUM_SHARES());
        assertEq(IERC20(TSLA).balanceOf(address(basket)), 2e18);
        assertEq(testusd.balanceOf(address(router)), 0);
        (, int256 navAnswer,,,) = nav.latestRoundData();
        assertEq(navAnswer, int256(TSLA_PRICE));
    }

    /// Same official PoolManager, but the pool was opened 15% under the market. Refused, and nothing moves.
    function test_officialV4Pool_offMarket_isRefused() public {
        (SlateTestDollar testusd, SlateRouter router, UniswapV4Venue venue, bytes memory route) =
            _v4Setup(TSLA_PRICE * 85 / 100);
        uint256 before = testusd.balanceOf(alice);
        (uint256 effective,) = _expectRefused(router, 2e18, _legs(venue, route), 10_000e6);
        console.log("off-market v4 pool, USD per TSLA (8 dp):", effective);
        assertApproxEqRel(effective, uint256(int256(TSLA_PRICE)) * 85 / 100, 0.01e18);
        assertEq(testusd.balanceOf(alice), before);
        assertEq(basket.totalSupply(), 0);
    }

    function _v4Setup(int192 poolPrice)
        internal
        returns (SlateTestDollar testusd, SlateRouter router, UniswapV4Venue venue, bytes memory route)
    {
        testusd = new SlateTestDollar(address(this));
        SlateV4Seeder seeder = new SlateV4Seeder(POOL_MANAGER);
        venue = new UniswapV4Venue(POOL_MANAGER);
        route = abi.encode(uint24(3000), int24(60), address(0));
        (PoolKey memory key, bool usdIs0) = venue.poolKey(address(testusd), TSLA, route);

        // Price as token1 per token0 in raw units, then √ × 2^96.
        uint256 usdPerTsla = uint256(int256(poolPrice)) / 100; // TESTUSD units (6 dp) per 1e18 TSLA units
        uint256 sqrtPriceX96 = usdIs0
            ? Math.sqrt(Math.mulDiv(1e18, 1 << 192, usdPerTsla))
            : Math.sqrt(Math.mulDiv(usdPerTsla, 1 << 192, 1e18));
        // Full range, about 1,000 TSLA and the matching TESTUSD: L = √(amount0 × amount1).
        uint128 liquidity = uint128(Math.sqrt(1000e18 * usdPerTsla * 1000));

        deal(TSLA, address(this), 10_000e18);
        testusd.mint(address(this), 100_000_000e6);
        IERC20(TSLA).approve(address(seeder), type(uint256).max);
        testusd.approve(address(seeder), type(uint256).max);
        seeder.seed(key, uint160(sqrtPriceX96), -887_220, 887_220, liquidity, type(uint256).max, type(uint256).max);

        router = new SlateRouter(nav, testusd, AggregatorV3Interface(address(0)), 0, 300);
        testusd.mint(alice, 100_000e6);
        vm.prank(alice);
        testusd.approve(address(router), type(uint256).max);
    }
}

/// Robinhood Chain mainnet, read-only fork through `script/rpc_relay.py`: the real AAPL/USDG pool on the official
/// Uniswap v3 deployment, Chainlink's AAPL total-return feed, and Chainlink USDG/USD.
contract RobinhoodMainnetRouterForkTest is RouterForkTest {
    address internal constant AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant AAPL_USDG_POOL = 0xAae0d815EE56e4092a5E5C2911E676Fea50B2d6D; // fee 500
    AggregatorV3Interface internal constant AAPL_USD =
        AggregatorV3Interface(0x6B22A786bAa607d76728168703a39Ea9C99f2cD0);
    AggregatorV3Interface internal constant USDG_USD =
        AggregatorV3Interface(0x61B7e5650328764B076A108EFF5fa7282a1B9aD2);
    ISwapRouter02 internal constant SWAP_ROUTER_02 = ISwapRouter02(0xCaf681a66D020601342297493863E78C959E5cb2);

    function setUp() public {
        _fork("rh_mainnet");
    }

    /// Buys AAPL with USDG through the real pool. The band holds against Chainlink's AAPL price, priced in USD via
    /// Chainlink USDG/USD.
    function test_aaplUsdgPool_createsWithinTheBand() public {
        SlateFeed feed = _feed(
            AAPL,
            MultiplierModel.ERC8056,
            new ChainlinkSource(AAPL_USD, PriceKind.TOTAL_RETURN),
            4 days,
            Session.EXTENDED
        );
        (SlateBasket basket, SlateNavFeed nav) = _singleBasket(AAPL, feed);
        SlateRouter router = new SlateRouter(nav, IERC20(USDG), USDG_USD, 25 hours, 300);

        vm.prank(AAPL_USDG_POOL); // the pool holds USDG; borrow some for alice
        IERC20(USDG).transfer(alice, 1000e6);
        vm.prank(alice);
        IERC20(USDG).approve(address(router), type(uint256).max);

        (uint256 fair,) = router.fairCash(0.1e18);
        SlateRouter.Leg[] memory legs = _legs(new UniswapV3Venue(SWAP_ROUTER_02), abi.encode(uint24(500)));
        vm.prank(alice);
        uint256 spent = router.createWithCash(0.1e18, alice, legs, 1000e6, block.timestamp);
        console.log("fair USDG (6 dp):", fair);
        console.log("spent USDG (6 dp):", spent);
        assertEq(IERC20(AAPL).balanceOf(address(basket)), 0.1e18);
        assertEq(basket.balanceOf(alice), 0.1e18 - basket.MINIMUM_SHARES());
        assertEq(IERC20(USDG).balanceOf(address(router)), 0);
    }
}
