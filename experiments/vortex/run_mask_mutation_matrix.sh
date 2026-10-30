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

BUILD="$VORTEX/build"
SRC="$VORTEX/sim/simx/wctl_unit.cpp"
OBJ="$BUILD/sw/runtime/obj/wctl_unit.o"
LIB="$BUILD/sw/runtime/libsimx.so"
APP="$BUILD/tests/regression/coverage_diverge/coverage_diverge"
OUT="${RESULT_CSV:-$RESEARCH/experiments/vortex/mutation_matrix.csv}"
RANDOM_SEEDS="${RANDOM_SEEDS:-0}"
FIXED_COUNT="${FIXED_COUNT:-16}"
SWEEP_COUNT="${SWEEP_COUNT:-16}"
SEEDED_COUNT="${SEEDED_COUNT:-16}"
if [[ ! "$RANDOM_SEEDS" =~ ^[0-9]+$ ]]; then
  echo "RANDOM_SEEDS must be a nonnegative integer" >&2
  exit 2
fi
for count in "$FIXED_COUNT" "$SWEEP_COUNT" "$SEEDED_COUNT"; do
  if [[ ! "$count" =~ ^[1-9][0-9]*$ ]]; then
    echo "workload counts must be positive integers" >&2
    exit 2
  fi
done

for file in "$SRC" "$OBJ" "$LIB" "$APP"; do
  test -f "$file" || { echo "Missing required file: $file" >&2; exit 1; }
done
if ! grep -Eq '^#define[[:space:]]+VX_CFG_NUM_THREADS[[:space:]]+4([[:space:]]|$)' "$BUILD/sw/VX_config.h"; then
  echo "This mutation generator is defined for four-thread warps; configuration mismatch." >&2
  exit 1
fi
if strings "$LIB" | grep -q VX_SIMX_MASK_FAULT_ID; then
  echo "Runtime library already contains a temporary mutation hook; refusing to overwrite it." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
tmpdir=$(mktemp -d /tmp/vx-mutation-matrix.XXXXXX)
cp "$SRC" "$tmpdir/wctl_unit.cpp"
cp "$OBJ" "$tmpdir/wctl_unit.o"
cp "$LIB" "$tmpdir/libsimx.so"
restore() {
  cp "$tmpdir/wctl_unit.cpp" "$SRC"
  cp "$tmpdir/wctl_unit.o" "$OBJ"
  cp "$tmpdir/libsimx.so" "$LIB"
  rm -rf "$tmpdir"
}
trap restore EXIT

python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
source = p.read_text()
needle = "    bool is_divergent = then_tmask.any() && else_tmask.any();"
injection = """    bool is_divergent = then_tmask.any() && else_tmask.any();
    const char* fault_id_text = std::getenv("VX_SIMX_MASK_FAULT_ID");
    int fault_id = fault_id_text ? std::atoi(fault_id_text) : 0;
    if (fault_id > 0) {
      uint32_t target_mask = ((fault_id - 1) / 4) + 1;
      uint32_t fault_lane = (fault_id - 1) % 4;
      uint32_t then_mask = 0;
      for (uint32_t t = 0; t < 4; ++t)
        then_mask |= uint32_t(then_tmask.test(t)) << t;
      if (then_mask == target_mask) {
        if (then_tmask.test(fault_lane)) {
          then_tmask.reset(fault_lane);
          else_tmask.set(fault_lane);
        } else {
          else_tmask.reset(fault_lane);
          then_tmask.set(fault_lane);
        }
        std::cout << "COV_MUTATION id=" << fault_id
                  << " pc=0x" << std::hex << trace->PC
                  << std::dec << " wid=" << trace->wid << "\\n";
      }
    }"""
if source.count(needle) != 1:
    raise SystemExit(f"Expected one insertion point, found {source.count(needle)}")
p.write_text(source.replace(needle, injection))
PY

make -C "$BUILD/sw/runtime/simx" driver > "$tmpdir/build.log" 2>&1
cp "$LIB" "$tmpdir/mutant-libsimx.so"
cp "$tmpdir/wctl_unit.cpp" "$SRC"
cp "$tmpdir/wctl_unit.o" "$OBJ"
cp "$tmpdir/libsimx.so" "$LIB"

