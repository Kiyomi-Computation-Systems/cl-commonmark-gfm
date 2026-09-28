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
- The pure systems depend on nothing outside the project (no alexandria, no
  UTF-8 library).
- The HTML tree is LHTML-shaped (ADR-0010) and oracle-tested against cmark's
  HTML (ADR-0011). It carries cmark's newlines, and footnotes follow
  definition order (ADR-0014).
- The AST vocabulary is the plan's table (ADR-0005). Changing it needs an ADR.
- Tests use Parachute, run with the quiet reporter and exit non-zero on
  failure (ADR-0007).
- CI is one amd64 job in a `debian:trixie` container (ADR-0013).
- TDD. A test is done when it has been seen to fail.

## Milestones

| Milestone | Status |
|-----------|--------|
| M0 design freeze | closed 2026-09-27; GitHub CI proof deferred to October |
| M1 pure core | built and reviewed 2026-09-28; the local `debian:trixie` CI proof runs after the commit |
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

### M1 checklist

Spec: [M1 pure core design](2026-09-27-m1-pure-core-design.md) ·
Plan: [implementation](2026-09-27-m1-pure-core-implementation.md)

- [x] Skeleton, dependencies and runner: the four systems, `ocicl.csv`,
  `tests/run.lisp`, `make deps`, `make check-purity` (Task 1)
- [x] AST: schema, `make-node`, `copy-node`, queries, `node=`, transforms
  (Task 2)
- [x] URL helpers: `href-encode`, `dangerous-url-p` (Task 3)
- [x] Serializer: `html-tree->string` (Task 4)
- [x] Oracle fixtures: the manifest, the pinned CLI's HTML,
  `make check-fixtures`, `make fixtures-html` (Task 5)
- [x] Converter and footnotes: `ast->html-tree` (Task 6)
- [x] Documents: ADR-0014, the plan, this file (Task 7)
- [x] CI workflow: `make deps` and `make -k test` (Task 8)
- [x] Review, fixes and close-out (Task 9)
- [ ] Local `debian:trixie` CI proof against the commit, green and seen to
  fail (Task 9)

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

### 2026-09-28 — M1 pure core (branch `m1-pure-core`)

- **Built** (spec 2026-09-27, ADR-0014):
  - the conditions, AST, URL-helper, serializer and converter code, with the
    footnote pre-pass;
  - 28 oracle fixtures;
  - `make deps`, `check-purity`, `check-fixtures`, `fixtures-html` and
    `test`;
  - the CI steps `make deps` and `make -k test`.

  Nine tasks, run by subagents: Sonnet for the mechanical ones, Opus for the
  converter, the documents and the review.
- **Tests**, in the Guix container:
  - SBCL 2.6.4, CCL 1.13 and ECL 24.5.10 each run 226 tests with
    683 assertions;
  - all 28 oracle cases match the pinned CLI byte for byte;
  - `check-fixtures`, `check-help` and `check-guix` pass.

  Every check was seen to fail under a targeted mutation.
- **The final review ran the converter over the whole corpus, ahead of M2.**
  It built ASTs from cmark's own parse (`-t xml`, with footnote labels read
  from the source).
  - Inputs: all 744 corpus examples plus 123 edge inputs, each under the
    default options, `--nobreaks`, `--hardbreaks` and `--unsafe`. That's
    3,380 comparisons.
  - All were byte-identical except 12 (3 inputs × 4 option sets), which hit
    the two known footnote divergences (spec §5.4).
  - It also found 3 must-fix problems, all fixed:
    - mixed-case keywords (`:|href|`) slipped past the serializer's name
      rules;
    - raw comment text let markup escape from `textarea`, `title`, `script`
      and `style`;
    - a circular datum hung or killed the condition report.

    Its 8 should-fixes and 14 nits were fixed too.
- **A code review (`/code-review high`) then found 9 more.** Seven are
  fixed, each with a test seen to fail:
  - `copy-node` copied a circular children list before rejecting it;
  - condition slots had no defaults, so a partial condition broke its own
    report;
  - a self-referential tree overflowed the serializer's stack;
  - `make fixtures-html` could leave an empty fixture behind;
  - `map-ast` was quadratic in depth;
  - a nested duplicate definition was chosen differently from cmark;
  - the three footnote walkers now build paths with one shared helper.

  The other two, a non-copying child accessor and the duplicated
  `proper-list-p`, go to M2.
- **Found:**
  - ASDF won't load `cl-commonmark-gfm/ast` without a primary
    `cl-commonmark-gfm` system, so the `.asd` has an empty one.
  - Loading a file that declaims an optimization policy changes the image's
    policy on CCL and ECL; SBCL rebinds it around `load`. AGENTS.md's
    "Optimization Declarations" section is gone, and library source declares
    no policy.
  - CL case pairs are one-to-one, so `char-equal` folds no non-ASCII letter
    into ASCII on any of the three Lisps. `string-equal` therefore matches
    cmark's ASCII-only scheme check exactly.
  - cmark's XML omits `align` on body cells, but its HTML applies it per
    column. M2's copier must take alignment from the table's columns.
  - `****s****` parses as a `strong` inside a `strong`; only the renderer
    collapses them.
  - Parachute files every result under its test and under the report. The
    runner removes the duplicates, prints its counts, and fails if no tests
    ran.
  - Debian's `ecl` package depends on `gcc`, so CI needs no change for ECL
    to compile.
- **Handed to M2** (spec §9):
  - Recursive traversals overflow the stack at 10,000 nested block quotes on
    SBCL and CCL (50,000 on ECL). cmark handles 50,000.
  - Settle the two footnote divergences against the oracle.
  - The copier gives each reference its definition's label as written.
  - Show that each hand-built fixture AST equals the copier's.
  - Add a non-copying child accessor for internal walks, and share the
    duplicated `proper-list-p` (from the code review).
- **CI evidence:** pending. The local `debian:trixie` run needs a commit;
  the GitHub run waits for October.

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
