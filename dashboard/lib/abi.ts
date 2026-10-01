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
