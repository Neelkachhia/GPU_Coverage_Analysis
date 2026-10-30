# GPU Coverage Analysis

This repository contains a research prototype for measuring divergent SIMT
lane-mask coverage in Vortex. The current study records dynamic split events
and compares fixed and exhaustive mask patterns against selected injected
faults. It is an experimental case study, not a general-purpose GPU
verification framework.

## Current scope

- The Rust workspace models coverage bins, runs Vortex test cases, and reports
  measured results.
- The experimental `coverage_diverge` kernel generates nonuniform masks for
  4-, 8-, and 16-lane warps.
- An opt-in SIMX trace records each divergent split's compiled PC, warp ID,
  then/else lane counts, and lane masks.
- Result summaries are CSV files under `experiments/vortex/`; the measurement
  details and known limits are in
  [`docs/coverage_experiment_log.md`](docs/coverage_experiment_log.md).

The exhaustive 16-lane results were collected on SIMX. RTLSIM checks cover
bounded workloads; they are not a full 16-lane exhaustive run. No physical GPU
or FPGA evaluation is included.

## Run the Rust tests

From the repository root:

```bash
cargo test -p runner -p orchestrator
```

Simulator-dependent integration tests are ignored by default. They require a
configured Vortex build, the experimental regression app, and the trace patch.
Follow the setup steps in the experiment log before enabling those tests.

## Run the measured depth sweep

After setting up Vortex as described in the experiment log:

```bash
export VORTEX_ROOT=/path/to/vortex
export VORTEX_BUILD_DIR="$VORTEX_ROOT/build"
cargo run -p orchestrator -- --vortex-sweep
```

The current sweep measures patterns 0 through 2 at depths 1 through 8 on the
configured four-thread SIMX build. It is separate from the pattern-3, -4, and
-5 experiment scripts under `experiments/vortex/`.

## Reproduce the wider mask and mutation experiments

Set `VORTEX_ROOT` to the Vortex source checkout. The scripts locate this
repository from their own paths; result files default to
`experiments/vortex/`. Some scripts temporarily edit Vortex source or its
thread configuration and restore those files on exit. Read the script and
experiment-log notes before running one. The alternate 8- and 16-thread
experiments require separately configured Vortex build directories.

The logged mutations are synthetic, targeted fault models. A pass or kill
result applies to the tested mutant and workload; it is not a general RTL
fault-coverage estimate.

The latest four-lane matrix includes patterns 0, 1, and 2, plus five
deterministic seeded schedules (pattern 6). Rebuild that data with:

```bash
RANDOM_SEEDS=5 \
RESULT_CSV="$PWD/experiments/vortex/mutation_matrix_simx_random.csv" \
  VORTEX_ROOT="$VORTEX_ROOT" bash experiments/vortex/run_mask_mutation_matrix.sh
python3 experiments/vortex/analyze_mask_mutations.py
```

The analyzer checks all 56 mutant IDs for each fixed pattern and seed, then
reports each seed separately. These cycle totals describe one campaign of
synthetic lane-routing variants on SIMX. They are not a general test-efficiency
or hardware fault-coverage estimate.

## Project status

The present implementation and results focus on divergence and active-lane
masks. Scheduler, barrier, memory-bank, and outstanding-miss coverage remain
future work. Simulator cycle counts are model-specific and are not physical
performance measurements.
