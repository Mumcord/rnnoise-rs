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

/// Port of `sparse_sgemv8x4` (float weights) — the portable reference. Accumulated
/// per column (`out[row] += w[col*8+row] * x[pos+col]`), which is exactly the order
/// upstream `vec.h` uses, so a vectorised version over the 8 rows is bit-identical.
pub(crate) fn sparse_sgemv8x4(out: &mut [f32], w: &[f32], idx: &[i32], rows: usize, x: &[f32]) {
    for v in out.iter_mut() {
        *v = 0.0;
    }
    let mut wi = 0usize;
    let mut ii = 0usize;
    let mut i = 0usize;
    while i < rows {
        let cols = idx[ii] as usize;
        ii += 1;
        for _ in 0..cols {
            let pos = idx[ii] as usize;
            ii += 1;
            for c in 0..4 {
                for r in 0..8 {
                    out[i + r] += w[wi + c * 8 + r] * x[pos + c];
                }
            }
            wi += 32;
        }
        i += 8;
    }
}
