#!/usr/bin/env python3
"""Summarize fixed, exhaustive, and seeded SIMX mask-routing tests."""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUT_FIELDS = [
    "suite",
    "patterns",
    "mutant_variants",
    "killed",
    "not_reached",
    "survived",
    "detection_rate_pct",
    "mutant_runs",
    "mutant_cycle_total",
    "mean_cycles_per_mutant_suite_case",
    "mean_cycles_per_execution",
    "clean_workload_cycles_per_execution",
    "test_points_per_mutant_variant",
    "clean_workload_cycles_per_mutant_suite",
]
ALLOWED_OUTCOMES = {"KILLED", "NOT_REACHED", "SURVIVED"}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def summarize(mutation_path: Path, baseline_path: Path) -> list[dict[str, str]]:
    mutation_rows = read_csv(mutation_path)
    baseline_rows = read_csv(baseline_path)
    if not mutation_rows or not baseline_rows:
        raise ValueError("mutation and baseline CSVs must both contain rows")

    mutant_ids = {str(i) for i in range(1, 57)}
    fixed_patterns = {"0", "1", "2"}
    by_mutant_pattern: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in mutation_rows:
        pattern, seed, fault_id = row["pattern"], row["seed"], row["fault_id"]
        if pattern not in fixed_patterns | {"6"}:
            raise ValueError(f"unexpected pattern in mutation data: {pattern}")
        key = (pattern, seed, fault_id)
        if key in by_mutant_pattern:
            raise ValueError(f"duplicate mutant run: pattern={pattern}, seed={seed}, mutant={fault_id}")
        if fault_id not in mutant_ids:
            raise ValueError(f"unexpected mutant ID: {fault_id}")
        if row["outcome"] not in ALLOWED_OUTCOMES:
            raise ValueError(f"unrecognized outcome: {row['outcome']}")
        if not row["cycles"].isdigit():
            raise ValueError("every mutation execution must include measured cycles")
        by_mutant_pattern[key] = row

    for pattern in fixed_patterns:
        present = {fault_id for p, seed, fault_id in by_mutant_pattern if p == pattern and seed == "0"}
        if present != mutant_ids:
            raise ValueError(f"pattern {pattern} must have exactly one row for each of 56 mutants")
    random_seeds = sorted(
        {seed for pattern, seed, _ in by_mutant_pattern if pattern == "6"},
        key=lambda value: int(value),
    )
    if not random_seeds:
        raise ValueError("mutation data has no seeded pattern-6 rows")
    for seed in random_seeds:
        present = {fault_id for p, s, fault_id in by_mutant_pattern if p == "6" and s == seed}
        if present != mutant_ids:
            raise ValueError(f"random seed {seed} must have exactly one row for each of 56 mutants")

    baseline: dict[tuple[str, str], dict[str, str]] = {}
    for row in baseline_rows:
        key = (row["pattern"], row["seed"])
        if key in baseline:
            raise ValueError(f"duplicate baseline row: pattern={key[0]}, seed={key[1]}")
        if row["result"] != "PASSED":
            raise ValueError(f"baseline case did not pass: {key}")
        if not row["cycles"].isdigit():
            raise ValueError(f"baseline case has no cycle count: {key}")
        baseline[key] = row

    required_baselines = {(p, "0") for p in fixed_patterns} | {("6", s) for s in random_seeds}
    if set(baseline) != required_baselines:
        raise ValueError("baseline rows must match patterns 0, 1, 2 and each random mutation seed")
    if len({row["depth"] for row in baseline.values()}) != 1:
        raise ValueError("baseline workloads must use the same depth")

    for (pattern, seed, fault_id), row in by_mutant_pattern.items():
        baseline_key = (pattern, seed)
        if baseline_key not in baseline:
            raise ValueError(f"missing clean baseline for pattern={pattern}, seed={seed}")
        expected_points = baseline[baseline_key]["points"]
        if row.get("points") and row["points"] != expected_points:
            raise ValueError(
                f"mutant workload mismatch for pattern={pattern}, seed={seed}, mutant={fault_id}"
            )

    suites: list[tuple[str, list[dict[str, str]], list[tuple[str, str]]]] = []
    for pattern in ("0", "1", "2"):
        cases = [by_mutant_pattern[(pattern, "0", fault_id)] for fault_id in sorted(mutant_ids, key=int)]
        suites.append((f"pattern_{pattern}", cases, [(pattern, "0")]))

    fixed_pair = [
        by_mutant_pattern[(pattern, "0", fault_id)]
        for fault_id in sorted(mutant_ids, key=int)
        for pattern in ("0", "1")
    ]
    suites.append(("fixed_0_plus_1", fixed_pair, [("0", "0"), ("1", "0")]))
    for seed in random_seeds:
        cases = [by_mutant_pattern[("6", seed, fault_id)] for fault_id in sorted(mutant_ids, key=int)]
        suites.append((f"seeded_random_seed_{seed}", cases, [("6", seed)]))

    results = []
    for name, cases, baseline_keys in suites:
        outcomes_by_mutant: dict[str, list[str]] = defaultdict(list)
        for row in cases:
            outcomes_by_mutant[row["fault_id"]].append(row["outcome"])
        suite_outcomes = []
        for fault_id in sorted(mutant_ids, key=int):
            outcomes = outcomes_by_mutant[fault_id]
            suite_outcomes.append(
                "KILLED" if "KILLED" in outcomes
                else "SURVIVED" if "SURVIVED" in outcomes
                else "NOT_REACHED"
            )
        counts = Counter(suite_outcomes)
        cycles = sum(int(row["cycles"]) for row in cases)
        clean_suite_cycles = sum(int(baseline[key]["cycles"]) for key in baseline_keys)
        clean_cycles = clean_suite_cycles / len(baseline_keys)
        test_points = sum(int(baseline[key]["points"]) for key in baseline_keys)
        results.append({
            "suite": name,
            "patterns": "+".join(key[0] if key[0] != "6" else f"6@seed{key[1]}" for key in baseline_keys),
            "mutant_variants": str(len(mutant_ids)),
            "killed": str(counts["KILLED"]),
            "not_reached": str(counts["NOT_REACHED"]),
            "survived": str(counts["SURVIVED"]),
            "detection_rate_pct": f"{100 * counts['KILLED'] / len(mutant_ids):.2f}",
            "mutant_runs": str(len(cases)),
            "mutant_cycle_total": str(cycles),
            "mean_cycles_per_mutant_suite_case": f"{cycles / len(mutant_ids):.1f}",
            "mean_cycles_per_execution": f"{cycles / len(cases):.1f}",
            "clean_workload_cycles_per_execution": f"{clean_cycles:.1f}",
            "test_points_per_mutant_variant": str(test_points),
            "clean_workload_cycles_per_mutant_suite": str(clean_suite_cycles),
        })
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mutations", type=Path, default=ROOT / "mutation_matrix_simx_random.csv")
    parser.add_argument("--baseline", type=Path, default=ROOT / "simx_baseline_random_rerun.csv")
    parser.add_argument("--output", type=Path, default=ROOT / "mask_adequacy_summary.csv")
    parser.add_argument(
        "--require-equal-points",
        action="store_true",
        help="require the fixed-pair, exhaustive, and seeded suites to use equal total points",
    )
    args = parser.parse_args()

    results = summarize(args.mutations, args.baseline)
    if args.require_equal_points:
        budgets = {
            row["test_points_per_mutant_variant"]
            for row in results
            if row["suite"] == "fixed_0_plus_1"
            or row["suite"] == "pattern_2"
            or row["suite"].startswith("seeded_random_")
        }
        if len(budgets) != 1:
            raise ValueError(f"suite point budgets are not equal: {sorted(budgets)}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=OUT_FIELDS)
        writer.writeheader()
        writer.writerows(results)
    print(f"Wrote {len(results)} suite summaries to {args.output}")
    for row in results:
        print(
            f"{row['suite']}: killed={row['killed']}/{row['mutant_variants']}, "
            f"not_reached={row['not_reached']}, "
            f"mean_suite_cycles/mutant={row['mean_cycles_per_mutant_suite_case']}"
        )


if __name__ == "__main__":
    main()
