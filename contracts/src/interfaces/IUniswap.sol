// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Minimal, ABI-exact subsets of the Uniswap interfaces Slate calls. `Currency`, `IHooks` and `BalanceDelta` in
// v4-core are user-defined value types over address / address / int256, so plain types encode identically.

/// @dev v4-core `PoolKey`.
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/// @dev v4-core `IPoolManager.SwapParams`. Negative `amountSpecified` is exact input, positive is exact output.
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

/// @dev v4-core `IPoolManager.ModifyLiquidityParams`.
struct ModifyLiquidityParams {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;
    bytes32 salt;
}

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @return swapDelta `BalanceDelta`: amount0 in the upper 128 bits, amount1 in the lower, caller's view.
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 swapDelta);

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (int256 callerDelta, int256 feesAccrued);

    function sync(address currency) external;

    function settle() external payable returns (uint256 paid);

    function take(address currency, address to, uint256 amount) external;

    function extsload(bytes32 slot) external view returns (bytes32 value);
}

interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

/// @dev Uniswap SwapRouter02 (swap-router-contracts), which has no deadline field.
interface ISwapRouter02 {
    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
}

library BalanceDeltaLib {
    function amount0(int256 delta) internal pure returns (int128) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return int128(delta >> 128);
    }

    function amount1(int256 delta) internal pure returns (int128) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return int128(delta);
    }
}
