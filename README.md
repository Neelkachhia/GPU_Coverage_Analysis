# GPU DV Research

Research framework for coverage-driven verification of open-source SIMT GPUs, inspired by the Vortex architecture.

# Goal

This project explores how to define and close functional coverage for GPU-specific microarchitectural behaviors such as:

- divergence and reconvergence
- wavefront scheduling
- barrier synchronization
- memory access footprint
- bank conflicts
- outstanding miss / progress states

# Planned components

- **Rust**: orchestration, coverage model, kernel generation, selection logic
- **C++**: trace parsing and high-performance coverage extension
- **Python**: plotting and experiment analysis

# Notes

This repository is intended for research prototyping and experimentation.
