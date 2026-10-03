import { createServer } from "node:http";
import {
  BaseError,
  ContractFunctionRevertedError,
  createPublicClient,
  createWalletClient,
  http,
  maxUint256,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrum } from "viem/chains";
import { aggregatorAbi, calendarAbi, erc20Abi, erc8056Abi, seederAbi, signedSourceAbi, slateFeedAbi } from "./abi.ts";
import {
  ARBITRUM_RPC,
  CADENCE,
  PRESIGN,
  CROSS_CHECK_FEEDS,
  keys as loadKeys,
  loadManifest,
  networks as loadNetworks,
  POOL_SYMBOLS,
  robinhoodMainnet,
  settings,
  SIGNED_SYMBOLS,
  SYMBOL_CADENCE,
  type Keys,
  type Network,
} from "./config.ts";
import { board, updateBoard } from "./board.ts";
import { historyEnabled, readHistory, storeSnapshot } from "./history.ts";
import { COSIGNER_URLS, cosign } from "./cosigners.ts";
import { buildReport, feedId } from "./report.ts";
import { fetchQuote, quoteProblems, type Quote } from "./robinhood.ts";

const EXTENDED_SESSION = 1;
let boardBusy = false;
let lastSnapshotHour = 0;
const ONE = 10n ** 18n;

type FeedState = {
  chainId: number;
  symbol: string;
  lastPrice?: string;
  lastObservedAt?: number;
  lastTx?: Hex;
  skipped?: string;
  error?: string;
  at?: string;
};

const state = {
  startedAt: new Date().toISOString(),
  cycles: 0,
  lastCycleAt: "",
  relayer: "" as Address,
  marketOpen: {} as Record<number, boolean>,
  feeds: {} as Record<string, FeedState>,
  pools: {} as Record<string, { lastRecenterTx?: Hex; error?: string; at?: string }>,
  pokes: {} as Record<string, Hex>,
  /** Reports signed ahead of the mainnet deployment, newest last. See PRESIGN in config.ts. */
  presigned: [] as { symbol: string; feedId: Hex; price: string; observedAt: number; chainId: number; signedSource: Address; report: Hex }[],
};

function log(msg: string, extra?: unknown) {
  console.log(JSON.stringify({ t: new Date().toISOString(), msg, ...(extra ? { extra } : {}) }, (_, v) => (typeof v === "bigint" ? v.toString() : v)));
}

function reason(e: unknown): string {
  if (e instanceof BaseError) {
    const revert = e.walk((x) => x instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) return revert.data?.errorName ?? revert.shortMessage;
    return e.shortMessage;
  }
  return e instanceof Error ? e.message : String(e);
}

type Ctx = { net: Network; pub: PublicClient; wallet: WalletClient; keys: Keys };

const mainnetClient = createPublicClient({
  chain: robinhoodMainnet,
  transport: http(process.env.RH_MAINNET_RPC_URL ?? robinhoodMainnet.rpcUrls.default.http[0], { timeout: 10_000 }),
});
const arbitrumClient = createPublicClient({ chain: arbitrum, transport: http(ARBITRUM_RPC, { timeout: 10_000 }) });

// ------------------------------------------------------------------------------------------------
// Checks a quote must pass before any key signs it
// ------------------------------------------------------------------------------------------------

/** Robinhood's tokenBid ÷ bid must equal the token's on-chain multiplier on Robinhood Chain mainnet. */
async function multiplierProblem(q: Quote): Promise<string | null> {
  if (!q.mainnetToken || q.bid === 0n) return null;
  let onChain: bigint;
  try {
    onChain = await mainnetClient.readContract({ address: q.mainnetToken as Address, abi: erc8056Abi, functionName: "uiMultiplier" });
  } catch {
    return null; // the mainnet RPC being unreachable must not stop testnet prices; logged as unchecked
  }
  const implied = (q.tokenBid * ONE) / q.bid;
  const diff = implied > onChain ? implied - onChain : onChain - implied;
  if (diff * 10_000n > onChain * BigInt(settings.multiplierToleranceBps)) {
    return `tokenBid/bid ${implied} disagrees with on-chain uiMultiplier ${onChain}`;
  }
  return null;
}

