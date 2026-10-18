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
