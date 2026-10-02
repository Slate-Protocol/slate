"use client";

import { useQuery } from "@tanstack/react-query";
import { formatUnits, parseAbi, type Address } from "viem";
import { client } from "@/lib/chains";
import { MATCH_WINDOW, PUBLISHER_URL, fetchBoard, median, mergeBoards, verify, type Attestation, type BoardRow, type Verdict } from "@/lib/board";
import { useNow } from "./live";
import { card } from "./sections";

const MAINNET = 4663;
const TESTNET = 46630;
const TESTNET_SIGNED_SOURCE: Address = "0x8B27311a3493a85E063f97e4bB59cf3a22aEA507";
const signedSourceAbi = parseAbi(["function signers() view returns (address[])", "function quorum() view returns (uint8)"]);
const readAbi = parseAbi([
  "function uiMultiplier() view returns (uint256)",
  "function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)",
  "function decimals() view returns (uint8)",
]);

type Row = {
  symbol: string;
  multiplier: number | null;
  slateNow: number | null;
  chainlink: number | null;
  chainlinkUpdatedAt: number | null;
  slateObservedAt: number | null;
  gapNow: number | null;
  slateAt: number | null;
  gapAt: number | null;
  verdict: Verdict | null;
  thresholdPct: number;
};

type Result = {
  rows: Row[];
  signerSet: { chainId: number; address: Address; signers: readonly Address[]; quorum: number };
  publisherOk: boolean;
  newest: number | null;
};

/** The signer set to verify against: mainnet's SignedSource once deployed, until then testnet's (the same keys). */
async function signerSet(signedSource: Address) {
  const main = client(MAINNET);
  const code = await main.getCode({ address: signedSource }).catch(() => undefined);
  const [chainId, address, c] = code && code !== "0x" ? [MAINNET, signedSource, main] : [TESTNET, TESTNET_SIGNED_SOURCE, client(TESTNET)];
  const [signers, quorum] = await Promise.all([
    c.readContract({ address, abi: signedSourceAbi, functionName: "signers" }),
    c.readContract({ address, abi: signedSourceAbi, functionName: "quorum" }),
  ]);
  return { chainId, address, signers, quorum: Number(quorum) };
}

async function load(): Promise<Result | null> {
  const [live, snapshot] = await Promise.all([fetchBoard(`${PUBLISHER_URL}/board`), fetchBoard("/board-snapshot.json")]);
  const board = mergeBoards(live, snapshot);
  if (!board) return null;
  const set = await signerSet(board.signedSource);
  const list = Object.values(board.rows).sort((a, b) => a.symbol.localeCompare(b.symbol));
  const reads = await client(MAINNET).multicall({
    allowFailure: true,
    contracts: list.flatMap((r: BoardRow) => [
      { address: r.token, abi: readAbi, functionName: "uiMultiplier" } as const,
      { address: r.chainlink, abi: readAbi, functionName: "latestRoundData" } as const,
      { address: r.chainlink, abi: readAbi, functionName: "decimals" } as const,
    ]),
  });
  const check = (a?: Attestation) => (a ? verify(a, set.signers, set.quorum, board.chainId, board.signedSource) : Promise.resolve(null));
  const rows = await Promise.all(
    list.map(async (r, i): Promise<Row> => {
      const mult = reads[3 * i].status === "success" ? (reads[3 * i].result as bigint) : null;
      const round = reads[3 * i + 1].status === "success" ? (reads[3 * i + 1].result as readonly bigint[]) : null;
      const dec = reads[3 * i + 2].status === "success" ? Number(reads[3 * i + 2].result) : null;
      const chainlink = round && dec !== null ? Number(formatUnits(round[1], dec)) : null;
      const updatedAt = round ? Number(round[3]) : null;
      const [vLatest, vAt] = await Promise.all([check(r.latest), check(r.atChainlink)]);
      const token = (a?: Attestation) => (a && mult !== null ? Number(formatUnits((BigInt(a.price) * mult) / 10n ** 18n, 8)) : null);
      const slateNow = vLatest?.ok ? token(r.latest) : null;
      const matched = vAt?.ok && r.atChainlink && updatedAt !== null && Math.abs(r.atChainlink.observedAt - updatedAt) <= MATCH_WINDOW;
      const slateAt = matched ? token(r.atChainlink) : null;
      const gap = (s: number | null) => (s !== null && chainlink ? s / chainlink - 1 : null);
      return {
        symbol: r.symbol,
        multiplier: mult !== null ? Number(formatUnits(mult, 18)) : null,
        slateNow,
        chainlink,
        chainlinkUpdatedAt: updatedAt,
        slateObservedAt: r.latest?.observedAt ?? null,
        gapNow: gap(slateNow),
        slateAt,
        gapAt: gap(slateAt),
        verdict: vLatest,
        thresholdPct: r.chainlinkThresholdPct,
      };
    }),
  );
  const newest = rows.reduce<number | null>((m, r) => (r.slateObservedAt && (!m || r.slateObservedAt > m) ? r.slateObservedAt : m), null);
  return { rows, signerSet: set, publisherOk: !!live, newest };
}

