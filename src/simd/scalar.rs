//! Portable reference kernel: exact int32 dot product.
//!
//! This is the definition the SIMD kernels must match bit for bit, and it is what
//! runs on targets without a detected SIMD path.

pub(crate) fn i8_dot(w: &[i8], x: &[i8]) -> i32 {
    let mut acc = 0i32;
    for (&wv, &xv) in w.iter().zip(x) {
        acc += wv as i32 * xv as i32;
    }
    acc
}

/// `out[o] = scale[o] · (w[o] · x)`, one contiguous int8 row per output.
pub(crate) fn dense_q8(out: &mut [f32], w: &[i8], scale: &[f32], m: usize, n: usize, qx: &[i8]) {
    for o in 0..n {
        out[o] = i8_dot(&w[o * m..o * m + m], qx) as f32 * scale[o];
    }
}
