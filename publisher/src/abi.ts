import { parseAbi } from "viem";

export const signedSourceAbi = parseAbi([
  "function submit(bytes32 feedId, bytes report)",
  "function observe(bytes32 feedId) view returns ((int256 price, uint8 decimals, uint64 observedAt))",
  "function signers() view returns (address[])",
  "function quorum() view returns (uint8)",
  "error UnknownSigner(address signer)",
  "error QuorumNotMet(uint256 signed, uint256 required)",
  "error NonPositivePrice()",
  "error SpreadTooWide(uint256 spreadBps)",
  "error FutureObservation(uint64 observedAt)",
  "error StaleReport(uint64 observedAt, uint64 latestObservedAt)",
]);

export const calendarAbi = parseAbi(["function closedSince(uint256 timestamp, uint8 session) view returns (uint256)"]);

export const slateFeedAbi = parseAbi([
  "function token() view returns (address)",
  "function poke() returns (bool)",
  "function latestQuote() view returns ((uint8 status, int256 answer, uint64 observedAt))",
]);

export const erc8056Abi = parseAbi([
  "function uiMultiplier() view returns (uint256)",
  "function newUIMultiplier() view returns (uint256)",
  "function effectiveAt() view returns (uint256)",
]);

export const aggregatorAbi = parseAbi([
  "function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)",
]);

export const erc20Abi = parseAbi([
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address owner) view returns (uint256)",
]);

const poolKey = "(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks)";

export const seederAbi = parseAbi([
  `function recenter(${poolKey} key, address feed, uint256 toleranceBps, uint256 max0, uint256 max1) returns (bool)`,
  `function sqrtPriceOf(${poolKey} key) view returns (uint160)`,
  `function targetSqrtPrice(${poolKey} key, address feed) view returns (uint160)`,
]);
