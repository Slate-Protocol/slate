# Slate

**195 stock tokens on Robinhood Chain, 35 Chainlink feeds. Slate prices the other 160.**

Slate is a multiplier-correct, fail-closed pricing layer for Robinhood stock tokens (ERC-8056), and an in-kind basket token whose NAV is itself an on-chain price feed. Two things set it apart:

1. **It prices the 160 stock tokens that have no Chainlink feed.**
2. **The basket's NAV is itself a drop-in `AggregatorV3Interface` feed**, so a Slate share can be priced by any protocol that reads Chainlink.

Prices can be quoted in USD or in Paxos USDG (via the USDG/USD Chainlink feed on Robinhood Chain).

> Status: under active development for the Arbitrum Open House Singapore Online Buildathon. Contracts are unaudited.

## Why

Robinhood stock tokens keep `balanceOf` fixed and express dividends and splits through an on-chain multiplier, `uiMultiplier()` (ERC-8056). Only 35 of the 195 tokens have a Chainlink feed. For the other 160 there is no on-chain price at all. That includes CRWD, which sits at a 4× multiplier after a 4:1 split.

On top of that, the multiplier changes silently: `UIMultiplierUpdated` fires when a change is *staged*, and the value flips later by `block.timestamp`. An integrator who pairs a share price with "the multiplier now" is wrong exactly when it matters.

## What's here

| Path | What |
|---|---|
| `contracts/` | Solidity (Foundry): pricing layer (`SlateFeed`, sources, multiplier lens), basket, NAV feed, router |
| `stylus/` | Rust (Arbitrum Stylus): `SlateVerifier`, the signed-report verifier |
| `publisher/` | Signer and relayer service for off-chain share prices |
| `dashboard/` | Dashboard app |
| `docs/` | Documentation site |

## Prior art

- [nirholas/three.ws](https://github.com/nirholas/three.ws) already ships an in-kind basket vault on Robinhood Chain and deliberately keeps prices off-chain ("prices are a display concern, computed off-chain"). Slate's in-kind create/redeem follows the same price-independent principle. What Slate adds is the on-chain price: per-token feeds for the uncovered tokens, and a basket NAV feed that other protocols can consume.
- [Prashant-thakur77/Strike](https://github.com/Prashant-thakur77/Strike) is an options-vault product whose `SafeStockFeed` library guards Chainlink stock feeds: staleness, both pause flags, corporate actions and an on-chain market calendar. On testnet it mirrors mainnet Chainlink rounds into `MirrorFeed`s.

three.ws keeps prices off-chain and Strike builds on Chainlink feeds that already exist. Neither prices a stock token that has no Chainlink feed, and neither publishes a basket NAV as a feed. Those are the two things Slate adds.

## Development

```bash
# contracts
cd contracts && forge build && forge test

# stylus
cd stylus && cargo test
```

## License

MIT