/** Where Chainlink publishes the same share price (Arbitrum One), a fresh Chainlink answer must agree. */
async function crossCheckProblem(q: Quote, now: number): Promise<string | null> {
  const feed = CROSS_CHECK_FEEDS[q.symbol];
  if (!feed) return null;
  try {
    const [, answer, , updatedAt] = await arbitrumClient.readContract({ address: feed, abi: aggregatorAbi, functionName: "latestRoundData" });
    if (now - Number(updatedAt) > 2 * 3600 || answer <= 0n) return null; // Chainlink is not fresh: nothing to compare
    const diff = q.mid > answer ? q.mid - answer : answer - q.mid;
    if (diff * 10_000n > answer * BigInt(settings.crossCheckToleranceBps)) {
      return `Robinhood ${q.mid} vs Chainlink ${answer} on Arbitrum One`;
    }
  } catch {
    return null;
  }
  return null;
}

// ------------------------------------------------------------------------------------------------
// Publishing
// ------------------------------------------------------------------------------------------------

async function marketOpen(ctx: Ctx, now: number): Promise<boolean> {
  const closedSince = await ctx.pub.readContract({
    address: ctx.net.contracts.USMarketCalendar,
    abi: calendarAbi,
    functionName: "closedSince",
    args: [BigInt(now), EXTENDED_SESSION],
  });
  return closedSince === 0n;
}

async function publish(ctx: Ctx, symbol: string, quotes: Map<string, Promise<Quote>>, now: number) {
  const key = `${ctx.net.chain.id}:${symbol}`;
  const s: FeedState = (state.feeds[key] ??= { chainId: ctx.net.chain.id, symbol });
  s.at = new Date().toISOString();
  s.skipped = undefined;
  s.error = undefined;
  try {
    if (!quotes.has(symbol)) quotes.set(symbol, fetchQuote(symbol));
    const q = await quotes.get(symbol)!;
    const problems = quoteProblems(q, now);
    const mult = await multiplierProblem(q);
    if (mult) problems.push(mult);
    const cross = await crossCheckProblem(q, now);
    if (cross) problems.push(cross);
    if (problems.length) {
      s.skipped = problems.join("; ");
      log("refused to sign", { key, problems });
      return;
    }

    const id = feedId(symbol);
    const last = await ctx.pub.readContract({
      address: ctx.net.contracts.SignedSource,
      abi: signedSourceAbi,
      functionName: "observe",
      args: [id],
    });
    const lastAt = Number(last.observedAt);
    if (q.observedAt <= lastAt) {
      s.skipped = "no newer quote";
      return;
    }
    const moved = last.price > 0n ? ((q.mid > last.price ? q.mid - last.price : last.price - q.mid) * 10_000n) / last.price : 10_000n;
    const cadence = SYMBOL_CADENCE[ctx.net.chain.id]?.[symbol] ?? CADENCE[ctx.net.chain.id] ?? CADENCE[46630];
    if (moved < BigInt(cadence.deviationBps) && now - lastAt < cadence.heartbeat) {
      s.skipped = `within ${cadence.deviationBps} bps and ${cadence.heartbeat} s heartbeat`;
      return;
    }

    // Independent co-signers, if any are configured, add their own signed observations.
    const co = COSIGNER_URLS.length
      ? await cosign(COSIGNER_URLS, symbol, ctx.net.chain.id, ctx.net.contracts.SignedSource, q)
      : { entries: [], dropped: [] };
    if (co.dropped.length) log("co-signer entries dropped", { key, dropped: co.dropped });
    const report = await buildReport(
      ctx.keys.signers,
      ctx.net.chain.id,
      ctx.net.contracts.SignedSource,
      { feedId: id, price: q.mid, observedAt: BigInt(q.observedAt) },
      co.entries,
    );
    const { request } = await ctx.pub.simulateContract({
      account: ctx.wallet.account!,
      address: ctx.net.contracts.SignedSource,
      abi: signedSourceAbi,
      functionName: "submit",
      args: [id, report],
    });
    const hash = await ctx.wallet.writeContract(request);
    const receipt = await ctx.pub.waitForTransactionReceipt({ hash, timeout: 60_000 });
    if (receipt.status !== "success") throw new Error(`submit reverted: ${hash}`);
    s.lastPrice = (Number(q.mid) / 1e8).toFixed(4);
    s.lastObservedAt = q.observedAt;
    s.lastTx = hash;
    log("submitted", { key, price: s.lastPrice, observedAt: q.observedAt, moved: Number(moved), hash });
  } catch (e) {
    s.error = reason(e);
    log("publish failed", { key, error: s.error });
  }
}

