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
        .filter(|line| line.starts_with("PERF: branches:"))
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DivergenceEvent {
    pub pc: u64,
    pub warp: u32,
    pub then_lanes: u32,
    pub else_lanes: u32,
}

pub fn parse_divergence_events(output: &str) -> Result<Vec<DivergenceEvent>> {
    let mut events = Vec::new();

    for line in output.lines().filter(|line| line.starts_with("COV_SPLIT ")) {
        let mut pc = None;
        let mut warp = None;
        let mut then_lanes = None;
        let mut else_lanes = None;

        for field in line.split_whitespace().skip(1) {
            let (key, value) = field
                .split_once('=')
                .ok_or_else(|| anyhow::anyhow!("malformed COV_SPLIT field: {field}"))?;

            match key {
                "pc" => {
                    let hex = value.strip_prefix("0x").unwrap_or(value);
                    pc = Some(u64::from_str_radix(hex, 16).map_err(|e| {
                        anyhow::anyhow!("invalid COV_SPLIT PC {value}: {e}")
                    })?);
                }
                "wid" => {
                    warp = Some(value.parse::<u32>().map_err(|e| {
                        anyhow::anyhow!("invalid COV_SPLIT warp {value}: {e}")
                    })?);
                }
                "then" => {
                    then_lanes = Some(value.parse::<u32>().map_err(|e| {
                        anyhow::anyhow!("invalid COV_SPLIT then count {value}: {e}")
                    })?);
                }
                "else" => {
                    else_lanes = Some(value.parse::<u32>().map_err(|e| {
                        anyhow::anyhow!("invalid COV_SPLIT else count {value}: {e}")
                    })?);
                }
                _ => {}
            }
        }

        events.push(DivergenceEvent {
            pc: pc.ok_or_else(|| anyhow::anyhow!("COV_SPLIT record has no PC: {line}"))?,
            warp: warp.ok_or_else(|| anyhow::anyhow!("COV_SPLIT record has no warp: {line}"))?,
            then_lanes: then_lanes
                .ok_or_else(|| anyhow::anyhow!("COV_SPLIT record has no then count: {line}"))?,
            else_lanes: else_lanes
                .ok_or_else(|| anyhow::anyhow!("COV_SPLIT record has no else count: {line}"))?,
        });
    }

    Ok(events)
}
#[cfg(test)]
mod divergence_event_tests {
    use super::{parse_divergence_events, DivergenceEvent};

    #[test]
    fn parses_split_pc_and_lane_counts() {
        let output = [
            "COV_SPLIT pc=0x800000c0 wid=3 then=2 else=2",
            "COV_SPLIT pc=0x800000ec wid=7 then=3 else=1",
        ]
        .join("\n");

        assert_eq!(
            parse_divergence_events(&output).unwrap(),
            vec![
                DivergenceEvent {
                    pc: 0x800000c0,
                    warp: 3,
                    then_lanes: 2,
                    else_lanes: 2,
                },
                DivergenceEvent {
                    pc: 0x800000ec,
                    warp: 7,
                    then_lanes: 3,
                    else_lanes: 1,
                },
            ]
        );
    }

    #[test]
    fn no_split_records_produce_an_empty_event_list() {
        assert!(parse_divergence_events("PASSED!\n").unwrap().is_empty());
    }
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

pub fn run_vortex_coverage_case(
    build_dir: &std::path::Path,
    depth: u32,
) -> anyhow::Result<CoverageReport> {
    let args = format!("--args=-n16 -d{depth}");

    let output = std::process::Command::new("./ci/blackbox.sh")
        .current_dir(build_dir)
        .env("VX_SIMX_SPLIT_TRACE", "1")
        .args([
            "--driver=simx",
            "--cores=2",
            "--app=coverage_diverge",
            "--perf=1",
        ])
        .arg(args)
        .output()?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let combined = format!("{stdout}\n{stderr}");

    if !output.status.success() || !combined.contains("PASSED!") {
        anyhow::bail!("Vortex coverage run failed at depth {depth}:\n{combined}");
    }

    coverage_report_from_vortex_output(&combined)
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

    let mut bins_hit = Vec::new();

    if divergent_splits > 0
    {
        bins_hit.push(CoverageBinId::divergence("divergence_occurred"));
    }

    for event in parse_divergence_events(output)?
    {
        bins_hit.push(CoverageBinId::divergence(format!(
                    "pc_{:x}_split_seen",
                    event.pc
                )));
        bins_hit.push(CoverageBinId::divergence(format!(
                    "pc_{:x}_lanes_{}_{}",
                    event.pc, event.then_lanes, event.else_lanes
                )));
    }

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
    fn prefers_aggregate_divergence_count_over_per_core_counts()
    {
        let output = [
            "PERF: core0: branches: total=100, divergent=99 (rate=99%)",
            "PERF: core1: branches: total=100, divergent=77 (rate=77%)",
            "PERF: branches: total=200, divergent=12 (rate=6%)",
        ]
        .join("\n");

        assert_eq!(parse_divergent_split_count(&output).unwrap(), 12);
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
            "COV_SPLIT pc=0x800000c0 wid=0 then=2 else=2",
        ]
            .join("\n");

        let report = coverage_report_from_vortex_output(&output).unwrap();

        assert_eq!(report.unique_bin_count(), 3);
        assert_eq!(report.cycles, 750);
        assert_eq!(
            report.unique_bins()[0].name,
            "divergence_occurred"
            );
        assert!(report
                .unique_bins()
                .iter()
                .any(|bin| bin.name == "pc_800000c0_split_seen"));
        assert!(report
                .unique_bins()
                .iter()
                .any(|bin| bin.name == "pc_800000c0_lanes_2_2"));
    }
}

#[cfg(test)]
mod vortex_coverage_integration_tests {
    use super::run_vortex_coverage_case;
    use std::path::PathBuf;

    #[test]
    #[ignore = "requires the pinned Vortex simx build and coverage_diverge test"]
    fn simx_depth8_reports_seven_split_sites_and_lanes_bins() {
        let build_dir = PathBuf::from(
            std::env::var_os("VORTEX_BUILD_DIR")
                .expect("set VORTEX_BUILD_DIR to the Vortex build directory"),
        );

        let report = run_vortex_coverage_case(&build_dir, 8).unwrap();
        let bins = report.unique_bins();

        let site_bins = bins
            .iter()
            .filter(|bin| bin.name.ends_with("_split_seen"))
            .count();
        let lane_count_bins = bins
            .iter()
            .filter(|bin| bin.name.contains("_lanes_"))
            .count();

        assert_eq!(site_bins, 7);
        assert_eq!(lane_count_bins, 7);
        assert_eq!(report.unique_bin_count(), 15);
    }
}
