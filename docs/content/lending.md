---
title: Lending against a stock token
description: StockLender, a minimal lending market that prices collateral through Slate feeds the way any other protocol would.
---

Slate exists so that protocols can use stock tokens: lend against them, hold them in vaults, put them in indices. `StockLender` is the proof. It is a minimal over-collateralised lending market, written the way a third party would write one: it prices collateral through Slate feeds with nothing but Chainlink's `AggregatorV3Interface.latestRoundData()`. It holds no Slate code and has no special access.

It is a proof, not a product: one loan asset valued at $1, no interest, isolated positions per collateral token, markets listed by the owner, and bad debt is not socialised.

## The whole integration

The lender's price read is the integration. A SlateFeed that refuses (a split in progress, a stale or paused oracle, a closed market past the lender's own bound) reverts with `FeedUnavailable`, and the lender treats any revert as "no price":

```solidity
try market.feed.latestRoundData() returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80) {
    if (answer <= 0 || updatedAt + market.maxAge < block.timestamp) return (false, 0, updatedAt);
    return (true, uint256(answer), updatedAt);
} catch {
    return (false, 0, 0);
}
```

With no price, the lender will not lend, will not release collateral against debt, and will not liquidate. Repaying and depositing always work.

## Live on Robinhood Chain testnet

| | Address |
|---|---|
| `StockLender` (TESTUSD loans; TSLA, AMZN, AMD, PLTR, NFLX, labTSLA) | [`0xb25712c148B676941f160C30a9F57B1551118a20`](https://explorer.testnet.chain.robinhood.com/address/0xb25712c148B676941f160C30a9F57B1551118a20) |
| `StockLender` on the naive labTSLA feed, LAB ONLY | [`0x231D8706419162E3CD79fE2DFD2aa2152536CCF3`](https://explorer.testnet.chain.robinhood.com/address/0x231D8706419162E3CD79fE2DFD2aa2152536CCF3) |

Each market lends up to 50% of the collateral's value and liquidates above 65%, with a 5% liquidation bonus. The dashboard's Lend section drives it from a wallet.

**A loan against Robinhood's NFLX token**, 2 October 2026: 0.58 NFLX deposited, NFLX priced at $67.50 a token through its SlateFeed, and 19.57 TESTUSD borrowed, one cent under the limit ([transaction](https://explorer.testnet.chain.robinhood.com/tx/0xefa1a7ce6287dcefb36d1d35f6a7282845ae3efe343dd26f7499f01464e317a8)). The `Borrowed` event records the price and the time it was observed.

## What a split does to a lender

The same contract, deployed twice on labTSLA: once on its SlateFeed, once on the Lab's naive feed (last share price × the multiplier now). One labTSLA went into each, and a 4:1 split was scheduled from the dashboard ([transaction](https://explorer.testnet.chain.robinhood.com/tx/0xe77756e3e8ed97dc3402b661bc4d1284dab71328d8c5948811c54bd421251078)). At the switch:

| | Slate-fed lender | Naive-fed lender |
|---|---|---|
| 1 labTSLA valued at | no price: borrowing paused | $1,484.94, four times its worth |
| Lent | nothing | 742.47 TESTUSD ([transaction](https://explorer.testnet.chain.robinhood.com/tx/0xdfeb0d58be87ee32a303c1a7980ea75cc8ca9265958949279a48069c4af8f57a)) |
| After the post-split price | lends again, up to half of $372.94 | owes 742.47 against collateral worth $372.94 |

The naive-fed lender is left with a loan worth twice its collateral, and liquidating it cannot recover the difference. A reverse split does the opposite: the naive feed prices the token at a quarter of its worth, and the naive-fed lender liquidates healthy loans. The unit tests cover both directions with the same two lenders.

## On mainnet

`StockLender` is live on Robinhood Chain mainnet at [`0x66770067Bf690a8eAcA95aCAB896659835704F52`](https://robinhoodchain.blockscout.com/address/0x66770067Bf690a8eAcA95aCAB896659835704F52). It takes Paxos USDG as the loan asset and lists CRWD on its SlateFeed: 40% loan-to-value, liquidation at 60%. CRWD has no Chainlink feed, so no other lender can price it. At deployment, `quote(CRWD, 1 token)` valued one CRWD at $1,072.42, with up to 428.97 USDG borrowable. No USDG is supplied yet, so it is read-only for now. CRWD can be bought on-chain through Uniswap v4: the USDG/CRWD pool (2.945% fee) quoted 0.01 CRWD at 10.81 USDG on 3 Oct. A fork test borrows real USDG against the real CRWD token:

```bash
cd contracts && python3 script/rpc_relay.py https://rpc.mainnet.chain.robinhood.com 8548 &
SLATE_FORK=1 SLATE_FORK_URL_rh_mainnet=http://127.0.0.1:8548 \
  forge test --match-test test_usdgLoanAgainstRealCrwd -vv
```

## Tests

- **Unit:** limits, exact borrow and liquidation arithmetic, staleness, a reverting feed blocking everything but repay and deposit, and the split in both directions against a naive-fed twin.
- **Invariant:** random sequences of every action, price moves, feed outages and time passing. The books always balance, totals equal their parts, and no borrow, withdrawal or liquidation ever goes through without a usable price or leaves a position over its limit.
- **Fork:** against Slate's live TSLA feed on testnet, and against the real CRWD token with real USDG on mainnet.
