// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ERC-8056 Scaled UI Amount, as implemented by Robinhood stock tokens on Robinhood Chain.
/// @dev `uiMultiplier()` switches to `newUIMultiplier()` silently once `block.timestamp >= effectiveAt()`.
///      `UIMultiplierUpdated` is emitted when a change is staged, not when it takes effect.
interface IERC8056 {
    event UIMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier, uint256 effectiveAtTimestamp);

    /// @notice Shares per token, 18 decimals.
    function uiMultiplier() external view returns (uint256);

    /// @notice The staged multiplier; equals `uiMultiplier()` once effective or when nothing is staged.
    function newUIMultiplier() external view returns (uint256);

    /// @notice When `newUIMultiplier()` takes effect.
    function effectiveAt() external view returns (uint256);
}

/// @notice Robinhood's advisory oracle-pause flag. Present on Robinhood Chain mainnet tokens, absent on
///         the older testnet implementation.
interface IOraclePausable {
    function oraclePaused() external view returns (bool);
}

/// @notice Robinhood's earlier rebasing stock tokens on Arbitrum One: `balanceOf` already includes the
///         multiplier, so one token is one share-equivalent.
interface IRebasingMultiplier {
    function multiplier() external view returns (uint256);
}