/** Snapshots a staged ERC-8056 multiplier change into each feed while the old multiplier is still readable. */
async function pokeAll(ctx: Ctx, now: number) {
  for (const f of ctx.net.feeds) {
    try {
      const [current, next, effectiveAt] = await Promise.all([
        ctx.pub.readContract({ address: f.token, abi: erc8056Abi, functionName: "uiMultiplier" }),
        ctx.pub.readContract({ address: f.token, abi: erc8056Abi, functionName: "newUIMultiplier" }),
        ctx.pub.readContract({ address: f.token, abi: erc8056Abi, functionName: "effectiveAt" }),
      ]);
      if (current === next || BigInt(now) >= effectiveAt) continue;
      const { result, request } = await ctx.pub.simulateContract({
        account: ctx.wallet.account!,
        address: f.feed,
        abi: slateFeedAbi,
        functionName: "poke",
      });
      if (!result) continue; // already recorded
      const hash = await ctx.wallet.writeContract(request);
      await ctx.pub.waitForTransactionReceipt({ hash, timeout: 60_000 });
      state.pokes[`${ctx.net.chain.id}:${f.symbol}:${effectiveAt}`] = hash;
      log("poked", { chainId: ctx.net.chain.id, symbol: f.symbol, effectiveAt, hash });
    } catch {
      // not an ERC-8056 token (the basket), or a read failed; try again next time
    }
  }
}

// ------------------------------------------------------------------------------------------------
// Testnet market keeping
// ------------------------------------------------------------------------------------------------

function poolKeyFor(cash: Address, stock: Address) {
  const [currency0, currency1] = cash.toLowerCase() < stock.toLowerCase() ? [cash, stock] : [stock, cash];
  return { currency0, currency1, fee: 3000, tickSpacing: 60, hooks: "0x0000000000000000000000000000000000000000" as Address };
}

async function ensureAllowance(ctx: Ctx, token: Address, spender: Address) {
  const owner = ctx.wallet.account!.address;
  const allowance = await ctx.pub.readContract({ address: token, abi: erc20Abi, functionName: "allowance", args: [owner, spender] });
  if (allowance > maxUint256 / 2n) return;
  const hash = await ctx.wallet.writeContract({
    account: ctx.wallet.account!,
    chain: ctx.net.chain,
    address: token,
    abi: erc20Abi,
    functionName: "approve",
    args: [spender, maxUint256],
  });
  await ctx.pub.waitForTransactionReceipt({ hash, timeout: 60_000 });
  log("approved", { token, spender, hash });
}

