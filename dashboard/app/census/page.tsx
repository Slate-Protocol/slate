import type { Metadata } from "next";
import { card } from "@/components/sections";
import { Shell } from "@/components/shell";
import { census, type CensusRow } from "@/lib/census";

export const revalidate = 300;

export const metadata: Metadata = {
  title: "Multiplier census",
  description: "Every Robinhood stock token on mainnet, its ERC-8056 multiplier read from the chain, and how wrong a price that ignores it would be.",
};

const EXPLORER = "https://robinhoodchain.blockscout.com";
const day = (t: number) => new Date(t * 1000).toUTCString().slice(5, 16);
const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

function Stat({ label, value, note }: { label: string; value: string; note: string }) {
  return (
    <div className={`${card} flex flex-col gap-1 p-4`}>
      <span className="text-xs text-muted">{label}</span>
      <span className="font-mono text-2xl font-semibold">{value}</span>
      <span className="text-[13px] text-muted">{note}</span>
    </div>
  );
}

function Yes({ on, label }: { on: boolean; label: string }) {
  return on ? (
    <span className="rounded-md bg-ok-bg px-2 py-0.5 text-xs font-semibold text-ok">{label}</span>
  ) : (
    <span className="text-xs text-muted">none</span>
  );
}

function Table({ rows }: { rows: CensusRow[] }) {
  const cols = "grid grid-cols-[minmax(0,0.8fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.1fr)_minmax(0,0.9fr)_minmax(0,1fr)] gap-x-4 px-4";
  return (
    <>
      <div role="table" aria-label="Tokens with a multiplier other than 1" className="hidden text-sm md:block">
        <div role="row" className={`${cols} text-xs tracking-[0.04em] text-muted uppercase`}>
          {["Token", "Multiplier", "Blind price is low by", "In force since", "Chainlink", "Slate (mainnet)"].map((h, i) => (
            <div key={h} role="columnheader" className={`py-2.5 font-medium ${i === 1 || i === 2 ? "text-right" : ""}`}>
              {h}
            </div>
          ))}
        </div>
        {rows.map((r) => (
          <div key={r.token} role="row" className={`${cols} items-center border-t border-border`}>
            <div role="cell" className="py-2.5 font-semibold">
              <a href={`${EXPLORER}/address/${r.token}`} target="_blank" rel="noreferrer" className="hover:underline">
                {r.symbol}
              </a>
            </div>
            <div role="cell" className="py-2.5 text-right font-mono">{r.multiplier?.toFixed(6) ?? "—"}</div>
            <div role="cell" className={`py-2.5 text-right font-mono ${(r.blindLowPct ?? 0) >= 1 ? "text-warn font-semibold" : ""}`}>
              {r.blindLowPct !== null ? `${r.blindLowPct.toFixed(r.blindLowPct >= 1 ? 2 : 3)}%` : "—"}
            </div>
            <div role="cell" className="py-2.5 text-muted">{r.effectiveAt ? day(r.effectiveAt) : "—"}</div>
            <div role="cell" className="py-2.5"><Yes on={r.chainlink} label="feed" /></div>
            <div role="cell" className="py-2.5">
              {r.slateFeed ? (
                <a href={`${EXPLORER}/address/${r.slateFeed}`} target="_blank" rel="noreferrer" className="font-mono text-[13px] text-accent-text hover:underline">
                  {short(r.slateFeed)}
                </a>
              ) : (
                <span className="text-xs text-muted">not yet</span>
              )}
            </div>
          </div>
        ))}
      </div>
      <ul className="flex flex-col md:hidden">
        {rows.map((r) => (
          <li key={r.token} className="flex flex-col gap-1 border-t border-border px-4 py-3 first:border-t-0">
            <div className="flex items-center justify-between gap-2">
              <span className="font-semibold">{r.symbol}</span>
              <span className={`font-mono ${(r.blindLowPct ?? 0) >= 1 ? "font-semibold text-warn" : ""}`}>
                {r.blindLowPct !== null ? `−${r.blindLowPct.toFixed(r.blindLowPct >= 1 ? 2 : 3)}%` : "—"}
              </span>
            </div>
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[13px] text-muted">
              <span className="font-mono">×{r.multiplier?.toFixed(6)}</span>
              {r.effectiveAt && <span>since {day(r.effectiveAt)}</span>}
              <span>Chainlink: {r.chainlink ? "feed" : "none"}</span>
              <span>Slate: {r.slateFeed ? short(r.slateFeed) : "not yet"}</span>
            </div>
          </li>
        ))}
      </ul>
    </>
  );
}

