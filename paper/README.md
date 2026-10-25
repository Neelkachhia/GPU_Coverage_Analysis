# Paper package status

This directory contains an internal manuscript draft, not a submission-ready
paper. The current project has a solid, reproducible simulator case study and
useful mutation evidence, but the generality required for a strong empirical
paper is not yet established.

## Current contribution

The strongest defensible contribution is a per-static-site measure of dynamic
then/else lane-mask coverage for divergent SIMT splits, accompanied by
exhaustive mask-generation kernels and controlled mutation comparisons on
Vortex. The empirical result is nuanced: exhaustive masks exposed activation
gaps for selected exact-mask faults, while other faults were detected equally
by fixed and sweeping patterns.

The project already includes 4-, 8-, and 16-lane mask enumeration; SIMX and
bounded RTLSIM checks; a Rust parser and coverage-bin model; reproducible shell
harnesses; CSV result summaries; and a detailed experiment log. The codebase
does not yet implement all of the README's broader goals such as systematic
barrier, memory-bank, scheduler, or outstanding-miss coverage.

## Submission readiness

**Status: promising M.Tech / workshop case study; not yet ready for a strong
conference or journal submission.** The main blockers are:

1. Expand the evaluation to several structurally different kernels and,
   preferably, a second open SIMT RTL design.
2. Broaden mutation operators and avoid relying mainly on lane-0,
   exact-mask, PC-specific RTL mutants. Explain equivalent and unobservable
   mutants and report a carefully defined denominator.
3. Automate coverage-guided test selection and compare against fixed/random
   baselines under the same execution budget. A measured coverage metric alone
   is a weaker contribution than showing improved test efficiency.
4. Repeat the important measurements and include uncertainty where results
   can vary. Keep simulator cycle counts separate from physical performance.
5. Add a portable, one-command artifact setup, pin toolchain/build metadata,
   and ensure source-PC mappings remain understandable across rebuilds.
6. Complete novelty review, author list, venue fit, and the manuscript after
   those results exist.

## Fastest credible plan

For a narrowly scoped workshop or student-research submission, plan on roughly
**4–8 focused weeks** to finish the evaluation, rerun the key comparisons,
package the artifact, and revise the paper. A stronger conference-level
empirical study is more plausibly **2–4 months** of focused work, especially if
it adds another architecture or real kernels. These are planning estimates,
not acceptance predictions; peer review and publication schedules add
additional months and cannot be controlled by the project.

Recommended order:

1. Independently validate the host oracle and the current experimental source.
2. Select 3–5 diverse kernels and define non-duplicative, reviewable RTL fault
   operators before running the main study.
3. Compare branch-only, lane-count, mask-coverage, and random-input strategies
   at equal budgets; repeat runs and report activation separately from
   detection.
4. Freeze the source revision, configuration, scripts, data, and logs; run the
   artifact from a clean checkout.
5. Revise `draft.md`, conduct a novelty check against the target venue, and
   obtain advisor/coauthor review before submission.

## Related work checked for this draft

- Peng and Rajan, CLTestCheck, FASE 2019: GPU-kernel coverage, fault seeding,
  and schedule amplification over 82 kernels. [DOI](https://doi.org/10.1007/978-3-030-16722-6_19)
- Zhu and Zaidman, GPU program mutation testing, ICST 2020. [DOI](https://doi.org/10.1109/ICST46399.2020.00030)
- Gao et al., FuzzGPU, USENIX Security 2026: SIMT program generation and
  differential testing of Vortex and Ventus RTL. [Paper page](https://www.usenix.org/conference/usenixsecurity26/presentation/gao-zibo)

These references make it essential to frame this work as mask-aware test
adequacy and a Vortex case study. Do not claim the first GPU coverage,
mutation-testing, or GPU-RTL-fuzzing framework.
