---
title: Router and the refused route
description: Creating basket shares with cash, and why the router refuses a pool that disagrees with Slate.
---

Most people do not hold five stock tokens. `SlateRouter` creates basket shares from one cash token (USDG on mainnet, TESTUSD on testnet) by buying each constituent through a swap venue, then calling `create`.

```solidity
function createWithCash(uint256 shares, address to, Leg[] calldata legs, uint256 maxCashIn, uint256 deadline)
    external returns (uint256 cashIn);
function fairCash(uint256 shares) external view returns (uint256 total, uint256[] memory amounts);
```

## A pool is not a price

Before a leg counts, the router measures its **effective price**, the cash that actually left its balance × cash/USD ÷ tokens received, and compares it with that constituent's SlateFeed price:

```
|effective − SlateFeed| / SlateFeed ≤ maxDeviationBps     (300 = 3% deployed; 20% is the hard ceiling)
```

Outside the band, the whole creation reverts with `RouteRefused(leg, effectivePrice, feedPrice)`. Too expensive means a manipulated or illiquid pool. Too cheap means the pool is not the stock's market: the wrong token, a dead pool, or a broken price. Either way the router will not treat it as fair. The feed price is read through `latestRoundData()`, so a stale or mid-split feed also stops the creation.

## The refused route, on a real pool

On Robinhood Chain testnet, a third-party Uniswap v3 clone (factory `0x911b4000D3422F482F4062a913885f7b035382Df`) has a TSLA/USDC pool, `0xFfEf1147c3724a19AB7328F4e361C049ba452dA9`, that sells TSLA for **$0.0675**. Slate's TSLA price at the time was **$354.11**. That is 99.98% off. A router that trusts the pool fills there; Slate's refuses:

```bash
cd contracts && SLATE_FORK=1 forge test --match-test test_thirdPartyV3Pool_isRefused -vv
#   third-party pool, USD per TSLA (8 dp): 6752677
#   Slate TSLA price  (8 dp): 35411000000
```

## Accepted routes

- **Mainnet, real USDG:** on a fork of Robinhood Chain mainnet, the router bought 0.1 AAPL through the live AAPL/USDG pool for **32.79 USDG against 32.71 fair**, inside the band. See [USDG integration](/usdg).
- **Testnet, live:** one SLATE-5 share for 50.33 TESTUSD against a NAV of $49.96, through Slate's seeded Uniswap v4 pools (transaction `0xe53384ae…7d03`).

## Venues

| Venue | For | `route` |
|---|---|---|
| `UniswapV4Venue` | Uniswap v4's `PoolManager` (official on Robinhood Chain testnet) | `abi.encode(uint24 fee, int24 tickSpacing, address hooks)` |
| `UniswapV3Venue` | `SwapRouter02` (the official one on Robinhood Chain mainnet, for the stock/USDG pools) | `abi.encode(uint24 fee)` |

The router never trusts a venue's return value: cash spent and tokens received are measured by balance. Leftover cash is refunded, and the router holds nothing between calls (fuzz-tested).

**Testnet pools have no arbitrageurs.** Left alone, a pool keeps its seed price while the market moves, and the router would (rightly) refuse it. Slate's publisher recenters the testnet pools to the Slate price through `SlateV4Seeder.recenter`. It acts as the missing arbitrageur, and it is labelled as testnet-only.
