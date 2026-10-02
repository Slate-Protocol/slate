"use client";

import { useEffect, useState } from "react";
import {
  BaseError,
  ContractFunctionRevertedError,
  encodeAbiParameters,
  formatUnits,
  maxUint256,
  parseUnits,
  zeroAddress,
  type Abi,
  type Address,
  type ContractFunctionParameters,
  type Hash,
} from "viem";
import { useConfig, useConnection, useReadContracts } from "wagmi";
import { simulateContract, switchChain, waitForTransactionReceipt, writeContract } from "wagmi/actions";
import {
  basketAbi,
  erc20Abi,
  labStockAbi,
  aggregatorAbi,
  navFeedAbi,
  routerAbi,
  slateFeedAbi,
  testDollarAbi,
} from "@/lib/abi";
import type { DashboardData } from "@/lib/data";
import { useCashLiquidity, type Liquidity } from "@/lib/liquidity";
import { FEED_STATUS, type FeedStatusLabel } from "@/lib/status";
import { LabTag, Pill, card } from "./sections";

const TESTNET = 46630;
const POLL = { refetchInterval: 10_000 } as const;
const V4_ROUTE = encodeAbiParameters(
  [{ type: "uint24" }, { type: "int24" }, { type: "address" }],
  [3000, 60, zeroAddress],
);

type Testnet = DashboardData["testnet"];

type Read = { address: Address; abi: Abi; functionName: string; args?: readonly unknown[]; chainId: number };
/** Mixed read lists defeat wagmi's tuple inference; results are cast where they are used. */
const reads = (xs: Read[]) => xs as unknown as readonly ContractFunctionParameters[];

/** Unix seconds, ticking once a second. */
function useNow() {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(id);
  }, []);
  return now;
}

const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
const usd = (v: number) => `$${v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const num = (v: bigint, decimals: number, digits = 4) =>
  Number(formatUnits(v, decimals)).toLocaleString("en-US", { maximumFractionDigits: digits });
const statusOf = (s: number | undefined): FeedStatusLabel => (s === undefined ? "No data" : (FEED_STATUS[s] ?? "No data"));

function ExplorerLink({ explorer, address, label }: { explorer: string; address: string; label?: string }) {
  return (
    <a href={`${explorer}/address/${address}`} target="_blank" rel="noreferrer" className="font-mono text-accent-text underline-offset-2 hover:underline">
      {label ?? short(address)}
    </a>
  );
}

/** Readable reason for a failed call, naming Slate's own errors. */
function explain(e: unknown): string {
  if (e instanceof BaseError) {
    const revert = e.walk((x) => x instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError && revert.data) {
      const { errorName, args = [] } = revert.data;
      if (errorName === "RouteRefused") {
        const [i, effective, feed] = args as bigint[];
        return `Route refused on leg ${Number(i) + 1}: the pool's price ${usd(Number(formatUnits(effective, 8)))} is outside 3% of the Slate price ${usd(Number(formatUnits(feed, 8)))}.`;
      }
      if (errorName === "FeedUnavailable") return `A constituent's feed is ${statusOf(Number(args[0]))}; Slate will not price through it.`;
      if (errorName === "Cooldown") return `Cooling down until ${new Date(Number(args[0]) * 1000).toLocaleTimeString()}.`;
      return `${errorName}(${args.map(String).join(", ")})`;
    }
    return e.shortMessage;
  }
  return e instanceof Error ? e.message : String(e);
}

type WriteRequest = { address: Address; abi: Abi; functionName: string; args?: readonly unknown[] };

