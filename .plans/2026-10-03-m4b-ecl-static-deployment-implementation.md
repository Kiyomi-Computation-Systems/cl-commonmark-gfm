# M4b ECL static deployment — implementation plan

- **Spec:** [2026-10-03-m4-ccl-ecl-design.md](2026-10-03-m4-ccl-ecl-design.md)
  (approved 2026-10-03, amended before M4b), §1, §2, §3 (findings 6 to 9
  and 23 to 25), §4, §6 and §7
- **Branch:** `m4b-ecl-static-deployment`
- **Superseded in places by the reviews.** The amended spec rules where
  this plan differs: the method record is in `src/ffi.lisp` (finding 31);
  the condition test runs an order check in place of its checks that
  couldn't fail (§6.4); the build sets its own output translations, and
  escapes or refuses archive paths (finding 30); `GUIX_ENV_MANIFEST` is a
  file name at the repository root. The close-out in `progress.md` lists
  the rest.
- **Scope:**
  - a second Guix container, whose ECL has no dynamic FFI;
  - the recipe, the smoke program and `make check-ecl-static`;
  - linked mode in the native layer, and `dynamic-ffi-unavailable`'s datum
    and reason;
  - `make check-ecl-nodffi`;
  - CI: the static check on `main` and on dispatch;
  - the documents for this slice, and M4's close.

## Brief for every task

Each task goes to one subagent, which works only on the files its task
owns. If another file needs changing, the agent reports it instead of
editing it.

- **Read first:**
  - `AGENTS.md`;
  - the global constraints in `.plans/progress.md`;
  - the spec sections the task names, the M4 findings they cite, and the
    ADRs they cite.
- **Run builds and tests only through a container.** Batch commands into
  one call, e.g. `scripts/guix-env sh -c 'make check-ecl-static && make
  check-native NATIVE_LISPS=ecl'`; each call takes seconds to start.
  - `make check-ecl-static` (from Task 2) builds the linked program,
    compiling everything, and runs it: about 1.5 minutes.
  - The second container (from Task 1): `GUIX_ENV_MANIFEST=manifest-ecl-nodffi.scm
    scripts/guix-env ...`, or `make check-ecl-nodffi` on the host.
  - When the native layer changes: `make test` (about 4 minutes) and
    `make check-native NATIVE_LISPS="ccl ecl"` (about 8 minutes).
- **TDD, red first.** Write the task's checks first and run them. The
  report shows each new check failing, with its output, before any
  implementation exists. Then implement.
