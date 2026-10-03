import { listFeeds } from "@/lib/price";

export const dynamic = "force-dynamic";

/** GET /price: every Slate feed on a network, with the URL for its live price. */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const network = url.searchParams.get("network") === "testnet" ? "testnet" : "mainnet";
  const feeds = await listFeeds(network);
  const q = network === "testnet" ? "?network=testnet" : "";
  const body = { network, feeds: feeds.map((f) => ({ ...f, price: `${url.origin}/price/${encodeURIComponent(f.symbol)}${q}` })), docs: "https://docs.slate.0xo.in/api" };
  return new Response(JSON.stringify(body, null, 2), { headers: { "content-type": "application/json; charset=utf-8", "access-control-allow-origin": "*", "cache-control": "public, max-age=60" } });
}
