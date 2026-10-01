---
title: The multiplier problem
description: Why a stock-token price is harder than a share price, and the timing rule SlateFeed applies.
---

An ERC-8056 token never rebases. Your balance stays the same through a split; instead the token says how many shares one token represents:

```solidity
function uiMultiplier() external view returns (uint256);    // shares per token, 18 decimals
function newUIMultiplier() external view returns (uint256); // the staged value
function effectiveAt() external view returns (uint256);     // when the staged value takes over
```

So the price of one token is **share price × multiplier**. Getting that product right is harder than it looks, in four ways.

## 1. The switch is silent

`UIMultiplierUpdated` fires when a change is **staged**, not when it happens. At `effectiveAt`, `uiMultiplier()` simply starts returning the new value: no transaction, no event. For CRWD the event fired at 01:01 UTC and the switch happened at 13:30 UTC, twelve and a half hours later. An indexer or keeper that applies the new multiplier on the event is wrong for that whole gap.

## 2. The share price and the multiplier move at different moments

The multiplier switches at `effectiveAt`. The share price drops at the next print. Between the two, `last share price × current multiplier` is off by the split ratio: 4× too high for a 4:1 split. That window is what the [Corporate Action Lab](/lab) lets you trigger on testnet.

## 3. Double counting

Robinhood's Chainlink feeds already include the multiplier (they are *total return* prices). Raw equity feeds, and Robinhood's own `/prices` API `bid` and `ask`, do not. Multiply a total-return price by the multiplier and you are off by the multiplier again. On a token whose multiplier is 1.0006 the mistake is invisible, until the next split.

## 4. A closed market is not a stale feed

Equities do not print from Friday's close to Sunday evening. A flat staleness check either rejects every weekend price or accepts a dead feed. See [Market calendar](/concepts/calendar).

## The rule SlateFeed applies

SlateFeed never asks "what is the multiplier now?". It asks: **what multiplier was in force when this price was observed?**

```
U = uiMultiplier()   N = newUIMultiplier()   E = effectiveAt()   t = observedAt   now = block.timestamp

if t >= E:             m = N                        // observed after the switch
elif now < E:          m = U                        // the switch has not happened
else (t < E <= now):   m = snapshot.old if recorded // observed before a switch that has since happened
                       otherwise: STRADDLE, refuse
```

Once the switch has happened the old multiplier can no longer be read from the token. So anyone can call `poke()` on a feed while a change is staged, and the feed records the pre-switch multiplier. The publisher does this automatically. With a snapshot, a straddling price is priced exactly; without one, the feed refuses.

**Corporate-action grace.** A large change (more than `largeChangeBps`, 5% by default: dividends pass, splits do not) also refuses prices observed within `corporateActionGrace` of the switch, 30 minutes by default. The first prints around a split open are unreliable even when the arithmetic is exact.

## Price kinds, declared once

Every source declares an immutable `PriceKind`:

- `RAW_UNDERLYING`: a per-share price. SlateFeed multiplies it.
- `TOTAL_RETURN`: already per token. SlateFeed passes it through.

`SlateFeedFactory.deployCalibrated` refuses to deploy a feed whose answer disagrees with an independent reference by more than a bound. A source declared with the wrong kind is off by the multiplier and never ships.
