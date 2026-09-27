# ADR-0013: Linux CI in a Debian trixie container

- **Status:** Accepted
- **Date:** 2026-09-27
- **Scope:** CI workflow, CI toolchain, native memory checks
- **Spec:** [M0 close design](../2026-09-27-m0-close-design.md) §5
- **Related:** ADR-0001 (Linux-only CI), ADR-0002 (the pin), ADR-0004
  (the Guix container stays local), ADR-0009 (discovery), ADR-0011
  (the oracle and `check-pins`)

## Context

CI must run SBCL, CCL and ECL against the pinned cmark-gfm, on Linux only
(ADR-0001). Facts checked on 2026-09-27:

- **Debian trixie ships exactly the pin:** cmark-gfm 0.29.0.gfm.13-4, with
  SBCL 2.5.2 and ECL 24.5.10.
- **CCL 1.13 has no arm64 build** (ADR-0001).
- **The repository is private.** CI minutes are billed, and the free arm64
  Linux runners are not available to it.

## Decision

### Shape

- **One file, one job:** `.github/workflows/ci.yml`, on `ubuntu-latest`
  (amd64) in `container: debian:trixie`.
- **Triggers:** `pull_request`, and `push` to `main`.
- **Limits:** `permissions: contents: read` on the workflow;
  `timeout-minutes: 20`; `concurrency` cancels superseded runs on
  `pull_request` only, not on `push` to `main`.
- **The three Lisps run in sequence in one job**, since private-repo
  minutes are billed per job. Each runs even if an earlier one fails, and
  the job fails if any did. Once the Lisp steps land (M1), each step needs
  `if: ${{ !cancelled() }}` (or one aggregating `make` target) to run
  regardless of an earlier step's outcome — a job's later steps do not run
  by default once one fails.
- **Container gotchas.** Install `git` and `ca-certificates` before
  `actions/checkout`: without `git`, a checkout with `submodules: true`
  fails, because it cannot fall back to the REST API for submodules. Add
  `safe.directory` for the workspace and for the submodule, because
  `actions/checkout`'s own `safe.directory` setting lives in a temporary
  global git config, and root in the container does not own the checked-out
  files.

### Toolchain

| Tool | Source | Pin |
|------|--------|-----|
| SBCL 2.5.2, ECL 24.5.10 | Debian apt | the trixie release |
| cmark-gfm | apt: `libcmark-gfm0.29.0.gfm.13`, `libcmark-gfm-extensions0.29.0.gfm.13`, `cmark-gfm` (CLI) | exact version; **no `-dev` packages**, so discovery sees what a user sees |
| CCL 1.13 | `ccl-1.13-linuxx86.tar.gz` from the GitHub release | SHA-256 recorded in the repo |
| ocicl 2.9.0 | `ocicl_2.9.0-1_amd64.deb` from the GitHub release | SHA-256 recorded in the repo |
| Lisp dependencies | `ocicl install` from `ocicl.csv` | lockfile; `./ocicl/` cached on its hash |
| Corpus | `actions/checkout` with submodules | ADR-0002 commit |

### Steps

Each step comes into use as its milestone arrives.

| Step | From |
|------|------|
| `make info`: Lisp versions, architecture, cmark-gfm version | now |
| `make check-help`; `sh tests/guix-env-launcher.sh` (dry run, needs no Guix) | now |
| `make check-vocabulary` against Debian's CLI | now |
| `make check-pins`, `make check-notice` | now |
| `make check-purity`: the pure suites on each Lisp with `CL_COMMONMARK_GFM_LIBS=/nonexistent:/nonexistent` must pass | M1 |
| The native suites on each Lisp, **with no override set**, so discovery searches `/usr/lib/x86_64-linux-gnu` | M2 |
| The corpus oracle (ADR-0011) | M2 (partial) / M3 (full) |

### Left out on purpose

- **macOS, arm64 and Windows runners** (ADR-0001). The free arm64 runners
  are not available to a private repository anyway.
- **`make check-guix`**, which stays local (ADR-0004).
- **Valgrind and sanitizer gates.** We compile no C (ADR-0008). None of
  the three Lisp runtimes suits Valgrind: their collectors use signals and
  memory protection. Native memory safety is checked instead by:
  - the live-handle counters (ADR-0008);
  - repeated parse/render cycles under GC pressure;
  - the render stress tests behind ABI belief 1 (ADR-0008).

  This is revisited in M2 if the counters prove too weak.

## Consequences

- One billed job per run covers all three Lisps.
- CI's cmark-gfm is a distribution package, loaded the way a user's would
  be. That makes CI a real test of discovery (ADR-0009).
- CCL is covered on Linux amd64 only.
- A failure in one Lisp does not hide the results of the others.
- A native memory bug the counters and stress cycles miss can reach
  `main`. No tool in CI inspects native memory directly.
