#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/projects/vortex"
BUILD="$ROOT/build"
SRC="$ROOT/hw/rtl/core/VX_alu_int.sv"
APP_DIR="$BUILD/tests/regression/coverage_diverge"
APP="$APP_DIR/coverage_diverge"
OUT="$HOME/projects/research/experiments/vortex/size_scaling_mask_mutation.csv"
TMP="$(mktemp -d /tmp/vx-size-mask.XXXXXX)"
cp "$SRC" "$TMP/original.sv"
restore() { cp "$TMP/original.sv" "$SRC"; rm -rf "$TMP"; }
trap restore EXIT INT TERM
if grep -q SIZE_SCALING_MUTANT "$SRC"; then echo "Mutation marker already present" >&2; exit 2; fi
python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
needle="        assign result_if.data.data[i] = (is_br_op_r && is_br_static) ? PC_next : alu_result_r[i];"
repl="""        // SIZE_SCALING_MUTANT: flip lane 0 result bit 0 under exact mask 0101.
        wire targeted_fault = ((current_pc == from_fullPC(32'h80000188))
                            || (current_pc == from_fullPC(32'h80000190)))
                            && (result_if.data.header.tmask == 4'b0101);
        assign result_if.data.data[i] = (is_br_op_r && is_br_static) ? PC_next
            : (((i == 0) && targeted_fault) ? (alu_result_r[i] ^ 32'd1) : alu_result_r[i]);
        always @(posedge clk) begin
          if (result_fire && (i == 0) && targeted_fault)
            $display("MUT_HIT mask=%%b", result_if.data.header.tmask);
        end"""
if s.count(needle)!=1: raise SystemExit(f"expected one ALU result assignment, got {s.count(needle)}")
p.write_text(s.replace(needle,repl))
PY
if ! make -s -C "$BUILD/sw/runtime/rtlsim" DESTDIR="$TMP/build" all >"$TMP/build.log" 2>&1; then tail -100 "$TMP/build.log"; exit 1; fi
printf 'count,pattern,points,mutant_hits,reference_errors,exit_code,result\n' > "$OUT"
for count in 8 16 32; do
 for pattern in 0 1 2; do
  log="$TMP/n${count}_p${pattern}.log"
  set +e
  (cd "$APP_DIR" && env LD_LIBRARY_PATH="$TMP/build:$BUILD/sw/runtime" VORTEX_DRIVER=rtlsim timeout --kill-after=5 60 "$APP" -n"$count" -d8 -p"$pattern") >"$log" 2>&1
  rc=$?
  set -e
  points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
  hits="$(grep -c '^MUT_HIT ' "$log" || true)"
  errors="$(sed -n 's/^Found \([0-9][0-9]*\) errors!.*/\1/p' "$log" | tail -1)"; errors="${errors:-0}"
  if [[ $hits -eq 0 && $errors -eq 0 && $rc -eq 0 ]] && grep -q PASSED! "$log"; then result=PASS_NO_ACTIVATION
  elif [[ $hits -gt 0 && $errors -eq $hits && $rc -eq $errors ]] && grep -q FAILED! "$log"; then result=DETECTED
  elif [[ $rc -eq 124 || $rc -eq 137 ]]; then result=TIMEOUT
  else result=UNEXPECTED; fi
  printf '%s,%s,%s,%s,%s,%s,%s\n' "$count" "$pattern" "$points" "$hits" "$errors" "$rc" "$result" | tee -a "$OUT"
  [[ $result == PASS_NO_ACTIVATION || $result == DETECTED ]] || { tail -60 "$log" >&2; exit 1; }
 done
done
echo "Results: $OUT"
