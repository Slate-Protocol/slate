"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getAddress, isAddress, type Address } from "viem";
import type { ChainId } from "@/lib/chains";
import { fixed, readFeed, type FeedRead } from "@/lib/feedread";
import { Pill, card } from "./sections";
import type { FeedStatusLabel } from "@/lib/status";

const NETWORKS: { id: ChainId; label: string; rpc: string }[] = [
  { id: 4663, label: "Robinhood Chain", rpc: "https://rpc.mainnet.chain.robinhood.com" },
  { id: 46630, label: "Robinhood Chain testnet", rpc: "https://rpc.testnet.chain.robinhood.com" },
];

const EXAMPLES: { label: string; chainId: ChainId; address: Address }[] = [
  { label: "CRWD · SlateFeed", chainId: 4663, address: "0x84Ad4c99b6AB003b97943E9c48aF73ba20B5Cc77" },
  { label: "AAPL · SlateFeed over Chainlink", chainId: 4663, address: "0x0c098235d4069Ad82c9EcaeF8264835C5A0dBc7D" },
  { label: "AAPL · Chainlink", chainId: 4663, address: "0x6B22A786bAa607d76728168703a39Ea9C99f2cD0" },
  { label: "TSLA · SlateFeed (testnet)", chainId: 46630, address: "0x5A9cD81b257a073802E9A039e7877A604964aa84" },
];

const ts = (t: number) => new Date(t * 1000).toUTCString().replace("GMT", "UTC");

function solidity(r: Extract<FeedRead, { kind: "slate" | "aggregator" }>) {
  const addr = getAddress(r.address);
  const label = r.kind === "slate" ? (r.feedName ?? r.description ?? "feed") : (r.description ?? "feed");
  if (r.kind === "slate")
    return `// ${label}, ${NETWORKS.find((n) => n.id === r.chainId)?.label}
import {AggregatorV3Interface, SlatePrice} from "@slate-protocol/contracts/SlatePrice.sol";

AggregatorV3Interface feed = AggregatorV3Interface(${addr});
(bool ok, uint256 price,,) = SlatePrice.tryRead(feed, 3 days);
if (!ok) revert("no price: pause, don't guess");
uint256 usd = SlatePrice.value(amount, 18, price, 8, 6); // amount tokens -> 6-decimal dollars`;
  return `// ${label}, ${NETWORKS.find((n) => n.id === r.chainId)?.label}: a plain AggregatorV3Interface feed
import {AggregatorV3Interface} from "@slate-protocol/contracts/interfaces/AggregatorV3Interface.sol";

AggregatorV3Interface feed = AggregatorV3Interface(${addr});
(, int256 answer,, uint256 updatedAt,) = feed.latestRoundData(); // ${r.decimals ?? 8} decimals
require(answer > 0 && block.timestamp - updatedAt <= 1 days, "stale");`;
}

function Copy({ text, label = "Copy" }: { text: string; label?: string }) {
  const [done, setDone] = useState(false);
  return (
    <button
      type="button"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(text);
          setDone(true);
          setTimeout(() => setDone(false), 1500);
        } catch {}
      }}
      className="rounded-md border border-border px-2.5 py-1 text-xs font-semibold hover:border-faint"
    >
      {done ? "Copied" : label}
    </button>
  );
}

function Row({ k, v, mono = true }: { k: string; v: React.ReactNode; mono?: boolean }) {
  return (
    <div className="grid grid-cols-[minmax(0,0.9fr)_minmax(0,1.6fr)] gap-3 border-t border-border px-4 py-2.5 text-sm first:border-t-0">
      <dt className="text-muted">{k}</dt>
      <dd className={mono ? "font-mono text-[13px] break-all" : "break-words"}>{v}</dd>
    </div>
  );
}

