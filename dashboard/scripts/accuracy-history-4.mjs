// Builds public/accuracy-history-4.json: Slate's signed share prices for TSLA, AMD, AMZN and PLTR (published on
// Robinhood Chain testnet from 1 Oct 2026) against Chainlink's answers for the same tokens on Robinhood Chain mainnet.
// Chain data only: testnet SignedSource PriceUpdated logs, and every Chainlink round in the window (getRoundData).
// Run: node scripts/accuracy-history-4.mjs
import fs from "node:fs";
import { createPublicClient, http, parseAbi, parseAbiItem, hexToString } from "viem";

const testnet = createPublicClient({ transport: http("https://rpc.testnet.chain.robinhood.com", { retryCount: 3 }) });
const mainnet = createPublicClient({ transport: http("https://rpc.mainnet.chain.robinhood.com", { retryCount: 3 }) });
const SIGNED_SOURCE_TESTNET = "0x8B27311a3493a85E063f97e4bB59cf3a22aEA507";
const TOKENS = {
  TSLA: { token: "0x322F0929c4625eD5bAd873c95208D54E1c003b2d", chainlink: "0x4A1166a659A55625345e9515b32adECea5547C38" },
  AMD: { token: "0x86923f96303D656E4aa86D9d42D1e57ad2023fdC", chainlink: "0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72" },
  AMZN: { token: "0x12f190a9F9d7D37a250758b26824B97CE941bF54", chainlink: "0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C" },
  PLTR: { token: "0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A", chainlink: "0x820ABedFF239034956B7A9d2F0a331f9F075eB4c" },
};
const MATCH_WINDOW = 90; // as the accuracy board: Slate's report signed within 90 s of Chainlink's update
const agg = parseAbi([
  "function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)",
  "function getRoundData(uint80) view returns (uint80, int256, uint256, uint256, uint80)",
  "function decimals() view returns (uint8)",
]);
const erc8056 = parseAbi(["function uiMultiplier() view returns (uint256)", "function effectiveAt() view returns (uint256)"]);

const logs = await testnet.getLogs({
  address: SIGNED_SOURCE_TESTNET,
  event: parseAbiItem("event PriceUpdated(bytes32 indexed feedId, int192 price, uint64 observedAt, uint256 signerCount)"),
  fromBlock: 0n,
  toBlock: "latest",
});
const slate = {};
for (const l of logs) {
  const sym = hexToString(l.args.feedId, { size: 32 }).replace(/\0/g, "").replace("/USD", "");
  if (!TOKENS[sym]) continue;
  (slate[sym] ??= []).push({ t: Number(l.args.observedAt), p: Number(l.args.price) / 1e8, signers: Number(l.args.signerCount) });
}
const from = Math.min(...Object.values(slate).flat().map((x) => x.t));
const to = Math.max(...Object.values(slate).flat().map((x) => x.t));

const out = { generatedAt: new Date().toISOString(), from, to, matchWindow: MATCH_WINDOW, tokens: {} };
for (const [sym, c] of Object.entries(TOKENS)) {
  const [mult, eff, dec] = await Promise.all([
    mainnet.readContract({ address: c.token, abi: erc8056, functionName: "uiMultiplier" }),
    mainnet.readContract({ address: c.token, abi: erc8056, functionName: "effectiveAt" }),
    mainnet.readContract({ address: c.chainlink, abi: agg, functionName: "decimals" }),
  ]);
  if (eff !== 0n) throw new Error(`${sym}: a multiplier change is on record; handle it before charting`);
  const m = Number(mult) / 1e18;
  // Every Chainlink round from the window's start (and the one in force at it) to now.
  const rounds = [];
  let [id, answer, , updatedAt] = await mainnet.readContract({ address: c.chainlink, abi: agg, functionName: "latestRoundData" });
  for (;;) {
    rounds.unshift({ t: Number(updatedAt), p: Number(answer) / 10 ** dec, round: id.toString() });
    if (Number(updatedAt) < from || id <= 1n) break;
    try {
      [id, answer, , updatedAt] = await mainnet.readContract({ address: c.chainlink, abi: agg, functionName: "getRoundData", args: [id - 1n] });
    } catch {
      break;
    }
  }
  const s = slate[sym].sort((a, b) => a.t - b.t);
  // Like for like: each Chainlink update in the window against Slate's report signed closest to it, within 90 s.
  const matched = [];
  for (const r of rounds.filter((r) => r.t >= from && r.t <= to + MATCH_WINDOW)) {
    let best = null;
    for (const x of s) if (Math.abs(x.t - r.t) <= MATCH_WINDOW && (!best || Math.abs(x.t - r.t) < Math.abs(best.t - r.t))) best = x;
    if (best) matched.push({ t: r.t, chainlink: r.p, slate: best.p * m, slateAt: best.t, gapPct: ((best.p * m) / r.p - 1) * 100 });
  }
  // Continuous: every Slate report against Chainlink's answer in force at that moment (includes Chainlink's 0.5% threshold lag).
  const series = [];
  let k = 0;
  for (const x of s) {
    while (k + 1 < rounds.length && rounds[k + 1].t <= x.t) k++;
    if (rounds[k].t > x.t) continue;
    series.push({ t: x.t, slate: x.p * m, chainlink: rounds[k].p, gapPct: ((x.p * m) / rounds[k].p - 1) * 100 });
  }
  out.tokens[sym] = { multiplier: m, chainlink: c.chainlink, token: c.token, slateReports: s.length, chainlinkRounds: rounds.filter((r) => r.t >= from && r.t <= to).length, matched, series };
  console.log(sym, "slate", s.length, "rounds in window", out.tokens[sym].chainlinkRounds, "matched", matched.length, "series", series.length);
}
fs.writeFileSync(new URL("../public/accuracy-history-4.json", import.meta.url), JSON.stringify(out));
console.log("window", new Date(from * 1000).toISOString(), "->", new Date(to * 1000).toISOString());
