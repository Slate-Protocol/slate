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

## Known gap: a one-report jump

The publisher refuses a quote that is halted, non-positive, older than 60 seconds, from the future, or whose bid/ask spread is wider than 2%. It does not compare a quote with the prices it signed a minute earlier, and that has let at least one bad price through: at 23:14 New York time on Thu 1 Oct 2026, overnight in the 24/5 session, the testnet AMD feed received $609.80, 1.7% below the reports either side of it. The next report, a minute later, was $620.67. It is the only such report among 2,057 for the four tokens charted on the [accuracy page](https://app.slate.0xo.in/accuracy), which names it as Slate's error.

**The guard we would add:** before signing, compare the new midpoint with the last one signed for that token. If it moved more than a set bound (for example 1%) within a few minutes, and the move is not confirmed by the next quote, hold the report and sign the confirmed price instead. A genuine move costs one cycle of delay; a single bad quote is never signed. The same check would cover every feed, mainnet included.

**Why it is not shipped yet:** the guard changes what the live mainnet signer signs, and that signer is serving CRWD and nineteen other feeds through judging. One bad report in 2,057, corrected a minute later, does not justify changing a deployed, working signer mid-event. It is the first change planned after judging closes.
