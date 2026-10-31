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
- New optional feature `x86-vnni` for the AVX-512 tier (needs Rust ≥ 1.89 for the
  AVX-512 intrinsics; the default build stays on `rust-version = 1.85`).
- All kernels compute the same exact `i32` value, so quantized output is
  unchanged (`rel_energy 4.8e-6`); `src/simd/tests.rs` asserts SIMD == scalar and
  skips when the feature is not present.

## [0.1.0]

- Initial release.
