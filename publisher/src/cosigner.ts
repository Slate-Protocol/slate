import { createServer } from "node:http";
import { getAddress, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { feedId, signEntry } from "./report.ts";
import { fetchQuote, quoteProblems, type Quote } from "./robinhood.ts";

/**
 * The independent signer. An operator who is not Slate runs this with their own key: on request it fetches its own
 * Robinhood quote, applies the same checks the publisher does, and signs its own observation for one of the
 * SignedSource contracts it has chosen to sign for. It never signs a price it was handed.
 *
 *   COSIGNER_KEY=0x… COSIGNER_ALLOW="4663:0xf0b5…7526,46630:0x8B27…A507" PORT=8090 node src/cosigner.ts
 *
 * GET /sign?symbol=CRWD&chainId=4663&source=0x…  →  { signer, price, observedAt, entry }
 */

export type CosignDeps = { key: Hex; allow: Set<string>; quote: (symbol: string) => Promise<Quote>; now: () => number };

export async function handle(url: URL, deps: CosignDeps): Promise<{ status: number; body: unknown }> {
  const signer = privateKeyToAccount(deps.key).address;
  if (url.pathname === "/") return { status: 200, body: { signer, signsFor: [...deps.allow] } };
  if (url.pathname !== "/sign") return { status: 404, body: { error: "not found" } };
  const symbol = (url.searchParams.get("symbol") ?? "").toUpperCase();
  const chainId = Number(url.searchParams.get("chainId"));
  let source: Address;
  try {
    source = getAddress(url.searchParams.get("source") ?? "");
  } catch {
    return { status: 400, body: { error: "bad source" } };
  }
  if (!/^[A-Z.]{1,10}$/.test(symbol)) return { status: 400, body: { error: "bad symbol" } };
  if (!deps.allow.has(`${chainId}:${source.toLowerCase()}`)) return { status: 403, body: { error: "not a SignedSource this operator signs for" } };
  const q = await deps.quote(symbol);
  const problems = quoteProblems(q, deps.now());
  if (problems.length) return { status: 409, body: { error: "refused", problems } };
  const { entry } = await signEntry(deps.key, chainId, source, { feedId: feedId(symbol), price: q.mid, observedAt: BigInt(q.observedAt) });
  return { status: 200, body: { signer, price: q.mid.toString(), observedAt: q.observedAt, entry } };
}

/** `"4663:0xF0b5…,46630:0x8B27…"` → the set of `chainId:lowercased-address` pairs. */
export function parseAllow(spec: string): Set<string> {
  return new Set(
    spec
      .split(",")
      .map((x) => x.trim())
      .filter(Boolean)
      .map((x) => {
        const [chain, address] = x.split(":");
        return `${Number(chain)}:${getAddress(address).toLowerCase()}`;
      }),
  );
}

if (import.meta.main) {
  const key = process.env.COSIGNER_KEY as Hex;
  if (!/^0x[0-9a-fA-F]{64}$/.test(key ?? "")) throw new Error("COSIGNER_KEY missing or malformed");
  const deps: CosignDeps = { key, allow: parseAllow(process.env.COSIGNER_ALLOW ?? ""), quote: fetchQuote, now: () => Math.floor(Date.now() / 1000) };
  const port = Number(process.env.PORT ?? 8090);
  createServer(async (req, res) => {
    try {
      const { status, body } = await handle(new URL(req.url ?? "/", "http://x"), deps);
      res.writeHead(status, { "content-type": "application/json" });
      res.end(JSON.stringify(body));
    } catch (e) {
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }));
    }
  }).listen(port, () => console.log(JSON.stringify({ msg: "cosigner", signer: privateKeyToAccount(key).address, port, signsFor: [...deps.allow] })));
}
