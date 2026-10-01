"use client";

import type { DashboardData, FeedRow } from "@/lib/data";
import { FEED_STATUS, meaning, tone, type FeedStatusLabel, type Tone } from "@/lib/status";
import { useQuote } from "./providers";

const toneClass: Record<Tone, string> = {
  ok: "bg-ok-bg text-ok",
  neutral: "bg-neutral-bg text-neutral",
  warn: "bg-warn-bg text-warn",
  stop: "bg-stop-bg text-stop",
};

function Pill({ status }: { status: FeedStatusLabel }) {
  return <span className={`rounded-md px-2 py-0.5 text-xs font-semibold whitespace-nowrap ${toneClass[tone[status]]}`}>{status}</span>;
}

function LabTag({ children = "LAB" }: { children?: React.ReactNode }) {
  return <span className="rounded bg-lab-bg px-1.5 py-px text-[11px] font-semibold text-lab">{children}</span>;
}

const card = "rounded-[14px] border border-border bg-surface";

/** Formats a USD price in the selected quote currency. USDG uses the live USDG/USD Chainlink price. */
function usePrice(usdgUsd: number | null) {
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
            <Pill status={crwd.snapshot ? "Not deployed" : "OK"} />
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
            <span>
              Robinhood&apos;s <span className="font-mono">tokenBid</span> at the same moment: <span className="font-mono font-semibold">$1,059.92</span>
            </span>
          </div>
          {crwd.snapshot && (
            <p className="text-xs text-muted">
              Share and token price are from Slate&apos;s fork test against the live token (1 Oct 2026) until CRWD&apos;s feed is
              deployed. The multiplier is read live from the token.
            </p>
          )}
        </div>
        <dl className="grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] self-start overflow-hidden rounded-[10px] border border-border text-sm">
          <dt className="border-b border-border px-3 py-2.5 text-muted">Source</dt>
          <dd className="border-b border-border px-3 py-2.5">Signed share price · 3 of 3</dd>
          <dt className="border-b border-border px-3 py-2.5 text-muted">Multiplier</dt>
          <dd className="border-b border-border px-3 py-2.5 font-mono">{fmtMultiplier(crwd.multiplier)} since 2 Jul 2026</dd>
          <dt className="border-b border-border px-3 py-2.5 text-muted">Session</dt>
          <dd className="border-b border-border px-3 py-2.5">24/5 extended</dd>
          <dt className="px-3 py-2.5 text-muted">Feed contract</dt>
          <dd className="px-3 py-2.5 font-mono">{crwd.snapshot ? "after deploy" : "see deployments"}</dd>
        </dl>
      </section>

      <div className="grid grid-cols-[repeat(auto-fit,minmax(160px,1fr))] gap-3">
        <Stat label="Stock tokens on Robinhood Chain" value="195" />
        <Stat label="With a Chainlink feed" value="35" />
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

export function FeedsTable({ rows, usdgUsd }: { rows: FeedRow[]; usdgUsd: number | null }) {
  const price = usePrice(usdgUsd);
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
              {r.ticker}
              {r.lab && <LabTag />}
            </div>
            <div role="cell" className="py-3 text-muted">{r.network}</div>
            <div role="cell" className="py-3">{r.source}</div>
            <div role="cell" className="py-3 text-right font-mono">{fmtMultiplier(r.multiplier)}</div>
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
                {r.network} · ×{fmtMultiplier(r.multiplier)}
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

export function BasketAndCreate() {
  return (
    <div className="grid grid-cols-[repeat(auto-fit,minmax(300px,1fr))] gap-4">
      <section id="basket" aria-labelledby="basket-title" className={`${card} flex scroll-mt-20 flex-col gap-4 p-5`}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="basket-title" className="text-lg font-semibold">SLATE-5 basket</h2>
          <span className="rounded-md bg-surface-2 px-2 py-0.5 text-xs font-semibold">AggregatorV3Interface</span>
        </div>
        <div className="flex flex-wrap gap-6">
          <div className="flex flex-col gap-0.5">
            <span className="text-xs text-muted">NAV per share</span>
            <span className="font-mono text-2xl font-semibold">—</span>
          </div>
          <div className="flex flex-col gap-0.5">
            <span className="text-xs text-muted">NAV feed</span>
            <span className="pt-1.5 font-mono text-[15px]">after deploy</span>
          </div>
        </div>
        <div className="flex flex-col gap-1.5">
          {["TSLA", "AMZN", "AMD", "PLTR", "NFLX"].map((t) => (
            <div key={t} className="flex items-center gap-2.5 text-sm">
              <span className="w-[54px] font-semibold">{t}</span>
              <div className="h-2 flex-1 overflow-hidden rounded bg-surface-2">
                <div className="h-2 w-1/5 bg-muted" />
              </div>
              <span className="font-mono text-muted">20%</span>
            </div>
          ))}
        </div>
        <p className="text-[13px] text-muted">
          Equal value at creation, fixed composition. Rebalancing is v2: it needs a price to act on, and in-kind create and
          redeem never use one.
        </p>
      </section>

      <section id="create" aria-labelledby="create-title" className={`${card} flex scroll-mt-20 flex-col gap-4 p-5`}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="create-title" className="text-lg font-semibold">Create &amp; redeem</h2>
          <div role="tablist" aria-label="Creation mode" className="inline-flex overflow-hidden rounded-lg border border-border">
            <button type="button" role="tab" aria-selected="false" className="px-3 py-2 text-sm text-muted hover:text-text">
              In kind
            </button>
            <button type="button" role="tab" aria-selected="true" className="bg-surface-2 px-3 py-2 text-sm font-semibold">
              With cash
            </button>
          </div>
        </div>
        <label className="flex flex-col gap-1.5 text-sm">
          <span>Pay with TESTUSD (Slate Test Dollar)</span>
          <input
            type="text"
            inputMode="decimal"
            placeholder="1,000.00"
            disabled
            className="rounded-lg border border-border bg-bg p-3 font-mono text-lg disabled:opacity-70"
          />
          <span className="text-[13px] text-muted">Testnet stand-in for Paxos USDG. Not USDG. On mainnet this field takes USDG.</span>
        </label>
        <div className="flex gap-2 rounded-lg bg-warn-bg px-3 py-2.5 text-sm">
          <svg viewBox="0 0 24 24" className="mt-0.5 size-4 shrink-0 text-warn" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
            <circle cx="12" cy="12" r="9" />
            <path d="M5.6 5.6l12.8 12.8" />
          </svg>
          <span>
            Slate refuses routes priced far from SlateFeed. Today&apos;s third-party TSLA/USDC pool on testnet prices TSLA at
            $0.067, against $354.11.
          </span>
        </div>
        <button type="button" disabled className="min-h-[46px] rounded-[10px] bg-accent px-4 font-semibold text-on-accent disabled:opacity-60">
          Create SLATE-5 · after deploy
        </button>
      </section>
    </div>
  );
}

export function Lab() {
  return (
    <section id="lab" aria-labelledby="lab-title" className="flex scroll-mt-20 flex-wrap items-center justify-between gap-4 rounded-[14px] border border-dashed border-lab-border p-5">
      <div className="flex max-w-[760px] flex-col gap-1">
        <h2 id="lab-title" className="flex flex-wrap items-center gap-2 text-lg font-semibold">
          Corporate Action Lab <LabTag>LAB · ARBITRUM ONE</LabTag>
        </h2>
        <p className="text-muted">
          Schedule a split on a Slate Lab token, priced by Chainlink&apos;s real TSLA feed, and watch a naive feed jump while
          SlateFeed holds. Lab tokens are Slate&apos;s test tokens, not Robinhood&apos;s.
        </p>
      </div>
      <span className="rounded-[10px] border border-border px-4 py-3 font-medium text-muted">Opens after deploy</span>
    </section>
  );
}
