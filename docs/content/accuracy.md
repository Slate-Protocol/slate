---
title: Slate against Chainlink
description: Slate's signed price beside Chainlink's for every Robinhood stock token Chainlink covers, verified in your browser.
---

Why trust a Slate price? Where Chainlink also publishes one, you can compare them, live: [app.slate.0xo.in/accuracy](https://app.slate.0xo.in/accuracy).

Chainlink publishes feeds for 35 Robinhood stock tokens on Robinhood Chain mainnet. For each one, the board puts Chainlink's answer beside the price Slate signs from the same Robinhood quotes it uses for every Slate feed, times the token's on-chain multiplier, exactly as `SlateFeed` computes it. Agreement on the tokens Chainlink covers is the evidence for trusting Slate on the ones it does not.

## What your browser checks

The publisher supplies only signed reports, from its `/board` endpoint. Everything else is checked or read in the browser:

1. **Signatures.** Each report is the exact bytes `SignedSource.submit` takes. Every 97-byte entry must carry the claimed price and time and recover, under `SignedSource`'s EIP-712 domain for Robinhood Chain mainnet, a distinct address in Slate's on-chain signer set; there must be at least the quorum.
2. **Multiplier.** `uiMultiplier()` is read from each token on mainnet.
3. **Chainlink.** `latestRoundData()` and `decimals()` are read from each Chainlink proxy on mainnet.

No report is ever submitted, so the board costs no gas. The reports are signed for mainnet's `SignedSource`, so each is exactly what a mainnet SlateFeed would accept.

## Reading the gaps

- **Gap now** compares the latest of each. Chainlink's Robinhood feeds update on a 0.5% move or every 24 hours, so part of this gap can be Chainlink waiting for its threshold.
- **Gap then** is like for like: Chainlink's answer against Slate's report signed within 90 seconds of Chainlink's last update.

The summary shows the median and the worst case of each, and names the token with the worst gap. Slate signs the midpoint of Robinhood's bid and ask, so thinly traded names with wide spreads show wider gaps.

Outside the 24/5 session Slate signs nothing. Over a weekend the board shows the last reports signed before Friday's close, which the dashboard also keeps as a snapshot.
