import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { defineChain, type Address, type Chain, type Hex } from "viem";

export const robinhoodMainnet = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.mainnet.chain.robinhood.com"] } },
});

export const robinhoodTestnet = defineChain({
  id: 46630,
  name: "Robinhood Chain testnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.testnet.chain.robinhood.com"] } },
  testnet: true,
});

/** Chainlink's raw TSLA/USD push feed on Arbitrum One, used only as an independent cross-check. */
export const ARBITRUM_RPC = process.env.ARBITRUM_RPC_URL ?? "https://arb1.arbitrum.io/rpc";
export const CROSS_CHECK_FEEDS: Record<string, Address> = {
  TSLA: "0x3609baAa0a9b1f0FE4d6CC01884585d0e191C3E3",
};

/** Which deployed feeds read the signed price, per chain. Feed ids are `<SYMBOL>/USD`. */
export const SIGNED_SYMBOLS: Record<number, string[]> = {
  46630: ["TSLA", "AMZN", "AMD", "PLTR", "NFLX"],
  4663: ["CRWD"],
};

/**
 * Signing ahead of a deployment. Robinhood Chain mainnet is deployed after Friday's close, and the publisher signs
 * nothing while the market is closed, so CRWD's feed would hold no price until Monday. Instead, while the session is
 * open, the publisher signs real CRWD observations for the SignedSource that the deployer's nonce 3 will create on
 * mainnet. The last one signed before the close is relayed after deployment, at its true observation time, and the
 * feed reads MARKET_CLOSED with Friday's closing price. Inactive once mainnet's SignedSource is in deployments.json.
 */
export const PRESIGN = {
  chainId: 4663,
  signedSource: "0xf0b57272f1D69083019E8953B82bC128002D7526" as Address,
  symbols: ["CRWD"],
  keep: 24,
};

/** Testnet stocks whose TESTUSD pools the keeper keeps on the Slate price. */
export const POOL_SYMBOLS = ["TSLA", "AMZN", "AMD", "PLTR", "NFLX"];

/**
 * When to submit, per chain: on a move of `deviationBps` since the last on-chain price, or once the on-chain price
 * is `heartbeat` seconds old. Each must stay inside the feeds' `maxAge` (20 minutes on testnet, 40 on mainnet).
 * Mainnet gas is real money, so CRWD is signed on a 0.5% move or every 30 minutes; testnet tracks closely.
 */
export const CADENCE: Record<number, { deviationBps: number; heartbeat: number }> = {
  46630: { deviationBps: 10, heartbeat: 300 },
  4663: { deviationBps: 50, heartbeat: 1800 },
};

export const settings = {
  /** Seconds between cycles. */
  interval: Number(process.env.PUBLISH_INTERVAL ?? 15),
  /** Refuse a Robinhood quote older than this, in seconds. */
  maxQuoteAge: 60,
  /** Refuse a quote whose bid/ask spread is wider than this. */
  maxSpreadBps: 200,
  /** Robinhood's tokenBid ÷ bid must match the token's on-chain multiplier within this. */
  multiplierToleranceBps: 50,
  /** Robinhood and Chainlink (where both exist) must agree within this. */
  crossCheckToleranceBps: 200,
  /** Recenter a testnet pool when it is this far from the Slate price. */
  recenterBps: 50,
  port: Number(process.env.PORT ?? 8080),
};

export type Keys = { signers: Hex[]; relayer: Hex };

export function keys(): Keys {
  const need = (name: string): Hex => {
    const v = process.env[name];
    if (!v || !/^0x[0-9a-fA-F]{64}$/.test(v)) throw new Error(`missing or malformed ${name}`);
    return v as Hex;
  };
  return {
    signers: [need("SIGNER_1_PRIVATE_KEY"), need("SIGNER_2_PRIVATE_KEY"), need("SIGNER_3_PRIVATE_KEY")],
    relayer: need("RELAYER_PRIVATE_KEY"),
  };
}

export type Network = {
  chain: Chain;
  rpc: string;
  contracts: Record<string, Address>;
  feeds: { symbol: string; token: Address; feed: Address }[];
};

type Manifest = {
  networks: Record<string, { contracts: Record<string, Address> }>;
  feeds: { symbol: string; chainId: number; token: Address; feed: Address }[];
};

const MANIFEST_URL = "https://raw.githubusercontent.com/Slate-Protocol/slate/main/deployments/deployments.json";

/** The repo's deployments.json: the checked-out copy when present, else the published one on GitHub. */
export async function loadManifest(): Promise<Manifest> {
  const local = process.env.DEPLOYMENTS_FILE ?? fileURLToPath(new URL("../../deployments/deployments.json", import.meta.url));
  try {
    return JSON.parse(await readFile(local, "utf8")) as Manifest;
  } catch {
    const res = await fetch(MANIFEST_URL, { cache: "no-store" });
    if (!res.ok) throw new Error(`deployments.json: HTTP ${res.status}`);
    return (await res.json()) as Manifest;
  }
}

/** Networks with a deployed SignedSource. */
export function networks(m: Manifest): Network[] {
  const out: Network[] = [];
  for (const chain of [robinhoodTestnet, robinhoodMainnet]) {
    const contracts = m.networks[String(chain.id)]?.contracts ?? {};
    if (!contracts.SignedSource) continue;
    const rpcEnv = chain.id === 4663 ? process.env.RH_MAINNET_RPC_URL : process.env.RH_TESTNET_RPC_URL;
    out.push({
      chain,
      rpc: rpcEnv ?? chain.rpcUrls.default.http[0],
      contracts,
      feeds: m.feeds.filter((f) => f.chainId === chain.id),
    });
  }
  return out;
}