printf 'fault_id,original_then_mask,flipped_lane,pattern,seed,points,activations,errors,outcome,exit_status,instructions,cycles\n' > "$OUT"
for fault_id in $(seq 1 56); do
  target_mask=$(( (fault_id - 1) / 4 + 1 ))
  lane=$(( (fault_id - 1) % 4 ))
  mask_label=""
  for bit in 3 2 1 0; do
    mask_label+="$(( (target_mask >> bit) & 1 ))"
  done
  for pattern in 0 1 2; do
    count="$FIXED_COUNT"
    if [[ "$pattern" == 2 ]]; then count="$SWEEP_COUNT"; fi
    cp "$tmpdir/mutant-libsimx.so" "$LIB"
    log="$tmpdir/run_m${fault_id}_p${pattern}.log"
    if (cd "$BUILD/tests/regression/coverage_diverge" &&
        LD_LIBRARY_PATH="$BUILD/sw/runtime" VORTEX_DRIVER=simx \
        VX_SIMX_MASK_FAULT_ID="$fault_id" VX_SIMX_SPLIT_TRACE=1 \
        ./coverage_diverge -n"$count" -d8 -p"$pattern") > "$log" 2>&1; then
      exit_status=0
    else
      exit_status=$?
    fi
    summary=$(awk '
      /^COV_MUTATION / { activations++ }
      /Found [0-9]+ errors!/ { errors=$2 }
      /PASSED!/ { passed=1 }
      /FAILED!/ { failed=1 }
      END {
        outcome = errors > 0 ? "KILLED" : (activations > 0 ? "SURVIVED" : "NOT_REACHED")
        printf "%d,%d,%s", activations+0, errors+0, outcome
      }' "$log")
    IFS=, read -r activations errors outcome <<< "$summary"
    perf=$(sed -n 's/.*instrs=\([0-9][0-9]*\).*cycles=\([0-9][0-9]*\).*/\1,\2/p' "$log" | tail -1)
    if [[ -z "$perf" ]]; then
      echo "Missing instruction/cycle counters for mutant $fault_id pattern $pattern" >&2
      tail -30 "$log" >&2
      exit 1
    fi
    IFS=, read -r instructions cycles <<< "$perf"
    printf '%d,%s,%d,%d,0,%d,%d,%d,%s,%d,%s,%s\n' \
      "$fault_id" "$mask_label" "$lane" "$pattern" "$((count * 32))" \
      "$activations" "$errors" "$outcome" "$exit_status" \
      "$instructions" "$cycles" >> "$OUT"
    printf 'fault=%02d mask=%s lane=%d pattern=%d activation=%d errors=%d outcome=%s exit=%d cycles=%s\n' \
      "$fault_id" "$mask_label" "$lane" "$pattern" \
      "$activations" "$errors" "$outcome" "$exit_status" "$cycles"
  done
done
if (( RANDOM_SEEDS > 0 )); then
  for fault_id in $(seq 1 56); do
    target_mask=$(( (fault_id - 1) / 4 + 1 ))
    lane=$(( (fault_id - 1) % 4 ))
    mask_label=""
    for bit in 3 2 1 0; do
      mask_label+="$(( (target_mask >> bit) & 1 ))"
    done
    cp "$tmpdir/mutant-libsimx.so" "$LIB"
    for seed in $(seq 1 "$RANDOM_SEEDS"); do
      log="$tmpdir/run_m${fault_id}_p6_s${seed}.log"
      if (cd "$BUILD/tests/regression/coverage_diverge" &&
          LD_LIBRARY_PATH="$BUILD/sw/runtime" VORTEX_DRIVER=simx \
          VX_SIMX_MASK_FAULT_ID="$fault_id" VX_SIMX_SPLIT_TRACE=1 \
          ./coverage_diverge -n"$SEEDED_COUNT" -d8 -p6 -r"$seed") > "$log" 2>&1; then
        exit_status=0
      else
        exit_status=$?
      fi
      summary=$(awk '
        /^COV_MUTATION / { activations++ }
        /Found [0-9]+ errors!/ { errors=$2 }
        END {
          outcome = errors > 0 ? "KILLED" : (activations > 0 ? "SURVIVED" : "NOT_REACHED")
          printf "%d,%d,%s", activations+0, errors+0, outcome
        }' "$log")
      IFS=, read -r activations errors outcome <<< "$summary"
      perf=$(sed -n 's/.*instrs=\([0-9][0-9]*\).*cycles=\([0-9][0-9]*\).*/\1,\2/p' "$log" | tail -1)
      if [[ -z "$perf" ]]; then
        echo "Missing instruction/cycle counters for mutant $fault_id random seed $seed" >&2
        tail -30 "$log" >&2
        exit 1
      fi
      IFS=, read -r instructions cycles <<< "$perf"
      printf '%d,%s,%d,6,%d,%d,%d,%d,%s,%d,%s,%s\n' \
        "$fault_id" "$mask_label" "$lane" "$seed" "$((SEEDED_COUNT * 32))" \
        "$activations" "$errors" "$outcome" "$exit_status" \
        "$instructions" "$cycles" >> "$OUT"
      printf 'fault=%02d mask=%s lane=%d pattern=6 seed=%d activation=%d errors=%d outcome=%s exit=%d cycles=%s\n' \
        "$fault_id" "$mask_label" "$lane" "$seed" \
        "$activations" "$errors" "$outcome" "$exit_status" "$cycles"
    done
  done
fi
restore
trap - EXIT
if strings "$LIB" | grep -q VX_SIMX_MASK_FAULT_ID; then
  echo "Temporary mutation hook remains in runtime library." >&2
  exit 1
fi
echo "Restored SIMX source/object/runtime library."
echo "CSV: $OUT"
