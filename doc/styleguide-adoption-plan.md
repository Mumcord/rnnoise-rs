# Adopting the Google Rust Style Guide in `rnnoise-rs`

Plan for adapting <https://google.github.io/styleguide/rustguide.html> to this
repository. Nothing here changes numerical behaviour; parity is the binding
constraint and the guide's API-design rules must be reconciled with it.

Status: **proposal** — decision table (§2, §3) needs sign-off before the sweep.

---

## 1. Framing

The guide is a *Google-internal* guide: most rules restate the public Rust style
guide + Rust API Guidelines, and the rest is driven by large-scale changes (LSCs)
and Google-specific build systems (`[chrome]`, `[Fuchsia]` rules).

Adopting it here means three buckets, and the bucket must be stated per rule:

| Bucket | Meaning | Enforcement |
|---|---|---|
| **A — Adopt as-is** | Rules that already match the repo or are tool-enforced | CI gate (`make check`) + `[lints]` |
| **B — Adopt as repo policy** | New rules worth enforcing mechanically | new lints, `rustfmt.toml` keys, `scripts/check-style.sh` |
| **C — Waive / scope with rationale** | Rules that conflict with faithful-port, parity, or real-time audio | written down in the guide, exempt by name |

Binding scope: the guide itself distinguishes library code (binding) from
application code (advisory). For this repo:

- `src/` library path → **binding**
- `src/bin/`, `examples/`, `benches/`, `tests/` → **advisory** (the guide's own
  exceptions apply: `unwrap` in tests, `Vec` returns in application code)
- `src/simd/`, `src/fft/scalar.rs`, `src/nnet.rs`, `src/pitch.rs`,
  `src/celt_lpc.rs` (parity-critical) → **binding only where it cannot change
  accumulation order or expression order** (see §3, rule C1)

Deliverables to write: `doc/styleguide.md` (the adopted subset as a repo
standard), plus short pointers in `AGENTS.md` and `CONTRIBUTING.md`.

---

## 2. What already complies (no work, just cite in the guide)

- `rustfmt` (max_width = 100) — matches the guide's configurable formatting set.
- Clippy `-D warnings` already covers `wrong_self_convention`,
  `should_implement_trait`, `new_without_default`, `len_without_is_empty`,
  `derivable_impls`, `borrowed_box`, `ptr_arg`.
- `missing_docs` is currently **clean** — verified with
  `RUSTFLAGS="-W missing_docs" cargo clippy --all-targets`. Not yet a gate.
- Public docs use `///`/`!` with Markdown and punctuation; `//!` at file top ✓.
- `Result` for recoverable errors, `Option` for obvious failures ✓.
- No `panic::catch_unwind`, no threads, no async, no macros, no `#[doc(hidden)]`
  access, no unstable features, no pre-main code (lazy `OnceLock` at first use).
- `&[T]`/`&str`/`Option<&T>` parameter shapes ✓ (no `&Vec<T>`, `&String`,
  `&Option<T>`); tuple structs are newtypes only (`RNNModel`, `Cpx`-style).
- Test modules are `#[cfg(test)] mod tests` inside leaf modules — explicitly
  allowed by the guide as a sub-module of a non-leaf module.

So the first commit is mostly *documentation*: record what is already true so
reviewers stop re-litigating it.

---

## 3. Rules that conflict with this repo's premises (bucket C)

These need an explicit written exemption, otherwise the guide becomes an argument
generator on PRs.

