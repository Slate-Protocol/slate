import { BasketPanel, CreatePanel, LabPanel, UsdgProof } from "@/components/live";
import { FeedsTable, Legend, Overview } from "@/components/sections";
import { Shell } from "@/components/shell";
import { getDashboardData } from "@/lib/data";

export const revalidate = 60;

export default async function Dashboard() {
  const data = await getDashboardData();
  return (
    <Shell>
      <Overview data={data} />
      <UsdgProof />
      <FeedsTable rows={data.rows} usdgUsd={data.usdgUsd} />
      <Legend />
      <div className="grid grid-cols-[repeat(auto-fit,minmax(300px,1fr))] gap-4">
        <BasketPanel testnet={data.testnet} usdgUsd={data.usdgUsd} />
        <CreatePanel testnet={data.testnet} />
      </div>
      <LabPanel testnet={data.testnet} />
    </Shell>
  );
}
