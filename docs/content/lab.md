---
title: Corporate Action Lab
description: Schedule a split on a Slate test token and watch a naive feed get it wrong while SlateFeed refuses.
---

Robinhood's own tokens cannot be split on demand: `updateMultiplier` needs a role only Robinhood holds. The Lab gives anyone a token they *can* split, priced off the live TSLA share price, with a naive feed beside SlateFeed so the failure is visible.

**Lab tokens are Slate's test tokens, not Robinhood's.** It runs on Robinhood Chain testnet.

## The pieces

| Contract | Address (RH testnet) | Role |
|---|---|---|
| `SlateLabStock` (labTSLA) | `0xfa84823B70F3147656Be84D0C96eA958efA97AeC` | ERC-8056 token. Anyone may schedule a corporate action: multiplier between 0.01× and 100×, effective within a day, one action per 10 minutes |
| `LabSplitSource` | `0xC4aC0Ec0CaA53d0441CFF72d3a66f577825647BB` | The underlying share price: live TSLA ÷ the Lab multiplier in force when it was observed |
| `SlateFeed` (labTSLA) | `0x2B15c4AA73e8D387011e072d046a1B526f987322` | The real thing, with a 5-minute grace |
| `NaiveMultiplierFeed` | `0xb10c89Fe4ad141EB4ad74761958EB99572354ed6` | LAB ONLY: last share price × the multiplier **now** |

`LabSplitSource` exists because real TSLA never splits when a Lab action is scheduled. It makes the underlying split with the token, exactly as a real split moves the share price. A real split's first print comes at the next open, hours later. The Lab models that gap: scheduling freezes the last pre-split print, which stays in force until three minutes after the switch.

## A live run, 2 October 2026

Filmed from the dashboard: a wallet scheduled a 4:1 split 90 seconds ahead ([transaction](https://explorer.testnet.chain.robinhood.com/tx/0x93a3ac5e9cd44f230cecc9b80fc661fc6f93e03b1b10efb0261256e527cac631), 00:56 IST, 1 Oct 19:26 UTC), with TSLA at $356.96:

| | Naive feed | SlateFeed |
|---|---|---|
| Before the switch | $356.96 | $356.96, `OK` |
| The switch (multiplier 1 → 4) | **$1,427.82** (4× wrong) | `CORPORATE_ACTION`, refuses |
| +2:55, first post-split print | $356.93 | `CORPORATE_ACTION`, still refuses |
| +5:15, after the 5-minute grace | $357.75 | **$357.75, `OK`** |

A lending market reading the naive feed would have valued every labTSLA at four times its worth for three minutes. One reading SlateFeed would have paused borrowing for five.

## Try it

Open the dashboard's Lab section, connect a wallet on Robinhood Chain testnet and schedule a split, or call the token directly:

```bash
cast send 0xfa84823B70F3147656Be84D0C96eA958efA97AeC \
  "scheduleCorporateAction(uint256,uint256)" 4000000000000000000 $(( $(date +%s) + 90 )) \
  --rpc-url https://rpc.testnet.chain.robinhood.com --private-key $YOUR_TESTNET_KEY
```

