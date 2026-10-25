# From Branch Outcomes to Lane Masks: Measuring SIMT Divergence Coverage for GPU RTL Tests

**Manuscript status:** research draft for internal review; not submission-ready
**Authors and affiliations:** to be completed by the research team

## Abstract

GPU test suites can execute a divergent branch without exercising the range of
lane populations and lane identities that determine how a SIMT implementation
splits and reconverges a warp. We study an execution-derived coverage measure
that records, for each dynamic divergent split, the compiled instruction PC and
the ordered then/else lane masks. We implement the measure in the open-source
Vortex GPU simulator and use generated kernels to enumerate nonuniform masks
for 4-, 8-, and 16-lane warps. We then compare fixed and mask-sweeping tests
against controlled lane-routing and RTL datapath mutations. On Vortex, the
16-lane SIMX experiment observes all 65,534 nonuniform masks at each of seven
static split sites; a separate loop-based experiment does so at eight sites.
For a targeted exact-mask ALU mutation, the exhaustive four-lane test activates
and detects the mutant, while either fixed pattern does not. For a different
lane-0 mutation that accepts any eligible partial mask, all patterns detect
the fault, even though the sweep reaches more masks. These results show that
lane-mask coverage can expose test-input gaps hidden by branch reachability or
lane-count coverage in this case study. They do not establish a general fault
coverage rate: the workloads are synthetic, the mutations are deliberately
targeted, and exhaustive 16-lane enumeration was completed on SIMX rather than
RTLSIM. We present the method as a reproducible measurement prototype and
identify the additional workloads, independent fault models, and platform
validation required for a broader claim.

**Keywords:** SIMT, GPU verification, functional coverage, lane masks,
mutation testing, Vortex

## 1. Introduction

SIMT processors execute groups of lanes under a shared instruction stream, but
control-flow divergence creates subsets of active lanes and later reconverges
them. A branch counter or a record that a static branch was reached says little
about which lanes were active at the split. Two test inputs may reach the same
branch and exercise the same then/else lane counts while selecting different
lane identities. A defect conditional on a particular active-lane mask can
therefore remain dormant despite apparently good branch coverage.

This paper investigates a narrow question: **does recording and deliberately
varying the lane masks at dynamic divergent split sites reveal test-input gaps
that branch-site and lane-count coverage alone miss?** We add opt-in trace
records to the Vortex SIMX warp-control model. Each record contains the
compiled split PC, warp identifier, then/else population counts, and the
ordered lane masks. A Rust runner converts these events into per-PC coverage
bins. Parameterized kernels enumerate nonuniform masks at several warp widths;
controlled mutations test whether additional mask diversity changes
activation and detection for selected faults.

Our results support a limited empirical observation, not a universal adequacy
criterion. For the four-lane kernel, the two fixed patterns each detect 28 of
56 generated lane-routing mutations; their union detects 40, while the
14-mask sweep detects all 56. For one exact-mask RTL ALU mutant at each of
seven sites, the fixed patterns activate none and the mask sweep detects all
seven. Conversely, a broader lane-0 ALU mutant and a split-predicate mutant
are detected by all patterns. Thus, increasing mask coverage is useful for
exposing certain mask-conditioned gaps, but it does not imply proportionally
better fault detection.

The contributions are:

1. A trace and coverage representation that distinguishes dynamic split-site
   reachability, then/else lane populations, and ordered then/else lane masks.
2. Reproducible Vortex experiments that enumerate every nonuniform mask for
   4-, 8-, and 16-lane configurations at multiple static split sites.
3. A controlled comparison of mask patterns against a small, explicitly
   characterized family of simulator and RTL mutations, including cases where
   extra mask diversity changes activation and cases where it does not.
4. An artifact containing the kernels, harnesses, result summaries, and a
   documented account of incomplete or simulator-limited runs.

We do not claim to introduce GPU code coverage, mutation testing, hardware
fuzzing, or exhaustive mask enumeration in general. Prior GPU software testing
work already studies coverage and seeded faults, and recent work fuzzes GPU
RTL. We position this study as an empirical, mask-level test-adequacy probe for
one open SIMT GPU design and make its scope explicit.

