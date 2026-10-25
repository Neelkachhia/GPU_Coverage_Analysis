#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/projects/vortex"
ALT="$ROOT/build-threads8b"
CFG="$ROOT/VX_config.toml"
OUT="$HOME/projects/research/experiments/vortex/thread_count_crosscheck.csv"
TMP="$(mktemp -d /tmp/vx-threads8.XXXXXX)"
cp "$CFG" "$TMP/VX_config.toml"
restore() { cp "$TMP/VX_config.toml" "$CFG"; rm -rf "$TMP"; }
trap restore EXIT INT TERM
if [[ -e "$ALT" ]]; then
  echo "Alternate build directory already exists: $ALT" >&2
  exit 2
fi
if ! grep -q '^VX_CFG_NUM_THREADS = 4$' "$CFG"; then
  echo "Expected the source configuration to specify four threads" >&2
  exit 2
fi
sed -i 's/^VX_CFG_NUM_THREADS = 4$/VX_CFG_NUM_THREADS = 8/' "$CFG"
mkdir -p "$ALT"
(
  cd "$ALT"
  "$ROOT/configure" --tooldir="$HOME/tools"
)
grep -q 'VX_CFG_NUM_THREADS 8' "$ALT/hw/VX_config.vh" || {
  echo "alternate Verilog config did not resolve to 8 threads" >&2
  exit 1
}
grep -q '#define VX_CFG_NUM_THREADS 8' "$ALT/sw/VX_config.h" || {
  echo "alternate software config did not resolve to 8 threads" >&2
  exit 1
}
echo "Configured alternate build with 8 threads/warp at $ALT"

printf 'simulator,pattern,threads,points,instructions,total_branches,divergent_events,cycles,result\n' > "$OUT"
for driver in simx rtlsim; do
  for pattern in 0 2; do
    log="$TMP/$driver-p$pattern.log"
    set +e
    (
      cd "$ALT"
      timeout --kill-after=5 300 ./ci/blackbox.sh --driver="$driver" --cores=2 --app=coverage_diverge --perf=1 --args="-n16 -d8 -p$pattern"
    ) >"$log" 2>&1
    rc=$?
    set -e
    points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
    instr="$(sed -n 's/^PERF: instrs=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
    cycles="$(sed -n 's/^PERF: instrs=.*cycles=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
    branches="$(sed -n 's/^PERF: branches: total=\([0-9][0-9]*\), divergent=.*/\1/p' "$log" | tail -1)"
    divergent="$(sed -n 's/^PERF: branches: total=[0-9][0-9]*, divergent=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
    if [[ -z $points ]]; then points=NA; fi
    if [[ $points != 1024 ]]; then echo "Expected 1024 points at 8 threads, got $points" >&2; tail -100 "$log" >&2; exit 1; fi
    if [[ -z $instr ]]; then instr=NA; fi
    if [[ -z $cycles ]]; then cycles=NA; fi
    if [[ -z $branches ]]; then branches=NA; fi
    if [[ -z $divergent ]]; then divergent=NA; fi
    if [[ $rc -eq 0 ]] && grep -q PASSED! "$log"; then result=PASSED
    elif [[ $rc -eq 124 || $rc -eq 137 ]]; then result=TIMEOUT
    else result=FAILED; fi
    printf '%s,%s,8,%s,%s,%s,%s,%s,%s\n' "$driver" "$pattern" "$points" "$instr" "$branches" "$divergent" "$cycles" "$result" | tee -a "$OUT"
    if [[ $result != PASSED ]]; then tail -100 "$log" >&2; exit 1; fi
  done
done
echo "Results: $OUT"
