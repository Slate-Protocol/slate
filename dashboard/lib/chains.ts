import { createPublicClient, defineChain, http, type PublicClient } from "viem";
import { arbitrum } from "viem/chains";

export const robinhoodChain = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.mainnet.chain.robinhood.com"] } },
  blockExplorers: { default: { name: "Blockscout", url: "https://robinhoodchain.blockscout.com" } },
});

export const robinhoodTestnet = defineChain({
  id: 46630,
  name: "Robinhood Chain testnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.testnet.chain.robinhood.com"] } },
  blockExplorers: { default: { name: "Blockscout", url: "https://explorer.testnet.chain.robinhood.com" } },
  testnet: true,
});

export const chains = [robinhoodChain, robinhoodTestnet, arbitrum] as const;
export type ChainId = (typeof chains)[number]["id"];

const clients = new Map<number, PublicClient>();

/** A cached public client per chain. Reads only; nothing here signs. */
export function client(chainId: ChainId): PublicClient {
  let c = clients.get(chainId);
  if (!c) {
    const chain = chains.find((x) => x.id === chainId)!;
    c = createPublicClient({ chain, transport: http(undefined, { retryCount: 2, timeout: 8_000 }) }) as PublicClient;
    clients.set(chainId, c);
  }
  return c;
}

export const networkLabel: Record<ChainId, string> = {
  4663: "Robinhood Chain",
  46630: "RH testnet",
  42161: "Arbitrum One",
};