## 2. Background and related work

**GPU kernel test effectiveness.** CLTestCheck measures OpenCL kernel
coverage, seeds faults, and explores work-group schedules, with an evaluation
over 82 kernels [1]. Zhu and Zaidman study mutation testing for GPU programs
and propose GPU-specific mutation operators [2]. Our work shares their use of
coverage and mutation evidence, but observes Vortex warp-control events in the
GPU implementation rather than source-level coverage in application kernels.
The scale and diversity of their workloads also exceed this case study; our
results should not be read as a replacement for those broad evaluations.

**GPU hardware testing.** FuzzGPU generates SIMT programs and performs
differential testing of GPU RTL, including Vortex and Ventus [3]. Its goal is
bug discovery through program generation and an ISA-level oracle. Our current
prototype instead measures a specific execution dimension—ordered lane masks
at divergent split sites—and asks how selected tests activate deliberately
targeted faults. The techniques are complementary: mask bins could inform
input selection or corpus adequacy within a hardware fuzzer. Evaluating that
integration is future work.

**Vortex.** Vortex is an open-source RISC-V GPGPU architecture with software
and simulation infrastructure [4]. We use its SIMX and Verilator-based RTLSIM
flows. SIMX counters are simulator results, not measurements from a physical
GPU or FPGA. RTLSIM runs provide RTL-simulation evidence, but they do not
establish board-level timing or power.

## 3. Measurement and implementation

### 3.1 Coverage event

For a divergent split event at compiled instruction address `pc`, let `T` be
the active lanes selected for the then path and `E` the active lanes selected
for the else path. We record `(pc, wid, |T|, |E|, T, E)`. Lane 0 is bit 0;
the trace prints masks most-significant lane first, so lane 0 is the rightmost
printed bit. Only events for which both path masks are nonempty are emitted.

The prototype derives three bin families from each event: (i) split-site
reachability `pc_split_seen`, (ii) lane-count pair `pc_lanes_|T|_|E|`, and
(iii) ordered mask pair `pc_masks_T_E`. The aggregate divergence counter is
also retained. These are dynamic execution bins tied to a compiled binary;
PCs can change with compiler, source, and build configuration. The bins do not
directly identify source-level branches unless a separate disassembly/source
mapping is maintained.

### 3.2 Test kernels and mask schedules

The experimental `coverage_diverge` application contains nested branch sites
and a host reference check. Patterns 0 and 1 use complementary four-lane
predicates. Pattern 2 enumerates the 14 nonuniform four-lane masks. Pattern 3
enumerates all 254 nonuniform eight-lane masks. Pattern 4 enumerates all
65,534 nonuniform 16-lane masks across work items. Pattern 5 holds a 16-lane
warp active while looping over a mask range and rotates the tested bit across
eight static branch sites. The host-side oracle computes lane selection with
arithmetic division and modulo rather than reusing the device mask helper for
the exhaustive 4-, 8-, and 16-lane paths.

The full pattern-4 run processes 1,048,576 points, corresponding to 65,536
16-lane groups. Therefore every nonuniform mask is observed, with two group
slots repeating masks. The pattern-5 loop covers all 65,534 nonuniform masks
at each of eight sites in a single SIMX workload. Its host oracle separately
computes each lane's accumulated result. Full 16-lane enumeration is not
reported for RTLSIM: only bounded RTLSIM smoke/shard cases completed.

### 3.3 Mutation experiments

We use three classes of controlled fault experiments, keeping their evidence
separate:

* **SIMX lane-routing mutations:** 56 deterministic variants flip one lane's
  then/else classification for each of the 14 nonuniform four-lane masks.
* **Targeted RTL datapath mutations:** synthetic lane-specific ALU result-bit
  flips guarded by selected compiled PCs and active masks. One campaign places
  the same exact-mask condition at each of seven nested sites.
* **Control/data-path controls:** a split-predicate inversion, broader
  lane-0-active ALU mutations, and selected load/store data corruptions.

We distinguish *activation* (the injected condition fires) from *detection*
(the host result checker reports a mismatch). A test that passes without
activating a mutant is classified as not reached, not as a killed mutant.
These are manually constructed fault models, not a representative sample of
real GPU defects. Reported “all detected” results apply only to the enumerated
synthetic family.