- **Seen to fail.** Every check the task adds must fail under the
  mutations listed for it:
  - apply each mutation, watch the failure, revert;
  - report what failed and how;
  - before every run of a mutation series, the restoring run and the
    final run included, delete the project's own fasls: `find
    .guix-env/cache*/common-lisp -type d \( -path
    '*/cl-commonmark-gfm/src' -o -path '*/cl-commonmark-gfm/tests' \)
    -prune -exec rm -rf {} +`. The glob covers the second container's
    cache. `make check-ecl-static` empties `build/ecl-static/` itself;
  - after a series, `git diff --stat` shows only the task's own changes.
- **Two Parachute traps make vacuous tests:**
  - `(is < a b)` evaluates `(< b a)`. Write `(true (< a b))`;
  - a bare `(fail form)` passes on any error, an undefined function
    included. Always name the exact condition type.
- **ECL probes and checks are compiled.** Interpreted code on ECL takes
  other paths through the FFI and interrupts, and misleads.
- **Stay inside the repository.** Never delete or change anything outside
  it, such as `~/.cache/common-lisp/`, even as a precaution. Scratch work
  goes under `.guix-env/tmp/`. The probes behind findings 23 to 25 are in
  `.guix-env/tmp/m4b-probe/`: `build5.lisp` is the recipe, proven on all
  three ECLs, and `debian4.sh` runs a build in `debian:trixie`.
- **Existing expectations stand.** No existing test changes to make new
  code pass, and no test is loosened.
- **Read ECL's, ASDF's and CFFI's behavior from their source or a probe,
  never from memory.** ECL's ASDF is in the container's store, CFFI under
  `ocicl/`, and Debian's ASDF 3.3.7.3 at
  `.guix-env/tmp/m4b-probe/asdf-3.3.7.3.lisp`. Every fact a check or
  comment relies on names where it came from.
- **Assert on what was signalled:** the exact condition type, then the
  slots that carry the meaning.
- **The open counters are zero** at the end of every suite and of the
  smoke program.
- **Lisp style:**
  - follow AGENTS.md's conventions;
  - no optimization `declaim`s;
  - `:import-from`, never `:use`, apart from `cl`;
  - tests and the smoke program reach internal functions as
    `package::symbol`;
  - reader conditionals only in `/native`, in tests and in
    `tests/static/`.
- **Don't commit.** The user commits.
- **Report:**
  - the files changed;
  - each new check's red output;
  - the counts and run times of what ran;
  - the mutations, and how each failed;
  - anything found, numbered for the spec if it's new.

## Execution

The code tasks share one working tree, so they run **one at a time**. The
documents never load Lisp, so they run alongside a code task.

| Step | Task | Model | Alongside |
|------|------|-------|-----------|
| 1 | 1 The second container | Sonnet | 5 Documents, part 1 (Opus) |
| 2 | 2 The recipe, the smoke program and `make check-ecl-static` | Opus | |
| 3 | 3 Linked mode and `dynamic-ffi-unavailable` | Opus | |
| 4 | 4 CI | Sonnet | 5 Documents, part 2 (Opus) |
| 5 | 6 Review and close-out | Opus review, fixes, then a second review | |

Tasks that run alongside each other share no files.

**What may fail between tasks.** After Task 2, the smoke program fails in
both containers, by design: the library has no linked mode yet, so its
startup looks for the files `make check-ecl-static` says don't exist, and
in the second container stops at step 1. So `make check-ecl-static` and
`make check-ecl-nodffi` fail until Task 3. Everything else passes after
every task. Any other failure stops the task.

## Interfaces the tasks share

**Files:**

| File | Change | Task |
|------|--------|------|
| `manifest-ecl-nodffi.scm` (new) | `manifest.scm`'s packages, its ECL built without dynamic FFI | 1 |
| `scripts/guix-env`, `scripts/guix-env-enter` | `GUIX_ENV_MANIFEST`, and that manifest's own fasl cache | 1 |
| `tests/guix-env-launcher.sh` | the new cases | 1 |
| `Makefile` | `check-ecl-nodffi` and its guard (1); `check-ecl-static` and its preflight (2); the condition test's step (3) | 1, 2, 3 |
| `tests/static/build.lisp` (new) | the build script | 2 |
| `tests/static/cl-commonmark-gfm-static-smoke.asd`, `tests/static/smoke.lisp` (new) | the smoke program | 2 |
| `tests/make-preflight.sh` | the static check's preflight cases | 2 |
| `src/native-core/linking.lisp` (new), `src/native-core/package.lisp`, `cl-commonmark-gfm.asd` | `linked-method-p` | 3 |
| `tests/native-core.lisp` | its pure test | 3 |
| `src/native/startup.lisp`, `src/native/package.lisp` | linked mode; the condition's datum and reason | 3 |
| `src/conditions.lisp` | `dynamic-ffi-unavailable`'s docstring | 3 |
| `tests/static/nodffi.lisp` (new) | the condition test | 3 |
| `.github/workflows/ci.yml` | the two static steps | 4 |

**Make targets:**
- `make check-ecl-static` (Task 2):
  - fails fast, before any Lisp starts: `ecl` through
    `scripts/require-tools`; then both archives in
    `CMARK_GFM_ARCHIVE_DIR`, or it exits 2 naming the missing archive and
    Debian's `libcmark-gfm-dev` and `libcmark-gfm-extensions-dev`;
  - `CMARK_GFM_ARCHIVE_DIR` defaults to the directory of the first path in
    `CL_COMMONMARK_GFM_LIBS` when that is set, as in the containers;
    otherwise to the first of ADR-0009's Linux directories
    (`/usr/lib/<multiarch>`, `/usr/lib64`, `/usr/lib`, `/usr/local/lib`)
    that holds both pinned shared libraries
    (`src/native-core/discovery.lisp`);
  - empties `build/ecl-static/`, builds the program
    `build/ecl-static/cl-commonmark-gfm-static-smoke` with
    `tests/static/build.lisp`, and runs it with `CL_COMMONMARK_GFM_LIBS`
    naming two files that don't exist, its one argument
    `tests/fixtures/html/`.
- `make check-ecl-nodffi` (Task 1), on the host: runs
  `GUIX_ENV_MANIFEST=manifest-ecl-nodffi.scm scripts/guix-env make
  check-ecl-nodffi-inside`.
- `make check-ecl-nodffi-inside`, in that container: the guard (Task 1),
  then the condition test (Task 3), then `make check-ecl-static` (Task 2).

**Library** (Task 3):
- `(cl-commonmark-gfm.native-core:linked-method-p method)` is true for
  `:c/c++` alone: pure, no CFFI.
- `(cl-commonmark-gfm.native::ffi-method)` returns the method CFFI compiled
  the native layer with: `cffi-sys:*cffi-ecl-method*`, read by a macro as
  `startup.lisp` compiles (finding 25). It is NIL on SBCL and CCL.
- A linked state's two libraries are NIL, and its paths `:linked`.

**The smoke program's output:** one line per failure, `FAIL <check>:
<detail>`, then `check-ecl-static: <n> checks, <m> failed`. It exits 0 when
nothing failed, 1 otherwise.

## Task 1: The second container

Spec §6.4; findings 8 and 9; ADR-0004. **Owns:**
- `manifest-ecl-nodffi.scm`, `scripts/guix-env`, `scripts/guix-env-enter`
  and `tests/guix-env-launcher.sh`;
- the Makefile's `check-ecl-nodffi` and `check-ecl-nodffi-inside`, with
  their help lines and `.PHONY` entries.

1. **`manifest-ecl-nodffi.scm`:** `manifest.scm`'s packages, read from it,
   not copied, with ECL alone transformed by `options->transformation` and
   `((with-configure-flag . "ecl=--with-dffi=no"))` (finding 8).
   Transforming every package could rebuild whatever is built with ECL.
   M4a's probe built this ECL (`.guix-env/tmp/m4-probe/manifest-nodffi.scm`,
   a copied list), so the matching derivation is already in the store.
2. **`scripts/guix-env`:** `GUIX_ENV_MANIFEST` names another manifest,
   relative to the repository root; unset, it is `manifest.scm`. A manifest
   that doesn't exist exits 2, naming it, before Guix starts. The variable
   is preserved into the container.
3. **`scripts/guix-env-enter`:** under any manifest but `manifest.scm`,
   `XDG_CACHE_HOME` is `.guix-env/cache-<the manifest's name without
   .scm>`, so the two ECLs never share fasls (finding 9). Nothing else
   changes.
4. **Launcher tests:**
   - with `GUIX_ENV_MANIFEST=manifest-ecl-nodffi.scm`, the command names
     that manifest, and preserves the variable;
   - a missing manifest: exit 2, naming it, and no command printed;
   - `scripts/guix-env-enter` with the variable set uses the other cache,
     and without it `.guix-env/cache`.
5. **The Makefile:** `check-ecl-nodffi` as above. `check-ecl-nodffi-inside`
   first checks that its ECL lacks `:dffi`, and otherwise fails at once,
   saying this is the container without dynamic FFI's target and to run
   `make check-ecl-nodffi`. For now that guard is all it does.

**Mutations:**
- the launcher ignoring `GUIX_ENV_MANIFEST`: the manifest case fails;
- `scripts/guix-env-enter` keeping the shared cache: the cache case fails;
- the guard removed: `make check-ecl-nodffi-inside` passes in the ordinary
  container, where it must fail. Show the guard failing there and passing
  in the second container.

**Verify:** on the host, `make check-guix` and `make check-ecl-nodffi`;
`scripts/guix-env make check-ecl-nodffi-inside` fails at once; `make
check-help`.

## Task 2: The recipe, the smoke program and `make check-ecl-static`

Spec §6.3; findings 6, 7, 9 and 23 to 25. **Owns:**
- `tests/static/build.lisp`,
  `tests/static/cl-commonmark-gfm-static-smoke.asd` and
  `tests/static/smoke.lisp`;
- the Makefile's `check-ecl-static`, with its help line and `.PHONY`
  entry, and the line of `check-ecl-nodffi-inside` that runs it;
- `tests/make-preflight.sh`.

1. **The build script,** `tests/static/build.lisp`, run by `ecl -norc
   -load` from the repository root, with `CL_SOURCE_REGISTRY` listing the
   root and `tests/static/` (one trailing slash each) and `ocicl//`, and
   `XDG_CACHE_HOME` under `build/ecl-static/`. It uses ECL's own ASDF:
   - `(require :asdf)` and `(require :cmp)`; load CFFI; set
     `cffi-sys:*cffi-ecl-method*` to `:c/c++`;
   - put `libcmark-gfm-extensions.a`, then `libcmark-gfm.a`, from
     `CMARK_GFM_ARCHIVE_DIR`, first in `c::*ld-libs*` (finding 6);
   - `(asdf:load-system "cl-commonmark-gfm-static-smoke" :force :all)`:
     everything compiles under `:c/c++`, CFFI included. ASDF 3.1.8.8's
     `make-build` can't compile it itself (finding 23);
   - `asdf:make-build` the smoke system as a monolithic `:program`, moved
     into `build/ecl-static/`. Its epilogue calls the smoke program's
     `main` and exits with its status. When `SYS:libasdf.a` doesn't
     exist, as on Debian, a prologue requires ECL's own ASDF with
     `*load-verbose*` off, before any compiled file starts (finding 23).
     ASDF 3.3's deprecation style-warning for `make-build` is expected;
   - any error prints itself and exits non-zero.
