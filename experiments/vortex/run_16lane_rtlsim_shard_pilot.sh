#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RESEARCH_ROOT="${RESEARCH_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
VORTEX_ROOT="${VORTEX_ROOT:-}"
if [[ -z "$VORTEX_ROOT" ]]; then
  echo "Set VORTEX_ROOT to the Vortex source checkout" >&2
  exit 2
fi
ROOT="$VORTEX_ROOT"
VORTEX="$VORTEX_ROOT"
RESEARCH="$RESEARCH_ROOT"

BUILD="${VORTEX_BUILD_DIR:-$VORTEX_ROOT/build-threads16}"
APP_DIR="$BUILD/tests/regression/coverage_diverge"
APP="$APP_DIR/coverage_diverge"
OUT="${1:-$RESEARCH_ROOT/experiments/vortex/rtlsim_16lane_shard_pilot.csv}"
SHARD_SIZE=128
N_ARG=64
TMP="$(mktemp -d /tmp/vx-16lane-shard-pilot.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT INT TERM

grep -q '#define VX_CFG_NUM_THREADS 16' "$BUILD/sw/VX_config.h" || {
  echo "Expected a configured 16-thread build at $BUILD" >&2
  exit 2
}
for file in common.h kernel.cpp main.cpp; do
  cmp -s "$RESEARCH_ROOT/experiments/vortex/coverage_diverge/$file"     "$VORTEX_ROOT/tests/regression/coverage_diverge/$file" || {
      echo "Vortex test source is stale: $file" >&2
      exit 2
    }
done
grep -q 'COV_SPLIT pc=' "$VORTEX_ROOT/sim/simx/wctl_unit.cpp" || {
  echo "SIMX split trace patch is required for the per-site trace check" >&2
  exit 2
}

mkdir -p "$(dirname "$OUT")"
printf 'simulator,mask_start,mask_count,points,total_branches,divergent_events,cycles,split_sites,distinct_pairs_per_site,result\n' > "$OUT"

record_run() {
  local simulator="$1" start="$2" log="$3"
  python3 - "$simulator" "$start" "$SHARD_SIZE" "$log" "$OUT" <<'PY'
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

sim, start, count, log_path, csv_path = sys.argv[1:]
start, count = int(start), int(count)
text = Path(log_path).read_text(errors="replace")
def one(pattern, label):
    matches = re.findall(pattern, text, re.M)
    if not matches:
        raise SystemExit(f"{sim} shard {start}: missing {label}")
    return int(matches[-1])
if "PASSED!" not in text or "FAILED!" in text:
    raise SystemExit(f"{sim} shard {start}: application did not pass")
points = one(r"^number of points: (\d+)$", "point count")
branches, divergent = map(int, re.findall(
    r"^PERF: branches: total=(\d+), divergent=(\d+)", text, re.M)[-1])
cycles = one(r"^PERF: instrs=\d+, cycles=(\d+)", "cycle count")
if f"mask shard: {start}..{start + count - 1}" not in text:
    raise SystemExit(f"{sim} shard {start}: printed mask range does not match request")
sites = 0
pairs_per_site = 0
if sim == "rtlsim":
    if divergent != 7 * points // 16:
        raise SystemExit(f"RTLSIM shard {start}: unexpected divergent-event count {divergent}")
else:
    events = defaultdict(int)
    pairs = defaultdict(set)
    for line in text.splitlines():
        if not line.startswith("COV_SPLIT "):
            continue
        fields = dict(field.split("=", 1) for field in line.split()[1:])
        pc = fields["pc"]
        events[pc] += 1
        pairs[pc].add((fields["then_mask"], fields["else_mask"]))
    if len(events) != 7 or any(events[pc] != count or len(pairs[pc]) != count for pc in events):
        raise SystemExit(f"SIMX shard {start}: each of seven sites must see {count} masks; got {dict(events)}")
    sites = len(events)
    pairs_per_site = min(map(len, pairs.values()))
with open(csv_path, "a", newline="") as stream:
    csv.writer(stream).writerow(
        [sim, start, count, points, branches, divergent, cycles, sites, pairs_per_site, "PASSED"])
print(f"{sim} shard={start}..{start+count-1} points={points} "
      f"divergent={divergent} cycles={cycles} sites={sites} "
      f"distinct_pairs_per_site={pairs_per_site} PASSED")
PY
}

for start in 1 65407; do
  args="-n$N_ARG -d8 -p4 -s$start -m$SHARD_SIZE"
  rtlog="$TMP/rtlsim-$start.log"
  timeout --signal=INT --kill-after=5 120 "$BUILD/ci/blackbox.sh" \
    --driver=rtlsim --cores=2 --app=coverage_diverge --perf=1 --args="$args" > "$rtlog" 2>&1
  record_run rtlsim "$start" "$rtlog"

  simlog="$TMP/simx-$start.log"
  VX_SIMX_SPLIT_TRACE=1 timeout --signal=INT --kill-after=5 120 \
    "$BUILD/ci/blackbox.sh" --driver=simx --cores=2 \
    --app=coverage_diverge --perf=1 --args="$args" > "$simlog" 2>&1
  record_run simx "$start" "$simlog"
done

echo "CSV: $OUT"
cat "$OUT"
