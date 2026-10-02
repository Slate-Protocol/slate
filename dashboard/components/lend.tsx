"use client";

import { useState } from "react";
import { formatUnits, maxUint256, parseUnits, zeroAddress, type Address } from "viem";
import { useConnection, useReadContracts } from "wagmi";
import { erc20Abi, labStockAbi, lenderAbi, testDollarAbi } from "@/lib/abi";
import type { DashboardData } from "@/lib/data";
import { ExplorerLink, POLL, TESTNET, TxMessage, button, num, reads, usd, useTx } from "./live";
import { LabTag, card } from "./sections";

type Testnet = DashboardData["testnet"];
type Mainnet = DashboardData["mainnet"];

const CRWD: Address = "0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931";

/** The mainnet lender, read-only: what one CRWD token would borrow today, priced by CRWD's SlateFeed. */
function MainnetLender({ lender }: { lender: Address }) {
  const { data } = useReadContracts({
    contracts: reads([{ address: lender, abi: lenderAbi, functionName: "quote", args: [CRWD, 10n ** 18n], chainId: 4663 }]),
    query: POLL,
  });
  const q = data?.[0]?.result as QuoteRead | undefined;
  return (
    <p className="rounded-lg border border-border px-3 py-2.5 text-sm">
      <span className="font-semibold">On Robinhood Chain mainnet.</span>{" "}
      <ExplorerLink explorer="https://robinhoodchain.blockscout.com" address={lender} /> lends Paxos USDG against CRWD, a token
      with no Chainlink feed.{" "}
      {q?.[0]
        ? `Through CRWD's SlateFeed it values one token at ${usd(Number(formatUnits(q[1], 6)))} and would lend up to ${num(q[2], 6, 2)} USDG against it (40%).`
        : q
          ? "CRWD's feed is not serving a price right now, so it would lend nothing."
          : ""}{" "}
      <span className="text-muted">No USDG is supplied yet: read-only.</span>
    </p>
  );
}
type Mode = "deposit" | "borrow" | "repay" | "withdraw";
type Position = readonly [boolean, bigint, bigint, bigint, bigint];
type PriceRead = readonly [boolean, bigint, bigint];
type QuoteRead = readonly [boolean, bigint, bigint];

const NAIVE = "StockLender (naive feed, LAB ONLY)";

function Lending({ ok }: { ok: boolean | undefined }) {
  if (ok === undefined) return <span className="text-xs text-muted">—</span>;
  return ok ? (
    <span className="rounded-md bg-ok-bg px-2 py-0.5 text-xs font-semibold whitespace-nowrap text-ok">Lending</span>
  ) : (
    <span className="rounded-md bg-warn-bg px-2 py-0.5 text-xs font-semibold whitespace-nowrap text-warn">Paused · no price</span>
  );
}

