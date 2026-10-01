// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    BalanceDeltaLib,
    IPoolManager,
    IUnlockCallback,
    ModifyLiquidityParams,
    PoolKey
} from "../interfaces/IUniswap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title SlateV4Seeder
/// @notice TESTNET HELPER. Opens a Uniswap v4 pool at a chosen price and adds or removes liquidity, so the router
///         has something honest to trade against on Robinhood Chain testnet. Not for mainnet, where the real
///         stock/USDG pools already exist.
/// @dev Each caller's position is its own (the salt is the caller's address); only that caller can remove it, and
///      removed tokens go back to that caller. Amounts owed are pulled from the caller inside `unlock`, capped by
///      `max0`/`max1`. Liquidity is in Uniswap's units: for a full-range position at price P (token1 per token0,
///      raw units), L ≈ amount1 / √P ≈ amount0 × √P.
contract SlateV4Seeder is IUnlockCallback {
    using SafeERC20 for IERC20;
    using BalanceDeltaLib for int256;

    IPoolManager public immutable poolManager;

    struct Job {
        PoolKey key;
        ModifyLiquidityParams params;
        address owner;
        uint256 max0;
        uint256 max1;
    }

    error OnlyPoolManager();
    error NativeCurrencyUnsupported();
    error ExcessiveAmount(uint256 amount, uint256 maximum);

    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

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
        try poolManager.initialize(key, sqrtPriceX96) {} catch {} // already initialized: keep its price
        delta = _modify(key, tickLower, tickUpper, SafeCast.toInt256(uint256(liquidity)), max0, max1);
    }

    /// @notice Removes `liquidity` from the caller's position and sends the tokens to the caller.
    function unseed(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (int256 delta)
    {
        delta = _modify(key, tickLower, tickUpper, -SafeCast.toInt256(uint256(liquidity)), 0, 0);
    }

    function _modify(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        uint256 max0,
        uint256 max1
    ) private returns (int256 delta) {
        Job memory job = Job({
            key: key,
            params: ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(uint256(uint160(msg.sender)))
            }),
            owner: msg.sender,
            max0: max0,
            max1: max1
        });
        delta = abi.decode(poolManager.unlock(abi.encode(job)), (int256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        Job memory job = abi.decode(data, (Job));
        (int256 delta,) = poolManager.modifyLiquidity(job.key, job.params, "");
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
