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
SRC="$ROOT/hw/rtl/core/VX_alu_int.sv"
APP_DIR="$BUILD/tests/regression/diverge"
APP="$APP_DIR/diverge"
OUT="$RESEARCH_ROOT/experiments/vortex/diverge_workload_mutation.csv"
TMP="$(mktemp -d /tmp/vx-diverge-mutant.XXXXXX)"
cp "$SRC" "$TMP/original.sv"
restore() { cp "$TMP/original.sv" "$SRC"; rm -rf "$TMP"; }
trap restore EXIT INT TERM
if grep -q SECOND_WORKLOAD_MUTANT "$SRC"; then echo "Mutation marker already present" >&2; exit 2; fi
printf 'case,points,mutant_hits,reference_errors,exit_code,result\n' > "$OUT"

baseline="$TMP/baseline.log"
set +e
(cd "$BUILD" && timeout --kill-after=5 120 ./ci/blackbox.sh --driver=rtlsim --cores=1 --app=diverge --args="-n16 -d8") >"$baseline" 2>&1
base_rc=$?
set -e
base_points="$(sed -n 's/^number of points: //p' "$baseline" | head -1)"
if [[ $base_rc -ne 0 ]] || ! grep -q PASSED! "$baseline"; then tail -80 "$baseline"; exit 1; fi
printf 'baseline,%s,0,0,%s,PASSED\n' "$base_points" "$base_rc" | tee -a "$OUT"

python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
needle="        assign result_if.data.data[i] = (is_br_op_r && is_br_static) ? PC_next : alu_result_r[i];"
replacement="""        // SECOND_WORKLOAD_MUTANT: flip lane 2 result bit 0 at diverge kernel PC 0x800000ac under mask 0100.
        wire second_workload_fault = (current_pc == from_fullPC(32'h800000ac))
                                  && (result_if.data.header.tmask == 4'b0100);
        assign result_if.data.data[i] = (is_br_op_r && is_br_static) ? PC_next
            : (((i == 2) && second_workload_fault) ? (alu_result_r[i] ^ 32'd1) : alu_result_r[i]);
        always @(posedge clk) begin
          if (result_fire && (i == 2) && second_workload_fault)
            $display("MUT_HIT mask=%%b", result_if.data.header.tmask);
        end"""
if s.count(needle)!=1: raise SystemExit(f"expected one ALU result assignment, got {s.count(needle)}")
p.write_text(s.replace(needle,replacement))
PY
if ! make -s -C "$BUILD/sw/runtime/rtlsim" DESTDIR="$TMP/build" all >"$TMP/build.log" 2>&1; then tail -100 "$TMP/build.log"; exit 1; fi
for repeat in 1 2 3 4 5; do
  mutant="$TMP/mutant_r${repeat}.log"
  set +e
  (cd "$APP_DIR" && env LD_LIBRARY_PATH="$TMP/build:$BUILD/sw/runtime" VORTEX_DRIVER=rtlsim timeout --kill-after=5 120 "$APP" -n16 -d8) >"$mutant" 2>&1
  rc=$?
  set -e
  points="$(sed -n 's/^number of points: //p' "$mutant" | head -1)"
  hits="$(grep -c '^MUT_HIT ' "$mutant" || true)"
  errors="$(sed -n 's/^Found \([0-9][0-9]*\) errors!.*/\1/p' "$mutant" | tail -1)"; errors="${errors:-0}"
  if grep -q FAILED! "$mutant" && [[ $hits -gt 0 && $hits -eq $errors ]]; then result=DETECTED
  elif grep -q PASSED! "$mutant" && [[ $hits -eq 0 && $errors -eq 0 ]]; then result=NOT_ACTIVATED
  elif [[ $rc -eq 124 || $rc -eq 137 ]]; then result=TIMEOUT
  else result=UNEXPECTED; fi
  printf 'mutant_r%s,%s,%s,%s,%s,%s\n' "$repeat" "$points" "$hits" "$errors" "$rc" "$result" | tee -a "$OUT"
  [[ $result == DETECTED || $result == NOT_ACTIVATED ]] || { tail -80 "$mutant" >&2; exit 1; }
done
echo "Results: $OUT"
