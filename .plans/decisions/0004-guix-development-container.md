# ADR-0004: A pinned, toolchain-only Guix container for builds and tests

- **Status:** Accepted; amended 2026-09-27 (CL_COMMONMARK_GFM_LIBS);
  amended 2026-10-04 (M4b: GUIX_ENV_MANIFEST and a second container)
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
  `bash`). `GUIX_ENV_MANIFEST` can name another manifest (below).
- **Toolchain only.** Nothing from `HOME` enters the container: no git
  config, SSH or GPG agent, token, or Claude state. Agents and people edit,
  commit and push on the host. Builds and tests go through the container.
- **`scripts/guix-env-enter`** runs first inside the container. It:
  - points `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and
    `OCICL_PREFIX` at `.guix-env/`, which is gitignored and outlives the
    container (the container's own `HOME` does not);
  - puts `.guix-env/bin` (ocicl) on `PATH`;
  - puts `$GUIX_ENVIRONMENT/lib` on `LD_LIBRARY_PATH`;
  - exports `CL_COMMONMARK_GFM_LIBS` as the profile's two versioned library
    paths, colon-separated, core first —
    `.../libcmark-gfm.so.<ver>:.../libcmark-gfm-extensions.so.<ver>` — which
    is how the library finds cmark-gfm in the container (ADR-0009, spec
    §3.2).
- **`LD_LIBRARY_PATH`, not `--emulate-fhs`.** Guix's SBCL uses Guix's
  glibc, whose `dlopen` searches no FHS directory, so `--emulate-fhs` did not
  let ocicl find `libcrypto`. `LD_LIBRARY_PATH` did, and it stays set for
  that reason alone: spec §3.2 dropped bare-name library lookup, so this
  variable no longer makes any cmark-gfm lookup testable. cmark-gfm
  discovery in the container goes through `CL_COMMONMARK_GFM_LIBS` instead.
- **`make check-guix`** runs the launcher's dry-run tests on the host
  (`tests/guix-env-launcher.sh`), then `scripts/guix-env-selftest` inside.
  The self-test asserts:
  1. an isolated `HOME`;
  2. pinned tools, however a login shell finds them;
  3. the pinned cmark-gfm libraries from the store;
  4. state directories under `.guix-env/`;
  5. the pinned ocicl on `PATH`;
  6. bare-name `dlopen` of `libcrypto.so` — what ocicl's TLS stack loads,
     and what `LD_LIBRARY_PATH` guards in the container (spec §3.2), not
     cmark-gfm;
  7. `cmark-override`: `CL_COMMONMARK_GFM_LIBS` holds two absolute paths
     whose basenames are exactly `libcmark-gfm.so.<pin>` then
     `libcmark-gfm-extensions.so.<pin>`, in that order — both exist, and
     both resolve under `/gnu/store`;
  8. `check-help`, `check-vocabulary`, `check-pins` and `check-notice` pass.

  Each assertion has been seen to fail under a targeted mutation.
- **`tests/guix-env-launcher.sh` T7** runs on the host and asserts
  `scripts/guix-env-enter` resolves to exactly one match when the profile
  holds more than one versioned candidate for a library.
- **A second container, whose ECL has no dynamic FFI** (M4 spec §6.4), for
  `dynamic-ffi-unavailable` and linked programs (ADR-0021):
  - **`GUIX_ENV_MANIFEST`** names another manifest: a file name at the
    repository root, as `manifest.scm` is. Unset or empty, it is
    `manifest.scm`. A value holding `/`, or naming no file, is refused.
    The variable is preserved into the container.
  - **`manifest-ecl-nodffi.scm`** is `manifest.scm`'s packages, loaded from
    that file, with ECL alone built `--with-dffi=no` (M4 finding 8).
  - **Its own fasl cache.** Under any manifest but `manifest.scm`,
    `scripts/guix-env-enter` sets `XDG_CACHE_HOME` to
    `.guix-env/cache-<that name without .scm>`, so two ECLs built
    differently never share fasls (M4 finding 9).
  - **`make check-ecl-nodffi`** runs on the host, as `make check-guix`
    does, and runs `make check-ecl-nodffi-inside` in that container. Run
    on a Guix host outside any Guix environment, `make
    check-ecl-nodffi-inside` points at `make check-ecl-nodffi` instead.
  - **`tests/guix-env-launcher.sh`,** from T8, covers the variable, a
    refused manifest and the cache.
- No CI job runs `check-guix` or `check-ecl-nodffi` (M4 spec D5).

## Consequences

- **x86_64-linux only.** Guix builds `sbcl`, `ecl`, `ccl` and `cmark-gfm`
  for x86_64 (and i686). arm64 and macOS development do not use this
  container.
- Each `scripts/guix-env` call pays several seconds of `time-machine`
  startup. Batch commands: `scripts/guix-env sh -c 'make a && make b'`.
- The first `make ocicl` takes minutes. Later runs reuse `.guix-env/`.
- Guix builds the second container's ECL once, in about 5 minutes (M4
  finding 8).
- The container isolates the toolchain. It is not a sandbox: the repository
  is shared read-write, and the host later runs what the container writes
  there (the Makefile, git hooks).