/** Testnet pools have no arbitrageurs; the relayer is one. Swaps each pool back to its Slate price. */
async function keepPools(ctx: Ctx) {
  const seeder = ctx.net.contracts.SlateV4Seeder;
  const cash = ctx.net.contracts.SlateTestDollar;
  if (!seeder || !cash) return;
  for (const symbol of POOL_SYMBOLS) {
    const f = ctx.net.feeds.find((x) => x.symbol === symbol);
    if (!f) continue;
    const p = (state.pools[symbol] ??= {});
    p.at = new Date().toISOString();
    p.error = undefined;
    try {
      const key = poolKeyFor(cash, f.token);
      const [current, target] = await Promise.all([
        ctx.pub.readContract({ address: seeder, abi: seederAbi, functionName: "sqrtPriceOf", args: [key] }),
        ctx.pub.readContract({ address: seeder, abi: seederAbi, functionName: "targetSqrtPrice", args: [key, f.feed] }),
      ]);
      if (current === 0n) continue;
      const diff = current > target ? current - target : target - current;
      if (diff * 2n * 10_000n <= current * BigInt(settings.recenterBps)) continue;
      await ensureAllowance(ctx, cash, seeder);
      await ensureAllowance(ctx, f.token, seeder);
      const { request } = await ctx.pub.simulateContract({
        account: ctx.wallet.account!,
        address: seeder,
        abi: seederAbi,
        functionName: "recenter",
        args: [key, f.feed, BigInt(settings.recenterBps), maxUint256, maxUint256],
      });
      const hash = await ctx.wallet.writeContract(request);
      await ctx.pub.waitForTransactionReceipt({ hash, timeout: 60_000 });
      p.lastRecenterTx = hash;
      log("recentered", { symbol, hash });
    } catch (e) {
      p.error = reason(e);
      if (!/FeedUnavailable/.test(p.error)) log("recenter failed", { symbol, error: p.error });
    }
  }
}

// ------------------------------------------------------------------------------------------------
// Signing ahead of a deployment
// ------------------------------------------------------------------------------------------------

async function presign(keys: Keys, quotes: Map<string, Promise<Quote>>, now: number) {
  const queue = [...PRESIGN.symbols];
  await Promise.all(Array.from({ length: 5 }, () => presignWorker(queue, keys, quotes, now)));
}

async function presignWorker(queue: string[], keys: Keys, quotes: Map<string, Promise<Quote>>, now: number) {
  for (let symbol = queue.shift(); symbol; symbol = queue.shift()) {
    try {
      if (!quotes.has(symbol)) quotes.set(symbol, fetchQuote(symbol));
      const q = await quotes.get(symbol)!;
      const problems = quoteProblems(q, now);
      const mult = await multiplierProblem(q);
      if (mult) problems.push(mult);
      if (problems.length) {
        log("refused to presign", { symbol, problems });
        continue;
      }
      const last = state.presigned.filter((r) => r.symbol === symbol).at(-1);
      if (last && last.observedAt >= q.observedAt) continue;
      const id = feedId(symbol);
      const report = await buildReport(keys.signers, PRESIGN.chainId, PRESIGN.signedSource, {
        feedId: id,
        price: q.mid,
        observedAt: BigInt(q.observedAt),
      });
      state.presigned.push({
        symbol,
        feedId: id,
        price: (Number(q.mid) / 1e8).toFixed(4),
        observedAt: q.observedAt,
        chainId: PRESIGN.chainId,
        signedSource: PRESIGN.signedSource,
        report,
      });
      // Per symbol, keep the newest report and one per five minutes before it.
      const mine = state.presigned.filter((r) => r.symbol === symbol).reverse();
      const kept: typeof state.presigned = [];
      for (const r of mine) {
        if (kept.length === 0 || kept[kept.length - 1].observedAt - r.observedAt >= 300) kept.push(r);
        if (kept.length >= PRESIGN.keep) break;
      }
      state.presigned = [...state.presigned.filter((r) => r.symbol !== symbol), ...kept.reverse()];
    } catch (e) {
      log("presign failed", { symbol, error: reason(e) });
    }
  }
}

// ------------------------------------------------------------------------------------------------
// Loop
// ------------------------------------------------------------------------------------------------

