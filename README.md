<p align="center"><img src="brand/logo-C-tick.svg" alt="Slate" height="56"></p>

# Slate

[![ci](https://github.com/Slate-Protocol/slate/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Slate-Protocol/slate/actions/workflows/ci.yml) · [Docs](https://docs.slate.0xo.in) · [Dashboard](https://app.slate.0xo.in)

**Nearly 200 stock tokens on Robinhood Chain. 35 Chainlink feeds. Slate prices the rest.**

On 1 Oct 2026 Robinhood's registry listed 194 stock tokens and Chainlink had feeds for 35 of them. Recount any time: `curl -s https://api.robinhood.com/rhj/assets | jq '.assets | length'`, against `curl -s https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json | jq '[.[] | select(.name | startswith("Robinhood"))] | length'`.

**And it is not one token.** At mainnet block 79,510,181, **45 of the 194 stock tokens have a multiplier other than 1, and 32 of those have no Chainlink feed.** 36 of the 45 changed in the last 30 days. A price that ignores the multiplier is 75% low on CRWD and up to 2.10% low on the rest. [Live census](https://app.slate.0xo.in/census) · `node dashboard/scripts/multiplier-census.mjs`.

## CRWD, the case in one token

CrowdStrike's stock token on Robinhood Chain mainnet (`0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931`) went through a 4:1 split on 2 July 2026. Its `uiMultiplier()` is now `4e18`: one token is four shares. It has **no Chainlink feed**, so nothing on-chain can price it, and anything that pairs the share price with the raw balance is off by 4×.

Slate's `SlateFeed` takes a signed share price and the token's on-chain multiplier, and returns the token price. **CRWD's SlateFeed is live on Robinhood Chain mainnet** ([`0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77`](https://robinhoodchain.blockscout.com/address/0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77)). Its first price, signed Fri 2 Oct 15:04:50 EDT, was a share price of $268.105 times 4.000: **$1,072.42** ([transaction](https://robinhoodchain.blockscout.com/tx/0x0d8a2bde33c69e0ae8f931314a6ebe3dcebf29a1860c268d0ffdb3e30e9cccda)). In the earlier fork test against the same token, a share price of $264.98 gave $1,059.92, exactly Robinhood's own `tokenBid` at that moment.

Check every part of that yourself. No keys, no accounts:

```bash
# 1. CRWD's multiplier on Robinhood Chain mainnet: prints 4.0
curl -s https://rpc.mainnet.chain.robinhood.com -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"to":"0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931","data":"0xa60bf13d"},"latest"]}' \
  | jq -r .result | python3 -c "import sys; print(int(sys.stdin.read(),16)/1e18)"

# 2. Robinhood prices one CRWD token at 4x the share price: tokenBid = 4 * bid
curl -s https://api.robinhood.com/rhj/prices/CRWD | jq '.quotes[0] | {bid, tokenBid}'

# 3. Chainlink has no CRWD feed on Robinhood Chain: prints 0
curl -s https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json \
  | jq '[.[] | select(.name | test("CRWD"))] | length'

# 4. SlateFeed against the live token (Foundry; the relay works around Cloudflare blocking Foundry's client)
cd contracts && python3 script/rpc_relay.py https://rpc.mainnet.chain.robinhood.com 8548 &
SLATE_FORK=1 SLATE_FORK_URL_rh_mainnet=http://127.0.0.1:8548 \
  forge test --match-test test_crwd_signedPriceTimesRealMultiplier -vv
```

## AAPL with real USDG, through a real pool

Slate's router bought 0.1 AAPL with **USDG** through the live AAPL/USDG Uniswap pool on Robinhood Chain mainnet (`0xAae0d815EE56e4092a5E5C2911E676Fea50B2d6D`), on a fork. Pinned to mainnet block 78,690,791 (3 Oct 2026), it paid **33.36 USDG against a fair value of 33.38 USDG** (Chainlink AAPL × Chainlink USDG/USD), inside its 3% band, so the router accepted the route. The same check refuses a third-party TSLA pool on testnet that prices TSLA at $0.0675 against $354.11.

```bash
cd contracts && python3 script/rpc_relay.py https://rpc.mainnet.chain.robinhood.com 8548 &
SLATE_FORK=1 SLATE_FORK_URL_rh_mainnet=http://127.0.0.1:8548 \
  forge test --match-test test_aaplUsdgPool_createsWithinTheBand -vv
```

## Live now

On **Robinhood Chain mainnet** (chain 4663), since 3 Oct 2026: twenty SlateFeeds for stock tokens with no Chainlink feed (CRWD, NFLX, AVGO, LLY, COST, BA, JNJ, IBM, PFE, F, RIVN, SNAP, RBLX, RDDT, HIMS, SHOP, LMT, GLD, AMC, CCL), AAPL over Chainlink's total-return feed, CRWD and AAPL quoted in USDG, SignedSource `0xf0b57272f1D69083019E8953B82bC128002D7526` owned by a 48-hour timelock, and StockLender, a USDG lender that values CRWD through its SlateFeed. All verified on Sourcify. Addresses: [docs: Deployments](https://docs.slate.0xo.in/deployments).

On **Robinhood Chain testnet** (chain 46630), with prices signed 24/5 by three keys and relayed by the publisher on Railway ([status](https://publisher-production-891d.up.railway.app/)). Every contract is verified on the [explorer](https://explorer.testnet.chain.robinhood.com). The full list is in [`deployments/deployments.json`](deployments/deployments.json).

| Contract | Address |
|---|---|
| SlateFeed TSLA / AMZN / AMD / PLTR / NFLX | `0x5A9c…aa84` / `0x368A…5667` / `0x72c0…bAc8` / `0xE880…e17A` / `0x0c46…E2c0` |
| SLATE-5 basket | `0xed509B491F58D19eB489aC7C01c7a4bcBCf4e1bf` |
| SLATE-5 NAV feed (AggregatorV3) | `0x8E2b6C63463DCf51b307811dB41bd60d7987608D` |
| SlateRouter (TESTUSD, 3% band) | `0x3de24B7AEaD51D137c6C6B2c2820587108FA05Bd` |
| SignedSource (3 signers, 2 needed, 48 h timelock owner) | `0x8B27311a3493a85E063f97e4bB59cf3a22aEA507` |
| Corporate Action Lab: labTSLA / its SlateFeed | `0xfa84823B70F3147656Be84D0C96eA958efA97AeC` / `0x2B15c4AA73e8D387011e072d046a1B526f987322` |
| StockLender (a lending market built on Slate feeds) | `0xb25712c148B676941f160C30a9F57B1551118a20` |

```bash
# SLATE-5's NAV per share, 8 decimals, through the standard Chainlink interface
cast call 0x8E2b6C63463DCf51b307811dB41bd60d7987608D "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url https://rpc.testnet.chain.robinhood.com
```

In the Lab, anyone can schedule a split on labTSLA. In our filmed run of a 4:1 split on 2 Oct ([transaction](https://explorer.testnet.chain.robinhood.com/tx/0x93a3ac5e9cd44f230cecc9b80fc661fc6f93e03b1b10efb0261256e527cac631)), the naive feed read **$1,427.82** (4 × TSLA's $356.96) the moment the multiplier switched, while SlateFeed reported `CORPORATE_ACTION` and refused. Three minutes later the first post-split print brought the naive feed back to $356.93; SlateFeed held through its five-minute grace and then served **$357.75**, `OK`.

## Integrate in five lines

Every Slate feed is a Chainlink `AggregatorV3Interface`. [`@slate-protocol/contracts`](packages/contracts) adds the interfaces and `SlatePrice`, which turns a Slate refusal into `ok = false` so your protocol pauses instead of guessing:

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

Install from npm, [`@slate-protocol/contracts`](https://www.npmjs.com/package/@slate-protocol/contracts): `npm install @slate-protocol/contracts` with the remapping `@slate-protocol/contracts/=node_modules/@slate-protocol/contracts/src/`. Or with Foundry: `forge install Slate-Protocol/slate` and `@slate-protocol/contracts/=lib/slate/packages/contracts/src/`. [Docs: Integrate in five lines](https://docs.slate.0xo.in/integrate).

**Try a feed in a browser first:** [app.slate.0xo.in/price/CRWD](https://app.slate.0xo.in/price/CRWD) returns any Slate feed as JSON (price, multiplier, observedAt, status, feed address), read from the chain on every request. `/price` lists them all. [Docs: Price API](https://docs.slate.0xo.in/api).

## A loan against a stock token

Slate is for protocols that want to use stock tokens. [`StockLender`](contracts/src/examples/StockLender.sol) is a minimal lending market written the way any third party would write one: it prices collateral through Slate feeds with nothing but `latestRoundData()`, with no Slate code and no special access. When a feed refuses, it stops lending and liquidating; repaying always works.

- **Live on Robinhood Chain mainnet: a lender for a token Chainlink cannot price.** [`StockLender`](https://robinhoodchain.blockscout.com/address/0x66770067Bf690a8eAcA95aCAB896659835704F52) takes Paxos USDG as the loan asset and lists the real CRWD token, priced through CRWD's SlateFeed. CRWD has no Chainlink feed, so no other lender on the chain can value it. At block 78,972,600 (3 Oct 2026, market closed) `quote(CRWD, 1 token)` returned **$1,079.90** with a borrow limit of **431.96 USDG** (40% loan-to-value). Anyone can read it:

  ```bash
  cast call 0x66770067Bf690a8eAcA95aCAB896659835704F52 "quote(address,uint256)(bool,uint256,uint256)" \
    0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931 1000000000000000000 --rpc-url https://rpc.mainnet.chain.robinhood.com
  # true, 1079900000 (= $1,079.90), 431960000 (= 431.96 USDG)
  ```
- **A loan against Robinhood's NFLX token** on testnet: 0.58 NFLX deposited, priced at $67.50 a token through its SlateFeed, 19.57 TESTUSD borrowed ([transaction](https://explorer.testnet.chain.robinhood.com/tx/0xefa1a7ce6287dcefb36d1d35f6a7282845ae3efe343dd26f7499f01464e317a8)).
- **The same lender on a naive feed**, through a live 4:1 Lab split: at the switch it valued one labTSLA at $1,484.94 and lent 742.47 TESTUSD against a token worth $372.94 ([transaction](https://explorer.testnet.chain.robinhood.com/tx/0xdfeb0d58be87ee32a303c1a7980ea75cc8ca9265958949279a48069c4af8f57a)). The Slate-fed lender paused borrowing until the post-split price landed.
- **On a fork of mainnet**, the lender borrows real Paxos USDG against the real CRWD token, which has no Chainlink feed: `forge test --match-test test_usdgLoanAgainstRealCrwd`.

Details: [docs: Lending against a stock token](https://docs.slate.0xo.in/lending).

## Slate against Chainlink, live

For the 35 Robinhood stock tokens Chainlink covers on mainnet, [app.slate.0xo.in/accuracy](https://app.slate.0xo.in/accuracy) puts Chainlink's answer beside Slate's signed price, times the on-chain multiplier, with the median and the worst-case gap. Your browser verifies every signature against Slate's on-chain signer set and reads Chainlink and the multipliers from mainnet itself. Agreement where Chainlink exists is the evidence for the tokens where it does not.

## What Slate is

A multiplier-correct, fail-closed pricing layer for Robinhood stock tokens (ERC-8056), and an in-kind basket token built on it. Two things set it apart:

1. **It prices the stock tokens that have no Chainlink feed** (159 of 194 on 1 Oct 2026).
2. **The basket's NAV is itself a drop-in `AggregatorV3Interface` feed**, so a Slate share can be priced by any protocol that reads Chainlink.

Prices can be quoted in USD or in **Paxos USDG**, through the USDG/USD Chainlink feed on Robinhood Chain.
On testnet, **TESTUSD** (Slate Test Dollar) is the testnet stand-in for Paxos USDG. Not USDG.

### Why a stock-token price is harder than it looks

- **The multiplier changes silently.** `UIMultiplierUpdated` fires when a change is *staged*; `uiMultiplier()` switches later by `block.timestamp`. `SlateFeed` pairs every share price with the multiplier in force *when the price was observed*, records staged switches through a permissionless `poke()`, and holds the feed through a grace window after a split.
- **Double counting.** Robinhood's own Chainlink feeds already include the multiplier. `SlateFeed` never applies it to them again, and its factory refuses to deploy a feed that disagrees with a reference.
- **Markets close.** An on-chain US market calendar (NYSE holidays and early closes through 2028, New York daylight saving for any year) tells "closed" apart from "stale".
- **Issuers pause.** Robinhood's `oraclePaused()` flag is advisory on-chain; Slate enforces it.

## Prior art, named plainly

- **[Prashant-thakur77/Strike](https://github.com/Prashant-thakur77/Strike)** guards Chainlink stock feeds in its `SafeStockFeed` library: staleness, both pause flags, corporate actions, and an on-chain market calendar. **Strike's market calendar was better than our first version**, which only knew weekends. We adopted the same approach: holidays, early closes and daylight saving, on-chain.
- **[nirholas/three.ws](https://github.com/nirholas/three.ws)** ships an in-kind basket vault on Robinhood Chain and deliberately keeps prices off-chain ("prices are a display concern, computed off-chain"). Slate's in-kind create/redeem follows the same price-independent principle.

Strike builds on Chainlink feeds that already exist, and three.ws has no on-chain price at all. **Neither prices a stock token that has no Chainlink feed, and neither publishes a basket NAV as a feed.** Those are the two things Slate adds.

## Tests, and the gap they found

170 tests, 0 failing: 146 unit and fuzz tests, 16 fork tests against live Robinhood Chain mainnet, testnet and Arbitrum One, and 8 stateful invariants. The SignedSource invariants check, against independently computed rules, that it accepts exactly the reports those rules allow; the SlateFeed invariants check that every price it serves is the share price × the multiplier truly in force when that price was observed. That suite found one real gap in the deployed feed: a later multiplier schedule can hide an earlier switch, and an older price then gets the newer multiplier (up to 2.1% on the adjustments seen so far, 4× on a split). No mainnet feed is exposed today; the fix needs a redeploy. What it is, what it could cost and the fix: [Security and limitations](https://docs.slate.0xo.in/security).

## Repository

| Path | What |
|---|---|
| `contracts/` | Solidity (Foundry): `SlateFeed`, price sources, `USMarketCalendar`, USDG quoting, basket, NAV feed, router |
| `stylus/` | Rust (Arbitrum Stylus): `SlateVerifier`, the signed-report verifier, benchmarked against Solidity |
| `publisher/` | Signer and relayer service for off-chain share prices |
| `dashboard/` | Dashboard app |
| `docs/` | Documentation site |
| `brand/` | Logo, favicon, social images |

```bash
cd contracts && forge build && forge test          # unit and fuzz tests
cd stylus && cargo test                            # Stylus verifier
```

**A pool is not a price.** `SlateRouter` buys a basket's constituents with USDG (TESTUSD on testnet) and refuses any leg whose fill is more than 3% from that stock's Slate price. On Robinhood Chain testnet, a third-party Uniswap v3 clone sells TSLA at $0.0675 against $354.11, which is 99.98% off the market. The router refuses that route on a fork of the live pool. Through the official v4 PoolManager and, on mainnet, the real AAPL/USDG pool, it fills inside the band:

```bash
cd contracts && SLATE_FORK=1 forge test --match-contract RobinhoodTestnetRouterForkTest -vv
```

**We measured Stylus and it lost.** The Rust signed-report verifier matches the Solidity one on 307 live test reports, but costs 10–61% more gas at the signer counts Slate uses, so Slate ships the Solidity verifier. Numbers and method: [`stylus/BENCHMARK.md`](stylus/BENCHMARK.md).

> Status: under active development for the Arbitrum Open House Singapore Online Buildathon. Unaudited.

## License

MIT
