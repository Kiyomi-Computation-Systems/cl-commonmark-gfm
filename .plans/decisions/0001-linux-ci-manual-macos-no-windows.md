# ADR-0001: Linux in CI, macOS verified by hand, no Windows

- **Status:** Accepted
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
  release: build the shim, run the full test suite for every supported Lisp,
  record the results in `.plans/progress.md`.

## Consequences

- A macOS regression can land on `main` and stay there until the next manual
  run. Releases are the gate, not merges.
- macOS loader risks (install names, `DYLD_*`, extension-library discovery)
  get no automatic coverage. Keep every loader branch inside `native` so the
  manual run exercises all of them.
- The arm64 Linux and arm64 macOS cells are covered only as far as CI or the
  laptop reach them. Guix's `ccl` is x86_64-only (ADR-0004), so CCL on arm64
  is verified on macOS.