| # | Guide rule | Conflict here | Decision |
|---|---|---|---|
| C1 | Accept `impl IntoIterator` in library APIs; prefer returning iterators over `Vec` | RNNoise kernels must keep the C reference's exact expression/accumulation order; fixed-size arrays (`[f32; 5]`, `[f32; 2]`) and `&mut [f32]` out-parameters are part of the parity contract | **Waive inside parity-critical modules.** Keep `&[T]`/`&mut [T]` slices. Add a lint-free carve-out comment in `doc/styleguide.md`. |
| C2 | Name source files/leaf modules after the primary user-defined item | Current names mirror upstream C files (`celt_lpc.rs`, `nnet.rs`, `pitch.rs`, `plan.rs`) and are the parity traceability anchor (`/// `frame_synthesis`: …`) | **Waive for upstream-derived modules**, adopt elsewhere. Minimum action: rename `fft/plan.rs` → `fft/kiss_fft.rs` (primary item `KissFft`) and keep the C-file name in the module doc comment. |
| C3 | Flat file layout for one crate's sources `[chrome]` | Chrome-scoped and explicitly excepted for Cargo-built code; the repo already uses `src/simd/`, `src/fft/` | **Not applicable.** State that the conventional Cargo layout is the repo standard. |
| C4 | "Don't write unsafe code unless unavoidable" + per-block `SAFETY:` comments | `core::arch` intrinsics are unavoidable for the SIMD tiers; `unsafe` cannot coexist with the current `forbid(unsafe_code)` claim in `AGENTS.md` | **Adopt the unsafe policy, fix the claim.** Crate-level `#![deny(unsafe_code)]` + `#[allow(unsafe_code)]` on the SIMD/FFI islands only, and require a `SAFETY:` comment per unsafe block. Audit: **32 unsafe blocks, 6 unsafe `extern "C"` fns, only 2 files carry `SAFETY:` comments** (`simd/*select*`, `simd/tests`, `fft/dispatch`, `fft/tests` have none at the call sites). |
| C5 | Avoid `Rc`/`Arc` | `Arc<RnnModel>` is the intended sharing model (one immutable model, many `DenoiseState`s) | **Accept as the documented exception**; keep `OnceLock<Arc<_>>` singletons. Optionally gate with `clippy.toml` `disallowed-types` + `#[allow]` at the 10 known sites. |
| C6 | `dyn Trait` is discouraged in libraries | `legacy-model` path uses `Arc<dyn RealToComplex<f32>>` from `rustfft` — forced by the dependency | **Not applicable** (external crate, size-of-code exception). |
| C7 | Prefer `enum` params over `bool` | Applies to public API only; internal bools (`kf_factor`, `compute_frame_features`) mirror C control flow | **Adopt for public API**; advisory internally. `compute_frame_features() -> bool` should become `Option<...>`/`Result` if it ever becomes public. |
| C8 | `#[non_exhaustive]` on public enums/structs | `pub enum ModelError` is public API used by callers; adding variants later breaks exhaustive matches | **Adopt** (`ModelError`). Requires a CHANGELOG entry. `RnnModel`/`DenoiseState` have private fields → no action. `Cpx` is not exported publicly → no action. |
| C9 | Per-codebase test framework (`rust_gtest_interop`, `#[fuchsia::test]`) | Open-source crate | **Not applicable**; keep `#[test]`. Adopt only the assertion-context-string rule. |
| C10 | "Don't start new threads via std" `[chrome]` + "no async `[chrome]`" | These are chrome-scoped but *fit* a real-time audio crate perfectly (audio callback must not allocate or spawn) | **Adopt as repo rules** despite the `[chrome]` tag: no threads, no async in the DSP path. Enforce with `clippy.toml`/CI grep. |
| C11 | "Don't use abbreviations" | `capi`, `nnet`, `xcorr`, `qx`, `ac`, `EBAND20MS` — upstream-derived and unambiguous in context | **Adopt for new names**; grandfather existing ones, since renaming them breaks the upstream cross-reference. |
| C12 | "Comments should say something the code doesn't" | Repo docs deliberately cite upstream `*.c` functions — that *is* insight for a faithful port | **Explicitly allowed**; keep. |

---

## 4. Bucket B — make the adopted rules enforceable

### 4.1 `Cargo.toml` `[lints]` (new)

```toml
[lints.rust]
unsafe_code = "deny"          # makes the AGENTS.md claim real; islands allow-override
missing_docs = "deny"
unsafe_op_in_unsafe_fn = "deny"
unstable_features = "deny"

[lints.clippy]
all = { level = "deny", priority = -1 }
pedantic = "warn"
must_use_candidate = "warn"
exhaustive_enums = "warn"
exhaustive_structs = "warn"
unwrap_used = "deny"          # src only; tests keep unwrap via allow
expect_used = "warn"
panic = "warn"
single_call = "warn"          # if the installed clippy supports it
disallowed_methods = "deny"   # catch_unwind, Arc::new (see 4.3)
module_name_repetitions = "allow"   # C2/C11 grandfather
```

### 4.2 `rustfmt.toml` additions

```toml
hex_literal_case = "Lower"      # works on the pinned stable rustfmt (verified)
format_macro_matchers = true    # accepted on stable (verified)
imports_granularity = "Module"  # effective on stable here (verified)
# group_imports = "Standard"     -> nightly-only, so skip (guide's own opt-out clause)
```

`imports_granularity = Module` also mechanically implements the guide's
"one module per `use`" rule. Existing `use core::arch::x86_64::*` glob imports
stay as a documented exception (intrinsics cannot be imported individually
practically); `use super::*` inside test modules is already an allowed case.

### 4.3 `clippy.toml` + `scripts/check-style.sh` (new)

Mechanical checks the lints cannot express:

1. every `unsafe {` block must have a `SAFETY:` comment above it,
2. `unsafe` may only appear in the declared islands (`src/simd/**`,
   `src/fft/x86_64.rs`, `src/capi.rs`),
