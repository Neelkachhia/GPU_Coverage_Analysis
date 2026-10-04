use anyhow::Result;
use coverage_model::CoverageReport;
use kernelgen::generate_seed_kernels;
use runner::run_kernel_mock;
use selector::{greedy_score, marginal_score};

fn main() -> Result<()>
{
    let kernels = generate_seed_kernels()?;
    let baseline = CoverageReport::default();

    println!("Generated {} seed kernels", kernels.len());

    for k in kernels
    {
        let report = run_kernel_mock(&k)?;
        println!(
            "kernel={} score={} marginal={} cycles={} bins={:?}",
            k.name,
            greedy_score(&report),
            marginal_score(&report, &baseline),
            report.cycles,
            report.unique_bins()
        );

        let category_counts = report.category_counts();
        println!(" category_counts={:?}", category_counts);
    }

    Ok(())
}
