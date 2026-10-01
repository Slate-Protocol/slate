// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC8056, IOraclePausable, IRebasingMultiplier} from "../interfaces/IERC8056.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice How a token expresses corporate actions.
enum MultiplierModel {
    /// @dev Plain ERC-20: one token is one share, forever.
    NONE,
    /// @dev ERC-8056 (Robinhood Chain): `balanceOf` is fixed, one token is `uiMultiplier()` shares.
    ERC8056,
    /// @dev Robinhood's rebasing tokens on Arbitrum One: `balanceOf` already includes `multiplier()`,
    ///      so one token is one share-equivalent.
    REBASING
}

/// @notice A token's multiplier state as read at the current block.
struct MultiplierState {
    /// @dev The multiplier in force now, 18 decimals.
    uint256 current;
    /// @dev The staged multiplier. Equals `current` once effective or when nothing is staged.
    uint256 pending;
    /// @dev When `pending` takes (or took) effect. Zero if nothing was ever staged.
    uint64 effectiveAt;
    /// @dev Whether the token exposes Robinhood's `oraclePaused()` flag.
    bool pauseSupported;
    /// @dev The flag's value. Meaningless unless `pauseSupported`.
    bool oraclePaused;
}

/// @title MultiplierLens
/// @notice Reads multiplier and oracle-pause state from Robinhood stock tokens of either model.
library MultiplierLens {
    uint256 internal constant ONE = 1e18;

    /// @dev Gas allowed for the optional `oraclePaused()` probe. Older tokens don't have the function.
    uint256 private constant PAUSE_PROBE_GAS = 30_000;

    function read(address token, MultiplierModel model) internal view returns (MultiplierState memory s) {
        if (model == MultiplierModel.ERC8056) {
            s.current = IERC8056(token).uiMultiplier();
            s.pending = IERC8056(token).newUIMultiplier();
            s.effectiveAt = SafeCast.toUint64(IERC8056(token).effectiveAt());
            (s.pauseSupported, s.oraclePaused) = _probePause(token);
        } else if (model == MultiplierModel.REBASING) {
            s.current = IRebasingMultiplier(token).multiplier();
            s.pending = s.current;
        } else {
            s.current = ONE;
            s.pending = ONE;
        }
    }

    /// @dev Returns `(false, false)` when the token has no `oraclePaused()` or answers with anything but a bool.
    function _probePause(address token) private view returns (bool supported, bool paused) {
        (bool ok, bytes memory data) =
            token.staticcall{gas: PAUSE_PROBE_GAS}(abi.encodeCall(IOraclePausable.oraclePaused, ()));
        if (!ok || data.length != 32) return (false, false);
        uint256 value = abi.decode(data, (uint256));
        if (value > 1) return (false, false);
        return (true, value == 1);
    }
}
