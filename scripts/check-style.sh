#!/usr/bin/env bash
# =============================================================================
# rnnoise-rs — style gate for the rules that no compiler lint can express.
# See doc/styleguide.md. Runs as part of `make style` and `make check`.
# =============================================================================
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1

fail=0
bad() { printf 'style: %s\n' "$1"; fail=1; }

# --- 1. Stable toolchain, no unstable features (guide: "No unstable features")
channel=$(sed -n 's/^channel = "\([^"]*\)".*/\1/p' rust-toolchain.toml)
[ "$channel" = "stable" ] || bad "rust-toolchain.toml channel is '$channel'; unstable features are not allowed"
grep -rn '^#!\[*feature' src tests benches examples 2>/dev/null | grep -q . \
    && bad "unstable feature gate found"

# --- 2. Module roots only declare submodules and re-export (repo rule, stricter
#     than the guide's "small amount of glue" allowance)
for f in src/lib.rs $(find src -name 'mod.rs' | sort); do
    offenders=$(awk '
        BEGIN { inattr = 0 }
        {
            line = $0
            if (inattr) { if (line ~ /\)\]$/) { inattr = 0 }; next }
            if (line ~ /^[[:space:]]*#/) { if (line !~ /\]\]$/) { inattr = 1 }; next }
            if (line ~ /^[[:space:]]*$/) { next }
            if (line ~ /^[[:space:]]*\/\//) { next }
            if (line ~ /^[[:space:]]*(pub |pub\(crate\) )?(mod|use) /) { next }
            print line
        }' "$f")
    [ -z "$offenders" ] || bad "$f: module root must only declare submodules and re-export (found: $(printf '%s' "$offenders" | head -1))"
done

# --- 3. Unsafe code is confined to the declared islands (code, not prose)
ISLANDS='^(src/capi\.rs|src/simd/|src/fft/x86_64\.rs|src/fft/dispatch\.rs|src/fft/tests\.rs)'
# Only the code forms count: `unsafe {`, `unsafe fn`, `unsafe extern "C"`.
stray=$(grep -rnE 'unsafe (\{|fn|extern)' src tests 2>/dev/null | grep -vE ':[[:space:]]*(//|///|//!)' \
    | cut -d: -f1 | sort -u | grep -vE "$ISLANDS")
[ -z "$stray" ] || bad "unsafe code outside the declared islands: $(printf '%s' "$stray" | tr '\n' ' ')"

# --- 4. Each unsafe block needs a SAFETY justification: the comment above the block,
#     or a justification covering the whole file (both allowed by the guide).
for f in $(grep -rln 'unsafe {' src tests 2>/dev/null | sort); do
    case "$f" in *tests.rs|tests/*) continue ;; esac        # guide exception: tests may panic
    grep -q 'SAFETY' "$f" && continue
    bad "$f: unsafe blocks need a SAFETY: justification (per block, or file-level)"
done

# --- 5. Glob imports: only the guide's exemptions (`use super::*` in inline modules,
#     `pub use m::*` in non-leaf modules, `core::arch` intrinsics)
for f in $(grep -rn 'use [^ ]*::\*' src tests 2>/dev/null | cut -d: -f1 | sort -u); do
    grep -q 'core::arch::' "$f" && continue
    grep -q 'use super::\*' "$f" && continue
    bad "$f: glob import outside the documented exemptions"
done

# --- 6. No `use foo::{bar::Baz, Qux}` (one module per use statement)
for f in $(find src tests benches examples -name '*.rs' | sort); do
    if grep -qE '^use [^ ]*\{[^}]*::' "$f"; then
        bad "$f: use statement imports from more than one module"
    fi
done

# --- 7. No `#[rustfmt::skip]` except manual alignment or generated code
for f in $(grep -rln 'rustfmt::skip' src tests benches examples 2>/dev/null); do
    bad "$f: rustfmt::skip (allowed only for manual alignment or generated code)"
done

# --- 8. Real-time path: no async, no threads, no catch_unwind, nothing before main()
for pat in 'async ' 'await ' 'thread::spawn' 'catch_unwind' '\\bctor\\b'; do
    if grep -rn "$pat" src 2>/dev/null | grep -vE ':\s*(//|///|//!)' | grep -q .; then
        bad "found '$pat' in src/ (doc/styleguide.md: no async, no threads, no catch_unwind)"
    fi
done

# --- 9. `clippy::pedantic` stays off as a whole (rule C9): the DSP casts and the
#     deliberately-near-f32 constants are the arithmetic, not style.
grep -q 'clippy::pedantic' Cargo.toml 2>/dev/null && bad "clippy::pedantic enabled; rule C9 waives it"

if [ "$fail" -ne 0 ]; then
    printf '\nstyle gate FAILED\n'
    exit 1
fi
echo 'style gate: ok (toolchain, module roots, unsafe islands, SAFETY, globs, imports, rustfmt::skip, async/threads)'
