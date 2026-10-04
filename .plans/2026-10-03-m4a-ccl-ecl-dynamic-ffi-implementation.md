# M4a CCL and ECL with dynamic FFI — implementation plan

- **Spec:** [2026-10-03-m4-ccl-ecl-design.md](2026-10-03-m4-ccl-ecl-design.md)
  (approved 2026-10-03), §1, §2, §3, §4, §5 and §7
- **Branch:** `m4a-ccl-ecl-dynamic-ffi`
- **Scope:**
  - native tests that run on every Lisp: test threads, lock waits and
    joins, the star path and the interrupt checks;
  - child processes on every Lisp, with a start retry for CCL, and the
    interrupt race on CCL;
  - CCL's one pair per process;
  - saved images on CCL;
  - the two performance hand-offs;
  - CI: CCL and ECL's native suites on `main` and on dispatch;
  - the documents for this slice.

M4b gets its own plan once M4a has merged.

## Brief for every task

Each task goes to one subagent, which works only on the files its task
owns. If another file needs changing, the agent reports it instead of
editing it.

- **Read first:**
  - `AGENTS.md`;
  - the global constraints in `.plans/progress.md`;
  - the spec sections the task names, the M4 findings they cite, and the
    ADRs they cite.
- **Run builds and tests only through the container.** Batch commands into
  one call, e.g. `scripts/guix-env sh -c 'make check-native && make
  check-native NATIVE_LISPS=ccl'`; each call takes seconds to start.
  - `make check-native` runs the native suite on SBCL (about 45 s).
  - `make check-native NATIVE_LISPS=ccl` runs it on CCL (about 1.5 min),
    and `NATIVE_LISPS=ecl` on ECL (about 6 min, 7 compiling first).
  - Iterate on the Lisp the change is about. Every task ends with all
    three: `make check-native NATIVE_LISPS="sbcl ccl ecl"`.
  - `make check-purity` runs the pure suite on all three Lisps.
- **TDD, red first.** Write the task's tests first and run them. The
  report shows each new test failing, with its output, before any
  implementation exists. Then implement.
- **Seen to fail.** Every check the task adds must fail under the
  mutations listed for it:
  - apply each mutation, watch the failure, revert;
  - report what failed and how;
  - before every run of a mutation series, the restoring run and the
    final run included, delete the project's own fasls: `find
    .guix-env/cache/common-lisp -type d \( -path
    '*/cl-commonmark-gfm/src' -o -path '*/cl-commonmark-gfm/tests' \)
    -prune -exec rm -rf {} +`. ASDF compares file dates to the second, so
    a source mutated and restored within a second keeps its mutated fasl
    (global constraint). The dependencies' fasls may stay: no mutation
    touches them;
  - after a series, `git diff --stat src/ tests/` shows only the task's
    own changes.
- **Two Parachute traps make vacuous tests:**
  - `(is < a b)` evaluates `(< b a)`: an ordering comparator gets the
    actual value first. Write `(true (< a b))`;
  - a bare `(fail form)` passes on any error, an undefined function
    included. Always name the exact condition type.
- **Stay inside the repository.** Never delete or change anything outside
  it, such as `~/.cache/common-lisp/`, even as a precaution. Scratch work
  goes under `.guix-env/tmp/`.
- **Existing expectations stand.** What a test expects on SBCL and ECL
  never changes to make new code pass. Where CCL behaves differently
  (findings 2 and 3), its expectation goes beside the old one under
  `#+ccl`, and the old one keeps running elsewhere under `#-ccl`. No test
  is loosened to pass.
- **Read cmark's behavior from `vendor/cmark-gfm`, and a Lisp's or CFFI's
  from its source or a probe, never from memory.** Every such fact a test
  or comment relies on names where it came from.
- **Large values stay out of assertions** (global constraint).
- **Assert on what was signalled.** Use `fail` with the exact condition
  type, then check the slots that carry the meaning.
- **Restore what a test changes,** in `unwind-protect`: a redefined
  function, a rebound variable, a hook list, a record.
- **The open counters are zero** after every native test, and at the end
  of every suite.
- **No test thread lets a condition escape** (from Task 1): every thread
  a test starts goes through `make-test-thread`. On CCL an escaped error
  ends the whole run (finding 1).
