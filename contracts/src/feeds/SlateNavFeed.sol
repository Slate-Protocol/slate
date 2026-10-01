// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SlateBasket} from "../basket/SlateBasket.sol";
import {FeedStatus, ISlateFeed, Quote} from "../interfaces/ISlateFeed.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface ITokenFeed {
    function token() external view returns (address);
}

/// @title SlateNavFeed
/// @notice The NAV of one basket share as a drop-in `AggregatorV3Interface` feed, in USD with 8 decimals.
/// @dev NAV per share = Σ holdingᵢ × priceᵢ / totalSupply, where priceᵢ is the token price from that
///      constituent's Slate feed (multiplier already applied). The status is the worst of the constituents'
///      and the observation time is the oldest, so one stale or paused stock makes the whole NAV unusable.
///      Wrap it in `SlateQuotedFeed` with the USDG/USD feed to quote it in USDG.
contract SlateNavFeed is ISlateFeed {
    uint8 public constant DECIMALS = 8;
    uint256 public constant VERSION = 1;
    uint256 private constant SHARE = 1e18;

    SlateBasket public immutable basket;
    bool public immutable allowMarketClosed;
    ISlateFeed[] private _feeds;
    uint8[] private _tokenDecimals;
    string private _description;

    error LengthMismatch();
    error FeedTokenMismatch(uint256 index, address feedToken, address constituent);

    constructor(SlateBasket basket_, ISlateFeed[] memory feeds_, bool allowMarketClosed_, string memory description_) {
        uint256 n = basket_.constituentCount();
        if (feeds_.length != n) revert LengthMismatch();
        for (uint256 i; i < n; ++i) {
            address constituent = address(basket_.constituent(i));
            address feedToken = ITokenFeed(address(feeds_[i])).token();
            if (feedToken != constituent) revert FeedTokenMismatch(i, feedToken, constituent);
            _tokenDecimals.push(IERC20Metadata(constituent).decimals());
        }
        basket = basket_;
        _feeds = feeds_;
        allowMarketClosed = allowMarketClosed_;
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

    function feeds() external view returns (ISlateFeed[] memory) {
        return _feeds;
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert NoHistory();
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        Quote memory q = _evaluate();
        if (q.status != FeedStatus.OK && !(q.status == FeedStatus.MARKET_CLOSED && allowMarketClosed)) {
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
        uint256 supply = basket.totalSupply();
        if (supply == 0) {
            q.status = FeedStatus.NO_DATA;
            return q;
        }
        uint256[] memory holdings = basket.holdings();
        uint256 value; // USD, 8 decimals, for the whole basket
        uint64 oldest = type(uint64).max;
        FeedStatus worst = FeedStatus.OK;

        for (uint256 i; i < holdings.length; ++i) {
            Quote memory c = _feeds[i].latestQuote();
            if (uint8(c.status) > uint8(worst)) worst = c.status;
            if (c.status == FeedStatus.NO_DATA || c.answer <= 0) {
                q.status = FeedStatus.NO_DATA;
                return q;
            }
            if (c.observedAt < oldest) oldest = c.observedAt;
            value += Math.mulDiv(holdings[i], SafeCast.toUint256(c.answer), 10 ** _tokenDecimals[i]);
        }

        q.status = worst;
        q.answer = SafeCast.toInt256(Math.mulDiv(value, SHARE, supply));
        q.observedAt = oldest;
    }
}
