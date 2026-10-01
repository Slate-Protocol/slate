import "server-only";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { formatUnits, type Address } from "viem";
import { aggregatorAbi, erc8056Abi, slateFeedAbi } from "./abi";
import { client, networkLabel, type ChainId } from "./chains";
import { FEED_STATUS, type FeedStatusLabel } from "./status";

const DEPLOYMENTS_URL = "https://raw.githubusercontent.com/Slate-Protocol/slate/main/deployments/deployments.json";
const USDG_USD: Address = "0x61B7e5650328764B076A108EFF5fa7282a1B9aD2"; // Chainlink, Robinhood Chain

type Deployments = {
  networks: Record<string, { name: string; explorer: string; contracts: Record<string, Address> }>;
  feeds: { symbol: string; chainId: ChainId; token: Address; feed: Address }[];
};

/** The repo's deployments.json: the local copy in development, GitHub in production. */
async function deployments(): Promise<Deployments> {
  try {
    const local = await readFile(path.join(process.cwd(), "..", "deployments", "deployments.json"), "utf8");
    return JSON.parse(local) as Deployments;
  } catch {
    const res = await fetch(DEPLOYMENTS_URL, { next: { revalidate: 60 } });
    return (await res.json()) as Deployments;
  }
}

type Token = {
  ticker: string;
  chainId: ChainId;
  token?: Address;
  source: string;
  lab?: boolean;
};

const TOKENS: Token[] = [
  { ticker: "CRWD", chainId: 4663, token: "0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931", source: "Signed · 3 of 3" },
  { ticker: "AAPL", chainId: 4663, token: "0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9", source: "Chainlink · total return" },
  { ticker: "TSLA", chainId: 46630, token: "0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E", source: "Signed · 2 of 3" },
  { ticker: "AMZN", chainId: 46630, token: "0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02", source: "Signed · 2 of 3" },
  { ticker: "AMD", chainId: 46630, token: "0x71178BAc73cBeb415514eB542a8995b82669778d", source: "Signed · 2 of 3" },
  { ticker: "PLTR", chainId: 46630, token: "0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0", source: "Signed · 2 of 3" },
  { ticker: "NFLX", chainId: 46630, token: "0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93", source: "Signed · 2 of 3" },
  { ticker: "labTSLA", chainId: 42161, source: "Chainlink · raw × multiplier", lab: true },
];

export type FeedRow = {
  ticker: string;
  network: string;
  source: string;
  lab: boolean;
  /** Shares per token, from the token itself; null when it could not be read. */
  multiplier: number | null;
  /** USD per token from the deployed SlateFeed; null until the feed is deployed or when it has no data. */
  price: number | null;
  status: FeedStatusLabel;
};

export type DashboardData = {
  rows: FeedRow[];
  crwd: {
    multiplier: number | null;
    sharePrice: number;
    tokenPrice: number;
    /** True when the figures are the fork-test snapshot rather than a deployed feed. */
    snapshot: boolean;
  };
  usdgUsd: number | null;
  feedsLive: number;
  readAt: string;
};

const settle = async <T,>(p: Promise<T>): Promise<T | null> => {
  try {
    return await p;
  } catch {
    return null;
  }
};

export async function getDashboardData(): Promise<DashboardData> {
  const dep = await deployments();

  const rows = await Promise.all(
    TOKENS.map(async (t): Promise<FeedRow> => {
      const multiplierRaw = t.token
        ? await settle(client(t.chainId).readContract({ address: t.token, abi: erc8056Abi, functionName: "uiMultiplier" }))
        : null;
      const feed = dep.feeds.find((f) => f.symbol === t.ticker && f.chainId === t.chainId);
      const detail = feed
        ? await settle(client(t.chainId).readContract({ address: feed.feed, abi: slateFeedAbi, functionName: "latestDetail" }))
        : null;
      return {
        ticker: t.ticker,
        network: networkLabel[t.chainId],
        source: t.source,
        lab: !!t.lab,
        multiplier:
          multiplierRaw !== null ? Number(formatUnits(multiplierRaw, 18)) : detail ? Number(formatUnits(detail[2], 18)) : null,
        price: detail && detail[0].answer > 0n ? Number(formatUnits(detail[0].answer, 8)) : null,
        status: detail ? FEED_STATUS[detail[0].status] ?? "No data" : "Not deployed",
      };
    }),
  );

  const usdg = await settle(client(4663).readContract({ address: USDG_USD, abi: aggregatorAbi, functionName: "latestRoundData" }));
  const crwdRow = rows[0];

  return {
    rows,
    crwd: {
      multiplier: crwdRow.multiplier,
      // Until CRWD's SlateFeed is deployed these are the fork-test figures: $264.98 signed share price × 4.
      sharePrice: crwdRow.price !== null && crwdRow.multiplier ? crwdRow.price / crwdRow.multiplier : 264.98,
      tokenPrice: crwdRow.price ?? 1059.92,
      snapshot: crwdRow.price === null,
    },
    usdgUsd: usdg && usdg[1] > 0n ? Number(formatUnits(usdg[1], 8)) : null,
    feedsLive: dep.feeds.length,
    readAt: new Date().toISOString(),
  };
}