## 4. Experimental setup

The primary platform is Vortex revision `1cd71c4`, configured for 4 warps per
core and 4 threads per warp by default. Additional builds use 8 or 16 threads
per warp. The opt-in `COV_SPLIT` trace is emitted by SIMX's warp-control unit;
RTLSIM is used for correctness cross-checks and selected RTL fault injections.
All successful kernel runs check device outputs against a host reference.
Instrumentation and harnesses are in `patches/` and
`experiments/vortex/`; step-by-step setup is in
`docs/coverage_experiment_log.md`.

For four- and eight-lane enumeration, every nonuniform mask is assigned to
consecutive task-ID groups; the full 16-lane pattern-4 run uses the same
group-based schedule. Pattern 5 provides an alternate loop-based 16-lane
schedule. We report simulator cycle counters only as simulator-specific
observations. We do not treat them as physical performance measurements or
compare SIMX and RTLSIM cycles as if they were interchangeable.

## 5. Results

### 5.1 Exhaustive mask reachability

| Warp width | Schedule | Masks/site | Sites | Simulator evidence | Result |
|---:|---|---:|---:|---|---|
| 4 | Pattern 2, grouped | 14/14 | 7 | SIMX; targeted RTLSIM controls | All 14 observed/site |
| 8 | Pattern 3, grouped | 254/254 | 7 | SIMX and RTLSIM, 2,048 points each | All 254 observed/site |
| 16 | Pattern 4, grouped | 65,534/65,534 | 7 | SIMX full; RTLSIM smoke only | All 65,534 observed/site on SIMX |
| 16 | Pattern 5, looped | 65,534/65,534 | 8 | SIMX full; RTLSIM 128-mask shard | All 65,534 observed/site on SIMX |

The pattern-3 SIMX and RTLSIM runs both pass the reference check and match at
59,680 retired instructions, 9,216 total branches, and 1,792 divergent events.
Each of the seven sites sees 256 events and 254 distinct masks. The 16-lane
pattern-4 SIMX run passes over 1,048,576 points with 458,752 divergent events;
each of seven sites sees 65,536 events and all 65,534 distinct masks. The
looped pattern-5 SIMX run passes with 524,272 divergent events; each of eight
sites sees 65,534 events and 65,534 distinct mask pairs. The full pattern-5
run reports 7,667,563 instructions and 117,438,380 cycles. It took long enough
that full RTLSIM enumeration was stopped at the documented timeout.

These results demonstrate that the implementation can construct and measure
exhaustive mask schedules for the tested widths and kernel structures. They
do not show that those schedules are representative of application workloads.

### 5.2 Fault activation and detection

| Experiment | Fixed pattern 0 | Fixed pattern 1 | Sweep | Interpretation |
|---|---:|---:|---:|---|
| 56 four-lane SIMX lane-routing mutants | 28/56 detected | 28/56 detected | Pattern 2: 56/56 | Sweep completes this constructed mask/operator space |
| Exact `0101` RTL ALU mutant at seven sites | 0/7 activated | 0/7 activated | Pattern 2: 7/7 detected | Targeted evidence of a mask-conditioned test gap |
| Lane-0-active partial-mask RTL ALU mutant at seven sites | 7/7 detected | 7/7 detected | Pattern 2: 7/7 detected | More mask diversity did not change detection here |
| Lane-0 split-predicate inversion, 3 repeats/pattern | 3/3 detected | 3/3 detected | Pattern 2: 3/3 detected | Control-flow fault is not pattern-selective |

For the 56 SIMX mutations, patterns 0 and 1 together detect 40/56; the
remaining 16 are not activated by either. Pattern 2 is designed to enumerate
the complete nonuniform four-lane space, so its 56/56 result confirms reach
and observability for this generated mutation family. At the seven RTL branch
sites, the exact-mask mutant is activated nine times and yields nine output
mismatches per pattern-2 run; patterns 0 and 1 record zero activations. For
the broader mutant enabled whenever lane 0 is active under a partial mask, all
patterns detect it, while pattern 2 observes seven eligible active masks and
each fixed pattern only one. This contrast supports the narrower conclusion
that mask bins can reveal a known activation gap, but mask-bin growth alone
does not predict detection improvement.

