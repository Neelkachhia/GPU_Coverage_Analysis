# Vortex SIMX Divergence Coverage Experiment

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
git -C ~/projects/vortex apply ~/projects/research/patches/vortex-simx-split-trace.patch
cd ~/projects/vortex/build
make -C sim/simx

```

Then run the depth-8 case from the build directory:

```bash
cd ~/projects/vortex/build
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
cp -a ~/projects/research/experiments/vortex/coverage_diverge \
  ~/projects/vortex/tests/regression/
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
