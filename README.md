<p align="center"><img src="brand/logo-C-tick.svg" alt="Slate" height="56"></p>

# Slate

[![ci](https://github.com/Slate-Protocol/slate/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Slate-Protocol/slate/actions/workflows/ci.yml)

**195 stock tokens on Robinhood Chain, 35 Chainlink feeds. Slate prices the other 160.**

## CRWD, the case in one token

CrowdStrike's stock token on Robinhood Chain mainnet (`0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931`) went through a 4:1 split on 2 July 2026. Its `uiMultiplier()` is now `4e18`: one token is four shares. It has **no Chainlink feed**, so nothing on-chain can price it, and anything that pairs the share price with the raw balance is off by 4×.

Slate's `SlateFeed` takes a signed share price and the token's on-chain multiplier, and returns the token price. In our fork test against the live token, a share price of $264.98 gives **$1,059.92**. That is exactly Robinhood's own `tokenBid` for CRWD at the same moment.

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

Slate's router bought 0.1 AAPL with **USDG** through the live AAPL/USDG Uniswap pool on Robinhood Chain mainnet (`0xAae0d815EE56e4092a5E5C2911E676Fea50B2d6D`), on a fork. It paid **32.79 USDG against a fair value of 32.71 USDG** (Chainlink AAPL × Chainlink USDG/USD), which is inside its 3% band, so the router accepted the route. The same check refuses a third-party TSLA pool on testnet that prices TSLA at $0.0675 against $354.11.

```bash
cd contracts && python3 script/rpc_relay.py https://rpc.mainnet.chain.robinhood.com 8548 &
SLATE_FORK=1 SLATE_FORK_URL_rh_mainnet=http://127.0.0.1:8548 \
  forge test --match-test test_aaplUsdgPool_createsWithinTheBand -vv
```

## What Slate is

A multiplier-correct, fail-closed pricing layer for Robinhood stock tokens (ERC-8056), and an in-kind basket token built on it. Two things set it apart:

1. **It prices the 160 stock tokens that have no Chainlink feed.**
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
