---
title: Stylus benchmark
description: We built the report verifier in Rust on Stylus, measured it against Solidity, and Rust lost.
---

**Result: on Robinhood Chain testnet the Stylus verifier costs more gas than the Solidity one at every signer count Slate uses, so Slate ships the Solidity verifier.** We kept the Rust verifier deployed and tested, and we publish the numbers, because the comparison is the point.

## What was compared

Both contracts implement `IReportVerifier.verify(domainSeparator, feedId, report)`. Each one decodes 97-byte entries, recovers every EIP-712 signer through the ecrecover precompile, requires low-s signatures and strictly ascending signers, then sorts and takes the median, minimum and maximum.

| | Robinhood Chain testnet |
|---|---|
| Stylus (Rust, `stylus/slate-verifier`), activated | `0x0819e35fd1ccccabb15a100dbb8315f04f1f093b` |
| Solidity (`SolidityReportVerifier`) | `0x1015EddD8776275446E23469c16F85E1ec6b5131` |

## Same behaviour

A live differential run compared 300 random valid reports (1 to 7 signers, prices across the full int192 range) and 7 malformed ones (empty, bad length, high-s, bad `v`, out of order, duplicate signer). It required identical return values and byte-identical revert data. The result was **0 mismatches**.

## Gas

| Signers | Stylus | Solidity | Stylus vs Solidity |
|---|---|---|---|
| 1 | 82,241 | 50,970 | +61.4% |
| 3 | 98,989 | 74,576 | **+32.7%** |
| 5 | 114,709 | 96,823 | +18.5% |
| 7 | 129,219 | 117,870 | +9.6% |

## Why Rust lost here

- **Fixed cost.** Each call into the Stylus program costs about 31,000 gas before any work starts: program entry and memory setup for a 16 KB binary. Robinhood Chain testnet has no Stylus CacheManager, so the program cannot be cached to cut that cost.
- **Marginal cost.** Each extra signer costs Stylus about 7,500 gas against about 11,000 for Solidity. Decoding, hashing and sorting are cheaper in Wasm, but the dominant cost, ecrecover, is the same precompile for both.
- **Crossover** is around 10 signers. Slate runs 2 of 3.

Reproduce: `stylus/bench/bench.mjs` against the two addresses above. Full method in [`stylus/BENCHMARK.md`](https://github.com/Slate-Protocol/slate/blob/main/stylus/BENCHMARK.md).
