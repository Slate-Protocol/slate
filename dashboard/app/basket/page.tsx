import type { Metadata } from "next";
import { BasketPanel } from "@/components/live";
import { Shell } from "@/components/shell";
import { getDashboardData } from "@/lib/data";

export const revalidate = 60;

export const metadata: Metadata = { title: "Basket", description: "SLATE-5, an in-kind basket of five stock tokens, and its NAV feed." };

export default async function BasketPage() {
  const data = await getDashboardData();
  return (
    <Shell>
      <BasketPanel testnet={data.testnet} usdgUsd={data.usdgUsd} />
    </Shell>
  );
}
