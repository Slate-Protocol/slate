// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapVenue} from "../../src/interfaces/ISwapVenue.sol";
import {MockStockToken} from "./MockStockToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Sells any MockStockToken for cash at a set rate (cash units per 1e18 token units), minting what it sells.
///      Misbehaviours on demand: deliver short, or pull more cash than it reports.
contract MockVenue is ISwapVenue {
    mapping(address token => uint256) public rate;
    uint256 public shortBy;
    uint256 public overcharge;

    function setRate(address token, uint256 cashPerToken) external {
        rate[token] = cashPerToken;
    }

    function setShortBy(uint256 amount) external {
        shortBy = amount;
    }

    function setOvercharge(uint256 amount) external {
        overcharge = amount;
    }

    function swapExactOut(address tokenIn, address tokenOut, uint256 amountOut, uint256 maxIn, bytes calldata)
        external
        returns (uint256 amountIn)
    {
        amountIn = Math.mulDiv(amountOut, rate[tokenOut], 1e18, Math.Rounding.Ceil);
        require(amountIn <= maxIn, "venue: maxIn");
        IERC20(tokenIn).transferFrom(msg.sender, address(this), Math.min(amountIn + overcharge, maxIn));
        MockStockToken(tokenOut).mint(msg.sender, amountOut - shortBy);
    }
}