2. **The smoke system,** `cl-commonmark-gfm-static-smoke` (package
   `cl-commonmark-gfm.static-smoke`), depends on `cl-commonmark-gfm` alone:
   no Parachute. Its `main` handles every error itself, since an error
   that reaches an ECL program's debugger doesn't exit cleanly. It reads
   the fixtures directory from its one argument, and the cases from
   `cases` there, mapping the three flags as `cli-flag-options` does
   (`tests/native/render.lisp`); an unknown flag fails. Its checks, each
   counted:
   - `(cl-commonmark-gfm.native::ffi-method)` is `:c/c++`. Until Task 3
     that function doesn't exist, and the check fails;
   - the published state is linked: its paths `:linked`, its version
     `0.29.0.gfm.13`;
   - each of the 28 cases, through `markdown->html` and through
     `(html-tree->string (markdown->html-tree …))`, equals its committed
     HTML byte for byte. A failure names the case and the path;
   - after `reset-native-state`, with `*cmark-gfm-libraries*` bound to two
     files that don't exist, `paragraphs` renders again, and the startup
     count has risen by one;
   - the open counters are zero;
   - `(cffi:list-foreign-libraries)` is empty;
   - on Linux, no line of `/proc/self/maps` names `libcmark-gfm`.
3. **`make check-ecl-static`,** as the interfaces say. `make
   check-ecl-nodffi-inside` runs it after its guard.
