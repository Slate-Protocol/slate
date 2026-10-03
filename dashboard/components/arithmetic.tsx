"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { getAddress, isAddress, type Address } from "viem";
import type { ChainId } from "@/lib/chains";
import { fixed, readFeed, type FeedRead } from "@/lib/feedread";
import type { FeedStatusLabel } from "@/lib/status";
import { Pill, card } from "./sections";

type Option = { symbol: string; feed: Address; chainId: ChainId };
type Slate = Extract<FeedRead, { kind: "slate" }>;

const ONE = 10n ** 18n;
const utc = (t: number) => new Date(t * 1000).toUTCString().replace("GMT", "UTC");
const dur = (s: number) => (s < 120 ? `${s} s` : s < 7200 ? `${Math.round(s / 60)} min` : s < 172800 ? `${(s / 3600).toFixed(1)} h` : `${(s / 86400).toFixed(1)} days`);
const mono = "font-mono text-[13px]";

function Step({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <li className={`${card} flex gap-4 p-5`}>
      <span className="flex size-8 shrink-0 items-center justify-center rounded-full border border-border font-mono text-sm font-semibold">{n}</span>
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <h2 className="font-semibold">{title}</h2>
        {children}
      </div>
    </li>
  );
}

function Calc({ children }: { children: React.ReactNode }) {
  return <div className={`overflow-x-auto rounded-lg bg-code px-3.5 py-2.5 ${mono} leading-relaxed`}>{children}</div>;
}

/** The multiplier SlateFeed applies, and why: its `_multiplierAt` rule with this token's numbers. */
function multiplierReason(r: Slate) {
  const e = r.effectiveAt ?? 0;
  if (r.model !== 1) return "This token has no multiplier model, so one token is one share.";
  if (e === 0) return "No multiplier change has ever been scheduled for this token (effectiveAt() = 0), so the current multiplier applies.";
  if (r.observedAt >= e) return `The price was observed after the current multiplier took effect (${utc(e)}), so the current multiplier applies.`;
  if (r.now < e) return `A change is scheduled for ${utc(e)} but has not happened yet, so the current multiplier applies.`;
  return `The price was observed before the multiplier changed at ${utc(e)}: the feed uses the multiplier recorded before the change, or refuses (Straddle) if it never recorded one.`;
}

/** SlateFeed's `_status` checks, in its order, with this feed's numbers; the first that decides is marked. */
function statusChecks(r: Slate) {
  const age = r.now - r.observedAt;
  const checks: { label: string; detail: string; decides: boolean }[] = [];
  let decided = false;
  const push = (label: string, detail: string, hit: boolean) => {
    checks.push({ label, detail, decides: hit && !decided });
    if (hit) decided = true;
  };
  push("Oracle paused?", r.oraclePaused === undefined ? "The token has no pause flag." : r.oraclePaused ? "Yes: Robinhood's oraclePaused() is set." : "No: oraclePaused() is false.", r.oraclePaused === true);
  const e = r.effectiveAt ?? 0;
  const inWindow = !!r.multiplierApplied && e !== 0 && r.now >= e && r.observedAt < e + (r.corporateActionGrace ?? 0);
  push(
    "Inside a corporate action?",
    !r.multiplierApplied
      ? "This feed's price already includes the multiplier."
      : e === 0
        ? "No multiplier change on record."
        : inWindow
          ? `Yes: the multiplier changed at ${utc(e)} and the price is not yet ${dur(r.corporateActionGrace ?? 0)} past it.`
          : `No: the last change (${utc(e)}) is more than the ${dur(r.corporateActionGrace ?? 0)} grace window before this price.`,
    inWindow && (r.status === "Corporate action" || r.status === "Straddle"),
  );
  push("Fresh?", `Observed ${dur(age)} ago; this feed allows ${dur(r.maxAge ?? 0)} (maxAge).`, age <= (r.maxAge ?? 0));
  const closed = r.closedSince ?? 0;
  push(
    "Market closed since the price?",
    closed === 0
      ? `The ${r.session === "EXTENDED" ? "24/5" : "regular"} session is open now, per the on-chain calendar.`
      : `The ${r.session === "EXTENDED" ? "24/5" : "regular"} session closed at ${utc(closed)}, and the price was fresh at the close (observed + maxAge ≥ the close).`,
    closed !== 0 && r.observedAt + (r.maxAge ?? 0) >= closed,
  );
  push("Otherwise", "Stale: too old, with the market open.", true);
  return checks;
}

