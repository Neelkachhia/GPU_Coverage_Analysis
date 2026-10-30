# Vortex SIMX Divergence Coverage Experiment

## Reproduction paths

Set these variables to the local checkouts before running commands in this log:

```bash
export RESEARCH_ROOT=/path/to/GPU_Coverage_Analysis
export VORTEX_ROOT=/path/to/vortex
```

## Environment

- Vortex revision: `1cd71c4`
- Simulator: `simx`
- Configuration: 4 warps/core, 4 threads/warp
- Workload: 512 points; `--cores=2 -n16` or `--cores=1 -n32`
- Test: experimental `tests/regression/coverage_diverge`
- Performance counters enabled with `--perf=1`

## Depth sweep

Every run passed its host-reference result check.

| Requested depth | Static PCs with divergent events | Divergent events | Total branches |
|---:|---:|---:|---:|
| 1 | 0 | 0 | 1,536 |
| 2 | 1 | 128 | 1,920 |
| 3 | 2 | 256 | 2,304 |
| 4 | 3 | 384 | 2,688 |
| 5 | 4 | 512 | 3,072 |
| 6 | 5 | 640 | 3,456 |
| 7 | 6 | 768 | 3,840 |
| 8 | 7 | 896 | 4,224 |

At depth 8, each measured PC produced 128 events:

| Split PC | Events | Then lanes/event | Else lanes/event | Source level |
|---|---:|---:|---:|---:|
| `0x800000c0` | 128 | 2 | 2 | 2 |
| `0x800000ec` | 128 | 3 | 1 | 3 |
| `0x80000120` | 128 | 3 | 1 | 4 |
| `0x80000154` | 128 | 3 | 1 | 5 |
| `0x80000188` | 128 | 3 | 1 | 6 |
| `0x800001b8` | 128 | 3 | 1 | 7 |
| `0x800001e8` | 128 | 3 | 1 | 8 |

The 1-core run with the same 512 points reproduced the 2-core totals: 4,224 branches, 896 divergent events, and 128 events per PC.

## Interpretation and limits

The dynamic simulator trace attributes divergence events to static instruction PCs. The depth sweep adds one measured split site per level from 2 through 8. The level-1 source condition is compiled into predicated arithmetic and therefore does not appear in the divergent-split trace.

PC addresses depend on the compiled binary and can change when the kernel changes. These results characterize this test and configuration; they are not yet general Vortex coverage results. The `divergent` counter is a dynamic event count, not a count of unique source branches.

## Reproducing the SIMX trace

The simulator trace instrumentation is stored in
`patches/vortex-simx-split-trace.patch`. It was generated against Vortex
revision `1cd71c4`.

From a clean Vortex checkout at that revision, apply and build it:

```bash
git -C $VORTEX_ROOT apply $RESEARCH_ROOT/patches/vortex-simx-split-trace.patch
cd $VORTEX_ROOT/build
make -C sim/simx

```

Then run the depth-8 case from the build directory:

```bash
cd $VORTEX_ROOT/build
VX_SIMX_SPLIT_TRACE=1 ./ci/blackbox.sh --driver=simx --cores=2 \
  --app=coverage_diverge --perf=1 --args="-n16 -d8"
```

The run should print `PASSED!`, with 4,224 total branches, 896 divergent events, and seven split PCs with 128 events each.

### Install the experimental test

The `coverage_diverge` test is not part of the pinned Vortex checkout. Its
source files are stored in
`experiments/vortex/coverage_diverge/`. Before building, copy the directory
into the Vortex regression tests:

```bash
cp -a $RESEARCH_ROOT/experiments/vortex/coverage_diverge \
  $VORTEX_ROOT/tests/regression/
```

Then apply the trace patch and follow the build and run steps above.

## Orchestrator depth sweep (three repetitions)

Three consecutive measured SIMX sweeps produced identical cycle and unique-bin
counts at every depth:

| Depth | Cycles per run | Unique bins |
|---:|---:|---:|
| 1 | 17,597 | 0 |
| 2 | 20,060 | 3 |
| 3 | 22,174 | 5 |
| 4 | 24,421 | 7 |
| 5 | 26,677 | 9 |
| 6 | 29,066 | 11 |
| 7 | 31,285 | 13 |
| 8 | 33,559 | 15 |

The identical results show repeatability for this pinned simulator, configuration, and workload. They do not establish performance behavior across other
configurations or platforms.

## Complementary branch-pattern sweep (single repetition)

The coverage kernel was extended with two branch patterns. Pattern 0 uses the original predicates; pattern 1 inverts each predicate. Both were run at depths 1 through 8 with the same SIMX configuration and workload.

| Pattern | Depth | Cycles | Unique bins |
|---:|---:|---:|---:|
| 0 | 1 | 18,146 | 0 |
| 0 | 2 | 20,851 | 3 |
| 0 | 3 | 23,075 | 5 |
| 0 | 4 | 25,760 | 7 |
| 0 | 5 | 28,280 | 9 |
| 0 | 6 | 30,993 | 11 |
| 0 | 7 | 33,465 | 13 |
| 0 | 8 | 36,097 | 15 |
| 1 | 1 | 18,146 | 0 |
| 1 | 2 | 20,851 | 3 |
| 1 | 3 | 23,130 | 5 |
| 1 | 4 | 25,722 | 7 |
| 1 | 5 | 28,249 | 9 |
| 1 | 6 | 30,981 | 11 |
| 1 | 7 | 33,499 | 13 |
| 1 | 8 | 35,937 | 15 |

