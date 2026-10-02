import { parseAbi } from "viem";

export const erc8056Abi = [
  { type: "function", name: "uiMultiplier", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

export const aggregatorAbi = [
  {
    type: "function",
    name: "latestRoundData",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "roundId", type: "uint80" },
      { name: "answer", type: "int256" },
      { name: "startedAt", type: "uint256" },
      { name: "updatedAt", type: "uint256" },
      { name: "answeredInRound", type: "uint80" },
    ],
  },
] as const;

/** SlateFeed.latestDetail(): never reverts on a bad status, so the dashboard can show why. */
export const slateFeedAbi = [
  {
    type: "function",
    name: "latestDetail",
    stateMutability: "view",
    inputs: [],
    outputs: [
      {
        name: "quote",
        type: "tuple",
        components: [
          { name: "status", type: "uint8" },
          { name: "answer", type: "int256" },
          { name: "observedAt", type: "uint64" },
        ],
      },
      { name: "sharePrice", type: "int256" },
      { name: "multiplier", type: "uint256" },
    ],
  },
] as const;

export const navFeedAbi = [
  {
    type: "function",
    name: "latestQuote",
    stateMutability: "view",
    inputs: [],
    outputs: [
      {
        name: "quote",
        type: "tuple",
        components: [
          { name: "status", type: "uint8" },
          { name: "answer", type: "int256" },
          { name: "observedAt", type: "uint64" },
        ],
      },
    ],
  },
] as const;

export const basketAbi = parseAbi([
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function holdings() view returns (uint256[])",
  "function quoteCreate(uint256 shares) view returns (uint256[])",
  "function quoteRedeem(uint256 shares) view returns (uint256[])",
  "function create(uint256 shares, address to, uint256[] maxAmounts) returns (uint256[])",
  "function redeem(uint256 shares, address to, uint256[] minAmounts) returns (uint256[])",
  "error AboveMaximum(uint256 index, uint256 amount, uint256 maximum)",
  "error BelowMinimum(uint256 index, uint256 amount, uint256 minimum)",
  "error FirstCreationTooSmall(uint256 minimum)",
  "error ZeroShares()",
]);

export const routerAbi = parseAbi([
  "function fairCash(uint256 shares) view returns (uint256 total, uint256[] amounts)",
  "function createWithCash(uint256 shares, address to, (address venue, bytes route)[] legs, uint256 maxCashIn, uint256 deadline) returns (uint256)",
  "error RouteRefused(uint256 index, uint256 effectivePrice, uint256 feedPrice)",
  "error ShortFill(uint256 index, uint256 received, uint256 expected)",
  "error Expired(uint256 deadline)",
  "error FeedUnavailable(uint8 status)",
  "error ExcessiveInput(uint256 amountIn, uint256 maxIn)",
]);

export const erc20Abi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
]);

export const testDollarAbi = parseAbi([
  "function faucet()",
  "function lastFaucetAt(address) view returns (uint256)",
  "error Cooldown(uint256 nextAt)",
]);

export const labStockAbi = parseAbi([
  "function uiMultiplier() view returns (uint256)",
  "function newUIMultiplier() view returns (uint256)",
  "function effectiveAt() view returns (uint256)",
  "function lastScheduledAt() view returns (uint256)",
  "function scheduleCorporateAction(uint256 newMultiplier, uint256 effectiveAt)",
  "function faucet()",
  "error MultiplierOutOfRange(uint256 multiplier)",
  "error EffectiveTimeOutOfRange(uint256 effectiveAt)",
  "error Cooldown(uint256 nextAt)",
]);

/** StockLender: the integration example. It prices collateral with `latestRoundData()` only. */
export const lenderAbi = parseAbi([
  "function priceOf(address token) view returns (bool ok, uint256 price, uint256 updatedAt)",
  "function quote(address token, uint256 amount) view returns (bool ok, uint256 value, uint256 maxBorrow)",
  "function positionOf(address token, address who) view returns (bool ok, uint256 collateral, uint256 debt, uint256 borrowLimit, uint256 liquidationThreshold)",
  "function markets(address token) view returns (address feed, uint8 feedDecimals, uint8 tokenDecimals, uint16 ltvBps, uint16 liquidationBps, uint16 bonusBps, uint32 maxAge, bool listed)",
  "function cash() view returns (uint256)",
  "function totalDebt() view returns (uint256)",
  "function deposit(address token, uint256 amount)",
  "function withdraw(address token, uint256 amount)",
  "function borrow(address token, uint256 amount)",
  "function repay(address token, address account, uint256 amount) returns (uint256)",
  "error NotListed(address token)",
  "error ZeroAmount()",
  "error PriceUnavailable(address token)",
  "error ExceedsLimit(uint256 debt, uint256 limit)",
  "error InsufficientCollateral(uint256 requested, uint256 available)",
  "error InsufficientLiquidity(uint256 requested, uint256 available)",
  "error Healthy(uint256 debt, uint256 threshold)",
]);