export default async function CensusPage() {
  const c = await census();
  const nonOne = c.rows.filter((r) => r.multiplierRaw !== null && r.multiplierRaw !== "1000000000000000000");
  const one = c.rows.filter((r) => r.multiplierRaw === "1000000000000000000");
  const worstSmall = nonOne.filter((r) => (r.multiplier ?? 1) < 1.5).sort((a, b) => (b.blindLowPct ?? 0) - (a.blindLowPct ?? 0))[0];
  return (
    <Shell>
      <div className="flex max-w-[820px] flex-col gap-1">
        <h1 className="text-[26px] font-semibold tracking-[-0.015em]">Multiplier census</h1>
        <p className="text-muted">
          Every stock token in Robinhood&apos;s registry on Robinhood Chain mainnet, with its ERC-8056 multiplier read from the chain. A token is worth share price ×
          multiplier, so a price that ignores the multiplier is low by 1 − 1/multiplier. This is why Slate applies the multiplier in force when each price was
          observed, on every token, not only after a split.
        </p>
      </div>

      <div className="grid grid-cols-[repeat(auto-fit,minmax(190px,1fr))] gap-3">
        <Stat label="Stock tokens on mainnet" value={String(c.tokens)} note={`read at block ${c.block.toLocaleString("en-US")}`} />
        <Stat label="Multiplier other than 1" value={String(c.nonOne)} note={`${c.splits} split, ${c.nonOne - c.splits} small adjustments`} />
        <Stat label="…of those, no Chainlink feed" value={String(c.nonOneUncovered)} note={`${c.nonOneUncoveredWithSlate} already have a Slate feed on mainnet`} />
        <Stat label="Changed in the last 30 days" value={String(c.changed30)} note={`${c.changed30Uncovered} with no Chainlink feed; ${c.changed7} in the last 7 days`} />
        <Stat
          label="Largest error, multiplier ignored"
          value={nonOne[0]?.blindLowPct ? `${nonOne[0].blindLowPct.toFixed(0)}%` : "—"}
          note={`${nonOne[0]?.symbol ?? ""} (×${nonOne[0]?.multiplier?.toFixed(0) ?? ""})${worstSmall ? `; next ${worstSmall.symbol}, ${worstSmall.blindLowPct?.toFixed(2)}%` : ""}`}
        />
      </div>

      <p className="text-sm text-muted">
        Chainlink&apos;s Robinhood feeds are total-return feeds: they already include the multiplier, so a token with a Chainlink feed is priced correctly by it. The
        risk is for the {c.nonOneUncovered} tokens with a multiplier and no feed, priced by anyone who pairs a share price with the wrong multiplier, or with
        none. Multiplier changes are routine, not rare: {c.changed30} of these took effect in the last 30 days (a floor, since a token reports only its
        latest change). {c.pending === 0 ? "No multiplier change is scheduled at this block." : `${c.pending} multiplier change${c.pending === 1 ? " is" : "s are"} scheduled.`}
        {c.failed ? ` ${c.failed} tokens could not be read at this block.` : ""}
      </p>

      <section className={`${card} overflow-hidden`} aria-labelledby="census-title">
        <div className="flex flex-wrap items-baseline justify-between gap-2 border-b border-border px-4 py-3">
          <h2 id="census-title" className="font-semibold">
            The {c.nonOne} tokens with a multiplier other than 1
          </h2>
          <span className="text-[13px] text-muted">largest error first · refreshed every 5 minutes</span>
        </div>
        <Table rows={nonOne} />
      </section>

      <details className={`${card} p-4 text-sm`}>
        <summary className="cursor-pointer font-medium">The other {one.length} tokens, multiplier exactly 1.000</summary>
        <p className="mt-3 font-mono text-[13px] leading-relaxed text-muted">{one.map((r) => r.symbol).join(" · ")}</p>
      </details>

      <p className="text-[13px] text-muted">
        Sources: Robinhood&apos;s token registry (api.robinhood.com/rhj/assets) for the token list; each token&apos;s uiMultiplier(), newUIMultiplier() and effectiveAt()
        read from Robinhood Chain mainnet at the block shown; Chainlink&apos;s feed directory for coverage. Rebuild the numbers yourself:{" "}
        <a href="https://github.com/Slate-Protocol/slate/blob/main/dashboard/scripts/multiplier-census.mjs" className="text-accent-text hover:underline">
          scripts/multiplier-census.mjs
        </a>
        .
      </p>
    </Shell>
  );
}