Each depth-8 pattern report contains seven split-site bins, seven lane-count
bins, and the divergence bin. The integration test merges both depth-8 reports and passes with 21 unique bins: six additional lane-count bins beyond either pattern alone. At six sites, the patterns exchange the observed `1:3` and `3:1` lane counts; one site remains `2:2`.

These are single-run cycle observations for the updated kernel. The earlier
depth-sweep cycle table used a different kernel version and should not be
compared directly. Repeat runs are needed before drawing performance
conclusions. Lane-count bins record then/else population counts; they do not
identify individual lane masks.

## Mask-aware coverage results (supersedes prior bin counts)

The Rust report now adds one then/else lane-mask pair bin per divergent split site. The previous section's unique-bin counts included split-site and
lane-count bins only; the updated sweep reports:

| Pattern | Depth 1 | Depth 2 | Depth 3 | Depth 4 | Depth 5 | Depth 6 | Depth 7 | Depth 8 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 4 | 7 | 10 | 13 | 16 | 19 | 22 |
| 1 | 0 | 4 | 7 | 10 | 13 | 16 | 19 | 22 |

At depth 8, each pattern reports seven split-site bins, seven lane-count bins, seven mask-pair bins, and the divergence bin. The integration test merges both patterns and passes with 35 unique bins: six additional lane-count bins and seven additional mask-pair bins beyond one pattern's 22 bins.

The trace prints masks most-significant lane first, so lane 0 is the least-significant bit on the right. For example, at PC `0x80000108`, pattern 0
reported then=`0b0001`, else=`0b1110`; pattern 1 reported then=`0b1110`,
else=`0b0001`. Each of the seven sites produced 128 events in these runs.

These bins distinguish the observed lane identities for this four-thread
configuration. Each site produced one mask pair per pattern in this workload; the results do not yet show broader mask diversity across input data or
configurations.

## Pattern-2 divergent-mask sweep

Pattern 2 cycles through all 14 nonuniform lane masks for the four-thread
configuration. Every depth passed the host-reference check. At depth 8, each of
the seven split sites recorded all 14 then/else mask pairs, with 128 events per
site. The Rust integration test passed with 127 unique bins.

| Pattern | Depth | Cycles | Unique bins |
|---:|---:|---:|---:|
| 2 | 1 | 22,326 | 0 |
| 2 | 2 | 27,743 | 19 |
| 2 | 3 | 33,242 | 37 |
| 2 | 4 | 38,653 | 55 |
| 2 | 5 | 43,999 | 73 |
| 2 | 6 | 49,410 | 91 |
| 2 | 7 | 54,891 | 109 |
| 2 | 8 | 60,179 | 127 |

These are single-run cycle observations for this kernel and configuration.

## SIMX single-lane misrouting mutation matrix

Reproduce the matrix from the WSL research checkout after installing the
experimental test in the Vortex checkout:

```bash
cd $RESEARCH_ROOT
bash experiments/vortex/run_mask_mutation_matrix.sh
```

A reusable harness, `experiments/vortex/run_mask_mutation_matrix.sh`, generated
56 deterministic mask-routing mutants. For each of the 14 nonuniform
four-thread then masks (`0001` through `1110`), it flips each of the four
lane classifications once, moving that lane from then to else or else to then.
Each mutant was tested at depth 8 with patterns 0, 1, and 2: 168 simulator runs
in total. A result mismatch reported by the host-reference checker marks a
mutant as detected; an untriggered mutant is counted as not reached, not as a
survivor.

| Test pattern(s) | Mutants reached | Reached and detected | Not reached |
|---|---:|---:|---:|
| 0 | 28/56 | 28/28 | 28/56 |
| 1 | 28/56 | 28/28 | 28/56 |
| 0 or 1, combined | 40/56 | 40/40 | 16/56 |
| 2 | 56/56 | 56/56 | 0/56 |

Pattern 2 activated and detected every mutation in this generated family. The
two fixed patterns together did not activate 16 cases. The CSV contains one
row per mutant and pattern, including activation count, output mismatch count,
classification, and process exit status:
`experiments/vortex/mutation_matrix.csv`. The costed rerun uses the same
schema plus instruction and cycle columns.

These 56 cases are systematic variants of one SIMX-side lane-misrouting
operator, not 56 independent implementation defects. The harness temporarily
injects that operator into `sim/simx/wctl_unit.cpp`, rebuilds the SIMX runtime,
runs the existing kernel with its host-reference check, and restores the source,
object, and shared library on exit. Reported mismatch text is used to classify
detection because large mismatch counts can wrap the process exit status.
Pattern 2's full activation is expected from its construction to cycle through
all 14 nonuniform masks. This is controlled evidence that the mask sweep reaches
the targeted input space; it is not an RTL mutation campaign or evidence of
fault coverage across other Vortex configurations.

### Initial costed rerun (superseded by the seeded-schedule rerun below)

The mutation matrix was rerun from Vortex revision `1cd71c4` using the same
four-thread SIMX configuration. The rerun records retired instructions and
cycles for every mutant/pattern execution. Its raw output is
`experiments/vortex/mutation_matrix_simx_costs.csv`; the clean-kernel baseline
is `experiments/vortex/simx_baseline_rerun.csv`. Recompute the suite summary
with:

```bash
RESULT_CSV="$RESEARCH_ROOT/experiments/vortex/mutation_matrix_simx_costs.csv" \
  VORTEX_ROOT="$VORTEX_ROOT" bash experiments/vortex/run_mask_mutation_matrix.sh
python3 experiments/vortex/analyze_mask_mutations.py
```

