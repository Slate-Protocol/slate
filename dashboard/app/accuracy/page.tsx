import type { Metadata } from "next";
import { AccuracyBoard } from "@/components/accuracy";
import { Shell } from "@/components/shell";
import { coverage } from "@/lib/data";

export const revalidate = 3600;

export const metadata: Metadata = {
  title: "Slate against Chainlink",
  description: "Slate's signed price beside Chainlink's for every Robinhood stock token Chainlink covers, verified in the browser.",
};

export default async function Accuracy() {
  const c = await coverage();
  return (
    <Shell page="accuracy">
      <AccuracyBoard uncovered={c ? c.tokens - c.withFeed : null} />
    </Shell>
  );
}
