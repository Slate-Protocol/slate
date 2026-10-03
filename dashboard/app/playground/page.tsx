import type { Metadata } from "next";
import { Playground } from "@/components/playground";
import { Shell } from "@/components/shell";

export const metadata: Metadata = {
  title: "Integration playground",
  description: "Paste a feed address, see what it returns live, and copy the Solidity that reads it.",
};

export default function PlaygroundPage() {
  return (
    <Shell>
      <Playground />
    </Shell>
  );
}
