# Reproduction environment

Metadata captured for the primary four-thread SIMX campaign and matched-point
mutation runs.

| Item | Value |
|---|---|
| Vortex commit | `1cd71c4023e9fbc3f635fb3cae924722b9808f67` |
| Host | Ubuntu 22.04 under WSL2; Linux `6.6.87.2-microsoft-standard-WSL2` |
| RISC-V clang | `20.1.8` (`vortexgpgpu/llvm`, commit `4c836512a60c0b965bb298104e084cd0f07ca962`) |
| Warp configuration, primary run | 4 warps/core, 4 threads/warp |
| SIMX command topology | `--cores=2` |
| Source config SHA-256 | `e8ae136a951dcbe7d90c752c463856378498b35a02f2bc2dc35140ce38c3b724` |
| Generated `build/sw/VX_config.h` SHA-256 | `379a6993e572e4864fb611644cc3d935b13a3632c6222098a07641c457dbf729` |
| Generated `build-threads16/sw/VX_config.h` SHA-256 | `3c200012121c765db2b989f2bac1585b3c363af6ad21b59ba5f8db3827ddc375` |

The 8- and 16-thread experiments use separately configured build directories.
The 16-thread pattern-4 and pattern-5 SIMX runs were repeated after the host
oracle was made independent; full exhaustive RTLSIM enumeration remains
incomplete. Generated configuration hashes for the separate 8- and 16-thread
builds were not preserved, so the claims are limited to the recorded workloads
and configurations.

SHA-256 hashes for the experimental application and trace patch:

| File | SHA-256 |
|---|---|
| `coverage_diverge/common.h` | `BBDAC705C2487715AD88094B04EBA55A7ACE54637A64B3674B1F3F6862316A31` |
| `coverage_diverge/kernel.cpp` | `62DB5E4903CB492FE4A830681FBCC5C0AA26DF0FC82346148CDD1FA43C03EA78` |
| `coverage_diverge/main.cpp` | `D499B29D9E5BE50613CA55CA6CA2754E3137624FBA9636EE12535B0BF5FD4D9F` |
| `patches/vortex-simx-split-trace.patch` | `1826529D4B88045905F34DE4672FFC22222EBC0F9F8463FE1AAA9343368BAD00` |

The Verilator version used for the recorded RTLSIM runs was not captured.