The clean-kernel baseline can be reproduced separately from the Vortex build
directory:

```bash
cd "$VORTEX_ROOT/build"
for p in 0 1 2; do
  ./ci/blackbox.sh --driver=simx --cores=2 --app=coverage_diverge \
    --perf=1 --args="-n16 -d8 -p$p"
done
```

Patterns 0 and 1 each detected 28 of 56 variants. As a two-pattern suite,
they detected 40; 16 variants were not activated by either pattern. Pattern 2
detected all 56. Summing the measured cycles for all executions in each suite
gives 9,896,338 cycles for patterns 0+1 (112 executions; 176,720 cycles per
mutant suite case on average) and 6,255,288 cycles for pattern 2 (56
executions; 111,702 cycles per mutant suite case). In this run, the exhaustive
suite detected 16 more variants and used 36.8% fewer simulator cycles per
mutant suite case than the two fixed-pattern suite.

This is a measured comparison for the generated 56-variant operator, not an
estimate of general defect detection. It is based on one run per mutant and
pattern, with the fault-injection hook enabled; repeat campaigns and other
fault families are needed to assess variability and generality. The result
must not be described as equal-budget coverage or a general mutation score.

## RTLSIM baseline validation

The unmodified depth-8 kernel was also run through the RTL simulator with
patterns 0, 1, and 2. All three runs passed the host-reference result check.
Each processed 512 points and counted 896 divergent events. Patterns 0 and 1
reported 5,376 total branches; pattern 2 reported 6,400. The exact instruction,
cycle, and IPC counters are in experiments/vortex/rtlsim_baseline.csv.
These single runs confirm functional agreement for this test on RTLSIM; they
are not repeated performance measurements.

## RTL fault-injection attempts

Two initial control-path RTL faults were tried: flipping lane 0's split
predicate for a selected mask, and clearing lane 0 from the reconvergence join
mask. Pattern 0 did not finish within 120 and 60 seconds, respectively. A later
unmutated control showed that the temporary setup paired a rebuilt RTLSIM core
with a copied prebuilt driver; that mismatched isolated setup also timed out.
These initial attempts are therefore harness failures, not evidence about the
mutants. Their results are excluded from mutation scores. The original RTL was
restored and temporary builds were removed.

## RTLSIM ALU-result fault experiment

The isolated build setup was corrected to build the simulator core and matching
runtime driver together with:

    make -C build/sw/runtime/rtlsim DESTDIR=<temporary-directory> all

An unmodified control passed through that matched pair. It processed 256 points
in the configured RTLSIM device.

The mutant flipped bit 0 of lane 0's ALU result at the compiled depth-5
arithmetic PCs 0x80000310 and 0x80000318. The RTL compared internal PCs using
from_fullPC; a MUT_HIT marker confirmed activation. At depth 8, patterns 0, 1,
and 2 each produced 128 mutant-hit events and each failed the host reference
check with 64 mismatches (exit code 64). A repeat of pattern 0 printed the
explicit 64-error summary. The original RTL was restored after every run.

This is one successful, synthetic, PC- and lane-specific ALU datapath fault
test. All three patterns detected it, so it does not distinguish their
sensitivity to this fault. It should be reported separately from the abstract
56-case lane-misrouting mutation matrix; neither result alone establishes
general RTL fault coverage.

## Mask-targeted RTL fault comparison

A second ALU mutant flips lane 0 result bit 0 only at the two depth-5
arithmetic PCs and only when the active thread mask is 0101. The targeted PC
check uses the RTL's from_fullPC conversion. This isolates whether a test
pattern reaches a particular active-lane configuration.

The matched RTLSIM build processed 256 points per run. Pattern 0 and pattern 1
each had zero mutant activations and passed the host-reference check. Pattern 2
had nine activations and nine reference mismatches in each of three runs:

| Pattern | Repetition | Mutant activations | Reference mismatches | Result |
|---:|---:|---:|---:|:---|
| 0 | 1 | 0 | 0 | Passed |
| 1 | 1 | 0 | 0 | Passed |
| 2 | 1 | 9 | 9 | Failed |
| 2 | 2 | 9 | 9 | Failed |
| 2 | 3 | 9 | 9 | Failed |

The reproducible harness is experiments/vortex/run_mask_targeted_rtlsim_mutant.sh.
It builds the RTLSIM core and matching runtime driver together in a temporary
directory, runs the cases above, checks activation and result counts, and
restores the original RTL automatically. Its hard-coded PCs match the compiled
kernel used here and must be revalidated if that kernel changes.

For this targeted fault, pattern 2 detected a fault that patterns 0 and 1 did
not activate. This is evidence for this specific synthetic mask-gated ALU
fault and workload, not a general RTL fault-coverage rate. Broader mutation
families and more workloads are needed for that claim.


## Branch-site mask-gated mutation matrix

To test whether the mask-pattern sweep activates faults at multiple nested
branch sites, a separate ALU-result mutant was injected at each source level
2 through 8. Each mutant flips bit 0 of lane 0's ALU result only when the
current PC is one of that level's two arithmetic branch-body instructions and
the active warp mask is exactly `0101`. Mutants were isolated: one branch
level was modified per build, and the original RTL was restored between builds.
The RTLSIM core and its matching runtime driver were built together for each
mutant. All runs used depth 8 and 256 points.

