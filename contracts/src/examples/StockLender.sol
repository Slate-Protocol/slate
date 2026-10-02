// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title StockLender
/// @notice A minimal over-collateralised lending market for stock tokens. It exists to show the integration path a
///         third party would take: collateral is priced through any Chainlink-compatible feed, such as a SlateFeed,
///         using nothing but `AggregatorV3Interface.latestRoundData()`.
/// @dev No Slate-specific code and no privileged access. A feed that reverts (a SlateFeed refusing to price during
///      a split, a closed market past this lender's bound, a stale or paused oracle) means "no price", and with no
///      price the lender blocks borrowing, withdrawing collateral against debt and liquidating. Repaying and
///      depositing always work.
///
///      A proof, not a product: one loan asset valued at $1 (a dollar stablecoin), no interest, isolated positions
///      per collateral token, markets listed by the owner, and bad debt is not socialised across suppliers.
contract StockLender is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Market {
        AggregatorV3Interface feed;
        uint8 feedDecimals;
        uint8 tokenDecimals;
        /// @dev Borrow up to this share of the collateral's value.
        uint16 ltvBps;
        /// @dev Liquidatable once the debt exceeds this share of the collateral's value.
        uint16 liquidationBps;
        /// @dev The liquidator's discount on seized collateral.
        uint16 bonusBps;
        /// @dev This lender's own bound on the feed's `updatedAt`. A SlateFeed already refuses a price that is stale
        ///      while its market is open, so this only caps how long a closed-market price is trusted.
        uint32 maxAge;
        bool listed;
    }

    struct Position {
        uint256 collateral;
        uint256 debt;
    }

    uint256 internal constant BPS = 10_000;

    IERC20 public immutable loanAsset;
    uint8 public immutable loanDecimals;

    mapping(address token => Market) public markets;
    address[] public listedTokens;
    mapping(address token => mapping(address account => Position)) public positions;
    mapping(address token => uint256) public totalCollateral;
    mapping(address supplier => uint256) public supplied;
    uint256 public totalSupplied;
    uint256 public totalDebt;

    event MarketListed(
        address indexed token, address feed, uint16 ltvBps, uint16 liquidationBps, uint16 bonusBps, uint32 maxAge
    );
    event Supplied(address indexed supplier, uint256 amount);
    event SupplyWithdrawn(address indexed supplier, uint256 amount);
    event Deposited(address indexed token, address indexed account, uint256 amount);
    event Withdrawn(address indexed token, address indexed account, uint256 amount);
    event Borrowed(address indexed token, address indexed account, uint256 amount, uint256 price, uint256 updatedAt);
    event Repaid(address indexed token, address indexed account, address payer, uint256 amount);
    event Liquidated(
        address indexed token,
        address indexed account,
        address liquidator,
        uint256 repaid,
        uint256 seized,
        uint256 price,
        uint256 updatedAt
    );

    error NotListed(address token);
    error AlreadyListed(address token);
    error BadParameters();
    error ZeroAmount();
    error PriceUnavailable(address token);
    error ExceedsLimit(uint256 debt, uint256 limit);
    error InsufficientCollateral(uint256 requested, uint256 available);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error InsufficientSupply(uint256 requested, uint256 available);
    error Healthy(uint256 debt, uint256 threshold);

    constructor(IERC20 loanAsset_, address owner_) Ownable(owner_) {
        loanAsset = loanAsset_;
        loanDecimals = IERC20Metadata(address(loanAsset_)).decimals();
        if (loanDecimals > 18) revert BadParameters();
    }

    // ------------------------------------------------------------------------------------------------
    // Markets
    // ------------------------------------------------------------------------------------------------

    function listMarket(
        address token,
        AggregatorV3Interface feed,
        uint16 ltvBps,
        uint16 liquidationBps,
        uint16 bonusBps,
        uint32 maxAge
    ) external onlyOwner {
        if (markets[token].listed) revert AlreadyListed(token);
        // Liquidating at the threshold must be able to cover the debt plus the bonus from the collateral.
        if (
            token == address(loanAsset) || address(feed) == address(0) || ltvBps == 0 || ltvBps >= liquidationBps
                || uint256(liquidationBps) * (BPS + bonusBps) > BPS * BPS || maxAge == 0
        ) revert BadParameters();
        uint8 feedDecimals = feed.decimals();
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        if (feedDecimals > 18 || tokenDecimals > 18) revert BadParameters();
        markets[token] = Market({
            feed: feed,
            feedDecimals: feedDecimals,
            tokenDecimals: tokenDecimals,
            ltvBps: ltvBps,
            liquidationBps: liquidationBps,
            bonusBps: bonusBps,
            maxAge: maxAge,
            listed: true
        });
        listedTokens.push(token);
        emit MarketListed(token, address(feed), ltvBps, liquidationBps, bonusBps, maxAge);
    }

    function listedCount() external view returns (uint256) {
        return listedTokens.length;
    }

    // ------------------------------------------------------------------------------------------------
    // Suppliers
    // ------------------------------------------------------------------------------------------------

    function supply(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        loanAsset.safeTransferFrom(msg.sender, address(this), amount);
        supplied[msg.sender] += amount;
        totalSupplied += amount;
        emit Supplied(msg.sender, amount);
    }

    function withdrawSupply(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount > supplied[msg.sender]) revert InsufficientSupply(amount, supplied[msg.sender]);
        if (amount > cash()) revert InsufficientLiquidity(amount, cash());
        supplied[msg.sender] -= amount;
        totalSupplied -= amount;
        loanAsset.safeTransfer(msg.sender, amount);
        emit SupplyWithdrawn(msg.sender, amount);
    }

    /// @notice Loan asset available to borrow or withdraw.
    function cash() public view returns (uint256) {
        return totalSupplied - totalDebt;
    }

    // ------------------------------------------------------------------------------------------------
    // Borrowers
    // ------------------------------------------------------------------------------------------------

    function deposit(address token, uint256 amount) external nonReentrant {
        if (!markets[token].listed) revert NotListed(token);
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        positions[token][msg.sender].collateral += amount;
        totalCollateral[token] += amount;
        emit Deposited(token, msg.sender, amount);
    }

    /// @dev With debt outstanding this needs a price, and the position must stay within its loan-to-value limit.
    function withdraw(address token, uint256 amount) external nonReentrant {
        Market memory m = _market(token);
        if (amount == 0) revert ZeroAmount();
        Position storage p = positions[token][msg.sender];
        if (amount > p.collateral) revert InsufficientCollateral(amount, p.collateral);
        uint256 remaining = p.collateral - amount;
        if (p.debt > 0) {
            (uint256 price,) = _price(token, m);
            uint256 limit = _limit(m, remaining, price, m.ltvBps);
            if (p.debt > limit) revert ExceedsLimit(p.debt, limit);
        }
        p.collateral = remaining;
        totalCollateral[token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawn(token, msg.sender, amount);
    }

    function borrow(address token, uint256 amount) external nonReentrant {
        Market memory m = _market(token);
        if (amount == 0) revert ZeroAmount();
        if (amount > cash()) revert InsufficientLiquidity(amount, cash());
        Position storage p = positions[token][msg.sender];
        (uint256 price, uint256 updatedAt) = _price(token, m);
        uint256 debt = p.debt + amount;
        uint256 limit = _limit(m, p.collateral, price, m.ltvBps);
        if (debt > limit) revert ExceedsLimit(debt, limit);
        p.debt = debt;
        totalDebt += amount;
        loanAsset.safeTransfer(msg.sender, amount);
        emit Borrowed(token, msg.sender, amount, price, updatedAt);
    }

    /// @notice Repays up to `amount` of `account`'s debt. Needs no price, so it works while the feed refuses.
    function repay(address token, address account, uint256 amount) external nonReentrant returns (uint256 repaid) {
        if (!markets[token].listed) revert NotListed(token);
        Position storage p = positions[token][account];
        repaid = Math.min(amount, p.debt);
        if (repaid == 0) revert ZeroAmount();
        loanAsset.safeTransferFrom(msg.sender, address(this), repaid);
        p.debt -= repaid;
        totalDebt -= repaid;
        emit Repaid(token, account, msg.sender, repaid);
    }

    /// @notice Repays up to `repayAmount` of an unhealthy position's debt for its collateral at a discount. If the
    ///         collateral cannot cover the repayment plus the bonus, all of it is seized and the rest of the debt
    ///         stays as bad debt.
    function liquidate(address token, address account, uint256 repayAmount)
        external
        nonReentrant
        returns (uint256 repaid, uint256 seized)
    {
        Market memory m = _market(token);
        Position storage p = positions[token][account];
        (uint256 price, uint256 updatedAt) = _price(token, m);
        uint256 threshold = _limit(m, p.collateral, price, m.liquidationBps);
        if (p.debt <= threshold) revert Healthy(p.debt, threshold);

        repaid = Math.min(repayAmount, p.debt);
        if (repaid == 0) revert ZeroAmount();
        seized = _tokensFor(m, repaid * (BPS + m.bonusBps) / BPS, price);
        if (seized > p.collateral) {
            seized = p.collateral;
            repaid = Math.mulDiv(_value(m, seized, price), BPS, BPS + m.bonusBps, Math.Rounding.Ceil);
            repaid = Math.min(repaid, p.debt);
            if (repaid == 0) revert ZeroAmount();
        }
        loanAsset.safeTransferFrom(msg.sender, address(this), repaid);
        p.debt -= repaid;
        p.collateral -= seized;
        totalDebt -= repaid;
        totalCollateral[token] -= seized;
        IERC20(token).safeTransfer(msg.sender, seized);
        emit Liquidated(token, account, msg.sender, repaid, seized, price, updatedAt);
    }

    // ------------------------------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------------------------------

    /// @notice The collateral price in the feed's decimals, or `ok = false` when the feed reverts, answers zero or
    ///         less, or is older than this market's `maxAge`.
    function priceOf(address token) public view returns (bool ok, uint256 price, uint256 updatedAt) {
        Market memory m = markets[token];
        if (!m.listed) revert NotListed(token);
        return _tryPrice(m);
    }

    /// @notice What `amount` of `token` is worth and how much it could borrow, both in the loan asset's units.
    function quote(address token, uint256 amount) external view returns (bool ok, uint256 value, uint256 maxBorrow) {
        Market memory m = markets[token];
        if (!m.listed) revert NotListed(token);
        uint256 price;
        (ok, price,) = _tryPrice(m);
        if (!ok) return (false, 0, 0);
        value = _value(m, amount, price);
        maxBorrow = value * m.ltvBps / BPS;
    }

    /// @notice A position with its limits at the current price. With no price, `ok` is false and both limits are 0.
    function positionOf(address token, address who)
        external
        view
        returns (bool ok, uint256 collateral, uint256 debt, uint256 borrowLimit, uint256 liquidationThreshold)
    {
        Market memory m = markets[token];
        if (!m.listed) revert NotListed(token);
        Position memory p = positions[token][who];
        (collateral, debt) = (p.collateral, p.debt);
        uint256 price;
        (ok, price,) = _tryPrice(m);
        if (ok) {
            borrowLimit = _limit(m, p.collateral, price, m.ltvBps);
            liquidationThreshold = _limit(m, p.collateral, price, m.liquidationBps);
        }
    }

    // ------------------------------------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------------------------------------

    function _market(address token) internal view returns (Market memory m) {
        m = markets[token];
        if (!m.listed) revert NotListed(token);
    }

    function _price(address token, Market memory m) internal view returns (uint256 price, uint256 updatedAt) {
        bool ok;
        (ok, price, updatedAt) = _tryPrice(m);
        if (!ok) revert PriceUnavailable(token);
    }

    function _tryPrice(Market memory m) internal view returns (bool ok, uint256 price, uint256 updatedAt) {
        try m.feed.latestRoundData() returns (uint80, int256 answer, uint256, uint256 updated, uint80) {
            if (answer <= 0 || updated + m.maxAge < block.timestamp) return (false, 0, updated);
            // forge-lint: disable-next-line(unsafe-typecast)
            return (true, uint256(answer), updated);
        } catch {
            return (false, 0, 0);
        }
    }

    /// @dev Value of `amount` collateral in loan-asset units, rounded down.
    function _value(Market memory m, uint256 amount, uint256 price) internal view returns (uint256) {
        return Math.mulDiv(amount, price * 10 ** loanDecimals, 10 ** (uint256(m.tokenDecimals) + m.feedDecimals));
    }

    function _limit(Market memory m, uint256 collateral, uint256 price, uint256 bps) internal view returns (uint256) {
        return _value(m, collateral, price) * bps / BPS;
    }

    /// @dev Collateral worth `value` loan-asset units, rounded down.
    function _tokensFor(Market memory m, uint256 value, uint256 price) internal view returns (uint256) {
        return Math.mulDiv(value, 10 ** (uint256(m.tokenDecimals) + m.feedDecimals), price * 10 ** loanDecimals);
    }
}
