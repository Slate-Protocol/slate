import type { Address, Hex, PublicClient } from "viem";
import { aggregatorAbi } from "./abi.ts";
import { PRESIGN } from "./config.ts";
import { buildReport, feedId } from "./report.ts";
import { quoteProblems, type Quote } from "./robinhood.ts";

/**
 * The accuracy board. For every stock token that Chainlink also prices on Robinhood Chain mainnet, the publisher signs
 * the same Robinhood share price it signs for Slate's own feeds, for mainnet's SignedSource domain, about once a
 * minute while the session is open. Nothing is submitted and no gas is spent: the dashboard verifies each report,
 * multiplies it by the token's on-chain multiplier exactly as SlateFeed does, and compares the result with
 * Chainlink's answer read from mainnet. Agreement where Chainlink exists is the evidence for the tokens where it does not.
 */

const DIRECTORY_URL = "https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json";
const REGISTRY_URL = "https://api.robinhood.com/rhj/assets";

export type Covered = { symbol: string; chainlink: Address; decimals: number; token: Address; thresholdPct: number; heartbeat: number };

export type Attestation = { symbol: string; feedId: Hex; price: string; observedAt: number; report: Hex };

export type BoardRow = {
  symbol: string;
  token: Address;
  chainlink: Address;
  chainlinkDecimals: number;
  chainlinkThresholdPct: number;
  chainlinkHeartbeat: number;
  latest?: Attestation;
  /** The signed report observed closest to Chainlink's last update, when one is within `MATCH_WINDOW`. */
  atChainlink?: Attestation;
  chainlinkUpdatedAt?: number;
  refused?: string[];
};

export const HISTORY_SECONDS = 6 * 3600;
export const MATCH_WINDOW = 90;

type DirectoryEntry = { name: string; proxyAddress: string; decimals: number; threshold: number; heartbeat: number };
type Asset = { tokenSymbol: string; deployments?: { contractAddress: string; chainId: number }[] };

/** Chainlink stock feeds on Robinhood Chain mainnet ("Robinhood AAPL / USD"), matched to Robinhood's registry. */
export function matchCovered(directory: DirectoryEntry[], assets: Asset[]): Covered[] {
  const bySymbol = new Map(assets.map((a) => [a.tokenSymbol.toUpperCase(), a]));
  const out: Covered[] = [];
  for (const f of directory) {
    const m = /^Robinhood\s+([A-Za-z.]+)\s*[-/]\s*USD/.exec(f.name);
    const asset = m && bySymbol.get(m[1].toUpperCase());
    const token = asset?.deployments?.find((d) => d.chainId === 4663)?.contractAddress;
    if (!m || !token || out.some((c) => c.symbol === m[1].toUpperCase())) continue;
    out.push({
      symbol: m[1].toUpperCase(),
      chainlink: f.proxyAddress as Address,
      decimals: f.decimals,
      token: token as Address,
      thresholdPct: f.threshold,
      heartbeat: f.heartbeat,
    });
  }
  return out.sort((a, b) => a.symbol.localeCompare(b.symbol));
}

/** The attestation observed closest to `at`, if one lies within `window` seconds of it. */
export function closest(history: Attestation[], at: number, window = MATCH_WINDOW): Attestation | undefined {
  let best: Attestation | undefined;
  for (const a of history) {
    if (Math.abs(a.observedAt - at) > window) continue;
    if (!best || Math.abs(a.observedAt - at) < Math.abs(best.observedAt - at)) best = a;
  }
  return best;
}

export const board = {
  updatedAt: 0,
  chainId: PRESIGN.chainId,
  signedSource: PRESIGN.signedSource,
  rows: {} as Record<string, BoardRow>,
};
const history = new Map<string, Attestation[]>();
let covered: { at: number; list: Covered[] } = { at: 0, list: [] };

async function coverage(now: number): Promise<Covered[]> {
  if (covered.list.length && now - covered.at < 6 * 3600) return covered.list;
  const [directory, registry] = await Promise.all([
    fetch(DIRECTORY_URL, { signal: AbortSignal.timeout(15_000) }).then((r) => r.json() as Promise<DirectoryEntry[]>),
    fetch(REGISTRY_URL, { signal: AbortSignal.timeout(15_000) }).then((r) => r.json() as Promise<{ assets: Asset[] }>),
  ]);
  const list = matchCovered(directory, registry.assets);
  if (list.length) covered = { at: now, list };
  return covered.list;
}

/**
 * One board update. `quote` fetches (and caches per cycle) a Robinhood quote; `multiplierProblem` is the same
 * tokenBid ÷ bid against on-chain multiplier check the live feeds use.
 */
export async function updateBoard(args: {
  signers: Hex[];
  now: number;
  marketOpen: boolean;
  mainnet: PublicClient;
  quote: (symbol: string) => Promise<Quote>;
  multiplierProblem: (q: Quote) => Promise<string | null>;
}) {
  const list = await coverage(args.now);
  const queue = [...list];
  const worker = async () => {
    for (let c = queue.shift(); c; c = queue.shift()) {
      const row: BoardRow = board.rows[c.symbol] ?? {
        symbol: c.symbol,
        token: c.token,
        chainlink: c.chainlink,
        chainlinkDecimals: c.decimals,
        chainlinkThresholdPct: c.thresholdPct,
        chainlinkHeartbeat: c.heartbeat,
      };
      board.rows[c.symbol] = row;
      try {
        const [, , , updatedAt] = await args.mainnet.readContract({ address: c.chainlink, abi: aggregatorAbi, functionName: "latestRoundData" });
        row.chainlinkUpdatedAt = Number(updatedAt);
      } catch {}
      // Outside the session Robinhood serves the last close with a fresh timestamp; nothing is signed then.
      if (args.marketOpen) {
        try {
          const q = await args.quote(c.symbol);
          const problems = quoteProblems(q, args.now);
          const mult = await args.multiplierProblem(q);
          if (mult) problems.push(mult);
          row.refused = problems.length ? problems : undefined;
          const past = history.get(c.symbol) ?? [];
          if (!problems.length && (past.at(-1)?.observedAt ?? 0) < q.observedAt) {
            const id = feedId(c.symbol);
            const report = await buildReport(args.signers, PRESIGN.chainId, PRESIGN.signedSource, {
              feedId: id,
              price: q.mid,
              observedAt: BigInt(q.observedAt),
            });
            past.push({ symbol: c.symbol, feedId: id, price: q.mid.toString(), observedAt: q.observedAt, report });
            history.set(c.symbol, past.filter((a) => args.now - a.observedAt <= HISTORY_SECONDS));
          }
        } catch (e) {
          row.refused = [e instanceof Error ? e.message : String(e)];
        }
      }
      const past = history.get(c.symbol) ?? [];
      row.latest = past.at(-1) ?? row.latest;
      row.atChainlink = row.chainlinkUpdatedAt ? closest(past, row.chainlinkUpdatedAt) : undefined;
    }
  };
  await Promise.all(Array.from({ length: 5 }, worker));
  board.updatedAt = args.now;
}
