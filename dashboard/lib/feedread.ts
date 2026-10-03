import { BaseError, ContractFunctionRevertedError, parseAbi, type Address } from "viem";
import { client, type ChainId } from "./chains";
import { aggregatorAbi, slateFeedAbi } from "./abi";
import { FEED_STATUS } from "./status";

/**
 * Reads one price feed from the chain, from the browser: any AggregatorV3Interface, and for a SlateFeed everything its
 * answer is made from (the signed observation, the token's ERC-8056 multiplier state, the market calendar). Calls go
 * one by one, so a call a contract does not have fails alone, and testnet (no Multicall3) works the same.
 */

const feedMeta = parseAbi([
  "function decimals() view returns (uint8)",
  "function description() view returns (string)",
  "function token() view returns (address)",
  "function feedId() view returns (bytes32)",
  "function source() view returns (address)",
  "function priceKind() view returns (uint8)",
  "function model() view returns (uint8)",
  "function multiplierApplied() view returns (bool)",
  "function maxAge() view returns (uint32)",
  "function corporateActionGrace() view returns (uint32)",
  "function allowMarketClosed() view returns (bool)",
  "function calendar() view returns (address)",
  "function session() view returns (uint8)",
]);
const tokenAbi = parseAbi([
  "function symbol() view returns (string)",
  "function uiMultiplier() view returns (uint256)",
  "function newUIMultiplier() view returns (uint256)",
  "function effectiveAt() view returns (uint256)",
  "function oraclePaused() view returns (bool)",
]);
const sourceAbi = [
  {
    type: "function",
    name: "observe",
    stateMutability: "view",
    inputs: [{ name: "feedId", type: "bytes32" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "price", type: "int256" },
          { name: "decimals", type: "uint8" },
          { name: "observedAt", type: "uint64" },
        ],
      },
    ],
  },
] as const;
const calendarAbi = parseAbi(["function closedSince(uint256 timestamp, uint8 session) view returns (uint256)", "function isOpen(uint256 timestamp, uint8 session) view returns (bool)"]);

export type Revert = { ok: false; reason: string };
type Result<T> = { ok: true; value: T } | Revert;

function reason(e: unknown): string {
  if (e instanceof BaseError) {
    const r = e.walk((x) => x instanceof ContractFunctionRevertedError);
    if (r instanceof ContractFunctionRevertedError) {
      const name = r.data?.errorName;
      if (name === "FeedUnavailable" && r.data?.args?.[0] !== undefined) return `FeedUnavailable(${FEED_STATUS[Number(r.data.args[0])] ?? r.data.args[0]})`;
      return name ?? r.reason ?? "reverted";
    }
    return e.shortMessage;
  }
  return String(e);
}

async function attempt<T>(p: Promise<T>): Promise<Result<T>> {
  try {
    return { ok: true, value: await p };
  } catch (e) {
    return { ok: false, reason: reason(e) };
  }
}
const val = <T,>(r: Result<T>): T | undefined => (r.ok ? r.value : undefined);

export type FeedRead = Awaited<ReturnType<typeof readFeed>>;