async function cycle(keys: Keys) {
  const manifest = await loadManifest();
  const nets = loadNetworks(manifest);
  const now = Math.floor(Date.now() / 1000);
  const quotes = new Map<string, Promise<Quote>>();
  const relayer = privateKeyToAccount(keys.relayer);
  state.relayer = relayer.address;

  await Promise.all(
    nets.map(async (net) => {
      const transport = http(net.rpc, { timeout: 15_000, retryCount: 2 });
      const pub = createPublicClient({ chain: net.chain, transport }) as PublicClient;
      const wallet = createWalletClient({ account: relayer, chain: net.chain, transport });
      const ctx: Ctx = { net, pub, wallet, keys };
      try {
        const open = await marketOpen(ctx, now);
        state.marketOpen[net.chain.id] = open;
        // Outside the 24/5 session, Robinhood keeps serving Friday's prices with a fresh timestamp. Signing those
        // would make a closed market look live, so nothing is signed until the session reopens.
        if (open) {
          for (const symbol of SIGNED_SYMBOLS[net.chain.id] ?? []) {
            if (net.feeds.some((f) => f.symbol === symbol)) await publish(ctx, symbol, quotes, now);
          }
        }
        if (state.cycles % 4 === 0) await pokeAll(ctx, now);
        await keepPools(ctx);
      } catch (e) {
        log("network cycle failed", { chainId: net.chain.id, error: reason(e) });
      }
    }),
  );
  // Until mainnet's SignedSource exists, sign CRWD for it while the market is open (testnet's calendar says so).
  const mainnetDeployed = nets.some((n) => n.chain.id === PRESIGN.chainId);
  if (!mainnetDeployed && state.marketOpen[46630] && state.cycles % 4 === 2) await presign(keys, quotes, now);
  // The accuracy board, about once a minute, off the critical path: signed, never submitted. See board.ts.
  if (state.cycles % 4 === 0 && !boardBusy) {
    boardBusy = true;
    updateBoard({
      signers: keys.signers,
      now,
      marketOpen: !!state.marketOpen[46630],
      mainnet: mainnetClient as PublicClient,
      quote: (symbol) => {
        if (!quotes.has(symbol)) quotes.set(symbol, fetchQuote(symbol));
        return quotes.get(symbol)!;
      },
      multiplierProblem,
    })
      .then(async () => {
        // Once an hour, the board into Postgres (history.ts): the accuracy history the dashboard charts.
        const hour = Math.floor(now / 3600);
        if (!historyEnabled() || hour === lastSnapshotHour) return;
        lastSnapshotHour = hour;
        const stored = await storeSnapshot(Object.values(board.rows), mainnetClient as PublicClient, now);
        log("board snapshot", { stored });
      })
      .catch((e) => log("board update failed", { error: reason(e) }))
      .finally(() => (boardBusy = false));
  }

  state.cycles++;
  state.lastCycleAt = new Date().toISOString();
}

async function main() {
  const keys = loadKeys();
  const once = process.argv.includes("--once");
  if (once) {
    await cycle(keys);
    console.log(JSON.stringify(state, null, 2));
    return;
  }

  createServer(async (req, res) => {
    if (req.url?.startsWith("/history")) {
      try {
        const body = await readHistory();
        res.writeHead(200, { "content-type": "application/json", "access-control-allow-origin": "*", "cache-control": "public, max-age=300" });
        res.end(JSON.stringify(body));
      } catch (e) {
        res.writeHead(502, { "content-type": "application/json", "access-control-allow-origin": "*" });
        res.end(JSON.stringify({ collecting: true, error: reason(e) }));
      }
      return;
    }
    const stale = Date.now() - Date.parse(state.lastCycleAt || state.startedAt) > 5 * 60_000;
    res.writeHead(req.url === "/healthz" && stale ? 503 : 200, {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
    });
    res.end(JSON.stringify(req.url?.startsWith("/board") ? board : state, null, 2));
  }).listen(settings.port, () => log("status server", { port: settings.port }));

  for (;;) {
    const started = Date.now();
    try {
      await cycle(keys);
    } catch (e) {
      log("cycle failed", { error: reason(e) });
    }
    await new Promise((r) => setTimeout(r, Math.max(1_000, settings.interval * 1000 - (Date.now() - started))));
  }
}

await main();
