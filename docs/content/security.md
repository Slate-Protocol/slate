---
title: Security and limitations
description: What Slate trusts, what it does not, and what is not done yet.
---

**Slate is unaudited hackathon software.** Do not use it to secure real value.

## Trust assumptions

- **Signers.** Prices for tokens without a Chainlink feed come from a 2-of-3 signer set, and today all three keys are ours. On-chain bounds limit the damage: a 0.5% maximum spread between signers, unanimity for moves over 10%, strictly increasing timestamps, and a 60-second future bound. They do not make a colluding majority honest. The set changes only through a 48-hour timelock.
- **Robinhood's quote API.** The publisher's source. It is cross-checked against the token's on-chain multiplier, and against Chainlink where Chainlink has the same share price.
- **Robinhood's token contracts.** Slate reads `uiMultiplier`, `newUIMultiplier`, `effectiveAt` and, where present, `oraclePaused`. See [Disclosures](/disclosures) for what those contracts do not enforce.
- **Chainlink.** Where a Chainlink feed exists, Slate passes it through with its own status rules on top.

## What fails closed

Stale prices, paused oracles, prices straddling a multiplier switch, the grace window after a large change, a dead or missing USDG/USD price, and any constituent of a basket in any of those states all make `latestRoundData()` revert. The router reads prices through `latestRoundData()`, so it stops too.

## Known limitations

- **No sequencer uptime check yet.** Chainlink's Robinhood Chain directory lists no sequencer-uptime feed to read. A price observed around sequencer downtime is bounded only by `maxAge`.
- **Testnet pools are kept honest by us.** They have no arbitrageurs, so the publisher recenters them. On mainnet the real stock/USDG pools have real arbitrage.
- **No rebalancing.** SLATE-5's composition is fixed at creation; weights drift with prices.
- **Holiday coverage ends in 2028.** After that the calendar treats every weekday as a trading day, which fails closed: an unlisted holiday reads as `STALE`, not `MARKET_CLOSED`.

## Tests

The contracts have 121 unit and fuzz tests, plus live fork tests against Robinhood Chain mainnet and testnet and Arbitrum One. CI runs them on every push, the fork job included.
