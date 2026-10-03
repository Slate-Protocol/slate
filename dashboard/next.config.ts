import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // pnpm workspace: packages resolve through the monorepo root's node_modules.
  turbopack: {
    root: path.join(import.meta.dirname, ".."),
    // See lib/stubs/empty.js.
    resolveAlias: {
      "@x402/core/client": "./lib/stubs/empty.js",
      "@x402/core/schemas": "./lib/stubs/empty.js",
      "@x402/core/server": "./lib/stubs/empty.js",
      "@x402/evm": "./lib/stubs/empty.js",
      "@x402/evm/auth-capture/client": "./lib/stubs/empty.js",
      "@x402/evm/batch-settlement/client": "./lib/stubs/empty.js",
      "@x402/evm/exact/client": "./lib/stubs/empty.js",
      "@x402/evm/exact/server": "./lib/stubs/empty.js",
      "@x402/evm/exact/v1/client": "./lib/stubs/empty.js",
      "@x402/evm/upto/client": "./lib/stubs/empty.js",
      "@x402/evm/upto/server": "./lib/stubs/empty.js",
      "@x402/express": "./lib/stubs/empty.js",
      "@x402/extensions/bazaar": "./lib/stubs/empty.js",
      "@x402/extensions/builder-code": "./lib/stubs/empty.js",
      "@x402/fetch": "./lib/stubs/empty.js",
      "@x402/svm/exact/client": "./lib/stubs/empty.js",
      "@x402/svm/exact/server": "./lib/stubs/empty.js",
      "@x402/svm/exact/v1/client": "./lib/stubs/empty.js",
      "@x402/svm/upto/client": "./lib/stubs/empty.js",
      "@x402/svm/upto/server": "./lib/stubs/empty.js",
    },
  },
};

export default nextConfig;
