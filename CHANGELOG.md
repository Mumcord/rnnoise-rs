# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Repository scaffolding aligned with the sibling `lovelace-labs/*-rs` repos:
  `rust-toolchain.toml`, `rustfmt.toml`, `Makefile`, `VERSION`, `AUTHORS`,
  `.editorconfig`, `.gitattributes`, `.gitconfig`, `.gitmodules`,
  `.dockerignore`, `cspell.json`, `codemeta.json`, `CITATION.cff`,
  `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, and `AGENTS.md`.
- `.github/workflows/ci.yml` aligned with the org-wide CI template.
- `src/simd/`: the int8 dot-product kernels, split per architecture (`scalar`,
  `aarch64`, `x86_64`) behind one runtime-detected `dispatch`.

### Performance

- x86-64 gets real int8 dot kernels, one per ISA tier (`SSE2` sign-mask +
  `pmaddwd`, `SSE4.1`/`pmovsxbw`, `AVX2`, and `AVX-512 VNNI` `vpdpbusd`), chosen
  at **runtime** from CPUID — no `-C target-cpu` needed. On an AMD Zen 3 core the
  quantized model's neural net drops from ≈487 µs to ≈84 µs per frame (5.8×), so
  the int8 path is finally *faster* than the float path on x86 instead of slower
  (full frame 519 → 119 µs, ≈84× real time); legacy 40.2 → 38.1 µs. Tier ladder
  measured on that core: 1.3 / 3.5 / 6.5 / 15.3 MACs per cycle (v1–v3).
- `simd::sparse_sgemv8x4` (the GRU matrices, ~90 % of the float network) keeps the
  eight-row accumulator in a register for the whole row group instead of
  load/store per block, accumulating per column in upstream `vec.h` order —
  bit-identical to the portable reference (float NN 289 → 248 µs/frame).
### Changes

- `rust-version` raised to **1.89** so the AVX-512 VNNI tier is unconditional
  (it is still only *used* when CPUID reports `avx512f` + `avx512vnni`; nothing
  forces AVX-512 codegen elsewhere in the crate).
- `chunks_exact(2|4)` sites rewritten as `as_chunks::<N>()` so the crate is clean
  under the lint set of the current toolchain.
- All kernels compute the same exact `i32` value, so quantized output is
  unchanged (`rel_energy 4.8e-6`); `src/simd/tests.rs` asserts SIMD == scalar and
  skips when the feature is not present.

## [0.1.0]

- Initial release.
