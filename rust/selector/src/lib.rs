use coverage_model::CoverageReport;

pub fn greedy_score(report: &CoverageReport) -> usize 
{
    report.unique_bin_count()
}

pub fn marginal_score(candidate: &CoverageReport, baseline: &CoverageReport) -> usize
{
    candidate.marginal_bin_count_against(baseline)
}
