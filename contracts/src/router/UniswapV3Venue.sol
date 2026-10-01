// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapVenue} from "../interfaces/ISwapVenue.sol";
import {ISwapRouter02} from "../interfaces/IUniswap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title UniswapV3Venue
/// @notice Exact-output swaps through a Uniswap v3 SwapRouter02, such as the official one on Robinhood Chain
///         (0xcaf681a66d020601342297493863e78c959e5cb2) for the real stock/USDG pools.
/// @dev `route` is `abi.encode(uint24 fee)`. The venue pulls `maxIn`, swaps, and returns what is left over.
contract UniswapV3Venue is ISwapVenue {
    using SafeERC20 for IERC20;

    ISwapRouter02 public immutable router;

    constructor(ISwapRouter02 router_) {
        router = router_;
    }

    /// @inheritdoc ISwapVenue
    function swapExactOut(address tokenIn, address tokenOut, uint256 amountOut, uint256 maxIn, bytes calldata route)
        external
        returns (uint256 amountIn)
    {
        uint24 fee = abi.decode(route, (uint24));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), maxIn);
        IERC20(tokenIn).forceApprove(address(router), maxIn);
        amountIn = router.exactOutputSingle(
            ISwapRouter02.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: msg.sender,
                amountOut: amountOut,
                amountInMaximum: maxIn,
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(tokenIn).forceApprove(address(router), 0);
        if (maxIn > amountIn) IERC20(tokenIn).safeTransfer(msg.sender, maxIn - amountIn);
    }
}