/** Runs one transaction on RH testnet, switching the wallet's chain first if needed. */
function useTx(onDone?: () => void) {
  const config = useConfig();
  const { chainId, address } = useConnection();
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<{ kind: "ok" | "error"; text: string; hash?: Hash } | null>(null);

  async function run(label: string, request: WriteRequest) {
    setBusy(label);
    setMessage(null);
    try {
      if (chainId !== TESTNET) await switchChain(config, { chainId: TESTNET });
      // Simulate first: a refused route or an unusable feed is explained here, by name, before the wallet opens.
      await simulateContract(config, { ...request, account: address, chainId: TESTNET } as Parameters<typeof simulateContract>[1]);
      const hash = await writeContract(config, { ...request, chainId: TESTNET } as Parameters<typeof writeContract>[1]);
      const receipt = await waitForTransactionReceipt(config, { hash, chainId: TESTNET });
      if (receipt.status !== "success") throw new Error("Transaction reverted.");
      setMessage({ kind: "ok", text: `${label}: confirmed.`, hash });
      onDone?.();
    } catch (e) {
      setMessage({ kind: "error", text: explain(e) });
    } finally {
      setBusy(null);
    }
  }
  return { run, busy, message };
}

function TxMessage({ message, explorer }: { message: ReturnType<typeof useTx>["message"]; explorer: string }) {
  if (!message) return null;
  return (
    <p role="status" className={`rounded-lg px-3 py-2.5 text-sm ${message.kind === "ok" ? "bg-ok-bg text-ok" : "bg-stop-bg text-stop"}`}>
      {message.text}{" "}
      {message.hash && (
        <a href={`${explorer}/tx/${message.hash}`} target="_blank" rel="noreferrer" className="font-mono underline">
          {short(message.hash)}
        </a>
      )}
    </p>
  );
}

const button =
  "min-h-[46px] rounded-[10px] bg-accent px-4 font-semibold text-on-accent hover:brightness-105 disabled:opacity-60";
const secondary = "min-h-[42px] rounded-[10px] border border-border px-4 text-sm font-semibold hover:border-faint disabled:opacity-60";

// ------------------------------------------------------------------------------------------------
// Mainnet USDG proof
// ------------------------------------------------------------------------------------------------

export function UsdgProof() {
  return (
    <section aria-labelledby="usdg-title" className={`${card} flex flex-col gap-3 p-5`}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="usdg-title" className="font-semibold">AAPL with real USDG, through a real pool</h2>
        <span className="rounded-md bg-ok-bg px-2 py-0.5 text-xs font-semibold text-ok">Accepted · inside the 3% band</span>
      </div>
      <div className="grid grid-cols-[repeat(auto-fit,minmax(140px,1fr))] gap-3">
        <div className="flex flex-col gap-0.5">
          <span className="text-xs text-muted">Paid for 0.1 AAPL</span>
          <span className="font-mono text-2xl font-semibold">32.79 USDG</span>
        </div>
        <div className="flex flex-col gap-0.5">
          <span className="text-xs text-muted">Fair value (Chainlink AAPL × USDG/USD)</span>
          <span className="font-mono text-2xl font-medium">32.71 USDG</span>
        </div>
        <div className="flex flex-col gap-0.5">
          <span className="text-xs text-muted">Difference</span>
          <span className="font-mono text-2xl font-medium">+0.25%</span>
        </div>
      </div>
      <p className="text-[13px] text-muted">
        SlateRouter on a fork of Robinhood Chain mainnet, buying through the live AAPL/USDG Uniswap pool{" "}
        <span className="font-mono">0xAae0…2d6D</span> with Paxos USDG. Run it yourself:{" "}
        <span className="font-mono">forge test --match-test test_aaplUsdgPool_createsWithinTheBand</span>.
      </p>
    </section>
  );
}

// ------------------------------------------------------------------------------------------------
// Basket
// ------------------------------------------------------------------------------------------------

