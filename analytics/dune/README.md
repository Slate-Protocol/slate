# Slate on Dune

The queries behind Slate's Dune dashboard. Dune indexes Robinhood Chain mainnet as raw tables (`robinhood.logs`,
`robinhood.transactions`), so every query decodes Slate's own events directly; nothing depends on a decoded table.

| Query | What it shows | Source |
|---|---|---|
| `01_feeds.sql` | Every feed `SlateFeedFactory` deployed, its source, last signed share price, when it was observed, how many updates, and the feed and token addresses | `FeedDeployed` and `PriceUpdated` logs |
| `02_updates_over_time.sql` | Signed price updates per hour, by feed | `PriceUpdated` logs |
| `03_publisher.sql` | The relayer's transactions to `SignedSource` per hour, gas spent and its running total | `robinhood.transactions` |
| `04_crwd.sql` | Every CRWD share price, and the token price at its 4.000 multiplier | `PriceUpdated` logs for `CRWD/USD` |
| `05_vs_chainlink.sql` | Slate against Chainlink for the 35 tokens Chainlink prices, median and worst case | the accuracy board's snapshot, uploaded from `slate_accuracy_snapshot.csv` |

## Contracts (Robinhood Chain mainnet, 4663)

- `SignedSource` `0xf0b57272f1D69083019E8953B82bC128002D7526`: emits `PriceUpdated(bytes32 indexed feedId, int192 price, uint64 observedAt, uint256 signerCount)`, topic0 `0xb5fc72f4…3edc`. The price is the share price with 8 decimals; `feedId` is the ASCII symbol, e.g. `CRWD/USD`.
- `SlateFeedFactory` `0xd921ad145FA22b0C8A4846d234857FBEFFDfDdc6`: emits `FeedDeployed(address indexed feed, address indexed token, bytes32 indexed feedId, address deployer)`, topic0 `0xfae97898…6461`.
- Relayer `0x0acfe7b486d2a2181B4CeDe90A41ddd15c80168f`: Slate's own; anyone may relay a signed report.

## Expected results (cross-checked over RPC at block 79,239,673, Sat 3 Oct 2026)

- 21 feeds deployed: 20 signed (CRWD and 19 more with no Chainlink feed) and AAPL over Chainlink's total-return feed.
- 54 price updates, every one signed by 3 signers: CRWD 10, RIVN 4, AMC, HIMS, RBLX and SNAP 3 each, the other 14 two each.
- 54 relayer transactions to `SignedSource`, 0.000130 ETH of gas in all.
- CRWD's first price: $268.105 a share, × 4 = $1,072.42 (observed Fri 2 Oct 15:04:50 EDT); last before the close $269.975.
- Slate against Chainlink at the snapshot (35 tokens): gap now median 0.11%, worst 0.41%; like-for-like (Slate signed within 90 s of Chainlink's update, 12 tokens) median 0.02%, worst 0.51%.

Slate's prices for the 35 Chainlink-covered tokens are signed reports that the dashboard verifies in the browser and never submits on-chain, so they are not in `robinhood.logs`; that is why query 05 reads an uploaded snapshot. The snapshot is the board's state at Friday's close (01:02 UTC, 3 Oct): the market is closed until Monday, so no newer reports exist.
