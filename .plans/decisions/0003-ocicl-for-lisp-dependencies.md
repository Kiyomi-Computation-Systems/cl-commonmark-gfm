# ADR-0003: ocicl manages Lisp dependencies; ASDF finds them by environment

- **Status:** Accepted
- **Date:** 2026-09-27
- **Scope:** Lisp dependency acquisition, distribution, test loading

## Context

`AGENTS.md` requires ocicl for package management and distribution. The
library needs CFFI, and the tests need a test framework. It must load the same
way on SBCL, CCL and ECL.

ocicl installs systems into `./ocicl/` and records them in `ocicl.csv`. Its
suggested setup loads `ocicl-runtime.lisp` from each Lisp's rc file. That
runtime also fetches missing systems on demand.

ocicl is not packaged in Guix.

## Decision

- **`ocicl.csv` is committed; `ocicl/` is not.** `ocicl install` recreates
  `ocicl/` from the lockfile.
- **Tests find systems through `CL_SOURCE_REGISTRY`**, e.g.
  `CL_SOURCE_REGISTRY="$PWD//:$PWD/ocicl//"`, not through
  `ocicl-runtime.lisp` or an rc file. Plain ASDF works the same on all three
  Lisps. A missing system fails loudly instead of being downloaded mid-test.
  Configuration comes from the environment (12-factor).
- **ocicl itself is pinned** to tag `v2.9.0`, commit
  `f5faca8070c5ef04c6eac9b324c060519c5379d0`. `make ocicl` builds it from
  source with the container's SBCL into `.guix-env/bin/`, and refuses the tag
  if it resolves to any other commit.
- **Outside Guix, contributors use their own installed ocicl.** The
  lockfile, not the ocicl binary's version, decides what gets installed.
  Nothing in the build except `make ocicl` refers to `.guix-env/`. A
  contributor's own `~/.sbclrc` ocicl-runtime hook is not loaded, because
  test runs pass `--no-userinit` (or the equivalent flag on each Lisp) and
  use `CL_SOURCE_REGISTRY`.
- **Distribution** of `cl-commonmark-gfm` itself goes through ocicl. That work
  is part of M5.

## Consequences

- Verified 2026-09-27: `ocicl install alexandria` in the container, then
  `asdf:load-system` via `CL_SOURCE_REGISTRY` on SBCL 2.6.4, ECL 24.5.10 and
  CCL 1.13.
- ocicl's TLS loads `libcrypto` through CFFI by bare name, so the container
  sets `LD_LIBRARY_PATH` (ADR-0004).
- Without `LD_LIBRARY_PATH`, `ocicl` drops into SBCL's debugger and waits on
  stdin. Scripts that call it must redirect stdin from `/dev/null`.
