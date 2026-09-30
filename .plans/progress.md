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
- No walk over a tree recurses on its depth: walks loop over explicit stacks
  (ADR-0015).
- Tests use Parachute, run with the quiet reporter and exit non-zero on
  failure (ADR-0007).
- CI is one amd64 job in a `debian:trixie` container (ADR-0013).
- TDD. A test is done when it has been seen to fail.

## Milestones

| Milestone | Status |
|-----------|--------|
| M0 design freeze | closed 2026-09-27; GitHub CI proof deferred to October |
| M1 pure core | closed 2026-09-28; GitHub CI proof deferred to October |
| M2 stack-safe walks and the native layer | in progress: M2a |
| M3 unknown extensions and version probes | not started — evaluate property-based testing (ADR-0007) |
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
- [x] Local `debian:trixie` CI proof against the commit, green and seen to
  fail (Task 9)

### M2 checklist

Spec: [M2 design](2026-09-30-m2-native-layer-design.md) ·
Plan: [M2a implementation](2026-09-30-m2a-stack-safe-walks-implementation.md)

**M2a, stack-safe walks** (branch `m2a-stack-safe-walks`):

- [x] `/util` and one `proper-list-p` (Task 1)
- [x] `walk-ast` and the AST walks (Task 2)
- [x] The serializer (Task 3)
- [x] The converter and footnotes (Task 4)
- [x] Documents: ADR-0015, the plan, this file (Task 5)
- [x] Review, fixes, a second review and close-out (Task 6)
- [x] Local `debian:trixie` CI proof against the commit, green and seen to
  fail (Task 6)

**M2b, the native layer** (branch `m2b-native-layer`; its plan follows
M2a), one line per spec section:

- [ ] Bindings: `/ffi`'s declarations and one native walker (§5.1)
- [ ] Startup: once per process, under a lock (§5.2)
- [ ] Saved images: the save hooks (§5.3)
- [ ] Lifetimes and counters: `with-native-document`, the alive flag (§5.4)
- [ ] Limits: the three variables, the table-cell and output bounds (§5.5)
- [ ] The copier's walk: `copy-native-tree` (§6.1)
- [ ] Classification: `classify-node` (§6.2)
- [ ] Attributes, footnote labels included (§6.3)
- [ ] Source positions (§6.4)
- [ ] Text: UTF-8 in and out (§6.5)
- [ ] Entry points: `parse` and the three `markdown->…` functions (§7.1)
- [ ] Options and their defaults (§7.2)
- [ ] Option bits (§7.3)
- [ ] Conditions (§7.4)
- [ ] Threads (§7.5)
- [ ] Pure suite additions (§8.1)
- [ ] The corpus reader (§8.2)
- [ ] The four oracles (§8.3)
- [ ] Other native tests: deep documents, crash guards, lifetimes (§8.4)
- [ ] Runner, `make check-native` and CI (§8.5)
- [ ] Seen to fail (§8.6)
- [ ] Documents: ADRs 0016 to 0018, and the corrections to ADR-0005, 0011,
  0013 and 0014 and to the plan (§9, §10)

### October: CI follow-up

GitHub Actions minutes ran out before the first run (2026-09-27; the job was
refused for billing, never started).
- [ ] Confirm the first `main` run of `.github/workflows/ci.yml` is green,
  that its `make info` log shows the versions recorded below, and that its
  `make -k test` step shows each Lisp's test counts (M1).
- [ ] See it fail once: push a throwaway branch with one byte of
  `tests/fixtures/vocabulary.xml` flipped. The job must go red at
  `make check-vocabulary`. Delete the branch.
- [ ] Record both here and tick them.

## Manual macOS runs

Record each run: date, macOS and chip, Lisp versions, cmark-gfm version,
result.

_None yet._

## Close-outs

### 2026-09-30 — M2a stack-safe walks (branch `m2a-stack-safe-walks`)

- **Built** (M2 spec §3 and §4, ADR-0015):
  - `cl-commonmark-gfm/util`, holding the one `proper-list-p`, a loop;
  - `walk-ast`, now exported, with `fold-ast`, `map-ast` and
    `transform-ast` built on it; `node=` loops over a stack of node pairs;
  - `html-tree->string` loops over a stack of open elements, with an `eq`
    set to find an element that contains itself;
  - `ast->html-tree` is a port of cmark's event loop, with footnote places
    keyed by owner and ordinal, not by path;
  - `tests/run.lisp` exits 1 when a stack overflow escapes Parachute. ECL
    exited 0 there, so `check-purity` reported a pass.

  Six tasks, run by subagents one at a time, with the documents alongside
  the first: Sonnet for util, the walks, the serializer and the fixes; Opus
  for the converter, the documents and both reviews.
- **Tests**, in the Guix container:
  - SBCL 2.6.4, CCL 1.13 and ECL 24.5.10 each run 280 tests with
    793 assertions (M1: 226 and 683);
  - M1's tests are unchanged apart from comments: "design §N" became
    "M1 design §N", since the M2 spec reuses M1's numbers;
  - seven deep shapes at 100,000 levels, spec §4.7's six plus nested
    tables, go through every AST walk, the converter and the serializer. So
    do 300,000-wide trees;
  - the pure suite takes 4.8 s on SBCL, 19.5 s on CCL and 24.4 s on ECL;
  - all 28 oracle cases match; `check-help` and `check-guix` pass.

  Every new check was seen to fail. Each walk put back to recursion aborts
  the SBCL run with a stack exhaustion; the other mutations fail named
  tests.
