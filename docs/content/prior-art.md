---
title: Prior art
description: Who built what first, named plainly, and the two things Slate adds.
---

| | Slate | Strike | three.ws |
|---|---|---|---|
| Prices tokens with no Chainlink feed | **Yes** | No | No |
| Basket NAV as an AggregatorV3 feed | **Yes** | No | No |
| On-chain market calendar | Yes, approach adopted from Strike | Yes | No |
| In-kind basket | Yes | No | Yes |

## Strike

[Prashant-thakur77/Strike](https://github.com/Prashant-thakur77/Strike) guards Chainlink stock feeds in its `SafeStockFeed` library: staleness, both pause flags, corporate actions, and an on-chain market calendar. **Strike's market calendar was better than our first version and we adopted the approach.** Our first version only knew weekends. Holidays, early closes and daylight saving on-chain came from seeing Strike do it.

## three.ws

[nirholas/three.ws](https://github.com/nirholas/three.ws) ships an in-kind basket vault on Robinhood Chain and deliberately keeps prices off-chain: "prices are a display concern, computed off-chain". Slate's in-kind create and redeem follow the same price-independent principle.

## What Slate adds

Strike builds on Chainlink feeds that already exist, and three.ws has no on-chain price at all. **Neither prices a stock token that has no Chainlink feed, and neither publishes a basket NAV as a feed.** Those are the two things Slate adds.
