#!/usr/bin/env bash
# Checks the rules that no lint can express (doc/styleguide.md — the review rules).
# Part of `make check` through `make style`.
#
# Text checks, not an AST analysis: they catch the common case and fail loudly, which
# is what a review rule needs in order to survive review.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/src"
fails=0

flag() {
  echo "style: $1" >&2
  fails=$((fails + 1))
}

# The declared unsafe islands (doc/styleguide.md §unsafe).
islands() {
  cat <<'EOF'
src/capi.rs
src/simd
src/fft/x86_64.rs
src/fft/dispatch.rs
src/simd/tests.rs
src/simd/coverage.rs
src/fft/tests.rs
EOF
}

in_island() {
  local f="$1"
  for island in $(islands); do
    case "$f" in
      "$REPO/$island" | "$REPO/$island"/*) return 0 ;;
    esac
  done
  return 1
}

# --- the pinned toolchain stays on stable ----------------------------------------
if [ -f "$REPO/rust-toolchain.toml" ]; then
  grep -q 'channel = "stable"' "$REPO/rust-toolchain.toml" ||
    flag "rule B: rust-toolchain.toml must pin channel = \"stable\""
fi

# --- module-root purity: lib.rs and mod.rs declare and re-export only -----------
for root in "$SRC/lib.rs" "$SRC"/*/mod.rs; do
  [ -e "$root" ] || continue
  offenders=$(grep -nE '^\s*(pub |pub\(crate\) )?(fn|struct|enum|trait|impl|type|const|static)' "$root" || true)
  [ -z "$offenders" ] || flag "module-root purity (review rule): ${root#"$REPO"/} defines items
$offenders"
done

# --- unsafe usage only inside the declared islands, with a SAFETY justification ---
while IFS= read -r file; do
  [ -z "$file" ] && continue
  in_island "$file" || flag "unsafe outside the declared islands: ${file#"$REPO"/}"
  grep -q 'SAFETY:\|# Safety' "$file" ||
    flag "missing a SAFETY: justification (per block or per file): ${file#"$REPO"/}"
  grep -q 'allow(unsafe_code' "$file" ||
    grep -q 'allow(unsafe_code' "$(dirname "$file")/mod.rs" ||
    grep -q 'allow(unsafe_code' "$SRC/lib.rs" ||
    flag "unsafe island without an island #[allow(unsafe_code)]: ${file#"$REPO"/}"
done < <(grep -rl 'unsafe {\|unsafe fn' "$SRC" | sort)

# --- one module per use block ---------------------------------------------------
while IFS= read -r line; do
  [ -z "$line" ] && continue
  flag "one module per use block (review rule): ${line#"$REPO"/}"
done < <(grep -rnE 'use [A-Za-z_]+::[A-Za-z_]+::\{[^}]*::' "$SRC" || true)

# --- glob imports: only the guide's exemptions ----------------------------------
while IFS= read -r line; do
  [ -z "$line" ] && continue
  file=$(printf '%s\n' "$line" | sed 's/:.*//')
  case "$line" in
    *'use super::*;'*) continue ;;                       # inline test modules
    *'pub use '*'\*;'*) continue ;;                      # non-leaf module re-exports
    *'core::arch'*) in_island "$file" && continue ;;     # SIMD island exemption
  esac
  grep -q 'allow(.*wildcard_imports' "$file" ||
    flag "glob import without the exemption: ${file#"$REPO"/}"
done < <(grep -rn 'use [A-Za-z_:]*::\*;' "$SRC" || true)

# --- no async, no catch_unwind, no threads, no unwrap in the crate -------------
grep -rq 'async ' "$SRC" && flag "no async in the DSP path (review rule)"
grep -rq 'catch_unwind' "$SRC" && flag "no catch_unwind (review rule)"
grep -rq 'thread::spawn' "$SRC" && flag "no thread spawn (review rule)"
found=$(grep -rn '\.unwrap()' "$SRC" || true)
[ -n "$found" ] && flag "no unwrap() in src/ (rule B):
$found"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  flag "#[rustfmt::skip] without a cited exemption: ${line#"$REPO"/}"
done < <(grep -rn 'rustfmt::skip' "$SRC" | grep -v 'styleguide' || true)

if [ "$fails" -eq 0 ]; then
  echo "style: ok (the rules no lint can express)"
else
  echo "style: $fails rule(s) broken" >&2
  exit 1
fi
