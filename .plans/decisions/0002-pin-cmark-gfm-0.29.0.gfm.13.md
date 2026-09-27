# ADR-0002: Pin cmark-gfm 0.29.0.gfm.13

- **Status:** Accepted
- **Date:** 2026-09-27
- **Scope:** native dependency, shim ABI, version probes

## Context

The plan requires one pinned cmark-gfm release, with the shim, core and
extension libraries built as a set. On 2026-09-27:

- `0.29.0.gfm.13` is the newest upstream tag. It is a lightweight tag on
  commit `587a12bb54d95ac37241377e6ddc93ea0e45439b`.
- The pinned Guix channel (`channels.scm`) packages exactly this version.

## Decision

- Pin **cmark-gfm 0.29.0.gfm.13**, commit `587a12bb54d9`.
- The Makefile's `CMARK_GFM_VERSION` names it. `make check-guix` fails if the
  container's `pkg-config --modversion libcmark-gfm` differs.
- The shim's supported runtime range is exactly this version until a later
  ADR widens it.
- Every node kind and attribute in the plan was verified against this
  release (ADR-0005).

## Consequences

- Bumping the pin means changing `CMARK_GFM_VERSION` and `channels.scm`, then
  rerunning `make check-guix` (which includes `check-vocabulary`) and the
  native test suite.
- A system cmark-gfm of another version is unsupported, even if it loads.
