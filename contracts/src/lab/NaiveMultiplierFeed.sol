// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IERC8056} from "../interfaces/IERC8056.sol";

/// @title NaiveMultiplierFeed
/// @notice LAB ONLY: what not to do. Multiplies a raw share price by the token's multiplier *now*.
/// @dev Exists so the Corporate Action Lab can show the failure side by side with `SlateFeed`. When a split
///      takes effect, the multiplier switches at once but the share price on the feed is still the pre-split
///      print, so this feed jumps by the split ratio until the next price arrives. Never use it to price
///      anything.
contract NaiveMultiplierFeed is AggregatorV3Interface {
    AggregatorV3Interface public immutable rawFeed;
    IERC8056 public immutable token;
    uint8 private immutable _decimals;

    constructor(AggregatorV3Interface rawFeed_, IERC8056 token_) {
        rawFeed = rawFeed_;
        token = token_;
        _decimals = rawFeed_.decimals();
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "LAB ONLY: naive raw x current multiplier";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("no history");
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = rawFeed.latestRoundData();
        answer = answer * int256(token.uiMultiplier()) / 1e18;
    }
}
