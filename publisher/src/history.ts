import pg from "pg";
import type { Address, PublicClient } from "viem";
import { aggregatorAbi, erc8056Abi } from "./abi.ts";
import { MATCH_WINDOW, type BoardRow } from "./board.ts";

/**
 * The accuracy board's history. Once an hour the publisher stores, for every token Chainlink prices on Robinhood Chain
 * mainnet, Slate's latest signed price (with the signed report itself, so every row stays verifiable), Chainlink's
 * answer read from mainnet at that moment, the token's multiplier and the gaps, computed exactly as the dashboard's
 * accuracy board computes them. A row is stored once per (token, Slate observation, Chainlink update): while the market
 * is closed nothing changes, so nothing new is stored.
 *
 * Postgres (Neon) at DATABASE_URL; without it, nothing is stored and /history says so.
 */

const DDL = `
CREATE TABLE IF NOT EXISTS board_snapshots (
  id bigserial PRIMARY KEY,
  taken_at timestamptz NOT NULL,
  symbol text NOT NULL,
  multiplier numeric NOT NULL,
  slate_share_price numeric NOT NULL,
  slate_price numeric NOT NULL,
  slate_observed_at timestamptz NOT NULL,
  chainlink_price numeric NOT NULL,
  chainlink_updated_at timestamptz NOT NULL,
  gap_now_pct double precision NOT NULL,
  slate_then_price numeric,
  slate_then_observed_at timestamptz,
  gap_then_pct double precision,
  chainlink_threshold_pct double precision,
  report text NOT NULL,
  UNIQUE (symbol, slate_observed_at, chainlink_updated_at)
);
CREATE INDEX IF NOT EXISTS board_snapshots_taken_at ON board_snapshots (taken_at);
`;

let pool: pg.Pool | null = null;
let ready: Promise<void> | null = null;

export const historyEnabled = () => !!process.env.DATABASE_URL;

function db() {
  if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL is not set");
  pool ??= new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 2, idleTimeoutMillis: 30_000 });
  ready ??= pool.query(DDL).then(() => undefined);
  return { pool, ready };
}

export type SnapshotRow = {
  symbol: string;
  multiplier: number;
  slateSharePrice: number;
  slatePrice: number;
  slateObservedAt: number;
  chainlinkPrice: number;
  chainlinkUpdatedAt: number;
  gapNowPct: number;
  slateThenPrice: number | null;
  slateThenObservedAt: number | null;
  gapThenPct: number | null;
  thresholdPct: number;
  report: string;
};

/** The board's rows as they stand, with Chainlink and the multiplier read from mainnet now. Pure arithmetic is exported for tests. */
export function snapshotRow(r: BoardRow, multiplier: bigint, answer: bigint, decimals: number, updatedAt: number): SnapshotRow | null {
  if (!r.latest || answer <= 0n || multiplier === 0n) return null;
  const token = (price: string) => Number((BigInt(price) * multiplier) / 10n ** 18n) / 1e8;
  const chainlink = Number(answer) / 10 ** decimals;
  const slate = token(r.latest.price);
  const then = r.atChainlink && Math.abs(r.atChainlink.observedAt - updatedAt) <= MATCH_WINDOW ? r.atChainlink : undefined;
  const slateThen = then ? token(then.price) : null;
  return {
    symbol: r.symbol,
    multiplier: Number(multiplier) / 1e18,
    slateSharePrice: Number(r.latest.price) / 1e8,
    slatePrice: slate,
    slateObservedAt: r.latest.observedAt,
    chainlinkPrice: chainlink,
    chainlinkUpdatedAt: updatedAt,
    gapNowPct: (slate / chainlink - 1) * 100,
    slateThenPrice: slateThen,
    slateThenObservedAt: then?.observedAt ?? null,
    gapThenPct: slateThen !== null ? (slateThen / chainlink - 1) * 100 : null,
    thresholdPct: r.chainlinkThresholdPct,
    report: r.latest.report,
  };
}