4. **Preflight cases** in `tests/make-preflight.sh`:
   - no `ecl`: exit 2, naming `ecl`, and nothing started;
   - a stub `ecl`, and `CMARK_GFM_ARCHIVE_DIR` an empty directory: exit 2,
     naming the missing archive and `libcmark-gfm-dev`, and nothing
     started.

**Red:** the program builds, then fails on both of the container's ECLs:
on the stock ECL, `ffi-method` is undefined and the startup fails on the
files that don't exist; in the second container, the startup stops at step
1 with `dynamic-ffi-unavailable`. Show that the build succeeded and the
startup failed.

**Mutations:**
- one byte of a fixture's HTML flipped: both paths fail for that case,
  and no other;
- the archives left out of `c::*ld-libs*`: the build fails at the link,
  naming cmark's symbols;
- a `cffi:load-foreign-library` of the real core added before the final
  checks: both nothing-loaded checks fail;
- a case naming an unknown flag: that case fails, and the program still
  finishes, with exit status 1;
- an error during the build, such as the build script run directly with
  an archive directory that holds no archives: the build exits non-zero
  rather than waiting in ECL's debugger.

**Verify:** `make check-ecl-static` fails as the red says, in both
containers; `make check-preflight` passes; `make check-help`.

## Task 3: Linked mode and `dynamic-ffi-unavailable`

