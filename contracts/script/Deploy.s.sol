// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateBasket} from "../src/basket/SlateBasket.sol";
import {USMarketCalendar} from "../src/calendar/USMarketCalendar.sol";
import {StockLender} from "../src/examples/StockLender.sol";
import {SlateFeed} from "../src/feeds/SlateFeed.sol";
import {SlateFeedFactory} from "../src/feeds/SlateFeedFactory.sol";
import {SlateNavFeed} from "../src/feeds/SlateNavFeed.sol";
import {SlateQuotedFeed} from "../src/feeds/SlateQuotedFeed.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {IERC8056} from "../src/interfaces/IERC8056.sol";
import {IMarketCalendar, Session} from "../src/interfaces/IMarketCalendar.sol";
import {IPriceSource, PriceKind} from "../src/interfaces/IPriceSource.sol";
import {IReportVerifier} from "../src/interfaces/IReportVerifier.sol";
import {ISlateFeed} from "../src/interfaces/ISlateFeed.sol";
import {IPoolManager, PoolKey} from "../src/interfaces/IUniswap.sol";
import {LabSplitSource} from "../src/lab/LabSplitSource.sol";
import {NaiveMultiplierFeed} from "../src/lab/NaiveMultiplierFeed.sol";
import {SlateLabStock} from "../src/lab/SlateLabStock.sol";
import {MultiplierModel} from "../src/libraries/MultiplierLens.sol";
import {SlateRouter} from "../src/router/SlateRouter.sol";
import {UniswapV4Venue} from "../src/router/UniswapV4Venue.sol";
import {ChainlinkSource} from "../src/sources/ChainlinkSource.sol";
import {SignedSource} from "../src/sources/SignedSource.sol";
import {SolidityReportVerifier} from "../src/sources/SolidityReportVerifier.sol";
import {SlateTestDollar} from "../src/testnet/SlateTestDollar.sol";
import {SlateV4Seeder} from "../src/testnet/SlateV4Seeder.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice Slate deployments. Each entry point writes `deployments/<chainId>.json`; `script/merge_deployments.py`
///         folds those into `deployments/deployments.json`.
///
///   RH testnet, phase 1 (core, feeds, Lab):   forge script script/Deploy.s.sol --sig "testnetCore()" ...
///   then start the publisher so the five feeds have prices, then
///   RH testnet, phase 2 (basket, pools, router): forge script script/Deploy.s.sol --sig "testnetMarket()" ...
///   RH mainnet (read-only feeds, via the relay): forge script script/Deploy.s.sol --sig "mainnet()" ...
///   Arbitrum One (Corporate Action Lab):       forge script script/Deploy.s.sol --sig "arbitrum()" ...
contract Deploy is Script {
    // Robinhood Chain testnet
    IPoolManager internal constant RH_TESTNET_POOL_MANAGER = IPoolManager(0x8366a39CC670B4001A1121B8F6A443A643e40951);
    // Robinhood Chain mainnet
    address internal constant CRWD = 0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931;
    address internal constant AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    AggregatorV3Interface internal constant AAPL_USD =
        AggregatorV3Interface(0x6B22A786bAa607d76728168703a39Ea9C99f2cD0);
    AggregatorV3Interface internal constant USDG_USD =
        AggregatorV3Interface(0x61B7e5650328764B076A108EFF5fa7282a1B9aD2);
    // Arbitrum One
    AggregatorV3Interface internal constant ARB_TSLA_USD =
        AggregatorV3Interface(0x3609baAa0a9b1f0FE4d6CC01884585d0e191C3E3);

    uint256 internal constant TIMELOCK_DELAY = 48 hours;
    bytes32 internal constant CALENDAR_SALT = keccak256("slate: calendar under the timelock");
    /// @dev Share price of SLATE-5 at first creation: $10 of each constituent.
    uint256 internal constant USD_PER_CONSTITUENT = 10e8;
    uint256 internal constant FIRST_CREATION = 5e18;
    uint256 internal constant POOL_STOCK = 3e18;
    uint256 internal constant RELAYER_STOCK = 0.5e18;
    /// @dev ±4,080 ticks is a price range of about 1/1.5x to 1.5x around the seed price.
    int24 internal constant HALF_RANGE = 4080;
    int24 internal constant TICK_SPACING = 60;
    uint24 internal constant POOL_FEE = 3000;

    string[5] internal TESTNET_SYMBOLS = ["TSLA", "AMZN", "AMD", "PLTR", "NFLX"];
    address[5] internal TESTNET_TOKENS = [
        0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E,
        0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02,
        0x71178BAc73cBeb415514eB542a8995b82669778d,
        0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0,
        0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93
    ];

    /// @dev Mainnet stock tokens with no Chainlink feed, beyond CRWD: CCL (multiplier 1.0215, the other non-1 one) and a
    ///      spread of liquid, recognisable names. The publisher's MAINNET_SYMBOLS lists the same, with CRWD.
    string[19] internal FEEDLESS_SYMBOLS = [
        "NFLX",
        "AVGO",
        "LLY",
        "COST",
        "BA",
        "JNJ",
        "IBM",
        "PFE",
        "F",
        "RIVN",
        "SNAP",
        "RBLX",
        "RDDT",
        "HIMS",
        "SHOP",
        "LMT",
        "GLD",
        "AMC",
        "CCL"
    ];
    address[19] internal FEEDLESS_TOKENS = [
        0xE0444EF8BF4eD74f74FD73686e2ddF4C1c5591E8,
        0x156E175DD063a8cE274C50654eF40e0032b3fbcF,
        0x8005d266423c7ea827372c9c864491e5786600ea,
        0x4EA005168D7F09a7A0Ba9D1DEf21a479950E44C2,
        0x4D21483a44Bf67a86b77E3dA301411880797D452,
        0x03DfbBE0AC4E7bCDaFd08eD41A400326B77D8c80,
        0x980dcf6766FA79f5Cf0c4AAdb3ab477ff15a9619,
        0x7066A64c24e4206CD62E83bf198c1E7EB361F51e,
        0x25C288E6D899b9BC30160965aD9644c67e73bE0C,
        0xB1BF26c1D20ff267A4f93550d1E0d06ac40a114B,
        0xF6589F11Bc40b669e584073F428B05562F568733,
        0xF0C4BF4C582cb3836e98394b1d4e7B7281101bE8,
        0x05b37Fb53A299a1b874A619e1c4C404D52C36F4C,
        0xCceE82fE024c36fA15E1005edE3E9e4787e23D09,
        0xF53F66751B1Eff985311b693531E3290F600c410,
        0x329fcACEb9AD6F9580DD5F643fed0646900D043c,
        0xC9a981FEE1F9DEc688bb123ccDeCc63D0deBFC4e,
        0x05a3d1Cd21d0C88145E82600E62e7E496e0F222B,
        0x9651342CeA770aE9a2969Ba2A52611523146aef9
    ];

    address internal deployer;
    string[] internal _names;
    address[] internal _addresses;
    string[] internal _symbols;
    address[] internal _tokens;
    address[] internal _feeds;

    // ------------------------------------------------------------------------------------------------
    // Robinhood Chain testnet
    // ------------------------------------------------------------------------------------------------

    function testnetCore() external {
        require(block.chainid == 46_630, "not RH testnet");
        _begin();
        (USMarketCalendar calendar, SignedSource source, SlateFeedFactory factory) = _core(2);

        for (uint256 i; i < 5; ++i) {
            SlateFeed feed = _signedFeed(factory, source, calendar, TESTNET_TOKENS[i], TESTNET_SYMBOLS[i], 20 minutes);
            _feed(TESTNET_SYMBOLS[i], TESTNET_TOKENS[i], address(feed));
        }

        // Corporate Action Lab: a Slate test token over the same signed TSLA share price, 24/5.
        _lab(factory, source, "TSLA/USD", calendar, Session.EXTENDED, 20 minutes, "labTSLA-v3");
        _contract("SlateTestDollar", address(new SlateTestDollar(deployer)));
        _end();
    }

    /// @notice Replaces the testnet Lab (token, split source, feed, naive feed), keeping everything else.
    function testnetLab() external {
        require(block.chainid == 46_630, "not RH testnet");
        string memory json = vm.readFile(_outPath());
        _load(json);
        _begin();
        _lab(
            SlateFeedFactory(vm.parseJsonAddress(json, ".contracts['SlateFeedFactory']")),
            SignedSource(vm.parseJsonAddress(json, ".contracts['SignedSource']")),
            "TSLA/USD",
            USMarketCalendar(vm.parseJsonAddress(json, ".contracts['USMarketCalendar']")),
            Session.EXTENDED,
            20 minutes,
            "labTSLA-v3"
        );
        _end();
    }

    function testnetMarket() external {
        require(block.chainid == 46_630, "not RH testnet");
        string memory json = vm.readFile(_outPath());
        deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address relayer = vm.envAddress("RELAYER_ADDRESS");
        SlateTestDollar testusd = SlateTestDollar(vm.parseJsonAddress(json, ".contracts['SlateTestDollar']"));

        IERC20[] memory tokens = new IERC20[](5);
        ISlateFeed[] memory feeds = new ISlateFeed[](5);
        uint256[] memory units = new uint256[](5);
        for (uint256 i; i < 5; ++i) {
            tokens[i] = IERC20(TESTNET_TOKENS[i]);
            feeds[i] = ISlateFeed(vm.parseJsonAddress(json, string.concat(".feeds['", TESTNET_SYMBOLS[i], "'].feed")));
            (, int256 price,,,) = feeds[i].latestRoundData(); // the publisher must be running
            units[i] = USD_PER_CONSTITUENT * 1e18 / uint256(price);
            console.log(TESTNET_SYMBOLS[i], uint256(price), units[i]);
        }

        vm.startBroadcast(deployer);
        SlateBasket basket = new SlateBasket("Slate Basket 5", "SLATE-5", tokens, units);
        SlateNavFeed nav = new SlateNavFeed(basket, feeds, true, "SLATE-5 NAV / USD (Slate, 8 dp)");
        UniswapV4Venue venue = new UniswapV4Venue(RH_TESTNET_POOL_MANAGER);
        SlateV4Seeder seeder = new SlateV4Seeder(RH_TESTNET_POOL_MANAGER);
        SlateRouter router = new SlateRouter(nav, testusd, AggregatorV3Interface(address(0)), 0, 300);

        testusd.mint(deployer, 10_000_000e6);
        testusd.approve(address(seeder), type(uint256).max);
        bytes memory route = abi.encode(POOL_FEE, TICK_SPACING, address(0));
        for (uint256 i; i < 5; ++i) {
            _seedPool(venue, seeder, testusd, TESTNET_TOKENS[i], feeds[i], route);
            tokens[i].approve(address(basket), type(uint256).max);
        }
        uint256[] memory max = new uint256[](5);
        for (uint256 i; i < 5; ++i) {
            max[i] = type(uint256).max;
        }
        basket.create(FIRST_CREATION, deployer, max);

        // The relayer recenters the pools (the testnet's missing arbitrageur), so it holds both sides.
        testusd.mint(relayer, 1_000_000e6);
        for (uint256 i; i < 5; ++i) {
            tokens[i].transfer(relayer, RELAYER_STOCK);
        }
        vm.stopBroadcast();

        _load(json);
        _contract("SlateBasket", address(basket));
        _contract("SlateNavFeed", address(nav));
        _contract("UniswapV4Venue", address(venue));
        _contract("SlateV4Seeder", address(seeder));
        _contract("SlateRouter", address(router));
        _feed("SLATE-5", address(basket), address(nav));
        _write();
    }

    function _seedPool(
        UniswapV4Venue venue,
        SlateV4Seeder seeder,
        SlateTestDollar testusd,
        address token,
        ISlateFeed feed,
        bytes memory route
    ) internal {
        (PoolKey memory key, bool cashIs0) = venue.poolKey(address(testusd), token, route);
        uint160 sqrtPrice = seeder.targetSqrtPrice(key, feed);
        int24 tick = RH_TESTNET_POOL_MANAGER.initialize(key, sqrtPrice);
        int24 lower = ((tick - HALF_RANGE) / TICK_SPACING - 1) * TICK_SPACING;
        int24 upper = ((tick + HALF_RANGE) / TICK_SPACING + 1) * TICK_SPACING;
        // Stock side of a range of about 1.5x each way: amount ≈ L × (1 − 1/√1.5) / √P (stock is token0) or
        // L × √P × (1 − 1/√1.5) (stock is token1). Solve for L from POOL_STOCK, then cap both sides.
        uint256 liquidity = cashIs0
            ? POOL_STOCK * (1 << 96) / sqrtPrice * 10_000 / 1845
            : POOL_STOCK * sqrtPrice / (1 << 96) * 10_000 / 1845;
        IERC20(token).approve(address(seeder), type(uint256).max);
        (uint256 max0, uint256 max1) =
            cashIs0 ? (type(uint256).max, POOL_STOCK * 12 / 10) : (POOL_STOCK * 12 / 10, type(uint256).max);
        seeder.seed(key, sqrtPrice, lower, upper, uint128(liquidity), max0, max1);
    }

    /// @notice StockLender: a lending market that prices collateral through Slate feeds with nothing but
    ///         `latestRoundData()`. Markets on the five stock feeds and labTSLA, loans in TESTUSD. Beside it, LAB ONLY,
    ///         the same contract on the naive labTSLA feed, to show what a split does to a lender that uses one.
    function testnetLend() external {
        require(block.chainid == 46_630, "not RH testnet");
        string memory json = vm.readFile(_outPath());
        _load(json);
        _begin();
        SlateTestDollar testusd = SlateTestDollar(vm.parseJsonAddress(json, ".contracts['SlateTestDollar']"));
        StockLender lender = new StockLender(testusd, deployer);
        for (uint256 i; i < 5; ++i) {
            address feed = vm.parseJsonAddress(json, string.concat(".feeds['", TESTNET_SYMBOLS[i], "'].feed"));
            lender.listMarket(TESTNET_TOKENS[i], AggregatorV3Interface(feed), 5000, 6500, 500, 3 days);
        }
        address lab = vm.parseJsonAddress(json, ".feeds['labTSLA'].token");
        lender.listMarket(
            lab, AggregatorV3Interface(vm.parseJsonAddress(json, ".feeds['labTSLA'].feed")), 5000, 6500, 500, 3 days
        );
        testusd.mint(deployer, 70_000e6);
        testusd.approve(address(lender), 50_000e6);
        lender.supply(50_000e6);

        StockLender naive = new StockLender(testusd, deployer);
        naive.listMarket(
            lab,
            AggregatorV3Interface(vm.parseJsonAddress(json, ".contracts['NaiveMultiplierFeed']")),
            5000,
            6500,
            500,
            3 days
        );
        testusd.approve(address(naive), 20_000e6);
        naive.supply(20_000e6);
        _contract("StockLender", address(lender));
        _contract("StockLender (naive feed, LAB ONLY)", address(naive));
        _end();
    }

    // ------------------------------------------------------------------------------------------------
    // Robinhood Chain mainnet: read-only feeds
    // ------------------------------------------------------------------------------------------------

    /// @dev The publisher signed Friday's CRWD prices for the SignedSource this deployer's nonce 3 creates. A
    ///      deployer that has sent anything before this script would put SignedSource elsewhere and make those
    ///      reports worthless, so the script refuses to run.
    address internal constant PRESIGNED_SIGNED_SOURCE = 0xf0b57272f1D69083019E8953B82bC128002D7526;

    function mainnet() external {
        require(block.chainid == 4663, "not RH mainnet");
        address d = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        require(
            vm.getNonce(d) == 0, "ABORT: deployer nonce is not 0; the presigned SignedSource address no longer holds"
        );
        require(
            vm.computeCreateAddress(d, 3) == PRESIGNED_SIGNED_SOURCE,
            "ABORT: SignedSource would not land on the presigned address"
        );
        _begin();
        (USMarketCalendar calendar, SignedSource source, SlateFeedFactory factory) = _core(2);
        require(address(source) == PRESIGNED_SIGNED_SOURCE, "ABORT: SignedSource is not on the presigned address");

        // CRWD: no Chainlink feed. Signed share price × the token's own multiplier (4.0). Mainnet gas is real, so the
        // publisher signs on a 0.5% move or every 30 minutes; the feed accepts prices up to 40 minutes old.
        SlateFeed crwd = _signedFeed(factory, source, calendar, CRWD, "CRWD", 40 minutes);
        _feed("CRWD", CRWD, address(crwd));
        SlateQuotedFeed crwdUsdg = new SlateQuotedFeed(crwd, USDG_USD, 25 hours, "CRWD / USDG (Slate, 8 dp)");
        _contract("SlateQuotedFeed CRWD/USDG", address(crwdUsdg));

        // AAPL: Chainlink's total-return feed passed through unchanged (the multiplier is already in it).
        ChainlinkSource aaplSource = new ChainlinkSource(AAPL_USD, PriceKind.TOTAL_RETURN);
        SlateFeed aapl = factory.deploy(
            _config(
                AAPL,
                aaplSource,
                "",
                calendar,
                Session.EXTENDED,
                1 days,
                30 minutes,
                "AAPL / USD (Slate over Chainlink total return, 8 dp)"
            ),
            "AAPL"
        );
        _feed("AAPL", AAPL, address(aapl));
        SlateQuotedFeed aaplUsdg = new SlateQuotedFeed(aapl, USDG_USD, 25 hours, "AAPL / USDG (Slate, 8 dp)");
        _contract("SlateQuotedFeed AAPL/USDG", address(aaplUsdg));
        _end();
    }

    // ------------------------------------------------------------------------------------------------
    // Arbitrum One: Corporate Action Lab over Chainlink's raw TSLA feed
    // ------------------------------------------------------------------------------------------------

    /// @notice Signed feeds for the feedless tokens above, through the factory and SignedSource that `mainnet()` deployed.
    ///         Run straight after it: `mainnet()` then `mainnetFeedless()`. The publisher signs these on a 1% move or every
    ///         4 hours (CRWD: 0.5% or 30 minutes), so they accept prices up to 4 h 15 min old.
    function mainnetFeedless() external {
        require(block.chainid == 4663, "not RH mainnet");
        string memory json = vm.readFile(_outPath());
        _load(json);
        SlateFeedFactory factory = SlateFeedFactory(vm.parseJsonAddress(json, ".contracts['SlateFeedFactory']"));
        SignedSource source = SignedSource(vm.parseJsonAddress(json, ".contracts['SignedSource']"));
        USMarketCalendar calendar = USMarketCalendar(vm.parseJsonAddress(json, ".contracts['USMarketCalendar']"));
        require(address(source) == PRESIGNED_SIGNED_SOURCE, "ABORT: not the presigned SignedSource");
        _begin();
        for (uint256 i; i < FEEDLESS_SYMBOLS.length; ++i) {
            require(IERC8056(FEEDLESS_TOKENS[i]).uiMultiplier() > 0, "not an ERC-8056 token");
            SlateFeed feed =
                _signedFeed(factory, source, calendar, FEEDLESS_TOKENS[i], FEEDLESS_SYMBOLS[i], 255 minutes);
            _feed(FEEDLESS_SYMBOLS[i], FEEDLESS_TOKENS[i], address(feed));
        }
        _end();
    }

    /// @notice StockLender on mainnet: USDG loans against CRWD, priced by CRWD's SlateFeed. Read-only by default: anyone
    ///         can call `quote(CRWD, 1e18)` to see what one CRWD token borrows today. With `LEND_SUPPLY_USDG` and
    ///         `LEND_COLLATERAL_CRWD` set (6 and 18 decimals) and the deployer holding both, it also supplies, deposits and
    ///         borrows half of the limit, a real loan against a token no other oracle prices. Run after `mainnet()`.
    function mainnetLend() external {
        require(block.chainid == 4663, "not RH mainnet");
        string memory json = vm.readFile(_outPath());
        _load(json);
        address crwdFeed = vm.parseJsonAddress(json, ".feeds['CRWD'].feed");
        uint256 supplyAmount = vm.envOr("LEND_SUPPLY_USDG", uint256(0));
        uint256 collateral = vm.envOr("LEND_COLLATERAL_CRWD", uint256(0));
        _begin();
        StockLender lender = new StockLender(IERC20(USDG), deployer);
        lender.listMarket(CRWD, AggregatorV3Interface(crwdFeed), 4000, 6000, 800, 3 days);
        if (supplyAmount > 0 && collateral > 0) {
            IERC20(USDG).approve(address(lender), supplyAmount);
            lender.supply(supplyAmount);
            IERC20(CRWD).approve(address(lender), collateral);
            lender.deposit(CRWD, collateral);
            (bool ok,, uint256 maxBorrow) = lender.quote(CRWD, collateral);
            require(ok, "CRWD feed not serving a price");
            lender.borrow(CRWD, maxBorrow / 2);
        }
        _contract("StockLender", address(lender));
        _end();
    }

    // ------------------------------------------------------------------------------------------------
    // Governance: everything below goes through the 48-hour TimelockController that owns SignedSource.
    // ------------------------------------------------------------------------------------------------

    /// @notice Puts the market calendar under the timelock: transfers ownership and schedules the timelock's
    ///         `acceptOwnership()`, executable after the delay with `acceptCalendar()`.
    function handOverCalendar() external {
        string memory json = vm.readFile(_outPath());
        _load(json);
        USMarketCalendar calendar = USMarketCalendar(vm.parseJsonAddress(json, ".contracts['USMarketCalendar']"));
        TimelockController timelock =
            TimelockController(payable(vm.parseJsonAddress(json, ".contracts['TimelockController']")));
        _begin();
        calendar.transferOwnership(address(timelock));
        timelock.schedule(
            address(calendar),
            0,
            abi.encodeWithSignature("acceptOwnership()"),
            bytes32(0),
            CALENDAR_SALT,
            timelock.getMinDelay()
        );
        vm.stopBroadcast();
    }

    function acceptCalendar() external {
        string memory json = vm.readFile(_outPath());
        address calendar = vm.parseJsonAddress(json, ".contracts['USMarketCalendar']");
        TimelockController timelock =
            TimelockController(payable(vm.parseJsonAddress(json, ".contracts['TimelockController']")));
        _begin();
        timelock.execute(calendar, 0, abi.encodeWithSignature("acceptOwnership()"), bytes32(0), CALENDAR_SALT);
        vm.stopBroadcast();
    }

    /// @notice Proposes a new signer set: `NEW_SIGNERS` (comma-separated) and `NEW_QUORUM`. Executable after the delay
    ///         with `executeSigners()` and the same environment.
    function proposeSigners() external {
        (TimelockController timelock, address source, bytes memory call, bytes32 salt) = _signerChange();
        _begin();
        timelock.schedule(source, 0, call, bytes32(0), salt, timelock.getMinDelay());
        vm.stopBroadcast();
        console.log("scheduled; operation id:");
        console.logBytes32(timelock.hashOperation(source, 0, call, bytes32(0), salt));
    }

    function executeSigners() external {
        (TimelockController timelock, address source, bytes memory call, bytes32 salt) = _signerChange();
        _begin();
        timelock.execute(source, 0, call, bytes32(0), salt);
        vm.stopBroadcast();
    }

    function _signerChange() internal view returns (TimelockController, address, bytes memory, bytes32) {
        string memory json = vm.readFile(_outPath());
        address[] memory next = vm.envAddress("NEW_SIGNERS", ",");
        uint8 quorum = uint8(vm.envUint("NEW_QUORUM"));
        bytes memory call = abi.encodeCall(SignedSource.setSigners, (next, quorum));
        return (
            TimelockController(payable(vm.parseJsonAddress(json, ".contracts['TimelockController']"))),
            vm.parseJsonAddress(json, ".contracts['SignedSource']"),
            call,
            keccak256(call)
        );
    }

    function arbitrum() external {
        require(block.chainid == 42_161, "not Arbitrum One");
        _begin();
        USMarketCalendar calendar = new USMarketCalendar(deployer);
        _contract("USMarketCalendar", address(calendar));
        SlateFeedFactory factory = new SlateFeedFactory();
        _contract("SlateFeedFactory", address(factory));

        ChainlinkSource tslaRaw = new ChainlinkSource(ARB_TSLA_USD, PriceKind.RAW_UNDERLYING);
        _contract("ChainlinkSource TSLA raw", address(tslaRaw));
        // Chainlink's equity feeds here update on deviation in the regular session, so the age bound is a day.
        _lab(factory, tslaRaw, "", calendar, Session.REGULAR, 1 days, "labTSLA");
        _end();
    }

    // ------------------------------------------------------------------------------------------------
    // Shared
    // ------------------------------------------------------------------------------------------------

    function _core(uint8 quorum)
        internal
        returns (USMarketCalendar calendar, SignedSource source, SlateFeedFactory factory)
    {
        calendar = new USMarketCalendar(deployer);
        SolidityReportVerifier verifier = new SolidityReportVerifier();
        address[] memory admins = new address[](1);
        admins[0] = deployer;
        TimelockController timelock = new TimelockController(TIMELOCK_DELAY, admins, admins, address(0));
        address[] memory signers = new address[](3);
        signers[0] = vm.envAddress("SIGNER_1_ADDRESS");
        signers[1] = vm.envAddress("SIGNER_2_ADDRESS");
        signers[2] = vm.envAddress("SIGNER_3_ADDRESS");
        // 0.5% spread between signers, all signers for a >10% jump, 60 s future skew. Owner: the 48 h timelock.
        source = new SignedSource(IReportVerifier(address(verifier)), address(timelock), signers, quorum, 50, 1000, 60);
        factory = new SlateFeedFactory();
        _contract("USMarketCalendar", address(calendar));
        _contract("SolidityReportVerifier", address(verifier));
        _contract("TimelockController", address(timelock));
        _contract("SignedSource", address(source));
        _contract("SlateFeedFactory", address(factory));
    }

    /// @dev A Lab token, the source that splits its underlying with it, its SlateFeed and the naive feed beside it.
    function _lab(
        SlateFeedFactory factory,
        IPriceSource inner,
        string memory innerFeedId,
        USMarketCalendar calendar,
        Session session,
        uint32 maxAge,
        bytes32 salt
    ) internal {
        SlateLabStock lab = new SlateLabStock("Slate Lab TSLA", "labTSLA");
        LabSplitSource split = new LabSplitSource(inner, bytes32(bytes(innerFeedId)), lab);
        lab.setSplitSource(address(split));
        SlateFeed feed = factory.deploy(
            _config(
                address(lab),
                split,
                "",
                calendar,
                session,
                maxAge,
                5 minutes,
                "labTSLA / USD (Slate Lab, ERC-8056 adjusted, 8 dp)"
            ),
            salt
        );
        NaiveMultiplierFeed naive = new NaiveMultiplierFeed(split, lab);
        _contract("SlateLabStock", address(lab));
        _contract("LabSplitSource", address(split));
        _contract("NaiveMultiplierFeed", address(naive));
        _feed("labTSLA", address(lab), address(feed));
    }

    function _signedFeed(
        SlateFeedFactory factory,
        SignedSource source,
        USMarketCalendar calendar,
        address token,
        string memory symbol,
        uint32 maxAge
    ) internal returns (SlateFeed) {
        return factory.deploy(
            _config(
                token,
                source,
                string.concat(symbol, "/USD"),
                calendar,
                Session.EXTENDED,
                maxAge,
                30 minutes,
                string.concat(symbol, " / USD (Slate, ERC-8056 adjusted, 8 dp)")
            ),
            bytes32(bytes(symbol))
        );
    }

    function _config(
        address token,
        IPriceSource source,
        string memory feedId,
        IMarketCalendar calendar,
        Session session,
        uint32 maxAge,
        uint32 grace,
        string memory description
    ) internal pure returns (SlateFeed.Config memory) {
        return SlateFeed.Config({
            token: token,
            model: MultiplierModel.ERC8056,
            source: source,
            feedId: bytes32(bytes(feedId)),
            maxAge: maxAge,
            corporateActionGrace: grace,
            largeChangeBps: 500,
            allowMarketClosed: true,
            calendar: calendar,
            session: session,
            description: description
        });
    }

    function _begin() internal {
        deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        vm.startBroadcast(deployer);
    }

    function _end() internal {
        vm.stopBroadcast();
        _write();
    }

    function _contract(string memory name, address addr) internal {
        for (uint256 i; i < _names.length; ++i) {
            if (keccak256(bytes(_names[i])) == keccak256(bytes(name))) {
                _addresses[i] = addr;
                return;
            }
        }
        _names.push(name);
        _addresses.push(addr);
    }

    function _feed(string memory symbol, address token, address feed) internal {
        for (uint256 i; i < _symbols.length; ++i) {
            if (keccak256(bytes(_symbols[i])) == keccak256(bytes(symbol))) {
                _tokens[i] = token;
                _feeds[i] = feed;
                return;
            }
        }
        _symbols.push(symbol);
        _tokens.push(token);
        _feeds.push(feed);
    }

    /// @dev Carries a previous run's entries into this one.
    function _load(string memory json) internal {
        string[] memory keys = vm.parseJsonKeys(json, ".contracts");
        for (uint256 i; i < keys.length; ++i) {
            _contract(keys[i], vm.parseJsonAddress(json, string.concat(".contracts['", keys[i], "']")));
        }
        string[] memory symbols = vm.parseJsonKeys(json, ".feeds");
        for (uint256 i; i < symbols.length; ++i) {
            string memory base = string.concat(".feeds['", symbols[i], "']");
            _feed(
                symbols[i],
                vm.parseJsonAddress(json, string.concat(base, ".token")),
                vm.parseJsonAddress(json, string.concat(base, ".feed"))
            );
        }
    }

    function _write() internal {
        string memory out = '{"contracts":{';
        for (uint256 i; i < _names.length; ++i) {
            out = string.concat(out, i == 0 ? "" : ",", '"', _names[i], '":"', vm.toString(_addresses[i]), '"');
        }
        out = string.concat(out, '},"feeds":{');
        for (uint256 i; i < _symbols.length; ++i) {
            out = string.concat(
                out,
                i == 0 ? "" : ",",
                '"',
                _symbols[i],
                '":{"token":"',
                vm.toString(_tokens[i]),
                '","feed":"',
                vm.toString(_feeds[i]),
                '"}'
            );
        }
        out = string.concat(out, "}}");
        if (!vm.envOr("DRY_RUN", false)) vm.writeFile(_outPath(), out);
        console.log(out);
    }

    function _outPath() internal view returns (string memory) {
        string memory standard =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        return vm.envOr("DEPLOYMENTS_FILE", standard); // a rehearsal on a fork writes elsewhere
    }
}