const abs = (x: number) => `${(x * 100).toFixed(2)}%`;
const pct = (x: number | null, digits = 2) => (x === null ? "—" : `${x >= 0 ? "+" : "−"}${Math.abs(x * 100).toFixed(digits)}%`);
const money = (x: number | null) =>
  x === null ? "—" : `$${x.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: x < 10 ? 4 : 2 })}`;
const ago = (t: number | null, now: number) => {
  if (t === null) return "—";
  const s = Math.max(0, now - t);
  return s < 90 ? `${s}s ago` : s < 5400 ? `${Math.round(s / 60)} min ago` : s < 172800 ? `${Math.round(s / 3600)} h ago` : `${Math.round(s / 86400)} d ago`;
};

function Stat({ label, value, note, tone }: { label: string; value: string; note?: string; tone?: "stop" }) {
  return (
    <div className={`${card} flex flex-col gap-1 p-4`}>
      <span className="text-xs text-muted">{label}</span>
      <span className={`font-mono text-2xl font-semibold ${tone === "stop" ? "text-stop" : ""}`}>{value}</span>
      {note && <span className="text-[13px] text-muted">{note}</span>}
    </div>
  );
}

export function AccuracyBoard({ uncovered }: { uncovered: number | null }) {
  const { data, isLoading } = useQuery({ queryKey: ["accuracy"], queryFn: load, refetchInterval: 30_000 });
  const now = useNow();
  const rows = data?.rows ?? [];
  const verified = rows.filter((r) => r.verdict?.ok);
  const nowGaps = rows.filter((r) => r.gapNow !== null).map((r) => ({ s: r.symbol, g: Math.abs(r.gapNow!) }));
  const atGaps = rows.filter((r) => r.gapAt !== null).map((r) => ({ s: r.symbol, g: Math.abs(r.gapAt!) }));
  const worst = (xs: { s: string; g: number }[]) => xs.reduce<{ s: string; g: number } | null>((w, x) => (!w || x.g > w.g ? x : w), null);
  const worstNow = worst(nowGaps);
  const worstAt = worst(atGaps);
  const withinThreshold = rows.filter((r) => r.gapNow !== null && Math.abs(r.gapNow) * 100 <= r.thresholdPct).length;
  const closed = data?.newest ? now - data.newest > 15 * 60 : false;
  const cols =
    "grid grid-cols-[minmax(0,0.8fr)_minmax(0,0.8fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,0.8fr)_minmax(0,1fr)_minmax(0,0.9fr)_minmax(0,0.9fr)] gap-x-3 px-4";

  return (
    <div className="flex flex-col gap-4">
      <section aria-labelledby="accuracy-title" className="flex max-w-[820px] flex-col gap-2">
        <h1 id="accuracy-title" className="text-2xl font-semibold">Slate against Chainlink, live</h1>
        <p className="text-muted">
          Chainlink publishes prices for {rows.length || 35}{" "}Robinhood stock tokens on Robinhood Chain mainnet. For each one, this
          page puts Chainlink&apos;s answer beside the price Slate signs from the same Robinhood quotes it uses for every Slate feed,
          times the token&apos;s on-chain multiplier, exactly as SlateFeed computes it. Your browser checks every signature against
          Slate&apos;s on-chain signer set and reads the multiplier and Chainlink&apos;s answer from mainnet itself. Agreement here is
          the evidence for trusting Slate on the {uncovered ?? "other"} tokens Chainlink does not cover.
        </p>
      </section>

      <div className="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-3">
        <Stat label="Median gap at Chainlink's last update" value={atGaps.length ? abs(median(atGaps.map((x) => x.g))) : "—"} note={`${atGaps.length} of ${rows.length} tokens matched`} />
        <Stat
          label="Worst gap at Chainlink's last update"
          value={worstAt ? abs(worstAt.g) : "—"}
          note={worstAt ? worstAt.s : "No matched update yet"}
          tone={worstAt && worstAt.g > 0.01 ? "stop" : undefined}
        />
        <Stat label="Median gap now" value={nowGaps.length ? abs(median(nowGaps.map((x) => x.g))) : "—"} note={`${nowGaps.length} of ${rows.length} tokens`} />
        <Stat
          label="Worst gap now"
          value={worstNow ? abs(worstNow.g) : "—"}
          note={worstNow ? `${worstNow.s} · ${withinThreshold} of ${nowGaps.length} inside Chainlink's own 0.5% update threshold` : undefined}
          tone={worstNow && worstNow.g > 0.01 ? "stop" : undefined}
        />
      </div>

      <div className="flex flex-col gap-1 text-[13px] text-muted">
        <span>
          Chainlink&apos;s Robinhood feeds update on a 0.5% move or every 24 hours, so a gap of up to 0.5% &ldquo;now&rdquo; can be
          Chainlink waiting for its threshold. The like-for-like column compares Chainlink&apos;s answer with Slate&apos;s report signed
          within {MATCH_WINDOW}{" "}seconds of Chainlink&apos;s last update. Slate signs the bid/ask midpoint; spreads on thinly traded names
          widen the gap.
        </span>
        {data && (
          <span>
            {verified.length} of {rows.length} reports verified in this browser: {data.signerSet.quorum} of {data.signerSet.signers.length} signers
            on {data.signerSet.chainId === MAINNET ? "mainnet's SignedSource" : "SignedSource on Robinhood Chain testnet, which holds the same keys until mainnet's is deployed"} (
            <span className="font-mono">{data.signerSet.address.slice(0, 6)}…{data.signerSet.address.slice(-4)}</span>).
            {!data.publisherOk && " The publisher is unreachable; showing the last snapshot."}
            {closed && " The market is closed: these are the last prices signed before the close."}
          </span>
        )}
      </div>

      <section aria-label="Every token" className={`${card} overflow-hidden`}>
        {isLoading && <p className="px-4 py-6 text-sm text-muted">Reading Chainlink and verifying signatures…</p>}
        {!isLoading && !data && <p className="px-4 py-6 text-sm text-muted">No signed reports available right now.</p>}
        {rows.length > 0 && (
          <>
            <div role="table" aria-label="Slate and Chainlink by token" className="hidden text-sm lg:block">
              <div role="row" className={`${cols} text-xs tracking-[0.04em] text-muted uppercase`}>
                {["Token", "Multiplier", "Slate", "Chainlink", "Gap now", "Chainlink updated", "Slate then", "Gap then"].map((h, i) => (
                  <div key={h} role="columnheader" className={`py-2.5 font-medium ${i > 0 ? "text-right" : ""}`}>
                    {h}
                  </div>
                ))}
              </div>
              {rows.map((r) => (
                <div key={r.symbol} role="row" className={`${cols} items-center border-t border-border`}>
                  <div role="cell" className="py-2.5 font-semibold" title={r.verdict?.ok ? `Signed by ${r.verdict.signers.join(", ")}` : r.verdict?.reason}>
                    {r.symbol}
                    {r.verdict && !r.verdict.ok && <span className="ml-1.5 text-xs text-stop">unverified</span>}
                  </div>
                  <div role="cell" className="py-2.5 text-right font-mono text-muted">{r.multiplier === null ? "—" : r.multiplier.toFixed(4)}</div>
                  <div role="cell" className="py-2.5 text-right font-mono">{money(r.slateNow)}</div>
                  <div role="cell" className="py-2.5 text-right font-mono">{money(r.chainlink)}</div>
                  <div role="cell" className={`py-2.5 text-right font-mono ${r.gapNow !== null && Math.abs(r.gapNow) > 0.005 ? "text-warn" : ""}`}>{pct(r.gapNow)}</div>
                  <div role="cell" className="py-2.5 text-right text-muted">{ago(r.chainlinkUpdatedAt, now)}</div>
                  <div role="cell" className="py-2.5 text-right font-mono">{money(r.slateAt)}</div>
                  <div role="cell" className={`py-2.5 text-right font-mono font-medium ${r.gapAt !== null && Math.abs(r.gapAt) > 0.005 ? "text-warn" : ""}`}>{pct(r.gapAt)}</div>
                </div>
              ))}
            </div>
            <ul className="flex flex-col lg:hidden">
              {rows.map((r) => (
                <li key={r.symbol} className="flex flex-col gap-1 border-t border-border px-4 py-3 first:border-t-0">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-semibold">
                      {r.symbol}
                      {r.verdict && !r.verdict.ok && <span className="ml-1.5 text-xs text-stop">unverified</span>}
                    </span>
                    <span className="font-mono">{pct(r.gapAt ?? r.gapNow)}</span>
                  </div>
                  <div className="flex justify-between gap-2 text-[13px] text-muted">
                    <span className="font-mono">
                      Slate {money(r.slateNow)} · Chainlink {money(r.chainlink)}
                    </span>
                    <span>{r.gapAt !== null ? "at update" : "now"}</span>
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}
      </section>
      <p className="text-[13px] text-muted">
        Signed reports come from the publisher&apos;s <span className="font-mono">/board</span>{" "}endpoint and are never submitted
        on-chain, so this costs no gas. They are signed for mainnet&apos;s SignedSource, so each one is exactly what a mainnet
        SlateFeed would accept.
      </p>
    </div>
  );
}
