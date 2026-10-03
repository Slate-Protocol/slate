---
title: Price API
description: Any Slate feed as JSON, read from the chain on every request. Try it in a browser.
---

Every Slate feed is an on-chain contract, and reading one from Solidity is the real integration. To look at one first, there is an HTTP endpoint. Open it in a browser:

**[app.slate.0xo.in/price/CRWD](https://app.slate.0xo.in/price/CRWD)**

```bash
curl -s https://app.slate.0xo.in/price/CRWD
```

```json
{
  "symbol": "CRWD",
  "network": "Robinhood Chain",
  "chainId": 4663,
  "status": "Market closed",
  "servesLatestRoundData": true,
  "price": 1079.9,
  "sharePrice": 269.975,
  "multiplier": 4,
  "observedAt": 1790984206,
  "observedAtIso": "2026-10-02T23:36:46.000Z",
  "ageSeconds": 62353,
  "decimals": 8,
  "answerRaw": "107990000000",
  "feed": "0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77",
  "token": "0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931",
  "explorer": { "feed": "https://robinhoodchain.blockscout.com/address/0x84Ad…Cc77", "token": "…" },
  "block": 79242031,
  "readAt": "2026-10-03T16:55:59.000Z"
}
```

(A real response from 3 Oct 2026, with the market closed: the price is the last one signed before Friday's close.)

## Endpoints

| Request | Returns |
|---|---|
| `GET /price` | Every Slate feed on Robinhood Chain mainnet, each with the URL of its price |
| `GET /price/{SYMBOL}` | One feed, read from the chain now. Symbols are the token tickers: `CRWD`, `NFLX`, `AAPL`… |
| `GET /price?network=testnet`, `GET /price/TSLA?network=testnet` | The same on Robinhood Chain testnet |

Base URL `https://app.slate.0xo.in`. Responses are JSON, open to any origin (CORS `*`), and cached for 10 seconds. There is no key and no account.

## Fields

| Field | Meaning |
|---|---|
| `status` | The feed's own status: `OK`, `Market closed`, `Stale`, `Oracle paused`, `Straddle`, `Corporate action` or `No data`. See [Feed statuses](/concepts/statuses). |
| `servesLatestRoundData` | Whether `latestRoundData()`, the call a lending market makes, returns this price right now. The endpoint makes that call; when it reverts, `latestRoundDataReverts` names the error. |
| `price` | The token price in USD: `sharePrice × multiplier`, as the feed computed it. `null` when the feed holds no price. |
| `sharePrice` | The signed share price the feed holds. |
| `multiplier` | The token's ERC-8056 multiplier in force when that price was observed. |
| `observedAt`, `observedAtIso`, `ageSeconds` | When the share price was observed, and how long ago. |
| `answerRaw`, `decimals` | The exact on-chain answer and its decimals (8), for anyone checking the arithmetic. |
| `feed`, `token`, `explorer` | The feed and token contracts, with explorer links. |
| `block`, `readAt` | The block the endpoint read at, and when. |

Each request calls `SlateFeed.latestDetail()`, which never reverts so it can report why there is no price, and `latestRoundData()`. Nothing is cached beyond the 10 seconds, nothing is signed, and nothing is computed off-chain: the endpoint shows what a contract would see at that block.

## It is not the integration

A protocol should read the feed on-chain, never this endpoint. A lending market that prices collateral from an HTTP response trusts whoever runs the server; reading the feed trusts only the contract. See [Integrate in five lines](/integrate).