export function Playground() {
  const [chainId, setChainId] = useState<ChainId>(4663);
  const [input, setInput] = useState<string>(EXAMPLES[0].address);
  const [result, setResult] = useState<FeedRead | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const latest = useRef(0);

  const run = useCallback(async (id: ChainId, addr: string) => {
    const n = ++latest.current; // only the newest request may update the page
    if (!isAddress(addr.trim())) {
      setError("That is not an address. Paste a 0x… feed address.");
      setResult(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const r = await readFeed(id, getAddress(addr.trim()));
      if (n === latest.current) setResult(r);
    } catch (e) {
      if (n === latest.current) setError(`Could not reach ${NETWORKS.find((x) => x.id === id)?.label}: ${e instanceof Error ? e.message.split("\n")[0] : String(e)}`);
    } finally {
      if (n === latest.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    // The first example, read once on arrival (from a timer: an effect must not set state synchronously).
    const t = setTimeout(() => void run(EXAMPLES[0].chainId, EXAMPLES[0].address), 0);
    return () => clearTimeout(t);
  }, [run]);

  const r = result;
  const round = r && r.kind !== "empty" ? r.round : null;
  const cast =
    r && r.kind !== "empty" && r.kind !== "unknown"
      ? `cast call ${getAddress(r.address)} "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url ${NETWORKS.find((n) => n.id === r.chainId)?.rpc}`
      : null;

  return (
    <>
      <div className="flex max-w-[780px] flex-col gap-1">
        <h1 className="text-[26px] font-semibold tracking-[-0.015em]">Integration playground</h1>
        <p className="text-muted">
          Paste a feed address and see what it returns, read from the chain in your browser, then copy the Solidity that reads
          it. Any Chainlink-style feed works; a SlateFeed also shows why it will or won&apos;t serve a price.
        </p>
      </div>

      <section className={`${card} flex flex-col gap-3 p-5`} aria-label="Feed to read">
        <form
          className="flex flex-col gap-3 md:flex-row"
          onSubmit={(e) => {
            e.preventDefault();
            void run(chainId, input);
          }}
        >
          <label className="flex flex-col gap-1 md:w-[230px]">
            <span className="text-xs text-muted">Network</span>
            <select value={chainId} onChange={(e) => setChainId(Number(e.target.value) as ChainId)} className="min-h-[44px] rounded-lg border border-border bg-bg px-3">
              {NETWORKS.map((n) => (
                <option key={n.id} value={n.id}>
                  {n.label}
                </option>
              ))}
            </select>
          </label>
          <label className="flex min-w-0 flex-1 flex-col gap-1">
            <span className="text-xs text-muted">Feed address</span>
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              spellCheck={false}
              placeholder="0x…"
              className="min-h-[44px] rounded-lg border border-border bg-bg px-3 font-mono text-sm"
            />
          </label>
          <button type="submit" disabled={loading} className="min-h-[44px] self-end rounded-[10px] bg-accent px-5 text-sm font-semibold text-on-accent hover:brightness-105 disabled:opacity-60 md:w-auto">
            {loading ? "Reading…" : "Read feed"}
          </button>
        </form>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted">Try:</span>
          {EXAMPLES.map((x) => (
            <button
              key={x.label}
              type="button"
              onClick={() => {
                setChainId(x.chainId);
                setInput(x.address);
                void run(x.chainId, x.address);
              }}
              className="rounded-md border border-border px-2.5 py-1 text-[13px] hover:border-faint"
            >
              {x.label}
            </button>
          ))}
        </div>
        {error && <p className="text-sm text-warn">{error}</p>}
      </section>

      {loading && <p className="text-sm text-muted">Reading from the chain…</p>}
      {r && r.kind === "empty" && <p className={`${card} p-5 text-sm`}>No contract at that address on {NETWORKS.find((n) => n.id === r.chainId)?.label}. Check the network.</p>}
      {r && r.kind === "unknown" && <p className={`${card} p-5 text-sm`}>That contract is not a price feed: it has no <span className="font-mono">latestRoundData()</span> or <span className="font-mono">decimals()</span>.</p>}

      {r && (r.kind === "slate" || r.kind === "aggregator") && round && (
        <div className="grid grid-cols-[repeat(auto-fit,minmax(320px,1fr))] gap-4">
          <section className={`${card} flex flex-col overflow-hidden`} aria-label="What the feed returns">
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border px-4 py-3">
              <h2 className="font-semibold">What a lending market sees</h2>
              {r.kind === "slate" && <Pill status={r.status as FeedStatusLabel} />}
            </div>
            <div className="flex flex-col gap-1 px-4 py-4">
              <span className="text-xs text-muted">latestRoundData()</span>
              {round.ok ? (
                <span className="font-mono text-[28px] font-semibold">${fixed(round.value[1], r.decimals ?? 8, 4, 2)}</span>
              ) : (
                <span className="font-mono text-lg font-semibold text-warn">reverts: {round.reason}</span>
              )}
              <span className="text-[13px] text-muted">
                {round.ok
                  ? `answer ${round.value[1].toString()} at ${r.decimals ?? 8} decimals, updated ${ts(Number(round.value[3]))}`
                  : "A protocol reading this feed gets no price, so it pauses instead of guessing."}
              </span>
            </div>
            <dl className="border-t border-border">
              <Row k="description()" v={r.description ?? "—"} mono={false} />
              <Row k="decimals()" v={r.decimals ?? "—"} />
              {r.kind === "slate" && (
                <>
                  <Row k="status" v={r.status} mono={false} />
                  <Row k="token" v={`${r.tokenSymbol ?? ""} ${r.token}`} />
                  <Row k="share price × multiplier" v={`${fixed(r.sharePrice, 8)} × ${fixed(r.multiplier, 18)} = ${fixed(r.answer, 8)}`} />
                  <Row k="observed" v={r.observedAt ? ts(r.observedAt) : "—"} mono={false} />
                  <Row k="maxAge" v={r.maxAge !== undefined ? `${r.maxAge} s` : "—"} />
                  <Row k="serves when closed" v={r.allowMarketClosed === undefined ? "—" : r.allowMarketClosed ? "yes, the last price fresh at the close" : "no"} mono={false} />
                </>
              )}
              <Row k="read at" v={`block ${r.block.toLocaleString("en-US")}`} />
            </dl>
            {r.kind === "slate" && (
              <a href={`/arithmetic?network=${r.chainId === 4663 ? "mainnet" : "testnet"}&feed=${r.address}`} className="border-t border-border px-4 py-3 text-sm font-medium text-accent-text hover:underline">
                See the arithmetic, step by step →
              </a>
            )}
          </section>

          <section className={`${card} flex min-w-0 flex-col overflow-hidden`} aria-label="Solidity">
            <div className="flex items-center justify-between gap-2 border-b border-border px-4 py-3">
              <h2 className="font-semibold">Read it from Solidity</h2>
              <Copy text={solidity(r)} />
            </div>
            <pre className="overflow-x-auto bg-code px-4 py-3.5 font-mono text-[12.5px] leading-relaxed">{solidity(r)}</pre>
            <div className="flex flex-col gap-2 border-t border-border px-4 py-3 text-[13px] text-muted">
              <span>
                Install: <span className="font-mono text-text">npm install @slate-protocol/contracts</span>, remapping{" "}
                <span className="font-mono text-text break-all">@slate-protocol/contracts/=node_modules/@slate-protocol/contracts/src/</span>
              </span>
              {cast && (
                <div className="flex flex-col gap-1.5">
                  <div className="flex items-center justify-between gap-2">
                    <span>Or from a terminal:</span>
                    <Copy text={cast} />
                  </div>
                  <pre className="overflow-x-auto rounded-md bg-code px-3 py-2 font-mono text-[12px] text-text">{cast}</pre>
                </div>
              )}
            </div>
          </section>
        </div>
      )}
    </>
  );
}