export function LendPanel({ testnet, mainnet }: { testnet: Testnet; mainnet: Mainnet }) {
  const c = testnet.contracts;
  const lender = c.StockLender as Address | undefined;
  const naiveLender = c[NAIVE] as Address | undefined;
  const markets = [
    ...testnet.constituents.map((x) => ({ symbol: x.symbol, token: x.token, lab: false })),
    ...(c.SlateLabStock ? [{ symbol: "labTSLA", token: c.SlateLabStock, lab: true }] : []),
  ];
  const { address, isConnected } = useConnection();
  const user = address ?? zeroAddress;
  const [selected, setSelected] = useState(0);
  const [mode, setMode] = useState<Mode>("deposit");
  const [input, setInput] = useState("");
  const n = markets.length;
  const L = lender ?? zeroAddress;

  const { data, refetch } = useReadContracts({
    contracts: reads([
      ...markets.map((m) => ({ address: L, abi: lenderAbi, functionName: "priceOf", args: [m.token], chainId: TESTNET })),
      ...markets.map((m) => ({ address: L, abi: lenderAbi, functionName: "positionOf", args: [m.token, user], chainId: TESTNET })),
      ...markets.map((m) => ({ address: m.token, abi: erc20Abi, functionName: "balanceOf", args: [user], chainId: TESTNET })),
      ...markets.map((m) => ({ address: m.token, abi: erc20Abi, functionName: "allowance", args: [user, L], chainId: TESTNET })),
      { address: L, abi: lenderAbi, functionName: "cash", chainId: TESTNET },
      { address: L, abi: lenderAbi, functionName: "totalDebt", chainId: TESTNET },
      { address: c.SlateTestDollar, abi: erc20Abi, functionName: "balanceOf", args: [user], chainId: TESTNET },
      { address: c.SlateTestDollar, abi: erc20Abi, functionName: "allowance", args: [user, L], chainId: TESTNET },
      { address: L, abi: lenderAbi, functionName: "quote", args: [c.SlateLabStock ?? zeroAddress, 10n ** 18n], chainId: TESTNET },
      { address: naiveLender ?? zeroAddress, abi: lenderAbi, functionName: "quote", args: [c.SlateLabStock ?? zeroAddress, 10n ** 18n], chainId: TESTNET },
    ]),
    query: { ...POLL, enabled: !!lender },
  });
  // The amount stays after an approval or faucet step, so the next click carries on with it.
  const tx = useTx(() => refetch());
  if (!lender) return null;

  const prices = markets.map((_, i) => data?.[i]?.result as PriceRead | undefined);
  const positions = markets.map((_, i) => data?.[n + i]?.result as Position | undefined);
  const balances = markets.map((_, i) => data?.[2 * n + i]?.result as bigint | undefined);
  const allowances = markets.map((_, i) => data?.[3 * n + i]?.result as bigint | undefined);
  const cash = data?.[4 * n]?.result as bigint | undefined;
  const totalDebt = data?.[4 * n + 1]?.result as bigint | undefined;
  const usdBalance = data?.[4 * n + 2]?.result as bigint | undefined;
  const usdAllowance = data?.[4 * n + 3]?.result as bigint | undefined;
  const slateQuote = data?.[4 * n + 4]?.result as QuoteRead | undefined;
  const naiveQuote = data?.[4 * n + 5]?.result as QuoteRead | undefined;

  const m = markets[selected];
  const pos = positions[selected];
  const priced = prices[selected]?.[0];
  const tokenAmount = mode === "deposit" || mode === "withdraw";
  let amount = 0n;
  try {
    amount = input.trim() ? parseUnits(input.trim(), tokenAmount ? 18 : 6) : 0n;
  } catch {}
  const headroom = pos && pos[3] > pos[2] ? pos[3] - pos[2] : 0n;
  const max = (() => {
    if (!pos) return undefined;
    if (mode === "deposit") return balances[selected];
    if (mode === "borrow") return cash !== undefined && cash < headroom ? cash : headroom;
    if (mode === "repay") return usdBalance !== undefined && usdBalance < pos[2] ? usdBalance : pos[2];
    return pos[2] === 0n ? pos[1] : undefined;
  })();

  let action: { label: string; onClick: () => void; disabled?: boolean } | null = null;
  const idle = (label: string) => ({ label, onClick: () => {}, disabled: true });
  if (!isConnected) action = null;
  else if (mode === "deposit") {
    const bal = balances[selected];
    if (bal === undefined || allowances[selected] === undefined) action = idle("Reading…");
    else if (bal === 0n && m.lab)
      action = { label: "Get 100 labTSLA from the faucet", onClick: () => tx.run("Faucet", { address: m.token, abi: labStockAbi, functionName: "faucet" }) };
    else if (amount === 0n) action = idle(`Enter an amount of ${m.symbol}`);
    else if (bal < amount) action = idle(`Not enough ${m.symbol}`);
    else if (allowances[selected]! < amount)
      action = {
        label: `Approve ${m.symbol}`,
        onClick: () => tx.run(`Approve ${m.symbol}`, { address: m.token, abi: erc20Abi, functionName: "approve", args: [lender, maxUint256] }),
      };
    else
      action = {
        label: `Deposit ${input} ${m.symbol}`,
        onClick: () => tx.run("Deposit", { address: lender, abi: lenderAbi, functionName: "deposit", args: [m.token, amount] }),
      };
  } else if (mode === "borrow") {
    if (priced === false) action = idle("Borrowing paused: no usable price");
    else if (amount === 0n) action = idle("Enter an amount of TESTUSD");
    else
      action = {
        label: `Borrow ${input} TESTUSD against ${m.symbol}`,
        onClick: () => tx.run("Borrow", { address: lender, abi: lenderAbi, functionName: "borrow", args: [m.token, amount] }),
      };
  } else if (mode === "repay") {
    if (usdBalance === undefined || usdAllowance === undefined) action = idle("Reading…");
    else if (amount === 0n) action = idle("Enter an amount of TESTUSD");
    else if (usdBalance < amount)
      action = { label: "Get 10,000 TESTUSD from the faucet", onClick: () => tx.run("Faucet", { address: c.SlateTestDollar, abi: testDollarAbi, functionName: "faucet" }) };
    else if (usdAllowance < amount)
      action = {
        label: "Approve TESTUSD",
        onClick: () => tx.run("Approve TESTUSD", { address: c.SlateTestDollar, abi: erc20Abi, functionName: "approve", args: [lender, maxUint256] }),
      };
    else
      action = {
        label: `Repay ${input} TESTUSD`,
        onClick: () => tx.run("Repay", { address: lender, abi: lenderAbi, functionName: "repay", args: [m.token, user, amount] }),
      };
  } else {
    if (amount === 0n) action = idle(`Enter an amount of ${m.symbol}`);
    else
      action = {
        label: `Withdraw ${input} ${m.symbol}`,
        onClick: () => tx.run("Withdraw", { address: lender, abi: lenderAbi, functionName: "withdraw", args: [m.token, amount] }),
      };
  }

  const tab = (x: Mode, label: string) => (
    <button
      key={x}
      type="button"
      role="tab"
      aria-selected={mode === x}
      onClick={() => {
        setMode(x);
        setInput("");
      }}
      className={`px-3 py-2 text-sm ${mode === x ? "bg-surface-2 font-semibold" : "text-muted hover:text-text"}`}
    >
      {label}
    </button>
  );
  const price = (i: number) => {
    const p = prices[i];
    return p && p[0] ? usd(Number(formatUnits(p[1], 8))) : "—";
  };
  const held = (v: bigint | undefined, d: number, digits: number) => (isConnected && v !== undefined ? num(v, d, digits) : "—");
  const cols = "grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1fr)] gap-x-4 px-4";

  const slateMax = slateQuote ? (slateQuote[0] ? Number(formatUnits(slateQuote[2], 6)) : null) : undefined;
  const naiveMax = naiveQuote ? (naiveQuote[0] ? Number(formatUnits(naiveQuote[2], 6)) : null) : undefined;
  const naiveValue = naiveQuote?.[0] ? Number(formatUnits(naiveQuote[1], 6)) : null;
  const slateValue = slateQuote?.[0] ? Number(formatUnits(slateQuote[1], 6)) : null;
  const diverged = slateMax === null || (naiveValue !== null && slateValue !== null && Math.abs(naiveValue / slateValue - 1) > 0.05);

  return (
    <section id="lend" aria-labelledby="lend-title" className={`${card} flex scroll-mt-20 flex-col gap-4 p-5`}>
      <div className="flex max-w-[780px] flex-col gap-1">
        <h2 id="lend-title" className="flex flex-wrap items-center gap-2 text-lg font-semibold">
          Lend against a stock token
          <span className="rounded-md bg-surface-2 px-2 py-0.5 text-xs font-semibold">Integration · RH testnet</span>
        </h2>
        <p className="text-muted">
          StockLender is a minimal lending market written the way any other protocol would write one. It prices collateral
          through Slate feeds with nothing but Chainlink&apos;s <span className="font-mono text-[13px]">latestRoundData()</span>,
          with no Slate code and no special access. When a feed refuses, the lender stops lending and liquidating; repaying
          always works. A proof, not a product: loans in TESTUSD, 50% loan-to-value, liquidation at 65%, no interest.
        </p>
      </div>

      <div className="overflow-hidden rounded-[12px] border border-border">
        <div role="table" aria-label="Lending markets" className="hidden text-sm md:block">
          <div role="row" className={`${cols} text-xs tracking-[0.04em] text-muted uppercase`}>
            {["Collateral", "Price", "Lender", "Deposited", "Borrowed", "Limit"].map((h, i) => (
              <div key={h} role="columnheader" className={`py-2.5 font-medium ${i === 1 || i >= 3 ? "text-right" : ""}`}>
                {h}
              </div>
            ))}
          </div>
          {markets.map((x, i) => (
            <div key={x.symbol} role="row" className={`${cols} items-center border-t border-border`}>
              <div role="cell" className="flex items-center gap-2 py-3 font-semibold">
                {x.symbol}
                {x.lab && <LabTag />}
              </div>
              <div role="cell" className="py-3 text-right font-mono">{price(i)}</div>
              <div role="cell" className="py-3"><Lending ok={prices[i]?.[0]} /></div>
              <div role="cell" className="py-3 text-right font-mono">{held(positions[i]?.[1], 18, 4)}</div>
              <div role="cell" className="py-3 text-right font-mono">{held(positions[i]?.[2], 6, 2)}</div>
              <div role="cell" className="py-3 text-right font-mono">{held(positions[i]?.[0] ? positions[i]?.[3] : undefined, 6, 2)}</div>
            </div>
          ))}
        </div>
        <ul className="flex flex-col md:hidden">
          {markets.map((x, i) => (
            <li key={x.symbol} className="flex flex-col gap-1.5 border-t border-border px-4 py-3 first:border-t-0">
              <div className="flex items-center justify-between gap-2">
                <span className="flex items-center gap-2 font-semibold">
                  {x.symbol}
                  {x.lab && <LabTag />}
                </span>
                <span className="font-mono font-semibold">{price(i)}</span>
              </div>
              <div className="flex items-center justify-between gap-2 text-[13px] text-muted">
                <span>
                  {isConnected ? `Deposited ${held(positions[i]?.[1], 18, 4)} · borrowed ${held(positions[i]?.[2], 6, 2)}` : "50% LTV · liquidation 65%"}
                </span>
                <Lending ok={prices[i]?.[0]} />
              </div>
            </li>
          ))}
        </ul>
      </div>

      {mainnet.contracts.StockLender && <MainnetLender lender={mainnet.contracts.StockLender as Address} />}

      <div className="grid grid-cols-[repeat(auto-fit,minmax(300px,1fr))] gap-4">
        <div className="flex flex-col gap-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <label className="flex items-center gap-2 text-sm">
              <span className="text-muted">Collateral</span>
              <select
                value={selected}
                onChange={(e) => {
                  setSelected(Number(e.target.value));
                  setInput("");
                }}
                className="min-h-[42px] rounded-lg border border-border bg-bg px-3 font-semibold"
              >
                {markets.map((x, i) => (
                  <option key={x.symbol} value={i}>
                    {x.symbol}
                  </option>
                ))}
              </select>
            </label>
            <div role="tablist" aria-label="Action" className="inline-flex overflow-hidden rounded-lg border border-border">
              {tab("deposit", "Deposit")}
              {tab("borrow", "Borrow")}
              {tab("repay", "Repay")}
              {tab("withdraw", "Withdraw")}
            </div>
          </div>
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="flex justify-between gap-3">
              <span>{tokenAmount ? m.symbol : "TESTUSD"}</span>
              {isConnected && max !== undefined && max > 0n && (
                <button type="button" onClick={() => setInput(formatUnits(max, tokenAmount ? 18 : 6))} className="text-accent-text underline-offset-2 hover:underline">
                  Max {num(max, tokenAmount ? 18 : 6, tokenAmount ? 4 : 2)}
                </button>
              )}
            </span>
            <input
              type="text"
              inputMode="decimal"
              value={input}
              placeholder="0"
              onChange={(e) => setInput(e.target.value.replace(/[^0-9.]/g, ""))}
              className="rounded-lg border border-border bg-bg p-3 font-mono text-lg"
            />
          </label>
          {isConnected ? (
            <button type="button" disabled={!!tx.busy || action?.disabled} onClick={action?.onClick} className={button}>
              {tx.busy ? `${tx.busy}…` : action?.label}
            </button>
          ) : (
            <p className="rounded-[10px] border border-border px-4 py-3 text-sm text-muted">Connect a wallet on Robinhood Chain testnet to borrow.</p>
          )}
          <TxMessage message={tx.message} explorer={testnet.explorer} />
          <p className="text-[13px] text-muted">
            Lender <ExplorerLink explorer={testnet.explorer} address={lender} /> ·{" "}
            {cash !== undefined ? `${num(cash, 6, 2)} TESTUSD available` : "—"}
            {totalDebt !== undefined ? ` · ${num(totalDebt, 6, 2)} lent` : ""}. TESTUSD is a testnet stand-in for Paxos USDG.
          </p>
        </div>

        {naiveLender && (
          <div className="flex flex-col gap-3 rounded-[12px] border border-dashed border-lab-border p-4">
            <span className="flex flex-wrap items-center gap-2 font-semibold">
              What a split does to a lender <LabTag>LAB</LabTag>
            </span>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-0.5">
                <span className="text-xs text-muted">On SlateFeed: 1 labTSLA can borrow</span>
                <span className="font-mono text-xl font-semibold">{slateMax === undefined ? "—" : slateMax === null ? "nothing" : `${slateMax.toFixed(2)}`}</span>
                <span className="text-[13px] text-muted">{slateMax === null ? "Paused until the price is sure" : "TESTUSD"}</span>
              </div>
              <div className="flex flex-col gap-0.5">
                <span className="text-xs text-muted">Same lender on the naive feed</span>
                <span className={`font-mono text-xl font-semibold ${diverged ? "text-stop" : ""}`}>
                  {naiveMax === undefined || naiveMax === null ? "—" : naiveMax.toFixed(2)}
                </span>
                <span className="text-[13px] text-muted">
                  {diverged && naiveValue !== null && slateValue !== null
                    ? `Lends against ${(naiveValue / slateValue).toFixed(2)}× the token's worth`
                    : diverged && naiveMax
                      ? "Still lending, on a price Slate won't vouch for"
                      : "TESTUSD"}
                </span>
              </div>
            </div>
            <p className="text-[13px] text-muted">
              Schedule a split in the Lab below. At the switch the naive-fed copy of this lender values labTSLA at four times its
              worth and will lend against it; the Slate-fed lender pauses until a post-split price lands. A reverse split does
              the opposite: the naive-fed lender liquidates healthy loans. The naive-fed copy is{" "}
              <ExplorerLink explorer={testnet.explorer} address={naiveLender} />, LAB ONLY.
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
