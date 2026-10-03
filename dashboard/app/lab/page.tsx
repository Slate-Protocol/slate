import type { Metadata } from "next";
import { LabPanel } from "@/components/live";
import { Shell } from "@/components/shell";
import { getDashboardData } from "@/lib/data";

export const revalidate = 60;

export const metadata: Metadata = { title: "Lab", description: "The Corporate Action Lab: split a test token and watch a naive feed go wrong while SlateFeed refuses." };

export default async function LabPage() {
  const data = await getDashboardData();
  return (
    <Shell>
      <LabPanel testnet={data.testnet} />
    </Shell>
  );
}
