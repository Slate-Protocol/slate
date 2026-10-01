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

A signed share price of $264.98 × CRWD's on-chain multiplier of 4.000 = **$1,059.92** per token: exactly Robinhood's own `tokenBid` at the same moment. [Verify every part of that yourself](/verify-crwd).

## What is live

- **Robinhood Chain testnet:** five SlateFeeds (TSLA, AMZN, AMD, PLTR, NFLX) with prices signed 24/5, the SLATE-5 basket and its NAV feed, the router with oracle-banded Uniswap v4 pools, and the Corporate Action Lab. Every contract is verified. See [Deployments](/deployments).
- **Robinhood Chain mainnet:** read-only SlateFeeds, CRWD first, are scripted and dry-run. They are not deployed yet; this page will say so until they are.

## Where to go next

- Integrating a price? Start with the [Quickstart](/quickstart).
- Want the reasoning? Read [The multiplier problem](/concepts/multipliers) and [Feed statuses](/concepts/statuses).
- Judging what is new? See [Prior art](/prior-art) and [Disclosures](/disclosures).
