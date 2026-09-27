# ADR-0002: Pin cmark-gfm 0.29.0.gfm.13

- **Status:** Accepted
- **Date:** 2026-09-27
- **Scope:** native dependency, discovery, version probes

## Context

The plan requires one pinned cmark-gfm release, with the core and extension
libraries used as a matched pair (ADR-0009). On 2026-09-27:

- `0.29.0.gfm.13` is the newest upstream tag. It is a lightweight tag on
  commit `587a12bb54d95ac37241377e6ddc93ea0e45439b`.
- The pinned Guix channel (`channels.scm`) packages exactly this version.

## Decision

- Pin **cmark-gfm 0.29.0.gfm.13**, commit `587a12bb54d95ac37241377e6ddc93ea0e45439b`.
- The Makefile's `CMARK_GFM_VERSION` names it. `make check-guix` fails if the
  container's `pkg-config --modversion libcmark-gfm` differs.
- The library's supported runtime version is exactly this version, checked
  at load (ADR-0009), until a later ADR widens it.
- Every node kind and attribute in the plan was verified against this
  release (ADR-0005).

## Consequences

A pin bump touches every one of these, in order, then runs `make
check-guix` (which includes `check-vocabulary`, `check-pins` and
`check-notice`) and CI:

1. `CMARK_GFM_VERSION` and `CMARK_GFM_COMMIT` in the `Makefile`.
2. The `vendor/cmark-gfm` submodule's checked-out commit.
3. The commit hash in this ADR's Decision, above.
4. `channels.scm`.
5. NOTICE's `cmark-gfm <version> -- COPYING` heading and the `COPYING`
   text it reproduces.
6. The versioned apt package names in `ci/install-toolchain.sh`.
7. The pinned filenames in ADR-0009.

A system cmark-gfm of another version is unsupported, even if it loads.
