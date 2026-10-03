"use client";

import { useEffect, useState } from "react";
import { PUBLISHER_URL, median } from "@/lib/board";
import { card } from "./sections";

type Point = { t: number; slate: number; chainlink: number; gapPct: number };
type Matched = Point & { slateAt: number };
type Token = { multiplier: number; slateReports: number; chainlinkRounds: number; matched: Matched[]; series: Point[] };
type History4 = { from: number; to: number; matchWindow: number; tokens: Record<string, Token> };
type Hour = {
  hour: number;
  tokens: number;
  medianNowPct: number;
  worstNowPct: number;
  worstNowSymbol: string;
  medianThenPct: number | null;
  worstThenPct: number | null;
  worstThenSymbol: string | null;
  matched: number;
};
type Live = { collecting: boolean; since: number | null; rows: number; tokens?: number; hours: Hour[] };

const ny = (t: number, withDay = true) =>
  new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", ...(withDay ? { weekday: "short", day: "numeric", month: "short" } : {}), hour: "2-digit", minute: "2-digit", hour12: false }).format(t * 1000);
const pct = (x: number, d = 2) => `${x.toFixed(d)}%`;
const THRESHOLD = 0.5; // Chainlink's Robinhood feeds: a 0.5% deviation threshold (and a 24 h heartbeat)

function Stat({ label, value, note, worst = false }: { label: string; value: string; note: string; worst?: boolean }) {
  return (
    <div className={`${card} flex flex-col gap-1 p-4 ${worst ? "border-warn" : ""}`}>
      <span className="text-xs text-muted">{label}</span>
      <span className={`font-mono text-2xl font-semibold ${worst ? "text-warn" : ""}`}>{value}</span>
      <span className="text-[13px] text-muted">{note}</span>
    </div>
  );
}

