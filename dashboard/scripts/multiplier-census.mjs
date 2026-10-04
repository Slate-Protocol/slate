// The multiplier census, rebuilt from public sources: every stock token in Robinhood's registry on Robinhood Chain
// mainnet, its ERC-8056 multiplier read from the chain, and whether Chainlink publishes a feed for it.
// Run: node scripts/multiplier-census.mjs   (prints a summary, then CSV of the tokens whose multiplier is not 1)
import { createPublicClient, http, parseAbi } from "viem";

const c = createPublicClient({
  transport: http("https://rpc.mainnet.chain.robinhood.com", { retryCount: 3 }),
  chain: { id: 4663, name: "Robinhood Chain", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [""] } }, contracts: { multicall3: { address: "0xcA11bde05977b3631167028862bE2a173976CA11" } } },
});
const abi = parseAbi(["function uiMultiplier() view returns (uint256)", "function newUIMultiplier() view returns (uint256)", "function effectiveAt() view returns (uint256)"]);
const reg = await (await fetch("https://api.robinhood.com/rhj/assets")).json();
const dir = await (await fetch("https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json")).json();
const covered = new Set(dir.map((f) => /^Robinhood\s+([A-Za-z.]+)\s*[-/]\s*USD/.exec(f.name)?.[1]?.toUpperCase()).filter(Boolean));
const tokens = reg.assets.map((a) => ({ symbol: a.tokenSymbol.toUpperCase(), token: a.deployments?.find((d) => d.chainId === 4663)?.contractAddress })).filter((x) => x.token);
const block = await c.getBlockNumber();
const r = await c.multicall({ allowFailure: true, blockNumber: block, contracts: tokens.flatMap((t) => ["uiMultiplier", "newUIMultiplier", "effectiveAt"].map((functionName) => ({ address: t.token, abi, functionName }))) });
const ONE = 10n ** 18n;
const rows = tokens.map((t, i) => ({ ...t, m: r[3 * i].result, n: r[3 * i + 1].result, e: r[3 * i + 2].result, chainlink: covered.has(t.symbol) }));
const nonOne = rows.filter((x) => x.m !== undefined && x.m !== ONE).sort((a, b) => Number(b.m - a.m));
const now = Math.floor(Date.now() / 1000);
console.log(`block ${block}: ${rows.length} tokens, ${rows.filter((x) => x.m === undefined).length} unreadable`);
console.log(`multiplier != 1: ${nonOne.length}; of those without a Chainlink feed: ${nonOne.filter((x) => !x.chainlink).length}`);
console.log(`changes scheduled after now: ${rows.filter((x) => x.e && Number(x.e) > now).length}`);
console.log("symbol,token,multiplier,next,effective_at_utc,chainlink,multiplier_blind_price_low_pct");
for (const x of nonOne) {
  const m = Number(x.m) / 1e18;
  console.log([x.symbol, x.token, m.toFixed(6), (Number(x.n) / 1e18).toFixed(6), x.e > 0n ? new Date(Number(x.e) * 1000).toISOString() : "", x.chainlink ? "yes" : "no", ((1 - 1 / m) * 100).toFixed(4)].join(","));
}
