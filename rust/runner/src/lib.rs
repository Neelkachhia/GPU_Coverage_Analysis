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

    if spec.barriers > 0
    {
        bins.push(CoverageBinId::barrier("barrier_local"));
    }

    if spec.stride > 8
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
