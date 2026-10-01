// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateBasket} from "../basket/SlateBasket.sol";
import {SlateNavFeed} from "../feeds/SlateNavFeed.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {ISlateFeed} from "../interfaces/ISlateFeed.sol";
import {ISwapVenue} from "../interfaces/ISwapVenue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title SlateRouter
/// @notice Creates basket shares from one cash token (USDG on Robinhood Chain) by buying each constituent through
///         a swap venue, and refuses any leg whose fill is too far from that constituent's Slate price.
/// @dev The band is the point: a pool is not a price. On Robinhood Chain testnet a third-party v3 pool sells TSLA
///      at 99.98% below the market; a router that trusts the pool would happily fill there, and one that buys at a
///      premium could be drained by a manipulated pool. Each leg's effective price (cash spent × cash/USD ÷ tokens
///      received) must sit within `maxDeviationBps` of the constituent's `SlateFeed` answer, read through
///      `latestRoundData()` so a stale, paused or mid-split feed stops the whole creation. The router holds
///      nothing between calls; leftover cash is refunded.
contract SlateRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint8 private constant PRICE_DECIMALS = 8;
    /// @notice The widest band a router may be deployed with.
    uint256 public constant MAX_DEVIATION_LIMIT_BPS = 2000;

    SlateBasket public immutable basket;
    SlateNavFeed public immutable navFeed;
    /// @notice The token creations are paid in.
    IERC20 public immutable cash;
    /// @notice Cash/USD feed, such as Chainlink USDG/USD. `address(0)` prices cash at exactly $1, which is only
    ///         for testnet stand-ins.
    AggregatorV3Interface public immutable cashUsdFeed;
    /// @notice The oldest cash/USD answer accepted, in seconds.
    uint256 public immutable cashUsdMaxAge;
    /// @notice How far a leg's effective price may sit from the Slate price, either way, in basis points.
    uint256 public immutable maxDeviationBps;
    uint8 private immutable _cashDecimals;

    /// @notice How to buy one constituent.
    struct Leg {
        ISwapVenue venue;
        bytes route;
    }

    /// @notice What one leg bought and at what price.
    struct Fill {
        uint256 amount;
        uint256 cashIn;
        /// @dev USD per whole token, 8 decimals.
        uint256 effectivePrice;
        uint256 feedPrice;
    }

    event CreatedWithCash(address indexed caller, address indexed to, uint256 shares, uint256 cashIn, Fill[] fills);

    error ZeroAddress();
    error LengthMismatch();
    error DeviationTooWide(uint256 bps);
    error Expired(uint256 deadline);
    error CashPriceUnavailable();
    error ShortFill(uint256 index, uint256 received, uint256 expected);
    error RouteRefused(uint256 index, uint256 effectivePrice, uint256 feedPrice);
    error TooMuchCash(uint256 cashIn, uint256 maxCashIn);

    constructor(
        SlateNavFeed navFeed_,
        IERC20 cash_,
        AggregatorV3Interface cashUsdFeed_,
        uint256 cashUsdMaxAge_,
        uint256 maxDeviationBps_
    ) {
        if (address(navFeed_) == address(0) || address(cash_) == address(0)) {
            revert ZeroAddress();
        }
        if (maxDeviationBps_ == 0 || maxDeviationBps_ > MAX_DEVIATION_LIMIT_BPS) {
            revert DeviationTooWide(maxDeviationBps_);
        }
        navFeed = navFeed_;
        basket = navFeed_.basket();
        cash = cash_;
        cashUsdFeed = cashUsdFeed_;
        cashUsdMaxAge = cashUsdMaxAge_;
        maxDeviationBps = maxDeviationBps_;
        _cashDecimals = IERC20Metadata(address(cash_)).decimals();
    }

    // ------------------------------------------------------------------------------------------------
    // Create
    // ------------------------------------------------------------------------------------------------

    /// @notice Buys the constituents for `shares` and creates them for `to`, spending at most `maxCashIn`.
    /// @param legs One venue and route per constituent, in basket order.
    /// @return cashIn What was spent; the rest of `maxCashIn` goes back to the caller.
    function createWithCash(uint256 shares, address to, Leg[] calldata legs, uint256 maxCashIn, uint256 deadline)
        external
        nonReentrant
        returns (uint256 cashIn)
    {
        if (block.timestamp > deadline) revert Expired(deadline);
        if (to == address(0)) revert ZeroAddress();
        uint256 n = basket.constituentCount();
        if (legs.length != n) revert LengthMismatch();

        uint256[] memory amounts = basket.quoteCreate(shares);
        ISlateFeed[] memory feeds = navFeed.feeds();
        uint256 cashUsd = cashPrice();

        cash.safeTransferFrom(msg.sender, address(this), maxCashIn);
        Fill[] memory fills = new Fill[](n);
        for (uint256 i; i < n; ++i) {
            fills[i] = _buy(i, legs[i], feeds[i], amounts[i], maxCashIn - cashIn, cashUsd);
            cashIn += fills[i].cashIn;
        }
        if (cashIn > maxCashIn) revert TooMuchCash(cashIn, maxCashIn);

        for (uint256 i; i < n; ++i) {
            basket.constituent(i).forceApprove(address(basket), amounts[i]);
        }
        basket.create(shares, to, amounts);

        if (maxCashIn > cashIn) cash.safeTransfer(msg.sender, maxCashIn - cashIn);
        emit CreatedWithCash(msg.sender, to, shares, cashIn, fills);
    }

    // ------------------------------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------------------------------

    /// @notice Cash/USD with 8 decimals: the feed's answer, or exactly $1 with no feed.
    function cashPrice() public view returns (uint256) {
        if (address(cashUsdFeed) == address(0)) return 10 ** PRICE_DECIMALS;
        (, int256 answer,, uint256 updatedAt,) = cashUsdFeed.latestRoundData();
        if (answer <= 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > cashUsdMaxAge) {
            revert CashPriceUnavailable();
        }
        return _to8(SafeCast.toUint256(answer), cashUsdFeed.decimals());
    }

    /// @notice What creating `shares` costs at the Slate prices, in cash units, before fees and slippage. Reverts
    ///         like `createWithCash` would if any price is unusable. Add your slippage to set `maxCashIn`.
    function fairCash(uint256 shares) external view returns (uint256 total, uint256[] memory amounts) {
        amounts = basket.quoteCreate(shares);
        ISlateFeed[] memory feeds = navFeed.feeds();
        uint256 cashUsd = cashPrice();
        for (uint256 i; i < amounts.length; ++i) {
            uint256 price = _feedPrice(feeds[i]);
            uint256 usd =
                Math.mulDiv(amounts[i], price, 10 ** IERC20Metadata(address(basket.constituent(i))).decimals());
            total += Math.mulDiv(usd, 10 ** _cashDecimals, cashUsd, Math.Rounding.Ceil);
        }
    }

    // ------------------------------------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------------------------------------

    function _buy(uint256 i, Leg calldata leg, ISlateFeed feed, uint256 amount, uint256 budget, uint256 cashUsd)
        private
        returns (Fill memory fill)
    {
        IERC20 token = basket.constituent(i);
        fill.amount = amount;
        fill.feedPrice = _feedPrice(feed);

        uint256 tokensBefore = token.balanceOf(address(this));
        uint256 cashBefore = cash.balanceOf(address(this));
        cash.forceApprove(address(leg.venue), budget);
        leg.venue.swapExactOut(address(cash), address(token), amount, budget, leg.route);
        cash.forceApprove(address(leg.venue), 0);

        // Trust balances, not the venue's return value.
        uint256 received = token.balanceOf(address(this)) - tokensBefore;
        if (received < amount) revert ShortFill(i, received, amount);
        fill.cashIn = cashBefore - cash.balanceOf(address(this));

        uint256 usd = Math.mulDiv(fill.cashIn, cashUsd, 10 ** _cashDecimals);
        fill.effectivePrice = Math.mulDiv(usd, 10 ** IERC20Metadata(address(token)).decimals(), amount);
        if (!_withinBand(fill.effectivePrice, fill.feedPrice)) {
            revert RouteRefused(i, fill.effectivePrice, fill.feedPrice);
        }
    }

    /// @dev Reverts with `FeedUnavailable` unless the feed's own policy says the price is usable.
    function _feedPrice(ISlateFeed feed) private view returns (uint256) {
        (, int256 answer,,,) = feed.latestRoundData();
        return _to8(SafeCast.toUint256(answer), feed.decimals());
    }

    function _withinBand(uint256 price, uint256 anchor) private view returns (bool) {
        uint256 diff = price > anchor ? price - anchor : anchor - price;
        return diff * BPS <= anchor * maxDeviationBps;
    }

    function _to8(uint256 value, uint8 decimals) private pure returns (uint256) {
        if (decimals == PRICE_DECIMALS) return value;
        if (decimals > PRICE_DECIMALS) return value / 10 ** (decimals - PRICE_DECIMALS);
        return value * 10 ** (PRICE_DECIMALS - decimals);
    }
}
