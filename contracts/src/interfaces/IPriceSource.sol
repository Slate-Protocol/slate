// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice What a source's price means.
enum PriceKind {
    /// @dev Price of one underlying share. A multiplier still has to be applied for ERC-8056 tokens.
    RAW_UNDERLYING,
    /// @dev Price of one token with the multiplier already included (Robinhood's Chainlink feeds).
    TOTAL_RETURN
}

struct Observation {
    int256 price;
    uint8 decimals;
    uint64 observedAt;
}

/// @notice A source of observed prices, keyed by feed id. Single-feed sources ignore `feedId`.
interface IPriceSource {
    /// @notice The kind of price this source reports for `feedId`. Must never change for a given feed.
    function kind(bytes32 feedId) external view returns (PriceKind);

    /// @notice The latest observation for `feedId`. `observedAt == 0` means no data.
    function observe(bytes32 feedId) external view returns (Observation memory);
}
