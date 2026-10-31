//! Per-architecture router. The actual tier choice happens in `x86_64::select` /
//! `aarch64::select`, at runtime, from cached CPUID flags.

#[cfg(target_arch = "x86_64")]
pub(crate) fn dense_q8(out: &mut [f32], w: &[i8], scale: &[f32], m: usize, n: usize, qx: &[i8]) {
    crate::simd::x86_64::select::dense_q8(out, w, scale, m, n, qx);
}

#[cfg(target_arch = "aarch64")]
pub(crate) fn dense_q8(out: &mut [f32], w: &[i8], scale: &[f32], m: usize, n: usize, qx: &[i8]) {
    crate::simd::aarch64::select::dense_q8(out, w, scale, m, n, qx);
}

#[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
pub(crate) fn dense_q8(out: &mut [f32], w: &[i8], scale: &[f32], m: usize, n: usize, qx: &[i8]) {
    crate::simd::scalar::dense_q8(out, w, scale, m, n, qx);
}

#[cfg(feature = "legacy-model")]
#[cfg(target_arch = "x86_64")]
pub(crate) fn i8_dot(w: &[i8], x: &[i8]) -> i32 {
    crate::simd::x86_64::select::i8_dot(w, x)
}

#[cfg(feature = "legacy-model")]
#[cfg(target_arch = "aarch64")]
pub(crate) fn i8_dot(w: &[i8], x: &[i8]) -> i32 {
    crate::simd::aarch64::select::i8_dot(w, x)
}

#[cfg(feature = "legacy-model")]
#[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
pub(crate) fn i8_dot(w: &[i8], x: &[i8]) -> i32 {
    crate::simd::scalar::i8_dot(w, x)
}
