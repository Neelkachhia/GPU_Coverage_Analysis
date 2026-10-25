#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/projects/vortex"
RESEARCH="$HOME/projects/research"
ALT="$ROOT/build-threads8b"
CFG="$ROOT/VX_config.toml"
OUT="$RESEARCH/experiments/vortex/pattern3_8lane_results.csv"
SITES="$RESEARCH/experiments/vortex/pattern3_8lane_sites.csv"
TMP="$(mktemp -d /tmp/vx-pattern3-8lane.XXXXXX)"
cp "$CFG" "$TMP/VX_config.toml"
restore() {
  cp "$TMP/VX_config.toml" "$CFG"
  rm -rf "$TMP"
}
trap restore EXIT INT TERM

if ! grep -q '^VX_CFG_NUM_THREADS = 4$' "$CFG"; then
  echo "Expected source VX_config.toml to start at four threads" >&2
  exit 2
fi
sed -i 's/^VX_CFG_NUM_THREADS = 4$/VX_CFG_NUM_THREADS = 8/' "$CFG"

cp "$RESEARCH/experiments/vortex/coverage_diverge/"{Makefile,common.h,kernel.cpp,main.cpp} \
   "$ROOT/tests/regression/coverage_diverge/"
mkdir -p "$ALT"
(
  cd "$ALT"
  "$ROOT/configure" --tooldir="$HOME/tools"
)
grep -q '#define VX_CFG_NUM_THREADS 8' "$ALT/sw/VX_config.h"
grep -q 'VX_CFG_NUM_THREADS 8' "$ALT/hw/VX_config.vh"

printf 'simulator,pattern,threads,points,instructions,total_branches,divergent_events,cycles,result\n' > "$OUT"
for driver in simx rtlsim; do
  log="$TMP/$driver.log"
  if [[ "$driver" == simx ]]; then
    VX_SIMX_SPLIT_TRACE=1 "$ALT/ci/blackbox.sh" --driver="$driver" --cores=2 \
      --app=coverage_diverge --perf=1 --args="-n32 -d8 -p3" > "$log" 2>&1
  else
    "$ALT/ci/blackbox.sh" --driver="$driver" --cores=2 \
      --app=coverage_diverge --perf=1 --args="-n32 -d8 -p3" > "$log" 2>&1
  fi

  points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
  instr="$(sed -n 's/^PERF: instrs=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
  cycles="$(sed -n 's/^PERF: instrs=.*cycles=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
  branches="$(sed -n 's/^PERF: branches: total=\([0-9][0-9]*\), divergent=.*/\1/p' "$log" | tail -1)"
  divergent="$(sed -n 's/^PERF: branches: total=[0-9][0-9]*, divergent=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"

  if [[ "$points" != 2048 || "$instr" != 59680 || "$branches" != 9216 || "$divergent" != 1792 ]] ||
     ! grep -q 'PASSED!' "$log"; then
    echo "$driver pattern-3 run did not match the validated workload/counters" >&2
    grep -E '^number of points:|^PERF: branches:|^PERF: instrs=|FAILED!|PASSED!|error at result' "$log" >&2 || true
    exit 1
  fi
  printf '%s,3,8,%s,%s,%s,%s,%s,PASSED\n' \
    "$driver" "$points" "$instr" "$branches" "$divergent" "$cycles" >> "$OUT"
  grep -E '^PERF: branches:|^PERF: instrs=|PASSED!' "$log"
done

awk '
/^COV_SPLIT / {
  pc=$2
  pair=$6 "/" $7
  pairs[pc SUBSEP pair]=1
  events[pc]++
  pcs[pc]=1
}
END {
  for (key in pairs) {
    split(key, fields, SUBSEP)
    unique[fields[1]]++
  }
  pc_count=0
  for (pc in pcs) {
    pc_count++
    if (events[pc] != 256 || unique[pc] != 254) {
      printf "Unexpected coverage at %s: events=%d pairs=%d\n", pc, events[pc], unique[pc] > "/dev/stderr"
      failed=1
    }
    printf "%s,%d,%d\n", pc, events[pc], unique[pc]
  }
  if (pc_count != 7 || failed) exit 1
}' "$TMP/simx.log" > "$TMP/sites.csv"
{
  printf 'split_pc,events,distinct_mask_pairs\n'
  sort "$TMP/sites.csv"
} > "$SITES"

echo "Results: $OUT"
cat "$OUT"
echo "Per-site mask counts: $SITES"
cat "$SITES"
