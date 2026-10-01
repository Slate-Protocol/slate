import { concat, encodePacked, parseSignature, stringToHex, type Address, type Hex } from "viem";
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

/**
 * Signs one observation with every key and packs the report `SignedSource.submit` expects: one 97-byte entry per
 * signer, `int192 price ‖ uint64 observedAt ‖ r ‖ s ‖ v`, in ascending signer-address order.
 */
export async function buildReport(keys: Hex[], chainId: number, source: Address, obs: Observation): Promise<Hex> {
  const signed = await Promise.all(
    keys.map(async (key) => {
      const account = privateKeyToAccount(key);
      const signature = await account.signTypedData({
        domain: domain(chainId, source),
        types,
        primaryType: "Observation",
        message: obs,
      });
      const { r, s, v } = parseSignature(signature);
      const entry = encodePacked(
        ["int192", "uint64", "bytes32", "bytes32", "uint8"],
        [obs.price, obs.observedAt, r, s, Number(v)],
      );
      return { address: account.address.toLowerCase(), entry };
    }),
  );
  signed.sort((a, b) => (a.address < b.address ? -1 : 1));
  return concat(signed.map((x) => x.entry));
}
