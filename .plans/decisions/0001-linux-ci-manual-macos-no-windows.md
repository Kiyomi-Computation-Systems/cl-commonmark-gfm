# ADR-0001: Linux in CI, macOS verified by hand, no Windows

- **Status:** Accepted; amended 2026-09-27 (CCL is amd64-only)
- **Date:** 2026-09-27
- **Scope:** support matrix, CI, release gating

## Context

The first plan draft required macOS for SBCL, CCL and ECL and listed Windows
as "best effort until CI exists". GitHub's macOS runners cost too much for
this project. The maintainer has a Mac laptop.

## Decision

- **Supported:** Linux and macOS, on amd64 and arm64.
- **Dropped:** Windows. No Windows code paths, loader branches or docs.
- **CI runs on Linux only.** Never add a macOS runner.
- **macOS is verified by hand** on the maintainer's laptop before each
  release: load cmark-gfm via the override or directory search (ADR-0009),
  run the full test suite for every supported Lisp, record the results in
  `.plans/progress.md`.

## Consequences

- A macOS regression can land on `main` and stay there until the next manual
  run. Releases are the gate, not merges.
- macOS loader risks (install names, `DYLD_*`, extension-library discovery)
  get no automatic coverage. Keep every loader branch inside `native` so the
  manual run exercises all of them.
- **arm64 Linux currently has no verification path at all.** CI is
  amd64-only (ADR-0013), and the maintainer's laptop is macOS, not Linux.
  SBCL and ECL on arm64 are verified only on the Mac; arm64 Linux is
  untested by either CI or the manual run. **CCL is amd64-only**: CCL 1.13
  has no arm64 build on any OS (its release assets are `darwinx86`,
  `linuxx86`, `freebsdx86`, `solarisx86`, `windowsx86` and 32-bit
  `linuxarm` only). CCL therefore runs on Linux amd64 (CI) and, verified by
  hand, on macOS amd64 (Intel, or under Rosetta on Apple Silicon with an
  x86_64 cmark-gfm) — never on arm64.
