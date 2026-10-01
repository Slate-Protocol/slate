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
///      Lab exists to show. Serves `IPriceSource` for `SlateFeed` and `AggregatorV3Interface` for the naive feed.
contract LabSplitSource is IPriceSource, AggregatorV3Interface {
    uint256 private constant ONE = 1e18;

    IPriceSource public immutable inner;
    bytes32 public immutable innerFeedId;
    SlateLabStock public immutable lab;

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

    function observe(bytes32) public view returns (Observation memory o) {
        o = inner.observe(innerFeedId);
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
