use anyhow::Result;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct KernelSpec
{
    pub name: String,
    pub workgroups: u32,
    pub local_size: u32,
    pub branch_mode: String,
    pub stride: u32,
    pub barriers: u32,
}

pub fn generate_seed_kernels() -> Result<Vec<KernelSpec>>
{
    Ok(vec![
       KernelSpec {
           name: "divergence_basic".into(),
           workgroups: 4,
           local_size: 8,
           branch_mode: "even_odd".into(),
           stride: 1,
           barriers: 0,
        },

       KernelSpec {
           name: "barrier_stress".into(),
           workgroups: 8,
           local_size: 8,
           branch_mode: "none".into(),
           stride: 1,
           barriers: 2,
        },

       KernelSpec {
           name: "memory_stride".into(),
           workgroups: 4,
           local_size: 8,
           branch_mode: "none".into(),
           stride: 16,
           barriers: 0,
        },
    ])
}

