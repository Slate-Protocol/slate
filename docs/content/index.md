---
title: Introduction
description: A multiplier-correct, fail-closed price feed for every Robinhood stock token, and a basket whose NAV is itself a feed.
---

**Nearly 200 stock tokens on Robinhood Chain. 35 Chainlink feeds. Slate prices the rest.**

Robinhood Chain carries tokenised US stocks as ERC-20s. Each token implements ERC-8056: its balance never changes, and a `uiMultiplier()` says how many shares one token is worth. After CrowdStrike's 4:1 split on 2 July 2026, one CRWD token is four shares.

On 1 October 2026 Robinhood's registry listed **194** stock tokens. Chainlink publishes feeds for **35** of them. The other 159, CRWD included, have no on-chain price at all, so no lending market, vault or index can use them.

Slate does two things nobody else does:

1. **It prices the stock tokens that have no Chainlink feed.** A share price signed by a K-of-N committee, times the multiplier that was in force *when that price was observed*, behind a contract that refuses to answer when the answer could be wrong.
2. **The basket's NAV is itself a drop-in `AggregatorV3Interface` feed.** Any protocol that already reads Chainlink can price a Slate basket share with no adapter.

## CRWD in one line

Live on Robinhood Chain mainnet: CRWD's first signed share price, $268.105 × its on-chain multiplier of 4.000 = **$1,072.42** per token ([transaction](https://robinhoodchain.blockscout.com/tx/0x0d8a2bde33c69e0ae8f931314a6ebe3dcebf29a1860c268d0ffdb3e30e9cccda), Fri 2 Oct 15:04:50 EDT). In the fork test before deployment, $264.98 × 4.000 = $1,059.92 matched Robinhood's own `tokenBid` exactly. [Verify every part of that yourself](/verify-crwd).

## What is live

- **Robinhood Chain testnet:** five SlateFeeds (TSLA, AMZN, AMD, PLTR, NFLX) with prices signed 24/5, the SLATE-5 basket and its NAV feed, the router with oracle-banded Uniswap v4 pools, and the Corporate Action Lab. Every contract is verified. See [Deployments](/deployments).
- **Robinhood Chain mainnet:** live since 3 Oct 2026. Twenty SlateFeeds price stock tokens that have no Chainlink feed, CRWD first, and StockLender, a USDG lender, values CRWD through its SlateFeed: a token no other lender on the chain can price. See [Deployments](/deployments).

## Where to go next

- Integrating a price? Start with the [Quickstart](/quickstart). To look at one first, open [app.slate.0xo.in/price/CRWD](https://app.slate.0xo.in/price/CRWD) in a browser: the [Price API](/api) returns any feed as JSON, read from the chain.
- Want the reasoning? Read [The multiplier problem](/concepts/multipliers) and [Feed statuses](/concepts/statuses).
- Judging what is new? See [Prior art](/prior-art) and [Disclosures](/disclosures).