export function BasketPanel({ testnet }: { testnet: Testnet; usdgUsd: number | null }) {
  const c = testnet.contracts;
  const { data } = useReadContracts({
    contracts: reads([
      { address: c.SlateNavFeed, abi: navFeedAbi, functionName: "latestQuote", chainId: TESTNET },
      { address: c.SlateBasket, abi: basketAbi, functionName: "holdings", chainId: TESTNET },
      { address: c.SlateBasket, abi: basketAbi, functionName: "totalSupply", chainId: TESTNET },
      ...testnet.constituents.map((x) => ({ address: x.feed, abi: navFeedAbi, functionName: "latestQuote", chainId: TESTNET })),
    ]),
    query: { ...POLL, enabled: !!c.SlateBasket },
  });
  const nav = data?.[0]?.result as { status: number; answer: bigint } | undefined;
  const holdings = data?.[1]?.result as bigint[] | undefined;
  const supply = data?.[2]?.result as bigint | undefined;
  const prices = testnet.constituents.map((_, i) => (data?.[3 + i]?.result as { answer: bigint } | undefined)?.answer);
  const values = holdings && prices.every((p) => p !== undefined) ? holdings.map((h, i) => Number(formatUnits(h * prices[i]!, 26))) : null;
  const total = values?.reduce((a, b) => a + b, 0) ?? 0;

  return (
    <section id="basket" aria-labelledby="basket-title" className={`${card} flex scroll-mt-20 flex-col gap-4 p-5`}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="basket-title" className="text-lg font-semibold">SLATE-5 basket</h2>
        <span className="rounded-md bg-surface-2 px-2 py-0.5 text-xs font-semibold">AggregatorV3Interface</span>
      </div>
      <div className="flex flex-wrap items-end gap-6">
        <div className="flex flex-col gap-0.5">
          <span className="text-xs text-muted">NAV per share · RH testnet</span>
          <span className="font-mono text-2xl font-semibold">{nav && nav.answer > 0n ? usd(Number(formatUnits(nav.answer, 8))) : "—"}</span>
        </div>
        <div className="flex flex-col gap-1 pb-1">
          <Pill status={nav ? statusOf(nav.status) : "No data"} />
        </div>
        <div className="flex flex-col gap-0.5">
          <span className="text-xs text-muted">Shares outstanding</span>
          <span className="font-mono text-[15px]">{supply !== undefined ? num(supply, 18, 2) : "—"}</span>
        </div>
        <div className="flex flex-col gap-0.5">
          <span className="text-xs text-muted">NAV feed</span>
          <span className="text-[15px]">{c.SlateNavFeed ? <ExplorerLink explorer={testnet.explorer} address={c.SlateNavFeed} /> : "—"}</span>
        </div>
      </div>
      <div className="flex flex-col gap-1.5">
        {testnet.constituents.map((x, i) => {
          const w = values && total > 0 ? values[i] / total : null;
          return (
            <div key={x.symbol} className="flex items-center gap-2.5 text-sm">
              <span className="w-[54px] font-semibold">{x.symbol}</span>
              <div className="h-2 flex-1 overflow-hidden rounded bg-surface-2">
                <div className="h-2 bg-muted" style={{ width: `${((w ?? 0) * 100).toFixed(1)}%` }} />
              </div>
              <span className="w-[52px] text-right font-mono text-muted">{w === null ? "—" : `${(w * 100).toFixed(1)}%`}</span>
            </div>
          );
        })}
      </div>
      <p className="text-[13px] text-muted">
        Equal value at creation ($10 of each per share), fixed composition. Weights drift with prices. Rebalancing is v2: it
        needs a price to act on, and in-kind create and redeem never use one.
      </p>
    </section>
  );
}

// ------------------------------------------------------------------------------------------------
// Create & redeem
// ------------------------------------------------------------------------------------------------

