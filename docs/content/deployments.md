---
title: Deployments
description: Every Slate contract, by network. The canonical list is deployments.json.
---

The canonical, machine-readable list is [`deployments/deployments.json`](https://github.com/Slate-Protocol/slate/blob/main/deployments/deployments.json). The dashboard, the landing page and the publisher all read it.

## Robinhood Chain testnet (46630): live

Every contract is verified on the [explorer](https://explorer.testnet.chain.robinhood.com).

| Contract | Address |
|---|---|
| SlateFeed TSLA | `0x5A9cD81b257a073802E9A039e7877A604964aa84` |
| SlateFeed AMZN | `0x368A8E2D17271E55f8378BaB2424929b249C5667` |
| SlateFeed AMD | `0x72c0cba3De702b739E3455120D0F1bC7D6BEbAc8` |
| SlateFeed PLTR | `0xE880669F55783Bb343277dD35106d5Eb736De17A` |
| SlateFeed NFLX | `0x0c465299dD1C1E242e29a148b6aF9EbE8Ca7E2c0` |
| SLATE-5 basket | `0xed509B491F58D19eB489aC7C01c7a4bcBCf4e1bf` |
| SLATE-5 NAV feed | `0x8E2b6C63463DCf51b307811dB41bd60d7987608D` |
| SlateRouter | `0x3de24B7AEaD51D137c6C6B2c2820587108FA05Bd` |
| UniswapV4Venue | `0xCd1A61CA1cD4a4547a06e04A915535Ac04F8529B` |
| SlateV4Seeder (testnet pools) | `0xD2ECFBf050F2834722F3cC57E49b258A68851eF0` |
| SignedSource | `0x8B27311a3493a85E063f97e4bB59cf3a22aEA507` |
| SolidityReportVerifier | `0xd921ad145FA22b0C8A4846d234857FBEFFDfDdc6` |
| TimelockController (48 h, owns SignedSource) | `0xFc42883Ae9ac9FeCE9A3b656f30D356775Fe2270` |
| USMarketCalendar | `0xf0b57272f1D69083019E8953B82bC128002D7526` |
| SlateFeedFactory | `0xb9b82feE5926C74F5497C7571770d1532E8C9118` |
| TESTUSD (testnet stand-in for USDG, not USDG) | `0x239f410D4D2152ba890F378f6B4Aa103B9ea7FEF` |
| Lab: labTSLA | `0xfa84823B70F3147656Be84D0C96eA958efA97AeC` |
| Lab: SlateFeed labTSLA | `0x2B15c4AA73e8D387011e072d046a1B526f987322` |
| Lab: LabSplitSource | `0xC4aC0Ec0CaA53d0441CFF72d3a66f577825647BB` |
| Lab: NaiveMultiplierFeed | `0xb10c89Fe4ad141EB4ad74761958EB99572354ed6` |

Stylus benchmark contracts: SlateVerifier (Rust) `0x0819e35fd1ccccabb15a100dbb8315f04f1f093b`, Solidity reference `0x1015EddD8776275446E23469c16F85E1ec6b5131`.

## Robinhood Chain mainnet (4663): not deployed yet

Read-only SlateFeeds are scripted and dry-run: CRWD over signed prices, AAPL over Chainlink's total-return feed, and both re-quoted in USDG. They are not deployed yet. Until they are, nothing Slate publishes claims a live mainnet feed. The CRWD figures in these docs come from fork tests against the live token.

## Arbitrum One (42161): not deployed yet

The Corporate Action Lab over Chainlink's raw TSLA feed is scripted and dry-run, and not deployed yet.

## Deploying it yourself

```bash
cd contracts
forge script script/Deploy.s.sol --sig "testnetCore()"   --rpc-url rh_testnet --broadcast --private-key $KEY
forge script script/Deploy.s.sol --sig "testnetMarket()" --rpc-url rh_testnet --broadcast --private-key $KEY
python3 script/merge_deployments.py   # folds deployments/<chainId>.json into deployments.json
```

`testnetMarket()` reads live prices from the feeds, so the publisher must be running between the two steps.
