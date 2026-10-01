// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Reproduces the multiplier logic of Robinhood's verified `ERC20ScaledUIUpgradeable`
///      (implementation 0xb35490d6f9163DE4F80d88dc75c3516eb64C5aE2 on Robinhood Chain): staging stores the
///      current multiplier and the new one, and `uiMultiplier()` switches by timestamp.
abstract contract MockStockTokenBase is ERC20 {
    uint256 private constant DENOMINATOR = 1e18;
    uint256 private _multiplier;
    uint256 private _newMultiplier;
    uint256 private _effectiveAt;

    event UIMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier, uint256 effectiveAtTimestamp);

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev `updateMultiplier(uint256)`: effective immediately.
    function updateMultiplier(uint256 newMultiplier) external {
        _stage(newMultiplier, block.timestamp);
    }

    /// @dev `updateMultiplier(uint256,uint256)`: scheduled.
    function updateMultiplier(uint256 newMultiplier, uint256 effectiveAt_) external {
        _stage(newMultiplier, effectiveAt_);
    }

    function uiMultiplier() public view returns (uint256) {
        if (block.timestamp >= _effectiveAt && _newMultiplier != 0) return _newMultiplier;
        return _multiplier == 0 ? DENOMINATOR : _multiplier;
    }

    function newUIMultiplier() external view returns (uint256) {
        return _newMultiplier == 0 ? DENOMINATOR : _newMultiplier;
    }

    function effectiveAt() external view returns (uint256) {
        return _effectiveAt;
    }

    function _stage(uint256 newMultiplier, uint256 effectiveAt_) private {
        require(newMultiplier > 0, "New multiplier must be greater than 0");
        require(effectiveAt_ >= block.timestamp, "Effective time must not be in the past");
        uint256 oldMultiplier = uiMultiplier();
        _multiplier = oldMultiplier;
        _newMultiplier = newMultiplier;
        _effectiveAt = effectiveAt_;
        emit UIMultiplierUpdated(oldMultiplier, newMultiplier, effectiveAt_);
    }
}

/// @dev Robinhood Chain mainnet style: has `oraclePaused()`.
contract MockStockToken is MockStockTokenBase {
    bool public oraclePaused;

    constructor(string memory name_, string memory symbol_) MockStockTokenBase(name_, symbol_) {}

    function setOraclePaused(bool paused) external {
        oraclePaused = paused;
    }
}

/// @dev Robinhood Chain testnet style: no `oraclePaused()` at all.
contract MockLegacyStockToken is MockStockTokenBase {
    constructor(string memory name_, string memory symbol_) MockStockTokenBase(name_, symbol_) {}
}

/// @dev Robinhood's rebasing Arbitrum One tokens expose `multiplier()`.
contract MockRebasingToken {
    uint256 public multiplier = 1e18;

    function setMultiplier(uint256 m) external {
        multiplier = m;
    }
}
