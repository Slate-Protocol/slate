---
title: Security and limitations
description: What Slate trusts, what it does not, and what is not done yet.
---

**Slate is unaudited hackathon software.** Do not use it to secure real value.

## Trust assumptions

- **Signers.** Prices for tokens without a Chainlink feed come from a 2-of-3 signer set, and today all three keys are ours. On-chain bounds limit the damage: a 0.5% maximum spread between signers, unanimity for moves over 10%, strictly increasing timestamps, and a 60-second future bound. They do not make a colluding majority honest. The set changes only through a 48-hour timelock; [the path to independent signers](/decentralisation) sets out the handover.
- **Robinhood's quote API.** The publisher's source. It is cross-checked against the token's on-chain multiplier, and against Chainlink where Chainlink has the same share price.
- **Robinhood's token contracts.** Slate reads `uiMultiplier`, `newUIMultiplier`, `effectiveAt` and, where present, `oraclePaused`. See [Disclosures](/disclosures) for what those contracts do not enforce.
- **Chainlink.** Where a Chainlink feed exists, Slate passes it through with its own status rules on top.

## What fails closed

Stale prices, paused oracles, prices straddling a multiplier switch, the grace window after a large change, a dead or missing USDG/USD price, and any constituent of a basket in any of those states all make `latestRoundData()` revert. The router reads prices through `latestRoundData()`, so it stops too.

## Known limitations

- **A later multiplier schedule can hide an earlier switch (found by our invariant tests, 4 Oct 2026).** A Robinhood token reports only its latest multiplier change. If a price was observed before switch A, A takes effect, and the token then stages switch B before a newer price arrives, `SlateFeed` can no longer see A and applies A's multiplier to the older price, with status OK or Market closed. *What it could cost:* the size of switch A, on that one price, until the next price lands: up to 2.1% for the adjustments seen on mainnet so far (the [multiplier census](https://app.slate.0xo.in/census)), 4× for a split. *When it can happen:* while the market is open the publisher posts a newer price at least every 30 minutes for CRWD and every 4 hours for the other 19 mainnet feeds, so the window is that long at most; while it is closed the feed serves Friday's price all weekend, and real switches take effect just after the close (around 00:10 UTC), so a second change staged the same weekend would hit it. No mainnet feed is exposed today: all 21 hold a price observed after their token's latest switch (checked at block 79,525,398, 4 Oct). *The fix:* the feed must remember the switches it has seen (record each one in `poke()`, which the publisher already calls every minute, and refuse a price older than the last recorded switch unless it holds that switch's old multiplier), plus a check for switches applied with no staging window. *Why it is not deployed:* it changes `SlateFeed`'s bytecode, so it needs new feeds, a redeploy we cannot fund during the event; it is pinned by `test_knownGap_aLaterScheduleHidesAnEarlierSwitch` and is the first change after judging.

- **No sequencer uptime check yet.** Chainlink's Robinhood Chain directory lists no sequencer-uptime feed to read. A price observed around sequencer downtime is bounded only by `maxAge`.
- **Testnet pools are kept honest by us.** They have no arbitrageurs, so the publisher recenters them. On mainnet the real stock/USDG pools have real arbitrage.
- **No rebalancing.** SLATE-5's composition is fixed at creation; weights drift with prices.
- **Holiday coverage ends in 2028.** After that the calendar treats every weekday as a trading day, which fails closed: an unlisted holiday reads as `STALE`, not `MARKET_CLOSED`.

## Tests

- **170 tests, 0 failing:** 146 unit and fuzz tests (fuzzing at 1,024 runs, 4,096 in CI), 8 stateful invariants and 16 fork tests against live Robinhood Chain mainnet, testnet and Arbitrum One. CI runs them on every push, the fork job included.
- **SignedSource invariants** (mainnet's parameters: 2 of 3, 0.5% spread, unanimity above 10%, 60 s skew; 256 runs × 64 calls each): the source accepts exactly the reports its rules allow, computed independently, and no others; it stores the median of an accepted report; observation times only move forward; only the owner rotates signers, and the quorum is always a majority. Each campaign drives about 4,000 reports (269 accepted, 3,812 refused, 18 split-sized jumps accepted only with every signer) and 840 rotations.
- **SlateFeed invariants** (CRWD's mainnet configuration, the real calendar): whenever it serves a price, the answer is the share price × the multiplier truly in force when that price was observed, checked against a full multiplier history the token itself does not keep; it serves only with a serving status, never while paused, never a stale price with the market open. Each campaign serves about 3,040 prices (195 with the market closed) and refuses 1,940 straddles, 430 corporate actions and 2,390 stale prices across 2,700 scheduled switches. They found one gap, disclosed above; it is counted apart and every other wrong multiplier fails the run.
- **StockLender invariants:** cash matches the books, totals equal their parts, no risk without a price.