/** One token: Slate's gap to Chainlink over time (line), each like-for-like match (dots), Chainlink's threshold (band). */
function TokenChart({ symbol, t, from, to }: { symbol: string; t: Token; from: number; to: number }) {
  const W = 460, H = 180, L = 40, R = 10, T = 12, B = 24;
  const worst = t.series.reduce((a, b) => (Math.abs(b.gapPct) > Math.abs(a.gapPct) ? b : a), t.series[0]);
  const lim = Math.max(1, Math.ceil(Math.max(...t.series.map((p) => Math.abs(p.gapPct))) * 2) / 2);
  const x = (s: number) => L + ((s - from) / (to - from)) * (W - L - R);
  const y = (g: number) => T + ((lim - g) / (2 * lim)) * (H - T - B);
  const path = t.series.map((p, i) => `${i ? "L" : "M"}${x(p.t).toFixed(1)},${y(p.gapPct).toFixed(1)}`).join("");
  const ticks = [-lim, -THRESHOLD, 0, THRESHOLD, lim];
  // Midnight New York time, for day ticks (EDT, UTC−4, throughout these dates).
  const days: number[] = [];
  for (let d = Math.ceil((from - 4 * 3600) / 86400) * 86400 + 4 * 3600; d < to; d += 86400) days.push(d);
  const m = t.matched.map((p) => Math.abs(p.gapPct));
  return (
    <figure className={`${card} flex min-w-0 flex-col gap-2 p-4`}>
      <figcaption className="flex flex-wrap items-baseline justify-between gap-2 text-sm">
        <span className="font-semibold">{symbol}</span>
        <span className="text-[13px] text-muted">
          {t.slateReports} Slate reports · {t.matched.length} like-for-like · median {pct(median(m), 3)}, worst {pct(Math.max(...m), 2)}
        </span>
      </figcaption>
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full" role="img" aria-label={`${symbol}: Slate's gap to Chainlink over time, worst ${pct(Math.abs(worst.gapPct))}`}>
        <rect x={L} y={y(THRESHOLD)} width={W - L - R} height={y(-THRESHOLD) - y(THRESHOLD)} fill="var(--surface-2)" />
        {ticks.map((g) => (
          <g key={g}>
            <line x1={L} x2={W - R} y1={y(g)} y2={y(g)} stroke="var(--border)" strokeDasharray={g === 0 ? undefined : "3 3"} />
            <text x={L - 6} y={y(g) + 3.5} textAnchor="end" fontSize="10" fill="var(--muted)">
              {g > 0 ? "+" : ""}
              {g}%
            </text>
          </g>
        ))}
        {days.map((d) => (
          <g key={d}>
            <line x1={x(d)} x2={x(d)} y1={T} y2={H - B} stroke="var(--border)" />
            <text x={x(d) + 3} y={H - 9} fontSize="10" fill="var(--muted)">
              {new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", weekday: "short", day: "numeric", month: "short" }).format(d * 1000)}
            </text>
          </g>
        ))}
        <path d={path} fill="none" stroke="var(--muted)" strokeWidth="1" />
        {t.matched.map((p) => (
          <circle key={p.t} cx={x(p.t)} cy={y(p.gapPct)} r="2.6" fill="var(--accent)" stroke="var(--surface)" strokeWidth="0.8" />
        ))}
        <circle cx={x(worst.t)} cy={y(worst.gapPct)} r="5" fill="none" stroke="var(--warn)" strokeWidth="1.5" />
        <text
          x={Math.min(x(worst.t) + 8, W - R - 4)}
          y={Math.max(T + 10, Math.min(y(worst.gapPct) + 4, H - B - 4))}
          textAnchor={x(worst.t) > W - 150 ? "end" : "start"}
          fontSize="10.5"
          fill="var(--warn)"
          dx={x(worst.t) > W - 150 ? -16 : 0}
        >
          worst {worst.gapPct > 0 ? "+" : ""}
          {worst.gapPct.toFixed(2)}%
        </text>
      </svg>
    </figure>
  );
}

function LiveChart({ hours }: { hours: Hour[] }) {
  const W = 640, H = 190, L = 44, R = 12, T = 12, B = 26;
  const from = hours[0].hour, to = Math.max(hours.at(-1)!.hour, from + 3600);
  const lim = Math.max(0.5, Math.ceil(Math.max(...hours.map((h) => h.worstNowPct)) * 4) / 4);
  const x = (s: number) => L + ((s - from) / (to - from)) * (W - L - R);
  const y = (g: number) => T + ((lim - g) / lim) * (H - T - B);
  const line = (f: (h: Hour) => number | null) =>
    hours
      .filter((h) => f(h) !== null)
      .map((h, i) => `${i ? "L" : "M"}${x(h.hour).toFixed(1)},${y(f(h)!).toFixed(1)}`)
      .join("");
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full" role="img" aria-label="Median and worst gap to Chainlink across the covered tokens, by hour">
      {[0, lim / 2, lim].map((g) => (
        <g key={g}>
          <line x1={L} x2={W - R} y1={y(g)} y2={y(g)} stroke="var(--border)" strokeDasharray={g ? "3 3" : undefined} />
          <text x={L - 6} y={y(g) + 3.5} textAnchor="end" fontSize="10" fill="var(--muted)">
            {g.toFixed(2)}%
          </text>
        </g>
      ))}
      <path d={line((h) => h.worstNowPct)} fill="none" stroke="var(--warn)" strokeWidth="1.6" />
      <path d={line((h) => h.medianNowPct)} fill="none" stroke="var(--accent)" strokeWidth="1.6" />
      {hours.map((h) => (
        <g key={h.hour}>
          <circle cx={x(h.hour)} cy={y(h.worstNowPct)} r="2.5" fill="var(--warn)" />
          <circle cx={x(h.hour)} cy={y(h.medianNowPct)} r="2.5" fill="var(--accent)" />
        </g>
      ))}
      <text x={L} y={H - 8} fontSize="10" fill="var(--muted)">
        {ny(from)}
      </text>
      <text x={W - R} y={H - 8} textAnchor="end" fontSize="10" fill="var(--muted)">
        {ny(to)}
      </text>
    </svg>
  );
}

