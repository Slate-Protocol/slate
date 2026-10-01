import { BasketAndCreate, FeedsTable, Lab, Legend, Overview } from "@/components/sections";
import { Shell } from "@/components/shell";
import { getDashboardData } from "@/lib/data";

export const revalidate = 60;

export default async function Dashboard() {
  const data = await getDashboardData();
  return (
    <Shell>
      <Overview data={data} />
      <FeedsTable rows={data.rows} usdgUsd={data.usdgUsd} />
      <Legend />
      <BasketAndCreate />
      <Lab />
    </Shell>
  );
}
