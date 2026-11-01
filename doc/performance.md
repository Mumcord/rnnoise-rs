# Performance

This is the optimization-oriented guide: where the time goes, what was done about
it, and how to reproduce the numbers. For the full benchmark tables and
methodology see [`BENCHMARKS.md`](../BENCHMARKS.md).

All figures are Apple M4 Pro, single core, `opt-level=3, lto=true,
codegen-units=1`, except the x86-64 row, which is an AMD Ryzen 9 5900X (Zen 3)
with plain `cargo bench` — i.e. the default `x86-64` (SSE2) codegen baseline plus
runtime feature detection, no `-C target-cpu`. Per-frame is the steady-state cost of one `process_frame`;
"real time" is how many times faster than the 10 ms a frame represents.

## Summary

| Configuration | per frame | real-time | notes |
|---|--:|--:|---|
| current model, float (default) | ~312 µs | ~32× | bit-exact with C, zero deps |
| current model, int8 + `sdot` (aarch64) | ~105 µs | ~95× | opt-in, audibly identical |
| current model, int8 + `pmaddwd` (x86-64, Zen 3) | ~103 µs | ~97× | runtime-detected AVX2; 4.3× vs the old scalar path |
| current model, float, x86-64 Zen 3 | ~210 µs | ~47× | see the x86-64 section below |
| legacy model (`legacy-model`) | ~26 µs | ~309× | **faster than `nnnoiseless`** |
| — `nnnoiseless` (same old model) | ~28 µs | ~290× | for reference |

The current model is ~13× larger than the old one, so it cannot match the tiny
old model on raw throughput — but it denoises far better, and it runs faster than
the official C library (~1.5× on the same model; see [BENCHMARKS.md](../BENCHMARKS.md)).

## Where the time goes

For the **current model**, the neural net is ~89 % of a frame; the DSP front-end
(FFT, bands, pitch, features) is the rest. The net moves ~11.5 MB of float weights
per frame, but at ~41 GB/s it's well under the M4 Pro's single-core ceiling — so
it's **instruction/load-bound, not DRAM-bandwidth-bound**. That distinction drives
every optimization decision below.

For the **legacy model**, the net is tiny (~10 µs) and the front-end (FFT + pitch)
dominates, so the legacy work targeted the FFT and pitch.

## What was done

### Cache-friendly, auto-vectorizing GEMV (current model, parity-safe)

The dense matmuls are written as sequential SAXPYs (`j` outer, `i` inner), which
stream the weight matrix in order and let the compiler vectorize, while preserving
the exact per-output accumulation order — so the result stays **bit-identical** to
the C reference. Reorganising the GEMVs this way (and giving the sparse 8×4 kernel
bounds-check-free fixed-length slices) made the float path **faster than the C
library** (≈1.5×), at full parity.

### int8 + NEON `sdot` (current model, opt-in)

