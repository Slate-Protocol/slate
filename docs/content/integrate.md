---
title: Integrate in five lines
description: Read any Slate feed fail-closed with @slate-protocol/contracts, the interfaces and a small helper.
---

To try a feed before writing code, paste its address into the [integration playground](https://app.slate.0xo.in/playground): it shows what `latestRoundData()` returns and gives you this snippet with the address filled in.

Every Slate feed is a Chainlink `AggregatorV3Interface`, so code that reads Chainlink already reads Slate. The integration package adds the one thing that differs: a Slate feed refuses, by reverting, rather than serve a price it cannot vouch for. `SlatePrice.tryRead` turns that refusal into `ok = false`, so your protocol pauses what needs a price instead of guessing.

```solidity
import {AggregatorV3Interface, SlatePrice} from "@slate-protocol/contracts/SlatePrice.sol";

AggregatorV3Interface feed = AggregatorV3Interface(slateFeed);
(bool ok, uint256 price,,) = SlatePrice.tryRead(feed, 3 days);
if (!ok) revert("no price: pause, don't guess");
uint256 usd = SlatePrice.value(amount, 18, price, 8, 6);
```

- `tryRead` returns `ok = false` when the feed refuses (a split in progress, a stale or paused oracle) or its price is older than your bound. The price has 8 decimals.
- With no price, stop: pause what needs one. Never fall back to a guess.
- `value` converts `amount` tokens at `price` into 6-decimal dollars.

`amount` is the token's raw ERC-20 balance: a Slate price is already per token, the share price times the token's multiplier.

## Install

**Foundry**, from GitHub:

```bash
forge install Slate-Protocol/slate
echo '@slate-protocol/contracts/=lib/slate/packages/contracts/src/' >> remappings.txt
```

**npm** (`@slate-protocol/contracts`, publication pending): map `@slate-protocol/contracts/=node_modules/@slate-protocol/contracts/src/`.

## What is in it

- **`SlatePrice.tryRead(feed, maxAge)`** returns `(ok, price, updatedAt, reason)`. `reason` is `REFUSED` (the feed reverted), `NON_POSITIVE`, or `TOO_OLD` (older than your `maxAge`).
- **`SlatePrice.read(feed, maxAge)`** does the same, but reverts with `NoPrice(feed, reason)`.
- **`SlatePrice.status(feed)`** returns a SlateFeed's own status and quote, which never revert: what it would serve, and why it will or won't. See [Feed statuses](/concepts/statuses).
- **`SlatePrice.value(amount, tokenDecimals, price, feedDecimals, outDecimals)`** is amount × price in any decimals, at full precision, rounded down.
- **`interfaces/`** holds `AggregatorV3Interface`, `ISlateFeed` (`FeedStatus`, `Quote`, `FeedUnavailable`) and `IERC8056`.
- **`abi/`** has the same interfaces as JSON ABIs, for viem, ethers and other off-chain readers.

`maxAge` is your bound, not Slate's. A Slate feed already refuses a price that is stale while its market is open, so `maxAge` only decides how long you trust a closed-market price: three days covers a weekend.

## Tested as you would use it

Slate's own test suite imports the package through `@slate-protocol/contracts/…`. It runs the five lines above against a real `SlateFeed`, through a split, and fuzzes `value` against OpenZeppelin's `mulDiv`. A fresh Foundry project that installs from GitHub reads Slate's live TSLA feed on Robinhood Chain testnet with the same five lines.

For a complete integration, see [Lending against a stock token](/lending): a lending market that prices collateral through Slate feeds.