| Level | Split PC | Pattern 0 hits/errors | Pattern 1 hits/errors | Pattern 2 hits/errors |
|---:|---:|---:|---:|---:|
| 2 | `0x80000180` | 0 / 0 | 0 / 0 | 9 / 9 |
| 3 | `0x80000200` | 0 / 0 | 0 / 0 | 9 / 9 |
| 4 | `0x80000284` | 0 / 0 | 0 / 0 | 9 / 9 |
| 5 | `0x80000308` | 0 / 0 | 0 / 0 | 9 / 9 |
| 6 | `0x8000038c` | 0 / 0 | 0 / 0 | 9 / 9 |
| 7 | `0x80000410` | 0 / 0 | 0 / 0 | 9 / 9 |
| 8 | `0x80000494` | 0 / 0 | 0 / 0 | 9 / 9 |

For all seven sites, patterns 0 and 1 passed without activating the injected
fault. Pattern 2 activated it nine times and produced nine host-reference
mismatches, so all seven mutants were detected. The per-run data are preserved
in `experiments/vortex/branch_site_mutation_matrix.csv`.

This is a controlled proof-of-concept for one injected fault model: a lane-0
ALU result bit flip guarded by one exact four-lane mask at selected branch
bodies. It does not estimate coverage of arbitrary Vortex RTL faults. Each
result was one run; the repeated targeted depth-5 experiment documented above
is separate. PC values are specific to this compiled test binary.


## Active-mask diversity at each branch site

A second per-site mutation accepted any partial active mask that included lane 0
(the branch-body PC pair remained specific to one level). The mutant flipped
lane 0's ALU result bit 0. This differs from the earlier exact-`0101` gate:
it detects mask diversity at the ALU result point while leaving lane 0 eligible
for activation.

Each run used 256 points. At every site, all three patterns activated the
mutant 64 times and produced 64 reference mismatches. Patterns 0 and 1 each
reached one distinct active mask at the mutant point; pattern 2 reached seven:

| Level | Split PC | Pattern 0/1 mask | Pattern 2 distinct masks |
|---:|---:|:---:|---:|
| 2 | `0x80000180` | `0011` | 7 |
| 3 | `0x80000200` | `0001` | 7 |
| 4 | `0x80000284` | `1101` | 7 |
| 5 | `0x80000308` | `1011` | 7 |
| 6 | `0x8000038c` | `0111` | 7 |
| 7 | `0x80000410` | `1101` | 7 |
| 8 | `0x80000494` | `1011` | 7 |

Pattern 2 reached all seven partial four-lane masks that include lane 0:
`0001`, `0011`, `0101`, `0111`, `1001`, `1011`, and `1101`.
The other seven nonuniform masks exclude lane 0 and are outside this lane-0
fault's activation condition. Per-run counts and observed masks are in
`experiments/vortex/branch_site_mask_sweep.csv`; the reproducible script is
`experiments/vortex/run_branch_site_mask_sweep.sh`.

This sweep shows greater active-mask diversity for pattern 2 at these
instrumented result points, but all three patterns detected this broader
fault. Combined with the exact-`0101` results, the experiments distinguish
mask diversity from fault detection: pattern 2 reached more masks and uniquely
activated the exact-`0101` mutant, while a fault enabled for any lane-0-active
partial mask was detected by every pattern. The conclusions remain limited to
the injected ALU bit flip, tested PCs, 4-lane configuration, and workload.


## Split-predicate control-fault check

To check a different fault class from ALU result corruption, a SIMX-only
mutation inverted lane 0's predicate at the depth-2 `vx_split` instruction
(PC `0x80000180`). The mutant ran at the split instruction whenever lane 0
was active. All patterns used 512 points; the observed active mask was
`1111` at every hit.

| Pattern | Repetitions | Activations/run | Mismatches/run | Result |
|---:|---:|---:|---:|:---|
| 0 | 3 | 128 | 128 | Detected in all 3 |
| 1 | 3 | 128 | 128 | Detected in all 3 |
| 2 | 3 | 128 | 128 | Detected in all 3 |

All nine runs produced the same counts. This control-flow fault was detected
equally by all three patterns. Since the split's active mask was full for all
hits, this experiment does not test pattern-specific mask activation. It shows
that the reference check detects this lane-specific split-predicate inversion
in this test, while the earlier exact-mask ALU fault distinguishes pattern 2
from patterns 0 and 1.

The reproducible SIMX mutation harness and per-run counts are
`experiments/vortex/run_split_predicate_mutation.sh` and
`experiments/vortex/split_predicate_mutation.csv`. The script rebuilds SIMX,
restores the original `wctl_unit.cpp` on exit, and depends on the current
kernel's split PC; re-check the disassembly if the kernel changes.


## Input-size scaling for the exact-mask mutant

The level-2 ALU mutant guarded by exact active mask `0101` was rerun at three
input sizes. The site, kernel, and mutation were unchanged; only `-n` changed.
With the one-core RTLSIM build, the runs processed 128, 256, and 512 points.

| Points | Pattern 0 hits/errors | Pattern 1 hits/errors | Pattern 2 hits/errors |
|---:|---:|---:|---:|
| 128 | 0 / 0 | 0 / 0 | 4 / 4 |
| 256 | 0 / 0 | 0 / 0 | 9 / 9 |
| 512 | 0 / 0 | 0 / 0 | 18 / 18 |