Spec §6.1, §6.2 and §6.4; findings 6, 8 and 25; ADR-0009. **Owns:**
- `src/native-core/linking.lisp`, `src/native-core/package.lisp`, its line
  in `cl-commonmark-gfm.asd`, and `tests/native-core.lisp`;
- `src/native/startup.lisp`, `src/native/package.lisp`, and
  `dynamic-ffi-unavailable`'s docstring in `src/conditions.lisp`;
- `tests/static/nodffi.lisp`, and the line of `check-ecl-nodffi-inside`
  that runs it.

1. **Tests first:**
   - **the pure test,** on all three Lisps: `linked-method-p` is true for
     `:c/c++`, and false for `:dffi`, `:dlopen`, NIL and any other
     keyword;
   - **the condition test,** `tests/static/nodffi.lisp`, compiled and then
     loaded on the second container's ECL, in a process of its own. It
     loads `cl-commonmark-gfm` as any session does, CFFI's method there
     being `:dlopen`, calls `markdown->html` once, and checks:
     - it signals `dynamic-ffi-unavailable`, whose datum is `:dffi`, and
       whose report names `:c/c++`, `libcmark-gfm-extensions.a` and
       `libcmark-gfm.a`;
     - it left nothing behind: CFFI lists no library, no line of
       `/proc/self/maps` names `libcmark-gfm`, and the open counters are
       zero.

     It prints one line per failure and a summary, and exits 1 on any
     failure. `check-ecl-nodffi-inside` runs it after the guard, before the
     smoke program.
2. **`/native-core`:** `linked-method-p`, in `linking.lisp`, after
   `discovery`.
3. **`/native`:**
   - `ffi-method`, with its macro, under `#+ecl`;
   - `start-native-layer`, when `(linked-method-p (ffi-method))`, skips
     steps 1 to 3: no dynamic-FFI check, no discovery, so neither the
     override nor `CL_COMMONMARK_GFM_LIBS` is read, and no load. The
     state's libraries are NIL and its paths `:linked`. Steps 4 to 8 run
     as now, their code shared with the loading path. A failure in them
     closes nothing, since nothing was loaded;
   - `check-dynamic-ffi`'s datum is `:dffi`. Its reason says this ECL
     can't load cmark-gfm at run time, and how to build a linked program
     instead: compile with `cffi-sys:*cffi-ecl-method*` set to `:c/c++`,
     and link `libcmark-gfm-extensions.a` and `libcmark-gfm.a`;
   - the docstrings of `native-state`, `start-native-layer`,
     `reset-native-state` and `dynamic-ffi-unavailable` say what a linked
     program does.
4. **Green:** `make check-ecl-static` in the container; `make
   check-ecl-nodffi` on the host; `make test`; `make check-native
   NATIVE_LISPS="ccl ecl"`.

**Mutations:**
- `linked-method-p` also true for `:dlopen`, or false for `:c/c++`: the
  pure test fails, and for the second the smoke program too;
- `ffi-method` reading the variable at run time: the smoke program isn't
  linked, and its startup fails on the missing files (finding 25);
- a linked startup that still runs steps 1 to 3: the smoke program fails
  the same way;
- a linked state whose paths aren't `:linked`: the linked check fails;
- step 1's check removed: CFFI's own error arrives instead, and the
  condition test fails;
- the reason without its instructions, or the datum NIL: the condition
  test fails.

**Verify:** everything in step 4 green.

## Task 4: CI

Spec §6.5; ADR-0013. **Owns:** `.github/workflows/ci.yml`.

After the step "make check-native (CCL and ECL)", two steps with its `if:`
(`${{ !cancelled() && github.event_name != 'pull_request' }}`):
1. **"Install cmark-gfm's archives":** `apt-get install -y
   --no-install-recommends libcmark-gfm-dev libcmark-gfm-extensions-dev`,
   with `DEBIAN_FRONTEND=noninteractive`. A comment says why it comes
   after the native suites: discovery must only ever see the runtime
   packages, as a user's install would (ADR-0009, ADR-0013).
2. **"make check-ecl-static"**.

**Verify:** the workflow parses; `git diff` shows only these changes. Task
6's local CI run exercises both steps.

## Task 5: Documents

**Part 1,** alongside Task 1. **Owns:**
- `.plans/progress.md`'s milestones row and M4 checklist;
- `.plans/cl-commonmark-gfm.org`'s M4 section.

