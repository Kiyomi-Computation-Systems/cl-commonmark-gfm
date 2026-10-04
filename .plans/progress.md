# Progress

The spine of the project: where each milestone stands, the constraints every
task brief inherits, and the close-out of each piece of work. Read it before
starting a slice; append a close-out when one ends.

Plan: [cl-commonmark-gfm.org](cl-commonmark-gfm.org) ·
Decisions: [decisions/](decisions/)

## Global constraints

Every task brief is bound by these, on top of `AGENTS.md`.

- Common Lisp: SBCL, CCL and ECL from one source tree. No `sb-alien`, CCL or
  ECL FFI in library sources; CFFI only. One exception: to keep a saved
  image from reopening cmark-gfm, `/native` may edit a Lisp's own records
  of the libraries it loaded. No foreign call goes around CFFI (M4 design
  §4).
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
- A CCL process keeps the first pair it loads, even one whose startup
  failed, and refuses any other (ADR-0009).
- The pure systems (util, conditions, AST, HTML tree and native-core) load
  and pass tests with no C library present.
- The pure systems depend on nothing outside the project (no alexandria, no
  UTF-8 library).
- The HTML tree is LHTML-shaped (ADR-0010) and oracle-tested against cmark's
  HTML (ADR-0011). It carries cmark's newlines, and footnotes follow
  definition order (ADR-0014).
- The AST vocabulary is the plan's table (ADR-0005). Changing it needs an ADR.
- No walk over a tree recurses on its depth: walks loop over explicit stacks
  (ADR-0015).
- No input reaches cmark past the three limits, `*max-input-octets*`,
  `*max-nodes*` and `*max-output-octets*`, or past the input guard. Each
  limit is checked before cmark does the work it guards (ADR-0016). With
  footnotes on, the guard rejects what triggers cmark's footnote-entity bug,
  before parsing (ADR-0019).
- Tests use Parachute, run with the quiet reporter and exit non-zero on
  failure (ADR-0007). The checks in `tests/static/` are the exception:
  plain programs without Parachute, since they load the library alone.
  `make` judges them by exit status and summary line (ADR-0021).
- CI runs the property tests from a fixed seed with fixed case counts:
  seed 1 and ADR-0020's counts, so every run tests the same cases.
  `make fuzz` explores with random seeds (ADR-0020).
- Every native suite ends with the open counters (parsers, roots and
  buffers) at zero (ADR-0008).
- Tests keep large values out of assertions. Parachute keeps every result
  until the run ends, with each assertion's closure and the values it
  compared, so large data is built in a helper or inside the asserted form.
- No test thread lets a condition escape: every thread a test starts goes
  through `make-test-thread`. On CCL, an escaped condition ends the whole
  run (M4 finding 1).
- CI is one amd64 job in a `debian:trixie` container (ADR-0013). Pull
  requests run the native suite on SBCL. On `main` and on dispatch, the
  native suite also runs on CCL and ECL, and then `make check-ecl-static`
  runs (ADR-0021).
- TDD. A test is done when it has been seen to fail.
- Mutation runs delete the project's fasls before every run, the restoring
  run included: its `src` and `tests` trees under the fasl caches, which in
  the Guix containers are `.guix-env/cache*/common-lisp/`. ASDF compares
  file dates to the second, so a source mutated and restored within one
  second keeps its mutated fasl. Deleting those trees is enough, since
  mutations never touch the dependencies.
- No fasls are shared between ECLs built differently, or with a linked
  build (M4 finding 9). The container whose ECL has no dynamic FFI has its
  own fasl cache, and a linked build compiles into `build/ecl-static/`,
  emptied first.
- A check that runs an ECL program, or a test without Parachute in an ECL
  process, requires exit status 0 and its summary line with 0 failed.
  ECL's debugger quits with status 0 at the end of stdin, so a condition
  that reaches it can look like a pass (M4 finding 26).
- Comments and docstrings follow AGENTS.md's Formatting rules: comments for
  developers, exported symbols' docstrings for users, no references to the
  plans and no history (M5 comment sweep).

## Milestones

