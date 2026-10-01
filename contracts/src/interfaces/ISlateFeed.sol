// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

/// @notice Why a Slate feed will or will not serve a price.
enum FeedStatus {
    /// @dev Fresh and consistent.
    OK,
    /// @dev The session is closed (weekend, holiday or overnight gap) and the last price was fresh when it closed.
    MARKET_CLOSED,
    /// @dev Older than the feed's maximum age.
    STALE,
    /// @dev The token issuer has paused its oracle (Robinhood's `oraclePaused()`).
    ORACLE_PAUSED,
    /// @dev The price was observed before a multiplier change that has since taken effect, and the
    ///      multiplier in force at observation time is not known. Waits for a fresh price.
    STRADDLE,
    /// @dev Inside the grace window after a large (or unmeasured) multiplier change. Waits for a price
    ///      observed after the window.
    CORPORATE_ACTION,
    /// @dev No usable price.
    NO_DATA
}

/// @notice A price with the reason it can or cannot be used.
struct Quote {
    FeedStatus status;
    /// @dev 8 decimals.
    int256 answer;
    uint64 observedAt;
}

/// @notice A fail-closed Chainlink-compatible feed.
/// @dev `latestRoundData()` reverts with `FeedUnavailable` unless the status is usable.
///      `latestQuote()` never reverts on a bad status, so callers can see why.
interface ISlateFeed is AggregatorV3Interface {
    error FeedUnavailable(FeedStatus status);
    error NoHistory();

    function latestQuote() external view returns (Quote memory);

    function status() external view returns (FeedStatus);

    /// @notice Whether `MARKET_CLOSED` is served by `latestRoundData()`.
    function allowMarketClosed() external view returns (bool);
}