- **Every child process has a time limit** (from Task 2), and goes through
  `run-child`.
- **When a task adds a check to an existing flow,** it also tests that
  flow's existing error paths, so the check can't break them.
- **Lisp style:**
  - follow AGENTS.md's conventions;
  - no optimization `declaim`s;
  - `:import-from`, never `:use`, apart from `cl` and the primary
    package's re-exports;
  - tests reach internal helpers as `package::symbol`;
  - reader conditionals only in `/native` and in tests.
- **Don't commit.** The user commits.
- **Report:**
  - the files changed;
  - each new test's red output;
  - the test and assertion counts per Lisp, and each suite's run time;
  - the mutations, and how each failed;
  - anything found, numbered for the spec if it's new.

## Execution

The code tasks share one working tree, so they run **one at a time**. The
documents never load Lisp, so they run alongside a code task.

| Step | Task | Model | Alongside |
|------|------|-------|-----------|
| 1 | 1 Tests that run on every Lisp | Sonnet | 7 Documents, part 1 (Opus) |
| 2 | 2 Children on every Lisp | Opus | |
| 3 | 3 CCL: one pair per process | Opus | |
| 4 | 4 Saved images on CCL | Opus | |
| 5 | 5 Performance hand-offs | Opus | 7 Documents, part 2 (Opus) |
| 6 | 6 Makefile and CI | Sonnet | |
| 7 | 8 Review and close-out | Opus review, fixes, then a second review | |

Tasks that run alongside each other share no files.

**What may still fail between tasks.** Each task's verify run names every
failing test. Until Task 3, CCL fails exactly the 13 tests of findings 2
and 3, all in `tests/native/startup.lisp`:
- 12 whose mapping check expects a reset or a failed startup to unload
  both libraries:
  - `a-reset-unmaps-both-libraries`;
  - `a-missing-override-file-signals-native-library-not-found`;
  - `a-file-that-is-no-library-signals-native-library-not-found`;
  - `another-version-signals-native-abi-mismatch`;
  - `another-version-number-signals-native-abi-mismatch`;
  - `an-error-reading-the-version-signals-native-abi-mismatch`;
  - `an-error-reading-the-version-number-signals-native-abi-mismatch`;
  - `a-negative-version-number-is-reported-as-its-unsigned-version`;
  - `a-missing-extension-signals-native-initialization-error`;
  - `a-null-allocator-free-signals-native-initialization-error`;
  - `a-failed-smoke-parse-signals-native-initialization-error`;
  - `a-null-root-in-the-smoke-parse-signals-native-initialization-error`;
- and `an-override-naming-the-core-twice-signals-native-initialization-error`,
  which starts up instead (finding 3).

Any other failure stops the task. From Task 3 on, nothing fails on any
Lisp.

## Interfaces the tasks share

**Files,** in `cl-commonmark-gfm.asd`'s `/native-tests`, `:serial t`:

| File | Change | Task |
|------|--------|------|
| `tests/native/helpers.lisp` | the thread, join and lock helpers | 1 |
| `tests/native/children.lisp` (new, before `image.lisp`) | the child runner, moved out of `image.lisp` and made portable | 2 |
| `tests/native/interrupts.lisp` | the race on every Lisp | 2 |
| `tests/native/startup.lisp` | the waits and interrupt checks (1); CCL's expectations and tests (3) | 1, 3 |
| `tests/native/image.lisp` | `startup-holds` (1); the CCL image tests (4) | 1, 4 |

**Test helpers,** in `cl-commonmark-gfm.native-tests` (Task 1):
- `(make-test-thread function &key name)` returns a bordeaux-threads
  thread. It runs FUNCTION inside a `handler-case` on `serious-condition`,
  and returns FUNCTION's value, or `(:signalled condition)` for a
  condition that would have escaped. `thread-outcome` (`threads.lisp`)
  stays as it is.
- `(join-within thread seconds)` returns THREAD's outcome, as
  `thread-outcome` gives it, or `:timed-out` when THREAD is still alive at
  the deadline. It polls `bt2:thread-alive-p`.
- `(call-with-lock-within lock seconds function)` calls FUNCTION holding
  LOCK and returns `(values result t)`, or returns `(values nil nil)` when
  it can't take LOCK by the deadline. It polls `bt2:acquire-lock` with
  `:wait nil`, and releases LOCK however FUNCTION exits.
