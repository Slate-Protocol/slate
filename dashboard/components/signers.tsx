"use client";

import { useQuery } from "@tanstack/react-query";
import { parseAbi, toFunctionSelector, type Address, type Hex } from "viem";
import { useReadContracts } from "wagmi";
import type { DashboardData } from "@/lib/data";
import { ExplorerLink, POLL, TESTNET, reads, useNow } from "./live";
import { card } from "./sections";

type Testnet = DashboardData["testnet"];

const sourceAbi = parseAbi([
  "function signers() view returns (address[])",
  "function quorum() view returns (uint8)",
  "function owner() view returns (address)",
  "function maxSpreadBps() view returns (uint16)",
  "function unanimousJumpBps() view returns (uint16)",
  "function maxFutureSkew() view returns (uint32)",
]);
const timelockAbi = parseAbi([
  "function getMinDelay() view returns (uint256)",
  "function PROPOSER_ROLE() view returns (bytes32)",
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function getTimestamp(bytes32 id) view returns (uint256)",
  "function isOperationDone(bytes32 id) view returns (bool)",
]);
const ownableAbi = parseAbi(["function owner() view returns (address)", "function pendingOwner() view returns (address)"]);

const DEPLOYER: Address = "0xBBfFdd1Baf34AeAb21F2fFdDfbd2b64489BD4999";
const ACCEPT_OWNERSHIP = toFunctionSelector("acceptOwnership()");
const SET_SIGNERS = toFunctionSelector("setSigners(address[],uint8)");

type Scheduled = { id: Hex; target: Address; data: Hex; tx: Hex };

/** The timelock's scheduled operations, from the explorer's decoded `CallScheduled` events. */
async function scheduled(explorer: string, timelock: Address): Promise<Scheduled[]> {
  const res = await fetch(`${explorer}/api/v2/addresses/${timelock}/logs`);
  if (!res.ok) return [];
  const body = (await res.json()) as {
    items: { transaction_hash: Hex; decoded?: { method_call: string; parameters: { name: string; value: string }[] } }[];
  };
  return body.items
    .filter((x) => x.decoded?.method_call.startsWith("CallScheduled"))
    .map((x) => {
      const p = Object.fromEntries(x.decoded!.parameters.map((q) => [q.name, q.value]));
      return { id: p.id as Hex, target: p.target as Address, data: p.data as Hex, tx: x.transaction_hash };
    });
}

const when = (t: number) =>
  new Date(t * 1000).toLocaleString("en-GB", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZoneName: "short" });

function countdown(seconds: number) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return h > 0 ? `${h} h ${m} min` : `${m} min ${seconds % 60} s`;
}

