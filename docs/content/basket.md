---
title: Basket and NAV feed
description: SLATE-5, an in-kind basket whose NAV is a Chainlink-compatible feed.
---

`SlateBasket` is an ERC-20 backed by fixed amounts of its constituents. SLATE-5 on Robinhood Chain testnet holds TSLA, AMZN, AMD, PLTR and NFLX, set at **$10 of each per share** when it was first created.

## In kind, price-independent

```solidity
function create(uint256 shares, address to, uint256[] calldata maxAmounts) external returns (uint256[] memory);
function redeem(uint256 shares, address to, uint256[] calldata minAmounts) external returns (uint256[] memory);
function quoteCreate(uint256 shares) external view returns (uint256[] memory);  // rounded up
function quoteRedeem(uint256 shares) external view returns (uint256[] memory);  // rounded down
```

Creating takes each constituent pro rata to what the basket already holds; redeeming pays out pro rata. Neither reads a price, so no oracle failure can mint or drain the basket. Rounding always favours the basket, the first creation locks `MINIMUM_SHARES` (10⁶ wei) at the dead address so the supply never returns to zero, and delivery is checked by balance difference.

Fuzz invariants in the test suite: backing per share never decreases, and a create-then-redeem round trip never profits.

## The NAV is a feed

`SlateNavFeed` publishes NAV per share as an `AggregatorV3Interface`, 8 decimals:

```
NAV per share = Σ holdingᵢ × priceᵢ / totalSupply
```

where `priceᵢ` is each constituent's SlateFeed price (multiplier already applied). Its status is the **worst** of the constituents' and its observation time is the **oldest**. One stale, paused or mid-split stock makes the whole NAV unavailable, so a lending market that accepts SLATE-5 as collateral inherits every SlateFeed guard with no extra code:

```solidity
AggregatorV3Interface nav = AggregatorV3Interface(0x8E2b6C63463DCf51b307811dB41bd60d7987608D);
(, int256 navPerShare,,,) = nav.latestRoundData(); // reverts unless every constituent is usable
```

The constructor checks that each feed's `token()` matches the constituent at the same index, so a basket cannot be wired to the wrong feeds.

## Composition

Fixed composition, equal value at creation. Weights drift with prices. Rebalancing is v2: it needs a price to act on, and in-kind create and redeem deliberately never use one.