- **Differential check.** Two throwaway harnesses ran seeded random input
  through M1's code and M2a's, on each Lisp:
  - 25,000 ASTs, converted under 13 option sets and put through every AST
    walk;
  - 70,000 HTML trees, malformed ones included.

  Every result was byte-identical, conditions and datums included.
- **Reviews.** An Opus review found 3 should-fixes, 8 nits and 3 M1 issues;
  a second review of the fixes found 3 more small items. All are fixed or
  recorded here. Two of the M1 issues were bugs of M2a's kind, where a
  circular or deep value hangs the process:
  - a reason string printed a caller's attribute key unbounded, so a
    circular key hung or exhausted the heap. It now prints cut short;
  - the serializer compared malformed attribute names with `equal`, which
    loops on circular names. It now compares them by identity, so two
    distinct but `equal` names that are neither strings nor keywords
    report "invalid attribute name", not "repeated attribute name".

  Also changed, by design (spec §4.2): `fold-ast` and `map-ast` given a
  non-node signal a `type-error` before calling FUNCTION. M1 called it once
  first.
- **Found:**
  - ECL's top level exits 0 after a stack overflow once stdin is at EOF.
  - Were `proper-list-p` to accept a circular list, M1's test
    `copy-node-rejects-a-circular-children-list` would hang the suite
    (`copy-list` loops) rather than fail.
  - SBCL can die outright on a stack overflow ("Control stack exhausted
    while pseudo-atomic"). The exit status is still non-zero.
  - ASDF compares file dates to the second, so a source restored within a
    second of its mutated fasl isn't recompiled. Mutation runs clear the
    fasl cache before the final check.
  - CCL's `equal` hash tables degrade on label strings: 100,000 footnote
    labels take 1.4 s and 400,000 take 14 s, where SBCL takes 0.07 s. For
    M4.
  - A DAG that shares nodes heavily has exponentially many places, and
    every walk visits each. M1 behaves the same, and a parsed tree shares
    nothing.
  - The random harnesses never put one backref paragraph at two places of
    a definition; an explicit test covers it.
  - **The first local CI run failed,** against `f78ef48`: Debian's SBCL ran
    out of heap. Parachute keeps every assertion's closure until the run
    ends, and the deep tests' closures captured their trees and strings,
    515 MB in all. Debian's SBCL has a 1 GB heap by default and Guix's
    3 GB, so the container passed. The deep tests now build their data in
    helpers or inside the asserted form, and 20 MB stays alive. The suite
    still peaks between 768 MB and 1 GB, so `check-purity` gives SBCL a
    2 GB heap everywhere (`c59e4de`).
- **CI evidence (interim, local),** as for M0 and M1: the workflow's steps
  ran against commit `c59e4de` in `debian:trixie` under Docker.
  - The clone included submodules, and both toolchain checksums matched.
  - `make info` reported x86_64, SBCL 2.5.2.debian, ECL 24.5.10, CCL 1.13,
    cmark-gfm 0.29.0.gfm.13 and ocicl 2.9.0.
  - `check-help`, the launcher tests (28/28), `check-vocabulary`,
    `check-pins`, `check-notice` and `make deps` passed.
  - `make -k test` ran 280 tests with 793 assertions on each Lisp and
    passed, and so did `check-fixtures`.
  - With one byte of `tests/fixtures/html/paragraphs.html` flipped,
    `make -k test` failed. `check-fixtures` named `paragraphs`, and each
    Lisp's suite reported `oracle case paragraphs`.

  The GitHub run waits for October.
- **Settled from M1's hand-offs:** stack depth, the non-copying child
  accessor (`walk-ast`) and the shared `proper-list-p`.

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
  - [x] Recursive traversals overflow the stack at 10,000 nested block
    quotes on SBCL and CCL (50,000 on ECL). cmark handles 50,000. Done in
    M2a (ADR-0015).
  - [ ] Settle the two footnote divergences against the oracle.
  - [ ] The copier gives each reference its definition's label as written.
  - [ ] Show that each hand-built fixture AST equals the copier's.
  - [x] Add a non-copying child accessor for internal walks, and share the
    duplicated `proper-list-p` (from the code review). Done in M2a:
    `walk-ast`, and `cl-commonmark-gfm/util`.
- **CI evidence (interim, local),** as for M0: the workflow's steps ran
  against commit `67ae47b` in `debian:trixie` under Docker.
  - The clone included submodules, and both toolchain checksums matched.
  - `make info` reported x86_64, SBCL 2.5.2.debian, ECL 24.5.10, CCL 1.13,
    cmark-gfm 0.29.0.gfm.13 and ocicl 2.9.0.
  - `check-help`, the launcher tests (28/28), `check-vocabulary`,
    `check-pins`, `check-notice` and `make deps` passed.
  - `make -k test` ran 226 tests with 683 assertions on each Lisp and
    passed, and so did `check-fixtures`.
  - With one byte of `tests/fixtures/html/paragraphs.html` flipped,
    `make -k test` failed. `check-fixtures` named `paragraphs`, and each
    Lisp's suite reported `oracle case paragraphs`.

  The GitHub run waits for October.

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