- `(interrupts-enabled-p)` is true when this thread's interrupts are
  enabled: `sb-sys:*interrupts-enabled*` on SBCL, and CCL's and ECL's own
  indicator, which Task 1 finds and proves.

**The child runner,** in `tests/native/children.lisp` (Task 2):
- `(run-child forms &key image seconds start-tries command)` runs a
  child of this Lisp. It evaluates FORMS, strings, in turn, and is killed
  after SECONDS (`*child-seconds*`, 120).
  - It starts from IMAGE, a saved image, or this Lisp's own on SBCL and
    CCL; ECL takes no image.
  - It returns SBCL's plist, `:killed`, `:exit-code`, `:reports` and
    `:errors`, plus `:started`, whether the child printed
    `*child-start-line*`, and `:tries`.
  - The child's first act prints `*child-start-line*` and flushes. A child
    that hasn't printed it within `*child-start-seconds*` (30) is killed
    and started again, up to START-TRIES times: 3 on CCL by default, 1
    elsewhere (M2 finding 20). A child that has printed it is never
    retried.
  - COMMAND replaces the Lisp's command line, for testing the runner with
    fake children.
- `(suite-child-forms key form)` loads the native suite, reports FORM's
  value under KEY, and exits at once, abandoning any thread still
  running, on each Lisp.
- `report-to-parent` and `child-reports` move here unchanged.

**CCL's pair record,** in `cl-commonmark-gfm.native` (Task 3), internal:
- `(loaded-pair)` returns the truenames, core then extensions, of the pair
  this CCL process first loaded, or NIL before any. It is always NIL on
  SBCL and ECL.

## Task 1: Tests that run on every Lisp

Spec §5.1; M4 findings 1 and 4. **Owns:**
- `tests/native/helpers.lisp`, `tests/native/threads.lisp` and
  `tests/native/package.lisp`;
- in `tests/native/startup.lisp`: `holds-read-elsewhere`,
  `what-a-failure-handler-sees`,
  `a-startup-failure-is-handled-with-interrupts-enabled-and-no-hold`,
  `call-while-a-handler-waits` and `call-with-library-copies`;
- in `tests/native/image.lisp`: `startup-holds` only.

1. **The four helpers** (Interfaces).
2. **Every `bt2:make-thread` in `tests/native/`** goes through
   `make-test-thread`. The `sb-thread` uses in `image.lisp` and
   `interrupts.lisp` are Tasks 2 and 4's.
3. **`holds-read-elsewhere` and `startup-holds`** use
   `call-with-lock-within`, keeping what each returns when the lock can't
   be had: `:lock-held` and NIL.
4. **The interrupt checks.** `what-a-failure-handler-sees` reports
   `(interrupts-enabled-p)` on every Lisp, and the test asserts it, with
   its control, on all three.
5. **`call-with-library-copies`** copies with `cp` through
   `uiop:run-program`, on native namestrings, so no pathname holds the
   `*`. If ECL then can't load a library from such a path, the star test
   becomes `#-ecl`, with the reason in a comment and the report.

**Tests first,** on all three Lisps:
- a thread whose function signals `simple-error` gives `(:signalled
  <that condition>)`, and the suite goes on;
- `join-within` on a thread blocked on a semaphore gives `:timed-out`
  within its deadline. The test then signals the semaphore, and the thread
  ends;
- `call-with-lock-within`, while another thread holds the lock, gives NIL
  and NIL within its deadline. On a free lock it gives the function's
  value and T, and leaves the lock free;
- `interrupts-enabled-p` is true in a test, and false inside
  `native::with-interrupts-deferred`.

Before any change, run the native suite on CCL once, and record finding
1's exit 255 as the "before".

**Mutations:**
- `make-test-thread` without its `handler-case`: on CCL, the signalling
  thread ends the whole run;
- `join-within` returning NIL instead of `:timed-out`, then
  `call-with-lock-within` returning T without the lock: the helper tests
  fail;
- `interrupts-enabled-p` always true: its test fails on each Lisp;
- `call-with-library-copies` back on `uiop:copy-file`: ECL's star test
  errors (finding 4).

**Verify:** `make check-native NATIVE_LISPS="sbcl ccl ecl"`. SBCL and ECL
pass. CCL runs to its end and fails only the 13 tests named under
Execution.

