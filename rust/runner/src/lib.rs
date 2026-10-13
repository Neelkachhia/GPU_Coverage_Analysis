use anyhow::Result;
use coverage_model::{CoverageBinId, CoverageReport};
use kernelgen::KernelSpec;

pub fn run_kernel_mock(spec: &KernelSpec) -> Result<CoverageReport>
{
    let mut bins = Vec::new();

    if spec.branch_mode != "none"
    {
        bins.push(CoverageBinId::divergence("divergence_occurred"));
    }

    if spec.branch_mode == "nested"
    {
        bins.push(CoverageBinId::divergence("nested_divergence"));
    }

    if spec.workgroups <= 4
    {
        bins.push(CoverageBinId::occupancy("low_occupancy"));
    }

    else
    {
        bins.push(CoverageBinId::occupancy("high_occupancy"));
    }

    if spec.barriers > 0
    {
        bins.push(CoverageBinId::barrier("barrier_local"));
        bins.push(CoverageBinId::synchronization("wavefront_sync"));
    }

    if spec.stride > 32
    {
        bins.push(CoverageBinId::memory("memory_multi_line"));
        bins.push(CoverageBinId::memory("bank_conflict"));
        bins.push(CoverageBinId::memory("high_memory_spread"));
    }

    else if spec.stride > 8
    {
        bins.push(CoverageBinId::memory("memory_multi_line"));
        bins.push(CoverageBinId::memory("bank_conflict"));
    }
    else
    {
        bins.push(CoverageBinId::memory("memory_single_line"));
    }

    Ok(CoverageReport {
        bins_hit: bins,
        cycles: 1000 + spec.stride as u64 * 10,
        bug_found: false,
    })
}

pub fn parse_divergent_split_count(output: &str) -> Result<u64>
{
    output
        .lines()
        .filter(|line| line.contains("branches:"))
        .find_map(|line|
        {
            line.split_once("divergent=")?
                .1
                .split_whitespace()
                .next()?
                .trim_end_matches(',')
                .parse::<u64>()
                .ok()
        })
        .ok_or_else(|| anyhow::anyhow!("Vortex output has no divergence counter"))

}

pub fn run_vortex_divergence(
    build_dir: &std::path::Path,
    driver: &str,
    ) -> anyhow::Result<u64>
{
    if !matches!(driver, "simx" | "rtlsim")
    {
        anyhow::bail!("unsupported Vortex driver: {driver}");
    }

    let output = std::process::Command::new("./ci/blackbox.sh")
        .current_dir(build_dir)
        .args([
              format!("--driver={driver}"),
              "--cores=2".to_string(),
              "--app=diverge".to_string(),
              "--perf=1".to_string(),
            ])
        .output()?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let combined = format!("{stdout}\n{stderr}");

    if !output.status.success()
    {
        anyhow::bail!("Vortex diverge run failed:\n{combined}");
    }

    parse_divergent_split_count(&combined)
}

pub fn parse_cycle_count(output: &str) -> anyhow::Result<u64>
{
    output
        .lines()
        .find(|line| line.starts_with("PERF: instrs="))
        .and_then(|line|
        {
            line.split_once("cycles=")?
                .1
                .split_whitespace()
                .next()?
                .trim_end_matches(',')
                .parse::<u64>()
                .ok()
        })
        .ok_or_else(|| anyhow::anyhow!("Vortex output has no cycle counter"))
}

pub fn coverage_report_from_vortex_output(
    output: &str,
    ) -> anyhow::Result<CoverageReport>
{
    let divergent_splits = parse_divergent_split_count(output)?;
    let cycles = parse_cycle_count(output)?;

    let bins_hit = if divergent_splits > 0
    {
        vec![CoverageBinId::divergence("divergence_occurred")]
    }
    else
    {
        Vec::new()
    };

    Ok(CoverageReport {
        bins_hit,
        cycles,
        bug_found: false,
    })
}

#[cfg(test)]
mod perf_tests
{
    use super::parse_divergent_split_count;

    #[test]
    fn parses_nonzero_divergence_count()
    {
        let output = "PERF: branches: total=231949, divergent=8 (rate=0%)";
        assert_eq!(parse_divergent_split_count(output).unwrap(),8);
    }

    #[test]
    fn parse_zero_divergence_count()
    {
        let output = "PERF: branches: total=32, divergent=0 (rate=0%)";
        assert_eq!(parse_divergent_split_count(output).unwrap(),0);
    }

    #[test]
    fn rejects_output_without_divergence_counter()
    {
        assert!(parse_divergent_split_count("PASSED!").is_err());
    }
}

#[cfg(test)]
mod vortex_integration_tests
{
    use super::run_vortex_divergence;
    use std::path::PathBuf;

    #[test]
    #[ignore = "requires the pinned Vortex build"]

    fn simx_diverge_reports_eight_divergent_splits()
    {
        let build_dir = PathBuf::from(
            std::env::var_os("VORTEX_BUILD_DIR")
            .expect("set VORTEX_BUILD_DIR to the Vortex build directory"),
           );

        let count = run_vortex_divergence(&build_dir, "simx").unwrap();
        assert_eq!(count, 8);
    }

    #[test]
    #[ignore = "requires the pinned Vortex build"]

    fn rtlsim_diverge_reports_eight_divergent_splits()
    {
        let build_dir = PathBuf::from(
            std::env::var_os("VORTEX_BUILD_DIR")
            .expect("set VORTEX_BUILD_DIR to the Vortex build directory"),
            );

        let count  = run_vortex_divergence(&build_dir, "rtlsim").unwrap();
        assert_eq!(count, 8);
    }
}

#[cfg(test)]
mod cycle_tests
{
    use super::parse_cycle_count;

    #[test]
    fn parses_global_cycles_not_per_core_cycles()
    {
        let output = [
            "PERF: core0: instrs=100, cycles=60, IPC=1.667",
            "PERF: core1: instrs=120, cycles=70, IPC=1.714",
            "PERF: instrs=220, cycles=70, IPC=3.143",
        ]
        .join("\n");
        assert_eq!(parse_cycle_count(&output).unwrap(), 70);
    }

    #[test]
    fn rejects_output_without_cycle_counter()
    {
        assert!(parse_cycle_count("PASSED!").is_err());
    }
}

#[cfg(test)]
mod report_tests
{
    use super::coverage_report_from_vortex_output;

    #[test]
    fn builds_report_from_measured_vortex_output()
    {
        let output = [
            "PERF: branches: total=231949, divergent=8 (rate=0%)",
            "PERF: instrs=416, cycles=750, IPC=0.555",
            ]
            .join("\n");

        let report = coverage_report_from_vortex_output(&output).unwrap();

        assert_eq!(report.unique_bin_count(), 1);
        assert_eq!(report.cycles, 750);
        assert_eq!(
            report.unique_bins()[0].name,
            "divergence_occurred"
            );
    }
}
