// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IPriceSource, Observation, PriceKind} from "../interfaces/IPriceSource.sol";
import {SlateLabStock} from "./SlateLabStock.sol";

/// @title LabSplitSource
/// @notice LAB ONLY. The share price of a Lab token's imaginary underlying: a real share price (TSLA) divided by
///         the Lab multiplier that was in force when that price was observed.
/// @dev A real split moves two things: the token's multiplier switches at `effectiveAt`, and the share price drops
///      at the next print. The Lab's input is a real TSLA price, which does not split when a Lab action is
///      scheduled, so this source makes it split: a price observed after the switch is divided by the new
///      multiplier, one observed before by the old. The token price, share price × multiplier at observation,
///      therefore stays the TSLA price through any number of Lab splits, exactly as a token's value does through a
///      real split. What changes is the window between the switch and the next print, where a feed that
///      multiplies the last share price by the multiplier *now* is wrong by the split ratio. That is the bug the
///      Lab exists to show. On a real split the next print comes at the next open, hours later; the Lab models
///      that gap by freezing the last pre-split print when an action is scheduled and serving it until
///      `PRINT_DELAY` after the switch. Serves `IPriceSource` for `SlateFeed` and `AggregatorV3Interface` for the
///      naive feed.
contract LabSplitSource is IPriceSource, AggregatorV3Interface {
    uint256 private constant ONE = 1e18;
    /// @notice How long after the switch the first post-split print takes to arrive.
    uint256 public constant PRINT_DELAY = 3 minutes;

    IPriceSource public immutable inner;
    bytes32 public immutable innerFeedId;
    SlateLabStock public immutable lab;
    Observation private _frozen;

    error OnlyLab();

    constructor(IPriceSource inner_, bytes32 innerFeedId_, SlateLabStock lab_) {
        inner = inner_;
        innerFeedId = innerFeedId_;
        lab = lab_;
    }

    // ------------------------------------------------------------------------------------------------
    // IPriceSource
    // ------------------------------------------------------------------------------------------------

    function kind(bytes32) external pure returns (PriceKind) {
        return PriceKind.RAW_UNDERLYING;
    }

    /// @notice Called by the Lab token when an action is scheduled: keeps the last pre-split print.
    function freeze() external {
        if (msg.sender != address(lab)) revert OnlyLab();
        _frozen = inner.observe(innerFeedId);
    }

    function observe(bytes32) public view returns (Observation memory o) {
        uint256 scheduledAt = lab.lastScheduledAt();
        bool waitingForPrint = _frozen.observedAt != 0 && scheduledAt != 0 && block.timestamp >= scheduledAt
            && block.timestamp < lab.effectiveAt() + PRINT_DELAY;
        o = waitingForPrint ? _frozen : inner.observe(innerFeedId);
        if (o.observedAt == 0 || o.price <= 0) return o;
        // forge-lint: disable-next-line(unsafe-typecast)
        o.price = o.price * int256(ONE) / int256(lab.multiplierAt(o.observedAt));
    }

    // ------------------------------------------------------------------------------------------------
    // AggregatorV3Interface (the naive feed's input)
    // ------------------------------------------------------------------------------------------------

    function decimals() external view returns (uint8) {
        return inner.observe(innerFeedId).decimals;
    }

    function description() external pure returns (string memory) {
        return "LAB ONLY: underlying share price, split with the Lab token";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("no history");
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        Observation memory o = observe(bytes32(0));
        require(o.price > 0, "no data");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint80 round = uint80(o.observedAt);
        return (round, o.price, o.observedAt, o.observedAt, round);
    }
}
