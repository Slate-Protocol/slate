import type { Metadata } from "next";
import { UsdgProof } from "@/components/live";
import { FeedsTable, Legend, Overview } from "@/components/sections";
import { Shell } from "@/components/shell";
import { getDashboardData } from "@/lib/data";

export const revalidate = 60;

export const metadata: Metadata = { title: "Feeds", description: "Every Slate feed, its source, the multiplier it applies and why it will or won't serve a price." };

export default async function FeedsPage() {
  const data = await getDashboardData();
  return (
    <Shell>
      <Overview data={data} />
      <UsdgProof />
      <FeedsTable rows={data.rows} usdgUsd={data.usdgUsd} />
      <Legend />
    </Shell>
  );
}
