# Stylus vs Solidity: the report verifier

**Result: on Robinhood Chain testnet the Stylus verifier costs more gas than the Solidity one at every signer count Slate uses. Slate ships the Solidity verifier.** The Stylus verifier is kept, deployed and tested, because the comparison is the point.

## What was compared

Both contracts implement the same interface, `IReportVerifier.verify(domainSeparator, feedId, report)`: decode a packed report of 97-byte entries, recover each EIP-712 signer through the ecrecover precompile, require low-s signatures and strictly ascending signers, then sort and take the median, minimum and maximum.

| | Address (Robinhood Chain testnet, 46630) |
|---|---|
| Stylus (Rust, `stylus/slate-verifier`), activated, `programVersion` 3 | `0x0819e35fd1ccccabb15a100dbb8315f04f1f093b` |
| Solidity (`contracts/src/sources/SolidityReportVerifier.sol`) | `0x1015EddD8776275446E23469c16F85E1ec6b5131` |

## Correctness: identical behaviour

`stylus/bench/bench.mjs` calls both contracts with the same inputs and requires identical output:

- **300 random valid reports**: 1 to 7 signers with real secp256k1 keys, prices across the full int192 range including negatives, random times. The return values must be equal.
- **7 invalid reports**: empty, malformed length, high-s, bad `v`, signers out of order, duplicate signer, high-s in the second entry. The revert data must be equal byte for byte.

Run on 1 Oct 2026 (seed `20261001`): **0 mismatches**.

## Gas (`eth_estimateGas`, same calldata to both)

| Signers | Stylus | Solidity | Stylus vs Solidity |
|---|---|---|---|
| 1 | 82,241 | 50,970 | +61.4% |
| 3 | 98,989 | 74,576 | +32.7% |
| 5 | 114,709 | 96,823 | +18.5% |
| 7 | 129,219 | 117,870 | +9.6% |

## Why

- **Fixed cost.** Each call to the Stylus program costs about 31k gas more before any work is done: program entry and memory setup for a 16 KB binary. Robinhood Chain testnet has **no Stylus CacheManager** (`cargo stylus cache status` reports no cache managers), so the program can't be cached to cut that cost.
- **Marginal cost.** Per extra signer, Stylus costs about 7.5k gas against about 11k for Solidity. Decoding, hashing and sorting are cheaper in Wasm, but the dominant per-signer cost, ecrecover, is the same precompile for both.
- **Crossover** is around 10 signers. Slate runs 2-of-3.

A size-optimised build (`opt-level = "z"`) only shrank the binary from 16.1 KB to 15.8 KB, which isn't enough to matter.

## Reproduce

```bash
cd stylus/bench && npm install
RPC_URL=https://rpc.testnet.chain.robinhood.com \
STYLUS=0x0819e35fd1ccccabb15a100dbb8315f04f1f093b \
SOLIDITY=0x1015EddD8776275446E23469c16F85E1ec6b5131 \
SEED=20261001 CASES=300 node bench.mjs
```

Deploying the Stylus program on Robinhood Chain testnet: the public RPC refuses the activation fee estimate, so `cargo stylus deploy` fails even with `--no-activate`. Instead, send the output of `cargo stylus get-initcode` as a plain creation transaction, then call `ArbWasm.activateProgram(address)` (precompile `0x…71`) with an explicit gas limit and about 0.0002 ETH; the excess is refunded.
