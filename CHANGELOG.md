# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Weights::Q8` carries a per-output-row `128 · Σ w` correction table, computed in
  `LinearLayer::quantize`. Only the AVX-512 VNNI tier reads it — it is what lets that tier's hot
  loop be one load plus one `vpdpbusd` per chunk instead of a load plus a `vpaddb` plus a
  `vpdpbusd`. Internal (`Weights` is not public), so no public API change.

### Changed

- **x86-64 int8 tier v4 (AVX-512 VNNI)** — the `+128` that `vpdpbusd` needs is paid once per layer
  instead of once per chunk, and the model's hot width (384 bytes = exactly 6 chunks) keeps the
  biased activations in registers for the whole row loop with four independent accumulator chains.
  Measured per row on a Zen 4 core (Ryzen 7 7800X3D), same binary, same data: 4.88 ns with the bias
  in the loop, 4.77 hoisted to a buffer, **3.06** hoisted into registers with four accumulators;
  end to end on that box 52.8 µs → 45.5 µs of network per frame. Exact integer arithmetic
  throughout, so tier v4 stays bit-identical to `simd::scalar` (issue #16).


### Changed

- The tier gate in CI now accepts both `/proc/cpuinfo` spellings for the AVX512BW flag
  (`avx512_bw` and `avx512bw`); a Zen 4 runner prints the second, so the coverage job
  false-negativied on hardware that can actually exercise tier v4 (issue #16).


- **Style ruleset**: the adopted subset of the Google Rust style guide is now
  `doc/styleguide.md` (derivation and measured gaps:
  `doc/styleguide-adoption-plan.md`). Each rule is either tool-enforced or
  explicitly waived. `make style` — part of `make check` and of CI — checks what
  no lint can express: the stable toolchain, module-root purity, the unsafe
  islands, `SAFETY:` justifications, glob-import exemptions, one-module-per-`use`,
  `rustfmt::skip`, and the no-async/no-threads/no-`catch_unwind` rule.
- `Cargo.toml` gained a `[lints]` section (`unsafe_code`, `missing_docs`,
  `unstable_features`, `unwrap_used`, `panic`, `must_use_candidate`,
  `exhaustive_enums`, `exhaustive_structs`, `wildcard_imports`,
  `disallowed_methods`), and `clippy.toml` disallows `catch_unwind` and
  `std::thread::spawn`. `rustfmt.toml` gained `hex_literal_case = Lower`
  (`format_macro_matchers` and `imports_granularity` are nightly-only, so the
  one-module-per-`use` rule is checked by `make style` instead).
- The crate-wide `#![forbid(unsafe_code)]` claim in `AGENTS.md`/`CONTRIBUTING.md`
  was not true in practice (SIMD intrinsics and the C ABI). It is now the honest
  version: `unsafe_code = "deny"` at the crate root, with `#[allow(unsafe_code)]`
  only on the declared islands, and a `SAFETY:` justification per block or file.
- No `unwrap()` left in `src/`: pattern matching where the input proves the case,
  `expect("context")` otherwise.
- The model-geometry constants moved out of the crate root into the leaf `params`
  module; `lib.rs` only declares submodules and re-exports. `rnnoise::FRAME_SIZE`
  and the other sizes are re-exported from the crate root, so the paths are stable.
- `src/fft/plan.rs` → `src/fft/kiss_fft.rs`, named after its primary item
  (`KissFft`). Internal only: `KissFft` was never reachable from outside the
  private `fft` module, so no public path changed.
- `tests/api_surface.rs` names every exported item, so a public rename or removal
  is a compile failure rather than a silent break.

### Deprecated

- `DenoiseState::with_model` and `DenoiseStateV1::with_model` are deprecated in
  favour of `DenoiseState::new_with_model()` and `DenoiseStateV1::new_with_model()`:
  `with_foo()` is reserved for
  closure accessors, so constructors take the `new_with_foo()` form. The aliases
  are source-compatible and will be removed in 0.3.

### Breaking

- `ModelError` is now `#[non_exhaustive]` (guide rule), which means downstream
  exhaustive `match` statements without a wildcard arm no longer compile. This is
  the price of being able to add error variants later without a breaking change.


### Added

- Repository scaffolding aligned with the sibling `lovelace-labs/*-rs` repos:
  `rust-toolchain.toml`, `rustfmt.toml`, `Makefile`, `VERSION`, `AUTHORS`,
  `.editorconfig`, `.gitattributes`, `.gitconfig`, `.gitmodules`,
  `.dockerignore`, `cspell.json`, `codemeta.json`, `CITATION.cff`,
  `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, and `AGENTS.md`.
- `.github/workflows/ci.yml` aligned with the org-wide CI template.
- `src/simd/`: the int8 dot-product kernels, split per architecture (`scalar`,
  `aarch64`, `x86_64`) behind one runtime-detected `dispatch`.
- `src/fft/` split into `plan` (factors, twiddles, per-stage twiddle views),
  `scalar` (the portable reference butterflies), `x86_64` (the vector tier),
  `dispatch` and `tests`; the module root only re-exports.
- Tier-equality tests: every float and int8 kernel is asserted bit-identical to its
  portable reference (`simd/tests.rs`, `fft/tests.rs`, `common/tests`, and
  `weights/tests` for the dense-equivalence of a complete ascending index).
- CI gate for the SIMD tiers, since a skipped tier is not coverage: each run prints the
  runner's ISA flags and the tiers it exercised, and the `simd-tier-coverage` job runs the
  tier-equality tests on a real AVX-512 + VNNI machine when one is wired up through the
  repository variable `avx512_runner`, failing if a tier is skipped. What is provable without
  the hardware (tier v4's `128 · Σ q_x` bias identity) is asserted unconditionally, on every
  runner.

### Fixed

- `simd::x86_64::vnni::dense_q8` subtracted the `128 · Σ q_x` correction over the whole
  activation vector instead of over the length a row covers (`min(m, qx.len())`), so tier v4
  disagreed with the portable reference for any layer narrower than `qx` — the CI failure on
  AVX-512 runners through the tail-width assertion in `simd/tests.rs` (widths 7, 33, 65).
  Exact for every width again; the loads are bounded by the shorter of the two slices (as
  the reference's `zip` is), and the bias identity is asserted per row length so it is
  checkable without AVX-512 hardware.

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
- x86-64 gets runtime-detected **float** tiers, one per ISA level, each keeping the
  reference accumulation order (one accumulator per output, or per lag, in `j` order)
  so they are bit-identical to `simd::scalar`:
  - `simd/x86_64/dense.rs` — 8 outputs per accumulator instead of the SSE2 baseline's 4
    (384×1152 layer: 33.2 → 23.5 µs/frame on a Zen 3 core).
  - `simd/x86_64/xcorr.rs` — the pitch cross-correlation, 4 (SSE2) or 8 (AVX2) lags in
    parallel (7.2 → 3.0 µs/frame in the coarse pitch search).
  - `fft/x86_64.rs` — vector butterflies with per-stage contiguous twiddle views; the
    plan now builds those views so the arithmetic stays the same per element
    (4.86 → 2.5 µs per transform, three transforms per frame).
- A sparse weight index that is **complete and ascending** — every row group lists all
  its column blocks in order, which is the case for the shipped model's GRU matrices —
  accumulates each output in ascending input order, i.e. exactly `dense_sgemv`'s order.
  Such layers are now loaded in dense row-major form at parse time (same bytes, same
  bits), which lets the float network use the wider GEMV tier. Indices that are
  genuinely sparse or out of order still run through the sparse kernel. Measured on a
  Zen 3 core: float NN 239 → 192 µs/frame.
- `Common` precomputes the triangular band weights `j / band_size` with the same f32
  division the runtime used to do, removing ~317 float divisions per band pass.
- `simd::dense_sgemv_blocks`: a dense float layer whose outputs form complete groups of
  eight is stored in a **block-major** permutation of the same values
  (`w[(o/8)*8*m + j*8 + o%8]`), so the AVX2 tier keeps four group accumulators in registers
  for the whole `j` walk instead of loading and storing them once per block — four
  independent add chains in flight, one 32-byte weight load per eight MACs. Every output
  still sums in ascending `j`, so the bits are unchanged (`simd/tests.rs` asserts
  tier == reference, and `rnnoise-demo` output on `test_data/testing.raw` is byte-for-byte
  identical). On a Zen 3 core: 384×1152 20.7 → 15.3 µs per call, conv2 12.5 → 6.6,
  conv1 2.2 → 0.8, dense_out 5.0 → 1.4; full frame 213.5 → 157.4 µs (63.5× real time),
  neural net 192.0 → 135.7 µs.

End to end on an AMD Zen 3 core (plain `cargo bench`, tier v3 selected at runtime, best
of runs): float full frame **270.6 → 208–216 µs** (≈1.3×, 46–48× real time), its DSP
front-end **31.6 → 21.8 µs**; int8 full frame **116.8 → 102–107 µs** (94–98× real
time); legacy **38.1 → 33.8 µs**. Parity is unchanged: 3 samples of 47 520 differ by
1 LSB, relative energy `2.003e-10`.

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
