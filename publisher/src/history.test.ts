import assert from "node:assert/strict";
import { test } from "node:test";
import type { BoardRow } from "./board.ts";
import { snapshotRow } from "./history.ts";

const row = (latest: { price: string; observedAt: number }, at?: { price: string; observedAt: number }): BoardRow => ({
  symbol: "CRWD",
  token: "0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931",
  chainlink: "0x0000000000000000000000000000000000000001",
  chainlinkDecimals: 8,
  chainlinkThresholdPct: 0.5,
  chainlinkHeartbeat: 86400,
  latest: { symbol: "CRWD", feedId: "0x00", report: "0xab", ...latest },
  atChainlink: at ? { symbol: "CRWD", feedId: "0x00", report: "0xcd", ...at } : undefined,
});

test("a snapshot row applies the multiplier and computes gaps as the dashboard does", () => {
  // 268.105 a share × 4 = 1,072.42; Chainlink (hypothetically) at 1,070.00.
  const s = snapshotRow(row({ price: "26810500000", observedAt: 2000 }, { price: "26750000000", observedAt: 1950 }), 4n * 10n ** 18n, 107000000000n, 8, 1990)!;
  assert.equal(s.slatePrice, 1072.42);
  assert.equal(s.multiplier, 4);
  assert.ok(Math.abs(s.gapNowPct - (1072.42 / 1070 - 1) * 100) < 1e-9);
  assert.equal(s.slateThenPrice, 1070);
  assert.equal(s.gapThenPct, 0);
  assert.equal(s.report, "0xab");
});

test("no like-for-like gap when Slate's nearest report is more than 90 s from Chainlink's update", () => {
  const s = snapshotRow(row({ price: "26810500000", observedAt: 2000 }, { price: "26750000000", observedAt: 1800 }), 4n * 10n ** 18n, 107000000000n, 8, 1990)!;
  assert.equal(s.slateThenPrice, null);
  assert.equal(s.gapThenPct, null);
});

test("nothing to store without a signed price", () => {
  const r = row({ price: "1", observedAt: 1 });
  delete r.latest;
  assert.equal(snapshotRow(r, 10n ** 18n, 1n, 8, 1), null);
});
