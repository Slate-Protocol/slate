---
title: Deployments
description: Every Slate contract, by network. The canonical list is deployments.json.
---

The canonical, machine-readable list is [`deployments/deployments.json`](https://github.com/Slate-Protocol/slate/blob/main/deployments/deployments.json). The dashboard, the landing page and the publisher all read it.

## Web

| Site | Address |
|---|---|
| Landing | [slate.0xo.in](https://slate.0xo.in) |
| Dashboard | [app.slate.0xo.in](https://app.slate.0xo.in) |
| Docs | [docs.slate.0xo.in](https://docs.slate.0xo.in) |
| Publisher status | [publisher-production-891d.up.railway.app](https://publisher-production-891d.up.railway.app/) |

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
| StockLender (lending on Slate feeds, TESTUSD loans) | `0xb25712c148B676941f160C30a9F57B1551118a20` |
| StockLender on the naive labTSLA feed, LAB ONLY | `0x231D8706419162E3CD79fE2DFD2aa2152536CCF3` |

**Testnet limits.** Prices are signed 24/5 while the US session is open. Cash creation goes through five thinly seeded TESTUSD pools, so larger sizes can be refused on price impact; in-kind create and redeem always work. See [Router and the refused route](/router).

Stylus benchmark contracts: SlateVerifier (Rust) `0x0819e35fd1ccccabb15a100dbb8315f04f1f093b`, Solidity reference `0x1015EddD8776275446E23469c16F85E1ec6b5131`.

## Robinhood Chain mainnet (4663): live

Deployed on 3 Oct 2026, during Friday's US session. Every contract is verified on Sourcify, and the explorer shows the source. Twenty SlateFeeds price stock tokens that have no Chainlink feed: CRWD and the nineteen below. Prices are signed 24/5 by the same three keys and relayed by the publisher: CRWD on a 0.5% move or every 30 minutes, the others on a 1% move or every 4 hours.

Both networks were deployed by the same address, so the same address can belong to different contracts on each chain (`0x8B27…A507` is the SignedSource on testnet and the CRWD/USDG feed on mainnet). Always read an address with its chain.

**CRWD's first mainnet price**, signed Fri 2 Oct 15:04:50 EDT: a share price of $268.105, times the token's multiplier of 4.000, is $1,072.42 ([submit transaction](https://robinhoodchain.blockscout.com/tx/0x0d8a2bde33c69e0ae8f931314a6ebe3dcebf29a1860c268d0ffdb3e30e9cccda)).

| Contract | Address |
|---|---|
| SignedSource (3 signers, 2 needed; owned by the timelock) | [`0xf0b57272f1D69083019E8953B82bC128002D7526`](https://robinhoodchain.blockscout.com/address/0xf0b57272f1D69083019E8953B82bC128002D7526) |
| TimelockController (48 h) | [`0x1015EddD8776275446E23469c16F85E1ec6b5131`](https://robinhoodchain.blockscout.com/address/0x1015EddD8776275446E23469c16F85E1ec6b5131) |
| USMarketCalendar (moving under the timelock: executable Mon 5 Oct, 00:40 IST) | [`0x0819E35fd1cCcCabB15A100DBB8315f04f1f093b`](https://robinhoodchain.blockscout.com/address/0x0819E35fd1cCcCabB15A100DBB8315f04f1f093b) |
| SolidityReportVerifier | [`0x2E13A83f73df7b721fe020a1e11aD3c004653dC7`](https://robinhoodchain.blockscout.com/address/0x2E13A83f73df7b721fe020a1e11aD3c004653dC7) |
| SlateFeedFactory | [`0xd921ad145FA22b0C8A4846d234857FBEFFDfDdc6`](https://robinhoodchain.blockscout.com/address/0xd921ad145FA22b0C8A4846d234857FBEFFDfDdc6) |
| SlateQuotedFeed CRWD/USDG | [`0x8B27311a3493a85E063f97e4bB59cf3a22aEA507`](https://robinhoodchain.blockscout.com/address/0x8B27311a3493a85E063f97e4bB59cf3a22aEA507) |
| SlateQuotedFeed AAPL/USDG | [`0xe6943e58E3C3e8a29502430237bfC80bB6099c45`](https://robinhoodchain.blockscout.com/address/0xe6943e58E3C3e8a29502430237bfC80bB6099c45) |
| StockLender (USDG lender; values CRWD through its SlateFeed) | [`0x66770067Bf690a8eAcA95aCAB896659835704F52`](https://robinhoodchain.blockscout.com/address/0x66770067Bf690a8eAcA95aCAB896659835704F52) |
| SlateFeed CRWD (multiplier 4.000) | [`0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77`](https://robinhoodchain.blockscout.com/address/0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77) |
| SlateFeed AAPL (over Chainlink's total-return feed) | [`0x0c098235d4069Ad82c9EcaeF8264835C5A0dBc7D`](https://robinhoodchain.blockscout.com/address/0x0c098235d4069Ad82c9EcaeF8264835C5A0dBc7D) |

The nineteen other feedless tokens:

| Token | SlateFeed |
|---|---|
| AMC | [`0xF616AE554088bF3E2D7FF909DbdCf071B203e145`](https://robinhoodchain.blockscout.com/address/0xF616AE554088bF3E2D7FF909DbdCf071B203e145) |
| AVGO | [`0x1300fB818704c3B57eF8BDcd65DaAba0674C2315`](https://robinhoodchain.blockscout.com/address/0x1300fB818704c3B57eF8BDcd65DaAba0674C2315) |
| BA | [`0x4462C8B4F70b6438D6f43942aD7fA96A00DE2D93`](https://robinhoodchain.blockscout.com/address/0x4462C8B4F70b6438D6f43942aD7fA96A00DE2D93) |
| CCL | [`0x7997833BFFd1aEa6528BD28B574714D20618F5C5`](https://robinhoodchain.blockscout.com/address/0x7997833BFFd1aEa6528BD28B574714D20618F5C5) |
| COST | [`0xa230A338922FFEf19bf1b748Ec52136C26efb711`](https://robinhoodchain.blockscout.com/address/0xa230A338922FFEf19bf1b748Ec52136C26efb711) |
| F | [`0x8D8607D4ecA3cF912A8677069a493A2676D457Cb`](https://robinhoodchain.blockscout.com/address/0x8D8607D4ecA3cF912A8677069a493A2676D457Cb) |
| GLD | [`0x1760889FefB8012174D86D2544Ad8fB70431F74a`](https://robinhoodchain.blockscout.com/address/0x1760889FefB8012174D86D2544Ad8fB70431F74a) |
| HIMS | [`0x3a97b1A070461Da460Fcc8fc686A8342337300Aa`](https://robinhoodchain.blockscout.com/address/0x3a97b1A070461Da460Fcc8fc686A8342337300Aa) |
| IBM | [`0x7F4F3C3EAC5E4BAD30B7Eb6eFC6EeD5aff97D05a`](https://robinhoodchain.blockscout.com/address/0x7F4F3C3EAC5E4BAD30B7Eb6eFC6EeD5aff97D05a) |
| JNJ | [`0x7158D75e975bbad1Eebdbe6bb4A280c928De7004`](https://robinhoodchain.blockscout.com/address/0x7158D75e975bbad1Eebdbe6bb4A280c928De7004) |
| LLY | [`0x90B73cB8C436Ec6fb9244F2a976e9e65D4eA470f`](https://robinhoodchain.blockscout.com/address/0x90B73cB8C436Ec6fb9244F2a976e9e65D4eA470f) |
| LMT | [`0x28863229ee45Aa142E3C4b81cfD5C9ddCC1dB90c`](https://robinhoodchain.blockscout.com/address/0x28863229ee45Aa142E3C4b81cfD5C9ddCC1dB90c) |
| NFLX | [`0xd002fAaaf58C8b91D0c85D0788922Ed6F777DB9D`](https://robinhoodchain.blockscout.com/address/0xd002fAaaf58C8b91D0c85D0788922Ed6F777DB9D) |
| PFE | [`0x7371F1F7EddFd80507EDe7dD818379875Bf24867`](https://robinhoodchain.blockscout.com/address/0x7371F1F7EddFd80507EDe7dD818379875Bf24867) |
| RBLX | [`0x68B91835C5CC4849E7287ad04Fd870F63baa02aF`](https://robinhoodchain.blockscout.com/address/0x68B91835C5CC4849E7287ad04Fd870F63baa02aF) |
| RDDT | [`0xa722731319dc6dD969c5d4D2fe6B88b1a7aed2FC`](https://robinhoodchain.blockscout.com/address/0xa722731319dc6dD969c5d4D2fe6B88b1a7aed2FC) |
| RIVN | [`0x5A4871608F461fFb5c79034Dc9b0CC9864A00eaF`](https://robinhoodchain.blockscout.com/address/0x5A4871608F461fFb5c79034Dc9b0CC9864A00eaF) |
| SHOP | [`0x6C2656A66b6D92Cd69BcC138d23e3dE46D2475e5`](https://robinhoodchain.blockscout.com/address/0x6C2656A66b6D92Cd69BcC138d23e3dE46D2475e5) |
| SNAP | [`0x7b7031b9AB13af659f17F2eEeB3937C3d62b0003`](https://robinhoodchain.blockscout.com/address/0x7b7031b9AB13af659f17F2eEeB3937C3d62b0003) |

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
