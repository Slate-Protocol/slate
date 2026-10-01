---
title: Signed prices
description: How a share price with no Chainlink feed gets on-chain, and what bounds it there.
---

For the tokens Chainlink does not cover, the only off-chain fact Slate needs is the **share price**. Everything else (the multiplier, its timing, the pause flag, the corporate-action window) is read on-chain from the token itself.

## SignedSource

Share prices arrive as **reports**: one EIP-712 signature per signer over

```
Observation(bytes32 feedId, int192 price, uint64 observedAt)
```

packed as 97-byte entries (`price ‖ observedAt ‖ r ‖ s ‖ v`) in ascending signer order. `SignedSource.submit(feedId, report)` accepts a report only if:

| Check | Deployed value |
|---|---|
| Every signer is authorised, none repeated | 3 signers |
| At least `quorum` signed | 2 of 3 |
| Spread between the highest and lowest signed price | at most 0.5% |
| A move from the last price larger than the jump bound needs **every** signer | 10% |
| `observedAt` is newer than the last accepted price | strictly increasing |
| `observedAt` is not in the future | at most 60 s ahead |

The feed takes the **median** price and the median observation time. Anyone can relay a report; the signatures are what count. The signer set is changed only through a **48-hour timelock**.

The verifier is a separate contract behind `IReportVerifier`. Slate ships the Solidity verifier; a Rust (Stylus) verifier with identical behaviour exists and lost on gas. See [Stylus benchmark](/stylus).

## Where the prices come from

The publisher reads Robinhood's public quote endpoint, `https://api.robinhood.com/rhj/prices/{symbol}`, and signs the **mid** of `bid` and `ask`. Before any key signs, it refuses:

- a trading halt, a quote older than 60 seconds, or a bid/ask spread wider than 2%;
- a quote whose `tokenBid ÷ bid` disagrees with the token's on-chain `uiMultiplier()` on mainnet by more than 0.5%: Robinhood's own data must agree with Robinhood's own chain;
- a TSLA price more than 2% from Chainlink's raw TSLA feed on Arbitrum One, when that feed is fresh;
- anything at all while the market calendar says the session is closed. Robinhood keeps serving Friday's quote with a fresh timestamp all weekend, and signing it would make a closed market look live.

## The honest status

**Today all three keys are ours.** That is the hackathon reality. The contract is built so the set can be handed to independent operators, each running the same publisher against the same sources, without redeploying a feed.

And it is the same trust model as everything else that prices a US stock on-chain. Chainlink's Robinhood feeds are a committee of nodes reading an off-chain stream; their adapter multiplies by `uiMultiplier()` off-chain. Slate moves everything that *can* be on-chain on-chain, and bounds the one thing that cannot.
