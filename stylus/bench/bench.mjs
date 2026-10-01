// Differential test and gas benchmark for the two IReportVerifier implementations.
//
// Calls the Stylus (Rust) verifier and the Solidity reference verifier, deployed on the same chain, with the
// same reports, and requires identical results: return values for valid reports, revert data for invalid ones.
// Then estimates gas for both at 1, 3, 5 and 7 signers. Writes results.json and prints a markdown table.
//
//   RPC_URL=https://rpc.testnet.chain.robinhood.com STYLUS=0x… SOLIDITY=0x… CASES=300 node bench.mjs

import { writeFileSync } from 'node:fs';
import {
  createPublicClient,
  http,
  keccak256,
  encodeAbiParameters,
  concatHex,
  toHex,
  hexToBigInt,
  numberToHex,
  BaseError,
} from 'viem';
import { generatePrivateKey, privateKeyToAccount, sign } from 'viem/accounts';

const RPC_URL = process.env.RPC_URL ?? 'https://rpc.testnet.chain.robinhood.com';
const STYLUS = process.env.STYLUS;
const SOLIDITY = process.env.SOLIDITY;
const CASES = Number(process.env.CASES ?? 300);
if (!STYLUS || !SOLIDITY) throw new Error('set STYLUS and SOLIDITY');

const TYPEHASH = keccak256(toHex('Observation(bytes32 feedId,int192 price,uint64 observedAt)'));
const N_HALF = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0n;
const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
const INT192_MAX = (1n << 191n) - 1n;

const abi = [
  {
    type: 'function',
    name: 'verify',
    stateMutability: 'view',
    inputs: [
      { name: 'domainSeparator', type: 'bytes32' },
      { name: 'feedId', type: 'bytes32' },
      { name: 'report', type: 'bytes' },
    ],
    outputs: [
      { name: 'signers', type: 'address[]' },
      { name: 'medianPrice', type: 'int256' },
      { name: 'minPrice', type: 'int256' },
      { name: 'maxPrice', type: 'int256' },
      { name: 'medianObservedAt', type: 'uint64' },
      { name: 'maxObservedAt', type: 'uint64' },
    ],
  },
];

const client = createPublicClient({ transport: http(RPC_URL, { retryCount: 5, retryDelay: 400 }) });

// Deterministic PRNG so a run can be reproduced from its seed.
let seed = BigInt(process.env.SEED ?? Date.now());
const rand = () => {
  seed = (seed * 6364136223846793005n + 1442695040888963407n) & ((1n << 64n) - 1n);
  return seed;
};
const randBelow = (n) => rand() % n;
const randPrice = () => {
  const mode = randBelow(4n);
  const mag = mode === 0n ? randBelow(INT192_MAX) : mode === 1n ? randBelow(10n ** 14n) + 1n : randBelow(10n ** 30n);
  return randBelow(5n) === 0n ? -mag : mag;
};

const randomSigners = (count) => {
  const accounts = Array.from({ length: count }, () => {
    const key = generatePrivateKey();
    return { key, address: privateKeyToAccount(key).address };
  });
  return accounts.sort((a, b) => (BigInt(a.address) < BigInt(b.address) ? -1 : 1));
};

const digestFor = (domain, feedId, price, observedAt) => {
  const structHash = keccak256(
    encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'bytes32' }, { type: 'int192' }, { type: 'uint64' }],
      [TYPEHASH, feedId, price, observedAt],
    ),
  );
  return keccak256(concatHex(['0x1901', domain, structHash]));
};

const int192Bytes = (price) => numberToHex(BigInt.asUintN(192, price), { size: 24 });

const entry = async (domain, feedId, signer, price, observedAt, tamper) => {
  const sig = await sign({ hash: digestFor(domain, feedId, price, observedAt), privateKey: signer.key });
  let { r, s, v } = sig;
  let vv = Number(v);
  if (tamper === 'highS') {
    s = numberToHex(N - hexToBigInt(s), { size: 32 });
    vv = vv === 27 ? 28 : 27;
  }
  if (tamper === 'badV') vv = 29;
  return concatHex([int192Bytes(price), numberToHex(observedAt, { size: 8 }), r, s, numberToHex(vv, { size: 1 })]);
};

