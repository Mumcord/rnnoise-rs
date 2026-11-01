# Pull request

**Branch:** `feat/…`, `fix/…`, `docs/…`, `refactor/…`, `test/…`, `chore/…`
**Commit:** Conventional Commits (`<type>(<scope>): <description>`)

## What changed and why

Links to issues where relevant.

## Gate

- [ ] `make check` (fmt + clippy + style + test) is green
- [ ] `cargo test --release` — the parity harness is unchanged, byte for byte
- [ ] style commits and behaviour commits are separate commits
- [ ] public API changes have a `CHANGELOG.md` entry, and `tests/api_surface.rs`
      still compiles unchanged

## Rules

The ruleset is [doc/styleguide.md](../doc/styleguide.md). If a rule is broken, cite
the exemption by number (C1 parity/exactness, C2 upstream file names, C9 pedantic
casts, …) rather than arguing it again.
