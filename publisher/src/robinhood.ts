import { settings } from "./config.ts";

/** One Robinhood quote, with prices as 8-decimal integers. */
export type Quote = {
  symbol: string;
  bid: bigint;
  ask: bigint;
  /** (bid + ask) / 2, the share price Slate signs. */
  mid: bigint;
  /** Robinhood's own per-token bid: bid × the token's multiplier. */
  tokenBid: bigint;
  /** Unix seconds, from Robinhood's `generatedAt`. */
  observedAt: number;
  halted: boolean;
  /** The token's address on Robinhood Chain mainnet, from the same response. */
  mainnetToken?: string;
};

const PRICE_URL = "https://api.robinhood.com/rhj/prices/";

/** Parses a decimal string such as "264.98" or "1059.920000000000000000" into an integer with `decimals` places. */
export function toFixed(value: string, decimals = 8): bigint {
  if (!/^\d+(\.\d+)?$/.test(value)) throw new Error(`not a decimal: ${value}`);
  const [whole, frac = ""] = value.split(".");
  return BigInt(whole + frac.padEnd(decimals, "0").slice(0, decimals));
}

type Raw = {
  quotes: {
    tokenSymbol: string;
    bid: string;
    ask: string;
    tokenBid: string;
    generatedAt: string;
    isTradingHalt: boolean;
    deployments?: { contractAddress: string; chainId: number }[];
  }[];
};

export function parseQuote(raw: Raw): Quote {
  const q = raw.quotes?.[0];
  if (!q) throw new Error("no quote");
  const bid = toFixed(q.bid);
  const ask = toFixed(q.ask);
  return {
    symbol: q.tokenSymbol,
    bid,
    ask,
    mid: (bid + ask) / 2n,
    tokenBid: toFixed(q.tokenBid),
    observedAt: Math.floor(Date.parse(q.generatedAt) / 1000),
    halted: q.isTradingHalt,
    mainnetToken: q.deployments?.find((d) => d.chainId === 4663)?.contractAddress,
  };
}

export async function fetchQuote(symbol: string): Promise<Quote> {
  const res = await fetch(PRICE_URL + encodeURIComponent(symbol), {
    headers: { accept: "application/json" },
    signal: AbortSignal.timeout(8_000),
  });
  if (!res.ok) throw new Error(`${symbol}: HTTP ${res.status}`);
  return parseQuote((await res.json()) as Raw);
}

/** Reasons a quote must not be signed, or an empty list. */
export function quoteProblems(q: Quote, now: number): string[] {
  const problems: string[] = [];
  if (q.halted) problems.push("trading halt");
  if (q.bid <= 0n || q.ask <= 0n) problems.push("non-positive price");
  if (q.ask < q.bid) problems.push("crossed quote");
  else if (q.bid > 0n && ((q.ask - q.bid) * 10_000n) / q.bid > BigInt(settings.maxSpreadBps)) problems.push("spread too wide");
  if (!Number.isFinite(q.observedAt) || now - q.observedAt > settings.maxQuoteAge) problems.push("quote too old");
  if (q.observedAt - now > 30) problems.push("quote from the future");
  return problems;
}
