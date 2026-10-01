/** Mirrors `FeedStatus` in contracts/src/interfaces/ISlateFeed.sol, in order. */
export const FEED_STATUS = [
  "OK",
  "Market closed",
  "Stale",
  "Oracle paused",
  "Straddle",
  "Corporate action",
  "No data",
] as const;

export type FeedStatusLabel = (typeof FEED_STATUS)[number] | "Not deployed";

export type Tone = "ok" | "neutral" | "warn" | "stop";

export const tone: Record<FeedStatusLabel, Tone> = {
  OK: "ok",
  "Market closed": "neutral",
  Stale: "warn",
  "Oracle paused": "stop",
  Straddle: "warn",
  "Corporate action": "warn",
  "No data": "stop",
  "Not deployed": "neutral",
};

export const meaning: Record<(typeof FEED_STATUS)[number], string> = {
  OK: "Fresh and consistent.",
  "Market closed": "Weekend, holiday or overnight gap; the last price was fresh at the close.",
  Stale: "Older than the feed allows while the market is open.",
  "Oracle paused": "Robinhood's oraclePaused() is set.",
  Straddle: "Priced before a multiplier switch whose old value was not recorded.",
  "Corporate action": "Inside the grace window after a split.",
  "No data": "No usable price.",
};