Patterns 0 and 1 passed without activating the exact-mask mutant at all three
sizes. Pattern 2 activated and detected it at every size, with the hit count
increasing as the number of work items increased. The per-run results and
reproduction script are `experiments/vortex/size_scaling_mask_mutation.csv`
and `experiments/vortex/run_size_scaling_mask_mutation.sh`.

This is an input-size scaling check for one kernel, one branch site, and one
synthetic fault. It is not a separate application workload, and the smaller
and larger cases have not yet been repeated for cycle or activation-rate
variability.


## Second workload: original `diverge` regression

The original `tests/regression/diverge` application was used as a second
workload. Its unmodified RTLSIM run passed at depth 8 with 256 points. A
separate mutant flipped lane 2's ALU result bit 0 at the `addi +7` branch body
(PC `0x800000ac`) only when the active mask was `0100`. Five mutant runs,
using the same rebuilt mutant, each activated it once and produced one
host-reference mismatch; the application reported failure as expected.

| Workload case | Repetitions | Points/run | Activations/run | Mismatches/run | Outcome |
|:---|---:|---:|---:|---:|:---|
| Baseline `diverge` | 1 | 256 | 0 | 0 | Passed |
| Mutated `diverge` | 5 | 256 | 1 | 1 | Detected in all 5 |

All five mutant runs were executed against the same rebuilt mutant and each
reported one activation and one reference mismatch. The per-run records are in
`experiments/vortex/diverge_workload_mutation.csv`. The reproduction script is
`experiments/vortex/run_diverge_workload_mutation.sh`; it builds the RTLSIM
core and matching runtime driver together and restores the ALU RTL on exit. The
compiled instruction PC is build-specific and must be checked against the
current ELF disassembly.

This adds reproducible evidence on a second kernel workload for the same
synthetic ALU-result fault class. The original `diverge` application has no
branch-pattern option, so this does not compare patterns on that workload.
Additional fault models and workloads are still needed.

## LSU store-data corruption fault

A third fault class was tested by flipping bit 0 of lane 0's store payload at
the coverage kernel's final output store (compiled PC `0x80000094`). The
injection occurs in SIMX's LSU while it packages the lane's store data, before
the request proceeds through the cache and memory path. The unmodified baseline
passed with 512 points. The same built mutant was then run three times for
each branch pattern:

| Pattern | Repetitions | Corruptions/run | Reference mismatches/run | Result |
|---:|---:|---:|---:|:---|
| 0 | 3 | 128 | 128 | Detected in all 3 |
| 1 | 3 | 128 | 128 | Detected in all 3 |
| 2 | 3 | 128 | 128 | Detected in all 3 |

All nine mutant runs were detected. Per-run results and the reversible harness
are in `experiments/vortex/store_data_mutation.csv` and
`experiments/vortex/run_store_data_mutation.sh`. The script restores
`sim/simx/lsu_unit.cpp` on exit. The target PC depends on the compiled kernel
and should be rechecked in the disassembly after kernel changes.

This models corruption of store data at the SIMX LSU boundary. It does not
model a fault inside a cache, DRAM controller, or physical memory cell, and the
single output lane means it does not compare memory-fault activation across
different lane masks.


## LSU load-response data corruption fault

A load-side fault was tested on the original `diverge` workload by flipping bit
0 of lane 0's loaded source word in SIMX's LSU response formatter. The target
was the initial `lw` at compiled PC `0x80000054`. The unmodified RTLSIM/SIMX
baseline passed at 256 points. Five mutant SIMX runs each recorded 64 corrupted
load responses and 64 host-reference mismatches:

| Repetitions | Points/run | Corruptions/run | Reference mismatches/run | Result |
|---:|---:|---:|---:|:---|
| 5 | 256 | 64 | 64 | Detected in all 5 |

The per-run data and reversible harness are
`experiments/vortex/load_data_mutation.csv` and
`experiments/vortex/run_load_data_mutation.sh`. The harness restores
`sim/simx/lsu_unit.cpp` on exit. The load PC depends on the compiled kernel;
verify it in the ELF dump if that kernel changes.

This injects corruption at the SIMX load-response boundary. It does not model
a cache-array, DRAM-controller, or physical-cell defect.


## SIMX / RTLSIM clean-run cross-check

The unmodified depth-8 coverage kernel was run once per pattern on both
simulators with two cores and 512 points. All four runs passed the host
reference check. Instruction and branch counters agreed between simulators:

| Pattern | Instructions | Total branches | Divergent events | SIMX cycles | RTLSIM cycles |
|---:|---:|---:|---:|---:|---:|
| 0 | 26,656 | 5,376 | 896 | 48,047 | 45,411 |
| 2 | 36,256 | 6,400 | 896 | 60,179 | 57,461 |

Cycle counts are reported separately because SIMX and RTLSIM are different
simulator models; these single runs are not a cross-model performance
comparison. Raw outputs are in `/tmp/coverage_simx_p0.log`,
`/tmp/coverage_simx_p2.log`, `/tmp/coverage_rtlsim_p0.log`, and
`/tmp/coverage_rtlsim_p2.log` in the WSL environment. The comparison checks
functional results and architectural counters for these two cases only.


## Eight-thread-per-warp cross-configuration check

The depth-8 workload was rerun with two cores and eight threads per warp, using
patterns 0 and 2 on both SIMX and RTLSIM. All four runs processed 1,024 points
and passed the host-reference check.

