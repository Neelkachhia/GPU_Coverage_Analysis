use anyhow::Result;
use coverage_model::CoverageReport;
use kernelgen::{generate_seed_kernels, KernelSpec};
use runner::run_kernel_mock;
use selector::{greedy_score, marginal_score};

fn main() -> Result<()>
{
    let kernels = generate_seed_kernels()?;
    let mut accumulated = CoverageReport::empty();
    let mut evaluated: Vec<(KernelSpec, CoverageReport)> = Vec::new();

    println!("Generated {} seed kernels", kernels.len());

    for k in kernels
    {
        let report = run_kernel_mock(&k)?;
        evaluated.push((k, report));
    }

    for (k, report) in &evaluated
    {
        println!(
            "kernel={} score={} marginal={} cycles={} bins={:?}",
            k.name,
            greedy_score(report),
            marginal_score(report, &accumulated),
            report.cycles,
            report.unique_bins()
        );

        let category_counts = report.category_counts();
        println!(" category_counts={:?}", category_counts);

        accumulated = accumulated.merged_with(report);
        println!(
            " accumulated_unique_bins={}",
            accumulated.unique_bin_count()
            );
    }

    println!(
        "\nFinal accumulated unique coverage bins = {}",
        accumulated.unique_bin_count()
        );

    Ok(())
}
