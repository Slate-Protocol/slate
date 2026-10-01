// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {FeedStatus, ISlateFeed, Quote} from "../interfaces/ISlateFeed.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title SlateQuotedFeed
/// @notice Re-quotes a USD Slate feed in another currency using that currency's USD price feed.
/// @dev Built for Paxos USDG: base is any `ISlateFeed` (a stock token or a basket NAV) and `quote` is the
///      USDG / USD Chainlink feed on Robinhood Chain (0x61B7e5650328764B076A108EFF5fa7282a1B9aD2). The
///      answer is `base / quote` with 8 decimals: the price in USDG. A stale or missing quote price makes
///      the whole feed unusable, and the observation time is the older of the two.
contract SlateQuotedFeed is ISlateFeed {
    uint8 public constant DECIMALS = 8;
    uint256 public constant VERSION = 1;

    ISlateFeed public immutable base;
    AggregatorV3Interface public immutable quote;
    uint32 public immutable quoteMaxAge;
    uint8 private immutable _quoteDecimals;
    string private _description;

    error ZeroAddress();
    error ZeroMaxAge();

    constructor(ISlateFeed base_, AggregatorV3Interface quote_, uint32 quoteMaxAge_, string memory description_) {
        if (address(base_) == address(0) || address(quote_) == address(0)) revert ZeroAddress();
        if (quoteMaxAge_ == 0) revert ZeroMaxAge();
        base = base_;
        quote = quote_;
        quoteMaxAge = quoteMaxAge_;
        _quoteDecimals = quote_.decimals();
        _description = description_;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function version() external pure returns (uint256) {
        return VERSION;
    }

    function allowMarketClosed() public view returns (bool) {
        return base.allowMarketClosed();
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert NoHistory();
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        Quote memory q = _evaluate();
        if (q.status != FeedStatus.OK && !(q.status == FeedStatus.MARKET_CLOSED && allowMarketClosed())) {
            revert FeedUnavailable(q.status);
        }
        uint80 roundId = uint80(q.observedAt);
        return (roundId, q.answer, q.observedAt, q.observedAt, roundId);
    }

    function latestQuote() external view returns (Quote memory) {
        return _evaluate();
    }

    function status() external view returns (FeedStatus) {
        return _evaluate().status;
    }

    function _evaluate() internal view returns (Quote memory q) {
        q = base.latestQuote();
        if (q.status == FeedStatus.NO_DATA) return q;

        (int256 quotePrice, uint256 quoteAt) = _readQuote();
        if (quotePrice <= 0 || quoteAt == 0) {
            return Quote({status: FeedStatus.NO_DATA, answer: 0, observedAt: 0});
        }
        q.answer = SafeCast.toInt256(
            Math.mulDiv(SafeCast.toUint256(q.answer), 10 ** _quoteDecimals, SafeCast.toUint256(quotePrice))
        );
        if (quoteAt < q.observedAt) q.observedAt = SafeCast.toUint64(quoteAt);
        if (
            (q.status == FeedStatus.OK || q.status == FeedStatus.MARKET_CLOSED)
                && block.timestamp - quoteAt > quoteMaxAge
        ) {
            q.status = FeedStatus.STALE;
        }
    }

    function _readQuote() private view returns (int256 price, uint256 updatedAt) {
        try quote.latestRoundData() returns (uint80, int256 answer, uint256, uint256 updated, uint80) {
            if (updated > block.timestamp) return (0, 0);
            return (answer, updated);
        } catch {
            return (0, 0);
        }
    }
}
