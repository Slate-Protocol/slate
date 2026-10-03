import { readPrice } from "@/lib/price";

export const dynamic = "force-dynamic";

const headers = { "content-type": "application/json; charset=utf-8", "access-control-allow-origin": "*", "cache-control": "public, max-age=10, s-maxage=10" };

/** GET /price/CRWD (mainnet) or /price/TSLA?network=testnet: a Slate feed, read from the chain at request time. */
export async function GET(req: Request, { params }: { params: Promise<{ symbol: string }> }) {
  const { symbol } = await params;
  const network = new URL(req.url).searchParams.get("network") === "testnet" ? "testnet" : "mainnet";
  try {
    const body = await readPrice(symbol, network);
    if (!body) return new Response(JSON.stringify({ error: `no Slate feed for ${symbol} on ${network}`, list: "/price" }, null, 2), { status: 404, headers });
    return new Response(JSON.stringify(body, null, 2), { headers });
  } catch (e) {
    return new Response(JSON.stringify({ error: "could not read the feed from the chain", detail: e instanceof Error ? e.message.split("\n")[0] : String(e) }, null, 2), { status: 502, headers: { ...headers, "cache-control": "no-store" } });
  }
}
