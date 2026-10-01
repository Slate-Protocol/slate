// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapVenue} from "../interfaces/ISwapVenue.sol";
import {BalanceDeltaLib, IPoolManager, IUnlockCallback, PoolKey, SwapParams} from "../interfaces/IUniswap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title UniswapV4Venue
/// @notice Exact-output swaps against a Uniswap v4 PoolManager, for ERC-20 pairs. Stateless between calls.
/// @dev `route` is `abi.encode(uint24 fee, int24 tickSpacing, address hooks)`; the pool key is built from the two
///      tokens. Inside `unlock`, the swap's input is paid with sync → transfer → settle and the output taken
///      straight to the caller.
contract UniswapV4Venue is ISwapVenue, IUnlockCallback {
    using SafeERC20 for IERC20;
    using BalanceDeltaLib for int256;

    uint160 private constant MIN_PRICE_LIMIT = 4_295_128_740; // TickMath.MIN_SQRT_PRICE + 1
    uint160 private constant MAX_PRICE_LIMIT = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341; // MAX - 1

    IPoolManager public immutable poolManager;

    struct Job {
        PoolKey key;
        bool zeroForOne;
        uint256 amountOut;
        uint256 maxIn;
        address payer;
        address tokenIn;
        address tokenOut;
    }

    error OnlyPoolManager();
    error NativeCurrencyUnsupported();
    error ExcessiveInput(uint256 amountIn, uint256 maxIn);

    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    /// @inheritdoc ISwapVenue
    function swapExactOut(address tokenIn, address tokenOut, uint256 amountOut, uint256 maxIn, bytes calldata route)
        external
        returns (uint256 amountIn)
    {
        if (tokenIn == address(0) || tokenOut == address(0)) revert NativeCurrencyUnsupported();
        (PoolKey memory key, bool zeroForOne) = poolKey(tokenIn, tokenOut, route);
        bytes memory result = poolManager.unlock(
            abi.encode(
                Job({
                    key: key,
                    zeroForOne: zeroForOne,
                    amountOut: amountOut,
                    maxIn: maxIn,
                    payer: msg.sender,
                    tokenIn: tokenIn,
                    tokenOut: tokenOut
                })
            )
        );
        amountIn = abi.decode(result, (uint256));
    }

    /// @notice The pool key for a `tokenIn` → `tokenOut` swap, and whether it swaps currency0 for currency1.
    function poolKey(address tokenIn, address tokenOut, bytes calldata route)
        public
        pure
        returns (PoolKey memory key, bool zeroForOne)
    {
        (uint24 fee, int24 tickSpacing, address hooks) = abi.decode(route, (uint24, int24, address));
        zeroForOne = tokenIn < tokenOut;
        (address currency0, address currency1) = zeroForOne ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        key = PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks});
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        Job memory job = abi.decode(data, (Job));

        int256 delta = poolManager.swap(
            job.key,
            SwapParams({
                zeroForOne: job.zeroForOne,
                amountSpecified: SafeCast.toInt256(job.amountOut),
                sqrtPriceLimitX96: job.zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            ""
        );
        int128 inDelta = job.zeroForOne ? delta.amount0() : delta.amount1();
        // The caller owes the input, so its delta is negative.
        uint256 amountIn = SafeCast.toUint256(-int256(inDelta));
        if (amountIn > job.maxIn) revert ExcessiveInput(amountIn, job.maxIn);

        poolManager.sync(job.tokenIn);
        IERC20(job.tokenIn).safeTransferFrom(job.payer, address(poolManager), amountIn);
        poolManager.settle();
        poolManager.take(job.tokenOut, job.payer, job.amountOut);
        return abi.encode(amountIn);
    }
}
