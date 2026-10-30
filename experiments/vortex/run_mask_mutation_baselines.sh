#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RESEARCH_ROOT="${RESEARCH_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
VORTEX_ROOT="${VORTEX_ROOT:-}"
if [[ -z "$VORTEX_ROOT" ]]; then
  echo "Set VORTEX_ROOT to the Vortex source checkout" >&2
  exit 2
fi

BUILD="$VORTEX_ROOT/build"
APP="$BUILD/tests/regression/coverage_diverge/coverage_diverge"
OUT="${BASELINE_CSV:-$RESEARCH_ROOT/experiments/vortex/simx_baseline_equal_points.csv}"
FIXED_COUNT="${FIXED_COUNT:-8}"
SWEEP_COUNT="${SWEEP_COUNT:-16}"
SEEDED_COUNT="${SEEDED_COUNT:-16}"
SEEDED_SEED="${SEEDED_SEED:-1}"

for count in "$FIXED_COUNT" "$SWEEP_COUNT" "$SEEDED_COUNT"; do
  if [[ ! "$count" =~ ^[1-9][0-9]*$ ]]; then
    echo "workload counts must be positive integers" >&2
    exit 2
  fi
done
if [[ ! "$SEEDED_SEED" =~ ^[1-9][0-9]*$ ]]; then
  echo "SEEDED_SEED must be a positive integer" >&2
  exit 2
fi
test -x "$APP" || { echo "Missing executable: $APP" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
tmpdir="$(mktemp -d /tmp/vx-mask-baseline.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT
printf 'pattern,seed,points,depth,instructions,cycles,result\n' > "$OUT"

run_case() {
  local pattern="$1"
  local seed="$2"
  local count="$3"
  local log="$tmpdir/p${pattern}_s${seed}.log"
  local expected_points=$((count * 32))
  local -a args=(-n"$count" -d8 -p"$pattern")
  if [[ "$pattern" == 6 ]]; then
    args+=(-r"$seed")
  fi

  if ! (cd "$BUILD/tests/regression/coverage_diverge" &&
      LD_LIBRARY_PATH="$BUILD/sw/runtime" VORTEX_DRIVER=simx \
      "$APP" "${args[@]}") > "$log" 2>&1; then
    tail -30 "$log" >&2
    return 1
  fi
  grep -q '^PASSED!$' "$log" || {
    echo "Baseline did not pass: pattern=$pattern seed=$seed" >&2
    tail -30 "$log" >&2
    return 1
  }

  local points instructions cycles
  points="$(sed -n 's/^number of points: //p' "$log" | tail -1)"
  read -r instructions cycles < <(
    sed -n 's/.*instrs=\([0-9][0-9]*\).*cycles=\([0-9][0-9]*\).*/\1 \2/p' "$log" | tail -1
  )
  if [[ "$points" != "$expected_points" || -z "$instructions" || -z "$cycles" ]]; then
    echo "Baseline counters/workload did not match expectation: pattern=$pattern seed=$seed" >&2
    tail -30 "$log" >&2
    return 1
  fi
  printf '%s,%s,%s,8,%s,%s,PASSED\n' \
    "$pattern" "$seed" "$points" "$instructions" "$cycles" >> "$OUT"
  printf 'pattern=%s seed=%s points=%s instructions=%s cycles=%s PASSED\n' \
    "$pattern" "$seed" "$points" "$instructions" "$cycles"
}

run_case 0 0 "$FIXED_COUNT"
run_case 1 0 "$FIXED_COUNT"
run_case 2 0 "$SWEEP_COUNT"
run_case 6 "$SEEDED_SEED" "$SEEDED_COUNT"
echo "CSV: $OUT"