| Simulator | Pattern | Points | Instructions | Total branches | Divergent events | Cycles |
|---|---:|---:|---:|---:|---:|---:|
| SIMX | 0 | 1,024 | 26,656 | 5,376 | 896 | 49,212 |
| SIMX | 2 | 1,024 | 36,256 | 6,400 | 896 | 61,399 |
| RTLSIM | 0 | 1,024 | 26,656 | 5,376 | 896 | 46,616 |
| RTLSIM | 2 | 1,024 | 36,256 | 6,400 | 896 | 58,639 |

SIMX and RTLSIM agree on instruction, branch, and divergence counts for each
pattern. Their cycle counts are recorded separately and are not treated as a
cross-model performance comparison. Pattern 2 still sweeps 14 nonuniform masks
within each group of four IDs; this check does not cover the full set of 254
nonuniform eight-lane masks.

The source configuration was set to eight threads while the alternate build and
test flags were generated, then restored to four threads. The run harness
asserted the expected 1,024-point workload before recording any result. Raw
per-run output was kept in the harness temporary directory and removed when it
exited; the summary CSV is
`experiments/vortex/thread_count_crosscheck.csv`.


For pattern 2, a SIMX trace on this 8-thread build confirmed seven distinct
then/else mask pairs at each of the seven divergent split PCs. Each PC still
recorded 128 events. The generator supplies masks over four-ID groups, so an
eight-lane warp combines two adjacent 4-lane patterns; this is not an
exhaustive sweep of the 254 nonuniform eight-lane masks. The trace result is a
targeted cross-check of the current generator, not evidence of full 8-lane mask
coverage.


## Exhaustive 8-lane mask sweep (pattern 3)

Pattern 3 was added as a separate 8-lane predicate path. It enumerates masks
1 through 254 in groups of eight IDs, excluding the all-zero and all-one masks.
With two cores, four warps per core, eight threads per warp, and -n32, the
test processed 2,048 points (256 warp groups). SIMX and RTLSIM both passed the
host-reference check and matched on instruction and branch counters.

| Simulator | Points | Instructions | Total branches | Divergent events | Cycles |
|---|---:|---:|---:|---:|---:|
| SIMX | 2,048 | 59,680 | 9,216 | 1,792 | 96,620 |
| RTLSIM | 2,048 | 59,680 | 9,216 | 1,792 | 92,953 |

The SIMX trace attributed 256 events to each of seven static split PCs. Every
site observed all 254 distinct then/else mask pairs. The Rust integration test
passed with 1,835 unique bins: one divergence bin, seven split-site bins, 49
then/else lane-count bins, and 1,778 mask-pair bins.

This establishes exhaustive mask-pair coverage for the seven tested split
sites in this specific 8-thread configuration and workload. It does not
establish coverage of every branch structure or simulator configuration. Cycle
counts remain model-specific and are not a direct performance comparison.

Reproduce with:

bash $RESEARCH_ROOT/experiments/vortex/run_8lane_mask_sweep.sh

The harness temporarily switches the source configuration from four to eight
threads, configures the alternate build, runs both simulators, checks the
expected points and counters, verifies 254 mask pairs at each SIMX split site,
writes summary CSVs, and restores the source configuration. Results are in
experiments/vortex/pattern3_8lane_results.csv and
experiments/vortex/pattern3_8lane_sites.csv.


## Exhaustive 16-lane mask sweep

The Vortex configuration supports 16 threads per warp. Pattern 4 selects one
of all 65,534 nonuniform 16-bit lane masks for each consecutive 16 task IDs.
The SIMX run used two cores, four warps per core, depth 8, and 1,048,576
points. This provides 65,536 warp groups, so every mask was observed at all
seven split sites; two masks were repeated.

| Simulator | Points | Instructions | Total branches | Divergent events | Cycles | Result |
|---|---:|---:|---:|---:|---:|---|
| SIMX | 1,048,576 | 15,269,920 | 2,359,296 | 458,752 | 24,919,572 | Passed |
| RTLSIM smoke | 2,048 | 29,856 | 4,608 | 896 | 51,368 | Passed |

Each of the seven static split PCs produced 65,536 events and all 65,534
distinct then/else mask pairs. The host reference derives each selected lane
independently with division and modulo rather than reusing the device helper;
its result check passed on both simulators. Per-site
results are in experiments/vortex/pattern4_16lane_sites.csv; aggregate
counters are in experiments/vortex/pattern4_16lane_results.csv.

The exhaustive mask run was completed on SIMX. The RTLSIM smoke case used 2,048
points (128 warp groups), passed the host-reference check, and reported 896
divergent events. A matching full-size RTLSIM run did not complete during this
experiment, so exhaustive 16-lane coverage remains SIMX-only. The 16-thread
width is restored to four in the source configuration after the run.

Reproduce with:

    bash $RESEARCH_ROOT/experiments/vortex/run_16lane_mask_sweep.sh

The harness configures a separate build-threads16 tree, runs exhaustive SIMX
coverage and the RTLSIM smoke case, checks their host references and proportional
divergence count,
writes the two CSV files, and restores the source configuration on exit.

## Host-reference sensitivity check

To check that the independent host oracle can detect a lane-selection error, a
throwaway device-source mutation shifted the selected lane index by one. The
512-point SIMX control run then reported 98 incorrect outputs and failed the
host-reference check. After restoring the canonical source and forcing the
application to rebuild, the same control passed. This single mutation check
validates detection of a representative lane-mapping fault; it is not a
comprehensive mutation campaign. The exhaustive pattern-4 results above were
collected with the unmutated source.

