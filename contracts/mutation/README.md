# Mutation testing

Do the tests notice a bug? [Gambit](https://github.com/Certora/gambit) (Certora's open-source mutation generator) writes
one mutant per small change to a contract: a flipped comparison, a swapped operator, a deleted statement, a condition
forced true or false. `run.sh` runs the offline suite (unit, fuzz and invariant tests at the default profile) against
each mutant in a scratch copy of the project. A failing suite kills the mutant; a passing one means no test would notice
that bug.

```sh
cargo install --git https://github.com/Certora/gambit.git --locked
WORKERS=11 contracts/mutation/run.sh   # about 45 minutes on 12 cores
contracts/mutation/run.sh --one SignedSource 48   # one mutant: its change, then the tests that catch it
contracts/mutation/run.sh --summary               # the last run's results, per contract
```

## Results (4 Oct 2026, Gambit 0.2.1)

| Contract | Mutants | Killed, first run | Killed, after new tests | Survivors |
| --- | ---: | ---: | ---: | ---: |
| `SlateFeed` | 165 | 150 | 162 | 3, all equivalent |
| `SignedSource` | 107 | 103 | 105 | 2, all equivalent |
| `SolidityReportVerifier` (SignedSource's signature checks) | 202 | 180 | 202 | 0 |
| `MultiplierLens` (SlateFeed's multiplier reads) | 31 | 17 | 23 | 8, all equivalent |
| **Total** | **505** | **450 (89.1%)** | **492 (97.4%)** | **13, all equivalent** |

Eight of the kills are timeouts: a deleted or negated loop increment never terminates. They are counted as killed.

### What the first run found, and the tests added for it

- **The verifier's observation-time sort was never exercised.** Every report in the suite gave all signers the same
  timestamp, so deleting the sort, reversing it or reading the wrong element went unnoticed: 22 mutants. Added a fuzz
  test that checks the median and latest time against a reference for any order of signer times, and a test that one
  signer too far in the future fails the whole report.
- **A spread computed as `max % min` instead of `max − min` passed** (it reads zero when one signer reports exactly double).
  Added a test that signers a factor of two apart are refused.
- **`SlateFeed`'s handling of a falling multiplier was never checked inside the grace window.** Reverse-split mutants of
  the change measure survived. Added a 1:4 reverse split (held as a corporate action) and a 1% fall (stays exact).
- **No test covered:** a zero multiplier (must give no price, never a price of zero), a total-return price across a
  switch (must not be interrupted), a source with 2 decimals, an observation stamped at time 1, a zero `maxAge`, a zero
  verifier, and plain-ERC-20 and rebasing tokens reporting their multiplier. A test for each.

### The 13 survivors, and why no test can kill them

Each changes code without changing behaviour, so no input tells the mutant from the original.

- `SignedSource` #49, #107: `abs(a − b)` swapped to `abs(b − a)`.
- `SlateFeed` #35: `poke()`'s early return for non-ERC-8056 tokens removed. Those tokens report `effectiveAt` 0, so the
  next line returns false anyway.
- `SlateFeed` #89: `if (!known) return STRADDLE` removed. Unreachable: `known` is false only when the line above it has
  already returned `STRADDLE`. Kept as a guard.
- `SlateFeed` #127: the shortcut for 8-decimal sources removed. The general path multiplies by `10 ** 0`.
- `MultiplierLens` #8–10, #14–16: `pending` changed or unset for plain and rebasing tokens. Only `poke()` reads it, and
  only for ERC-8056 tokens.
- `MultiplierLens` #30, #31: the check that `oraclePaused()` returned a bool changed. The flag is only used as
  `supported && paused`, and `paused` is false for any value but 1.

`out/results.csv` (not committed) lists every mutant with its operator, line and status.
