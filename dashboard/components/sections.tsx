"use client";

import { formatUnits } from "viem";
import { useReadContracts } from "wagmi";
import { navFeedAbi, slateFeedAbi } from "@/lib/abi";
import type { DashboardData, FeedRow } from "@/lib/data";
import { FEED_STATUS, meaning, tone, type FeedStatusLabel, type Tone } from "@/lib/status";
import { useQuote } from "./providers";

const toneClass: Record<Tone, string> = {
  ok: "bg-ok-bg text-ok",
  neutral: "bg-neutral-bg text-neutral",
  warn: "bg-warn-bg text-warn",
  stop: "bg-stop-bg text-stop",
};

export function Pill({ status }: { status: FeedStatusLabel }) {
  return <span className={`rounded-md px-2 py-0.5 text-xs font-semibold whitespace-nowrap ${toneClass[tone[status]]}`}>{status}</span>;
}

export function LabTag({ children = "LAB" }: { children?: React.ReactNode }) {
  return <span className="rounded bg-lab-bg px-1.5 py-px text-[11px] font-semibold text-lab">{children}</span>;
}

export const card = "rounded-[14px] border border-border bg-surface";

/** Formats a USD price in the selected quote currency. USDG uses the live USDG/USD Chainlink price. */
export function usePrice(usdgUsd: number | null) {
  const { quote } = useQuote();
  return (usd: number | null) => {
    if (usd === null) return "—";
    if (quote === "USDG") {
      if (!usdgUsd) return "unavailable";
      return `${(usd / usdgUsd).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} USDG`;
    }
    return `$${usd.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  };
}

const explorers: Record<number, string> = {
  4663: "https://robinhoodchain.blockscout.com",
  46630: "https://explorer.testnet.chain.robinhood.com",
  42161: "https://arbiscan.io",
};

const fmtMultiplier = (m: number | null) => (m === null ? "—" : m.toFixed(m >= 10 || Number.isInteger(m * 1000) ? 3 : 6));

export function Overview({ data }: { data: DashboardData }) {
  const price = usePrice(data.usdgUsd);
  const { crwd } = data;
  return (
    <>
      <div className="flex flex-col gap-1">
        <h1 className="text-[26px] font-semibold tracking-[-0.015em]">Feeds</h1>
        <p className="text-muted">Every Slate feed, its source, the multiplier it applies and why it will or won&apos;t serve a price.</p>
      </div>

      <section aria-labelledby="crwd-title" className="grid grid-cols-[repeat(auto-fit,minmax(280px,1fr))] gap-6 rounded-[14px] border border-border-strong bg-surface p-[18px] lg:p-7">
        <div className="flex flex-col gap-[18px]">
          <div className="flex flex-wrap items-center gap-3">
            <div className="flex size-10 items-center justify-center rounded-[9px] border border-border bg-surface-2 font-mono text-[10px] font-semibold">CRWD</div>
            <div className="flex flex-1 flex-col">
              <h2 id="crwd-title" className="text-lg font-semibold">CrowdStrike · CRWD</h2>
              <span className="text-[13px] text-muted">Robinhood Chain · 0xea72…3931 · no Chainlink feed</span>
            </div>
            <Pill status={crwd.snapshot ? "Not deployed" : (data.rows[0]?.status ?? "No data")} />
          </div>
          <div className="grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] items-end gap-3">
            <div className="flex flex-col gap-1">
              <span className="text-xs text-muted">Share price</span>
              <span className="font-mono text-2xl font-medium">{price(crwd.sharePrice)}</span>
            </div>
            <div className="flex flex-col gap-1">
              <span className="text-xs text-muted">× uiMultiplier(), live</span>
              <span className="font-mono text-2xl font-semibold text-accent-text">{fmtMultiplier(crwd.multiplier)}</span>
            </div>
            <div className="flex flex-col gap-1">
              <span className="text-xs text-muted">= one token</span>
              <span className="font-mono text-[28px] font-semibold">{price(crwd.tokenPrice)}</span>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2 rounded-lg bg-surface-2 px-3 py-2.5 text-sm">
            <svg viewBox="0 0 24 24" className="size-4 text-ok" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M20 6 9 17l-5-5" />
            </svg>
            {crwd.snapshot || !crwd.robinhood ? (
              <span>
                Robinhood&apos;s <span className="font-mono">tokenBid</span> at the same moment: <span className="font-mono font-semibold">$1,059.92</span>
              </span>
            ) : (
              <span>
                Robinhood now: <span className="font-mono">tokenBid</span>{" "}
                <span className="font-mono font-semibold">${crwd.robinhood.tokenBid.toFixed(2)}</span>, <span className="font-mono">tokenAsk</span>{" "}
                <span className="font-mono font-semibold">${crwd.robinhood.tokenAsk.toFixed(2)}</span>. Slate signs the mid.
              </span>
            )}
          </div>
          {crwd.snapshot && (
            <p className="text-xs text-muted">
              Share and token price are from Slate&apos;s fork test against the live token (1 Oct 2026) until CRWD&apos;s mainnet
              feed is deployed. The multiplier is read live from the token.
            </p>
          )}
        </div>
        <dl className="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] self-start overflow-hidden rounded-[10px] border border-border text-sm">
          <dt className="border-b border-border px-3 py-2.5 text-muted">Source</dt>
          <dd className="border-b border-border px-3 py-2.5">Signed share price · 3 keys, 2 needed</dd>
          <dt className="border-b border-border px-3 py-2.5 text-muted">Multiplier</dt>
          <dd className="border-b border-border px-3 py-2.5 font-mono">{fmtMultiplier(crwd.multiplier)} since 2 Jul 2026</dd>
          <dt className="border-b border-border px-3 py-2.5 text-muted">Session</dt>
          <dd className="border-b border-border px-3 py-2.5">24/5 extended</dd>
          <dt className="px-3 py-2.5 text-muted">Feed contract</dt>
          <dd className="px-3 py-2.5 font-mono">
            {crwd.feed ? (
              <a href={`https://robinhoodchain.blockscout.com/address/${crwd.feed}`} target="_blank" rel="noreferrer" className="text-accent-text underline-offset-2 hover:underline">
                {crwd.feed.slice(0, 6)}…{crwd.feed.slice(-4)}
              </a>
            ) : (
              "mainnet deploy pending"
            )}
          </dd>
        </dl>
      </section>

      <div className="grid grid-cols-[repeat(auto-fit,minmax(160px,1fr))] gap-3">
        <Stat label="Stock tokens on Robinhood Chain" value={data.coverage ? String(data.coverage.tokens) : "~200"} />
        <Stat label="With a Chainlink feed" value={data.coverage ? String(data.coverage.withFeed) : "35"} />
        <Stat label="Slate feeds live" value={String(data.feedsLive)} />
      </div>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className={`${card} flex flex-col gap-0.5 px-4 py-3.5`}>
      <span className="text-[13px] text-muted">{label}</span>
      <span className="font-mono text-[22px] font-semibold">{value}</span>
    </div>
  );
}

