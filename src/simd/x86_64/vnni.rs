//! Tier v4 — AVX-512 VNNI (`vpdpbusd`): four int8 MACs per lane in one
//! instruction, i.e. 64 MACs per iteration — the only tier that does real int8
//! multiply-accumulate in hardware.
//!
//! `vpdpbusd` is **unsigned × signed**, so the weights are biased by +128 in
//! register and the constant `128 · Σ q_x` — over exactly the length a row covers —
//! is subtracted per output. Products are
//! at most `255 · 127` and the row sum at most `384 · 32385 ≈ 1.2e7`, still exact
//! in `i32`, so the result equals the scalar reference exactly.
//!
//! Needs Rust ≥ 1.89 for the AVX-512 intrinsics and the `avx512f` target feature
//! (hence the crate's `rust-version`), and the CPU must report `avx512f` + `avx512bw` +
//! `avx512vnni` — `vpdpbusd` is VNNI, the +128 bias uses AVX512BW `add_epi8`. Nothing here forces AVX-512 codegen
//! anywhere else: `dispatch` calls in only when CPUID reports the CPU has it.

use core::arch::x86_64::*;

#[target_feature(enable = "avx512f")]
#[target_feature(enable = "avx512bw")]
#[target_feature(enable = "avx512vnni")]
// SAFETY: requires AVX-512F + AVX512BW + AVX-512 VNNI; `select` only calls this after all
// three runtime detections (`set1_epi8`/`add_epi8` are AVX512BW). Unaligned 64-byte loads
// over `min(w.len(), x.len())` bytes, which is the length the reference zips to, so no load
// reads past either slice; `vpdpbusd` is unsigned x signed, which is why the caller passes
// the `128 * sum(x)` correction for exactly that length.
unsafe fn dot_biased(w: &[i8], x: &[i8], bias: i32) -> i32 {
    let mut acc = _mm512_setzero_si512();
    // +128 as bytes: 0x80. `vpaddb` is modular, so this is the unsigned bias.
    let sign = _mm512_set1_epi8(-128);
    let len = w.len().min(x.len());
    let chunks = len / 64;
    for k in 0..chunks {
        let a = _mm512_add_epi8(
            _mm512_loadu_si512(w.as_ptr().add(k * 64) as *const __m512i),
            sign,
        );
        let b = _mm512_loadu_si512(x.as_ptr().add(k * 64) as *const __m512i);
        acc = _mm512_dpbusd_epi32(acc, a, b);
    }
    let mut sum = _mm512_reduce_add_epi32(acc) - bias;
    for k in chunks * 64..len {
        sum += (w[k] as i32 + 128) * x[k] as i32;
    }
    sum
}

#[target_feature(enable = "avx512f")]
#[target_feature(enable = "avx512bw")]
#[target_feature(enable = "avx512vnni")]
pub(crate) unsafe fn dense_q8(
    out: &mut [f32],
    w: &[i8],
    scale: &[f32],
    m: usize,
    n: usize,
    qx: &[i8],
) {
    // `128 * Σ q_x` is the same for every output of this layer, so it is computed once —
    // but over the elements a row actually covers, `min(m, qx.len())`, not over the whole
    // activation vector. A layer narrower than `qx` (the tail widths in `simd/tests.rs`, and
    // any layer whose input is shorter than the quantised activation buffer) has to subtract
    // the narrower bias, otherwise the tier returns `reference - 128 * Σ q_x[m..]`.
    let covered = m.min(qx.len());
    let mut sx = 0i32;
    for &v in &qx[..covered] {
        sx += v as i32;
    }
    let bias = 128 * sx;
    for o in 0..n {
        out[o] = dot_biased(&w[o * m..o * m + m], qx, bias) as f32 * scale[o];
    }
}
