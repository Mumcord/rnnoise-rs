# Rust style guide for `rnnoise-rs`

Repo standard, adapted from the [Google Rust Style Guide][g]
(<https://google.github.io/styleguide/rustguide.html>). The upstream guide is a
Google-internal document: most of it restates the public [Rust style guide][r]
and the [Rust API Guidelines][a], and the rest is driven by Google-specific
build systems (`[chrome]`/`[Fuchsia]` rules) and large-scale changes. This file
says which rules apply here, which are tool-enforced, and which are waived — so
that a rule can be cited in review without re-arguing it.

[g]: https://google.github.io/styleguide/rustguide.html
[r]: https://style.hexo.rs/html/
[a]: https://rust-lang.github.io/api-guidelines/

Every rule below is marked:

- **A** — already satisfied, recorded so review stops re-litigating it.
- **B** — adopted as a gate (a `cargo clippy`/`rustc` lint level or a `rustfmt` setting).
- **C** — waived for this repo, with the reason.

Scope: **binding** for the library (`src/`), **advisory** for `tests/`,
`benches/`, `examples/` and `src/bin/` — the guide makes this distinction itself
(library code vs. application code).

---

## B — Adopted and mechanically enforced

### Tooling

| Rule | Mechanism |
|---|---|
| Formatting is tool-enforced, not argued | `rustfmt` with `max_width = 100` and `hex_literal_case = Lower` (both available on the pinned stable toolchain) |
| No `#[rustfmt::skip]` except manual alignment or generated code | review |
| All clippy warnings are errors | `cargo clippy --all-targets --all-features -- -D warnings` |
| Public items are documented | `[lints.rust] missing_docs = "deny"` |
| No unstable features | `[lints.rust] unstable_features = "deny"` (the pinned toolchain stays on `stable`) |
| `#![forbid(unsafe_code)]` is real, not aspirational | `[lints.rust] unsafe_code = "deny"`, with `#[allow(unsafe_code)]` only on the declared unsafe islands (§unsafe) |

### `use` statements

- One module per `use` block (no `::` inside `{..}`): review rule, because
  `imports_granularity = Module` is nightly-only and the toolchain stays on stable.
- No glob imports (`clippy::wildcard_imports` denied), **except**: `use super::*`
  in inline test modules, `pub use submodule::*` in non-leaf modules, and the
  `core::arch` intrinsic globs in the SIMD islands.
- Traits are imported inside the function body unless used throughout the file.
- Top-level functions from other modules are called module-qualified
  (`mem::transmute(y)`, not `transmute(y)`); types and traits are imported and
  used unqualified.
- No preludes.

### Naming

- Follow the standard-library method conventions: `as_`/`to_`/`into_` with the
  right `self` convention (`clippy::wrong_self_convention` denies).
- Constructors: `new()`, `new_with_foo()`; `Result`-returning constructors are
  `try_new()`.
- Accessors: `foo()`, `foo_mut()`, `take_foo()`, `set_foo()`, `replace_foo()`,
  `with_foo()` (closure accessor). `with_foo` is reserved for the closure form —
  constructors are never named `with_foo`.
- Lifetimes are descriptively named, except `'_` and up to two local
  single-character lifetimes.
- Generic parameters are short but indicative, ideally taken from the main trait
  bound.
- No abbreviations that someone outside the project would not recognise
  (`clippy::module_name_repetitions` is off because module names mirror upstream
  C files — see C2).

### Documentation

- `///` for items, `//!` at the top of a file, Markdown, capitalisation and
  punctuation.
- Document every panic a function can cause.
- Doc comments must say something the code does not; `clippy::_doc_markdown_...`
  noise aside, a comment that only restates the signature is a review comment.
- **C**: citing the upstream C function (`/// `frame_synthesis`: …`) counts as
  insight here, because the crate is a faithful port.
- Enum variants may be undocumented when the name is self-explanatory.

### Types and traits

- Newtypes over type aliases; named fields over tuples (newtype tuple structs and
  clearly-local tuples excepted).
- Implement the standard trait instead of a lookalike method
  (`clippy::should_implement_trait`).
- `#[derive()]` whenever the impl is expressible as a derive
  (`clippy::derivable_impls`).
- Error types: `Display` + `Error`, `Copy` when the payload allows it.
- `Clone` unless the type models an external resource; `Default` when the type
  has a natural default state; `Hash` + `Eq` when it could be a map key.
- `Option`-structs (bags of options) implement `Default`.
- Public enums with fields are `#[non_exhaustive]`
  (`clippy::exhaustive_enums`); public structs with public fields likewise
  (`clippy::exhaustive_structs`).
- `#[must_use]` on pure functions and on functions whose result is the point
  (`clippy::must_use_candidate` denies). `process_frame` is deliberately *not*
  `#[must_use]`: it is not pure (it writes the output buffer) and the VAD
  probability is informational, so denying it would force `let _ = ...` in every
  caller.
- `const fn` only when the function is expected to stay `const`.
- Prefer generics (`impl Trait`) over `dyn Trait` — except where a dependency
  forces the vtable (C6).
- Operator overloading only for mathematical/logical meaning, not as sugar.
- Macros last: functions, then `macro_rules!`, then codegen, then proc macros.

### Errors and panics

- `Option` for obvious failures, `Result` for recoverable failures that need
  context, `panic!` only for violated invariants (`clippy::panic` denies).
- Prefer pattern matching over check-then-unwrap when the input proves the case;
  otherwise `expect` with a context string, never `unwrap` anywhere
  (`clippy::unwrap_used` denies). The guide's "tests may panic" exception is
  implemented as `expect("context")` in test code, which doubles as the assertion
  context string the guide asks for.
- `clippy::disallowed_methods` denies `std::panic::catch_unwind` and
  `std::thread::spawn` — a real-time audio path must not spawn threads or unwind
  through a C callback.
- Never look inside a poisoned `Mutex`.

---

## Unsafe code (B, with the repo's island rule)

The guide's policy: unsafe only when no safe equivalent exists, encapsulated and
isolated, with a `SAFETY:` comment per block and a justification answering "why
not safe code?" and, if the answer is performance, "where is the benchmark?".

Here unsafe is unavoidable for exactly two reasons, both performance-driven:
`core::arch` intrinsics (`#[target_feature]` functions are unsafe by language
rule) and the C ABI (`Box::into_raw`/`Box::from_raw` across an FFI boundary).
`BENCHMARKS.md` carries the measurements.

Enforcement: `unsafe_code = "deny"` at the crate root, with the islands declared
in `lib.rs`/`mod.rs` and no unsafe anywhere else:

| Island | Why it is unsafe |
|---|---|
| `src/simd/**` | `core::arch` intrinsic calls are unsafe functions |
| `src/fft/x86_64.rs` | same, plus AoS load/store through vector registers |
| `src/capi.rs` | caller-supplied pointers crossing the FFI boundary |
| `src/simd/tests.rs`, `src/fft/tests.rs` | tests call the tiers directly to compare them with the portable reference |

A `SAFETY:` justification per block, or per file (the guide allows either), is a
review rule: no lint can express it. The island membership itself is a lint.

---

## C — Waived, with the reason

| # | Guide rule | Why it does not apply here |
|---|---|---|
| C1 | Library APIs should take `impl IntoIterator` and return iterators instead of `Vec` | The parity contract is the exact expression and accumulation order of the C reference. Kernels take `&mut [f32]`/`&[f32]` slices with fixed-size buffers; a generic iterator would change the loop structure and therefore the bits. `tests/parity.rs` is the arbiter. |
| C2 | Leaf modules and files are named after their primary user-defined item | `celt_lpc.rs`, `nnet.rs`, `pitch.rs`, `common.rs`, `weights.rs`, `spectrum.rs` mirror upstream C files and are the traceability anchor for parity. New modules follow the rule; the existing names are grandfathered. `fft/plan.rs` → `fft/kiss_fft.rs` was renamed to comply. |
| C3 | Flat file layout for one crate (`[chrome]`) | Chrome-scoped, and the guide excepts Cargo-built code. The conventional Cargo layout (with `src/simd/`, `src/fft/`) is the repo standard. |
| C4 | Small crates, one abstraction per crate | `rnnoise-rs` is a single published crate; the guide's own "foundational library" exception applies. Modularity is expressed through leaf modules. |
| C5 | Avoid `Rc`/`Arc` | `Arc<RnnModel>` is the intended ownership model: one immutable, parsed weight set shared by many `DenoiseState`s. That is the guide's own documented exception; `clippy::disallowed_types` lists `Rc` only. |
| C6 | Prefer generics over `dyn Trait` | The `legacy-model` path is bound to `rustfft`'s `dyn RealToComplex<f32>`/`ComplexToReal<f32>`. |
| C7 | Prefer enum parameters over `bool` | Binding for public API (currently no public `bool` parameters). Internal C-shaped helpers are exempt. |
| C8 | Per-codebase test frameworks (`rust_gtest_interop`, `#[fuchsia::test]`) | Open-source crate: `#[test]` + `tests/`, and tests that need `models/` or `test_data/` must skip gracefully when the artifacts are missing. Only the assertion-context-string rule is adopted. |
| C9 | `clippy::pedantic` | Measured: ~350 hits, dominated by `cast_precision_loss` and `cast_sign_loss` — the casts *are* the DSP arithmetic. `numeric_literal_separators` would also reformat the deliberately nearest-`f32` constants that parity depends on. Not enabled; specific pedantic lints that map to guide rules are enabled individually. |
| C10 | `use chromium::import!()`, `fuchsia_sync::Mutex` | Google-internal infrastructure. |

Adopted despite the `[chrome]` tag, because they fit a real-time audio crate:

- no `async`/`.await` anywhere,
- no new threads spawned by the library (`clippy::disallowed_methods` denies
  `std::thread::spawn`),
- no `panic::catch_unwind`,
- nothing runs before `main()` — lazy statics initialise on first use, not at load time.

---

## Module layout (A, our own rule is stricter than the guide)

`lib.rs` and every `mod.rs` contain only module declarations, re-exports, doc
comments and attributes — no logic, no types, no constants. This is the repo rule;
the guide allows "a small amount of core ties-things-together code", which we do
not take, and no lint can express it — review. `#[cfg(test)] mod tests` inside a leaf module
is explicitly allowed by the guide.

## What is enforced by a lint, and what is not

Everything below is a lint level, so `make check` is the whole gate:

| Rule | Lint |
|---|---|
| Unsafe confined to the declared islands | `unsafe_code = "deny"` + island `#[allow]` |
| Public items documented | `missing_docs = "deny"` |
| No feature gates / unstable features | `unstable_features = "deny"` |
| No `unwrap` in the crate | `clippy::unwrap_used = "deny"` |
| No `catch_unwind`, no thread spawn | `clippy::disallowed_methods` in `clippy.toml` |
| Glob imports only in the exemptions | `clippy::wildcard_imports` + island `#[allow]` |
| `#[must_use]` where the result is the point | `clippy::must_use_candidate` |
| `#[non_exhaustive]` on public enums/structs | `clippy::exhaustive_enums`, `clippy::exhaustive_structs` |
| Standard trait instead of a lookalike method | `clippy::should_implement_trait` |
| Derivable impls are derived | `clippy::derivable_impls` |
| `as_`/`to_`/`into_` and `self` conventions | `clippy::wrong_self_convention` |
| `len()` paired with `is_empty()` | `clippy::len_without_is_empty` |
| Flexible reference types | `clippy::borrowed_box`, `clippy::ptr_arg` |
| `new()` paired with `Default` | `clippy::new_without_default` |
| Formatting | `rustfmt` (`max_width = 100`, `hex_literal_case = Lower`) |

These are **review rules** — no lint can express them, so they are checked by a
human and nothing else:

- the `SAFETY:` justification per unsafe block or file,
- module-root purity (`lib.rs`/`mod.rs` declare and re-export only),
- one module per `use` block (`imports_granularity` is nightly-only),
- `#[rustfmt::skip]` only for manual alignment or generated code,
- no async in the DSP path, nothing that runs before `main()`, never looking
  inside a poisoned mutex,
- the naming rules that clippy cannot see (lifetimes, generics, `try_new()`).

If a rule is broken without an exemption, the PR says so. A rule nobody can check
is a rule that will not survive review, which is the guide's own argument for
keeping rules that "pull their weight".

## Review checklist

1. `make check` green (fmt + clippy + test).
2. `tests/parity.rs` byte-identical before and after — a style change that moves
   a bit is not a style change.
3. Style commits and behaviour commits do not mix.
4. If a rule here is broken, the PR description cites the exemption (C1…C10) or
   the reviewer's discretion.
5. Public-API changes have a `CHANGELOG.md` entry, and `tests/api_surface.rs`
   still compiles unchanged.