export function CreatePanel({ testnet }: { testnet: Testnet }) {
  const c = testnet.contracts;
  const { address, isConnected } = useConnection();
  const [mode, setMode] = useState<"cash" | "kind" | "redeem">("cash");
  const [input, setInput] = useState("1");
  let shares = 0n;
  try {
    shares = input.trim() ? parseUnits(input.trim(), 18) : 0n;
  } catch {}
  const valid = shares > 0n;
  const user = address ?? zeroAddress;

  const { data, refetch } = useReadContracts({
    contracts: reads([
      { address: c.SlateRouter, abi: routerAbi, functionName: "fairCash", args: [valid ? shares : 10n ** 18n], chainId: TESTNET },
      { address: c.SlateTestDollar, abi: erc20Abi, functionName: "balanceOf", args: [user], chainId: TESTNET },
      { address: c.SlateTestDollar, abi: erc20Abi, functionName: "allowance", args: [user, c.SlateRouter], chainId: TESTNET },
      { address: c.SlateBasket, abi: basketAbi, functionName: "balanceOf", args: [user], chainId: TESTNET },
      { address: c.SlateBasket, abi: basketAbi, functionName: "quoteCreate", args: [valid ? shares : 10n ** 18n], chainId: TESTNET },
      { address: c.SlateBasket, abi: basketAbi, functionName: "quoteRedeem", args: [valid ? shares : 10n ** 18n], chainId: TESTNET },
      ...testnet.constituents.map((x) => ({ address: x.token, abi: erc20Abi, functionName: "balanceOf", args: [user], chainId: TESTNET })),
      ...testnet.constituents.map((x) => ({
        address: x.token,
        abi: erc20Abi,
        functionName: "allowance",
        args: [user, c.SlateBasket],
        chainId: TESTNET,
      })),
    ]),
    query: { ...POLL, enabled: !!c.SlateRouter },
  });
  const tx = useTx(() => refetch());
  const now = useNow();
  const n = testnet.constituents.length;
  const liquidity = useCashLiquidity({
    router: c.SlateRouter,
    cash: c.SlateTestDollar,
    venue: c.UniswapV4Venue,
    route: V4_ROUTE,
    legs: n,
    symbols: testnet.constituents.map((x) => x.symbol),
    shares: valid ? shares : 0n,
    chainId: TESTNET,
  }).data;
  const fair = (data?.[0]?.result as readonly [bigint, readonly bigint[]] | undefined)?.[0];
  const cashBalance = data?.[1]?.result as bigint | undefined;
  const cashAllowance = data?.[2]?.result as bigint | undefined;
  const slateBalance = data?.[3]?.result as bigint | undefined;
  const createAmounts = data?.[4]?.result as readonly bigint[] | undefined;
  const redeemAmounts = data?.[5]?.result as readonly bigint[] | undefined;
  const stockBalances = testnet.constituents.map((_, i) => data?.[6 + i]?.result as bigint | undefined);
  const stockAllowances = testnet.constituents.map((_, i) => data?.[6 + n + i]?.result as bigint | undefined);
  const maxCash = fair !== undefined ? (fair * 1025n) / 1000n : undefined; // fees, price impact and drift: 2.5%

  let action: { label: string; onClick: () => void; disabled?: boolean } | null = null;
  if (!isConnected) action = null;
  else if (!valid) action = { label: "Enter a number of shares", onClick: () => {}, disabled: true };
  else if (mode === "cash") {
    if (maxCash === undefined || cashBalance === undefined || cashAllowance === undefined) {
      action = { label: "Reading…", onClick: () => {}, disabled: true };
    } else if (cashBalance < maxCash) {
      action = {
        label: "Get 10,000 TESTUSD from the faucet",
        onClick: () => tx.run("Faucet", { address: c.SlateTestDollar, abi: testDollarAbi, functionName: "faucet" }),
      };
    } else if (cashAllowance < maxCash) {
      action = {
        label: "Approve TESTUSD",
        onClick: () => tx.run("Approve TESTUSD", { address: c.SlateTestDollar, abi: erc20Abi, functionName: "approve", args: [c.SlateRouter, maxUint256] }),
      };
    } else if (liquidity && liquidity.kind !== "ok") {
      action = {
        label: liquidity.kind === "refused" && liquidity.oneShareOk ? "Too large for testnet liquidity" : "Cash create unavailable on testnet",
        onClick: () => {},
        disabled: true,
      };
    } else {
      action = {
        label: `Create ${input} SLATE-5 with TESTUSD`,
        onClick: () =>
          tx.run("Create with cash", {
            address: c.SlateRouter,
            abi: routerAbi,
            functionName: "createWithCash",
            args: [
              shares,
              user,
              testnet.constituents.map(() => ({ venue: c.UniswapV4Venue, route: V4_ROUTE })),
              maxCash,
              BigInt(now + 600),
            ],
          }),
      };
    }
  } else if (mode === "kind") {
    const missing = createAmounts ? testnet.constituents.findIndex((_, i) => (stockAllowances[i] ?? 0n) < createAmounts[i]) : -1;
    const short = createAmounts ? testnet.constituents.findIndex((_, i) => (stockBalances[i] ?? 0n) < createAmounts[i]) : -1;
    if (!createAmounts) action = { label: "Reading…", onClick: () => {}, disabled: true };
    else if (short >= 0) action = { label: `Not enough ${testnet.constituents[short].symbol}`, onClick: () => {}, disabled: true };
    else if (missing >= 0) {
      const x = testnet.constituents[missing];
      action = {
        label: `Approve ${x.symbol}`,
        onClick: () => tx.run(`Approve ${x.symbol}`, { address: x.token, abi: erc20Abi, functionName: "approve", args: [c.SlateBasket, maxUint256] }),
      };
    } else {
      action = {
        label: `Create ${input} SLATE-5 in kind`,
        onClick: () =>
          tx.run("Create in kind", { address: c.SlateBasket, abi: basketAbi, functionName: "create", args: [shares, user, createAmounts] }),
      };
    }
  } else {
    if (slateBalance === undefined || !redeemAmounts) action = { label: "Reading…", onClick: () => {}, disabled: true };
    else if (slateBalance < shares) action = { label: "Not enough SLATE-5", onClick: () => {}, disabled: true };
    else {
      action = {
        label: `Redeem ${input} SLATE-5 in kind`,
        onClick: () =>
          tx.run("Redeem", { address: c.SlateBasket, abi: basketAbi, functionName: "redeem", args: [shares, user, redeemAmounts] }),
      };
    }
  }

  const tab = (m: typeof mode, label: string) => (
    <button
      key={m}
      type="button"
      role="tab"
      aria-selected={mode === m}
      onClick={() => setMode(m)}
      className={`px-3 py-2 text-sm ${mode === m ? "bg-surface-2 font-semibold" : "text-muted hover:text-text"}`}
    >
      {label}
    </button>
  );

  return (
    <section id="create" aria-labelledby="create-title" className={`${card} flex scroll-mt-20 flex-col gap-4 p-5`}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="create-title" className="text-lg font-semibold">Create &amp; redeem</h2>
        <div role="tablist" aria-label="Mode" className="inline-flex overflow-hidden rounded-lg border border-border">
          {tab("cash", "With cash")}
          {tab("kind", "In kind")}
          {tab("redeem", "Redeem")}
        </div>
      </div>
      <label className="flex flex-col gap-1.5 text-sm">
        <span>SLATE-5 shares</span>
        <input
          type="text"
          inputMode="decimal"
          value={input}
          onChange={(e) => setInput(e.target.value.replace(/[^0-9.]/g, ""))}
          className="rounded-lg border border-border bg-bg p-3 font-mono text-lg"
        />
      </label>

      {mode === "cash" && (
        <div className="flex flex-col gap-1 text-sm">
          <div className="flex justify-between gap-3">
            <span className="text-muted">At Slate prices</span>
            <span className="font-mono whitespace-nowrap">{fair !== undefined ? `${num(fair, 6, 2)} TESTUSD` : "—"}</span>
          </div>
          <div className="flex justify-between gap-3">
            <span className="text-muted">Most you pay (+2.5% for fees and impact)</span>
            <span className="font-mono whitespace-nowrap">{maxCash !== undefined ? `${num(maxCash, 6, 2)} TESTUSD` : "—"}</span>
          </div>
          <span className="text-[13px] text-muted">
            TESTUSD (Slate Test Dollar): testnet stand-in for Paxos USDG. Not USDG. The router is built for USDG on mainnet, proven on a fork.
          </span>
          {valid && <LiquidityNote liquidity={liquidity} shares={input} />}
        </div>
      )}
      {(mode === "kind" || mode === "redeem") && (
        <div className="flex flex-col gap-1 text-sm">
          {testnet.constituents.map((x, i) => {
            const amount = (mode === "kind" ? createAmounts : redeemAmounts)?.[i];
            return (
              <div key={x.symbol} className="flex justify-between gap-3">
                <span className="text-muted">
                  {x.symbol} {mode === "kind" ? "in" : "out"}
                </span>
                <span className="font-mono whitespace-nowrap">
                  {amount !== undefined ? num(amount, 18, 6) : "—"}
                  {mode === "kind" && stockBalances[i] !== undefined && isConnected ? ` / ${num(stockBalances[i]!, 18, 4)} held` : ""}
                </span>
              </div>
            );
          })}
          {mode === "kind" && (
            <span className="text-[13px] text-muted">
              In kind uses no pools, so it works whatever the testnet liquidity. Robinhood&apos;s testnet faucet hands out the five
              stock tokens.
            </span>
          )}
        </div>
      )}

      <div className="flex gap-2 rounded-lg bg-warn-bg px-3 py-2.5 text-sm">
        <svg viewBox="0 0 24 24" className="mt-0.5 size-4 shrink-0 text-warn" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <circle cx="12" cy="12" r="9" />
          <path d="M5.6 5.6l12.8 12.8" />
        </svg>
        <span>
          The router refuses any leg priced more than 3% from its Slate feed. A third-party TSLA pool on this testnet prices TSLA
          at $0.0675 against $354.11; the router will not touch it.
        </span>
      </div>

      {isConnected ? (
        <button type="button" disabled={!!tx.busy || action?.disabled} onClick={action?.onClick} className={button}>
          {tx.busy ? `${tx.busy}…` : action?.label}
        </button>
      ) : (
        <p className="rounded-[10px] border border-border px-4 py-3 text-sm text-muted">Connect a wallet on Robinhood Chain testnet to create.</p>
      )}
      {isConnected && slateBalance !== undefined && (
        <p className="text-[13px] text-muted">
          You hold <span className="font-mono">{num(slateBalance, 18, 4)}</span> SLATE-5
          {cashBalance !== undefined && (
            <>
              {" "}
              and <span className="font-mono">{num(cashBalance, 6, 2)}</span> TESTUSD
            </>
          )}
          .
        </p>
      )}
      <TxMessage message={tx.message} explorer={testnet.explorer} />
    </section>
  );
}

