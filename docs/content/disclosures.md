---
title: Disclosures
description: Two statements in official documentation that the chain contradicts, with the evidence.
---

While building Slate we found two statements in official documentation that the deployed contracts and live data contradict. Both matter to anyone integrating Robinhood stock tokens, so we publish them here with the evidence and how to check it. Both quotes were re-read on the live pages on 2 October 2026.

## 1. "Every Stock Token has a live Chainlink price feed"

**Source:** Robinhood Chain documentation, [docs.robinhood.com/chain/stock-tokens](https://docs.robinhood.com/chain/stock-tokens/):

> Onchain prices — every Stock Token has a live Chainlink price feed, so your contracts can read prices directly onchain.

**What the chain shows:** on 1 October 2026, Robinhood's own asset registry listed **194** stock tokens. Chainlink's feed directory for Robinhood Chain mainnet has feeds for **35** of them. **159 have none**, including CRWD, whose multiplier is 4.000 after a 4:1 split.

```bash
# Stock tokens in Robinhood's registry
curl -s https://api.robinhood.com/rhj/assets | jq '.assets | length'

# Chainlink stock feeds on Robinhood Chain mainnet (named "Robinhood <SYMBOL> / USD")
curl -s https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json \
  | jq '[.[] | select(.name | startswith("Robinhood"))] | length'

# CRWD has none
curl -s https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json \
  | jq '[.[] | select(.name | test("CRWD"))] | length'
```

**Why it matters:** an integrator who takes the sentence at face value will look for a feed that does not exist. Worse, they may build their own price from Robinhood's `/prices` API, whose documentation describes `bid` and `ask` as "not multiplier-adjusted". For a token like CRWD that price is off by 4×. Pricing those tokens correctly is what Slate is for.

## 2. "The token contract enforces two update paths"

**Source:** Chainlink documentation, [docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood](https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood):

> Robinhood's on-chain token contract enforces two update paths: Small updates (no price discontinuity): Applied immediately via automated processes. These handle routine dividend reinvestments. Large updates (price discontinuity): Requires a scheduled pause window and manual confirmation before unpause. These handle major corporate actions like stock splits.

**What the code shows:** the verified Stock implementation on Robinhood Chain mainnet (`0xb35490d6f9163DE4F80d88dc75c3516eb64C5aE2`, behind every stock token's beacon) has a single update path for every size of change:

```solidity
function updateMultiplier(uint256 newMultiplier, uint256 effectiveAt_)
    public
    onlyNotPaused
    onlyRole(MULTIPLIER_UPDATER_ROLE)
{
    _updateUIMultiplier(newMultiplier, effectiveAt_);
}

function _updateUIMultiplier(uint256 newMultiplier, uint256 effectiveAt_) internal virtual {
    require(newMultiplier > 0, "New multiplier must be greater than 0");
    require(effectiveAt_ >= block.timestamp, "Effective time must not be in the past");
    ERC20ScaledUIStorage storage $ = _getERC20ScaledUIStorage();
    uint256 oldMultiplier = uiMultiplier();
    $._multiplier = oldMultiplier;
    $._newMultiplier = newMultiplier;
    $._effectiveAt = effectiveAt_;
    emit UIMultiplierUpdated(oldMultiplier, newMultiplier, effectiveAt_);
}
```

There is **no size check** that separates small from large changes, and **no precondition on `oraclePaused()`**. `onlyNotPaused` is the *token* pause, not the oracle pause, and `oraclePaused` is a plain boolean that nothing in the token reads. A 4:1 split goes through the same function as a 0.01% dividend reinvestment, with or without a pause window.

**Why it matters:** continuity across a split depends entirely on Robinhood's operators calling `pauseOracle()` before staging the change. Nothing on-chain enforces it. If that step is ever missed, Chainlink's adapter, which multiplies the stream price by `uiMultiplier()` off-chain, could publish a price that is briefly 4× or ¼× for one side of the switch. We have found no instance of this happening, and nobody outside Robinhood can trigger it. Integrators should still not rely on the contract to prevent it. SlateFeed does not: it reads the multiplier's timing itself and refuses to price across a large switch. See [The multiplier problem](/concepts/multipliers).

## Status

Published here on 2 October 2026. Both are documentation issues, not exploits. If either team corrects their page, this one will say so.