Additional evidence in the experiment log includes selected ALU, split
predicate, LSU load/store corruption, input-size scaling, and a second
`diverge` workload. Those experiments use different fault models and run
conditions; they are not combined into one mutation score.

## 6. Threats to validity and limitations

**Construct validity.** A distinct `(then, else)` mask pair is a useful
measure of lane identity at a split, but it is not a complete model of
SIMT behavior. It omits reconvergence-stack state, path order, nesting
interactions, instruction-level active masks after the split, and memory
coalescing effects. The coverage bin is compiled-PC based and can drift across
builds.

**Internal validity.** The device and host computations are separate for the
exhaustive paths, but the same generated test may still contain specification
errors. Mutation harnesses temporarily edit simulator or RTL code and depend
on PCs and RTL structures from a pinned build. A clean control and source
restoration are required for each mutation. The repository documents initial
RTL mutation attempts that timed out due to a mismatched simulator/runtime
build; those attempts are excluded from results.

**External validity.** The main coverage kernel is synthetic and small. Most
mask-conditional RTL mutants target lane 0, selected branch-body PCs, and a
specific active mask; this does not approximate a distribution of naturally
occurring design defects. Only one open GPU design is evaluated. Full 16-lane
exhaustive coverage is SIMX-only; RTLSIM validation is bounded. There are no
physical FPGA or commercial GPU measurements, and no demonstrated real bug
discovery.

**Conclusion validity.** Several results are deterministic and repeated,
but many sweep and fault rows are single runs. Simulator cycles depend on
configuration and model; they are not speedup results. The mutation scores
must not be generalized beyond the listed generated mutants.

## 7. Conclusion and next study

This case study adds lane-mask identity to dynamic divergent-branch coverage
and shows how an exhaustive test can expose selected mask-conditioned
activation gaps that fixed patterns miss. It also shows counterexamples to a
simple “more coverage means more faults found” claim. The evidence supports
using per-site lane-mask bins as a diagnostic complement to branch coverage,
not as a stand-alone quality guarantee.

The next study should add unrelated kernels and branch structures, broaden
RTL mutation operators without hard-coding one lane or exact mask, estimate
equivalent-mutant rates, repeat measurements, map PCs back to source, and
evaluate whether coverage-guided input selection improves fault detection
under a fixed runtime budget. Full 16-lane RTLSIM or board-level validation
would strengthen platform claims. Until then, the appropriate publication
claim is a focused Vortex case study and artifact, not a general GPU
verification framework.

## References

[1] C. Peng and A. Rajan, “CLTestCheck: Measuring Test Effectiveness for GPU
Kernels,” *Fundamental Approaches to Software Engineering (FASE)*, 2019,
LNCS 11424, pp. 315–331. [DOI](https://doi.org/10.1007/978-3-030-16722-6_19).

[2] Q. Zhu and A. Zaidman, “Massively Parallel, Highly Efficient, but What
About the Test Suite Quality? Applying Mutation Testing to GPU Programs,”
*IEEE International Conference on Software Testing, Verification and
Validation (ICST)*, 2020. [DOI](https://doi.org/10.1109/ICST46399.2020.00030).

[3] Z. Gao et al., “Fuzzing Open-Source GPU Hardware with SIMT Program
Generation,” *35th USENIX Security Symposium*, 2026, pp. 2465–2484.
[USENIX paper page](https://www.usenix.org/conference/usenixsecurity26/presentation/gao-zibo).

[4] Vortex GPGPU, source repository and project documentation,
[https://github.com/vortexgpgpu/vortex](https://github.com/vortexgpgpu/vortex).

## Artifact map

The experiment log is the detailed lab record. Machine-readable result tables
and reproduction scripts are under `experiments/vortex/`; the trace patch is
`patches/vortex-simx-split-trace.patch`. Avoid committing the 52 MB raw
pattern-5 trace unless the target venue requires raw traces: the per-site CSV
is sufficient to substantiate the summarized result, while the script
reconstructs the run.
