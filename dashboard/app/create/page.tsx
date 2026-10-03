import type { Metadata } from "next";
import { CreatePanel } from "@/components/live";
import { Shell } from "@/components/shell";
import { getDashboardData } from "@/lib/data";

export const revalidate = 60;

export const metadata: Metadata = { title: "Create & redeem", description: "Create and redeem SLATE-5 in kind or with cash, through oracle-banded pools." };

export default async function CreatePage() {
  const data = await getDashboardData();
  return (
    <Shell>
      <CreatePanel testnet={data.testnet} />
    </Shell>
  );
}
