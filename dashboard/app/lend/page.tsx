import type { Metadata } from "next";
import { LendPanel } from "@/components/lend";
import { Shell } from "@/components/shell";
import { getDashboardData } from "@/lib/data";

export const revalidate = 60;

export const metadata: Metadata = { title: "Lend", description: "StockLender: a lending market that prices stock collateral through Slate feeds." };

export default async function LendPage() {
  const data = await getDashboardData();
  return (
    <Shell>
      <LendPanel testnet={data.testnet} mainnet={data.mainnet} />
    </Shell>
  );
}
