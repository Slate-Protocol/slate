// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Which trading session a price source follows.
enum Session {
    /// @dev The exchanges' core session, 09:30 to 16:00 New York time (13:00 on early-close days).
    REGULAR,
    /// @dev Robinhood's 24/5 session: from 20:00 New York time on the previous evening to 20:00 on the trading
    ///      day (17:00 on early-close days).
    EXTENDED
}

interface IMarketCalendar {
    /// @notice If the session is closed at `timestamp`, when the last session ended; 0 if it is open.
    function closedSince(uint256 timestamp, Session session) external view returns (uint256);
}
