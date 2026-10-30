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

BUILD="${VORTEX_BUILD_DIR:-$ROOT/build}"
SRC="$ROOT/hw/rtl/core/VX_alu_int.sv"
APP_DIR="$BUILD/tests/regression/coverage_diverge"
APP="$APP_DIR/coverage_diverge"
CSV="${1:-$RESEARCH_ROOT/experiments/vortex/branch_site_mutation_matrix.csv}"
TMP="$(mktemp -d /tmp/vx-branch-site.XXXXXX)"
cp "$SRC" "$TMP/original.sv"
restore() { cp "$TMP/original.sv" "$SRC"; rm -rf "$TMP"; }
trap restore EXIT INT TERM
if grep -q BRANCH_SITE_MUTANT "$SRC"; then echo "Existing mutation marker; aborting" >&2; exit 2; fi
printf 'site,branch_pc,pattern,points,mutant_hits,reference_errors,exit_code,result\n' > "$CSV"
sites=("2 80000188 80000190 80000180" "3 80000208 80000210 80000200" "4 8000028c 80000294 80000284" "5 80000310 80000318 80000308" "6 80000394 8000039c 8000038c" "7 80000418 80000420 80000410" "8 8000049c 800004a4 80000494")
for entry in "${sites[@]}"; do
 read -r level pc_a pc_b split_pc <<< "$entry"
 cp "$TMP/original.sv" "$SRC"
 python3 - "$SRC" "$pc_a" "$pc_b" "$level" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); a,b,level=sys.argv[2:]; s=p.read_text()
old="        assign result_if.data.data[i] = (is_br_op_r && is_br_static) ? PC_next : alu_result_r[i];"
new="""        // BRANCH_SITE_MUTANT level=%s
        wire targeted_fault = ((current_pc == from_fullPC(32'h%s)) || (current_pc == from_fullPC(32'h%s))) && (result_if.data.header.tmask == 4'b0101);
        assign result_if.data.data[i] = (is_br_op_r && is_br_static) ? PC_next : (((i == 0) && targeted_fault) ? (alu_result_r[i] ^ 32'd1) : alu_result_r[i]);
        always @(posedge clk) if (result_fire && (i == 0) && targeted_fault) $display("MUT_HIT site=%s", to_fullPC(current_pc));""" % (level,a,b,level)
if s.count(old)!=1: raise SystemExit("expected one ALU assignment")
p.write_text(s.replace(old,new))
PY
 if ! make -s -C "$BUILD/sw/runtime/rtlsim" DESTDIR="$TMP/build" all >"$TMP/build.log" 2>&1; then tail -100 "$TMP/build.log"; exit 1; fi
 for pattern in 0 1 2; do
  log="$TMP/l${level}_p${pattern}.log"
  set +e
  (cd "$APP_DIR" && env LD_LIBRARY_PATH="$TMP/build:$BUILD/sw/runtime" VORTEX_DRIVER=rtlsim timeout --kill-after=5 60 "$APP" -n16 -d8 -p"$pattern") >"$log" 2>&1
  rc=$?
  set -e
  points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
  hits="$(grep -c '^MUT_HIT ' "$log" || true)"
  errors="$(sed -n 's/^Found \([0-9][0-9]*\) errors!.*/\1/p' "$log" | tail -1)"; errors="${errors:-0}"
  if [[ $rc -eq 0 ]] && grep -q PASSED! "$log" && [[ $hits -eq 0 && $errors -eq 0 ]]; then result=PASS_NO_ACTIVATION
  elif [[ $rc -eq $errors && $hits -eq $errors && $errors -gt 0 ]] && grep -q FAILED! "$log"; then result=DETECTED
  elif [[ $rc -eq 124 || $rc -eq 137 ]]; then result=TIMEOUT
  else result=UNEXPECTED; fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$level" "$split_pc" "$pattern" "$points" "$hits" "$errors" "$rc" "$result" | tee -a "$CSV"
  [[ $result == PASS_NO_ACTIVATION || $result == DETECTED ]] || { tail -50 "$log" >&2; exit 1; }
 done
 cp "$TMP/original.sv" "$SRC"
done