## Task 2: Children on every Lisp

Spec §5.2; M2 findings 20 and 21. **Owns:**
- `tests/native/children.lisp` (new), and its line in
  `cl-commonmark-gfm.asd`;
- in `tests/native/image.lisp`: `run-child`, `suite-child-forms`,
  `report-to-parent`, `child-reports` and the helpers only they use,
  which move to `children.lisp`;
- `tests/native/interrupts.lisp`.

1. **The runner** (Interfaces). Each Lisp's command line:
   - SBCL: `sb-ext:*runtime-pathname*`, `--core`, then `--noinform
     --non-interactive --no-sysinit --no-userinit` and one `--eval` per
     form, as now;
   - CCL: `(ccl::kernel-path)`, `-I` and the image
     (`ccl::*heap-image-name*` by default), `-n -b`, and one `-e` per form;
   - ECL: `(si:argv 0)`, `-norc`, and one `-eval` per form.

   The environment is this process's, as now: `CL_SOURCE_REGISTRY`, the
   fasl cache and, in the container, `CL_COMMONMARK_GFM_LIBS`.
2. **`suite-child-forms`** on each Lisp. Prove with a probe that each
   exit form ends the child at once while a thread is still running.
3. **The interrupt race** on all three:
   - `bt2:interrupt-thread`, `make-test-thread` and `join-within` replace
     the `sb-thread` calls;
   - the pacing's random yields come from the property harness's
     splitmix64, seeded 1, on every Lisp;
   - the test is `a-worker-interrupted-again-and-again-keeps-rendering`
     on every Lisp where it can be seen to fail (below).

**Tests first:**
- **the runner, on fake children** (COMMAND), on all three Lisps:
  - `sh -c 'sleep 60'` with START-TRIES 3 is killed three times, and
    reported as never started;
  - `sh -c 'echo <start line>; sleep 60'`, with SECONDS 3, is tried once,
    and killed at its time limit;
  - `sh -c 'echo <start line>; exit 7'` is tried once, with exit code 7;
- **a real child** of each Lisp reports a value back;
- **the race** on CCL, red until the race is ported. ECL skips it (M4
  finding 13).

**Mutations:**
- the runner retrying a child that has started: the second fake child is
  tried more than once;
- the runner never retrying: the first fake child reports one try;
- **on each Lisp,** `with-interrupts-deferred` made a plain `progn` in
  `src/native/interrupts.lisp`, with `unwind-protect-deferred` made a
  plain `unwind-protect`:
  - the race must fail: a child killed at its limit, a hold left, or
    counters not zero;
  - run just the race, through a scratch runner under `.guix-env/tmp/`,
    since the mutation breaks much else. Run it three times on each Lisp.
    On a Lisp where all three runs pass, the race can't tell right from
    wrong there: make the test skip that Lisp, and give the reason in a
    comment and the report;
  - restore the source after the series.

**Verify:** `make check-native NATIVE_LISPS="sbcl ccl ecl"`, failing only
CCL's 13.

## Task 3: CCL: one pair per process

Spec §5.3; M4 findings 2 and 3. **Owns:**
- `src/native/startup.lisp` and `src/native/image.lisp`;
- `src/conditions.lisp`: `native-initialization-error`'s docstring only;
- `tests/native/startup.lisp`, but for Task 1's parts.

1. **The record, CCL only,** in `/native` (spec §5.3):
   - `(loaded-pair)` and the variable behind it (Interfaces);
   - in `start-native-layer`, once step 3 has loaded both libraries and
     before step 4: the pair's truenames are recorded if no pair is yet.
     If a pair is recorded and these differ, both libraries close,
     extensions first, and `native-initialization-error` is signalled:
     - the datum is the refused pair's truenames;
     - the reason names the recorded pair, says CCL can't unload it, and
       says another pair needs a new process;
   - `clear-native-state-on-restart` also clears the record.
