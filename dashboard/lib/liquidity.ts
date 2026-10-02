"use client";

import { useQuery } from "@tanstack/react-query";
import {
  decodeErrorResult,
  encodeAbiParameters,
  encodeFunctionData,
  formatUnits,
  keccak256,
  maxUint256,
  pad,
  toHex,
  type Address,
  type Hex,
} from "viem";
import { usePublicClient } from "wagmi";
import { routerAbi } from "./abi";
import { FEED_STATUS } from "./status";

/** A placeholder account that exists only inside the simulation. */
const PROBE: Address = "0x000000000000000000000000000000000000510E";
const CASH = 10n ** 12n; // one million TESTUSD, inside the simulation only

export type Liquidity =
  | { kind: "ok"; cashIn: bigint }
  | { kind: "refused"; leg: number; symbol: string; effective: number; feed: number; oneShareOk: boolean }
  | { kind: "feed"; status: string }
  | { kind: "unknown"; detail: string };

/** OpenZeppelin ERC-20 v5 storage: `_balances` at slot 0, `_allowances` at slot 1. */
function cashOverride(cash: Address, router: Address) {
  const balance = keccak256(encodeAbiParameters([{ type: "address" }, { type: "uint256" }], [PROBE, 0n]));
  const inner = keccak256(encodeAbiParameters([{ type: "address" }, { type: "uint256" }], [PROBE, 1n]));
  const allowance = keccak256(encodeAbiParameters([{ type: "address" }, { type: "bytes32" }], [router, inner]));
  return [
    {
      address: cash,
      stateDiff: [
        { slot: balance, value: pad(toHex(CASH)) },
        { slot: allowance, value: pad(toHex(maxUint256)) },
      ],
    },
  ];
}

/**
 * Whether the testnet pools can serve a cash creation of `shares` right now. It simulates the real router call
 * from a placeholder account given TESTUSD only inside the simulation (an `eth_call` state override), so the
 * answer does not depend on the visitor's wallet, balance or approvals. A refusal is the router's 3% band working;
 * on testnet the usual cause is the seeded pools' limited depth, not a fault.
 */
export function useCashLiquidity(args: {
  router?: Address;
  cash?: Address;
  venue?: Address;
  route: Hex;
  legs: number;
  symbols: string[];
  shares: bigint;
  chainId: number;
}) {
  const client = usePublicClient({ chainId: args.chainId });
  return useQuery({
    queryKey: ["cash-liquidity", args.router, args.shares.toString()],
    enabled: !!client && !!args.router && !!args.cash && !!args.venue && args.shares > 0n,
    refetchInterval: 15_000,
    queryFn: async (): Promise<Liquidity> => {
      const simulate = async (shares: bigint) => {
        const data = encodeFunctionData({
          abi: routerAbi,
          functionName: "createWithCash",
          args: [
            shares,
            PROBE,
            Array.from({ length: args.legs }, () => ({ venue: args.venue!, route: args.route })),
            CASH,
            BigInt(Math.floor(Date.now() / 1000) + 600),
          ],
        });
        return client!.call({ account: PROBE, to: args.router!, data, stateOverride: cashOverride(args.cash!, args.router!) });
      };
      const decode = (e: unknown) => {
        let raw: Hex | undefined;
        let cur: unknown = e;
        for (let i = 0; i < 6 && cur && !raw; i++) {
          const d = (cur as { data?: unknown }).data;
          if (typeof d === "string" && d.startsWith("0x")) raw = d as Hex;
          cur = (cur as { cause?: unknown }).cause;
        }
        if (!raw) return null;
        try {
          return decodeErrorResult({ abi: routerAbi, data: raw });
        } catch {
          return null;
        }
      };
      try {
        const r = await simulate(args.shares);
        return { kind: "ok", cashIn: r.data ? BigInt(r.data) : 0n };
      } catch (e) {
        const err = decode(e);
        if (err?.errorName === "RouteRefused") {
          const [leg, effective, feed] = err.args as readonly bigint[];
          let oneShareOk = false;
          if (args.shares > 10n ** 18n) {
            oneShareOk = await simulate(10n ** 18n).then(
              () => true,
              () => false,
            );
          }
          return {
            kind: "refused",
            leg: Number(leg) + 1,
            symbol: args.symbols[Number(leg)] ?? `leg ${Number(leg) + 1}`,
            effective: Number(formatUnits(effective, 8)),
            feed: Number(formatUnits(feed, 8)),
            oneShareOk,
          };
        }
        if (err?.errorName === "FeedUnavailable") {
          return { kind: "feed", status: FEED_STATUS[Number((err.args as readonly unknown[])[0])] ?? "unusable" };
        }
        return { kind: "unknown", detail: err?.errorName ?? "the pools could not fill this size" };
      }
    },
  });
}

