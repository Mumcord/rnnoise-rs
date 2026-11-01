# Contributing to rnnoise-rs

Thank you for your interest in contributing! This document describes the
workflow used across all `lovelace-labs/*-rs` repos.

## Getting started

1. **Fork** the repository on GitHub.
2. **Clone** your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/rnnoise-rs.git
   cd rnnoise-rs
   ```
3. **Add the upstream remote**:
   ```bash
   git remote add upstream https://github.com/lovelace-labs/rnnoise-rs.git
   ```

## Development setup

### Prerequisites

- Rust 1.85+ (edition 2021), installed via [rustup](https://rustup.rs/).
  The pinned toolchain plus `rustfmt` and `clippy` are declared in
  [`rust-toolchain.toml`](rust-toolchain.toml) and installed automatically.

### Building

```bash
make build       # cargo build
make test        # cargo test
make check       # fmt-check + clippy + test (the CI gate)
```

Run `make help` for the full list of targets.

## Branch naming

Use descriptive branch names with a prefix:

- `feat/` — new features
- `fix/` — bug fixes
- `docs/` — documentation changes
- `refactor/` — code refactoring
- `test/` — test additions or changes
- `chore/` — maintenance tasks

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`.

## Pull request process

1. Sync with upstream:
   ```bash
   git fetch upstream
   git rebase upstream/dev
   ```
2. Run `make check`.
3. Open a pull request with a clear title (Conventional Commits format) and
   a description of what changed and why. Link related issues.
4. Address review feedback by pushing additional commits.
5. Squash and merge after approval.

## Coding standards

The full ruleset is [doc/styleguide.md](doc/styleguide.md), adapted from the
[Google Rust style guide](https://google.github.io/styleguide/rustguide.html).
The short version:

- Run `cargo fmt` (enforced by CI).
- All clippy warnings are errors (`-D warnings`); the lint set lives in
  `Cargo.toml` under `[lints]`.
- Document public items with `///` comments (`missing_docs` is denied).
- Prefer `Result` over panics for recoverable errors; `Option` for obvious
  failures; `panic!` only for violated invariants.
- No `unwrap` in `src/` — pattern-match when the input proves the case, otherwise
  `expect("context")`. Tests use `expect` with an assertion context string.
- Unsafe only in the declared islands (`src/capi.rs`, `src/simd/`,
  `src/fft/x86_64.rs`, `src/fft/dispatch.rs`), each with a `SAFETY:` justification.
- No async, no threads, no `catch_unwind`, no unstable features, no `rustfmt::skip`
  except manual alignment.
- `make style` runs the checks that no lint can express and is part of `make check`.

## Module organization

- `lib.rs` and `mod.rs` only declare submodules and re-export the public
  surface — no logic or types in module roots.
- Prefer small, single-responsibility submodules over large catch-all files.

## Questions?

- [Issues](https://github.com/lovelace-labs/rnnoise-rs/issues) — bugs and feature
  requests.
- [Discussions](https://github.com/lovelace-labs/rnnoise-rs/discussions) — design
  questions.
- [SECURITY.md](SECURITY.md) — vulnerability reporting.