/** One hourly snapshot: returns how many new rows were stored. */
export async function storeSnapshot(rows: BoardRow[], mainnet: PublicClient, now: number): Promise<number> {
  const { pool, ready } = db();
  await ready;
  // Plain reads, one token at a time (the publisher's mainnet client has no multicall contract configured).
  let stored = 0;
  for (const r of rows.filter((x) => x.latest)) {
    const [m, round] = await Promise.all([
      mainnet.readContract({ address: r.token as Address, abi: erc8056Abi, functionName: "uiMultiplier" }).catch(() => null),
      mainnet.readContract({ address: r.chainlink as Address, abi: aggregatorAbi, functionName: "latestRoundData" }).catch(() => null),
    ]);
    if (m === null || round === null) continue;
    const [, answer, , updatedAt] = round as readonly [bigint, bigint, bigint, bigint, bigint];
    const s = snapshotRow(r, m as bigint, answer, r.chainlinkDecimals, Number(updatedAt));
    if (!s) continue;
    const res = await pool.query(
      `INSERT INTO board_snapshots (taken_at, symbol, multiplier, slate_share_price, slate_price, slate_observed_at, chainlink_price,
         chainlink_updated_at, gap_now_pct, slate_then_price, slate_then_observed_at, gap_then_pct, chainlink_threshold_pct, report)
       VALUES (to_timestamp($1), $2, $3, $4, $5, to_timestamp($6), $7, to_timestamp($8), $9, $10, to_timestamp($11), $12, $13, $14)
       ON CONFLICT (symbol, slate_observed_at, chainlink_updated_at) DO NOTHING`,
      [now, s.symbol, s.multiplier, s.slateSharePrice, s.slatePrice, s.slateObservedAt, s.chainlinkPrice, s.chainlinkUpdatedAt, s.gapNowPct,
        s.slateThenPrice, s.slateThenObservedAt, s.gapThenPct, s.thresholdPct, s.report],
    );
    stored += res.rowCount ?? 0;
  }
  return stored;
}

/** For the dashboard: per hour of observation, how many tokens, and the median and worst gap (now, and like for like), with the worst token. */
export async function readHistory() {
  if (!historyEnabled()) return { collecting: false, hours: [], since: null, rows: 0 };
  const { pool, ready } = db();
  await ready;
  const [agg, meta] = await Promise.all([
    pool.query(`
      -- By the hour Slate's price was observed, not when the row was stored: a weekend snapshot holds Friday's reports.
      SELECT extract(epoch FROM date_trunc('hour', slate_observed_at))::bigint AS hour,
             count(DISTINCT symbol)::int AS tokens,
             percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(gap_now_pct)) AS median_now,
             max(abs(gap_now_pct)) AS worst_now,
             (array_agg(symbol ORDER BY abs(gap_now_pct) DESC))[1] AS worst_now_symbol,
             percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(gap_then_pct)) FILTER (WHERE gap_then_pct IS NOT NULL) AS median_then,
             max(abs(gap_then_pct)) AS worst_then,
             (array_agg(symbol ORDER BY abs(gap_then_pct) DESC NULLS LAST))[1] AS worst_then_symbol,
             count(gap_then_pct)::int AS matched
      FROM board_snapshots GROUP BY 1 ORDER BY 1`),
    pool.query(`SELECT count(*)::int AS rows, extract(epoch FROM min(taken_at))::bigint AS since, count(DISTINCT symbol)::int AS tokens FROM board_snapshots`),
  ]);
  return {
    collecting: true,
    since: meta.rows[0].since ? Number(meta.rows[0].since) : null,
    rows: meta.rows[0].rows,
    tokens: meta.rows[0].tokens,
    hours: agg.rows.map((h) => ({
      hour: Number(h.hour),
      tokens: h.tokens,
      medianNowPct: h.median_now,
      worstNowPct: h.worst_now,
      worstNowSymbol: h.worst_now_symbol,
      medianThenPct: h.median_then,
      worstThenPct: h.worst_then,
      worstThenSymbol: h.matched ? h.worst_then_symbol : null,
      matched: h.matched,
    })),
  };
}
