# Slate

**195 stock tokens on Robinhood Chain, 35 Chainlink feeds. Slate prices the other 160.**

Slate is a multiplier-correct, fail-closed pricing layer for Robinhood stock tokens (ERC-8056), and an in-kind basket token whose NAV is itself an on-chain price feed.

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

[nirholas/three.ws](https://github.com/nirholas/three.ws) already ships an in-kind basket vault on Robinhood Chain and deliberately keeps prices off-chain ("prices are a display concern, computed off-chain"). Slate's in-kind create/redeem follows the same price-independent principle. What Slate adds is the on-chain price: per-token feeds for the uncovered tokens, and a basket NAV feed that other protocols can consume.

## Development

```bash
# contracts
cd contracts && forge build && forge test

# stylus
cd stylus && cargo test
```

## License

MIT
