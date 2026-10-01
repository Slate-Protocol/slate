---
title: SlateFeed
description: One feed per token. Chainlink's interface, Slate's rules.
---

`SlateFeed` prices one stock token in USD with 8 decimals. It implements `AggregatorV3Interface` plus:

```solidity
function latestQuote() external view returns (Quote memory);  // (status, answer, observedAt); never reverts
function latestDetail() external view returns (Quote memory, int256 sharePrice, uint256 multiplier);
function status() external view returns (FeedStatus);
function poke() external returns (bool);                     // record a staged multiplier change
function token() external view returns (address);
```

`getRoundData` reverts with `NoHistory()`: a Slate feed is a current price, not an archive.

## Configuration

Each feed is immutable once deployed:

| Field | Meaning | Testnet value |
|---|---|---|
| `token` | The stock token | e.g. TSLA `0xC9f9…Bd4E` |
| `model` | `ERC8056`, `REBASING` (Robinhood's legacy Arbitrum One tokens) or `NONE` | `ERC8056` |
| `source` | Where share prices come from (`SignedSource`, `ChainlinkSource`) | `SignedSource` |
| `feedId` | The source's key, e.g. `bytes32("TSLA/USD")` | |
| `maxAge` | Oldest usable price while the market is open | 20 minutes |
| `corporateActionGrace` | Refusal window after a large multiplier change | 30 minutes |
| `largeChangeBps` | What counts as large | 500 (5%) |
| `allowMarketClosed` | Whether `latestRoundData()` serves `MARKET_CLOSED` prices | true |
| `calendar`, `session` | Trading calendar and session | `USMarketCalendar`, `EXTENDED` |

On Robinhood Chain mainnet, CRWD's feed accepts prices up to **40 minutes** old, because the publisher signs it on a 0.5% move or every 30 minutes to keep mainnet gas low.

## Models

- **ERC8056** (Robinhood Chain): token price = share price × the multiplier in force when the price was observed. See [The multiplier problem](/concepts/multipliers).
- **REBASING** (Robinhood's earlier tokens on Arbitrum One): `balanceOf` already includes `multiplier()`, so one token is one share-equivalent and the price is the share price. Applying the multiplier here would be the double count.
- **NONE**: a plain ERC-20; one token is one share.

## Sources

| Source | Kind | Used for |
|---|---|---|
| `SignedSource` | `RAW_UNDERLYING` | Tokens with no Chainlink feed. See [Signed prices](/concepts/signed-prices) |
| `ChainlinkSource` over Robinhood's feeds | `TOTAL_RETURN` | The 35 tokens Chainlink covers on Robinhood Chain |
| `ChainlinkSource` over raw equity feeds | `RAW_UNDERLYING` | Chainlink's 9 raw equity feeds on Arbitrum One |

A Chainlink answer that reverts or is non-positive reads as `NO_DATA`; it never reaches a caller.

## Deploying

`SlateFeedFactory.deploy(config, salt)` deploys at a CREATE2 address salted by the caller, so nobody can squat your address. `deployCalibrated(config, salt, reference, maxDiffBps)` deploys and then reverts unless the new feed agrees with an independent reference. This is the deploy-time guard against a source declared with the wrong price kind.
