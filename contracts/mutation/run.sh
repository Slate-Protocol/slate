#!/usr/bin/env bash
# Mutation testing for SlateFeed, SignedSource and the two libraries they rely on.
#
# Gambit (Certora's open-source mutation generator, https://github.com/Certora/gambit) writes one mutant per small
# change: a flipped comparison, a swapped operator, a deleted statement, a condition forced true or false. Each mutant
# replaces its source file in a scratch copy of this project and the offline test suite runs against it (unit, fuzz
# and invariant tests at the default profile; fork tests need live RPCs and are excluded). A mutant the tests fail on is
# killed; one they pass on survived, meaning no test would notice that bug.
#
#   cargo install --git https://github.com/Certora/gambit.git --locked
#   contracts/mutation/run.sh            # all four files, 6 workers
#   contracts/mutation/run.sh SlateFeed  # one file
#   APPEND=1 IDS=1-100 contracts/mutation/run.sh SolidityReportVerifier   # a slice, added to earlier results
#   APPEND=1 IDS=2,48 contracts/mutation/run.sh SignedSource              # re-run survivors after adding tests
#   contracts/mutation/run.sh --one SignedSource 48   # one mutant: its change, then the tests that catch it
#   contracts/mutation/run.sh --summary               # the last run's results, per contract
#
# Output: contracts/mutation/out/results.csv (file,id,operator,line,status) and a summary on stdout.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"           # contracts/
OUT="$HERE/out"
WORKERS="${WORKERS:-6}"
SOLC="${SOLC:-$(ls "$HOME/Library/Application Support/svm/0.8.30/solc-0.8.30" "$HOME/.svm/0.8.30/solc-0.8.30" 2>/dev/null | head -1 || true)}"
[ -x "$SOLC" ] || { echo "solc 0.8.30 not found; run forge build once or set SOLC" >&2; exit 1; }

generate() { # <path under src/ without .sol>
  rm -rf "$OUT/$(basename "$1")"
  (cd "$ROOT" && gambit mutate --filename "src/$1.sol" --solc "$SOLC" --solc_optimize \
    --solc_remappings forge-std/=lib/forge-std/src/ @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ \
    --outdir "$OUT/$(basename "$1")" >/dev/null)
}

scratch() { # <dir>: a copy of the project whose sources a mutant may overwrite
  mkdir -p "$1/contracts"
  cp -R "$ROOT/src" "$ROOT/test" "$ROOT/script" "$ROOT/foundry.toml" "$ROOT/remappings.txt" "$1/contracts/"
  ln -s "$ROOT/lib" "$1/contracts/lib"
  ln -s "$ROOT/../packages" "$1/packages"
  ln -s "$ROOT/../deployments" "$1/deployments"
}

summarize() { # [compact]: join results with Gambit's description of each mutant, write results.csv, print the summary
  node -e '
const fs = require("fs"), [out, mode] = process.argv.slice(1);
const meta = {};
for (const n of fs.readdirSync(out).filter((d) => fs.existsSync(`${out}/${d}/gambit_results.json`)))
  for (const m of JSON.parse(fs.readFileSync(`${out}/${n}/gambit_results.json`))) {
    const line = /@@ -(\d+)/.exec(m.diff)?.[1];
    const changed = m.diff.split("\n").find((l) => l.startsWith("+") && !l.startsWith("+++") && !l.includes("///"))?.slice(1).trim();
    meta[`${n},${m.id}`] = { op: m.description, line: Number(line) + 3, changed };
  }
const latest = new Map(fs.readFileSync(`${out}/results-raw.csv`, "utf8").trim().split("\n").map((r) => [r.split(",").slice(0, 2).join(","), r]));
const rows = [...latest.values()]
  .map((r) => { const [n, id, status] = r.split(","); return { n, id: Number(id), status, ...meta[`${n},${id}`] }; })
  .sort((a, b) => a.n.localeCompare(b.n) || a.id - b.id);
fs.writeFileSync(`${out}/results.csv`, "file,id,operator,line,status,mutant\n" + rows.map((r) => [r.n, r.id, r.op, r.line, r.status, JSON.stringify(r.changed ?? "")].join(",")).join("\n") + "\n");
const by = {};
for (const r of rows) { by[r.n] ??= { total: 0, killed: 0, survivors: [] }; by[r.n].total++; r.status.startsWith("killed") ? by[r.n].killed++ : by[r.n].survivors.push(r); }
let T = 0, K = 0;
const pct = (k, t) => ((100 * k) / t).toFixed(1).padStart(5) + "%";
for (const [n, s] of Object.entries(by)) {
  T += s.total; K += s.killed;
  if (mode === "compact") console.log(`${n.padEnd(23)}${`${s.killed}/${s.total}`.padStart(8)} ${pct(s.killed, s.total)}`);
  else {
    console.log(`${n}: ${s.killed}/${s.total} killed (${((100 * s.killed) / s.total).toFixed(1)}%)`);
    for (const r of s.survivors) console.log(`  survived #${r.id} line ${r.line} ${r.op}: ${r.changed}`);
  }
}
if (mode === "compact") console.log(`${"killed".padEnd(23)}${`${K}/${T}`.padStart(8)} ${pct(K, T)}`);
else console.log(`total: ${K}/${T} killed (${((100 * K) / T).toFixed(1)}%)`);
' "$OUT" "${1:-}"
}

