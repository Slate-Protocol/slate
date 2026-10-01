---
title: Publisher
description: The signer and relayer that keeps the signed feeds fresh, and what it refuses to do.
---

The publisher (`publisher/` in the repository) is a Node 24 service, running on Railway. Its state is public: [publisher-production-891d.up.railway.app](https://publisher-production-891d.up.railway.app/).

## Every 15 seconds

1. Ask the market calendar on-chain whether the 24/5 session is open. If not, sign nothing.
2. For each signed feed, fetch Robinhood's quote and run the checks in [Signed prices](/concepts/signed-prices).
3. Read the last on-chain price. Submit a new three-key report only if the price has moved enough or the last one is old enough:

   | Chain | Move | Heartbeat |
   |---|---|---|
   | Robinhood Chain testnet | 0.1% | 5 minutes |
   | Robinhood Chain mainnet (CRWD) | 0.5% | 30 minutes |

4. Every minute, `poke()` any feed whose token has a multiplier change staged, so the pre-switch multiplier is recorded.
5. On testnet, recenter any Uniswap v4 pool more than 0.5% from its Slate price.

## Keys

Three signing keys, each with no other role, and a separate relayer key that only pays gas. None can change the signer set: that goes through the 48-hour timelock. Relaying is permissionless, so anyone with valid signatures could submit them.

## Gas budget

A submit costs about 80,000 gas. On Robinhood Chain mainnet at 0.021 gwei with no L1 data fee, that is about 0.0000017 ETH. At the mainnet cadence of at most about 60 submits per trading day, that is about 0.0001 ETH a day.
