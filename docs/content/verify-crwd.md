---
title: Verify CRWD yourself
description: Five checks, no keys, no accounts. Robinhood's own chain and API, Slate's live mainnet feed, then the fork test that came before it.
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

## 4. CRWD's SlateFeed on mainnet

CRWD's SlateFeed is live at [`0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77`](https://robinhoodchain.blockscout.com/address/0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77). Read it like any Chainlink feed:

```bash
curl -s https://rpc.mainnet.chain.robinhood.com -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"to":"0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77","data":"0xfeaf968c"},"latest"]}' \
  | jq -r .result | python3 -c "import sys; r=sys.stdin.read()[2:]; print(int(r[64:128],16)/1e8)"
# the token price in USD, e.g. 1079.9 (Friday's close, 3 Oct)
```

`status()` says whether it will serve that price: `0` is OK, `1` is MARKET_CLOSED (the last price, fresh when the session closed). Its first price, signed Fri 2 Oct 15:04:50 EDT, was $268.105 × 4.000 = **$1,072.42** ([transaction](https://robinhoodchain.blockscout.com/tx/0x0d8a2bde33c69e0ae8f931314a6ebe3dcebf29a1860c268d0ffdb3e30e9cccda)).

## 5. The fork test before deployment

Before the mainnet deploy, this fork test read CRWD's real multiplier from mainnet, submitted a share price signed by three test keys, and checked the token price. It still runs:

```bash
cd contracts
python3 script/rpc_relay.py https://rpc.mainnet.chain.robinhood.com 8548 &
SLATE_FORK=1 SLATE_FORK_URL_rh_mainnet=http://127.0.0.1:8548 \
  forge test --match-test test_crwd_signedPriceTimesRealMultiplier -vv
```

On 1 Oct, $264.98 × 4.000 = **$1,059.92**, the `tokenBid` Robinhood published at the same moment. The relay forwards JSON-RPC through Python's HTTP client, which Cloudflare accepts.
