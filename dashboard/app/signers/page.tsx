import type { Metadata } from "next";
import { SignersPanel } from "@/components/signers";
import { Shell } from "@/components/shell";
import { getDashboardData } from "@/lib/data";

export const revalidate = 60;

export const metadata: Metadata = { title: "Signers", description: "Who signs Slate's prices, the quorum, and the timelock over the signer set, read from the chain." };

export default async function SignersPage() {
  const data = await getDashboardData();
  return (
    <Shell>
      <SignersPanel testnet={data.testnet} mainnet={data.mainnet} docsUrl={process.env.NEXT_PUBLIC_DOCS_URL ?? "https://docs.slate.0xo.in"} />
    </Shell>
  );
}