export function AccuracyHistory() {
  const [h4, setH4] = useState<History4 | null>(null);
  const [live, setLive] = useState<Live | null>(null);
  useEffect(() => {
    fetch("/accuracy-history-4.json")
      .then((r) => r.json())
      .then(setH4)
      .catch(() => {});
    fetch(`${PUBLISHER_URL}/history`, { signal: AbortSignal.timeout(15_000) })
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => d && setLive(d))
      .catch(() => {});
  }, []);

  const tokens = h4 ? Object.entries(h4.tokens) : [];
  const matched = tokens.flatMap(([s, t]) => t.matched.map((p) => ({ s, ...p })));
  const series = tokens.flatMap(([s, t]) => t.series.map((p) => ({ s, ...p })));
  const worstM = matched.reduce((a, b) => (Math.abs(b.gapPct) > Math.abs(a.gapPct) ? b : a), matched[0]);
  const worstS = series.reduce((a, b) => (Math.abs(b.gapPct) > Math.abs(a.gapPct) ? b : a), series[0]);
  // A single report far from the reports either side of it: Slate's own outlier, not Chainlink lagging.
  const outliers = tokens.flatMap(([s, t]) =>
    t.series.slice(1, -1).flatMap((p, i) => {
      const prev = t.series[i], next = t.series[i + 2];
      const off = p.slate / ((prev.slate + next.slate) / 2) - 1;
      // Its neighbours agree with each other (within 0.25%), and it is more than 0.5% from them.
      return Math.abs(off) > 0.005 && Math.abs(prev.slate / next.slate - 1) < 0.0025 ? [{ s, ...p, off, next }] : [];
    }),
  );
  const lastHour = live?.hours.at(-1);

  return (
    <section aria-labelledby="history-title" className="flex flex-col gap-4">
      <div className="flex max-w-[860px] flex-col gap-1">
        <h2 id="history-title" className="text-xl font-semibold tracking-[-0.01em]">
          Accuracy over time
        </h2>
        <p className="text-muted">The board above is one moment. These are the same comparisons over time, with the worst case shown as plainly as the median.</p>
      </div>

      {live?.collecting && (
        <div className={`${card} flex flex-col gap-3 p-5`}>
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h3 className="font-semibold">All {live.tokens || 35} tokens, collecting hourly</h3>
            {lastHour && (
              <span className="text-[13px] text-muted">
                Latest hour ({ny(lastHour.hour)} New York, {lastHour.tokens} {lastHour.tokens === 1 ? "token" : "tokens"}): median <span className="font-mono text-text">{pct(lastHour.medianNowPct)}</span>, worst{" "}
                <span className="font-mono text-warn">
                  {pct(lastHour.worstNowPct)} ({lastHour.worstNowSymbol})
                </span>
              </span>
            )}
          </div>
          <p className="text-sm text-muted">
            Every hour the publisher stores this board for all {live.tokens || 35}{" "}tokens Chainlink prices: Slate&apos;s signed report, Chainlink&apos;s answer
            read from mainnet and the gap, computed as above. Slate signs only while the market is open, so the history fills in from Monday&apos;s open (Sun 4 Oct,
            20:00 New York time; Mon 5 Oct, 05:30 IST) and grows every hour of every session after that.
          </p>
          {live.hours.length > 0 ? (
            <>
              <LiveChart hours={live.hours} />
              <p className="text-[13px] text-muted">
                <span className="font-semibold text-accent-text">Median</span> and <span className="font-semibold text-warn">worst</span>{" "}gap now across the tokens, by the
                hour Slate&apos;s price was observed. {live.hours.length} {live.hours.length === 1 ? "hour" : "hours"} so far, {live.rows}{" "}stored rows; the first holds
                the last reports signed before Friday&apos;s close.
              </p>
            </>
          ) : (
            <p className="text-sm">No snapshot stored yet.</p>
          )}
        </div>
      )}

      {h4 && worstM && worstS && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-1">
            <h3 className="font-semibold">So far: 4 tokens over 2 sessions</h3>
            <p className="text-sm text-muted">
              <b className="text-text">TSLA, AMD, AMZN and PLTR</b>, Robinhood&apos;s 24/5 sessions of <b className="text-text">Thu 1 Oct 2026</b> (from {ny(h4.from, false)} New
              York time) and <b className="text-text">Fri 2 Oct 2026</b>, to {ny(h4.to)}. Slate&apos;s signed share prices <b className="text-text">as published on Robinhood
              Chain testnet</b> (the only Slate prices on-chain for these tokens), times each token&apos;s mainnet multiplier (1.000, never changed), against{" "}
              <b className="text-text">Chainlink&apos;s answers on Robinhood Chain mainnet</b>. Built from chain data only:{" "}
              <a href="https://github.com/Slate-Protocol/slate/blob/main/dashboard/scripts/accuracy-history-4.mjs" className="text-accent-text hover:underline">
                the script
              </a>
              .
            </p>
          </div>
          <div className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-3">
            <Stat label="Like for like: median" value={pct(median(matched.map((p) => Math.abs(p.gapPct))), 3)} note={`${matched.length} Chainlink updates, each against Slate's report signed within ${h4.matchWindow} s`} />
            <Stat
              label="Like for like: worst"
              value={pct(Math.abs(worstM.gapPct))}
              note={`${worstM.s}, ${ny(worstM.t)} New York: Slate $${worstM.slate.toFixed(2)}, Chainlink $${worstM.chainlink.toFixed(2)}`}
              worst
            />
            <Stat label="Every report: median" value={pct(median(series.map((p) => Math.abs(p.gapPct))))} note={`${series.length.toLocaleString("en-US")} Slate reports, each against Chainlink's answer in force at the time`} />
            <Stat
              label="Every report: worst"
              value={pct(Math.abs(worstS.gapPct))}
              note={`${worstS.s}, ${ny(worstS.t)} New York: Slate $${worstS.slate.toFixed(2)}, Chainlink $${worstS.chainlink.toFixed(2)}`}
              worst
            />
          </div>
          {outliers.length > 0 && (
            <p className={`${card} border-warn p-4 text-sm`}>
              <b>The worst gap is Slate&apos;s, not Chainlink&apos;s.</b>{" "}
              {outliers.map((o) => (
                <span key={`${o.s}${o.t}`}>
                  One {o.s} report signed at {ny(o.t)} New York time (overnight, in the 24/5 session) read ${o.slate.toFixed(2)}, {pct(Math.abs(o.off * 100), 1)}{" "}
                  {o.off < 0 ? "below" : "above"} the reports either side of it; the next, {Math.round((o.next.t - o.t) / 60)} min later, was ${o.next.slate.toFixed(2)}.{" "}
                </span>
              ))}
              {outliers.length === 1 ? "It is the only report" : `They are the only ${outliers.length} reports`} of the {series.length.toLocaleString("en-US")}{" "}that far from
              their neighbours. Slate signs the midpoint of Robinhood&apos;s bid and ask, and the publisher&apos;s checks did not refuse this one: the testnet feed served
              that price until the next report replaced it.
            </p>
          )}
          <p className="text-[13px] text-muted">
            The grey line is every report&apos;s gap to Chainlink&apos;s answer in force at the time; Chainlink updates only on a {THRESHOLD}% move (or every 24 h), so gaps
            inside the shaded ±{THRESHOLD}% band are often Chainlink waiting. The gold dots are like for like: Slate&apos;s report signed within {h4.matchWindow} s of each
            Chainlink update.
          </p>
          <div className="grid grid-cols-[repeat(auto-fit,minmax(min(100%,440px),1fr))] gap-3">
            {tokens.map(([s, t]) => (
              <TokenChart key={s} symbol={s} t={t} from={h4.from} to={h4.to} />
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
