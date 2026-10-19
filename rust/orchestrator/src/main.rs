use anyhow::{Context, Result};
use clap::Parser;
use coverage_model::CoverageReport;
use kernelgen::{generate_seed_kernels, KernelSpec};
use runner::{run_kernel_mock, run_vortex_coverage_case};
use selector::{efficiency_score, greedy_score, marginal_score};
use std::path::PathBuf;

#[derive(Debug, Parser)]
#[command(about = "GPU coverage experiment orchestrator")]
struct Args {
    /// Run measured SIMX cases for branch depths 1 through 8
    #[arg(long)]
    vortex_sweep: bool,

    /// Vortex build directory; defaults to the VORTEX_BUILD_DIR environment variable
    #[arg(long, value_name = "PATH")]
    vortex_build_dir: Option<PathBuf>,
}

fn main() -> Result<()> {
    let args = Args::parse();

    if args.vortex_sweep {
        let build_dir = args
            .vortex_build_dir
            .or_else(|| std::env::var_os("VORTEX_BUILD_DIR").map(PathBuf::from))
            .context("set --vortex-build-dir or VORTEX_BUILD_DIR")?;

        println!("MODE=SIMX_MEASURED");
        println!("pattern | depth | cycles | unique bins");
      for pattern in 0..=2 {
        for depth in 1..=8 {
            let report = run_vortex_coverage_case(&build_dir, depth, pattern)?;
            println!(
                "{pattern:>7} | {depth:>5} | {:>6} | {:>11}",
                report.cycles,
                report.unique_bin_count()
            );
            for bin in report.unique_bins() {
                println!("        - {}", bin.name);
            }
        }
      }
        return Ok(());
    }

    println!("MODE=MOCK");
    run_mock_selection()
}

fn run_mock_selection() -> Result<()> {
    let kernels = generate_seed_kernels()?;
    let cycle_budget: u64 = 4000;
    let mut accumulated = CoverageReport::empty();
    let mut selected_kernel_names: Vec<String> = Vec::new();
    let mut evaluated: Vec<(KernelSpec, CoverageReport)> = Vec::new();

    println!("Generated {} mock seed kernels", kernels.len());

    for kernel in kernels {
        let report = run_kernel_mock(&kernel)?;
        evaluated.push((kernel, report));
    }

    evaluated.sort_by(|a, b| a.0.name.cmp(&b.0.name));

    for (kernel, report) in &evaluated {
        let fits_budget = accumulated.cycles_used() + report.cycles_used() <= cycle_budget;
        let selected = fits_budget;

        println!(
            "kernel={} score={} marginal={} efficiency={:.6} cycles={} fits_budget={} selected={} bins={:?}",
            kernel.name,
            greedy_score(report),
            marginal_score(report, &accumulated),
            efficiency_score(report, &accumulated),
            report.cycles,
            fits_budget,
            selected,
            report.unique_bins()
        );

        println!(" category_counts={:?}", report.category_counts());

        if selected {
            accumulated = accumulated.merged_with(report);
            selected_kernel_names.push(kernel.name.clone());
        }

        println!(
            " accumulated_unique_bins={}",
            accumulated.unique_bin_count()
        );
        println!(" accumulated_cycles={}", accumulated.cycles_used());
    }

    println!(
        "\nFinal accumulated unique coverage bins = {}",
        accumulated.unique_bin_count()
    );
    println!("Final accumulated cycles = {}", accumulated.cycles_used());
    println!("Cycle budget = {}", cycle_budget);
    println!(
        "Budget respected = {}",
        accumulated.cycles_used() <= cycle_budget
    );
    println!(
        "Final category counts = {:?}",
        accumulated.category_counts()
    );
    println!("Selected kernels = {:?}", selected_kernel_names);
    println!("Selected kernel count = {}", selected_kernel_names.len());

    let final_efficiency = if accumulated.cycles_used() == 0 {
        0.0
    } else {
        accumulated.unique_bin_count() as f64 / accumulated.cycles_used() as f64
    };
    println!("Final coverage efficiency = {:.6}", final_efficiency);

    Ok(())
}