A subsequent full-size RTLSIM attempt was capped at 180 seconds. With
`-n8192`, that build reported 262,144 points and emitted a command-retirement
warning before the cap; it produced no final performance counters or `PASSED!`
result. This is an incomplete run, not a datapoint, and it does not reproduce
the 1,048,576-point SIMX workload. At the time of that attempt, the only completed RTLSIM case was the
2,048-point smoke check; later scaling observations follow below.

## RTLSIM 16-lane workload scaling

A bounded RTLSIM scaling check used the pattern-4 depth-8 kernel in the
16-thread build. Runs at 512, 2,048, and 8,192 reported points passed; the
8,192-point case was repeated three times with identical counters and cycles.
At the next tested size, 32,768 points, the run exceeded a 45-second cap. A
separate attempt using `-n8192` reported 262,144 points and exceeded a
180-second cap before final counters or `PASSED!`. Timed-out rows are censored
runtime observations, not performance measurements.

| Requested `-n` | Reported points | Divergent events | Cycles | Outcome |
|---:|---:|---:|---:|:---|
| 16 | 512 | 224 | 16,863 | Passed |
| 64 | 2,048 | 896 | 52,067 | Passed |
| 256 | 8,192 | 3,584 | 192,117 | Passed; identical in 3 repeats |
| 1,024 | 32,768 | n/a | n/a | Exceeded 45-second cap |
| 8,192 | 262,144 | n/a | n/a | Exceeded 180-second cap |

Per-run observations are saved in
`experiments/vortex/rtlsim_16lane_scaling.csv`. The tested RTLSIM build and
host provide a practical limit for this workload; this scaling check does not
replace a completed 16-lane exhaustive RTLSIM run.

## RTLSIM mask-shard pilot

To check the range-based pattern-4 path, the first and final 128-mask shards
were run on both simulators. All four 2,048-point runs passed the host-reference
check and reported 896 divergent events. SIMX trace confirmed 128 distinct
then/else mask pairs at each of the seven split sites for each shard. An
out-of-range request (-s65534 -m2) was rejected before device launch.

| Simulator | Mask IDs | Points | Divergent events | Cycles | Split sites traced | Distinct pairs/site | Result |
|---|---:|---:|---:|---:|---:|---:|:---|
| RTLSIM | 1-128 | 2,048 | 896 | 44,915 | n/a | n/a | Passed |
| SIMX | 1-128 | 2,048 | 896 | 45,593 | 7 | 128 | Passed |
| RTLSIM | 65,407-65,534 | 2,048 | 896 | 44,644 | n/a | n/a | Passed |
| SIMX | 65,407-65,534 | 2,048 | 896 | 45,842 | 7 | 128 | Passed |

The pilot validates the shard boundaries and host-reference path, but it covers
only 256 of the 65,534 nonuniform masks. It is not an exhaustive RTLSIM result.
The reproducible pilot is
experiments/vortex/run_16lane_rtlsim_shard_pilot.sh; its per-run summary is
experiments/vortex/rtlsim_16lane_shard_pilot.csv. It requires an already
configured 16-thread build and the SIMX trace patch.

A larger RTLSIM shard covering mask IDs 1-4,096 (65,536 reported points)
was also attempted with a 120-second cap. It emitted a command-retirement
warning and did not produce final counters or PASSED!, so the attempt was
terminated and excluded from measurements. This confirms that the passing
128-mask boundary pilot does not imply that larger shards are practical.

## Looped exhaustive 16-lane mask sweep

Pattern 5 keeps one 16-lane warp active while it iterates over a selected mask
range. At each of eight static branch sites, the kernel rotates the lane bit
being tested. This produces a distinct then/else lane-mask pair for every
nonuniform mask at every site. The host reference independently computes each
lane's accumulated result, and the test passed its output check.

The full run used a build configured for 16 threads, one launched warp
(`-n1`), depth 8, and the default mask range 1 through 65,534:

```bash
cd $VORTEX_ROOT/build-threads16
VX_SIMX_SPLIT_TRACE=1 ./ci/blackbox.sh --driver=simx --cores=1 \
  --app=coverage_diverge --perf=1 --args="-n1 -d8 -p5"
```

SIMX passed with 524,272 divergent events. Each of the eight static split PCs
recorded 65,534 events and 65,534 distinct then/else mask pairs. Total
performance counters were 2,162,631 branches, 7,667,563 instructions, and
117,438,380 cycles. Per-site counts are in
`experiments/vortex/loop_pattern5_simx_full_sites.csv`; the full trace was
saved as `experiments/vortex/loop_pattern5_simx_full.log`.

| Split PC | Events | Distinct mask pairs |
|---|---:|---:|
| `0x800001ac` | 65,534 | 65,534 |
| `0x800001d8` | 65,534 | 65,534 |
| `0x80000204` | 65,534 | 65,534 |
| `0x80000238` | 65,534 | 65,534 |
| `0x8000026c` | 65,534 | 65,534 |
| `0x800002a0` | 65,534 | 65,534 |
| `0x800002d4` | 65,534 | 65,534 |
| `0x80000308` | 65,534 | 65,534 |

RTLSIM passed the same kernel over masks 1 through 128 with 1,024 divergent
events and 214,245 cycles. The full 65,534-mask RTLSIM run was stopped by a
300-second timeout after the command processor warned that it had not retired
a command in 10 seconds. It did not produce a completion result. Thus, this
looped design establishes exhaustive per-site mask coverage on SIMX and
correctness on a bounded RTLSIM shard; exhaustive RTLSIM coverage remains
unverified.

