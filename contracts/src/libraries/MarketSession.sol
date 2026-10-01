// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MarketSession
/// @notice The weekly window in which US equities are certainly not printing.
/// @dev Robinhood's stock tokens price over a 24/5 session: Sunday 20:00 to Friday 20:00 New York time.
///      In UTC that close is Saturday 00:00 (EDT) or 01:00 (EST), and the reopen is Monday 00:00 or 01:00.
///      The closed window used here is Saturday 00:00 UTC to Monday 00:00 UTC, which is closed under both
///      offsets. Exchange holidays are not modelled: a holiday shows as stale, which fails closed.
library MarketSession {
    uint256 private constant DAY = 1 days;
    uint256 private constant WEEK = 7 days;
    /// @dev 1970-01-01 was a Thursday, so Saturday 00:00 UTC is 2 days into each epoch-aligned week.
    uint256 private constant SATURDAY_OFFSET = 2 days;
    uint256 private constant CLOSED_LENGTH = 2 days;

    /// @notice If `timestamp` falls in the weekend closed window, returns when that window began; else 0.
    function closedSince(uint256 timestamp) internal pure returns (uint256) {
        if (timestamp < SATURDAY_OFFSET) return 0;
        uint256 weekStart = timestamp - ((timestamp - SATURDAY_OFFSET) % WEEK);
        return timestamp < weekStart + CLOSED_LENGTH ? weekStart : 0;
    }
}
