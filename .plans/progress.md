# Progress

The spine of the project: where each milestone stands, the constraints every
task brief inherits, and the close-out of each piece of work. Read it before
starting a slice; append a close-out when one ends.

Plan: [cl-commonmark-gfm.org](cl-commonmark-gfm.org) ·
Decisions: [decisions/](decisions/)

## Global constraints

Every task brief is bound by these, on top of `AGENTS.md`.

- Common Lisp: SBCL, CCL and ECL from one source tree. No `sb-alien`, CCL or
  ECL FFI in library sources; CFFI only.
- Linux and macOS, amd64 and arm64. No Windows. CI is Linux only; macOS is
  checked by hand before a release (ADR-0001).
- CCL is amd64-only: Linux amd64 in CI, macOS amd64 (Intel or Rosetta) by
  hand (ADR-0001).
- cmark-gfm 0.29.0.gfm.13, nothing else (ADR-0002).
- Lisp dependencies via ocicl; tests find them via `CL_SOURCE_REGISTRY`
  (ADR-0003).
- On a Guix host, every build and test goes through `scripts/guix-env`
  (ADR-0004).
- The project compiles no C. It binds libcmark-gfm directly through CFFI
  (ADR-0008) and loads the pinned pair by absolute path (ADR-0009).
- The AST and HTML-tree systems load and pass tests with no C library present.
- The HTML tree is LHTML-shaped (ADR-0010) and oracle-tested against cmark's
  HTML (ADR-0011).
- The AST vocabulary is the plan's table (ADR-0005). Changing it needs an ADR.
- Tests use Parachute, run with the quiet reporter and exit non-zero on
  failure (ADR-0007).
- CI is one amd64 job in a `debian:trixie` container (ADR-0013).
- TDD. A test is done when it has been seen to fail.

## Milestones

| Milestone | Status |
|-----------|--------|
| M0 design freeze | closed 2026-09-27; GitHub CI proof deferred to October |
| M1 pure core | not started |
| M2 SBCL vertical slice | not started |
| M3 complete copier | not started — evaluate property-based testing (ADR-0007) |
| M4 CCL and ECL | not started |
| M5 release candidate | not started |

### M0 checklist

- [x] Support matrix: Linux CI, manual macOS, no Windows (ADR-0001)
- [x] Pin cmark-gfm 0.29.0.gfm.13 (ADR-0002)
- [x] ocicl for dependencies (ADR-0003)
- [x] Guix development container, `make check-guix` (ADR-0004)
- [x] AST vocabulary verified against the pin (ADR-0005)
- [x] NOTICE with cmark-gfm's COPYING
- [x] `:gfm` enables footnotes (ADR-0006)
- [x] Test framework: Parachute (ADR-0007)
- [x] ~~Write the shim header~~: replaced by direct binding (ADR-0008) and
  pinned-pair discovery (ADR-0009)
- [x] Settle the tree shapes, now the HTML tree: LHTML shape, footnotes, raw
  HTML `:omit`/`:text` (ADR-0010–0012)
- [x] Linux CI (ADR-0013); the workflow lands with the m0-close branch

### October: CI follow-up

GitHub Actions minutes ran out before the first run (2026-09-27; the job was
refused for billing, never started).
- [ ] Confirm the first `main` run of `.github/workflows/ci.yml` is green,
  and that its `make info` log shows the versions recorded below.
- [ ] See it fail once: push a throwaway branch with one byte of
  `tests/fixtures/vocabulary.xml` flipped. The job must go red at
  `make check-vocabulary`. Delete the branch.
- [ ] Record both here and tick them.

## Manual macOS runs

Record each run: date, macOS and chip, Lisp versions, cmark-gfm version,
result.

_None yet._

## Close-outs

### 2026-09-27 — M0 close (PR #2)

- Direct binding, no shim (ADR-0008); pinned-pair discovery (ADR-0009);
  LHTML-shaped HTML tree with a public `html-tree->string` (ADR-0010, after a
  survey found no CL SXML consumer); cmark's HTML as the oracle, with a
  `vendor/cmark-gfm` submodule (ADR-0011); tree policies (ADR-0012); Linux CI
  (ADR-0013). ADRs 0001, 0002, 0004, 0005 and 0006 and the plan corrected.
- Built by subagents (Sonnet for mechanical tasks, Opus for the ADRs, the
  plan and review). The Opus review found 11 should-fix items; all were
  fixed before merge. Every new check was seen to fail under a mutation.
- `make check-guix`: 28 launcher tests and every container assertion pass.
- **CI evidence (interim, local).** GitHub refused to start the job for
  billing. Instead, the workflow's steps ran against commit `4b7759b` in
  `debian:trixie` under Docker:
  - the clone included submodules, and `ci/install-toolchain.sh` verified
    both checksums;
  - `make info` reported x86_64, SBCL 2.5.2.debian, ECL 24.5.10, CCL 1.13,
    cmark-gfm 0.29.0.gfm.13 and ocicl 2.9.0;
  - `check-help`, the launcher tests (28/28), `check-vocabulary`,
    `check-pins` and `check-notice` passed;
  - with one byte of the vocabulary fixture flipped, `check-vocabulary`
    failed.

  This covers the steps, not GitHub's own job wiring; see "October: CI
  follow-up".
- Found:
  - CCL has no arm64 build.
  - arm64 Linux has no verification path.
  - `make info` read cmark-gfm's version through `pkg-config`, which CI
    doesn't install; it now asks the CLI.
  - Git in a root container refuses a repository it doesn't own.

### 2026-09-27 — M0 foundation

- AGENTS.md corrected: Common Lisp, not Chez Scheme; ledger moved to
  `.plans/progress.md`.
- Guix container: `scripts/guix-env`, `scripts/guix-env-enter`,
  `scripts/guix-env-selftest`, `tests/guix-env-launcher.sh`, `manifest.scm`,
  `channels.scm`. `make check-guix` passes. Every launcher test and
  in-container assertion was seen to fail under a targeted mutation.
- Found: without `LD_LIBRARY_PATH`, `ocicl` sits in SBCL's debugger waiting
  on stdin. Its callers now redirect stdin from `/dev/null`.
- Found: `--emulate-fhs` does not help Guix's own SBCL find libraries by bare
  name; `LD_LIBRARY_PATH` does.
- Vocabulary findings (ADR-0005): footnotes have no type string; no autolink
  node kind; `table_header` is explicit; source positions can be absent or
  inverted.
