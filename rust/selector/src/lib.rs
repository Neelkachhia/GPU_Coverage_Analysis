use coverage_model::CoverageReport;

pub fn greedy_score(report: &CoverageReport) -> usize 
{
    report.unique_bin_count()
}

pub fn marginal_score(candidate: &CoverageReport, baseline: &CoverageReport) -> usize
{
    candidate.marginal_bin_count_against(baseline)
}

pub fn efficiency_score(candidate: &CoverageReport, baseline: &CoverageReport) -> f64
{
    let marginal = candidate.marginal_bin_count_against(baseline) as f64;
    let cycles = candidate.cycles_used() as f64;

    if cycles == 0.0
    {
        0.0
    }
    else
    {
        marginal / cycles
    }
}
