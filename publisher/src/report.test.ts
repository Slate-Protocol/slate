import assert from "node:assert/strict";
import { test } from "node:test";
import { hexToBigInt, recoverTypedDataAddress, size, slice, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { buildReport, domain, feedId, types } from "./report.ts";
import { parseQuote, quoteProblems, toFixed } from "./robinhood.ts";

const KEYS: Hex[] = [
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
];
const SOURCE = "0x8B27311a3493a85E063f97e4bB59cf3a22aEA507";

test("feed ids match Solidity's bytes32(\"CRWD/USD\")", () => {
  assert.equal(feedId("CRWD"), "0x435257442f555344000000000000000000000000000000000000000000000000");
});

test("decimal strings parse exactly", () => {
  assert.equal(toFixed("264.98"), 26_498_000_000n);
  assert.equal(toFixed("1059.920000000000000000"), 105_992_000_000n);
  assert.equal(toFixed("68"), 6_800_000_000n);
  assert.throws(() => toFixed("-1"));
});

test("reports are 97-byte entries in ascending signer order, each recovering its signer", async () => {
  const obs = { feedId: feedId("CRWD"), price: 26_498_000_000n, observedAt: 1_790_870_000n };
  const report = await buildReport(KEYS, 46630, SOURCE, obs);
  assert.equal(size(report), 97 * 3);

  const expected = KEYS.map((k) => privateKeyToAccount(k).address.toLowerCase()).sort();
  for (let i = 0; i < 3; i++) {
    const entry = slice(report, i * 97, (i + 1) * 97);
    assert.equal(hexToBigInt(slice(entry, 0, 24), { signed: true }), obs.price);
    assert.equal(hexToBigInt(slice(entry, 24, 32)), obs.observedAt);
    const r = slice(entry, 32, 64);
    const s = slice(entry, 64, 96);
    const v = Number(hexToBigInt(slice(entry, 96, 97)));
    const signer = await recoverTypedDataAddress({
      domain: domain(46630, SOURCE),
      types,
      primaryType: "Observation",
      message: obs,
      signature: { r, s, v: BigInt(v) },
    });
    assert.equal(signer.toLowerCase(), expected[i]);
  }
});

test("quotes: mid price, sanity checks", () => {
  const q = parseQuote({
    quotes: [
      {
        tokenSymbol: "CRWD",
        bid: "264.27",
        ask: "264.36",
        tokenBid: "1057.080000000000000000",
        generatedAt: "2026-10-01T16:33:35.995293565Z",
        isTradingHalt: false,
        deployments: [{ contractAddress: "0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931", chainId: 4663 }],
      },
    ],
  });
  assert.equal(q.mid, 26_431_500_000n);
  assert.equal(q.observedAt, 1_790_872_415);
  assert.equal(q.mainnetToken, "0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931");
  assert.deepEqual(quoteProblems(q, q.observedAt + 5), []);
  assert.deepEqual(quoteProblems(q, q.observedAt + 120), ["quote too old"]);
  assert.deepEqual(quoteProblems({ ...q, halted: true }, q.observedAt), ["trading halt"]);
  assert.deepEqual(quoteProblems({ ...q, ask: q.bid * 2n }, q.observedAt), ["spread too wide"]);
});
