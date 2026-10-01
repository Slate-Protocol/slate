// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title SlateBasket
/// @notice An ERC-20 share in a fixed basket of stock tokens, created and redeemed in kind.
/// @dev Creation and redemption never use a price, so no oracle can be manipulated to mint or redeem
///      wrongly. Each share is a claim on `holdings / totalSupply` of every constituent:
///      - the first creation delivers `unitAmounts[i]` per share (fixed at deployment: equal value at that time);
///      - every later creation delivers each constituent pro rata to current holdings;
///      - redemption pays each constituent out pro rata.
///      Deliveries round up and payouts round down, so the backing per share can only grow. The first creation
///      locks `MINIMUM_SHARES` with the dead address so the supply never returns to zero.
///      Holdings are raw token balances; corporate actions change what each raw token is worth (its
///      multiplier), never how many the basket holds. Pricing is the job of `SlateNavFeed`.
contract SlateBasket is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_SHARES = 1e6;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    IERC20[] private _constituents;
    uint256[] private _unitAmounts;

    event Created(address indexed caller, address indexed to, uint256 shares, uint256[] amounts);
    event Redeemed(address indexed caller, address indexed to, uint256 shares, uint256[] amounts);

    error NoConstituents();
    error LengthMismatch();
    error DuplicateConstituent(address token);
    error ZeroAddress();
    error ZeroAmount();
    error ZeroShares();
    error FirstCreationTooSmall(uint256 minimum);
    error AboveMaximum(uint256 index, uint256 amount, uint256 maximum);
    error BelowMinimum(uint256 index, uint256 amount, uint256 minimum);
    error ShortDelivery(uint256 index, uint256 received, uint256 expected);

    constructor(
        string memory name_,
        string memory symbol_,
        IERC20[] memory constituents_,
        uint256[] memory unitAmounts_
    ) ERC20(name_, symbol_) {
        uint256 n = constituents_.length;
        if (n == 0) revert NoConstituents();
        if (unitAmounts_.length != n) revert LengthMismatch();
        for (uint256 i; i < n; ++i) {
            if (address(constituents_[i]) == address(0)) revert ZeroAddress();
            if (unitAmounts_[i] == 0) revert ZeroAmount();
            for (uint256 j; j < i; ++j) {
                if (constituents_[j] == constituents_[i]) revert DuplicateConstituent(address(constituents_[i]));
            }
        }
        _constituents = constituents_;
        _unitAmounts = unitAmounts_;
    }

    // ------------------------------------------------------------------------------------------------
    // Create and redeem
    // ------------------------------------------------------------------------------------------------

    /// @notice Delivers each constituent and mints `shares` to `to`. Pull approvals first.
    /// @param maxAmounts Per-constituent ceilings on what may be taken, in raw token units.
    function create(uint256 shares, address to, uint256[] calldata maxAmounts)
        external
        nonReentrant
        returns (uint256[] memory amounts)
    {
        if (shares == 0) revert ZeroShares();
        if (to == address(0)) revert ZeroAddress();
        if (maxAmounts.length != _constituents.length) revert LengthMismatch();
        uint256 supply = totalSupply();
        if (supply == 0 && shares <= MINIMUM_SHARES) revert FirstCreationTooSmall(MINIMUM_SHARES + 1);

        amounts = quoteCreate(shares);
        for (uint256 i; i < amounts.length; ++i) {
            if (amounts[i] > maxAmounts[i]) revert AboveMaximum(i, amounts[i], maxAmounts[i]);
            IERC20 token = _constituents[i];
            uint256 before = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), amounts[i]);
            uint256 received = token.balanceOf(address(this)) - before;
            if (received < amounts[i]) revert ShortDelivery(i, received, amounts[i]);
        }

        if (supply == 0) {
            _mint(DEAD, MINIMUM_SHARES);
            _mint(to, shares - MINIMUM_SHARES);
        } else {
            _mint(to, shares);
        }
        emit Created(msg.sender, to, shares, amounts);
    }

    /// @notice Burns `shares` from the caller and pays out each constituent pro rata to `to`.
    /// @param minAmounts Per-constituent floors on what must be paid, in raw token units.
    function redeem(uint256 shares, address to, uint256[] calldata minAmounts)
        external
        nonReentrant
        returns (uint256[] memory amounts)
    {
        if (shares == 0) revert ZeroShares();
        if (to == address(0)) revert ZeroAddress();
        if (minAmounts.length != _constituents.length) revert LengthMismatch();

        amounts = quoteRedeem(shares);
        _burn(msg.sender, shares);
        for (uint256 i; i < amounts.length; ++i) {
            if (amounts[i] < minAmounts[i]) revert BelowMinimum(i, amounts[i], minAmounts[i]);
            _constituents[i].safeTransfer(to, amounts[i]);
        }
        emit Redeemed(msg.sender, to, shares, amounts);
    }

    // ------------------------------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------------------------------

    /// @notice What creating `shares` would take, rounded up.
    function quoteCreate(uint256 shares) public view returns (uint256[] memory amounts) {
        uint256 n = _constituents.length;
        amounts = new uint256[](n);
        uint256 supply = totalSupply();
        for (uint256 i; i < n; ++i) {
            amounts[i] = supply == 0
                ? Math.mulDiv(_unitAmounts[i], shares, 1e18, Math.Rounding.Ceil)
                : Math.mulDiv(_constituents[i].balanceOf(address(this)), shares, supply, Math.Rounding.Ceil);
        }
    }

    /// @notice What redeeming `shares` would pay, rounded down.
    function quoteRedeem(uint256 shares) public view returns (uint256[] memory amounts) {
        uint256 n = _constituents.length;
        amounts = new uint256[](n);
        uint256 supply = totalSupply();
        if (supply == 0) return amounts;
        for (uint256 i; i < n; ++i) {
            amounts[i] = Math.mulDiv(_constituents[i].balanceOf(address(this)), shares, supply);
        }
    }

    function constituents() external view returns (IERC20[] memory) {
        return _constituents;
    }

    function constituentCount() external view returns (uint256) {
        return _constituents.length;
    }

    function constituent(uint256 i) external view returns (IERC20) {
        return _constituents[i];
    }

    /// @notice Raw token amounts per 1e18 shares for the very first creation.
    function unitAmounts() external view returns (uint256[] memory) {
        return _unitAmounts;
    }

    /// @notice Raw balances of every constituent held by the basket.
    function holdings() external view returns (uint256[] memory amounts) {
        uint256 n = _constituents.length;
        amounts = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            amounts[i] = _constituents[i].balanceOf(address(this));
        }
    }
}