2. **The docstring** of `native-initialization-error` adds the refusal.
3. **The tests,** with SBCL's and ECL's expectations unchanged:
   - `check-nothing-left-behind`: its mapping assertion becomes `#-ccl`.
     Under `#+ccl`, the mapped libcmark-gfm files are exactly the
     recorded pair, or none before any record;
   - `a-reset-unmaps-both-libraries` becomes `#-ccl`. Beside it,
     `#+ccl`: a reset leaves exactly the recorded pair mapped;
   - the core-twice test and the star test stay in-process under `#-ccl`.
     Under `#+ccl`, each runs the same scenario in a fresh child CCL
     (`run-child`), and the parent asserts the same facts from the child's
     reports;
   - new, CCL: a copy of the pair at another path is refused, with
     `native-initialization-error`, its datum the copy's truenames. After
     it: nothing published, the copies not mapped, the record unchanged,
     and the next ordinary call starts up;
   - new, all three: `loaded-pair` is NIL on SBCL and ECL after a
     startup. On CCL, it equals the truenames of the state's paths;
   - new, CCL: `clear-native-state-on-restart` clears the record. The
     test saves the record first, and puts it back in `unwind-protect`.

**Mutations:**
- no comparison: the refusal test fails;
- no clearing in `clear-native-state-on-restart`: its test fails;
- the record taken before step 3 loads both: `a-file-that-is-no-library…`
  on CCL, or the refusal test, fails. Report which;
- the `#+ccl` mapping assertion expecting none: the CCL checks fail.

**Verify:** `make check-native NATIVE_LISPS="sbcl ccl ecl"`, all passing.

## Task 4: Saved images on CCL

Spec §5.4; M2 finding 18; M2b's question about a save while a thread
holds the state. **Owns:**
- `tests/native/image.lisp`, but for Task 1's and Task 2's parts;
- `src/native/image.lisp`, only for a fix this task finds needed.

1. **The three image tests** run on SBCL and CCL:
   - the saving child saves with `ccl:save-application` on CCL;
   - "the save hook removed" removes it from `ccl:*save-exit-functions*`;
   - the second child starts from the image through `run-child :image`.
2. **The restored image** also reports `(native::loaded-pair)` before its
   first call. It must be NIL.
3. **The busy save** (`saving-while-a-worker-holds-the-state…`): probe
   what CCL does, then pin it if it's safe, as spec §5.4 defines safe. If
   it isn't safe, stop and report. The fix is a design decision.
4. **If CCL reopens the libraries** when an image starts, the save hook
   also makes CCL forget them, test first.

**Mutations:**
- no save hook: the saved image starts with something published or
  mapped;
- no restore hook: the image saved without the save hook starts with
  something published;
- the restore hook not clearing the record: the restored image reports
  one.

**Verify:** `make check-native NATIVE_LISPS="sbcl ccl ecl"`, all passing.

## Task 5: Performance hand-offs

Spec §5.7; M4 findings 5 and 10; M2a's CCL finding. **Owns:**
- scratch scripts under `.guix-env/tmp/m4a-perf/`;
- for a fix only: the file that holds the cause, and its tests.

1. **CCL's footnote labels.** Build the input with the most distinct
   footnote labels that 1 MiB allows. Time `markdown->html-tree` on SBCL
   and CCL, split into parsing and copying, `ast->html-tree`, and
   `html-tree->string`.
   - If `ast->html-tree`'s label tables take most of CCL's time, replace
     them with a structure that doesn't degrade. The footnote fixtures and
     oracles must stay green. A mutation that breaks the new structure's
     lookup must fail them.
   - Otherwise record the numbers.
2. **ECL's 75-second test.** Find where
   `neither-output-bound-undercounts-cmarks-stress-inputs` spends its time
   on ECL, with ECL's profiler or by timing its phases. Fix only a cause in
   our code, test first. Otherwise record it.
3. **The report** gives every number before and after, and says which
   parts are ours and which are the Lisps' or CFFI's.

**Verify:** if anything changed, `make test` and `make check-native
NATIVE_LISPS="ccl ecl"`, all passing.

## Task 6: Makefile and CI

Spec §5.6. **Owns:** `Makefile` and `.github/workflows/ci.yml`.

1. **The workflow** (ADR-0013):
   - `workflow_dispatch:` joins the triggers, with no inputs;
   - `timeout-minutes: 30`;
   - after `make test`, a step "make check-native (CCL and ECL)" runs
     `make check-native NATIVE_LISPS="ccl ecl"`, with `if: ${{
     !cancelled() && github.event_name != 'pull_request' }}`. A comment
     says why: it runs on `main` and on dispatch only (spec D3).