| Milestone | Status |
|-----------|--------|
| M0 design freeze | closed 2026-09-27; GitHub CI proven 2026-10-02 |
| M1 pure core | closed 2026-09-28; GitHub CI proven 2026-10-02 |
| M2 stack-safe walks and the native layer | closed 2026-10-01: M2a merged 2026-09-30 (PR #4, `246eb51`), M2b merged 2026-10-02 (PR #5, `89fabeb`) |
| M3 unknown extensions and version probes | closed 2026-10-02, with its close-out (PR #8): property-based testing adopted (ADR-0020) |
| M4 CCL and ECL | closed 2026-10-04, with M4b's close-out: M4a merged 2026-10-03 (PR #9, `163077a`), M4b in PR #10 |
| M5 release candidate | in progress: the comment sweep (branch `m5-comment-sweep`) |

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
Plans: [M2a implementation](2026-09-30-m2a-stack-safe-walks-implementation.md),
[M2b implementation](2026-09-30-m2b-native-layer-implementation.md)

**M2a, stack-safe walks** (branch `m2a-stack-safe-walks`):

- [x] `/util` and one `proper-list-p` (Task 1)
- [x] `walk-ast` and the AST walks (Task 2)
- [x] The serializer (Task 3)
- [x] The converter and footnotes (Task 4)
- [x] Documents: ADR-0015, the plan, this file (Task 5)
- [x] Review, fixes, a second review and close-out (Task 6)
- [x] Local `debian:trixie` CI proof against the commit, green and seen to
  fail (Task 6)

**M2b, the native layer** (branch `m2b-native-layer`):

- [x] Dependencies, the encoder and the conditions (Task 1)
- [x] `/native-core`: constants, classification and discovery (Task 2)
- [x] `/native-core`: options, option bits and limits (Task 3)
- [x] `/ffi` and `/native`: startup, lifetimes, walking and rendering
  (Task 4)
- [x] Threads and saved images (Task 5)
- [x] The copier and `parse` (Task 6)
- [x] The renderers, the corpus and two oracles (Task 7)
- [x] The XML oracle (Task 8)
- [x] Output bounds and the crash guards (Task 9)
- [x] The input guard, with ADR-0019 (Task 9b)
- [x] Documents: ADRs 0016 to 0018, the amended ADRs, the plan, this file
  (Task 10)
- [x] Review, fixes, a second review and close-out (Task 11)
- [x] Local `debian:trixie` CI proof against the commit, green and seen to
  fail; covers the CCL start watchdog too, now that `run-suite` always
  runs CCL through it (ADR-0013) (Task 11)

### M3 checklist

Spec: [M3 design](2026-10-02-m3-extensions-versions-properties-design.md) ·
Plan: [implementation](2026-10-02-m3-extensions-versions-properties-implementation.md)

- [x] The version cross-check: `version-number`, `number-version` and the
  startup check of `cmark_version()` (Task 1)
- [x] Unknown extensions, on nodes built through cmark's public API
  (Task 2)
- [x] The spike's harness, our contender and the UTF-8 property (Task 3)
- [x] The bounds and clean-outcome properties (Task 4)
- [x] The oracle properties and the divergences (Task 5)
- [x] check-it, the second contender (Task 6)
- [x] The benchmark (Task 7)
- [x] Fixes for real bugs the spike finds, if any (Step 7b)
- [x] ADR-0020, confirmed by the user (Task 8)
- [x] Integration or removal, as ADR-0020 decides (Task 9)
- [x] Documents, part 1: the amended ADR-0008 and ADR-0009, the plan's M3,
  this file (Task 10)
- [x] Documents, part 2: decision 26 and, if adopted, the plan's Tests
  section and a global constraint (Task 10)
- [x] Review, fixes and a second review; the local `debian:trixie` CI run,
  green and seen to fail; close-out; a green GitHub run on the PR
  (Task 11)

### M4 checklist

Spec: [M4 design](2026-10-03-m4-ccl-ecl-design.md) ·
Plans: [M4a implementation](2026-10-03-m4a-ccl-ecl-dynamic-ffi-implementation.md),
[M4b implementation](2026-10-03-m4b-ecl-static-deployment-implementation.md)

**M4a, CCL and ECL with dynamic FFI** (branch `m4a-ccl-ecl-dynamic-ffi`):

- [x] Tests that run on every Lisp: test threads, lock waits and joins, the
  star path and the interrupt checks (Task 1)
- [x] Children on every Lisp, with a start retry for CCL, and the interrupt
  race on CCL; not on ECL, which doesn't defer interrupts in a region that
  allocates (M4 finding 13) (Task 2)
- [x] CCL: one pair per process (Task 3)
- [x] Saved images on CCL, with a save while a worker holds the state
  (Task 4)
- [x] Performance hand-offs: CCL's footnote labels and ECL's 75-second test
  (Task 5)
- [x] Makefile and CI: CCL's and ECL's native suites on `main` and on
  dispatch (Task 6)
- [x] Documents, part 1: the plan's M4, this file (Task 7)
- [x] Documents, part 2: ADRs 0008, 0009, 0013, 0017 and 0020 amended, the
  plan, decision 27 and the global constraints (Task 7)
- [x] Review, fixes and a second review; the local `debian:trixie` CI run
  of `main`'s steps, green and seen to fail; close-out; a green GitHub run
  on the PR, and CCL's and ECL's native suites green on GitHub, on the
  branch or in `main`'s first run (Task 8)

**M4b, ECL static deployment** (branch `m4b-ecl-static-deployment`):

- [x] The second container, whose ECL has no dynamic FFI:
  `GUIX_ENV_MANIFEST`, its own fasl cache and `make check-ecl-nodffi`
  (Task 1)
- [x] The recipe, the smoke program and `make check-ecl-static` (Task 2)
- [x] Linked mode in the native layer, and `dynamic-ffi-unavailable`'s datum
  and reason (Task 3)
- [x] CI: `make check-ecl-static` on `main` and on dispatch (Task 4)
- [x] Documents, part 1: the plan's M4, this file (Task 5)
- [x] Documents, part 2: ADR-0021, the amended ADRs 0004, 0009, 0013 and
  0017, the plan, decision 28 and the global constraints (Task 5)
- [x] Review, fixes and a second review; the local `debian:trixie` CI run
  of `main`'s steps, green and seen to fail; close-out, with the second
  container's result; a green GitHub run on the PR, and a green dispatched
  run of `main`'s steps, the static steps included (Task 6)

### M5 checklist

No spec yet. At the maintainer's request, the comment sweep comes first,
before the documentation.

**The comment sweep** (branch `m5-comment-sweep`):

- [x] A pilot on three files, approved by the maintainer: `src/conditions.lisp`,
  `src/ffi.lisp` and `src/native-core/linking.lisp`
- [x] The other 31 files, by five agents in parallel, one per area. A form
  check, seen to fail, shows that only comments and docstrings changed,
  and one error message the maintainer approved
- [x] Two reviews, fixes and a second review; the test suites; AGENTS.md's
  comment rules; close-out

### October: CI follow-up

GitHub Actions minutes ran out before the first run (2026-09-27; the job was
refused for billing, never started). They came back on 2026-10-01: PR #5's
run, the project's first to start, passed (M2b close-out). Done 2026-10-02.
- [x] Confirm the first `main` run of `.github/workflows/ci.yml` is green,
  that its `make info` log shows the versions recorded below, and that its
  `make -k test` step shows each Lisp's test counts (M1).
- [x] See it fail once: push a throwaway branch with one byte of
  `tests/fixtures/vocabulary.xml` flipped, and open a draft PR for it. CI
  runs only on pull requests and on pushes to `main`. The job must go red
  at `make check-vocabulary`. Close the PR and delete the branch.
- [x] Record both here and tick them.

The record:
- **The first `main` run** (run 36994077632, on M2b's merge `89fabeb`)
  passed in 3 min 24 s.
  - `make info` showed the versions M0 recorded: x86_64,
    SBCL 2.5.2.debian, ECL 24.5.10, CCL 1.13, cmark-gfm 0.29.0.gfm.13 and
    ocicl 2.9.0.
  - `make -k test` passed the watchdog's 37 checks, the fixtures, 528
    tests on each Lisp (1,569 assertions on SBCL and ECL, 1,568 on CCL)
    and 137 native tests.
- **The red run** (draft PR #6, run 36995312367) changed `Heading` to
  `Xeading` in `tests/fixtures/vocabulary.xml`.
  - The job went red at `make check-vocabulary`, whose diff showed the
    line.
  - `check-pins` and `check-notice` were skipped. `make deps` and
    `make test` ran anyway, by design (ADR-0013). The pure suite and the
    fixtures passed, since they don't read the file. The native suite's
    two vocabulary tests failed.
  - The PR is closed, and its branch deleted.

## Manual macOS runs

Record each run: date, macOS and chip, Lisp versions, cmark-gfm version,
result.

_None yet._

## Close-outs

### 2026-10-04 — M5 comment sweep (branch `m5-comment-sweep`)

- **Done:** every comment and docstring in `src/` and `cl-commonmark-gfm.asd`
  rewritten for the first release, in 34 files:
  - no references to the plans (ADRs, design documents, findings, decision
    labels, plan tasks, review labels) and no history. Where a reference
    stood in for a reason, the reason is written out;
  - the public package's docstrings are written for users, everything else
    for developers;
  - C identifiers spelled as cmark-gfm's source has them, and its paths
    given in full;
  - 213 of 559 docstrings changed (216 of 566 on CCL), and most comments;
  - one code change, approved by the maintainer: CHECK-INPUT's reason for
    UNSUPPORTED-INPUT no longer ends "(M2 design finding 16)".

  AGENTS.md's Formatting section now holds the rules, and a global
  constraint above points to them.
- **How:** the maintainer approved the rules, then a pilot on three files.
  Five Opus agents rewrote the other 31 files in parallel, one area each,
  and two Opus reviewers, one for the pure side and one for the native
  side, reviewed the result twice. Fixes went to the agent that wrote each
  file; I applied the second round's nits.
- **The form check** (throwaway, `.guix-env/tmp/m5-sweep/`) reads every
  top-level form of each file, on `main` and on the branch, on SBCL, CCL
  and ECL. It runs under six feature sets, so every one of the 31 reader
  conditionals is read, and it fails unless the forms match once
  docstrings are set aside.
  - It was seen to fail on 17 mutations made on copies: a symbol, a number,
    a string in code, code in a branch only one Lisp reads, a `#+nil` form,
    a deleted docstring, a deleted file and others. Each was flagged only by
    the Lisps that read it.
  - It passed comment and docstring edits, with the right counts.
- **Comments that were wrong about the code,** corrected, each one
  confirmed by a reviewer. Among them:
  - TRANSFORM-AST isn't built on WALK-AST;
  - `:unsafe-html nil` writes cmark's `<!-- raw HTML omitted -->`;
    `:unsafe-html t` under `:gfm` still has tagfilter escape some tags;
  - cmark's footnote code doesn't copy a label: `cmark_chunk_dup` points it
    into the entity's buffer;
  - CMARK_VERSION_STRING names nothing in the pin: the version comes from
    `cmark_version_string()` and `cmark_version()`;
  - `api.lisp` said every limit applies before any native call;
    `*max-output-octets*` applies after the parse;
  - the option-bit list left out SAFE; `%find-extension`'s allocation is
    CFFI's copy of its argument; NESTED-STRONG-P checks only the parent.
- **Tests,** in the Guix container, after the last edit: the pure suite's
  582 tests on each Lisp, and the native suite's 197, 207 and 188, as
  before; the watchdog's 37 checks and the preflight's 53. The CCL
  watchdog restarted nothing.
- **For later,** found during the sweep and left alone:
  1. TRANSFORM-AST doesn't CHECK-TYPE its node, unlike the other walks,
     and no test passes it a non-node.
  2. ADR-0015 and the M2 design's §4.2 say TRANSFORM-AST is built on
     WALK-AST; it isn't.
  3. ADR-0018's reason for decoded output being "never shorter" is stale:
     the bound tests compare against cmark's raw octets.
  4. When an override names a missing file, the report doesn't say which
     override; only the OVERRIDE slot does.
  5. UNWIND-PROTECT-DEFERRED's CCL branch wraps its cleanup forms in
     CCL:WITHOUT-INTERRUPTS, which changes nothing there.
  6. `tests/`, the Makefile and the scripts still cite the plans, review
     labels included.

### 2026-10-04 — M4b ECL static deployment (branch `m4b-ecl-static-deployment`)

- **Built** (M4 spec §6; ADR-0021; ADRs 0004, 0009, 0013 and 0017
  amended):
  - **linked ECL programs:** when ECL compiled cmark's calls with CFFI's
    `:c/c++` method, startup skips the dynamic-FFI check, discovery and
    loading, and its state's paths are `:linked`. `src/ffi.lisp` records
    the method as its calls compile (findings 25 and 31);
  - **`dynamic-ffi-unavailable`** only on an ECL without `:dffi` whose
    native layer isn't linked. Its datum is `:dffi`, and its reason says
    how to link cmark-gfm in instead;
  - **the recipe and the smoke program,** with `make check-ecl-static`:
    - the recipe (`tests/static/build.lisp`) uses ECL's own ASDF. It links
      ASDF into the program where ECL ships `libasdf.a`, and otherwise,
      as on Debian, has the program load it as it starts (finding 23);
    - the smoke program runs 65 checks: the method, the linked state, the
      28 oracle fixtures through both entry points, a restart, the open
      counters, and nothing loaded, after the first startup and at the
      end;
    - the archives come from `CMARK_GFM_ARCHIVE_DIR`, or from beside the
      pair discovery finds on Linux;
  - **a second Guix container,** whose ECL has no dynamic FFI
    (`GUIX_ENV_MANIFEST=manifest-ecl-nodffi.scm`, with its own fasl
    cache), and `make check-ecl-nodffi`: a guard, the condition test (5
    checks, among them the order of step 1 and discovery), then the smoke
    program on that ECL;
  - **CI:** on `main` and on dispatch, after CCL's and ECL's native
    suites, the `-dev` packages install and `make check-ecl-static` runs
    (ADR-0013).

  Six tasks, run by subagents one at a time, with the documents
  alongside. Sonnet took the second container and CI; Opus the recipe,
  linked mode, the documents and the reviews.
- **Tests,** in the Guix container, from fresh fasls:

  | Suite | SBCL | CCL | ECL |
  |---|---|---|---|
  | Pure | 582 tests, 1,703 assertions | 582, 1,702 | 582, 1,703 |
  | Native | 197 tests, 1,521 assertions | 207, 1,658 | 188, 1,449 |

  - The native counts are M4a's; the pure suite gains `linked-method-p`'s
    test.
  - The smoke program passes its 65 checks on the container's ECL, on
    its ECL without dynamic FFI, and on Debian trixie's ECL. The
    condition test passes its 5.
  - The launcher's tests pass 54 checks (M4a: 32), the preflight's 53
    (M4a: 26), and the watchdog's 37.
  - `make check-ecl-static` takes about 85 s, nearly all of it compiling;
    the program itself runs in under a second. `make check-ecl-nodffi`
    takes about 100 s.

  Every new check was seen to fail, under its task's mutations and each
  fix round's.
- **Decisions the user made during M4b:**
  - ASDF is linked into a program where ECL ships it, and loaded as the
    program starts otherwise;
  - the tasks ran by subagents, as in M4a;
  - after the first review: the method is recorded where the calls
    compile, `src/ffi.lisp`; the condition test's checks that couldn't
    fail gave way to an order check.
- **Reviews:**
  - **Round 1,** two Opus reviewers, split by area:
    - the library, the recipe and the check programs: no must-fix; three
      should-fixes, two of them the user's decisions above, and nine
      nits;
    - the containers, CI, the shell tests and the documents: no
      must-fix; six should-fixes, mostly untested shell branches, and
      twelve nits.
  - **Fix round F1:** four code follow-ups, one at a time, each to the
    agent that wrote the code, then the documents.
  - **Round 2:** no must-fix. Two should-fixes: a launcher test that broke
    when the repository's path holds a space, and a preflight helper that
    matched only newer GNU make's error line, not macOS's make 3.81. Eight
    nits, one a small regression from round 1's archive-path fix. All
    fixed.
  - **Round 3,** on round 2's fixes alone: clean in both areas. Two
    optional nits, a citation and the spec's status line, were fixed.
- **Found** (M4 findings 23 to 31):
  - **23:** Debian's ECL has ASDF 3.1.8.8, and no ASDF archive to link.
    CFFI's compiled code refers to ASDF's packages, which is finding 7's
    start failure;
  - **24:** replacing ECL's own FFI functions catches nothing: ECL calls
    them directly;
  - **25:** in a linked program, CFFI's method variable is ECL's default
    again at run time;
  - **26:** an ECL program or process that fails as it starts can exit 0,
    from its debugger at the end of stdin. So every new ECL check also
    requires its summary line;
  - **27:** `ext:quit` doesn't end a program from its prologue;
  - **28:** ECL links every compiled file with `c::*ld-libs*`, so the
    archives go in before anything compiles;
  - **29:** without step 1, an ECL without dynamic FFI fails only at
    loading, with advice that leads nowhere;
  - **30:** ECL reads a `?` or a `\` in a path as a wildcard, as it does a
    `*`;
  - **31:** a program behaves by the method of the file that compiled its
    calls.
- **For M5's documentation:**
  - the recipe for a linked ECL program; on Debian, such a program loads
    ECL's own ASDF as it starts;
  - on macOS, `CMARK_GFM_ARCHIVE_DIR` must name the archives'
    directory, and the static check hasn't run there;
  - M4a's items still stand.
- **CI evidence (local, before the commit):** `main`'s steps, the new
  static ones included, ran in `debian:trixie` under Docker against the
  working tree, three times: before the fix rounds, after the first, and
  on the final tree.
  - **`make info`** reported x86_64, SBCL 2.5.2.debian, ECL 24.5.10,
    CCL 1.13, cmark-gfm 0.29.0.gfm.13 and ocicl 2.9.0.
  - **Every step passed** each time. `make -k test`, CCL's and ECL's
    native suites and the static check took 674 s, 700 s and 658 s.
  - **Debian's ECL took the prologue path:** the program loaded ECL's
    ASDF 3.1.8.8 as it started, and passed its checks.
  - **With one fixture byte flipped,** every suite failed each time: the
    pure suite on all three Lisps, `check-fixtures`, the native suite on
    all three, and `check-ecl-static`, naming `paragraphs` in both entry
    points and in the restart's render.
  - **With the prologue removed,** the program stopped at start with
    finding 7's message, and `make check-ecl-static` failed on the missing
    summary line.
  - **The CCL watchdog** restarted one hung start, in the second run's
    flipped native pass. The first and third runs needed none.
- **`main`'s first run after M4a** (37166381582, on `163077a`) passed in
  15 min 33 s, CCL's and ECL's native suites included, with the counts
  above.
- **CI evidence (GitHub),** on PR #10's commit `d2b1243`:
  - **The PR's run** (37216097662) passed in 4 min 23 s. `make -k test`
    took 223 s; CCL's and ECL's suites and the static steps were skipped,
    as on every pull request.
  - **A dispatched run of `main`'s steps** (37216096957,
    `workflow_dispatch` on the branch) passed in 17 min 6 s: `make -k
    test` in 221 s, CCL's and ECL's native suites in 643 s, the `-dev`
    packages in 2 s, and `make check-ecl-static` in 109 s. The static
    check took the prologue path, with Debian's ASDF 3.1.8.8.
  - **Both matched the local runs:** `make info`'s versions; the
    launcher's 54 checks, the watchdog's 37 and the preflight's 53; the
    pure suite's 582 tests on each Lisp; the native suite's 197, 207 and
    188; and the static check's 65 checks, 0 failed. The CCL watchdog
    restarted nothing.
  - `main`'s full run now takes about 17 minutes: the static steps add
    about 2 to M4a's.

### 2026-10-03 — M4a CCL and ECL with dynamic FFI (branch `m4a-ccl-ecl-dynamic-ffi`)

- **Built** (M4 spec §5; ADRs 0008, 0009, 0013, 0017 and 0020 amended):
  - **native tests that run on every Lisp:** test threads hand back what
    they signal, and lock waits and joins poll a deadline (M4 finding 1);
  - **children on every Lisp,** with a start retry for a CCL child that
    hangs before it starts; the interrupt race on SBCL and CCL;
  - **CCL's one pair per process** (ADR-0009): the first pair a process
    loads is its pair, even when its startup fails; another is refused
    before any call into it;
  - **CCL forgets each library it closes that nothing holds open,** and the
    save hook forgets the recorded pair's re-learned records, so a saved
    image doesn't reopen cmark-gfm by bare name. A restored image records
    the pair CCL reopened, if it did. This edits CCL 1.13's own records,
    the one exception to "CFFI only" (ADR-0017);
  - **saved images on CCL:** the SBCL tests run there too, with new ones
    for a failed startup, a reloaded core, a pair other code holds open,
    and both outcomes of a save while a worker is busy;
  - **two speedups, in our own code:** footnote labels hashed by the
    converter itself (CCL hashes short strings into few values), and a
    node's type string read only when it has an extension (each foreign
    call is slow under ECL's dynamic FFI);
  - **CI:** CCL's and ECL's native suites run on pushes to `main` and on
    `workflow_dispatch`; the job's timeout is 30 minutes (ADR-0013).

  Eight tasks, run by subagents one at a time, with the documents
  alongside. Sonnet took the portable test helpers and the CI change; Opus
  the children, CCL's pair record and images, the performance work, the
  documents and the reviews.
- **Tests,** in the Guix container, from fresh fasls:

  | Suite | SBCL | CCL | ECL |
  |---|---|---|---|
  | Pure | 581 tests, 1,698 assertions | 581, 1,697 | 581, 1,698 |
  | Native | 197 tests, 1,521 assertions | 207, 1,658 | 188, 1,449 |

  M3's native suite ran 183 tests on SBCL alone. The watchdog's test
  passes 37 checks, and the preflight's 26. `make test` and `make
  check-native NATIVE_LISPS="ccl ecl"` take about 9 minutes together.

  Every new check was seen to fail, under its task's mutations and each
  fix round's.
- **Decisions the user made during M4a:** two slices under one design;
  CCL keeps one pair per process; CCL's and ECL's native suites run on
  `main` only; ECL's interrupt deferral is recorded as a limitation;
  CCL forgets the libraries it closes, with its internals; a restored CCL
  image keeps the pair CCL reopened. One refinement was mine, within the
  forgetting decision: only a record nothing holds open is forgotten.
- **Reviews:**
  - **Round 1,** two Opus reviewers, split by area:
    - the library and native tests: one must-fix, a CCL image test that
      failed 3 times in 20 under CPU contention; two should-fixes;
    - test validity, CI and the documents: one must-fix, the plan's
      classification paragraph; six should-fixes, among them wait tests
      that would hang rather than fail, and an ECL rule never checked.
  - **Fix round F1,** code and documents in parallel.
  - **Round 2:** no must-fix. One should-fix, finding 22, which the user
    chose to close in code (F2).
  - **Round 3:** no must-fix; five document items, fixed.
- **Found** (M4 findings 1 to 22):
  - **1:** on CCL, an error that escapes a thread ends the whole batch run;
    bordeaux-threads doesn't implement lock timeouts there;
  - **2, 3:** CCL never unloads a library it has called into, and CFFI
    looks names up globally on CCL, so a later pair can run an earlier
    pair's code;
  - **4, 12:** ECL passes nearly everything, but can't find a library whose
    path holds a `*`;
  - **5, 16 to 18:** ECL's native suite took 332 s, against SBCL's 43 s,
    much of it CFFI's lookup on every call; CCL's string hashing slowed
    the footnote tables;
  - **6 to 9:** ECL links cmark-gfm into a program (`:c/c++`); Debian
    ships the archives; Guix builds an ECL without dynamic FFI (for M4b);
  - **13:** ECL 24.5.10 runs interrupts inside `mp:without-interrupts`
    when the region allocates. On ECL, interrupting a thread during a call
    isn't safe. A report for ECL's maintainers is drafted at
    `.guix-env/tmp/m4-probe/ecl-deferral/ecl-issue.md`;
  - **14:** CCL never refuses a busy save: it unwinds other threads, and
    without the save hook's refusal it crashes;
  - **15, 22:** a saved CCL image reopens libraries by soname;
  - **19:** tests of label matching need fresh strings;
  - **20:** on SBCL and ECL, a reset unloads cmark-gfm from under other
    code that loaded the same files, since M2b; unsupported;
  - **21:** each Lisp needs its own way to end a child at once.
- **For M4b:** static deployment, as the spec's §6 designs it.
- **For M5's documentation:**
  - on ECL, interrupting or timing out a thread during a call isn't safe
    (finding 13);
  - on CCL, a process keeps the first pair it loads, even after a failed
    startup (§5.3);
  - loading cmark-gfm's own library files beside this library is
    unsupported (finding 20);
  - the manual macOS run is to cover CCL's image tests (finding 22).
- **CI evidence (local, before the commit):** the workflow's steps,
  `main`'s included, ran in `debian:trixie` under Docker against the
  working tree, twice: after the first fix round, and on the final tree.
  - **`make info`** reported x86_64, SBCL 2.5.2.debian, ECL 24.5.10,
    CCL 1.13, cmark-gfm 0.29.0.gfm.13 and ocicl 2.9.0.
  - **Every step passed** both times. `make -k test` and `main`'s CCL and
    ECL step took 628 s and 588 s.
  - **With one fixture byte flipped,** every suite failed both times: the
    pure suite on all three Lisps, `check-fixtures` (naming `paragraphs`),
    and the native suite on all three.
  - **The CCL watchdog** restarted one hung start in each pass of the
    first run, both in the pure suite. The second run needed none.
- **CI evidence (GitHub),** on PR #9's commit `7a90ad7`:
  - **The PR's run** (37164973677) passed in 4 min 26 s. `make -k test`
    took 218 s; the CCL and ECL step was skipped, as on every pull request.
  - **A dispatched run of `main`'s steps** (37164985716,
    `workflow_dispatch` on the branch) passed in 11 min 37 s: `make -k
    test` in 174 s, then CCL's native suite in 112 s and ECL's in 363 s,
    compiling included. That answers finding 11: a branch can add the
    trigger and be dispatched before it reaches `main`.
  - **Both matched the local runs:** `make info`'s versions, the pure
    suite's 581 tests on each Lisp, and the native suite's 197, 207 and
    188. The CCL watchdog restarted nothing.
  - `main`'s full run takes under 12 minutes, not the 16 finding 5
    estimated: ECL's suite took 363 s, not about 9 minutes, partly from
    Task 5's speedup.

### 2026-10-02 — M3 unknown extensions, version probes and property testing (branch `m3-extensions-versions-properties`)

- **Built** (M3 spec §4 to §6; ADR-0020; ADRs 0005, 0007, 0008, 0009, 0014
  and 0018 amended):
  - **the version cross-check:**
    - `version-number` and `number-version` in `/native-core`;
    - startup also requires `cmark_version()` to return `#x001D000D`;
  - **unknown-extension tests:** six native tests on nodes built through
    cmark's public API, with test-only bindings. They pin what M2b's
    copier already did:
    - unknown nodes are kept as `:extension`;
    - custom nodes are rejected;
    - the output bounds and the HTML tree refuse unknown nodes;
  - **property-based testing** (ADR-0020):
    - our own splitmix64 generator and delta-debugging shrinker;
    - three generators;
    - five properties as nine Parachute tests: the HTML and XML oracles,
      the bounds, clean outcomes, and UTF-8;
    - exact excuses for ADR-0014's two divergences;
    - `PROPERTY_SEED` and `PROPERTY_CASES` for the suites;
    - `make fuzz`, with `FUZZ_SEED` and `FUZZ_CASES`;
  - **a fix for the bug the properties found** (M3 finding 7): positions
    accept any integer, as cmark reports them (ADR-0005). By the user's
    decision, M1's rejection test lost its two negative cases, which an
    acceptance test now covers.

  Eleven tasks and a step 7b, run by subagents one at a time, with the
  documents alongside:
  - Sonnet for:
    - the version check and the unknown-extension tests;
    - two properties, check-it and the benchmark;
    - the fix and the integration;
    - the mechanical review fixes;
  - Opus for the harness, the oracle properties, ADR-0020, the documents
    and the reviews.
- **Tests,** in the Guix container, from a cold cache:
  - the pure suite runs 579 tests on SBCL, CCL and ECL (M2b: 528). That's
    1,692 assertions on SBCL and ECL, and 1,691 on CCL;
  - the native suite runs 183 tests with 1,436 assertions on SBCL (M2b:
    137);
  - `make test` takes 155 s, of which the properties take about 29 s;
  - `make fuzz`, at 150,000 cases a property, takes about 2.5 minutes.

  Every check was seen to fail, under its task's mutations and under each
  review fix's.
- **The spike** (spec §6; [the benchmark](2026-10-02-m3-benchmark.md)):
  check-it ran against our own generator, on the same generators and
  properties.
  - **The existing suite caught all seven benchmark mutations.**
  - **The properties caught five,** the same five with each contender,
    shrunk to inputs of 0 to 37 characters. They missed the footnote bound
    (finding 8) and a loose table-cell bound.
  - **2.2 million cases** on the fixed code found nothing.
  - **They found one real bug,** finding 7, which the corpus never reached.

  ADR-0020 adopted property testing with our own generator, and the user
  confirmed it. Ours is as effective as check-it and fits the project
  better, with replay on every Lisp and no dependency. It is not stronger.
- **Reviews:**
  - **Round 1:** two Opus reviewers, split by area.
    - One found no must-fix and five should-fixes.
    - The other found two must-fixes: the repeat excuse hid real converter
      bugs, and ADR-0018 contradicted itself.
  - **Fix rounds** F1 (Opus) and F2 (Sonnet), with the documents.
  - **Round 2:** one Opus reviewer.
    - Every fix checked out, and seven converter mutations couldn't break
      the exact repeat excuse.
    - One should-fix: a docstring claimed cmark reports negative lines,
      which it doesn't. Fixed in F3.
- **Found** (spec findings 1 to 10):
  - **1 and 2:** M2b already checked the version string, and
    `cmark_version()` packs the version as gfm does, not as its header
    says;
  - **3 and 4:** cmark's public API builds unknown nodes, and new node
    types are process-wide state;
  - **5 and 10:** check-it replays only on the Lisp that made a run, and
    its generator language can't express Markdown generators;
  - **6 and 8:** generated inputs rarely hold footnotes;
  - **7:** cmark reports a negative start column inside a paragraph that
    the table extension rebuilt;
  - **9:** ADR-0014's list of divergences was incomplete: three more
    shapes, and a fourth failing input.
- **Found, besides:**
  - `ocicl install`, run from a directory inside the repository, writes to
    the project's `ocicl.csv`. A probe's install was undone.
  - Two Parachute traps caught vacuous tests: `is` with an ordering
    comparator reads its arguments in reverse, and a bare `fail` passes on
    any error, an undefined function included.
  - ECL compiles a call to a function in the same file directly, so
    `with-redefined` can't replace it there. The three library functions
    the tests redefine that way are now `notinline`.
  - A helper's name, reused in a second test file of the same package,
    silently emptied two tests. Task 9 caught it.
  - Debian's own libcmark-gfm survived every property case in the
    `debian:trixie` run. A reviewer had feared it keeps cmark's `assert()`s.
  - **Run on the host,** outside `scripts/guix-env`, `make deps` and `make
    fuzz` failed obscurely, the maintainer found after the PR opened. So:
    - the toolchain targets now fail fast, before any Lisp starts, naming
      the missing tool and the command to run instead, `scripts/guix-env
      make <goal>` (`scripts/require-tools`);
    - the native runners check cmark-gfm's libraries before any test;
    - `make check-preflight`, part of `make test`, pins both, in 26 checks.
- **For M4:** the native properties on CCL and ECL.
- **Follow-up:** a footnote-aware generator, with excuses or fixes for
  finding 9's inputs.
- **CI evidence (local, before the commit):** the workflow's steps ran in
  `debian:trixie` under Docker, against the working tree, twice: after the
  first review's fixes, and again on the final tree.
  - **`make info`** reported x86_64, SBCL 2.5.2.debian, ECL 24.5.10,
    CCL 1.13, cmark-gfm 0.29.0.gfm.13 and ocicl 2.9.0.
  - **Every step passed** both times, and `make -k test` took 152 s.
  - **With one fixture byte flipped,** every suite failed both times: the
    pure suite on all three Lisps, `check-fixtures` (naming `paragraphs`)
    and the native suite.
  - **The CCL watchdog** restarted one hung start, in the first run's
    flipped pass. The second run needed none.
- **CI evidence (GitHub):** PR #8's runs passed on both commits: `97a66c6`
  in 4 min 19 s (run 37070701938), and `80954e0`, with the fail-fast
  checks, in 4 min 22 s (run 37074812870).
  - **The results matched the local runs:** the same `make info` versions;
    the pure suite's 579 tests on each Lisp; the native suite's 183; and
    the preflight's 26 checks.
  - **`make -k test` took 213 s** on GitHub, in both runs, 55 s more than
    M2b's 158 s. In the first run:
    - the native suite took 71 s (M2b: 34 s), mostly the native
      properties;
    - the pure suite took 119 s (M2b: 101 s), with the UTF-8 property on
      three Lisps and 51 new tests.

    So the properties cost roughly 40 to 45 s there, close to ADR-0020's
    projection of 39 to 42 s.

### 2026-10-01 — M2b native layer (branch `m2b-native-layer`)

- **Built** (M2 spec §3 and §5 to §8, ADRs 0016 to 0019):
  - the dependencies, pinned in `ocicl.csv`: CFFI and bordeaux-threads,
    with alexandria, babel, trivial-features, global-vars and
    trivial-garbage;
  - `/util`: the UTF-8 encoder (a lone surrogate becomes U+FFFD) and
    `decode-utf8` (U+FFFD for each maximal subpart);
  - the conditions: `invalid-option` over `invalid-parse-option` and
    `invalid-render-option`; `resource-limit-exceeded`;
    `unsupported-input`; and `native-error` with its six subtypes;
  - `/native-core`, pure, tested on all three Lisps:
    - cmark's constants, checked against its header;
    - `classify-node` and `resolve-cmark-libraries`;
    - options and their bits;
    - the three limits and the table-cell bound;
    - the output bounds' per-node terms;
    - the input guard's scanner;
  - `/ffi`, and `/native`:
    - startup under a lock;
    - holds, and the save and restore hooks;
    - the finish lock;
    - documents with an alive flag, and counters;
    - interrupts deferred around each cmark call;
    - the walker, the copier, rendering, and the output-bound walks;
  - `cl-commonmark-gfm`: `parse`, `markdown->html`, `markdown->plaintext`
    and `markdown->html-tree`, with the re-exports;
  - tests: the corpus reader, the four oracles, the crash guards, threads,
    saved images and interrupts; `tests/run-native.lisp`,
    `make check-native`, and the CCL start watchdog (`make
    check-watchdog`).

  Eleven tasks and a task 9b, run by subagents one at a time, with the
  documents alongside:
  - Sonnet for the dependencies, `/native-core`, the renderers and the
    corpus, the input guard, and the mechanical fixes;
  - Opus for the native layer, threads and images, the copier, the XML
    oracle, the output bounds, the documents, the reviews and the subtle
    fixes.
- **Tests,** in the Guix container, from a cold cache:
  - the pure suite runs 528 tests on SBCL 2.6.4, CCL 1.13 and ECL 24.5.10
    (1,569 assertions on SBCL and ECL, 1,568 on CCL, whose
    `(code-char #xD800)` is `nil`). M2a ran 280;
  - the native suite runs 137 tests with 1,280 assertions on SBCL;
  - the watchdog's test passes 37 checks under bash and dash;
  - all 28 fixtures match, and `check-help` and `check-guix` pass;
  - `make test` takes 122 s, three Lisps and the native suite included.

  Every check was seen to fail: under each task's listed mutations, and
  for each review fix, before the fix.
- **The four oracles:**
  - cmark's own expectations: 741 of 741 examples, byte for byte;
  - the HTML oracle: 2,241 of 2,241 (747 examples, three softbreaks), and
    668 of 668 comparing `:link-policy :unsafe` with `:unsafe-html t`;
  - the XML oracle: 747 of 747, positions included;
  - the fixture ASTs: 28 of 28.

  The corpus hits neither of ADR-0014's divergences. Two minimal inputs
  pin them, with exact HTML.
- **Crash guards:**
  - no bound ever undercounted:
    - across the corpus, 8,964 HTML and 4,482 plaintext comparisons;
    - crafted inputs and 20 of cmark's stress inputs;
    - a reviewer's fuzz of 324,000 comparisons, and 48,212 more
      footnote-heavy ones;
  - the table-cell bound is tight on cmark's tables stress input (89,998
    cells against 90,000);
  - each source of blowup is rejected, and the monotonic counters show
    when: before any parser for the input and table-cell limits, before
    any buffer for the output limit;
  - a 1 MiB prose document bounds to about 5.9 MiB of HTML.
- **Reviews:**
  - **two Opus reviewers,** split by area:
    - the native runtime's reviewer ran three rounds;
    - the pure core, test validity and the documents' reviewer ran two;
  - **round 1** found 8 must-fixes, among them:
    - a save hook that closed cmark under other threads' parses;
    - a raw decoder error on valid input;
    - a parsed document's `:extensions` that could alias the global
      list;
    - a circular override that hung startup;
  - **round 2** found the interrupt deadlock and a wrong document claim,
    and **round 3** two should-fixes. All are fixed;
  - **accepted as nits:** conditions naming internal operations, and
    CFFI's library table growing by two entries per startup.
- **Found** (spec findings 14 to 21; each changed the design):
  - **14. Concurrent parses corrupt each other** through cmark's global
    tables: 246 of 320 wrong. Fixed by the finish lock.
  - **15. A restart in one process needs both libraries to unload.**
    `/proc/self/maps` checks guard it.
  - **16. cmark misreads a footnote label that starts with an entity for
    `^`:** heap bytes in the output, and a fault on a long label. Fixed by
    the input guard and `unsupported-input` (ADR-0019). It's an upstream
    bug, unfixed at cmark-gfm's newest commit.
  - **17. References inside a dropped definition still render backrefs.**
    The HTML bound counts openers in the input.
  - **18. SBCL runs save hooks before it refuses a save with threads
    running.** Fixed by holds: closing refuses while a call holds the
    state.
  - **19. cmark can cut a character in a dangling label.** Output is
    decoded with U+FFFD.
  - **20. CCL 1.13's release binary sometimes hangs before it starts,**
    under Docker on Linux 7.1.1 (6 hangs in 30). Fixed by the watchdog
    (ADR-0013).
  - **21. An interrupt that unwinds out of a cmark call can deadlock** on
    glibc's malloc lock: 20 of 20 runs without the deferral. Fixed by
    deferring interrupts during each call, which costs about 6 to 9% on a
    1 MiB document.
- **Found, besides:**
  - A source mutated, run and restored within a second keeps its mutated
    fasl. Mutation series now delete fasls before every run.
  - Debian's SBCL 2.5.2 trips an internal AVER after many aborted saves
    with threads running. The saved-image test makes one deterministic
    attempt.
  - `markdown->html` returned babel's octet count as a second value; it
    now returns one value.
  - CFFI on SBCL loads libraries without `:dont-save`, so a saved image
    would reopen cmark; the save hook closes it first.
  - Task 4 was implemented before its tests were run, and made up for it
    with a mutation for each of its 39 tests.
- **For M4:**
  - the native suite on CCL and ECL;
  - ECL's `:dffi` check and its deferred interrupts;
  - `strlen` and `memcpy` through `foreign-funcall` on ECL;
  - whether CCL's save path unwinds threads that hold the state.
- **CI evidence.** The workflow's steps ran three times, with the same
  results each time:
  - **locally,** in `debian:trixie` under Docker, against the working tree
    before the commit, the step M2a lacked;
  - **locally again,** against commit `cf88cfd`. The clone included
    submodules, and both toolchain checksums matched;
  - **on GitHub:** PR #5's run, the project's first to start, passed in
    3 min 23 s (run 36934771014).

  In each run:
  - **`make info`** reported x86_64, SBCL 2.5.2.debian, ECL 24.5.10,
    CCL 1.13, cmark-gfm 0.29.0.gfm.13 and ocicl 2.9.0.
  - **The other checks:** `check-help`, the launcher tests (28 of 28),
    `check-vocabulary`, `check-pins`, `check-notice` and `make deps`
    passed.
  - **`make -k test` passed,** in 117 s and 115 s locally and 158 s on
    GitHub:
    - the watchdog's 37 checks;
    - the pure suite's 528 tests on each Lisp;
    - the fixtures;
    - the native suite's 137 tests, which found Debian's libraries by
      directory search.

  **With one fixture byte flipped,** both local runs failed every suite:
  the pure suite on all three Lisps, `check-fixtures` (naming
  `paragraphs`) and the native suite.

  **The watchdog at work:** in both local runs' flipped pass, the pure
  suite's first CCL start hung (finding 20). Each time the watchdog killed
  it after 30 s, and the second start ran. No other suite run needed a
  restart, on GitHub either.

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
  - [x] Settle the two footnote divergences against the oracle. Done in
    M2b: the HTML oracle hits neither over the whole corpus (Task 7), so
    both stay documented in ADR-0014, and two direct tests pin them.
  - [x] The copier gives each reference its definition's label as written.
    Done in M2b: Task 6's label test (ADR-0018).
  - [x] Show that each hand-built fixture AST equals the copier's. Done in
    M2b: Task 6's witness 4 compares all 28 cases (ADR-0018).
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
