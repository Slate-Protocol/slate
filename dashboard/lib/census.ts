import "server-only";
import { parseAbi, type Address } from "viem";
import { client } from "./chains";
import { deployments } from "./data";

/**
 * The multiplier census: every stock token in Robinhood's registry on Robinhood Chain mainnet, its ERC-8056 multiplier
 * read from the chain, whether Chainlink publishes a feed for it, and whether Slate does. A feed that ignores the
 * multiplier prices a token at its share price; the token is worth share price × multiplier, so that feed is low by
 * (1 − 1/multiplier).
 */

const REGISTRY = "https://api.robinhood.com/rhj/assets";
const DIRECTORY = "https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json";
const abi = parseAbi(["function uiMultiplier() view returns (uint256)", "function newUIMultiplier() view returns (uint256)", "function effectiveAt() view returns (uint256)"]);
const ONE = 10n ** 18n;

export type CensusRow = {
  symbol: string;
  token: Address;
  multiplier: number | null;
  multiplierRaw: string | null;
  next: number | null;
  effectiveAt: number | null;
  chainlink: boolean;
  slateFeed: Address | null;
  /** How far below the token's value a multiplier-blind price is, in percent. */
  blindLowPct: number | null;
};

export async function census() {
  const [reg, dir, dep] = await Promise.all([
    fetch(REGISTRY, { next: { revalidate: 300 } }).then((r) => r.json() as Promise<{ assets: { tokenSymbol: string; deployments?: { chainId: number; contractAddress: string }[] }[] }>),
    fetch(DIRECTORY, { next: { revalidate: 300 } }).then((r) => r.json() as Promise<{ name: string }[]>),
    deployments(),
  ]);
  const covered = new Set(dir.map((f) => /^Robinhood\s+([A-Za-z.]+)\s*[-/]\s*USD/.exec(f.name)?.[1]?.toUpperCase()).filter(Boolean) as string[]);
  const slate = new Map(dep.feeds.filter((f) => f.chainId === 4663).map((f) => [f.token.toLowerCase(), f.feed as Address]));
  const tokens = reg.assets
    .map((a) => ({ symbol: a.tokenSymbol.toUpperCase(), token: a.deployments?.find((d) => d.chainId === 4663)?.contractAddress as Address | undefined }))
    .filter((x): x is { symbol: string; token: Address } => !!x.token);
  const c = client(4663);
  const block = await c.getBlockNumber();
  const reads = await c.multicall({
    allowFailure: true,
    blockNumber: block,
    contracts: tokens.flatMap((t) => (["uiMultiplier", "newUIMultiplier", "effectiveAt"] as const).map((functionName) => ({ address: t.token, abi, functionName }))),
  });
  const rows: CensusRow[] = tokens.map((t, i) => {
    const m = reads[3 * i].status === "success" ? (reads[3 * i].result as bigint) : null;
    const n = reads[3 * i + 1].status === "success" ? (reads[3 * i + 1].result as bigint) : null;
    const e = reads[3 * i + 2].status === "success" ? (reads[3 * i + 2].result as bigint) : null;
    const mult = m !== null ? Number(m) / 1e18 : null;
    return {
      symbol: t.symbol,
      token: t.token,
      multiplier: mult,
      multiplierRaw: m?.toString() ?? null,
      next: n !== null ? Number(n) / 1e18 : null,
      effectiveAt: e !== null && e > 0n ? Number(e) : null,
      chainlink: covered.has(t.symbol),
      slateFeed: slate.get(t.token.toLowerCase()) ?? null,
      blindLowPct: m !== null && m > 0n ? (1 - 1 / mult!) * 100 : null,
    };
  });
  const nonOne = rows.filter((r) => r.multiplierRaw !== null && BigInt(r.multiplierRaw) !== ONE);
  const uncovered = nonOne.filter((r) => !r.chainlink);
  const now = Math.floor(Date.now() / 1000);
  return {
    block: Number(block),
    readAt: now,
    tokens: rows.length,
    failed: rows.filter((r) => r.multiplier === null).length,
    nonOne: nonOne.length,
    nonOneUncovered: uncovered.length,
    nonOneUncoveredWithSlate: uncovered.filter((r) => r.slateFeed).length,
    splits: nonOne.filter((r) => r.multiplier! >= 1.5 || r.multiplier! <= 1 / 1.5).length,
    pending: rows.filter((r) => r.effectiveAt !== null && r.effectiveAt > now).length,
    // effectiveAt holds only each token's latest change, so these are floors.
    changed30: nonOne.filter((r) => r.effectiveAt !== null && r.effectiveAt <= now && now - r.effectiveAt < 30 * 86400).length,
    changed30Uncovered: uncovered.filter((r) => r.effectiveAt !== null && r.effectiveAt <= now && now - r.effectiveAt < 30 * 86400).length,
    changed7: nonOne.filter((r) => r.effectiveAt !== null && r.effectiveAt <= now && now - r.effectiveAt < 7 * 86400).length,
    rows: rows.sort((a, b) => (b.blindLowPct ?? 0) - (a.blindLowPct ?? 0) || a.symbol.localeCompare(b.symbol)),
  };
}
