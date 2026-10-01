// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceSource, Observation, PriceKind} from "../interfaces/IPriceSource.sol";
import {FeedStatus, ISlateFeed, Quote} from "../interfaces/ISlateFeed.sol";
import {MarketSession} from "../libraries/MarketSession.sol";
import {MultiplierLens, MultiplierModel, MultiplierState} from "../libraries/MultiplierLens.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title SlateFeed
/// @notice A multiplier-correct, fail-closed price feed for one stock token, compatible with Chainlink's
///         `AggregatorV3Interface`. The answer is the price of one token, in USD with 8 decimals.
///
/// @dev The multiplier problem. ERC-8056 tokens keep `balanceOf` fixed and express dividends and splits
///      through `uiMultiplier()`. One token is worth `sharePrice * multiplier`. The multiplier changes
///      silently: the change is staged with an event, and `uiMultiplier()` switches by `block.timestamp` at
///      `effectiveAt()`. A share price observed before the switch must be paired with the multiplier that
///      was in force when it was observed, not the multiplier in force now.
///
///      This feed never asks "what is the multiplier now?". It asks "what multiplier was in force when the
///      price was observed?":
///      - observed at or after `effectiveAt`, or the switch hasn't happened: the token answers directly;
///      - observed before a switch that has since happened: the pre-switch multiplier is no longer
///        readable from the token, so `poke()` records it while it still is. With that record the price is
///        exact; without it the feed reports `STRADDLE` until a fresh price arrives.
///      A large change (a split) additionally holds the feed in `CORPORATE_ACTION` until a price observed
///      `corporateActionGrace` after the switch, because the market's own prints around a split open are
///      unreliable even when the arithmetic is exact.
///
///      Price kinds. A `RAW_UNDERLYING` source quotes one share, so the multiplier is applied here. A
///      `TOTAL_RETURN` source (Robinhood's Chainlink feeds) already includes it, so it is never applied
///      again. For `REBASING` tokens one token is one share-equivalent, so it is never applied either.
contract SlateFeed is ISlateFeed {
    uint8 public constant DECIMALS = 8;
    uint256 public constant VERSION = 1;
    uint256 private constant ONE = 1e18;
    uint256 private constant BPS = 10_000;
    uint8 private constant MAX_SOURCE_DECIMALS = 36;

    struct Config {
        address token;
        MultiplierModel model;
        IPriceSource source;
        bytes32 feedId;
        /// @dev Maximum age of a usable price, in seconds.
        uint32 maxAge;
        /// @dev How long after a large multiplier switch prices are refused, in seconds.
        uint32 corporateActionGrace;
        /// @dev A multiplier change above this many basis points counts as large.
        uint16 largeChangeBps;
        /// @dev Whether `latestRoundData()` serves `MARKET_CLOSED` prices.
        bool allowMarketClosed;
        string description;
    }

    /// @notice The multiplier switch most recently recorded by `poke()`.
    struct Snapshot {
        uint96 oldMultiplier;
        uint96 newMultiplier;
        uint64 effectiveAt;
    }

    address public immutable token;
    MultiplierModel public immutable model;
    IPriceSource public immutable source;
    bytes32 public immutable feedId;
    PriceKind public immutable priceKind;
    /// @notice Whether this feed multiplies the source price by the token's multiplier.
    bool public immutable multiplierApplied;
    uint32 public immutable maxAge;
    uint32 public immutable corporateActionGrace;
    uint16 public immutable largeChangeBps;
    bool public immutable allowMarketClosed;

    Snapshot public snapshot;
    string private _description;

    event MultiplierSnapshot(uint256 oldMultiplier, uint256 newMultiplier, uint64 effectiveAt);

    error ZeroAddress();
    error ZeroMaxAge();
    error UnsupportedCombination();

    constructor(Config memory config) {
        if (config.token == address(0) || address(config.source) == address(0)) revert ZeroAddress();
        if (config.maxAge == 0) revert ZeroMaxAge();
        PriceKind kind_ = config.source.kind(config.feedId);
        if (kind_ == PriceKind.TOTAL_RETURN && config.model == MultiplierModel.REBASING) {
            revert UnsupportedCombination();
        }
        token = config.token;
        model = config.model;
        source = config.source;
        feedId = config.feedId;
        priceKind = kind_;
        multiplierApplied = kind_ == PriceKind.RAW_UNDERLYING && config.model == MultiplierModel.ERC8056;
        maxAge = config.maxAge;
        corporateActionGrace = config.corporateActionGrace;
        largeChangeBps = config.largeChangeBps;
        allowMarketClosed = config.allowMarketClosed;
        _description = config.description;
    }

    // ------------------------------------------------------------------------------------------------
    // AggregatorV3Interface
    // ------------------------------------------------------------------------------------------------

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function version() external pure returns (uint256) {
        return VERSION;
    }

    /// @dev Slate feeds keep no history. Round ids are observation timestamps.
    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert NoHistory();
    }

    /// @notice The latest usable price. Reverts with `FeedUnavailable` otherwise.
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        (Quote memory q,,) = _evaluate();
        if (q.status != FeedStatus.OK && !(q.status == FeedStatus.MARKET_CLOSED && allowMarketClosed)) {
            revert FeedUnavailable(q.status);
        }
        uint80 roundId = uint80(q.observedAt);
        return (roundId, q.answer, q.observedAt, q.observedAt, roundId);
    }

    // ------------------------------------------------------------------------------------------------
    // ISlateFeed
    // ------------------------------------------------------------------------------------------------

    function latestQuote() external view returns (Quote memory q) {
        (q,,) = _evaluate();
    }

    function status() external view returns (FeedStatus) {
        (Quote memory q,,) = _evaluate();
        return q.status;
    }

    /// @notice The quote together with the per-share price and the multiplier paired with it.
    function latestDetail() external view returns (Quote memory quote, int256 sharePrice, uint256 multiplier) {
        return _evaluate();
    }

    /// @notice Records a staged multiplier switch while the pre-switch multiplier is still readable.
    /// @dev Permissionless and idempotent; it only copies token state. Relayers call it alongside price
    ///      updates. Returns whether a pending switch was recorded.
    function poke() external returns (bool) {
        if (model != MultiplierModel.ERC8056) return false;
        MultiplierState memory s = MultiplierLens.read(token, model);
        if (block.timestamp >= s.effectiveAt || s.pending == s.current) return false;
        snapshot = Snapshot({
            oldMultiplier: SafeCast.toUint96(s.current),
            newMultiplier: SafeCast.toUint96(s.pending),
            effectiveAt: s.effectiveAt
        });
        emit MultiplierSnapshot(s.current, s.pending, s.effectiveAt);
        return true;
    }

    // ------------------------------------------------------------------------------------------------
    // Evaluation
    // ------------------------------------------------------------------------------------------------

    function _evaluate() internal view returns (Quote memory q, int256 sharePrice, uint256 multiplier) {
        Observation memory o = source.observe(feedId);
        if (o.observedAt == 0 || o.price <= 0 || o.decimals > MAX_SOURCE_DECIMALS) {
            q.status = FeedStatus.NO_DATA;
            return (q, 0, 0);
        }
        uint256 observedAt = Math.min(o.observedAt, block.timestamp);
        uint256 price = _normalize(uint256(o.price), o.decimals);

        MultiplierState memory s = MultiplierLens.read(token, model);
        bool known;
        (multiplier, known) = _multiplierAt(s, observedAt);
        if (multiplier == 0) {
            q.status = FeedStatus.NO_DATA;
            return (q, 0, 0);
        }

        if (priceKind == PriceKind.RAW_UNDERLYING) {
            sharePrice = SafeCast.toInt256(price);
            q.answer = multiplierApplied ? SafeCast.toInt256(Math.mulDiv(price, multiplier, ONE)) : sharePrice;
        } else {
            q.answer = SafeCast.toInt256(price);
            sharePrice =
                model == MultiplierModel.ERC8056 ? SafeCast.toInt256(Math.mulDiv(price, ONE, multiplier)) : q.answer;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        q.observedAt = uint64(observedAt);
        q.status = _status(s, observedAt, known);
    }

    function _status(MultiplierState memory s, uint256 observedAt, bool known) internal view returns (FeedStatus) {
        if (s.pauseSupported && s.oraclePaused) return FeedStatus.ORACLE_PAUSED;

        if (multiplierApplied) {
            uint256 e = s.effectiveAt;
            if (e != 0 && block.timestamp >= e && observedAt < e + corporateActionGrace) {
                Snapshot memory snap = snapshot;
                if (snap.effectiveAt == e) {
                    if (_changeBps(snap.oldMultiplier, s.current) > largeChangeBps) {
                        return FeedStatus.CORPORATE_ACTION;
                    }
                } else {
                    return observedAt < e ? FeedStatus.STRADDLE : FeedStatus.CORPORATE_ACTION;
                }
            }
            if (!known) return FeedStatus.STRADDLE;
        }

        if (block.timestamp - observedAt <= maxAge) return FeedStatus.OK;
        uint256 closedSince = MarketSession.closedSince(block.timestamp);
        if (closedSince != 0 && observedAt + maxAge >= closedSince) return FeedStatus.MARKET_CLOSED;
        return FeedStatus.STALE;
    }

    /// @dev The multiplier in force at `observedAt`, and whether it is known.
    function _multiplierAt(MultiplierState memory s, uint256 observedAt)
        internal
        view
        returns (uint256 multiplier, bool known)
    {
        uint256 e = s.effectiveAt;
        if (model != MultiplierModel.ERC8056 || e == 0 || observedAt >= e || block.timestamp < e) {
            return (s.current, true);
        }
        Snapshot memory snap = snapshot;
        if (snap.effectiveAt == e) return (snap.oldMultiplier, true);
        return (s.current, false);
    }

    function _changeBps(uint256 from, uint256 to) private pure returns (uint256) {
        uint256 diff = to > from ? to - from : from - to;
        return Math.mulDiv(diff, BPS, from);
    }

    function _normalize(uint256 price, uint8 sourceDecimals) private pure returns (uint256) {
        if (sourceDecimals == DECIMALS) return price;
        if (sourceDecimals > DECIMALS) return price / 10 ** (sourceDecimals - DECIMALS);
        return price * 10 ** (DECIMALS - sourceDecimals);
    }
}