Reproduce the RTLSIM shard with:

```bash
cd $VORTEX_ROOT/build-threads16
./ci/blackbox.sh --driver=rtlsim --cores=1 --app=coverage_diverge \
  --perf=1 --args="-n1 -d8 -p5 -s1 -m128"
```

The earlier pattern-4 exhaustive run has seven static sites; pattern 5 adds an
eighth explicitly divergent site. Their site counts should not be compared as
if they were the same compiled kernel.

A depth-1 full-range RTLSIM attempt was also stopped at 180 seconds with the
same command-retirement warning and no final counters. Since this case has
only one active divergent site, the result indicates that iterating over the
full mask range is itself costly in RTLSIM; it does not isolate every source
of the eight-site run's runtime.

## Independent host-oracle cross-check

The host reference for the four- and eight-lane paths was changed to derive
lane selection with division and modulo rather than calling the device-side
mask helpers. The 16-lane reference already used an independent arithmetic
formulation. The experimental source was synchronized into the Vortex test
tree and both copies compared equal.

After this change, bounded correctness runs passed for four-lane pattern 2
(SIMX, 512 points), eight-lane pattern 3 (SIMX, 2,048 points), sixteen-lane
pattern 4 over masks 1–128 (SIMX, 2,048 points), and looped pattern 5 over
masks 1–128 (RTLSIM, 64 points). These checks validate the separate oracle
paths on representative workloads; they do not replace rerunning every full
exhaustive experiment after the oracle-only change.

## Seeded four-lane schedule comparison

The current test adds pattern 6, a deterministic seeded schedule that hashes
each four-ID group to one of the 14 nonuniform four-lane masks. The host oracle
uses a separate arithmetic formulation. At depth 8, seeds 1 through 5 each
passed the output check and produced 127 unique coverage bins: seven split
sites, 21 then/else population bins, 98 ordered mask-pair bins, and the
divergence bin. Each seed generated all 14 mask pairs at each site for this
512-point workload.

Clean-kernel baseline measurements from the same current source/build were:

| Pattern | Seed | Instructions | SIMX cycles | Result |
|---:|---:|---:|---:|---|
| 0 | 0 | 27,424 | 49,553 | Passed |
| 1 | 0 | 27,424 | 49,553 | Passed |
| 2 | 0 | 37,024 | 61,624 | Passed |
| 6 | 1 | 40,992 | 60,829 | Passed |
| 6 | 2 | 40,992 | 60,965 | Passed |
| 6 | 3 | 40,992 | 60,769 | Passed |
| 6 | 4 | 40,992 | 60,969 | Passed |
| 6 | 5 | 40,992 | 60,879 | Passed |

The costed mutation campaign ran each of the same 56 single-lane SIMX
misrouting variants under patterns 0, 1, and 2, and under pattern 6 with each
of seeds 1 through 5. The raw 448-row result is
`experiments/vortex/mutation_matrix_simx_random.csv`; the corresponding clean
baselines are in `experiments/vortex/simx_baseline_random_rerun.csv`. Rebuild
the summary with:

```bash
RANDOM_SEEDS=5 \
  RESULT_CSV="$RESEARCH_ROOT/experiments/vortex/mutation_matrix_simx_random.csv" \
  VORTEX_ROOT="$VORTEX_ROOT" bash experiments/vortex/run_mask_mutation_matrix.sh
python3 experiments/vortex/analyze_mask_mutations.py
```

| Suite | Detected | Not reached | Mutant runs | Total SIMX cycles | Mean cycles per mutant case |
|---|---:|---:|---:|---:|---:|
| Pattern 0 | 28/56 | 28/56 | 56 | 5,109,260 | 91,236.8 |
| Pattern 1 | 28/56 | 28/56 | 56 | 4,881,441 | 87,168.6 |
| Patterns 0+1 | 40/56 | 16/56 | 112 | 9,990,701 | 178,405.4 |
| Pattern 2, exhaustive | 56/56 | 0/56 | 56 | 6,298,120 | 112,466.4 |
| Pattern 6, seed 1 | 56/56 | 0/56 | 56 | 5,981,975 | 106,821.0 |
| Pattern 6, seed 2 | 56/56 | 0/56 | 56 | 6,039,469 | 107,847.7 |
| Pattern 6, seed 3 | 56/56 | 0/56 | 56 | 6,052,498 | 108,080.3 |
| Pattern 6, seed 4 | 56/56 | 0/56 | 56 | 6,003,464 | 107,204.7 |
| Pattern 6, seed 5 | 56/56 | 0/56 | 56 | 6,018,919 | 107,480.7 |

Each seeded run detected all 56 generated variants. The best observed seeded
run used 5.0% fewer simulator cycles than pattern 2 and 40.1% fewer than the
two-pattern suite. Those figures are per campaign on this simulator and fault
family; the comparison is not normalized to equal cycle budgets. The five
seeds are deterministic schedules, not five independently sampled test
campaigns. Since the harness deliberately mutates SIMX's lane-routing decision
for one exact mask and lane, these results measure adequacy against that
operator only. They do not establish a general mutation score or show
discovery of naturally occurring defects.

A second 224-execution campaign reran patterns 0, 1, and 2 and pattern 6 with
seed 1. It reproduced all per-mutant outcomes and cycle counts exactly. The
repeat data are preserved in
`experiments/vortex/mutation_matrix_simx_repeat.csv`. This checks run
repeatability in the pinned simulator; it does not add new fault variants or
independent random samples.
