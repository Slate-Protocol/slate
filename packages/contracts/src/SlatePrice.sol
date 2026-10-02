// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {FeedStatus, ISlateFeed, Quote} from "./interfaces/ISlateFeed.sol";

/// @title SlatePrice
/// @notice Reading a Slate feed, or any Chainlink-compatible feed, the fail-closed way.
/// @dev A SlateFeed's `latestRoundData()` reverts with `FeedUnavailable` instead of serving a price it cannot vouch for
///      (a split in progress, a stale or paused oracle, a closed market). `tryRead` turns that, a non-positive answer,
///      or an answer older than the caller's own bound into `ok = false`: pause what needs a price, never guess.
library SlatePrice {
    /// @notice Why `tryRead` returned no price.
    enum Reason {
        NONE,
        /// @dev The feed reverted. For a SlateFeed, `status(feed)` says why.
        REFUSED,
        NON_POSITIVE,
        /// @dev Older than the caller's `maxAge`.
        TOO_OLD
    }

    error NoPrice(address feed, Reason reason);

    /// @notice The latest price and its time, or `ok = false` with the reason.
    /// @param maxAge The caller's own bound on `updatedAt`, in seconds. A SlateFeed already refuses a price that is
    ///        stale while its market is open; this caps how long a closed-market price is trusted.
    function tryRead(AggregatorV3Interface feed, uint256 maxAge)
        internal
        view
        returns (bool ok, uint256 price, uint256 updatedAt, Reason reason)
    {
        try feed.latestRoundData() returns (uint80, int256 answer, uint256, uint256 updated, uint80) {
            if (answer <= 0) return (false, 0, updated, Reason.NON_POSITIVE);
            if (updated + maxAge < block.timestamp) return (false, 0, updated, Reason.TOO_OLD);
            // forge-lint: disable-next-line(unsafe-typecast)
            return (true, uint256(answer), updated, Reason.NONE);
        } catch {
            return (false, 0, 0, Reason.REFUSED);
        }
    }

    /// @notice Like `tryRead`, but reverts with `NoPrice` instead of returning `ok = false`.
    function read(AggregatorV3Interface feed, uint256 maxAge) internal view returns (uint256 price, uint256 updatedAt) {
        bool ok;
        Reason reason;
        (ok, price, updatedAt, reason) = tryRead(feed, maxAge);
        if (!ok) revert NoPrice(address(feed), reason);
    }

    /// @notice A SlateFeed's status and quote, which never revert: what it would serve, and why it will or won't.
    function status(ISlateFeed feed) internal view returns (FeedStatus, Quote memory q) {
        q = feed.latestQuote();
        return (q.status, q);
    }

    /// @notice The value of `amount` tokens at `price`, in `outDecimals`, rounded down.
    /// @dev Slate prices one token (the share price times the token's multiplier), so `amount` is the raw ERC-20
    ///      balance, not a share count.
    function value(uint256 amount, uint8 tokenDecimals, uint256 price, uint8 feedDecimals, uint8 outDecimals)
        internal
        pure
        returns (uint256)
    {
        return _mulDiv(amount, price * 10 ** outDecimals, 10 ** (uint256(tokenDecimals) + feedDecimals));
    }

    /// @dev Full-precision a × b ÷ d, rounded down (Remco Bloemen's mulDiv, as in OpenZeppelin's Math).
    function _mulDiv(uint256 a, uint256 b, uint256 d) private pure returns (uint256 result) {
        unchecked {
            uint256 lo;
            uint256 hi;
            assembly ("memory-safe") {
                let mm := mulmod(a, b, not(0))
                lo := mul(a, b)
                hi := sub(sub(mm, lo), lt(mm, lo))
            }
            if (hi == 0) return lo / d;
            require(d > hi, "SlatePrice: overflow");
            uint256 rem;
            assembly ("memory-safe") {
                rem := mulmod(a, b, d)
                hi := sub(hi, gt(rem, lo))
                lo := sub(lo, rem)
            }
            uint256 twos = d & (0 - d);
            assembly ("memory-safe") {
                d := div(d, twos)
                lo := div(lo, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            lo |= hi * twos;
            uint256 inv = (3 * d) ^ 2;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            inv *= 2 - d * inv;
            result = lo * inv;
        }
    }
}