export async function readFeed(chainId: ChainId, address: Address) {
  const c = client(chainId);
  const read = <T,>(abi: unknown, functionName: string, args: unknown[] = [], at: Address = address) =>
    attempt(c.readContract({ address: at, abi: abi as never, functionName: functionName as never, args: args as never }) as Promise<T>);

  const code = await c.getCode({ address });
  const block = await c.getBlock();
  const now = Number(block.timestamp);
  if (!code || code === "0x") return { kind: "empty" as const, chainId, address, block: Number(block.number), now };

  const [decimals, description, round, detail, token, feedId, source, priceKind, model, multiplierApplied, maxAge, grace, allowClosed, calendar, session] =
    await Promise.all([
      read<number>(feedMeta, "decimals"),
      read<string>(feedMeta, "description"),
      read<readonly [bigint, bigint, bigint, bigint, bigint]>(aggregatorAbi, "latestRoundData"),
      read<readonly [{ status: number; answer: bigint; observedAt: bigint }, bigint, bigint]>(slateFeedAbi, "latestDetail"),
      read<Address>(feedMeta, "token"),
      read<`0x${string}`>(feedMeta, "feedId"),
      read<Address>(feedMeta, "source"),
      read<number>(feedMeta, "priceKind"),
      read<number>(feedMeta, "model"),
      read<boolean>(feedMeta, "multiplierApplied"),
      read<number>(feedMeta, "maxAge"),
      read<number>(feedMeta, "corporateActionGrace"),
      read<boolean>(feedMeta, "allowMarketClosed"),
      read<Address>(feedMeta, "calendar"),
      read<number>(feedMeta, "session"),
    ]);

  const base = { chainId, address, block: Number(block.number), now, decimals: val(decimals), description: val(description), round };
  if (!detail.ok || !token.ok) {
    // A feed answers latestRoundData(), or (when it refuses) at least has description() and decimals(); a plain ERC-20 has no description().
    if (round.ok || (decimals.ok && description.ok)) return { kind: "aggregator" as const, ...base };
    return { kind: "unknown" as const, ...base };
  }

  const t = token.value;
  const [symbol, uiMultiplier, newUIMultiplier, effectiveAt, oraclePaused, observation, closedSince, isOpen] = await Promise.all([
    read<string>(tokenAbi, "symbol", [], t),
    read<bigint>(tokenAbi, "uiMultiplier", [], t),
    read<bigint>(tokenAbi, "newUIMultiplier", [], t),
    read<bigint>(tokenAbi, "effectiveAt", [], t),
    read<boolean>(tokenAbi, "oraclePaused", [], t),
    source.ok && feedId.ok ? read<{ price: bigint; decimals: number; observedAt: bigint }>(sourceAbi, "observe", [feedId.value], source.value) : Promise.resolve({ ok: false, reason: "no source" } as Revert),
    calendar.ok && session.ok ? read<bigint>(calendarAbi, "closedSince", [BigInt(now), session.value], calendar.value) : Promise.resolve({ ok: false, reason: "no calendar" } as Revert),
    calendar.ok && session.ok ? read<boolean>(calendarAbi, "isOpen", [BigInt(now), session.value], calendar.value) : Promise.resolve({ ok: false, reason: "no calendar" } as Revert),
  ]);
  const [quote, sharePrice, multiplier] = detail.value;
  return {
    kind: "slate" as const,
    ...base,
    status: FEED_STATUS[quote.status] ?? `Unknown (${quote.status})`,
    answer: quote.answer,
    observedAt: Number(quote.observedAt),
    sharePrice,
    multiplier,
    token: t,
    tokenSymbol: val(symbol),
    feedId: val(feedId),
    feedName: feedId.ok ? hexToAscii(feedId.value) : undefined,
    source: val(source),
    priceKind: priceKind.ok ? (priceKind.value === 0 ? ("RAW_UNDERLYING" as const) : ("TOTAL_RETURN" as const)) : undefined,
    model: val(model),
    multiplierApplied: val(multiplierApplied),
    maxAge: val(maxAge),
    corporateActionGrace: val(grace),
    allowMarketClosed: val(allowClosed),
    calendar: val(calendar),
    session: session.ok ? (session.value === 0 ? "REGULAR" : "EXTENDED") : undefined,
    uiMultiplier: val(uiMultiplier),
    newUIMultiplier: val(newUIMultiplier),
    effectiveAt: effectiveAt.ok ? Number(effectiveAt.value) : undefined,
    oraclePaused: val(oraclePaused),
    observation: val(observation),
    closedSince: closedSince.ok ? Number(closedSince.value) : undefined,
    isOpen: val(isOpen),
  };
}

export function hexToAscii(h: `0x${string}`) {
  const bytes = h.slice(2).match(/../g) ?? [];
  return bytes
    .map((b) => parseInt(b, 16))
    .filter((b) => b !== 0)
    .map((b) => String.fromCharCode(b))
    .join("");
}

/** A fixed-point integer as a decimal string, exactly (no float rounding), with at least `min` decimal places. */
export function fixed(v: bigint, decimals: number, places = decimals, min = 0) {
  const neg = v < 0n;
  const a = neg ? -v : v;
  const s = a.toString().padStart(decimals + 1, "0");
  const int = s.slice(0, s.length - decimals);
  const frac = s.slice(s.length - decimals).slice(0, places).replace(/0+$/, "").padEnd(min, "0");
  return `${neg ? "-" : ""}${Number(int).toLocaleString("en-US")}${frac ? `.${frac}` : ""}`;
}
