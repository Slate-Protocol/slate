import { concat, encodePacked, hexToBigInt, parseSignature, recoverTypedDataAddress, size, slice, stringToHex, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";

/** `SignedSource`'s EIP-712 domain. */
export function domain(chainId: number, verifyingContract: Address) {
  return { name: "Slate SignedSource", version: "1", chainId, verifyingContract } as const;
}

export const types = {
  Observation: [
    { name: "feedId", type: "bytes32" },
    { name: "price", type: "int192" },
    { name: "observedAt", type: "uint64" },
  ],
} as const;

/** `"CRWD"` → the bytes32 feed id `"CRWD/USD"`, left-aligned and zero-padded, as Solidity's `bytes32("CRWD/USD")`. */
export function feedId(symbol: string): Hex {
  return stringToHex(`${symbol}/USD`, { size: 32 });
}

export type Observation = { feedId: Hex; price: bigint; observedAt: bigint };

/** One signer's 97-byte report entry: `int192 price ‖ uint64 observedAt ‖ r ‖ s ‖ v`. */
export type Entry = { signer: Address; entry: Hex };

/** Signs one observation with one key. Each signer may sign its own observation; SignedSource takes the median. */
export async function signEntry(key: Hex, chainId: number, source: Address, obs: Observation): Promise<Entry> {
  const account = privateKeyToAccount(key);
  const signature = await account.signTypedData({ domain: domain(chainId, source), types, primaryType: "Observation", message: obs });
  const { r, s, v } = parseSignature(signature);
  const entry = encodePacked(["int192", "uint64", "bytes32", "bytes32", "uint8"], [obs.price, obs.observedAt, r, s, Number(v)]);
  return { signer: account.address, entry };
}

/** Recovers an entry's signer and reads its price and time, for `feedId` under `SignedSource`'s domain. */
export async function readEntry(entry: Hex, chainId: number, source: Address, id: Hex) {
  if (size(entry) !== 97) throw new Error("an entry is 97 bytes");
  const price = hexToBigInt(slice(entry, 0, 24));
  const observedAt = hexToBigInt(slice(entry, 24, 32));
  const signer = await recoverTypedDataAddress({
    domain: domain(chainId, source),
    types,
    primaryType: "Observation",
    message: { feedId: id, price, observedAt },
    signature: `${slice(entry, 32, 96)}${slice(entry, 96, 97).slice(2)}` as Hex,
  });
  return { signer, price, observedAt };
}

/** The report `SignedSource.submit` expects: one entry per distinct signer, in ascending signer-address order. */
export function pack(entries: Entry[]): Hex {
  const bySigner = new Map(entries.map((e) => [e.signer.toLowerCase(), e]));
  return concat([...bySigner.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([, e]) => e.entry));
}

/** Signs one observation with every local key, adds any co-signers' entries, and packs the report. */
export async function buildReport(keys: Hex[], chainId: number, source: Address, obs: Observation, extra: Entry[] = []): Promise<Hex> {
  const local = await Promise.all(keys.map((key) => signEntry(key, chainId, source, obs)));
  return pack([...local, ...extra]);
}
