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

VORTEX_BUILD_DIR="${VORTEX_BUILD_DIR:-$VORTEX_ROOT/build}"
SRC="$VORTEX_ROOT/hw/rtl/core/VX_alu_int.sv"
APP_DIR="$VORTEX_BUILD_DIR/tests/regression/coverage_diverge"
APP="$APP_DIR/coverage_diverge"
TMP="$(mktemp -d /tmp/vx-mask-targeted-alu.XXXXXX)"

if grep -q "MASK_COV_MUTANT" "$SRC"; then
  echo "Refusing to run: an experimental mutation marker already exists in $SRC" >&2
  exit 2
fi
cp "$SRC" "$TMP/VX_alu_int.sv.original"
cleanup() {
  cp "$TMP/VX_alu_int.sv.original" "$SRC"
  rm -rf "$TMP"
}
trap cleanup EXIT

python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = "        assign result_if.data.data[i] = (is_br_op_r && is_br_static) ? PC_next : alu_result_r[i];"
replacement = """        // MASK_COV_MUTANT: flip lane 0 result bit 0 only for tmask 0101 at depth-5 arithmetic.
        wire targeted_fault = ((current_pc == from_fullPC(32'h80000310))
                            || (current_pc == from_fullPC(32'h80000318)))
                            && (result_if.data.header.tmask == 4'b0101);
        assign result_if.data.data[i] = (is_br_op_r && is_br_static) ? PC_next
            : (((i == 0) && targeted_fault) ? (alu_result_r[i] ^ 32'd1) : alu_result_r[i]);
        always @(posedge clk) begin
            if (result_fire && (i == 0) && targeted_fault)
                $display("MUT_HIT pc=0x%0h tmask=%b", to_fullPC(current_pc), result_if.data.header.tmask);
        end"""
if s.count(needle) != 1:
    raise SystemExit(f"Expected one ALU result assignment, found {s.count(needle)}")
p.write_text(s.replace(needle, replacement))
PY

if ! make -s -C "$VORTEX_BUILD_DIR/sw/runtime/rtlsim" DESTDIR="$TMP" all >"$TMP/build.log" 2>&1; then
  tail -100 "$TMP/build.log"
  exit 1
fi

printf "pattern,repeat,points,mutant_hits,reference_errors,exit_code\n"
for pattern in 0 1 2; do
  repeats=1
  if [[ "$pattern" -eq 2 ]]; then repeats=3; fi
  for ((repeat = 1; repeat <= repeats; ++repeat)); do
    log="$TMP/p${pattern}_r${repeat}.log"
    set +e
    (cd "$APP_DIR" &&
      env LD_LIBRARY_PATH="$TMP:$VORTEX_BUILD_DIR/sw/runtime" VORTEX_DRIVER=rtlsim \
      timeout --kill-after=5 60 "$APP" -n16 -d8 -p"$pattern") >"$log" 2>&1
    rc=$?
    set -e
    points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
    hits="$(grep -c '^MUT_HIT ' "$log" || true)"
    errors="$(sed -n 's/^Found \([0-9][0-9]*\) errors!.*/\1/p' "$log" | tail -1)"
    errors="${errors:-0}"
    printf "%s,%s,%s,%s,%s,%s\n" "$pattern" "$repeat" "$points" "$hits" "$errors" "$rc"
    if [[ "$pattern" -lt 2 ]]; then
      if [[ "$rc" -ne 0 || "$hits" -ne 0 || "$errors" -ne 0 ]] || ! grep -q "PASSED!" "$log"; then
        tail -40 "$log" >&2
        exit 1
      fi
    else
      if [[ "$rc" -ne "$errors" || "$hits" -le 0 || "$errors" -ne "$hits" ]] || ! grep -q "FAILED!" "$log"; then
        tail -40 "$log" >&2
        exit 1
      fi
    fi
  done
done
