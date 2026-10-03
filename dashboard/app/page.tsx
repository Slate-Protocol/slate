import { HashForward } from "@/components/hash-forward";
import FeedsPage from "./feeds/page";

export const revalidate = 60;

/** The dashboard's front door shows Feeds; old links to its sections (/#lend) forward to their routes. */
export default async function Dashboard() {
  return (
    <>
      <HashForward />
      <FeedsPage />
    </>
  );
}
