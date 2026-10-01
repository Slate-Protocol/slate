// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IPriceSource, Observation, PriceKind} from "../interfaces/IPriceSource.sol";

/// @title ChainlinkSource
/// @notice Adapts one Chainlink aggregator to `IPriceSource`, with its price kind fixed at deployment.
/// @dev Robinhood's feeds on Robinhood Chain are `TOTAL_RETURN` (the multiplier is already in the answer).
///      Chainlink's US-equity feeds on Arbitrum One are `RAW_UNDERLYING`. Declaring the wrong kind is the
///      double-count bug, which is why `SlateFeedFactory` can calibrate a new feed against a reference.
contract ChainlinkSource is IPriceSource {
    AggregatorV3Interface public immutable aggregator;
    PriceKind public immutable priceKind;
    uint8 public immutable decimals;

    error ZeroAddress();

    constructor(AggregatorV3Interface aggregator_, PriceKind kind_) {
        if (address(aggregator_) == address(0)) revert ZeroAddress();
        aggregator = aggregator_;
        priceKind = kind_;
        decimals = aggregator_.decimals();
    }

    /// @inheritdoc IPriceSource
    function kind(bytes32) external view returns (PriceKind) {
        return priceKind;
    }

    /// @inheritdoc IPriceSource
    /// @dev A reverting aggregator reads as "no data" rather than bubbling the revert.
    function observe(bytes32) external view returns (Observation memory obs) {
        try aggregator.latestRoundData() returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80) {
            if (updatedAt > type(uint64).max) return obs;
            // forge-lint: disable-next-line(unsafe-typecast)
            obs = Observation({price: answer, decimals: decimals, observedAt: uint64(updatedAt)});
        } catch {}
    }
}
