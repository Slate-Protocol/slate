import type { Address, Hex } from "viem";
import { feedId, readEntry, type Entry } from "./report.ts";
import type { Quote } from "./robinhood.ts";

/** Independent signers' endpoints (see cosigner.ts), from `COSIGNER_URLS`. Empty means Slate's keys only. */
export const COSIGNER_URLS = (process.env.COSIGNER_URLS ?? "")
  .split(",")
  .map((x) => x.trim())
  .filter(Boolean);

/** An entry is kept only if it is signed as claimed and close enough to our own quote to pass SignedSource's spread rule. */
export const MAX_DEVIATION_BPS = 40n;
export const MAX_TIME_GAP = 60;

/**
 * Asks each co-signer for its own signed observation of `symbol`. Entries that fail verification, stray more than
 * MAX_DEVIATION_BPS from our quote, or are more than MAX_TIME_GAP seconds from it are dropped and reported.
 */
export async function cosign(
  urls: string[],
  symbol: string,
  chainId: number,
  source: Address,
  ours: Quote,
  fetcher: typeof fetch = fetch,
): Promise<{ entries: Entry[]; dropped: string[] }> {
  const id = feedId(symbol);
  const entries: Entry[] = [];
  const dropped: string[] = [];
  await Promise.all(
    urls.map(async (base) => {
      try {
        const res = await fetcher(`${base.replace(/\/$/, "")}/sign?symbol=${symbol}&chainId=${chainId}&source=${source}`, {
          signal: AbortSignal.timeout(4_000),
        });
        const body = (await res.json()) as { signer?: Address; entry?: Hex; error?: string };
        if (!res.ok || !body.entry || !body.signer) throw new Error(body.error ?? `HTTP ${res.status}`);
        const e = await readEntry(body.entry, chainId, source, id);
        if (e.signer.toLowerCase() !== body.signer.toLowerCase()) throw new Error(`signed by ${e.signer}, claimed ${body.signer}`);
        const gap = e.price > ours.mid ? e.price - ours.mid : ours.mid - e.price;
        if (gap * 10_000n > ours.mid * MAX_DEVIATION_BPS) throw new Error(`price ${e.price} vs ours ${ours.mid}`);
        if (Math.abs(Number(e.observedAt) - ours.observedAt) > MAX_TIME_GAP) throw new Error(`observed ${e.observedAt} vs ours ${ours.observedAt}`);
        entries.push({ signer: e.signer, entry: body.entry });
      } catch (err) {
        dropped.push(`${base}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }),
  );
  return { entries, dropped };
}