/** What the testnet pools can serve right now, from a simulated create; never blames the protocol for thin seed liquidity. */
function LiquidityNote({ liquidity, shares }: { liquidity: Liquidity | undefined; shares: string }) {
  if (!liquidity) return <span className="text-[13px] text-muted">Checking testnet pool liquidity…</span>;
  if (liquidity.kind === "ok") {
    return (
      <span className="text-[13px] text-muted">
        Testnet pools can fill {shares} {shares === "1" ? "share" : "shares"} right now, every leg within 3% of its Slate price
        (simulated).
      </span>
    );
  }
  const inKind = "In-kind create and redeem use no pools and still work.";
  let title: string;
  let body: string;
  if (liquidity.kind === "refused") {
    title = liquidity.oneShareOk ? `Testnet liquidity can't fill ${shares} shares with cash` : "Testnet liquidity exhausted for cash creates";
    body = `Route refused on leg ${liquidity.leg} (${liquidity.symbol}): the seeded TESTUSD/${liquidity.symbol} pool would fill at ${usd(
      liquidity.effective,
    )} a share, more than 3% from Slate's ${usd(liquidity.feed)}. That is the safety band working; the cause is this testnet's thin seed liquidity, not a fault in Slate. ${
      liquidity.oneShareOk ? "Fewer shares still fill. " : ""
    }${inKind}`;
  } else if (liquidity.kind === "feed") {
    title = "Cash creates paused";
    body = `A constituent's feed is ${liquidity.status}, and the router won't price through it. ${inKind}`;
  } else {
    title = "Testnet liquidity can't fill this size";
    body = `The seeded testnet pools can't serve this creation right now (${liquidity.detail}). ${inKind}`;
  }
  return (
    <div role="status" className="mt-1 flex flex-col gap-1 rounded-lg border border-border bg-surface-2 px-3 py-2.5">
      <span className="font-semibold">{title}</span>
      <span className="text-[13px] text-muted">{body}</span>
    </div>
  );
}