export function Arithmetic({ options }: { options: Option[] }) {
  const [sel, setSel] = useState<Option | null>(null);
  const [r, setR] = useState<FeedRead | null>(null);
  const [error, setError] = useState<string | null>(null);
  const latest = useRef(0);

  const load = useCallback(async (o: Option) => {
    const n = ++latest.current;
    setSel(o);
    setError(null);
    try {
      const res = await readFeed(o.chainId, o.feed);
      if (n === latest.current) setR(res);
    } catch (e) {
      if (n === latest.current) setError(e instanceof Error ? e.message.split("\n")[0] : String(e));
    }
  }, []);

  useEffect(() => {
    // From the URL (?feed=0x…&network=testnet), else CRWD; from a timer, as an effect must not set state synchronously.
    const q = new URLSearchParams(window.location.search);
    const feed = q.get("feed");
    const chainId: ChainId = q.get("network") === "testnet" ? 46630 : 4663;
    const fromUrl = feed && isAddress(feed) ? (options.find((o) => o.feed.toLowerCase() === feed.toLowerCase()) ?? { symbol: feed, feed: getAddress(feed), chainId }) : null;
    const first = fromUrl ?? options.find((o) => o.symbol === "CRWD") ?? options[0];
    const t = setTimeout(() => first && void load(first), 0);
    return () => clearTimeout(t);
  }, [load, options]);

  const s = r && r.kind === "slate" && sel && r.address.toLowerCase() === sel.feed.toLowerCase() ? r : null;
  const loading = !!sel && !s && !error && !(r && r.kind !== "slate");
  const obs = s?.observation;
  const raw = s?.priceKind === "RAW_UNDERLYING";
  const computed = s && obs ? (raw ? (s.multiplierApplied ? (obs.price * s.multiplier) / ONE : obs.price) : obs.price) : null;

  return (
    <>
      <div className="flex max-w-[780px] flex-col gap-1">
        <h1 className="text-[26px] font-semibold tracking-[-0.015em]">The arithmetic, shown</h1>
        <p className="text-muted">
          A stock token&apos;s price is a share price times the token&apos;s multiplier, but only the multiplier in force when that share
          price was observed. Pick a token: every number below is read from the chain now, and each step is the one SlateFeed
          takes.
        </p>
      </div>

      <label className={`${card} flex flex-col gap-2 p-5 sm:flex-row sm:items-center`}>
        <span className="text-sm text-muted">Token</span>
        <select
          value={sel ? `${sel.chainId}:${sel.feed}` : ""}
          onChange={(e) => {
            const o = options.find((x) => `${x.chainId}:${x.feed}` === e.target.value);
            if (o) void load(o);
          }}
          className="min-h-[44px] rounded-lg border border-border bg-bg px-3 font-semibold sm:min-w-[320px]"
        >
          {options.map((o) => (
            <option key={`${o.chainId}:${o.feed}`} value={`${o.chainId}:${o.feed}`}>
              {o.symbol} · {o.chainId === 4663 ? "Robinhood Chain" : "testnet"}
            </option>
          ))}
        </select>
        {s && (
          <span className="self-start sm:self-auto">
            <Pill status={s.status as FeedStatusLabel} />
          </span>
        )}
      </label>

      {error && <p className="text-sm text-warn">Could not read the feed: {error}</p>}
      {loading && <p className="text-sm text-muted">Reading from the chain…</p>}
      {r && r.kind !== "slate" && <p className={`${card} p-5 text-sm`}>That address is not a SlateFeed.</p>}

      {s && obs && computed !== null && (
        <ol className="flex flex-col gap-3">
          <Step n={1} title={raw ? "The signed share price" : "The price the source reports"}>
            <p className="text-sm text-muted">
              {raw
                ? `The feed asks its source, SignedSource, for ${s.feedName}: a share price signed by at least 2 of Slate's 3 signers, and when it was observed.`
                : `The feed asks its source for ${s.feedName}. This source is Chainlink's total-return feed, which already includes the multiplier.`}
            </p>
            <Calc>
              price = {obs.price.toString()} ({obs.decimals} decimals) = <b>${fixed(obs.price, obs.decimals, 4, 2)}</b>
              <br />
              observedAt = {obs.observedAt.toString()} = {utc(Number(obs.observedAt))}
            </Calc>
          </Step>

          <Step n={2} title="The multiplier in force at that moment">
            <p className="text-sm text-muted">
              ERC-8056 tokens never change balances on a split: a multiplier says how many shares one token is, and a change is
              scheduled for a set time. The token reports both.
            </p>
            <Calc>
              {s.tokenSymbol}.uiMultiplier() = {s.uiMultiplier !== undefined ? fixed(s.uiMultiplier, 18, 6) : "—"}
              <br />
              {s.tokenSymbol}.effectiveAt() = {s.effectiveAt ? `${s.effectiveAt} = ${utc(s.effectiveAt)}` : "0 (never scheduled)"}
              <br />
              {s.tokenSymbol}.newUIMultiplier() = {s.newUIMultiplier !== undefined ? fixed(s.newUIMultiplier, 18, 6) : "—"}
            </Calc>
            <p className="text-sm">
              {multiplierReason(s)} So the multiplier is <b className="font-mono">{fixed(s.multiplier, 18, 6)}</b>.
            </p>
          </Step>

          <Step n={3} title="Share price × multiplier">
            {raw ? (
              s.multiplierApplied ? (
                <>
                  <p className="text-sm text-muted">In integers, exactly as the contract computes it (Math.mulDiv, rounding down):</p>
                  <Calc>
                    {obs.price.toString()} × {s.multiplier.toString()} ÷ 10^18
                    <br />= <b>{computed.toString()}</b> = ${fixed(computed, 8, 8, 2)}
                  </Calc>
                </>
              ) : (
                <p className="text-sm">This feed is set not to apply the multiplier, so the answer is the share price.</p>
              )
            ) : (
              <>
                <p className="text-sm text-muted">The answer is the source&apos;s price as it stands; the share price is derived from it:</p>
                <Calc>
                  answer = {obs.price.toString()}
                  <br />
                  share price = {obs.price.toString()} × 10^18 ÷ {s.multiplier.toString()} = ${fixed(s.sharePrice, 8, 4, 2)}
                </Calc>
              </>
            )}
            <p className="text-sm">
              The feed&apos;s own answer: <span className="font-mono">{s.answer.toString()}</span>{" "}
              {s.answer === computed ? <b className="text-ok">matches ✓</b> : <b className="text-warn">differs from the working above</b>}
            </p>
          </Step>

          <Step n={4} title="Will it serve that price?">
            <p className="text-sm text-muted">A price can be correct and still unsafe to use. SlateFeed checks, in this order, and the first answer decides:</p>
            <ul className="flex flex-col gap-1.5">
              {statusChecks(s).map((c) => (
                <li key={c.label} className={`rounded-lg border px-3 py-2 text-sm ${c.decides ? "border-accent" : "border-border text-muted"}`}>
                  <span className="font-semibold">{c.label}</span> {c.detail}
                </li>
              ))}
            </ul>
            <p className="text-sm">
              Status: <b>{s.status}</b>.{" "}
              {s.round.ok
                ? `latestRoundData() serves $${fixed(s.round.value[1], 8, 4, 2)}${s.status === "Market closed" ? ", because this feed is set to serve the last price fresh at the close" : ""}.`
                : `latestRoundData() reverts (${s.round.reason}): a protocol reading it gets no price and pauses.`}
            </p>
          </Step>
          <p className="text-[13px] text-muted">
            Read at block {s.block.toLocaleString("en-US")}. Feed <span className="font-mono">{s.address}</span>, token{" "}
            <span className="font-mono">{s.token}</span>. The same reads are in the{" "}
            <Link href="/playground" className="text-accent-text hover:underline">
              playground
            </Link>{" "}
            and the{" "}
            {/* A JSON route handler, not a page: a full navigation, so <a>, not <Link>. */}
            <a href={`/price/${s.tokenSymbol ?? ""}${s.chainId === 46630 ? "?network=testnet" : ""}`} className="text-accent-text hover:underline">
              price API
            </a>
            .
          </p>
        </ol>
      )}
    </>
  );
}
