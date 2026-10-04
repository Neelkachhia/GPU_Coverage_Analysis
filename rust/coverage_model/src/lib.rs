use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::collections::HashSet;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum CoverageCategory 
{
    Divergence,
    Scheduler,
    Barrier, 
    Memory,
    Progress,
    Occupancy,
    Synchronization,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct CoverageBinId
{
    pub category: CoverageCategory, 
    pub name: String,
}

impl CoverageBinId
{
    pub fn new(category: CoverageCategory, name: impl Into<String>) -> Self
    {
        Self
        {
            category,
            name: name.into(),
        }
    }

    pub fn divergence(name: impl Into<String>) -> Self
    {
        Self::new(CoverageCategory::Divergence, name)
    }

    pub fn scheduler(name: impl Into<String>) -> Self
    {
        Self::new(CoverageCategory::Scheduler, name)
    }

    pub fn barrier(name: impl Into<String>) -> Self
    {
        Self::new(CoverageCategory::Barrier, name)
    }

    pub fn memory(name: impl Into<String>) -> Self
    {
        Self::new(CoverageCategory::Memory, name)
    }

    pub fn progress(name: impl Into<String>) -> Self
    {
        Self::new(CoverageCategory::Progress, name)
    }

    pub fn occupancy(name: impl Into<String>) -> Self
    {
        Self::new(CoverageCategory::Occupancy, name)
    }

    pub fn synchronization(name: impl Into<String>) -> Self
    {
        Self::new(CoverageCategory::Synchronization, name)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CoverageReport
{
    pub bins_hit: Vec<CoverageBinId>,
    pub cycles: u64,
    pub bug_found: bool,
}

impl CoverageReport
{
    pub fn unique_bin_count(&self) -> usize
    {
        self.bins_hit.iter().cloned().collect::<HashSet<_>>().len()
    }

    pub fn merged_with(&self, other: &CoverageReport) -> CoverageReport
    {
        let mut merged = self.bins_hit.clone();
        merged.extend(other.bins_hit.clone());

        CoverageReport
        {
            bins_hit: merged,
            cycles: self.cycles + other.cycles,
            bug_found: self.bug_found || other.bug_found,
        }
    }

    pub fn category_counts(&self) -> HashMap<CoverageCategory, usize>
    {
        let mut unique = HashSet::new();
        for bin in &self.bins_hit
        {
            unique.insert(bin.clone());
        }

        let mut counts = HashMap::new();
        for bin in unique
        {
            *counts.entry(bin.category).or_insert(0) += 1;
        }

        counts
    }

    pub fn marginal_bin_count_against(&self, baseline: &CoverageReport) -> usize
    {
        let baseline_set: HashSet<_> = baseline.bins_hit.iter().cloned().collect();
        let self_set: HashSet<_> = self.bins_hit.iter().cloned().collect();

        self_set.difference(&baseline_set).count()
    }

    pub fn unique_bins(&self) -> Vec<CoverageBinId>
    {
        let mut unique: Vec<_> = self
            .bins_hit
            .iter()
            .cloned()
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();

        unique.sort_by(|a, b| {
            let a_key = (format!("{:?}", a.category), a.name.clone());
            let b_key = (format!("{:?}", b.category), b.name.clone());
            a_key.cmp(&b_key)
        });

        unique
    }
}
