import "server-only";
import { BaseError, ContractFunctionRevertedError, formatUnits, type Address } from "viem";
import { aggregatorAbi, slateFeedAbi } from "./abi";
import { client, type ChainId } from "./chains";
import { deployments } from "./data";
import { FEED_STATUS } from "./status";

const NETWORKS: Record<string, ChainId> = { mainnet: 4663, testnet: 46630 };

/** Every Slate feed in deployments.json on one network. */
export async function listFeeds(network: "mainnet" | "testnet") {
  const dep = await deployments();
  return dep.feeds.filter((f) => f.chainId === NETWORKS[network]).map((f) => ({ symbol: f.symbol, feed: f.feed as Address, token: f.token as Address }));
}

/**
 * One feed, read from the chain now: SlateFeed.latestDetail() (which never reverts, so it can say why there is no
 * price) and whether latestRoundData(), the call a lending market makes, serves that price or reverts.
 */
export async function readPrice(symbol: string, network: "mainnet" | "testnet") {
  const chainId = NETWORKS[network];
  const dep = await deployments();
  const f = dep.feeds.find((x) => x.chainId === chainId && x.symbol.toUpperCase() === symbol.toUpperCase());
  if (!f) return null;
  const c = client(chainId);
  const explorer = dep.networks[String(chainId)]?.explorer;
  const [block, detail, round] = await Promise.all([
    c.getBlockNumber(),
    c.readContract({ address: f.feed as Address, abi: slateFeedAbi, functionName: "latestDetail" }),
    c.readContract({ address: f.feed as Address, abi: aggregatorAbi, functionName: "latestRoundData" }).then(
      () => ({ serves: true as const, reason: null }),
      (e: unknown) => {
        const revert = e instanceof BaseError ? e.walk((x) => x instanceof ContractFunctionRevertedError) : null;
        return { serves: false as const, reason: revert instanceof ContractFunctionRevertedError ? (revert.data?.errorName ?? "reverted") : "reverted" };
      },
    ),
  ]);
  const [quote, sharePrice, multiplier] = detail;
  const status = FEED_STATUS[quote.status] ?? `Unknown (${quote.status})`;
  const now = Math.floor(Date.now() / 1000);
  const observedAt = Number(quote.observedAt);
  return {
    symbol: f.symbol,
    network: chainId === 4663 ? "Robinhood Chain" : "Robinhood Chain testnet",
    chainId,
    status,
    servesLatestRoundData: round.serves,
    ...(round.reason ? { latestRoundDataReverts: round.reason } : {}),
    price: quote.answer > 0n ? Number(formatUnits(quote.answer, 8)) : null,
    sharePrice: sharePrice > 0n ? Number(formatUnits(sharePrice, 8)) : null,
    multiplier: Number(formatUnits(multiplier, 18)),
    observedAt: observedAt || null,
    observedAtIso: observedAt ? new Date(observedAt * 1000).toISOString() : null,
    ageSeconds: observedAt ? now - observedAt : null,
    decimals: 8,
    answerRaw: quote.answer.toString(),
    feed: f.feed,
    token: f.token,
    explorer: explorer ? { feed: `${explorer}/address/${f.feed}`, token: `${explorer}/address/${f.token}` } : null,
    block: Number(block),
    readAt: new Date(now * 1000).toISOString(),
    docs: "https://docs.slate.0xo.in/api",
  };
}
