import "server-only";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { formatUnits, type Address } from "viem";
import { aggregatorAbi, erc8056Abi, navFeedAbi, slateFeedAbi } from "./abi";
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
  /** The basket's NAV feed: no multiplier of its own. */
  nav?: boolean;
  /** Listed only once deployed. */
  optional?: boolean;
};

const TOKENS: Token[] = [
  { ticker: "CRWD", chainId: 4663, token: "0xea72Ecca2d0f6bFA1394DBBCff85b52CD4233931", source: "Signed · 2 of 3" },
  { ticker: "AAPL", chainId: 4663, token: "0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9", source: "Chainlink · total return" },
  { ticker: "TSLA", chainId: 46630, token: "0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E", source: "Signed · 2 of 3" },
  { ticker: "AMZN", chainId: 46630, token: "0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02", source: "Signed · 2 of 3" },
  { ticker: "AMD", chainId: 46630, token: "0x71178BAc73cBeb415514eB542a8995b82669778d", source: "Signed · 2 of 3" },
  { ticker: "PLTR", chainId: 46630, token: "0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0", source: "Signed · 2 of 3" },
  { ticker: "NFLX", chainId: 46630, token: "0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93", source: "Signed · 2 of 3" },
  { ticker: "SLATE-5", chainId: 46630, source: "Basket NAV · 5 Slate feeds", nav: true },
  { ticker: "labTSLA", chainId: 46630, source: "Signed TSLA × Lab multiplier", lab: true },
  { ticker: "labTSLA", chainId: 42161, source: "Chainlink TSLA raw × Lab multiplier", lab: true, optional: true },
];

export type FeedRow = {
  ticker: string;
  chainId: ChainId;
  network: string;
  source: string;
  lab: boolean;
  nav: boolean;
  feed: Address | null;
  /** Shares per token, from the token itself; null when it could not be read or does not apply. */
  multiplier: number | null;
  /** USD per token from the deployed feed; null until the feed is deployed or when it has no data. */
  price: number | null;
  status: FeedStatusLabel;
};

export type Contracts = Record<string, Address>;