export function SignersPanel({ testnet, docsUrl }: { testnet: Testnet; docsUrl: string }) {
  const c = testnet.contracts;
  const source = c.SignedSource as Address | undefined;
  const timelock = c.TimelockController as Address | undefined;
  const calendar = c.USMarketCalendar as Address | undefined;
  const now = useNow();
  const { data } = useReadContracts({
    contracts: reads([
      { address: source!, abi: sourceAbi, functionName: "signers", chainId: TESTNET },
      { address: source!, abi: sourceAbi, functionName: "quorum", chainId: TESTNET },
      { address: source!, abi: sourceAbi, functionName: "owner", chainId: TESTNET },
      { address: source!, abi: sourceAbi, functionName: "maxSpreadBps", chainId: TESTNET },
      { address: source!, abi: sourceAbi, functionName: "unanimousJumpBps", chainId: TESTNET },
      { address: source!, abi: sourceAbi, functionName: "maxFutureSkew", chainId: TESTNET },
      { address: timelock!, abi: timelockAbi, functionName: "getMinDelay", chainId: TESTNET },
      { address: calendar!, abi: ownableAbi, functionName: "owner", chainId: TESTNET },
      { address: calendar!, abi: ownableAbi, functionName: "pendingOwner", chainId: TESTNET },
    ]),
    query: { ...POLL, enabled: !!source && !!timelock && !!calendar },
  });
  const ops = useQuery({
    queryKey: ["timelock-ops", timelock],
    queryFn: () => scheduled(testnet.explorer, timelock!),
    enabled: !!timelock,
    refetchInterval: 60_000,
  }).data;
  const { data: opState } = useReadContracts({
    contracts: reads(
      (ops ?? []).flatMap((o) => [
        { address: timelock!, abi: timelockAbi, functionName: "getTimestamp", args: [o.id], chainId: TESTNET },
        { address: timelock!, abi: timelockAbi, functionName: "isOperationDone", args: [o.id], chainId: TESTNET },
      ]),
    ),
    query: { ...POLL, enabled: !!ops?.length },
  });
  if (!source || !timelock || !calendar) return null;

  const signers = data?.[0]?.result as readonly Address[] | undefined;
  const quorum = data?.[1]?.result as number | undefined;
  const owner = data?.[2]?.result as Address | undefined;
  const spread = data?.[3]?.result as number | undefined;
  const jump = data?.[4]?.result as number | undefined;
  const skew = data?.[5]?.result as number | undefined;
  const delay = data?.[6]?.result as bigint | undefined;
  const calendarOwner = data?.[7]?.result as Address | undefined;
  const calendarPending = data?.[8]?.result as Address | undefined;
  const same = (a?: string, b?: string) => !!a && !!b && a.toLowerCase() === b.toLowerCase();
  const label = (a?: Address) => (same(a, timelock) ? "the timelock" : same(a, DEPLOYER) ? "Slate (deployer)" : a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "—");

  const describe = (o: Scheduled) => {
    if (same(o.target, calendar) && o.data.startsWith(ACCEPT_OWNERSHIP)) return "The market calendar moves under the timelock: the timelock accepts ownership";
    if (same(o.target, source) && o.data.startsWith(SET_SIGNERS)) return "A new signer set for SignedSource";
    return `A call to ${label(o.target)}`;
  };

  return (
    <section id="signers" aria-labelledby="signers-title" className={`${card} flex scroll-mt-20 flex-col gap-4 p-5`}>
      <div className="flex max-w-[780px] flex-col gap-1">
        <h2 id="signers-title" className="flex flex-wrap items-center gap-2 text-lg font-semibold">
          Who signs the prices
          <span className="rounded-md bg-surface-2 px-2 py-0.5 text-xs font-semibold">On-chain · RH testnet</span>
        </h2>
        <p className="text-muted">
          Every Slate price needs {quorum ?? "a quorum of"}{" "}signatures from the set below, read from SignedSource now. All of
          these keys are Slate&apos;s today. Only the timelock can change the set, and only after a{" "}
          {delay !== undefined ? `${Number(delay) / 3600}-hour` : "48-hour"} delay that anyone can watch.{" "}
          <a href={`${docsUrl}/decentralisation`} className="text-accent-text underline-offset-2 hover:underline">
            The path to independent signers
          </a>
        </p>
      </div>

      <div className="grid grid-cols-[repeat(auto-fit,minmax(280px,1fr))] gap-4">
        <div className="flex flex-col gap-2">
          <span className="text-xs tracking-[0.04em] text-muted uppercase">Signer set · {quorum ?? "—"} of {signers?.length ?? "—"} required</span>
          <ul className="flex flex-col gap-1.5">
            {(signers ?? []).map((s, i) => (
              <li key={s} className="flex items-center justify-between gap-3 rounded-lg bg-surface-2 px-3 py-2 text-sm">
                <ExplorerLink explorer={testnet.explorer} address={s} label={`${s.slice(0, 10)}…${s.slice(-6)}`} />
                <span className="text-muted">Slate · key {i + 1}</span>
              </li>
            ))}
          </ul>
          <span className="text-[13px] text-muted">
            Fixed for good in the contract: signers within {spread !== undefined ? `${spread / 100}%` : "—"} of each other, every
            signer for a move over {jump !== undefined ? `${jump / 100}%` : "—"}, nothing more than {skew ?? "—"} s in the future.
          </span>
        </div>
        <div className="flex flex-col gap-2 text-sm">
          <span className="text-xs tracking-[0.04em] text-muted uppercase">Control</span>
          <div className="flex justify-between gap-3 border-b border-border py-1.5">
            <span className="text-muted">SignedSource owner</span>
            <span>{owner ? <ExplorerLink explorer={testnet.explorer} address={owner} label={label(owner)} /> : "—"}</span>
          </div>
          <div className="flex justify-between gap-3 border-b border-border py-1.5">
            <span className="text-muted">Timelock delay</span>
            <span className="font-mono">{delay !== undefined ? `${Number(delay) / 3600} h` : "—"}</span>
          </div>
          <div className="flex justify-between gap-3 border-b border-border py-1.5">
            <span className="text-muted">Can propose to the timelock</span>
            <span>Slate (deployer)</span>
          </div>
          <div className="flex justify-between gap-3 border-b border-border py-1.5">
            <span className="text-muted">Market calendar owner</span>
            <span>
              {label(calendarOwner)}
              {calendarPending && !same(calendarPending, "0x0000000000000000000000000000000000000000") ? ` → ${label(calendarPending)}` : ""}
            </span>
          </div>
          <span className="text-[13px] text-muted">Feeds, the basket and the router have no owner at all.</span>
        </div>
      </div>

      <div className="flex flex-col gap-2">
        <span className="text-xs tracking-[0.04em] text-muted uppercase">Timelock operations</span>
        {ops && ops.length === 0 && <span className="text-sm text-muted">None scheduled.</span>}
        {(ops ?? []).map((o, i) => {
          const at = opState?.[2 * i]?.result as bigint | undefined;
          const done = opState?.[2 * i + 1]?.result as boolean | undefined;
          const ready = at !== undefined && Number(at) <= now;
          return (
            <div key={o.id} className="flex flex-col gap-1 rounded-lg border border-border px-3 py-2.5 text-sm">
              <span className="font-medium">{describe(o)}</span>
              <span className="text-[13px] text-muted">
                {done
                  ? "Executed."
                  : at === undefined
                    ? "—"
                    : ready
                      ? `Ready since ${when(Number(at))}; anyone with the executor role can run it.`
                      : `Executable ${when(Number(at))}, in ${countdown(Number(at) - now)}. Scheduled in `}
                {!done && !ready && at !== undefined && (
                  <a href={`${testnet.explorer}/tx/${o.tx}`} target="_blank" rel="noreferrer" className="font-mono text-accent-text underline-offset-2 hover:underline">
                    {o.tx.slice(0, 10)}…
                  </a>
                )}
              </span>
            </div>
          );
        })}
      </div>
    </section>
  );
}
