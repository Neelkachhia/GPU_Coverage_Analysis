#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/projects/vortex"
BUILD="$ROOT/build"
SRC="$ROOT/sim/simx/wctl_unit.cpp"
APP_DIR="$BUILD/tests/regression/coverage_diverge"
APP="$APP_DIR/coverage_diverge"
OUT="$HOME/projects/research/experiments/vortex/split_predicate_mutation.csv"
TMP="$(mktemp -d /tmp/vx-split-control.XXXXXX)"
cp "$SRC" "$TMP/original.cpp"
restore() { cp "$TMP/original.cpp" "$SRC"; rm -rf "$TMP"; }
trap restore EXIT INT TERM
if grep -q SPLIT_PREDICATE_MUTANT "$SRC"; then echo "Mutation marker already present" >&2; exit 2; fi
python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
old="      auto cond = (rs1_data.at(t).i & 0x1) ^ not_pred;"
new="""      auto cond = (rs1_data.at(t).i & 0x1) ^ not_pred;
      // SPLIT_PREDICATE_MUTANT: invert lane 0 at depth-2 split PC.
      if (trace->PC == 0x80000180 && t == 0 && warp.tmask.test(0)) {
        cond = !cond;
        std::cout << "MUT_HIT site=2 lane=0 active_mask=";
        for (uint32_t bit = num_threads; bit > 0; --bit)
          std::cout << (warp.tmask.test(bit - 1) ? '1' : '0');
        std::cout << "\\n";
      }"""
if old not in s: raise SystemExit("SPLIT predicate expression not found")
p.write_text(s.replace(old,new,1))
PY
if ! make -s -C "$BUILD/sim/simx" >"$TMP/build.log" 2>&1; then tail -100 "$TMP/build.log"; exit 1; fi
printf 'repeat,pattern,points,mutant_hits,reference_errors,exit_code,result\n' > "$OUT"
for repeat in 1 2 3; do
  for pattern in 0 1 2; do
    log="$TMP/r"$repeat"_p"$pattern".log"
    set +e
    (cd "$BUILD" && ./ci/blackbox.sh --driver=simx --cores=2 --app=coverage_diverge --perf=1 --args="-n16 -d8 -p$pattern") >"$log" 2>&1
    rc=$?
    set -e
    points="$(sed -n 's/^number of points: //p' "$log" | head -1)"
    hits="$(grep -c '^MUT_HIT ' "$log" || true)"
    errors="$(sed -n 's/^Found \([0-9][0-9]*\) errors!.*/\1/p' "$log" | tail -1)"
    if [[ -z $errors ]]; then errors=0; fi
    if grep -q PASSED! "$log" && [[ $hits -eq 0 && $errors -eq 0 ]]; then result=PASS_NO_ACTIVATION
    elif grep -q FAILED! "$log" && [[ $hits -gt 0 && $errors -gt 0 ]]; then result=DETECTED
    elif [[ $rc -eq 124 || $rc -eq 137 ]]; then result=TIMEOUT
    else result=UNEXPECTED; fi
    printf '%s,%s,%s,%s,%s,%s,%s\n' "$repeat" "$pattern" "$points" "$hits" "$errors" "$rc" "$result" | tee -a "$OUT"
    grep '^MUT_HIT ' "$log" | sort -u | head -10 | sed 's/^/  /'
    [[ $result == DETECTED ]] || { tail -60 "$log" >&2; exit 1; }
  done
done
echo "Results: $OUT"