`RnnModel::quantized()` stores conv2 and the GRUs as transposed dense int8 with a
per-output scale, quantizes activations to int8, and computes each output with a
NEON `sdot` (4 int8 MACs per lane per instruction). Measured: **NN 277 → 69 µs
(4.0×)**, **full frame 312 → 105 µs (3.0×)**, footprint ~4× smaller, accuracy
`rel 4.8e-6` (see [models.md](models.md#int8-quantized-model)).

Key lesson — because the workload is instruction-bound, *how* you do int8 matters:

| approach | result |
|---|---|
| naive int8 (dequantize to f32 in the loop) | **0.81×** — *slower* (adds instructions) |
| f32 weights (no conversion, 4× memory) | *slower* (4× cache traffic) |
| **int8 + `sdot`** (fewer instructions, int math) | **3–4× faster** |

`sdot` is emitted via stable inline `asm!` (the `vdotq_s32` intrinsic is still
nightly-only), guarded by runtime `is_aarch64_feature_detected!("dotprod")`, with
a scalar fallback that yields the identical integer result.

### x86-64 float tiers (parity-safe, runtime-detected)

The int8 tiers only help the quantized model, so the float path used to run at the
plain `x86-64` (SSE2, 4-lane) codegen rate even on an AVX2 machine. `src/simd` now has
float tiers for the three hot DSP/DNN loops, each of them **bit-identical to the
portable reference** because it keeps the reference's accumulation order and never
fuses a multiply with an add:

| kernel | what the tier does | measured on a Zen 3 core |
|---|---|--|
| `simd/x86_64/dense.rs` | 8 outputs per accumulator instead of 4 | 384×1152 layer 33.2 → 23.5 µs/frame |
| `simd/x86_64/xcorr.rs` | 4 (SSE2) / 8 (AVX2) lags in parallel, one accumulator per lag | coarse pitch search 7.2 → 3.0 µs/frame |
| `fft/x86_64.rs` | vector butterflies over the inner `j`, reading per-stage contiguous twiddle views built by the plan | 4.86 → 2.5 µs per transform (3 per frame) |

Two structural changes make those tiers pay off:

- **Complete sparse indices are dense-equivalent.** The shipped model's GRU matrices are
  stored in the sparse 8×4 layout, but every row group lists all `nb_inputs/4` blocks in
  ascending order. The walk then visits each output's contributions in ascending input
  order — exactly `dense_sgemv`'s order — so `weights.rs` loads such layers in dense
  row-major form at parse time (same bytes, same bits) and the GEMV can run through the
  wider tier. Out-of-order or genuinely sparse blobs keep the sparse kernel.
- **Band weights are precomputed** in `Common` (`j / band_size`, the same f32 division as
  the runtime did), removing ~317 float divisions per band pass.

End to end, plain `cargo bench`, tier v3 selected at runtime (best of runs):

| | before | after |
|---|--:|--:|
| float full frame | 270.6 µs | **208–216 µs** (46–48× real time) |
| — float front-end | 31.6 µs | **21.8 µs** |
| int8 full frame | 116.8 µs | **102–107 µs** (94–98× real time) |
| legacy full frame | 38.1 µs | **33.8 µs** |

Parity is unchanged by all of this (`3 / 47 520 samples, 1 LSB`, `2.003e-10`), which is
the point of keeping the accumulation order: the tiers are a layout and width change, not
an arithmetic change. Aarch64 keeps the portable reference for these loops, so its numbers
are unchanged.

### x86-64 int8 tiers (parity-safe, runtime-detected)

Before this, x86-64 had no int8 dot kernel at all: on the `x86-64` baseline codegen
(`SSE2`) a byte dot product cannot be vectorized — `pmaddubsw` is SSSE3 and
`vpdpbusd` is VNNI — so the int8 path was **slower** than float (487 vs 289 µs of
NN per frame).

`src/simd/x86_64/` now has one kernel per ISA tier, chosen at **runtime** by CPUID
(`src/simd/x86_64/select.rs`), once per matmul call, never through `-C target-cpu`:

| tier | ISA | kernel | MACs/cycle on this Zen 3 core |
|---|---|---|--:|
| v1 | SSE2 (x86-64 baseline) | `punpcklbw` + `cmpgt` sign mask + `pmaddwd` | 3.5 |
| v2 | SSE4.1 (x86-64-v2) | `pmovsxbw` + `pmaddwd` | 6.5 |
| v3 | AVX2 (x86-64-v3) | same shape, 16 lanes | **15.3** |
| v4 | AVX-512 VNNI (x86-64-v4) | `vpdpbusd`, unsigned × signed → biased + corrected | ~30 (no VNNI CPU here) |

The same idea applies to the sparse 8×4 GEMV: `x86_64/sparse8x4.rs` keeps the
eight-row accumulator in a ymm register for the whole row group instead of
reloading and storing it per block, and accumulates per column in the order
upstream `vec.h` uses, so it is bit-identical to `scalar::sparse_sgemv8x4`.

End to end, plain `cargo bench`, tier v3 selected at runtime:

| | before | after |
|---|--:|--:|
| int8 neural net | 487 µs | **84 µs** (5.8×) |
| int8 full frame | 519 µs | **119 µs** (84× real time) |
| legacy full frame | 40.2 µs | 38.1 µs |

Tier v4 is available on Rust ≥ 1.89 (AVX-512 intrinsics + `avx512f` target feature),
which is why the crate's `rust-version` is 1.89. It does not force AVX-512 codegen:
a binary built with 1.89+ runs tier v3 on an AVX2-only CPU and v4 on a Zen 4.

Every int8 tier produces the **same exact integer** (products and pair sums fit in `i32`
for the model's widths), so the quantized output is unchanged — the accuracy test
still reports `rel_energy 4.826e-6`, and `src/simd/tests.rs` asserts tier == scalar
for every tier the CPU reports, skipping the others. The VNNI bias identity
(`Σ(w+128)·x − 128·Σx == Σ w·x`) is also unit-tested in pure Rust, so it is checked
even on runners without AVX-512.

## Choosing a configuration

- **Default (float):** highest quality, bit-exact, zero deps, ~32× real time —
  fine for real-time on one core with lots of headroom.
- **int8 (`.quantized()`):** ~3× faster and ~4× smaller, imperceptible quality
  loss — use it for many concurrent streams, embedded, or battery-sensitive cases.
- **legacy (`legacy-model`):** smallest/fastest, lower quality — use only when you
  specifically want the old model's profile.

## Reproducing

```sh
# current model: float + int8 breakdown (and legacy if the feature is on)
cargo bench --bench process
cargo bench --features legacy-model --bench process

# fair, isolated legacy vs nnnoiseless comparison
cargo run --release --features legacy-model --example bench_legacy

# end-to-end on your own 48 kHz mono RAW
cargo run --release --bin rnnoise-demo -- noisy.raw out.raw
```

Numbers vary with CPU and thermal state — treat them as ratios, not absolutes.
The benches build a deterministic noisy frame and time `process_frame` in a tight
loop after warm-up; the `process` bench also reports a front-end-only (silent
input) figure so you can separate the NN from the DSP.

## Remaining levers

See [`BENCHMARKS.md`](../BENCHMARKS.md) §"How to speed up" and
[`TODO.md`](../TODO.md): x86 VNNI for the int8 kernel, f16 SIMD, multi-threading
the GEMVs for batch, and a real-input FFT for the current model (the SIMD tier is done;
a real-input transform would relax its bit-exactness bound).
