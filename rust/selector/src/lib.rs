use coverage_model::CoverageReport;

pub fn greedy_score(report: &CoverageReport) -> usize 
{
    report.unique_bin_count()
}
