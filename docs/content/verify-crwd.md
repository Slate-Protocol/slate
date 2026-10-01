---
title: Verify CRWD yourself
description: Four commands, no keys, no accounts. Robinhood's own chain and API, then Slate's fork test.
---

CRWD is the case for Slate in one token: a real Robinhood stock token on mainnet, a 4:1 split behind it, and no Chainlink feed. Check each claim yourself.

## 1. The multiplier is 4.000

```bash
cast call 0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931 "uiMultiplier()(uint256)" \
  --rpc-url https://rpc.mainnet.chain.robinhood.com
# 4000000000000000000 [4e18]
```

Robinhood Chain's public RPC sits behind Cloudflare, which sometimes refuses Foundry's HTTP client. `curl` always works:

```bash
curl -s https://rpc.mainnet.chain.robinhood.com -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"to":"0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931","data":"0xa60bf13d"},"latest"]}' \
  | jq -r .result | python3 -c "import sys; print(int(sys.stdin.read(),16)/1e18)"
# 4.0
```

The multiplier switched on 2 July 2026 at 13:30 UTC (`effectiveAt() = 1782999000`).

## 2. Robinhood prices a token at four shares

```bash
curl -s https://api.robinhood.com/rhj/prices/CRWD | jq '.quotes[0] | {bid, tokenBid}'
```

`tokenBid` is exactly `bid × 4`. Robinhood's API applies the multiplier in fields its documentation does not describe.

## 3. Chainlink has no CRWD feed

```bash
curl -s https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json \
  | jq '[.[] | select(.name | test("CRWD"))] | length'
# 0
```

## 4. SlateFeed against the live token

The fork test reads CRWD's real multiplier from mainnet, submits a share price signed by three test keys, and checks the token price:

```bash
cd contracts
python3 script/rpc_relay.py https://rpc.mainnet.chain.robinhood.com 8548 &
SLATE_FORK=1 SLATE_FORK_URL_rh_mainnet=http://127.0.0.1:8548 \
  forge test --match-test test_crwd_signedPriceTimesRealMultiplier -vv
```

$264.98 × 4.000 = **$1,059.92**, the `tokenBid` Robinhood published at the same moment. The relay forwards JSON-RPC through Python's HTTP client, which Cloudflare accepts.
