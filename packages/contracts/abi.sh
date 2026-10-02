#!/usr/bin/env bash
# Regenerates abi/*.json. Run from the repository root. The package's interfaces are byte-identical to
# contracts/src/interfaces (CI checks), so their ABIs come from there (`forge inspect` rejects paths outside the project).
set -euo pipefail
for c in AggregatorV3Interface ISlateFeed IERC8056; do
  cmp "contracts/src/interfaces/$c.sol" "packages/contracts/src/interfaces/$c.sol"
  (cd contracts && forge inspect "src/interfaces/$c.sol:$c" abi --json) > "packages/contracts/abi/$c.json"
done
