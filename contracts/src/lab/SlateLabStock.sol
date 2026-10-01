// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC8056, IOraclePausable} from "../interfaces/IERC8056.sol";

interface ILabSplitSource {
    function freeze() external;
}
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SlateLabStock
/// @notice A Slate test token for the Corporate Action Lab. Not a Robinhood product and worth nothing.
/// @dev Reproduces the ERC-8056 multiplier behaviour of Robinhood's stock tokens (verified implementation
///      0xb35490d6f9163DE4F80d88dc75c3516eb64C5aE2 on Robinhood Chain): staging stores the current and the new
///      multiplier, and `uiMultiplier()` switches silently by timestamp. Unlike Robinhood's, anyone may schedule a
///      corporate action, within bounds and a cooldown, so anyone can watch what a split does to a price feed.
contract SlateLabStock is ERC20, IERC8056, IOraclePausable {
    uint256 private constant ONE = 1e18;
    /// @notice Multipliers stay within 1/100x and 100x of the starting 1.0.
    uint256 public constant MIN_MULTIPLIER = 0.01e18;
    uint256 public constant MAX_MULTIPLIER = 100e18;
    /// @notice The latest a corporate action may be scheduled for.
    uint256 public constant MAX_LEAD_TIME = 1 days;
    /// @notice Time between corporate actions.
    uint256 public constant COOLDOWN = 10 minutes;
    uint256 public constant FAUCET_AMOUNT = 100e18;
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    uint256 private _multiplier;
    uint256 private _newMultiplier;
    uint256 private _effectiveAt;
    uint256 public lastScheduledAt;
    /// @notice Set once at deployment: the source that splits this token's underlying share price.
    address public splitSource;
    address private immutable _admin;
    mapping(address account => uint256) public lastFaucetAt;

    event Faucet(address indexed to, uint256 amount);

    error MultiplierOutOfRange(uint256 multiplier);
    error EffectiveTimeOutOfRange(uint256 effectiveAt);
    error Cooldown(uint256 nextAt);
    error AlreadySet();

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _admin = msg.sender;
    }

    /// @notice Wires the split source once, at deployment.
    function setSplitSource(address source) external {
        if (msg.sender != _admin || splitSource != address(0)) revert AlreadySet();
        splitSource = source;
    }

    // ------------------------------------------------------------------------------------------------
    // ERC-8056
    // ------------------------------------------------------------------------------------------------

    function uiMultiplier() public view returns (uint256) {
        return multiplierAt(block.timestamp);
    }

    function newUIMultiplier() external view returns (uint256) {
        return _newMultiplier == 0 ? ONE : _newMultiplier;
    }

    function effectiveAt() external view returns (uint256) {
        return _effectiveAt;
    }

    /// @notice The multiplier in force at `timestamp`, for the most recent scheduled action. Robinhood's tokens have
    ///         no such view; the Lab needs it to simulate the underlying share price splitting with the token.
    function multiplierAt(uint256 timestamp) public view returns (uint256) {
        if (timestamp >= _effectiveAt && _newMultiplier != 0) return _newMultiplier;
        return _multiplier == 0 ? ONE : _multiplier;
    }

    /// @notice Never paused: the Lab is about multipliers, not pauses.
    function oraclePaused() external pure returns (bool) {
        return false;
    }

    // ------------------------------------------------------------------------------------------------
    // Lab controls
    // ------------------------------------------------------------------------------------------------

    /// @notice Schedules a new multiplier, as Robinhood's `updateMultiplier(uint256,uint256)` does. Anyone may
    ///         call it, once per `COOLDOWN`. A 4:1 split from 1.0 is `newMultiplier = 4e18`.
    function scheduleCorporateAction(uint256 newMultiplier, uint256 effectiveAt_) external {
        if (newMultiplier < MIN_MULTIPLIER || newMultiplier > MAX_MULTIPLIER) {
            revert MultiplierOutOfRange(newMultiplier);
        }
        if (effectiveAt_ < block.timestamp || effectiveAt_ > block.timestamp + MAX_LEAD_TIME) {
            revert EffectiveTimeOutOfRange(effectiveAt_);
        }
        if (lastScheduledAt != 0 && block.timestamp < lastScheduledAt + COOLDOWN) {
            revert Cooldown(lastScheduledAt + COOLDOWN);
        }
        lastScheduledAt = block.timestamp;
        uint256 oldMultiplier = uiMultiplier();
        _multiplier = oldMultiplier;
        _newMultiplier = newMultiplier;
        _effectiveAt = effectiveAt_;
        if (splitSource != address(0)) ILabSplitSource(splitSource).freeze();
        emit UIMultiplierUpdated(oldMultiplier, newMultiplier, effectiveAt_);
    }

    /// @notice Sends `FAUCET_AMOUNT` to the caller, once per `FAUCET_COOLDOWN`.
    function faucet() external {
        uint256 last = lastFaucetAt[msg.sender];
        if (last != 0 && block.timestamp < last + FAUCET_COOLDOWN) revert Cooldown(last + FAUCET_COOLDOWN);
        lastFaucetAt[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit Faucet(msg.sender, FAUCET_AMOUNT);
    }
}