1. **`progress.md`:**
   - the M4 row: "in progress: M4b; M4a merged 2026-10-03 (PR #9,
     `163077a`)";
   - under the M4 checklist, M4b's tasks, one line each, with this plan
     linked, in place of the line saying M4b gets its own plan.
2. **The plan's M4:** this plan linked, and the M4b exit restated as the
   amended spec's §1 has it.

**Part 2,** alongside Task 4, once Task 3 is done. **Owns:**
- `.plans/decisions/0021-linked-ecl-programs.md` (new);
- ADR-0004, 0009 and 0013: their status lines and the paragraphs they
  amend;
- `.plans/cl-commonmark-gfm.org`'s ECL section, support matrix, Tests
  section and decision log;
- `.plans/progress.md`'s global constraints.

1. **ADR-0021, linked ECL programs:** what makes a program linked, and
   that the method is read as the native layer compiles (finding 25);
   what a linked startup skips; the recipe, with ECL's ASDF in the
   program (finding 23); the checks, and why they don't replace ECL's own
   FFI functions (finding 24); the alternatives the spec rejected (D4,
   D5).
2. **ADR-0009:** linked programs skip steps 1 to 3;
   `dynamic-ffi-unavailable`'s datum and reason.
3. **ADR-0004:** the second container: `GUIX_ENV_MANIFEST`,
   `manifest-ecl-nodffi.scm`, its own fasl cache, `make check-ecl-nodffi`.
4. **ADR-0013:** the static steps on `main` and on dispatch, and the `-dev`
   packages after the native suites.
5. **The plan:** the ECL section; the support matrix's "ECL static
   deployment" row; the Tests section; decision 28, for M4b (ADR-0021).
6. **Global constraints:**
   - no build shares fasls between ECLs built differently, or with a
     linked build (finding 9);
   - CI's `main` and dispatch runs also run `make check-ecl-static`.

**Verify:** no document states a rule the spec doesn't, and every link
resolves.

## Task 6: Review and close-out

1. **In the container:** `make check-help`, `make deps`, `make test`,
   `make check-native NATIVE_LISPS="ccl ecl"` and `make check-ecl-static`;
   on the host, `make check-guix` and `make check-ecl-nodffi`. All green.
2. **Two Opus reviews** of the combined diff, against the spec and this
   plan, split by area:
   - the library, the recipe and the smoke program;
   - test validity, the containers, CI and the documents.

   Reviewers probe on copies under `.guix-env/tmp/`, with their own
   `CL_SOURCE_REGISTRY` and `XDG_CACHE_HOME`, while other checks run. Fix
   what they find, sending mechanical fixes to Sonnet and follow-ups to
   the agent that wrote the code. Review again until a round comes back
   clean.
3. **The local CI run, before any commit.** Copy
   `.guix-env/tmp/ci-proof-m4a/run-tree.sh` to `ci-proof-m4b/`, and add
   `main`'s two new steps after the CCL and ECL step. Run it in
   `debian:trixie` under Docker:
   - every step must pass, the static check included. On Debian's ECL it
     takes the prologue path (finding 23), which the containers never do;
   - with one fixture byte flipped, every suite must fail: the pure suite
     on all three Lisps, `check-fixtures`, the native suite on all three,
     and `check-ecl-static`, naming the case;
   - and once with the prologue removed from the build script: the
     program must stop at start, with finding 7's message;
   - check each step's exit status in `steps.txt`.
4. **Close-out** in `progress.md`:
   - the tasks done, the counts and run times, the mutations seen, and
     anything found;
   - the second container's result;
   - the local CI evidence;
   - the M4 row closed, once the PR's number is known.
5. **Ask the user** to commit and open the PR. Its GitHub run must pass.
   Then dispatch `main`'s steps on the branch (`gh workflow run ci.yml
   --ref m4b-ecl-static-deployment`); that run must pass too, the static
   steps included.

**M4b is done when:**
- `make check-ecl-static` passes in the container and in the local
  `debian:trixie` run, and `make check-ecl-nodffi` in the second container;
- every new check has been seen to fail;
- the PR's GitHub run passes, and so does the dispatched run of `main`'s
  steps.