3. no `#![feature(...)]` and `rust-toolchain.toml` channel must be `stable`,
4. no `std::thread`, `tokio`, `async`, `catch_unwind` under `src/`,
5. `lib.rs`/`mod.rs` contain only `mod` + `pub use` + doc comments (our own
   stricter rule; see §5.1).

Wire into `Makefile` as `make style` and into `check`, plus CI step.

### 4.4 Naming and API-shape conventions to write down

- Constructor naming per guide: `new()`, `new_with_foo()`, `try_new()` for
  `Result`-returning constructors. **Conflict:** `DenoiseState::with_model(...)`
  and `RnnModel::from_bytes(...)`. `with_foo` is reserved by the guide for
  closure accessors. Decision needed: rename to `new_with_model()` / keep
  `from_bytes` (value-to-value conversion is fine) — renaming is a breaking
  change → CHANGELOG + deprecation shim for one release, or do it before 1.0.
- Getter/setter vocabulary (`foo()`, `foo_mut()`, `take_foo()`, `set_foo()`,
  `replace_foo()`, `with_foo()`) — adopt as the naming contract for any future
  public accessor; current public getters (`KissFft::nfft()`) already comply.
- Pair important `From` impls with an inherent constructor: `RnnModel::from_bytes`
  is the primary path → add `impl From<&[u8]> for RnnModel` only if it can fail
  without an error type, otherwise keep `from_bytes` and document why.
- Trait coverage for public types: `ModelError` has `Display + Error` ✓ but not
  `Copy` (has `String` variants → impossible, document); `RnnModel` should
  implement `Clone` and `Debug`; `DenoiseState` already has `Default` (manual,
  not derivable — fine).
- `#[must_use]` on pure public functions: currently **zero** `#[must_use]` in
  `src/`. `process_frame` (returns VAD probability) and `quantized` (returns
  `Self`) are the candidates.

---

## 5. Bucket A/B — the concrete sweep (measured, small)

### 5.1 Module roots

`src/lib.rs` currently holds constants (`FRAME_SIZE`, `WINDOW_SIZE`, `FREQ_SIZE`,
`NB_BANDS`, `NB_FEATURES`, `PITCH_*`, `EBAND20MS`) — that violates our own
"module roots only re-export" rule and the guide's non-leaf-module rule.

Move to a leaf module (e.g. `src/params.rs` or `src/frame.rs`) and re-export
from `lib.rs`; `pub use params::{...}` keeps `rnnoise::FRAME_SIZE` stable, so
**no API break**. Also move the crate-level `#![allow(clippy::...)]` block to the
modules that actually need it, so the parity-exemptions are visible per-module
rather than blanket.

### 5.2 Findings from the audit (run on this toolchain)

| Rule | Sites | Action |
|---|---|---|
| `unwrap` in `src/` (prefer `expect`) | `src/weights.rs:219`, `:227`, `:473`, `:474`, `src/legacy.rs:143`, `:164` | convert to `expect("…")` with context |
| `#[must_use]` candidates | `src/denoise.rs:49`, `:54`, `src/weights.rs:389`, `src/legacy.rs:572` | add `#[must_use]` |
| public enum should be `#[non_exhaustive]` | `src/weights.rs:20` (`ModelError`) | add + CHANGELOG |
| `SAFETY:` comment per unsafe block | `src/simd/x86_64/select.rs` (12 blocks), `src/simd/aarch64/select.rs` (2), `src/simd/tests.rs` (13), `src/fft/tests.rs` (1), `src/fft/dispatch.rs` (1) | add block-level comments or restructure dispatch so the unsafe boundary is one function with a safety doc |
| unsafe-island enforcement | 6 `unsafe extern "C"` fns in `src/capi.rs` | add per-fn safety notes (caller obligations) + `#[allow(unsafe_code)]` on the island, `deny` at crate root |
| module/file naming (C2) | `src/fft/plan.rs` → `kiss_fft.rs` | rename; keep upstream name in the `//!` header |
| `use` granularity | any `{a::B, a::C}` grouping | new rustfmt key reformats automatically |

Total mechanical surface: **~20 line-level edits + 3 config files + 1 script.**
The risky part is not the sweep, it is the naming/API decisions in §4.4.

---

## 6. Sequence

1. **PR `docs/styleguide-adoption`** — `doc/styleguide.md` with the A/B/C tables
   above, pointers from `AGENTS.md` (§ "Structure & quality conventions") and
   `CONTRIBUTING.md` (§ "Coding standards"). Decision table signed off before
   any code PR.
2. **PR `chore/style-gates`**: `[lints]` in `Cargo.toml`,
   `rustfmt.toml` keys, `clippy.toml`, `scripts/check-style.sh`, `make style`,
   CI step, and the `AGENTS.md` unsafe-claim correction. Expected: red until 3–5.
