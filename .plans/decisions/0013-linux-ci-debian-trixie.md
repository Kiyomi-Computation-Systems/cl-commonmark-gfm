# ADR-0013: Linux CI in a Debian trixie container

- **Status:** Accepted; amended 2026-09-27 by the
  [M1 spec](../2026-09-27-m1-pure-core-design.md): the M1 step (D9), the
  cache wording and the Lisp steps' conditions; amended 2026-09-30 by
  ADR-0018 and the [M2 spec](../2026-09-30-m2-native-layer-design.md) §8.5:
  the native suite and the full oracle arrive in M2; amended 2026-10-01 by
  finding 20 and the same spec's §8.5: a startup watchdog for CCL; amended
  2026-10-01, after M2b's second review (the same spec's §8.5): the
  watchdog handles SIGINT and SIGTERM, polls once more before it kills,
  and checks its arguments; `make info` starts CCL through it; and `make
  test` runs `check-watchdog`
- **Date:** 2026-09-27
- **Scope:** CI workflow, CI toolchain, native memory checks, the CCL
  start watchdog
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
  the job fails if any did. A job skips its later steps once one fails, so
  the Lisp steps, `make deps` and `make test` (M1), run with
  `if: ${{ !cancelled() }}`; `make -k test` runs `check-fixtures` even
  when `check-purity` fails.
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
| Lisp dependencies | `ocicl install` from `ocicl.csv` | lockfile; `./ocicl/` not cached yet; `ci.yml` says so |
| Corpus | `actions/checkout` with submodules | ADR-0002 commit |

### Steps

Each step comes into use as its milestone arrives.

| Step | From |
|------|------|
| `make info`: Lisp versions, architecture, cmark-gfm version | now |
| `make check-help`; `sh tests/guix-env-launcher.sh` (dry run, needs no Guix) | now |
| `make check-vocabulary` against Debian's CLI | now |
| `make check-pins`, `make check-notice` | now |
| `make deps`, then `make -k test`, both `if: ${{ !cancelled() }}`: `check-purity` (the pure suite on each Lisp; fails if a `CFFI` package is loaded) and `check-fixtures` | M1 |
| `make -k test` adds `check-native`, the native suite, **with no override set**, so discovery searches `/usr/lib/x86_64-linux-gnu` | M2 (SBCL) / M4 (CCL, ECL) |
| The corpus oracles, over the whole corpus (ADR-0011, ADR-0018), in the native suite | M2 |

### CCL start watchdog

CCL 1.13's release binary sometimes hangs inside its own startup on this
host's kernel (Linux 7.1.1), before any Lisp code runs: one thread,
almost all its time in the kernel, 2.5 MB resident, deaf to SIGTERM
(finding 20, M2 design §8.5). Bare starts under Docker hung 6 times in
30; the Guix container's CCL never hung. It broke a local CI proof: `make
test` hung in `check-purity`'s CCL run for 35 minutes.

- Each test runner (`tests/run.lisp`, `tests/run-native.lisp`) prints a
  fixed marker line as its first act, then flushes it.
- `scripts/lisp-start-watchdog` runs a command in the background, polls
  for that marker, and on silence past a window kills the run with
  SIGKILL (SIGTERM doesn't work on a hung CCL) and starts it again, up to
  a set number of tries, reporting each attempt on standard error.
- `make check-purity` and `make check-native` use it for CCL only, through
  `run-suite`; SBCL and ECL run directly, as before. Once the marker
  appears, or the run exits on its own, the watchdog never retries again:
  that run's own exit status is final, so a test that fails, or hangs,
  after starting still fails.
- `tests/lisp-start-watchdog.sh` (`make check-watchdog`) tests the script
  against a fake command: no CCL, no Lisp. `make test` runs it first.

M2b's second review added four rules (M2 design §8.5):
- **Signals.** Stopping the watchdog, with Ctrl-C or SIGTERM, must not
  leave a hung CCL behind, deaf to SIGTERM, or lose what the run wrote. So
  on SIGINT or SIGTERM the watchdog kills its run with SIGKILL, prints
  the run's output, and exits 130 or 143.
- **A last poll.** The marker is looked for once more before a kill, so a
  run that started in the window's last second isn't killed as if it hung.
- **Checked arguments.** A window or a number of tries that isn't a
  positive integer fails at once, instead of misbehaving.
- **`make info`** asks CCL its version, which starts CCL, so it runs
  through the watchdog too. CI runs it before any other `make` step, and a
  hang there would stall the job until its 20-minute timeout.

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
