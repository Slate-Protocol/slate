---
title: USDG integration
description: Paxos USDG as a quote currency for every feed, and as the cash leg of basket creation.
---

Slate treats Paxos USDG as a first-class unit on Robinhood Chain.

## Prices in USDG

`SlateQuotedFeed` re-quotes any Slate feed (a stock token or a basket NAV) in USDG through Chainlink's USDG/USD feed on Robinhood Chain mainnet, `0x61B7e5650328764B076A108EFF5fa7282a1B9aD2`:

```
price in USDG = price in USD × 10⁸ / USDG-USD
```

It keeps the base feed's status. It reports `STALE` if the USDG/USD answer is older than its bound (25 hours) and `NO_DATA` if it is missing. A USDG depeg is therefore visible in every quoted price instead of silently assumed away.

## Buying in USDG

On mainnet, `SlateRouter` takes USDG as its cash token and prices it with the same Chainlink USDG/USD feed. A fill's effective price is `USDG spent × USDG/USD ÷ tokens received`. A depeg moves every leg's effective price, and past 3% the router refuses: USDG at $0.98 still clears the band, USDG at $0.96 does not.

**On a fork of Robinhood Chain mainnet**, through the official `SwapRouter02` (`0xcaf681a66d020601342297493863e78c959e5cb2`) and the live **AAPL/USDG** pool (`0xAae0d815EE56e4092a5E5C2911E676Fea50B2d6D`, 0.05% fee), the router bought 0.1 AAPL:

| | USDG |
|---|---|
| Paid | **32.79** |
| Fair (Chainlink AAPL × Chainlink USDG/USD) | **32.71** |
| Difference | +0.25%, inside the 3% band: accepted |

```bash
cd contracts && python3 script/rpc_relay.py https://rpc.mainnet.chain.robinhood.com 8548 &
SLATE_FORK=1 SLATE_FORK_URL_rh_mainnet=http://127.0.0.1:8548 \
  forge test --match-test test_aaplUsdgPool_createsWithinTheBand -vv
```

The same router targets the NVDA/USDG (`0xd4EB21209C4D6093f80B5b84f5C45cc093EA14a3`) and SPY/USDG (`0xa7Bb1AC63BBaB0C44316E6c8C455213441689167`) pools.

## Testnet: TESTUSD

Robinhood Chain testnet has no Paxos USDG we could verify, and no USDG/USD feed. Slate uses **TESTUSD (Slate Test Dollar)**, `0x239f410D4D2152ba890F378f6B4Aa103B9ea7FEF`: 6 decimals, a public `faucet()` of 10,000 per day, priced at exactly $1 by the router. **TESTUSD is a testnet stand-in for Paxos USDG. Not USDG.** The name avoids "tUSD", which is one character from TrueUSD.