3. **PR `refactor/lint-green`** (parity-neutral): the §5.2 sweep, `lib.rs`
   constants move. Run `cargo test --release` parity before/after — must be
   byte-identical.
4. **PR `feat/api-naming`** (the only user-visible change): `#[must_use]`,
   `#[non_exhaustive]` on `ModelError`, `Clone`/`Debug` on `RnnModel`,
   constructor renaming (deprecation shim), CHANGELOG entry.
5. **PR `test/assert-context`**: assertion context strings in `tests/` and
   `src/*/tests.rs`; tests must keep skipping gracefully when `models/` or
   `test_data/` artifacts are absent (our rule, the guide is silent on it).
6. **PR template + review checklist**: "bucket C exemptions must be cited in the
   CL description when a rule is broken" — that's what makes the guide enforceable
   without bikeshedding.

---

## 7. Guardrails

- **Parity gate is senior to the style guide.** Any style change that alters
  numerics is rejected; `tests/parity.rs` + `--release` run must stay green.
- Style changes must land as **separate commits from behaviour changes**, so an
  LSC-style rename can be reverted without touching the DSP.
- Prefer tool-enforced rules over prose rules. If a rule has no lint, either add
  one (4.3) or move it to bucket C — a rule nobody can check will not survive
  review, and the guide's own "rules must pull their weight" argument supports
  pruning.
- Do not adopt `[chrome]`/`[Fuchsia]` build rules (flat layout, `chromium::import!`,
  `fuchsia_sync::Mutex`, `rust_gtest_interop`) — cite them as out of scope in
  `doc/styleguide.md`.

## 8. API-compatibility assessment of the proposed changes

Public surface today (everything else is `pub` in private modules or
`pub(crate)`, so not API): `DenoiseState` + `RnnModel` + `ModelError`, the
`pub const` sizes, `pub mod capi` (feature-gated), `pub mod legacy` +
`DenoiseStateV1`/`RnnModelV1` (feature-gated).

| Change | Compat | Note |
|---|---|---|
| `rustfmt.toml`, `[lints]`, `clippy.toml`, `SAFETY:` comments, assert contexts, `unwrap`→`expect` | **compatible** | lints do not propagate to dependents; `expect` only changes the panic message |
| `src/fft/plan.rs` → `kiss_fft.rs` | **compatible** | `KissFft` lives in the private `fft` module → not reachable from outside |
| constants moved from `lib.rs` to a leaf module | **compatible only with the crate-root re-export** | `pub use params::{FRAME_SIZE, …}` must stay, or `rnnoise::FRAME_SIZE` breaks (`tests/api.rs` uses it) |
| `impl Debug`/`Clone` for `RnnModel` | **compatible (additive)** | needs `Debug` derived on internal `Weights`/`LinearLayer` first |
| `#[must_use]` on public methods | **source-compatible, build-noise** | a dependent running `deny(warnings)` gets new warnings; scope it to `process_frame` + `quantized`, keep `must_use_candidate` as an internal warn lint instead of annotating constructors |
| `#[non_exhaustive]` on `pub enum ModelError` | **breaking** | downstream exhaustive `match` and downstream construction both stop compiling; only justified by the guide's rule, so bundle it with the rename below |
| `with_model()` → `new_with_model()` | **breaking** unless a `#[deprecated]` alias is kept for one release |
| `From<&[u8]> for RnnModel` | **cannot be done** | the conversion is fallible → `From` is impossible; `from_bytes` stays and the guide's pairing rule is satisfied by the existing inherent constructor |
| `RNNModel` (capi) newtype tuple struct | **compatible** | newtypes are exempt from the `non_exhaustive` rule; the C ABI (`rnnoise_create`, `rnnoise_process_frame`, …) is untouched |
| `ModelError` → `Copy` (guide's error-type rule) | **impossible, documented exception** | `MissingArray(String)` / `BadSize(String)` payloads; making it `Copy` would require `&str` payloads, which is a further breaking change |

Recommendation: land everything except the two breaks as *compat* commits, and
collect `non_exhaustive` + the constructor rename into one pre-1.0 release with
CHANGELOG entries. If the repo is not yet at 0.2, take the break now — it is the
cheapest it will ever be, and it is what buys non-breaking variant additions later.

Verification, not opinion: add `tests/api_surface.rs` (or a CI step) that diffs
against a committed baseline generated with `cargo public-api`; the gate fails on
any change to the public surface. That makes "is it still compatible?" a build
result rather than a review argument.

## 9. Definition of done

`make check` (fmt + clippy + test) plus `make style` passes with the §4.1 lint
set, `scripts/check-style.sh` reports zero violations, `doc/styleguide.md` lists
every adopted rule with its enforcement mechanism and every exemption with a
rationale, and parity output is byte-identical to the pre-change run.
