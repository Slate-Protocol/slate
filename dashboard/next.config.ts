import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // pnpm workspace: packages resolve through the monorepo root's node_modules.
  turbopack: {
    root: path.join(import.meta.dirname, ".."),
  },
};

export default nextConfig;
