---
title: Feed statuses
description: Every reason a SlateFeed will or will not serve a price.
---

Every Slate feed evaluates a status on each read. `latestRoundData()` returns a price only for `OK`, or for `MARKET_CLOSED` when the feed was deployed with `allowMarketClosed`. Every other status reverts with `FeedUnavailable(status)`. `latestQuote()` never reverts, so you can always see why.

| Status | Meaning | `latestRoundData()` |
|---|---|---|
| `OK` | Fresh and consistent. | Price |
| `MARKET_CLOSED` | Weekend, holiday or overnight gap, and the last price was fresh when the session closed. | Price if `allowMarketClosed`, else reverts |
| `STALE` | Older than `maxAge` while the market is open. | Reverts |
| `ORACLE_PAUSED` | Robinhood's `oraclePaused()` is set on the token. | Reverts |
| `STRADDLE` | Observed before a multiplier switch that has since happened, and the old multiplier was not recorded. | Reverts |
| `CORPORATE_ACTION` | Within the grace window after a large multiplier change. | Reverts |
| `NO_DATA` | No usable price. | Reverts |

## Evaluation order

1. `NO_DATA` if the source has nothing, or the price is not positive.
2. `ORACLE_PAUSED` if the token supports the flag and it is set. Testnet tokens use an older implementation without it, and SlateFeed probes for it with a gas-capped call.
3. `CORPORATE_ACTION` or `STRADDLE` around a multiplier switch. See [The multiplier problem](/concepts/multipliers).
4. `OK` if the price is younger than `maxAge`.
5. `MARKET_CLOSED` if the session is closed and the price was fresh at the close. See [Market calendar](/concepts/calendar).
6. `STALE` otherwise.

## Composed feeds

- **SlateNavFeed** takes the **worst** status of its constituents and the **oldest** observation time. One stale or paused stock makes the whole NAV unavailable.
- **SlateQuotedFeed** (a feed re-quoted in USDG) passes the base feed's status through, and reports `STALE` or `NO_DATA` if the USDG/USD price is unusable.