2. **The Makefile:** the comment above `NATIVE_LISPS` says it stays
   `sbcl`, and that `main`'s CI adds CCL and ECL. `check-native`'s help
   says so too.

**Verify:** `make check-help`. `git diff` shows only these changes. The
close-out's local CI run exercises the new step.

## Task 7: Documents

**Part 1,** alongside Task 1. **Owns:**
- `.plans/progress.md`'s milestones row and a new M4 checklist;
- `.plans/cl-commonmark-gfm.org`'s M4 section.

1. **`progress.md`:**
   - the M4 row becomes "in progress: M4a";
   - an M4 checklist of this plan's tasks, one line each, with the spec
     and this plan linked;
   - the fasl rule in the global constraints says that deleting the
     project's own fasl trees is enough, since mutations never touch the
     dependencies.
2. **The plan's M4:** the spec linked; the two slices; each slice's exit.

**Part 2,** alongside Task 5, once Task 4 is done. **Owns:**
- ADR-0008, 0009, 0013, 0017 and 0020: their status lines and the
  paragraphs they amend;
- `.plans/cl-commonmark-gfm.org`'s CCL and ECL sections, Tests section,
  CI paragraph and decision log;
- `.plans/progress.md`'s global constraints.

1. **ADR-0008:** the shell reads a node's type string only for a node with
   an extension (Task 5; M4 finding 17).
2. **ADR-0009:** CCL's one pair per process, with findings 2 and 3; ECL's
   `*` paths (finding 12).
3. **ADR-0017:**
   - CCL's hooks and deferred interrupts exercised; ECL's deferred
     interrupts tried, and not holding where a region allocates (finding
     13);
   - what CCL does on a save with a busy worker, and CCL's forgetting
     (Task 4);
   - which Lisps run the interrupt race (Task 2).
4. **ADR-0013:** CCL and ECL's native suites on `main` and on dispatch;
   the 30-minute timeout.
5. **ADR-0020:** the native properties run on CCL and ECL too, on `main`
   and on dispatch.
6. **The plan:**
   - the CCL and ECL sections;
   - the Tests section: native tests on all three Lisps, and children on
     each;
   - the CI paragraph;
   - decision 27, for M4a.
7. **Global constraints:**
   - no test thread lets a condition escape;
   - a CCL process keeps the first pair it loads;
   - CI runs CCL's and ECL's native suites on `main` and on dispatch.

**Verify:** no document states a rule the spec doesn't, and every link
resolves.

## Task 8: Review and close-out

1. **In the container:** `make check-help`, `make deps`, `make test` and
   `make check-native NATIVE_LISPS="ccl ecl"`; on the host, `make
   check-guix`. All green.
2. **Two Opus reviews** of the combined diff, against the spec and this
   plan, split by area:
   - the library and the native tests;
   - test validity, CI and the documents.

   Fix what they find, sending mechanical fixes to Sonnet. Then a second
   review of the fixes, since a fix round can break what the first passed.
   Keep reviewing until a round comes back clean.
3. **The local CI run, before any commit.** Copy
   `.guix-env/tmp/ci-proof-m3/run-tree.sh` to `ci-proof-m4a/` and add
   `main`'s new step after `make test`. Run it in `debian:trixie` under
   Docker:
   - every step must pass, `main`'s included;
   - with one fixture byte flipped, every suite must fail: the pure suite
     on all three Lisps, `check-fixtures`, and the native suite on all
     three;
   - check each step's exit status in `steps.txt`.
4. **Close-out** in `progress.md`:
   - the tasks done, and the test counts per suite and per Lisp;
   - the run times, the mutations seen, and anything found;
   - the local CI evidence.
5. **Ask the user** to commit and open the PR. Its GitHub run must pass.
   Then try dispatching `main`'s steps on the branch (`gh workflow run
   ci.yml --ref m4a-ccl-ecl-dynamic-ffi`). If GitHub refuses (finding 11),
   `main`'s first run after the merge is the evidence, and M4b's
   close-out records it.

**M4a is done when:**
- the native suite passes on SBCL, CCL and ECL, in the container and in
  the local `debian:trixie` run of `main`'s steps;
- every new check has been seen to fail;
- the PR's GitHub run passes, and CCL's and ECL's native suites pass on
  GitHub, on the branch or in `main`'s first run.
