# ADR-0004: A pinned, toolchain-only Guix container for builds and tests

- **Status:** Accepted
- **Date:** 2026-09-27
- **Scope:** development tooling. No library change
- **Prior art:** chez-cmark-gfm ADR-0018 and ADR-0019, whose final shape this
  follows

## Context

The maintainer develops on Guix. Builds and tests need three Lisps, a C
toolchain, cmark-gfm and ocicl-installed systems. None of these should land
on, or be affected by, the host.

## Decision

- **`scripts/guix-env`** runs `guix time-machine -C channels.scm -- shell -m
  manifest.scm --container --network`, then any given command (default:
  `bash`).
- **Toolchain only.** Nothing from `HOME` enters the container: no git
  config, SSH or GPG agent, token, or Claude state. Agents and people edit,
  commit and push on the host. Builds and tests go through the container.
- **`scripts/guix-env-enter`** runs first inside the container. It:
  - points `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and
    `OCICL_PREFIX` at `.guix-env/`, which is gitignored and outlives the
    container (the container's own `HOME` does not);
  - puts `.guix-env/bin` (ocicl) on `PATH`;
  - puts `$GUIX_ENVIRONMENT/lib` on `LD_LIBRARY_PATH`.
- **`LD_LIBRARY_PATH`, not `--emulate-fhs`.** Guix's SBCL uses Guix's
  glibc, whose `dlopen` searches no FHS directory, so `--emulate-fhs` did not
  let ocicl find `libcrypto`. `LD_LIBRARY_PATH` did. The same variable makes
  the plan's last library-resolution step (CFFI conventional names) testable.
- **`make check-guix`** runs the launcher's dry-run tests on the host
  (`tests/guix-env-launcher.sh`), then `scripts/guix-env-selftest` inside.
  The self-test asserts:
  1. an isolated `HOME`;
  2. pinned tools, however a login shell finds them;
  3. the pinned cmark-gfm libraries from the store;
  4. state directories under `.guix-env/`;
  5. the pinned ocicl on `PATH`;
  6. `dlopen` of cmark-gfm by bare name;
  7. `check-help` and `check-vocabulary` pass.

  Each assertion has been seen to fail under a targeted mutation.
- No CI job runs `check-guix`.

## Consequences

- **x86_64-linux only.** Guix builds `sbcl`, `ecl`, `ccl` and `cmark-gfm`
  for x86_64 (and i686). arm64 and macOS development do not use this
  container.
- Each `scripts/guix-env` call pays several seconds of `time-machine`
  startup. Batch commands: `scripts/guix-env sh -c 'make a && make b'`.
- The first `make ocicl` takes minutes. Later runs reuse `.guix-env/`.
- The container isolates the toolchain. It is not a sandbox: the repository
  is shared read-write, and the host later runs what the container writes
  there (the Makefile, git hooks).
