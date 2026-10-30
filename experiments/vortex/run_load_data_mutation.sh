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

BUILD="$ROOT/build"
SRC="$ROOT/sim/simx/lsu_unit.cpp"
OUT="$RESEARCH_ROOT/experiments/vortex/load_data_mutation.csv"
TMP="$(mktemp -d /tmp/vx-load-mutant.XXXXXX)"
cp "$SRC" "$TMP/original.cpp"
restore() { cp "$TMP/original.cpp" "$SRC"; rm -rf "$TMP"; }
trap restore EXIT INT TERM
if grep -q LOAD_DATA_MUTANT "$SRC"; then echo "Mutation marker already present" >&2; exit 2; fi
printf 'case,repeat,points,mutant_hits,reference_errors,exit_code,result\n' > "$OUT"

baseline="$TMP/baseline.log"
set +e
(cd "$BUILD" && ./ci/blackbox.sh --driver=simx --cores=1 --app=diverge --args="-n16 -d8") >"$baseline" 2>&1
base_rc=$?
set -e
base_points="$(sed -n 's/^number of points: //p' "$baseline" | head -1)"
if [[ $base_rc -ne 0 ]] || ! grep -q PASSED! "$baseline"; then tail -80 "$baseline"; exit 1; fi
printf 'baseline,0,%s,0,0,%s,PASSED\n' "$base_points" "$base_rc" | tee -a "$OUT"

python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = "\t\t\tstd::memcpy(&read_data, lsu_rsp.data.at(lane)->data() + off, data_bytes);"
replacement = """\t\t\tstd::memcpy(&read_data, lsu_rsp.data.at(lane)->data() + off, data_bytes);
\t\t\t// LOAD_DATA_MUTANT: flip bit 0 on lane 0's initial source-data load.
\t\t\tif (trace->PC == 0x80000054 && lane_info.tid == 0) {
\t\t\t\tread_data ^= 1u;
\t\t\t\tstd::cout << "LOAD_MUT_HIT pc=0x" << std::hex << trace->PC
\t\t\t\t          << std::dec << " wid=" << trace->wid
\t\t\t\t          << " tid=" << lane_info.tid << " addr=0x"
\t\t\t\t          << std::hex << lane_info.addr << std::dec << "\\n";
\t\t\t}"""
if s.count(needle) != 1:
    raise SystemExit(f"expected one load-response memcpy, got {s.count(needle)}")
p.write_text(s.replace(needle, replacement))
PY
if ! make -s -C "$BUILD/sim/simx" >"$TMP/build.log" 2>&1; then tail -100 "$TMP/build.log"; exit 1; fi
for repeat in 1 2 3 4 5; do
  log="$TMP/r"$repeat".log"
  set +e
  (cd "$BUILD" && ./ci/blackbox.sh --driver=simx --cores=1 --app=diverge --args="-n16 -d8") >"$log" 2>&1
  rc=$?
  set -e
  points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
  hits="$(grep -c '^LOAD_MUT_HIT ' "$log" || true)"
  errors="$(sed -n 's/^Found \([0-9][0-9]*\) errors!.*/\1/p' "$log" | tail -1)"
  if [[ -z $errors ]]; then errors=0; fi
  if grep -q FAILED! "$log" && [[ $hits -gt 0 && $hits -eq $errors ]]; then result=DETECTED
  elif grep -q PASSED! "$log" && [[ $hits -eq 0 && $errors -eq 0 ]]; then result=NOT_ACTIVATED
  elif [[ $rc -eq 124 || $rc -eq 137 ]]; then result=TIMEOUT
  else result=UNEXPECTED; fi
  printf 'mutant,%s,%s,%s,%s,%s,%s\n' "$repeat" "$points" "$hits" "$errors" "$rc" "$result" | tee -a "$OUT"
  [[ $result == DETECTED ]] || { tail -80 "$log" >&2; exit 1; }
done
echo "Results: $OUT"