/** Re-reads every deployed feed every 10 seconds; the server's values show until the first read lands. */
function useLiveRows(rows: FeedRow[]): FeedRow[] {
  const deployed = rows.filter((r) => r.feed);
  const { data } = useReadContracts({
    contracts: deployed.map((r) =>
      r.nav
        ? { address: r.feed!, abi: navFeedAbi, functionName: "latestQuote" as const, chainId: r.chainId }
        : { address: r.feed!, abi: slateFeedAbi, functionName: "latestDetail" as const, chainId: r.chainId },
    ),
    query: { refetchInterval: 10_000 },
  });
  return rows.map((r) => {
    const i = deployed.indexOf(r);
    const result = i >= 0 ? data?.[i]?.result : undefined;
    if (!result) return r;
    const quote = (r.nav ? result : (result as readonly unknown[])[0]) as { status: number; answer: bigint };
    const multiplier = r.nav ? r.multiplier : Number(formatUnits((result as readonly [unknown, bigint, bigint])[2], 18));
    return {
      ...r,
      multiplier,
      price: quote.answer > 0n ? Number(formatUnits(quote.answer, 8)) : null,
      status: FEED_STATUS[quote.status] ?? "No data",
    };
  });
}

export function FeedsTable({ rows: serverRows, usdgUsd }: { rows: FeedRow[]; usdgUsd: number | null }) {
  const price = usePrice(usdgUsd);
  const rows = useLiveRows(serverRows);
  const cols = "grid grid-cols-[minmax(0,1.1fr)_minmax(0,1.3fr)_minmax(0,1.9fr)_minmax(0,0.9fr)_minmax(0,1fr)_minmax(0,1.2fr)] gap-x-4 px-4";
  return (
    <section id="feeds" aria-labelledby="feeds-title" className={`${card} scroll-mt-20 overflow-hidden`}>
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3">
        <h2 id="feeds-title" className="font-semibold">All feeds</h2>
      </div>
      <div role="table" aria-label="All feeds" className="hidden text-sm md:block">
        <div role="row" className={`${cols} text-xs tracking-[0.04em] text-muted uppercase`}>
          {["Token", "Network", "Source", "Multiplier", "Price", "Status"].map((h, i) => (
            <div key={h} role="columnheader" className={`py-2.5 font-medium ${i === 3 || i === 4 ? "text-right" : ""}`}>
              {h}
            </div>
          ))}
        </div>
        {rows.map((r) => (
          <div key={`${r.ticker}-${r.network}`} role="row" className={`${cols} items-center border-t border-border`}>
            <div role="cell" className="flex items-center gap-2 py-3 font-semibold">
              {r.feed ? (
                <a href={`${explorers[r.chainId]}/address/${r.feed}`} target="_blank" rel="noreferrer" className="underline-offset-2 hover:underline">
                  {r.ticker}
                </a>
              ) : (
                r.ticker
              )}
              {r.lab && <LabTag />}
            </div>
            <div role="cell" className="py-3 text-muted">{r.network}</div>
            <div role="cell" className="py-3">{r.source}</div>
            <div role="cell" className="py-3 text-right font-mono">{r.nav ? "n/a" : fmtMultiplier(r.multiplier)}</div>
            <div role="cell" className="py-3 text-right font-mono font-medium">{price(r.price)}</div>
            <div role="cell" className="py-3"><Pill status={r.status} /></div>
          </div>
        ))}
      </div>
      <ul className="flex flex-col md:hidden">
        {rows.map((r) => (
          <li key={`${r.ticker}-${r.network}`} className="flex flex-col gap-1.5 border-t border-border px-4 py-3 first:border-t-0">
            <div className="flex items-center justify-between gap-2">
              <span className="flex items-center gap-2 font-semibold">
                {r.ticker}
                {r.lab && <LabTag />}
              </span>
              <span className="font-mono font-semibold">{price(r.price)}</span>
            </div>
            <div className="flex items-center justify-between gap-2 text-[13px] text-muted">
              <span>
                {r.network}
                {r.nav ? "" : ` · ×${fmtMultiplier(r.multiplier)}`}
              </span>
              <Pill status={r.status} />
            </div>
            <span className="text-[13px]">{r.source}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

export function Legend() {
  return (
    <section aria-labelledby="legend-title" className={`${card} flex flex-col gap-3 p-4`}>
      <h2 id="legend-title" className="font-semibold">What a status means</h2>
      <div className="grid grid-cols-[repeat(auto-fit,minmax(230px,1fr))] gap-x-5 gap-y-2.5 text-sm">
        {FEED_STATUS.map((s) => (
          <div key={s} className="flex items-baseline gap-2.5">
            <Pill status={s} />
            <span className="text-muted">{meaning[s]}</span>
          </div>
        ))}
      </div>
    </section>
  );
}
