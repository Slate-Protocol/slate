import assert from "node:assert/strict";
import { test } from "node:test";
import { size, slice, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { handle, parseAllow, type CosignDeps } from "./cosigner.ts";
import { cosign } from "./cosigners.ts";
import { buildReport, feedId, readEntry } from "./report.ts";
import type { Quote } from "./robinhood.ts";

const SLATE_KEYS: Hex[] = [
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
];
const OPERATOR_KEY: Hex = "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a";
const SOURCE = "0xf0b57272f1D69083019E8953B82bC128002D7526";
const NOW = 1_790_950_000;

const quote = (mid: bigint, observedAt = NOW - 5): Quote => ({
  symbol: "CRWD",
  bid: mid - 10_000_000n,
  ask: mid + 10_000_000n,
  mid,
  tokenBid: (mid - 10_000_000n) * 4n,
  observedAt,
  halted: false,
});

const deps = (mid = 27_062_000_000n, observedAt = NOW - 5): CosignDeps => ({
  key: OPERATOR_KEY,
  allow: parseAllow(`4663:${SOURCE}`),
  quote: async () => quote(mid, observedAt),
  now: () => NOW,
});

/** A fetch that answers from the co-signer's handler, as if over HTTP. */
const local = (d: CosignDeps, tamper?: (b: Record<string, unknown>) => void): typeof fetch =>
  (async (input: string | URL | Request) => {
    const { status, body } = await handle(new URL(String(input)), d);
    if (tamper) tamper(body as Record<string, unknown>);
    return new Response(JSON.stringify(body), { status });
  }) as typeof fetch;

test("the co-signer signs its own observation, only for allowlisted sources", async () => {
  const ok = await handle(new URL(`http://x/sign?symbol=crwd&chainId=4663&source=${SOURCE}`), deps());
  assert.equal(ok.status, 200);
  const body = ok.body as { signer: string; entry: Hex; price: string; observedAt: number };
  const e = await readEntry(body.entry, 4663, SOURCE, feedId("CRWD"));
  assert.equal(e.signer, privateKeyToAccount(OPERATOR_KEY).address);
  assert.equal(e.price, 27_062_000_000n);
  assert.equal(Number(e.observedAt), NOW - 5);

  const other = await handle(new URL(`http://x/sign?symbol=CRWD&chainId=46630&source=${SOURCE}`), deps());
  assert.equal(other.status, 403);
  const bad = await handle(new URL(`http://x/sign?symbol=CR%20WD&chainId=4663&source=${SOURCE}`), deps());
  assert.equal(bad.status, 400);
  const stale = await handle(new URL(`http://x/sign?symbol=CRWD&chainId=4663&source=${SOURCE}`), deps(27_062_000_000n, NOW - 600));
  assert.equal(stale.status, 409); // the same quote checks as the publisher: too old
});

test("the publisher keeps a verified co-signer entry and packs four signers in order", async () => {
  const ours = quote(27_060_000_000n);
  const { entries, dropped } = await cosign(["http://op"], "CRWD", 4663, SOURCE, ours, local(deps()));
  assert.deepEqual(dropped, []);
  assert.equal(entries.length, 1);

  const report = await buildReport(SLATE_KEYS, 4663, SOURCE, { feedId: feedId("CRWD"), price: ours.mid, observedAt: BigInt(ours.observedAt) }, entries);
  assert.equal(size(report), 97 * 4);
  const signers: string[] = [];
  for (let i = 0; i < 4; i++) signers.push((await readEntry(slice(report, i * 97, (i + 1) * 97), 4663, SOURCE, feedId("CRWD"))).signer);
  const expected = [...SLATE_KEYS, OPERATOR_KEY].map((k) => privateKeyToAccount(k).address).sort((a, b) => (a.toLowerCase() < b.toLowerCase() ? -1 : 1));
  assert.deepEqual(signers, expected);
});

test("the publisher drops entries that are forged, far off, or out of time", async () => {
  const ours = quote(27_060_000_000n);
  const forged = await cosign(["http://op"], "CRWD", 4663, SOURCE, ours, local(deps(), (b) => (b.signer = privateKeyToAccount(SLATE_KEYS[0]).address)));
  assert.equal(forged.entries.length, 0);
  assert.match(forged.dropped[0], /claimed/);

  const far = await cosign(["http://op"], "CRWD", 4663, SOURCE, ours, local(deps(27_330_000_000n))); // ~1% off
  assert.equal(far.entries.length, 0);
  assert.match(far.dropped[0], /vs ours/);

  const late = await cosign(["http://op"], "CRWD", 4663, SOURCE, quote(27_060_000_000n, NOW - 100), local(deps()));
  assert.equal(late.entries.length, 0);
  assert.match(late.dropped[0], /observed/);
});
