#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/projects/vortex"
RESEARCH="$HOME/projects/research"
ALT="$ROOT/build-threads16"
CFG="$ROOT/VX_config.toml"
OUT="$RESEARCH/experiments/vortex/pattern4_16lane_results.csv"
SITES="$RESEARCH/experiments/vortex/pattern4_16lane_sites.csv"
TMP="$(mktemp -d /tmp/vx-pattern4-16lane.XXXXXX)"
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
sed -i 's/^VX_CFG_NUM_THREADS = 4$/VX_CFG_NUM_THREADS = 16/' "$CFG"
cp "$RESEARCH/experiments/vortex/coverage_diverge/"{Makefile,common.h,kernel.cpp,main.cpp} \
   "$ROOT/tests/regression/coverage_diverge/"
mkdir -p "$ALT"
(
  cd "$ALT"
  "$ROOT/configure" --tooldir="$HOME/tools"
)
grep -q '#define VX_CFG_NUM_THREADS 16' "$ALT/sw/VX_config.h"
grep -q 'VX_CFG_NUM_THREADS 16' "$ALT/hw/VX_config.vh"
log="$TMP/simx.log"
printf 'simulator,pattern,threads,points,instructions,total_branches,divergent_events,cycles,result\n' > "$OUT"
VX_SIMX_SPLIT_TRACE=1 "$ALT/ci/blackbox.sh" --driver=simx --cores=2 \
  --app=coverage_diverge --perf=1 --args="-n8192 -d8 -p4" > "$log" 2>&1
points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
instr="$(sed -n 's/^PERF: instrs=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
cycles="$(sed -n 's/^PERF: instrs=.*cycles=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
branches="$(sed -n 's/^PERF: branches: total=\([0-9][0-9]*\), divergent=.*/\1/p' "$log" | tail -1)"
divergent="$(sed -n 's/^PERF: branches: total=[0-9][0-9]*, divergent=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
if [[ "$points" != 1048576 || "$divergent" != 458752 ]] || ! grep -q 'PASSED!' "$log"; then
  echo "SIMX pattern-4 run did not match expected workload/counters" >&2
  grep -E '^number of points:|^PERF: branches:|^PERF: instrs=|FAILED!|PASSED!|error at result' "$log" >&2 || true
  exit 1
fi
printf 'simx,4,16,%s,%s,%s,%s,%s,PASSED\n' \
  "$points" "$instr" "$branches" "$divergent" "$cycles" >> "$OUT"
grep -E '^PERF: branches:|^PERF: instrs=|PASSED!' "$log"
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
    if (events[pc] != 65536 || unique[pc] != 65534) {
      printf "Unexpected coverage at %s: events=%d pairs=%d\n", pc, events[pc], unique[pc] > "/dev/stderr"
      failed=1
    }
    printf "%s,%d,%d\n", pc, events[pc], unique[pc]
  }
  if (pc_count != 7 || failed) exit 1
}' "$log" > "$TMP/sites.csv"
{
  printf 'split_pc,events,distinct_mask_pairs\n'
  sort "$TMP/sites.csv"
} > "$SITES"
# Cross-check the same 16-thread kernel and host reference on RTLSIM with
# 32 warp groups. Full mask enumeration remains the SIMX run above.
rtlog="$TMP/rtlsim-smoke.log"
"$ALT/ci/blackbox.sh" --driver=rtlsim --cores=2 \
  --app=coverage_diverge --perf=1 --args="-n16 -d8 -p4" > "$rtlog" 2>&1
rt_points="$(sed -n 's/^number of points: //p' "$rtlog" | head -1)"
rt_instr="$(sed -n 's/^PERF: instrs=\([0-9][0-9]*\).*/\1/p' "$rtlog" | tail -1)"
rt_cycles="$(sed -n 's/^PERF: instrs=.*cycles=\([0-9][0-9]*\).*/\1/p' "$rtlog" | tail -1)"
rt_branches="$(sed -n 's/^PERF: branches: total=\([0-9][0-9]*\), divergent=.*/\1/p' "$rtlog" | tail -1)"
rt_divergent="$(sed -n 's/^PERF: branches: total=[0-9][0-9]*, divergent=\([0-9][0-9]*\).*/\1/p' "$rtlog" | tail -1)"
if [[ ! "$rt_points" =~ ^[0-9]+$ ]] || (( rt_points == 0 || rt_points % 16 != 0 )); then
  echo "RTLSIM returned an invalid point count: $rt_points" >&2
  exit 1
fi
expected_rt_divergent=$((7 * rt_points / 16))
if [[ "$rt_divergent" != "$expected_rt_divergent" ]] || ! grep -q 'PASSED!' "$rtlog"; then
  echo "RTLSIM 16-thread smoke run failed its workload/reference checks" >&2
  grep -E '^number of points:|^PERF: branches:|^PERF: instrs=|FAILED!|PASSED!|error at result' "$rtlog" >&2 || true
  exit 1
fi
printf 'rtlsim,4,16,%s,%s,%s,%s,%s,PASSED\n' \
  "$rt_points" "$rt_instr" "$rt_branches" "$rt_divergent" "$rt_cycles" >> "$OUT"
grep -E '^PERF: branches:|^PERF: instrs=|PASSED!' "$rtlog"

echo "Results: $OUT"
cat "$OUT"
echo "Per-site mask counts: $SITES"
cat "$SITES"
