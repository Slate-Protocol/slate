import { hexToBigInt, recoverTypedDataAddress, size, slice, stringToHex, type Address, type Hex } from "viem";

/**
 * The accuracy board: Slate's signed prices for the stock tokens Chainlink also prices on Robinhood Chain mainnet.
 * The publisher only supplies signed reports. Everything else (the signatures, the multiplier, Chainlink's answer)
 * is checked or read here, in the browser.
 */

export const PUBLISHER_URL = process.env.NEXT_PUBLIC_PUBLISHER_URL ?? "https://publisher-production-891d.up.railway.app";

export type Attestation = { symbol: string; feedId: Hex; price: string; observedAt: number; report: Hex };

export type BoardRow = {
  symbol: string;
  token: Address;
  chainlink: Address;
  chainlinkDecimals: number;
  chainlinkThresholdPct: number;
  chainlinkHeartbeat: number;
  latest?: Attestation;
  atChainlink?: Attestation;
  chainlinkUpdatedAt?: number;
  refused?: string[];
};

export type Board = { updatedAt: number; chainId: number; signedSource: Address; rows: Record<string, BoardRow> };

/** A Chainlink update and a signed observation count as the same moment within this many seconds. */
export const MATCH_WINDOW = 90;

export async function fetchBoard(url: string): Promise<Board | null> {
  try {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) return null;
    const b = (await res.json()) as Board;
    return b && b.rows ? b : null;
  } catch {
    return null;
  }
}

/** Per row, the newer of two boards' attestations: the live publisher, and a snapshot taken at the last close. */
export function mergeBoards(live: Board | null, snapshot: Board | null): Board | null {
  if (!live) return snapshot;
  if (!snapshot) return live;
  const rows: Record<string, BoardRow> = { ...snapshot.rows };
  for (const [symbol, row] of Object.entries(live.rows)) {
    const old = rows[symbol];
    const newer = (a?: Attestation, b?: Attestation) => ((a?.observedAt ?? 0) >= (b?.observedAt ?? 0) ? a : b);
    rows[symbol] = old ? { ...row, latest: newer(row.latest, old.latest), atChainlink: newer(row.atChainlink, old.atChainlink) } : row;
  }
  return { ...live, rows };
}

const types = {
  Observation: [
    { name: "feedId", type: "bytes32" },
    { name: "price", type: "int192" },
    { name: "observedAt", type: "uint64" },
  ],
} as const;

export type Verdict = { ok: boolean; signers: Address[]; reason?: string };

/**
 * Checks a report the way `SignedSource.submit` would: every 97-byte entry carries the claimed price and time, each
 * recovers a distinct signer in the on-chain set for `SignedSource`'s EIP-712 domain, and there are at least `quorum`.
 */
export async function verify(
  a: Attestation,
  set: readonly Address[],
  quorum: number,
  chainId: number,
  verifyingContract: Address,
): Promise<Verdict> {
  const fail = (reason: string): Verdict => ({ ok: false, signers: [], reason });
  if (a.feedId.toLowerCase() !== stringToHex(`${a.symbol}/USD`, { size: 32 }).toLowerCase()) return fail("feed id does not match the symbol");
  if (size(a.report) % 97 !== 0 || size(a.report) === 0) return fail("malformed report");
  const allowed = new Set(set.map((s) => s.toLowerCase()));
  const message = { feedId: a.feedId, price: BigInt(a.price), observedAt: BigInt(a.observedAt) };
  const signers: Address[] = [];
  for (let i = 0; i < size(a.report) / 97; i++) {
    const e = slice(a.report, i * 97, (i + 1) * 97);
    if (hexToBigInt(slice(e, 0, 24)) !== message.price || hexToBigInt(slice(e, 24, 32)) !== message.observedAt) {
      return fail("an entry signs a different price or time");
    }
    const signer = await recoverTypedDataAddress({
      domain: { name: "Slate SignedSource", version: "1", chainId, verifyingContract },
      types,
      primaryType: "Observation",
      message,
      signature: `${slice(e, 32, 96)}${slice(e, 96, 97).slice(2)}` as Hex,
    });
    if (!allowed.has(signer.toLowerCase())) return fail(`signed by ${signer}, not in the signer set`);
    if (signers.some((s) => s.toLowerCase() === signer.toLowerCase())) return fail("a signer appears twice");
    signers.push(signer);
  }
  return signers.length >= quorum ? { ok: true, signers } : fail(`${signers.length} of ${quorum} signatures`);
}

/** Median of a non-empty list. */
export function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