const call = async (address, args) => {
  try {
    const result = await client.readContract({ address, abi, functionName: 'verify', args });
    return { ok: true, value: JSON.stringify(result, (_, x) => (typeof x === 'bigint' ? x.toString() : x)) };
  } catch (e) {
    const data = e instanceof BaseError ? e.walk((x) => x?.data)?.data ?? e.walk((x) => x?.raw)?.raw : undefined;
    return { ok: false, value: typeof data === 'string' ? data : `unparsed: ${e.shortMessage ?? e.message}` };
  }
};

const compare = async (label, args, failures) => {
  const [a, b] = await Promise.all([call(STYLUS, args), call(SOLIDITY, args)]);
  if (a.ok !== b.ok || a.value !== b.value) failures.push({ label, stylus: a, solidity: b, args });
  return a;
};

const main = async () => {
  const startSeed = seed;
  const domain = keccak256(toHex('slate-bench-domain'));
  const feedId = keccak256(toHex('CRWD/USD'));
  const failures = [];

  // Valid reports.
  for (let c = 0; c < CASES; c++) {
    const n = Number(randBelow(7n)) + 1;
    const signers = randomSigners(n);
    const parts = [];
    for (const s of signers) parts.push(await entry(domain, feedId, s, randPrice(), randBelow(1n << 63n)));
    await compare(`valid#${c} n=${n}`, [domain, feedId, concatHex(parts)], failures);
  }

  // Invalid reports.
  const two = randomSigners(2);
  const e0 = await entry(domain, feedId, two[0], 100n, 1n);
  const e1 = await entry(domain, feedId, two[1], 100n, 1n);
  const invalid = {
    empty: '0x',
    malformed: toHex(new Uint8Array(96)),
    highS: await entry(domain, feedId, two[0], 100n, 1n, 'highS'),
    badV: await entry(domain, feedId, two[0], 100n, 1n, 'badV'),
    unordered: concatHex([e1, e0]),
    duplicate: concatHex([e0, e0]),
    secondEntryHighS: concatHex([e0, await entry(domain, feedId, two[1], 100n, 1n, 'highS')]),
  };
  for (const [label, report] of Object.entries(invalid)) await compare(`invalid:${label}`, [domain, feedId, report], failures);

  // Gas.
  const gas = [];
  for (const n of [1, 3, 5, 7]) {
    const signers = randomSigners(n);
    const parts = [];
    for (const s of signers) parts.push(await entry(domain, feedId, s, 264_98000000n, 1_790_000_000n));
    const data = { abi, functionName: 'verify', args: [domain, feedId, concatHex(parts)] };
    const [st, so] = await Promise.all([
      client.estimateContractGas({ address: STYLUS, ...data }),
      client.estimateContractGas({ address: SOLIDITY, ...data }),
    ]);
    gas.push({ signers: n, stylus: Number(st), solidity: Number(so), saving: `${(100 * (1 - Number(st) / Number(so))).toFixed(1)}%` });
  }

  const result = {
    rpc: RPC_URL,
    stylus: STYLUS,
    solidity: SOLIDITY,
    seed: startSeed.toString(),
    validCases: CASES,
    invalidCases: Object.keys(invalid).length,
    mismatches: failures.length,
    failures: failures.slice(0, 10),
    gas,
    at: new Date().toISOString(),
  };
  writeFileSync(new URL('./results.json', import.meta.url), JSON.stringify(result, null, 2));

  console.log(`differential: ${CASES} valid + ${Object.keys(invalid).length} invalid reports, mismatches: ${failures.length}`);
  console.log('\n| Signers | Stylus gas | Solidity gas | Stylus saving |\n|---|---|---|---|');
  for (const g of gas) console.log(`| ${g.signers} | ${g.stylus} | ${g.solidity} | ${g.saving} |`);
  if (failures.length) {
    console.log('\nfirst mismatch:', JSON.stringify(failures[0], null, 2).slice(0, 2000));
    process.exitCode = 1;
  }
};

main();
