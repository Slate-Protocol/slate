import assert from "node:assert/strict";
import { test } from "node:test";
import { hexToBigInt, hexToNumber, recoverTypedDataAddress, slice, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { closest, matchCovered, type Attestation } from "./board.ts";
import { PRESIGN } from "./config.ts";
import { buildReport, domain, feedId, types } from "./report.ts";

const KEYS: Hex[] = [
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
];

const entry = (name: string, proxyAddress = "0x6B22A786bAa607d76728168703a39Ea9C99f2cD0") => ({
  name,
  proxyAddress,
  decimals: 8,
  threshold: 0.5,
  heartbeat: 86400,
});
const asset = (tokenSymbol: string, chainId = 4663) => ({
  tokenSymbol,
  deployments: [{ contractAddress: "0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9", chainId }],
});

test("coverage: Robinhood stock feeds in both spellings, matched to tokens deployed on mainnet", () => {
  const covered = matchCovered(
    [
      entry("Robinhood AAPL / USD"),
      entry("Robinhood SGOV-USD"),
      entry("ETH / USD"), // not a stock feed
      entry("Robinhood ZZZ / USD"), // no such token in the registry
      entry("Robinhood TEST / USD"), // token only on another chain
      entry("Robinhood AAPL / USD", "0x0000000000000000000000000000000000000001"), // duplicate listing
    ],
    [asset("AAPL"), asset("SGOV"), asset("TEST", 46630)],
  );
  assert.deepEqual(
    covered.map((c) => c.symbol),
    ["AAPL", "SGOV"],
  );
  assert.equal(covered[0].chainlink, "0x6B22A786bAa607d76728168703a39Ea9C99f2cD0");
  assert.equal(covered[0].thresholdPct, 0.5);
});

test("the report matched to Chainlink's update is the nearest one inside the window, or none", () => {
  const at = (observedAt: number): Attestation => ({ symbol: "AAPL", feedId: feedId("AAPL"), price: "1", observedAt, report: "0x" });
  const history = [at(1000), at(1060), at(1120), at(1180)];
  assert.equal(closest(history, 1100)?.observedAt, 1120);
  assert.equal(closest(history, 1090)?.observedAt, 1060);
  assert.equal(closest(history, 1300), undefined); // 120 s from the nearest
  assert.equal(closest(history, 1270)?.observedAt, 1180);
});

/** What the dashboard does with a board report: recover each 97-byte entry's signer for mainnet's domain. */
test("a board report verifies against mainnet's SignedSource domain, one signer per entry", async () => {
  const obs = { feedId: feedId("AAPL"), price: 33_250_000_000n, observedAt: 1_790_950_000n };
  const report = await buildReport(KEYS, PRESIGN.chainId, PRESIGN.signedSource, obs);
  const recovered: string[] = [];
  for (let i = 0; i < 3; i++) {
    const e = slice(report, i * 97, (i + 1) * 97);
    assert.equal(hexToBigInt(slice(e, 0, 24)), obs.price);
    assert.equal(hexToBigInt(slice(e, 24, 32)), obs.observedAt);
    const signature = `${slice(e, 32, 96)}${slice(e, 96, 97).slice(2)}` as Hex;
    recovered.push(
      await recoverTypedDataAddress({
        domain: domain(PRESIGN.chainId, PRESIGN.signedSource),
        types,
        primaryType: "Observation",
        message: obs,
        signature,
      }),
    );
    assert.ok([27, 28].includes(hexToNumber(slice(e, 96, 97))));
  }
  const expected = KEYS.map((k) => privateKeyToAccount(k).address).sort((a, b) => (a.toLowerCase() < b.toLowerCase() ? -1 : 1));
  assert.deepEqual(recovered, expected);
});