export type DashboardData = {
  rows: FeedRow[];
  crwd: {
    multiplier: number | null;
    sharePrice: number;
    tokenPrice: number;
    /** True when the figures are the fork-test snapshot rather than a deployed feed. */
    snapshot: boolean;
    feed: Address | null;
    /** Robinhood's own quote for one CRWD token right now, for comparison. */
    robinhood: { tokenBid: number; tokenAsk: number } | null;
  };
  testnet: {
    contracts: Contracts;
    explorer: string;
    constituents: { symbol: string; token: Address; feed: Address }[];
    labFeed: Address | null;
  };
  mainnet: { contracts: Contracts; aaplUsdg: Address | null };
  usdgUsd: number | null;
  /** Live: stock tokens in Robinhood's registry and how many have a Chainlink feed. Null if unreachable. */
  coverage: { tokens: number; withFeed: number } | null;
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

async function robinhoodQuote(symbol: string) {
  const res = await settle(fetch(`https://api.robinhood.com/rhj/prices/${symbol}`, { next: { revalidate: 30 } }));
  if (!res?.ok) return null;
  const body = (await settle(res.json())) as { quotes?: { tokenBid: string; tokenAsk: string }[] } | null;
  const q = body?.quotes?.[0];
  return q ? { tokenBid: Number(q.tokenBid), tokenAsk: Number(q.tokenAsk) } : null;
}

export async function coverage(): Promise<DashboardData["coverage"]> {
  const [assets, feeds] = await Promise.all([
    settle(fetch("https://api.robinhood.com/rhj/assets", { next: { revalidate: 3600 } }).then((r) => r.json())),
    settle(fetch("https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json", { next: { revalidate: 3600 } }).then((r) => r.json())),
  ]);
  if (!assets || !feeds) return null;
  const list = (Array.isArray(assets) ? assets : (Object.values(assets).find(Array.isArray) ?? [])) as { tokenSymbol: string }[];
  const symbols = new Set(list.map((a) => a.tokenSymbol.toUpperCase()));
  const covered = new Set<string>();
  for (const f of feeds as { name: string }[]) {
    const m = /^Robinhood\s+([A-Za-z.]+)\s*[-/]\s*USD/.exec(f.name);
    if (m && symbols.has(m[1].toUpperCase())) covered.add(m[1].toUpperCase());
  }
  return symbols.size && covered.size ? { tokens: symbols.size, withFeed: covered.size } : null;
}

export async function getDashboardData(): Promise<DashboardData> {
  const dep = await deployments();
  const feedOf = (ticker: string, chainId: number) => dep.feeds.find((f) => f.symbol === ticker && f.chainId === chainId);

  // Every other signed mainnet feed in deployments.json, after CRWD and AAPL (CRWD stays first: the hero reads it).
  const listed = new Set(TOKENS.map((t) => `${t.chainId}:${t.ticker}`));
  const extra: Token[] = dep.feeds
    .filter((f) => f.chainId === 4663 && !listed.has(`4663:${f.symbol}`))
    .sort((a, b) => a.symbol.localeCompare(b.symbol))
    .map((f) => ({ ticker: f.symbol, chainId: 4663, token: f.token, source: "Signed · 2 of 3" }));
  const tokens = [...TOKENS.slice(0, 2), ...extra, ...TOKENS.slice(2)];

  const rows = (
    await Promise.all(
      tokens.map(async (t): Promise<FeedRow | null> => {
        const feed = feedOf(t.ticker, t.chainId);
        if (t.optional && !feed) return null;
        const token = t.token ?? (t.nav ? undefined : feed?.token);
        const multiplierRaw = token
          ? await settle(client(t.chainId).readContract({ address: token, abi: erc8056Abi, functionName: "uiMultiplier" }))
          : null;
        let quote: { status: number; answer: bigint } | null = null;
        let detailMultiplier: bigint | null = null;
        if (feed && t.nav) {
          quote = await settle(client(t.chainId).readContract({ address: feed.feed, abi: navFeedAbi, functionName: "latestQuote" }));
        } else if (feed) {
          const d = await settle(client(t.chainId).readContract({ address: feed.feed, abi: slateFeedAbi, functionName: "latestDetail" }));
          if (d) {
            quote = d[0];
            detailMultiplier = d[2];
          }
        }
        const m = multiplierRaw ?? detailMultiplier;
        return {
          ticker: t.ticker,
          chainId: t.chainId,
          network: networkLabel[t.chainId],
          source: t.source,
          lab: !!t.lab,
          nav: !!t.nav,
          feed: feed?.feed ?? null,
          multiplier: m !== null ? Number(formatUnits(m, 18)) : null,
          price: quote && quote.answer > 0n ? Number(formatUnits(quote.answer, 8)) : null,
          status: !feed ? "Not deployed" : quote ? (FEED_STATUS[quote.status] ?? "No data") : "No data",
        };
      }),
    )
  ).filter((r): r is FeedRow => r !== null);

  const [usdg, crwdQuote, counts] = await Promise.all([
    settle(client(4663).readContract({ address: USDG_USD, abi: aggregatorAbi, functionName: "latestRoundData" })),
    robinhoodQuote("CRWD"),
    coverage(),
  ]);
  const crwdRow = rows[0];
  const live = crwdRow.price !== null;
  const testnetContracts = dep.networks["46630"]?.contracts ?? {};

  return {
    rows,
    crwd: {
      multiplier: crwdRow.multiplier,
      // Until CRWD's SlateFeed is deployed these are the fork-test figures: $264.98 signed share price × 4.
      sharePrice: live && crwdRow.multiplier ? crwdRow.price! / crwdRow.multiplier : 264.98,
      tokenPrice: live ? crwdRow.price! : 1059.92,
      snapshot: !live,
      feed: crwdRow.feed,
      robinhood: crwdQuote,
    },
    testnet: {
      contracts: testnetContracts,
      explorer: dep.networks["46630"]?.explorer ?? "https://explorer.testnet.chain.robinhood.com",
      constituents: ["TSLA", "AMZN", "AMD", "PLTR", "NFLX"]
        .map((s) => feedOf(s, 46630))
        .filter((f): f is NonNullable<typeof f> => !!f)
        .map((f) => ({ symbol: f.symbol, token: f.token, feed: f.feed })),
      labFeed: feedOf("labTSLA", 46630)?.feed ?? null,
    },
    mainnet: {
      contracts: dep.networks["4663"]?.contracts ?? {},
      aaplUsdg: dep.networks["4663"]?.contracts?.["SlateQuotedFeed AAPL/USDG"] ?? null,
    },
    usdgUsd: usdg && usdg[1] > 0n ? Number(formatUnits(usdg[1], 8)) : null,
    coverage: counts,
    feedsLive: rows.filter((r) => r.feed).length,
    readAt: new Date().toISOString(),
  };
}
