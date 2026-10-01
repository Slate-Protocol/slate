// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice A place `SlateRouter` can buy an exact amount of one token with another.
/// @dev The venue pulls at most `maxIn` of `tokenIn` from the caller (who must have approved it) and sends exactly
///      `amountOut` of `tokenOut` to the caller. `route` is venue-specific (fee tier, pool key, …).
interface ISwapVenue {
    function swapExactOut(address tokenIn, address tokenOut, uint256 amountOut, uint256 maxIn, bytes calldata route)
        external
        returns (uint256 amountIn);
}
