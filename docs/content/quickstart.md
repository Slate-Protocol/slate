---
title: Quickstart
description: Read a Slate price from Solidity or the command line in two minutes.
---

A SlateFeed is a Chainlink `AggregatorV3Interface`. If your protocol reads Chainlink, it already reads Slate.

## From Solidity

```solidity
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

AggregatorV3Interface feed = AggregatorV3Interface(SLATE_TSLA_FEED);
(, int256 price,, uint256 updatedAt,) = feed.latestRoundData(); // 8 decimals, USD per token
```

`latestRoundData()` **reverts** with `FeedUnavailable(status)` when the price must not be used: stale, mid-split, oracle paused or no data. You never get a wrong number back. To see why a feed is unavailable without catching a revert, call `latestQuote()`:

```solidity
interface ISlateFeed {
    function latestQuote() external view returns (Quote memory); // (status, answer, observedAt), never reverts
    function status() external view returns (FeedStatus);
}
```

The statuses are explained in [Feed statuses](/concepts/statuses).

## From the command line

```bash
# TSLA on Robinhood Chain testnet, 8 decimals
cast call 0x5A9cD81b257a073802E9A039e7877A604964aa84 \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url https://rpc.testnet.chain.robinhood.com

# The SLATE-5 basket's NAV per share, through the same interface
cast call 0x8E2b6C63463DCf51b307811dB41bd60d7987608D \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url https://rpc.testnet.chain.robinhood.com
```

## Choosing a feed

| You need | Use |
|---|---|
| USD per token, fail-closed | `SlateFeed.latestRoundData()` |
| The reason a price is unavailable | `SlateFeed.latestQuote()` or `status()` |
| The per-share price and the multiplier applied | `SlateFeed.latestDetail()` |
| A basket share's NAV | `SlateNavFeed.latestRoundData()` |
| Any of the above in USDG | Wrap it in `SlateQuotedFeed` with Chainlink USDG/USD. See [USDG integration](/usdg) |

All addresses are on [Deployments](/deployments).