// ------------------------------------------------------------------------------------------------
// Corporate Action Lab
// ------------------------------------------------------------------------------------------------

const COOLDOWN = 600;

export function LabPanel({ testnet }: { testnet: Testnet }) {
  const c = testnet.contracts;
  const { isConnected } = useConnection();
  const { data, refetch } = useReadContracts({
    contracts: reads([
      { address: c.SlateLabStock, abi: labStockAbi, functionName: "uiMultiplier", chainId: TESTNET },
      { address: c.SlateLabStock, abi: labStockAbi, functionName: "newUIMultiplier", chainId: TESTNET },
      { address: c.SlateLabStock, abi: labStockAbi, functionName: "effectiveAt", chainId: TESTNET },
      { address: c.SlateLabStock, abi: labStockAbi, functionName: "lastScheduledAt", chainId: TESTNET },
      { address: testnet.labFeed ?? zeroAddress, abi: slateFeedAbi, functionName: "latestDetail", chainId: TESTNET },
      { address: c.NaiveMultiplierFeed, abi: aggregatorAbi, functionName: "latestRoundData", chainId: TESTNET },
    ]),
    query: { refetchInterval: 5_000, enabled: !!c.SlateLabStock && !!testnet.labFeed },
  });
  const tx = useTx(() => refetch());
  const now = useNow();
  const multiplier = data?.[0]?.result as bigint | undefined;
  const next = data?.[1]?.result as bigint | undefined;
  const effectiveAt = data?.[2]?.result as bigint | undefined;
  const lastScheduled = data?.[3]?.result as bigint | undefined;
  const detail = data?.[4]?.result as readonly [{ status: number; answer: bigint; observedAt: bigint }, bigint, bigint] | undefined;
  const naive = data?.[5]?.result as readonly [bigint, bigint, bigint, bigint, bigint] | undefined;

  const pending = next !== undefined && multiplier !== undefined && effectiveAt !== undefined && next !== multiplier && Number(effectiveAt) > now;
  const cooldownEnds = lastScheduled ? Number(lastScheduled) + COOLDOWN : 0;
  const coolingDown = cooldownEnds > now;
  const m = multiplier !== undefined ? Number(formatUnits(multiplier, 18)) : null;
  const splitUp = m !== null && m * 4 <= 100;
  const target = multiplier !== undefined ? (splitUp ? multiplier * 4n : multiplier / 4n) : 0n;
  const slateStatus = detail ? statusOf(detail[0].status) : ("No data" as FeedStatusLabel);
  const slatePrice = detail && detail[0].answer > 0n ? Number(formatUnits(detail[0].answer, 8)) : null;
  const naivePrice = naive ? Number(formatUnits(naive[1], 8)) : null;
  const wrong = slatePrice !== null && naivePrice !== null && Math.abs(naivePrice / slatePrice - 1) > 0.05;

  return (
    <section id="lab" aria-labelledby="lab-title" className="flex scroll-mt-20 flex-col gap-4 rounded-[14px] border border-dashed border-lab-border p-5">
      <div className="flex max-w-[760px] flex-col gap-1">
        <h2 id="lab-title" className="flex flex-wrap items-center gap-2 text-lg font-semibold">
          Corporate Action Lab <LabTag>LAB · RH TESTNET</LabTag>
        </h2>
        <p className="text-muted">
          Schedule a split on labTSLA, a Slate test token over the live TSLA price, and watch a naive feed jump by the split
          ratio while SlateFeed refuses to price until a post-split print lands. Lab tokens are Slate&apos;s test tokens, not
          Robinhood&apos;s. Anyone can schedule one action every 10 minutes.
        </p>
      </div>
      <div className="grid grid-cols-[repeat(auto-fit,minmax(220px,1fr))] gap-3">
        <div className={`${card} flex flex-col gap-1 p-4`}>
          <span className="text-xs text-muted">labTSLA uiMultiplier()</span>
          <span className="font-mono text-2xl font-semibold">{m === null ? "—" : m.toFixed(m < 1 ? 4 : 3)}</span>
          <span className="text-[13px] text-muted">
            {pending
              ? `Switches to ${Number(formatUnits(next!, 18)).toFixed(3)} at ${new Date(Number(effectiveAt) * 1000).toLocaleTimeString()}`
              : "Nothing scheduled"}
          </span>
        </div>
        <div className={`${card} flex flex-col gap-1 p-4 ${wrong ? "border-stop" : ""}`}>
          <span className="text-xs text-muted">Naive feed · last share price × multiplier now</span>
          <span className={`font-mono text-2xl font-semibold ${wrong ? "text-stop" : ""}`}>{naivePrice === null ? "—" : usd(naivePrice)}</span>
          <span className="text-[13px] text-muted">{wrong ? `Off by ${(naivePrice! / slatePrice!).toFixed(2)}×` : "Agrees with Slate"}</span>
        </div>
        <div className={`${card} flex flex-col gap-1 p-4`}>
          <span className="text-xs text-muted">SlateFeed · multiplier in force when priced</span>
          <span className="font-mono text-2xl font-semibold">{(slateStatus === "OK" || slateStatus === "Market closed") && slatePrice !== null ? usd(slatePrice) : "refuses"}</span>
          <span>
            <Pill status={slateStatus} />
          </span>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-3">
        {isConnected ? (
          <button
            type="button"
            disabled={!!tx.busy || coolingDown || pending || multiplier === undefined}
            onClick={() =>
              tx.run(splitUp ? "Schedule a 4:1 split" : "Schedule a 1:4 reverse split", {
                address: c.SlateLabStock,
                abi: labStockAbi,
                functionName: "scheduleCorporateAction",
                args: [target, BigInt(Math.floor(Date.now() / 1000) + 90)],
              })
            }
            className={secondary}
          >
            {tx.busy ? `${tx.busy}…` : splitUp ? "Schedule a 4:1 split in 90 s" : "Schedule a 1:4 reverse split in 90 s"}
          </button>
        ) : (
          <span className="text-sm text-muted">Connect a wallet on Robinhood Chain testnet to schedule a split.</span>
        )}
        {coolingDown && <span className="text-[13px] text-muted">Next action allowed at {new Date(cooldownEnds * 1000).toLocaleTimeString()}.</span>}
        {c.SlateLabStock && (
          <span className="text-[13px] text-muted">
            Token <ExplorerLink explorer={testnet.explorer} address={c.SlateLabStock} /> · feed{" "}
            {testnet.labFeed && <ExplorerLink explorer={testnet.explorer} address={testnet.labFeed} />}
          </span>
        )}
      </div>
      <TxMessage message={tx.message} explorer={testnet.explorer} />
    </section>
  );
}