if [ "${1:-}" = "--summary" ]; then
  summarize compact
  exit
fi

if [ "${1:-}" = "--one" ]; then
  n="$2"; id="$3"
  f="$(cd "$ROOT/src" && ls */"$n".sol | sed 's/\.sol$//')"
  [ -f "$OUT/$n/gambit_results.json" ] || generate "$f"
  # The changed source line, before and after, cut to a window around the change so it fits a terminal.
  desc="$(node -e 'const m = JSON.parse(require("fs").readFileSync(process.argv[1])).find((x) => x.id === process.argv[2]);
    const d = m.diff.split("\n"), line = Number(/@@ -(\d+)/.exec(m.diff)[1]) + 3;
    const a = d.find((l) => l.startsWith("-") && !l.startsWith("---")).slice(1).trim();
    const b = d.find((l) => l.startsWith("+") && !l.startsWith("+++") && !l.includes("///")).slice(1).trim();
    let i = 0; while (i < a.length && a[i] === b[i]) i++;
    const W = 44, s = a.lastIndexOf(" ", Math.max(0, i - 10)) + 1; // start on a word
    const cut = (x) => (s > 0 ? "…" : "") + x.slice(s, s + W) + (x.length > s + W ? "…" : "");
    console.log(`mutant ${process.argv[3]} #${m.id}, line ${line}\n- ${cut(a)}\n+ ${cut(b)}`);' "$OUT/$n/gambit_results.json" "$id" "$n")"
  echo "$desc"
  WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
  scratch "$WORK"
  cp "$OUT/$n/mutants/$id/src/$f.sol" "$WORK/contracts/src/$f.sol"
  echo "running the suite against it..."
  log="$WORK/test.log"
  if (cd "$WORK/contracts" && forge test --match-path 'test/{unit,invariant}/*' --color never > "$log" 2>&1); then
    echo "survived: every test passed"
  else
    grep -o '^\[FAIL[^]]*\] [A-Za-z0-9_]*' "$log" | sed 's/^\[FAIL[^]]*\] /FAIL /' | sort -u
    grep -o '[0-9]* tests passed, [0-9]* failed' "$log" | tail -1 | awk '{print "killed: " $4 " of " $1 + $4 " tests failed"}'
  fi
  exit
fi

FILES=(feeds/SlateFeed sources/SignedSource libraries/MultiplierLens sources/SolidityReportVerifier)
if [ $# -gt 0 ]; then FILES=(); for n in "$@"; do FILES+=("$(cd "$ROOT/src" && ls */"$n".sol | sed 's/\.sol$//')"); done; fi

[ -n "${APPEND:-}" ] || rm -rf "$OUT"; mkdir -p "$OUT"
for f in "${FILES[@]}"; do generate "$f"; done

# Scratch copies, one per worker, so mutants never touch the real sources.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for w in $(seq 1 "$WORKERS"); do
  scratch "$WORK/$w"
  (cd "$WORK/$w/contracts" && forge build -q)
done

# One job per mutant: "<file> <id> <path inside contracts/>".
JOBS="$OUT/jobs.txt"; : > "$JOBS"
for f in "${FILES[@]}"; do
  n="$(basename "$f")"
  for d in "$OUT/$n"/mutants/*; do
    id="$(basename "$d")"
    if [ -n "${IDS:-}" ]; then
      case "$IDS" in
        *-*) { [ "$id" -lt "${IDS%-*}" ] || [ "$id" -gt "${IDS#*-}" ]; } && continue ;;
        *) case ",$IDS," in *",$id,"*) ;; *) continue ;; esac ;;
      esac
    fi
    echo "$n $id src/$f.sol" >> "$JOBS"
  done
done

run_worker() {
  local w="$1" dir="$WORK/$1/contracts"
  awk -v w="$w" -v n="$WORKERS" 'NR % n == w % n' "$JOBS" | while read -r n id path; do
    cp "$OUT/$n/mutants/$id/$path" "$dir/$path"
    local status
    if (cd "$dir" && perl -e 'alarm shift; exec @ARGV' 300 forge test --match-path 'test/{unit,invariant}/*' >/dev/null 2>&1); then status=survived
    else
      case $? in 142) status=killed_timeout ;; *) status=killed ;; esac
    fi
    cp "$ROOT/$path" "$dir/$path"
    echo "$n,$id,$status" >> "$OUT/results-raw.csv"
  done
}
export -f run_worker; export WORK OUT JOBS WORKERS ROOT
for w in $(seq 1 "$WORKERS"); do run_worker "$w" & done
wait

summarize
