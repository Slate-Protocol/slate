import type { Metadata } from "next";
import type { Address } from "viem";
import { Arithmetic } from "@/components/arithmetic";
import { Shell } from "@/components/shell";
import type { ChainId } from "@/lib/chains";
import { deployments } from "@/lib/data";

export const revalidate = 300;

export const metadata: Metadata = {
  title: "The arithmetic",
  description: "Share price, multiplier, timestamp and the result, step by step, read from the chain for any Slate feed.",
};

export default async function ArithmeticPage() {
  const dep = await deployments();
  // Every SlateFeed (the basket's NAV feed is a different contract): mainnet first, CRWD at the top.
  const options = dep.feeds
    .filter((f) => f.symbol !== "SLATE-5")
    .map((f) => ({ symbol: f.symbol, feed: f.feed as Address, chainId: f.chainId as ChainId }))
    .sort((a, b) => (a.chainId === b.chainId ? (a.symbol === "CRWD" ? -1 : b.symbol === "CRWD" ? 1 : a.symbol.localeCompare(b.symbol)) : a.chainId === 4663 ? -1 : 1));
  return (
    <Shell>
      <Arithmetic options={options} />
    </Shell>
  );
}
