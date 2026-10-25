#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/projects/vortex"
BUILD="$ROOT/build"
SRC="$ROOT/sim/simx/lsu_unit.cpp"
APP_DIR="$BUILD/tests/regression/coverage_diverge"
APP="$APP_DIR/coverage_diverge"
OUT="$HOME/projects/research/experiments/vortex/store_data_mutation.csv"
TMP="$(mktemp -d /tmp/vx-store-mutant.XXXXXX)"
cp "$SRC" "$TMP/original.cpp"
restore() { cp "$TMP/original.cpp" "$SRC"; rm -rf "$TMP"; }
trap restore EXIT INT TERM
if grep -q STORE_DATA_MUTANT "$SRC"; then echo "Mutation marker already present" >&2; exit 2; fi
printf 'case,repeat,pattern,points,mutant_hits,reference_errors,exit_code,result\n' > "$OUT"

baseline="$TMP/baseline.log"
set +e
(cd "$BUILD" && ./ci/blackbox.sh --driver=simx --cores=2 --app=coverage_diverge --perf=1 --args="-n16 -d8 -p0") >"$baseline" 2>&1
base_rc=$?
set -e
base_points="$(sed -n 's/^number of points: //p' "$baseline" | head -1)"
if [[ $base_rc -ne 0 ]] || ! grep -q PASSED! "$baseline"; then tail -80 "$baseline"; exit 1; fi
printf 'baseline,0,0,%s,0,0,%s,PASSED\n' "$base_points" "$base_rc" | tee -a "$OUT"

python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = "\t\t\t\tlsu_req.data.at(i) = block;"
replacement = """\t\t\t\t// STORE_DATA_MUTANT: corrupt lane 0's coverage result at the output store.
\t\t\t\tif (is_write && trace->PC == 0x80000094 && entry.tid == 0) {
\t\t\t\t\t(*block)[off] ^= 1u;
\t\t\t\t\tstd::cout << "STORE_MUT_HIT pc=0x" << std::hex << trace->PC
\t\t\t\t\t          << std::dec << " wid=" << trace->wid
\t\t\t\t\t          << " tid=" << entry.tid << " addr=0x"
\t\t\t\t\t          << std::hex << entry.addr << std::dec << "\\n";
\t\t\t\t}
\t\t\t\tlsu_req.data.at(i) = block;"""
if s.count(needle) != 1:
    raise SystemExit(f"expected one LSU block assignment, got {s.count(needle)}")
p.write_text(s.replace(needle, replacement))
PY
if ! make -s -C "$BUILD/sim/simx" >"$TMP/build.log" 2>&1; then tail -100 "$TMP/build.log"; exit 1; fi
for repeat in 1 2 3; do
  for pattern in 0 1 2; do
    log="$TMP/r"$repeat"_p"$pattern".log"
    set +e
    (cd "$BUILD" && ./ci/blackbox.sh --driver=simx --cores=2 --app=coverage_diverge --perf=1 --args="-n16 -d8 -p$pattern") >"$log" 2>&1
    rc=$?
    set -e
    points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
    hits="$(grep -c '^STORE_MUT_HIT ' "$log" || true)"
    errors="$(sed -n 's/^Found \([0-9][0-9]*\) errors!.*/\1/p' "$log" | tail -1)"
    if [[ -z $errors ]]; then errors=0; fi
    if grep -q FAILED! "$log" && [[ $hits -gt 0 && $hits -eq $errors ]]; then result=DETECTED
    elif grep -q PASSED! "$log" && [[ $hits -eq 0 && $errors -eq 0 ]]; then result=NOT_ACTIVATED
    elif [[ $rc -eq 124 || $rc -eq 137 ]]; then result=TIMEOUT
    else result=UNEXPECTED; fi
    printf 'mutant,%s,%s,%s,%s,%s,%s,%s\n' "$repeat" "$pattern" "$points" "$hits" "$errors" "$rc" "$result" | tee -a "$OUT"
    [[ $result == DETECTED ]] || { tail -80 "$log" >&2; exit 1; }
  done
done
echo "Results: $OUT"
