// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISlateFeed} from "../interfaces/ISlateFeed.sol";
import {
    BalanceDeltaLib,
    IPoolManager,
    IUnlockCallback,
    ModifyLiquidityParams,
    PoolKey,
    SwapParams
} from "../interfaces/IUniswap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface ITokenFeed {
    function token() external view returns (address);
}

/// @title SlateV4Seeder
/// @notice TESTNET HELPER. Opens Uniswap v4 stock/TESTUSD pools at a chosen price, adds or removes liquidity, and
///         recenters a pool on its Slate price, so the router has something honest to trade against on Robinhood
///         Chain testnet. Not for mainnet, where the real stock/USDG pools exist and arbitrage keeps them priced.
/// @dev Testnet pools have no arbitrageurs: left alone, a pool keeps its seed price while the market moves, and the
///      router (rightly) refuses it. `recenter` is the missing arbitrageur: it swaps the pool to the Slate price,
///      paid by the caller. Each caller's liquidity position is its own (salt = caller). Amounts owed are pulled
///      from the caller inside `unlock`, capped by `max0`/`max1`; amounts due are sent to the caller.
contract SlateV4Seeder is IUnlockCallback {
    using SafeERC20 for IERC20;
    using BalanceDeltaLib for int256;

    /// @dev v4-core `PoolManager` storage slot of the `pools` mapping.
    bytes32 private constant POOLS_SLOT = bytes32(uint256(6));
    uint8 private constant PRICE_DECIMALS = 8;
    uint160 private constant MIN_SQRT_PRICE = 4_295_128_739;
    uint160 private constant MAX_SQRT_PRICE = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    IPoolManager public immutable poolManager;

    enum Action {
        MODIFY,
        SWAP
    }

    struct Job {
        Action action;
        PoolKey key;
        ModifyLiquidityParams params;
        bool zeroForOne;
        uint160 sqrtPriceLimitX96;
        address owner;
        uint256 max0;
        uint256 max1;
    }

    event Recentered(bytes32 indexed poolId, uint160 fromSqrtPriceX96, uint160 toSqrtPriceX96);

    error OnlyPoolManager();
    error NativeCurrencyUnsupported();
    error ExcessiveAmount(uint256 amount, uint256 maximum);
    error FeedNotInPool(address token);
    error PoolNotInitialized();

    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    // ------------------------------------------------------------------------------------------------
    // Liquidity
    // ------------------------------------------------------------------------------------------------

    /// @notice Initializes the pool at `sqrtPriceX96` if it does not exist yet, then adds `liquidity` between the
    ///         two ticks.
    function seed(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 max0,
        uint256 max1
    ) external returns (int256 delta) {
        if (key.currency0 == address(0)) revert NativeCurrencyUnsupported();
        if (sqrtPriceOf(key) == 0) poolManager.initialize(key, sqrtPriceX96);
        delta = _modify(key, tickLower, tickUpper, SafeCast.toInt256(uint256(liquidity)), max0, max1);
    }

    /// @notice Removes `liquidity` from the caller's position and sends the tokens to the caller.
    function unseed(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (int256 delta)
    {
        delta = _modify(key, tickLower, tickUpper, -SafeCast.toInt256(uint256(liquidity)), 0, 0);
    }

    // ------------------------------------------------------------------------------------------------
    // Recentering
    // ------------------------------------------------------------------------------------------------

    /// @notice If the pool is more than `toleranceBps` from `feed`'s price, swaps it to exactly that price. The
    ///         other currency is valued at $1 (TESTUSD). Reverts like the feed if its price is unusable.
    /// @return moved Whether a swap happened.
    function recenter(PoolKey calldata key, ISlateFeed feed, uint256 toleranceBps, uint256 max0, uint256 max1)
        external
        returns (bool moved)
    {
        uint160 current = sqrtPriceOf(key);
        if (current == 0) revert PoolNotInitialized();
        uint160 target = targetSqrtPrice(key, feed);
        // Price is the square of the sqrt price, so a sqrt move of d is a price move of about 2d.
        uint256 diff = target > current ? target - current : current - target;
        if (diff * 2 * 10_000 <= uint256(current) * toleranceBps) return false;

        Job memory job;
        job.action = Action.SWAP;
        job.key = key;
        job.zeroForOne = target < current;
        job.sqrtPriceLimitX96 = target;
        job.owner = msg.sender;
        job.max0 = max0;
        job.max1 = max1;
        poolManager.unlock(abi.encode(job));
        emit Recentered(poolId(key), current, target);
        return true;
    }

    // ------------------------------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------------------------------

    function poolId(PoolKey calldata key) public pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    /// @notice The pool's current sqrt price (Q64.96), or 0 if it is not initialized. Read through `extsload`.
    function sqrtPriceOf(PoolKey calldata key) public view returns (uint160) {
        bytes32 slot = keccak256(abi.encode(poolId(key), POOLS_SLOT));
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint160(uint256(poolManager.extsload(slot)));
    }

    /// @notice The sqrt price (Q64.96, raw token1 per raw token0) that puts the stock at `feed`'s price in a $1 unit.
    function targetSqrtPrice(PoolKey calldata key, ISlateFeed feed) public view returns (uint160) {
        address stock = ITokenFeed(address(feed)).token();
        bool stockIs0 = stock == key.currency0;
        if (!stockIs0 && stock != key.currency1) revert FeedNotInPool(stock);
        address cash = stockIs0 ? key.currency1 : key.currency0;

        (, int256 answer,,,) = feed.latestRoundData();
        uint256 cashPerStock = SafeCast.toUint256(answer) * 10 ** IERC20Metadata(cash).decimals();
        uint256 stockUnit = 10 ** (PRICE_DECIMALS + IERC20Metadata(stock).decimals());
        uint256 ratioX192 =
            stockIs0 ? Math.mulDiv(cashPerStock, 1 << 192, stockUnit) : Math.mulDiv(stockUnit, 1 << 192, cashPerStock);
        uint256 sqrtPrice = Math.sqrt(ratioX192);
        if (sqrtPrice <= MIN_SQRT_PRICE) return MIN_SQRT_PRICE + 1;
        if (sqrtPrice >= MAX_SQRT_PRICE) return MAX_SQRT_PRICE - 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint160(sqrtPrice);
    }

    // ------------------------------------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------------------------------------

    function _modify(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        uint256 max0,
        uint256 max1
    ) private returns (int256 delta) {
        Job memory job;
        job.action = Action.MODIFY;
        job.key = key;
        job.params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            salt: bytes32(uint256(uint160(msg.sender)))
        });
        job.owner = msg.sender;
        job.max0 = max0;
        job.max1 = max1;
        delta = abi.decode(poolManager.unlock(abi.encode(job)), (int256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        Job memory job = abi.decode(data, (Job));
        int256 delta;
        if (job.action == Action.MODIFY) {
            (delta,) = poolManager.modifyLiquidity(job.key, job.params, "");
        } else {
            // Exact input with no practical cap: the price limit is what stops the swap.
            delta = poolManager.swap(
                job.key,
                SwapParams({
                    zeroForOne: job.zeroForOne,
                    amountSpecified: -int256(uint256(type(uint128).max)),
                    sqrtPriceLimitX96: job.sqrtPriceLimitX96
                }),
                ""
            );
        }
        _resolve(job.key.currency0, delta.amount0(), job.owner, job.max0);
        _resolve(job.key.currency1, delta.amount1(), job.owner, job.max1);
        return abi.encode(delta);
    }

    /// @dev Negative: the owner pays the pool. Positive: the pool pays the owner.
    function _resolve(address currency, int128 amount, address owner, uint256 maximum) private {
        if (amount < 0) {
            uint256 owed = SafeCast.toUint256(-int256(amount));
            if (owed > maximum) revert ExcessiveAmount(owed, maximum);
            poolManager.sync(currency);
            IERC20(currency).safeTransferFrom(owner, address(poolManager), owed);
            poolManager.settle();
        } else if (amount > 0) {
            poolManager.take(currency, owner, SafeCast.toUint256(int256(amount)));
        }
    }
}
