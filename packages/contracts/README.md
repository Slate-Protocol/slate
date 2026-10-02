# @slate-protocol/contracts

Interfaces and a fail-closed reader for [Slate](https://docs.slate.0xo.in): multiplier-correct price feeds for Robinhood stock tokens (ERC-8056), served through Chainlink's `AggregatorV3Interface`.

```solidity
import {AggregatorV3Interface, SlatePrice} from "@slate-protocol/contracts/SlatePrice.sol";

(bool ok, uint256 price,,) = SlatePrice.tryRead(AggregatorV3Interface(feed), 3 days); // 8 decimals
if (!ok) revert("no price: pause, don't guess");     // Slate refused: a split, a stale or paused oracle
uint256 usd = SlatePrice.value(amount, 18, price, 8, 6); // `amount` tokens, in 6-decimal dollars
```

## Install

**Foundry**, from GitHub:

```bash
forge install Slate-Protocol/slate
echo '@slate-protocol/contracts/=lib/slate/packages/contracts/src/' >> remappings.txt
```

**npm**: `npm install @slate-protocol/contracts`, then map `@slate-protocol/contracts/=node_modules/@slate-protocol/contracts/src/`.

## What is in it

| File | |
|---|---|
| `SlatePrice.sol` | `tryRead` (price or the reason there is none), `read` (reverts with `NoPrice`), `status` (a SlateFeed's own status and quote), `value` (amount × price in any decimals) |
| `interfaces/AggregatorV3Interface.sol` | Chainlink's feed interface, which every Slate feed implements |
| `interfaces/ISlateFeed.sol` | `FeedStatus`, `Quote`, `latestQuote()`, `status()`, and the `FeedUnavailable` error |
| `interfaces/IERC8056.sol` | Robinhood's stock-token multiplier interface |
| `abi/*.json` | ABIs for TypeScript and other off-chain readers |

Feed addresses: [deployments.json](https://github.com/Slate-Protocol/slate/blob/main/deployments/deployments.json). A worked integration: [StockLender](https://github.com/Slate-Protocol/slate/blob/main/contracts/src/examples/StockLender.sol), a lending market that prices stock collateral through Slate feeds.

MIT licensed.
