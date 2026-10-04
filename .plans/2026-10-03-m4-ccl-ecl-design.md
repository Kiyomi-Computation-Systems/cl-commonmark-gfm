# M4: CCL and ECL — design

- **Date:** 2026-10-03
- **Status:** Approved 2026-10-03. Amended 2026-10-03, during M4a:
  findings 12 to 22; §4's "CFFI only" exception; §5.1's star-path test on
  ECL; §5.2's race, which skips ECL; §5.3's failed-startup and restore
  rules; §5.4's
  outcomes and forgetting; §5.6's cancelled runs; §5.8's documents; §7's
  checks
- **Milestone:** M4, in two slices, each with its own plan, branch and PR:
  M4a on branch `m4a-ccl-ecl-dynamic-ffi`, then M4b on its own branch once
  M4a has merged
- **Inputs:**
  - the [project plan](cl-commonmark-gfm.org)'s M4, its "Runtime-specific
    CFFI behavior" section and its support matrix;
  - ADR-0001, 0004, 0008, 0009, 0013, 0017 and 0020;
  - the [M2 spec](2026-09-30-m2-native-layer-design.md) §5.2 to §5.4, §8.4
    and §8.5, and its findings 15, 18, 20 and 21;
  - the hand-offs in [progress.md](progress.md): M2a's CCL label tables,
    M2b's "For M4" and M3's native properties;
  - CFFI's `src/cffi-ecl.lisp`, `src/cffi-openmcl.lisp` and
    `src/package.lisp`, as ocicl serves them (cffi-20260821-787d3cd);
  - ECL 24.5.10's builder (`c::*ld-format*`, `c::*ld-libs*`) and its
    `asdf:make-build`;
  - Debian trixie's `libcmark-gfm-dev` and `libcmark-gfm-extensions-dev`.

Each rule below is stated here once. ADR-0021 records linked programs
(§6.1).

## 1. Goal

The plan's M4: run the same native suite on CCL and ECL, and add only the
loader and deployment branches that observed differences justify. Exit:
the dynamic-FFI steps pass in CI's one job (ADR-0013), and the ECL
static-link recipe is exercised. So M4 delivers two slices:

1. **M4a, CCL and ECL with dynamic FFI** (§5). The native suite runs on
   all three Lisps, CI runs it on CCL and ECL on `main`, and the hand-offs
   from M2a, M2b and M3 are settled.
2. **M4b, ECL static deployment** (§6). An ECL program with cmark-gfm
   linked in starts up without loading anything. A recipe builds one, and
   `make check-ecl-static` exercises it. `dynamic-ffi-unavailable` is
   tested on a real ECL without dynamic FFI.

**Success, M4a:**
- `make test` and `make check-native NATIVE_LISPS="ccl ecl"` pass in the
  Guix container and in a local `debian:trixie` run of `main`'s CI steps.
- Every new check has been seen to fail (§7).
- On GitHub, the PR's run passes, and so do the CCL and ECL steps: on the
  branch through `workflow_dispatch` if GitHub allows it before the merge
  (finding 11), otherwise in `main`'s first run after it, recorded in
  M4b's close-out.

**Success, M4b:**
- `make check-ecl-static` passes in the container and in a local
  `debian:trixie` run. `make check-ecl-nodffi` passes in the container
  whose ECL has no dynamic FFI.
- Every new check has been seen to fail.
- On GitHub, the PR's run passes, and so do `main`'s steps: on the branch
  through `workflow_dispatch` before the merge, if GitHub runs the
  branch's version of the workflow (finding 11), otherwise in `main`'s
  first run after it.

## 2. Decisions made while brainstorming

| # | Question | Decision |
|---|----------|----------|
| D1 | How M4 is delivered | **Two slices under this one design,** M4a then M4b, each with its own plan, branch and PR. |
| D2 | What startup does on CCL, which keeps every library it has called (findings 2 and 3) | **One pair per process.** Once a CCL process has loaded a pair, a startup naming another signals, and the same pair starts again (§5.3). |
| D3 | What CI spends on CCL and ECL (finding 5) | **Their native suites run on `main` only,** at ADR-0020's counts, with the job's timeout raised from 20 to 30 minutes. PR runs keep SBCL's native suite. A `workflow_dispatch` trigger runs `main`'s steps on any branch. `NATIVE_LISPS` keeps its `sbcl` default, so `make test` stays what a PR runs (§5.6). |
| D4 | How startup knows cmark-gfm is linked into the program | **From the build:** linked when ECL compiled the native layer with CFFI's `:c/c++` method. Nothing to set (§6.1). |
| D5 | Where a real ECL without dynamic FFI runs | **Locally, in a second Guix container** (§6.4). CI runs the static program on the stock ECL, with its dynamic FFI disabled. |
| D6 | What the static check runs | **The 28 oracle fixtures,** through `markdown->html` and through the tree path (§6.3). |

## 3. Findings

Probed on 2026-10-03 in the Guix container (SBCL 2.6.4, CCL 1.13,
ECL 24.5.10) and in `debian:trixie`, with throwaway scripts. Other
documents cite them as "M4 finding N".

1. **CCL: the native suite stops at its first lock wait with a timeout.**
   - bordeaux-threads' API v2 doesn't implement `with-lock-held`'s
     `:timeout` on CCL. It signals `keyarg-not-implemented`.
   - Two test helpers wait that way: `holds-read-elsewhere`
     (`tests/native/startup.lisp`) and `startup-holds`
     (`tests/native/image.lisp`).
   - The error lands in a thread the test started. CCL's batch mode (`-b`)
     then ends the whole run, with exit status 255, and every result is
     lost. A global `*debugger-hook*` doesn't stop it.
   - ECL implements the timeout.
2. **CCL never unloads a library it has called into.**
   - Loaded and closed through CFFI with no call in between, both
     libraries leave `/proc/self/maps`.
   - After one call into the core (`cmark_version_string`), closing leaves
     the core mapped. After `cmark_gfm_core_extensions_ensure_registered`,
     both stay. Closing with `ccl:close-shared-library :completely t`
     leaves them mapped too, while CCL's own record says closed: open count
     0, no handle.
   - CFFI's CCL backend ignores which library a function is in:
     `%foreign-funcall` is `ccl:external-call` by name, and
     `%foreign-symbol-pointer` ignores its library argument
     (`src/cffi-openmcl.lisp`).
   - 12 native tests expect a reset or a failed startup to unload both
     libraries, and fail on CCL: once any startup has called into the
     pair, every later check finds it still mapped.
3. **So on CCL, a later pair can run an earlier pair's code.**
   - An override naming the core twice should fail at step 5: the
     extensions' registration function isn't in the core. On CCL, after an
     earlier startup, it starts up instead. The earlier pair's extensions
     library is still mapped, and the name resolves there.
   - By inference, not shown: after a reset, a new pair's version check
     could run against the earlier pair's code.
   - M2 finding 15's crash can't happen on CCL. Registering the extensions
     pins their library, so it can't unload while the core stays.
4. **ECL passes 175 of the 176 native tests it runs.**
   - The failure is in a test's own setup.
     `a-pathname-override-holding-a-star-loads-its-native-namestring`
     copies the libraries to a name holding a `*`, which on ECL is a
     wildcard in a pathname: `uiop:copy-file` signals `file-error`.
   - ECL unloads both libraries on close. Every mapping check passed.
5. **Time, in the container,** with compiled files cached, at ADR-0020's
   counts from seed 1, each Lisp timed by the same runner:

   | Lisp | The native suite | Its 8 property tests |
   |------|------------------|----------------------|
   | SBCL | 43 s, 183 tests | 24 s |
   | CCL | 82 s, 178 tests | 61 s, 2.5 times SBCL |
   | ECL | 332 s, 176 tests; 403 s compiling first | 198 s, 8.2 times SBCL |

   - One ECL test, `neither-output-bound-undercounts-cmarks-stress-inputs`,
     takes 75 s alone. SBCL takes 7 s, and CCL 10 s.
   - Under ECL's dynamic FFI, CFFI looks each function up on every call:
     `si:find-foreign-symbol` on a fresh base string, then `si:call-cfun`
     with freshly consed type lists (`src/cffi-ecl.lisp`). How much of
     ECL's time that costs isn't measured.
   - M3's GitHub run took 1.37 times the container's time (213 s against
     155 s). By that ratio, CCL's suite would add about 2.3 minutes to a CI
     run, and ECL's about 9. Both count compiling first: CCL's 82 s plus
     about 20 s, and ECL's 403 s.
6. **ECL links cmark-gfm into a program.**
   - With `cffi-sys:*cffi-ecl-method*`, which CFFI exports on ECL, set to
     `:c/c++` while compiling, CFFI compiles each call as a direct C call
     and writes its own `extern` declaration. No headers are needed.
   - ECL's builder puts `:ld-flags` before the objects and `c::*ld-libs*`
     after them (`c::*ld-format*`). Passed as `:ld-flags`, every cmark
     symbol was undefined. The archives go first in `c::*ld-libs*`, the
     extensions before the core.
   - `asdf:make-build` built a monolithic program from a small system. It
     reported `0.29.0.gfm.13` and `#x001D000D`, found the table extension
     and rendered HTML. `ldd` listed no libcmark-gfm.
   - Guix's cmark-gfm ships both archives.
7. **Debian ships the archives, but the program fails at start there.**
   - `libcmark-gfm-dev` and `libcmark-gfm-extensions-dev` ship
     `libcmark-gfm.a`, `libcmark-gfm-extensions.a`, the headers and the
     `.so` links.
   - The program from finding 6 linked, statically and against the shared
     libraries alike, with no trouble from position-independent
     executables. At start it failed: "The packages ((ASDF/OPERATE …)
     (ASDF/LISP-ACTION …)) were referenced in compiled file NIL but have
     not been created".
8. **Guix builds an ECL without dynamic FFI.**
   - `--with-configure-flag=ecl=--with-dffi=no` built it in about 5
     minutes, once. Its features have `:dlopen` but not `:dffi`.
   - Given to `guix shell -m manifest.scm`, that option leaves the
     manifest's ECL alone. A manifest that applies `options->transformation`
     to its ECL works.
   - On it, CFFI's method is `:dlopen`, cl-commonmark-gfm loads, and the
     first `markdown->html` signals `dynamic-ffi-unavailable`. Its report
     reads "start-native-layer: this ECL was built without dynamic FFI
     (:dffi): NIL", with no static-link instructions and a NIL datum.
   - The program from finding 6 builds and runs on it, with no `-lffi` in
     its link line.
9. **ECL's fasls collide.** ASDF names an ECL's output directory by version
   and platform only (`ecl-24.5.10-linux-x64`). The stock ECL, an ECL
   without dynamic FFI and a `:c/c++` build would share it, though their
   compiled calls differ. The probes kept separate caches.
10. **CCL's footnote labels.** With 46,465 distinct footnotes in 880 KB,
    `markdown->html` takes 0.28 s on SBCL and 0.44 s on CCL, and
    `markdown->html-tree` 0.49 s and 2.24 s.
11. **`workflow_dispatch`** "will only trigger a workflow run if the
    workflow file exists on the default branch" (GitHub's documentation).
    Whether a branch can add the trigger before it reaches `main` isn't
    confirmed.

Found during M4a, by Task 1:

12. **ECL can't find a library whose path holds a `*`.** With the copies
    made by `cp` (finding 4), the file exists, but ECL parses its
    pathname as wild: `wild-pathname-p` is true, and `probe-file` returns
    NIL. So `regular-file-p` reports no file, and discovery signals
    `native-library-not-found` before anything loads. The star test loads
    the copies on SBCL and CCL only. On ECL, such an override is reported
    as not found, a clear condition, so the library keeps no branch for it,
    and an ECL test checks that report (§5.1).

Found during M4a, by Task 2:

13. **ECL doesn't defer interrupts in a region that allocates.**
    - **The race fails on ECL with the deferral in place.** It leaves 2 to
      5 holds and 20 to 44 each of parsers, roots and buffers open, and
      ECL prints "Detected write access to the environment while
      interrupts were disabled".
    - **A minimal program shows why,** with no CFFI and no cmark. A worker
      loops in `mp:without-interrupts`, and another thread interrupts it
      2,000 times with `mp:interrupt-process`. When the region conses a
      20-element list, 517 interrupts run inside it in the Guix
      container's ECL 24.5.10, and 571 in Debian's. When it doesn't
      cons, 0 and 1 do.
    - **Every deferred region in `/native` allocates:** CFFI's ECL calls
      cons, and so does the bookkeeping. Regions that never allocate
      aren't practical.
    - **So, by the user's decision:** on ECL, interrupting or timing out a
      thread during a call isn't safe (ADR-0017). The race runs on SBCL
      and CCL only, and M5's documentation warns ECL users.
    - Without the deferral, the race fails three runs in three on SBCL
      (the worker deadlocks) and on CCL (parsers, roots and buffers left
      open), so it tells right from wrong on both.

Found during M4a, by Task 4 (CCL 1.13's `lib/dumplisp.lisp`,
`level-1/l1-readloop.lisp` and `level-0/l0-cfm-support.lisp`, from its
v1.13 tag):

14. **CCL never refuses a save because other threads are running.**
    - `ccl:save-application` has CCL's initial thread kill every other
      thread with an interrupt that unwinds it, waiting up to 50 ms for
      each. Only then does it run the save hooks.
    - A worker outside a cmark call was unwound, its hold ended and its
      document released, before the hook ran, in 13 saves of 13. The
      image started clean.
    - A worker inside a call defers the interrupt, so it still held the
      state when the hook ran, in 4 saves of 4. The hook refused with
      `native-state-held`, and CCL's batch mode ended the process, exit
      255, leaving an empty image file.
    - Without that refusal, CCL saves past the thread it couldn't stop
      and dies of SIGSEGV, leaving an image it can't load: 3 saves of 3,
      and the same with no cmark loaded. So the save hook's refusal is
      what keeps a busy save safe on CCL.
15. **A saved CCL image reopens cmark-gfm by bare name.** CCL keeps a
    record of each library it opened, and closing leaves it there. As an
    image starts, CCL reopens every library on that list by its soname,
    from wherever the loader finds it, not by ADR-0009's absolute paths.
    An image saved after startup started with both libraries mapped. So,
    by the user's decision, every close on CCL also makes CCL forget the
    two libraries: off its list, and every entry point it resolved in them
    detached (§5.4). That needs CCL 1.13's internal symbols, and CFFI's
    unexported handle reader. CCL's image tests break if an upgrade
    changes them.
    - **Forgetting doesn't last.** Whenever any library opens, CCL records
      every mapped library it doesn't list, so a pair it still maps
      (finding 2) comes back. And CFFI's close empties CCL's record of a
      library, keeping only its soname, rather than removing it.
    - **So the save hook also forgets.** After its reset, the save hook
      makes CCL forget every listed record of the recorded pair's
      libraries, matched by their sonames, which startup records with the
      pair, whether or not anything was published.
    - **Only a record nobody holds open is forgotten,** by every close and
      by the save hook: CCL's open count for it must be 0. Our own closes
      bring it to 0, so a pair only we opened is always forgotten. A record
      that other code still holds open is left alone, and that code's
      image reopens it, as it expects.
    - **A review corrected this finding.** It first named a gap: a pair a
      user loads through CFFI before any startup would still be reopened.
      The review's probe showed otherwise: such a load shares CCL's
      records with the startup, and forgetting them whatever their count
      forgot the user's load too. The image started with nothing mapped.

Found during M4a, by Task 5 (container, probes compiled, pinned to the
performance cores):

16. **CCL hashes short strings into few, clustered values.** Its `sxhash`
    gives "0" 65 and "00" 1601. The 71,705 shortest distinct footnote
    labels that 1 MiB allows share 41,145 values. CCL's `equal` tables on
    them slow down faster than the input grows: the two label tables took
    3.58 s of `markdown->html-tree`'s 4.85 s. Even label sets whose hashes
    are all distinct were 25 times slower than an `eql` table keyed by a
    hash of our own. So the converter's label tables now hash labels
    themselves (FNV-1a) into an `eql` table, and `markdown->html-tree`
    takes 1.26 s on CCL (SBCL: 0.41 s). The rest of CCL's time is its
    allocation and collection, in rendering and serializing, and isn't
    label-specific.
17. **Classifying a node read its type string, though only a node with an
    extension needs it:** three foreign calls and a string per node. Under
    ECL's dynamic FFI each call costs about 0.76 µs, so in the 75-second
    test that was 17 to 21 s. `native-kind` now reads it only for a node
    with an extension. The test takes 55 to 58 s on ECL, and ECL's native
    suite 269 s, from 334 s before the change: another run than finding
    5's 332 s. Copying got faster on every Lisp.
18. **CFFI's per-call lookup is 85% of a call under ECL's dynamic FFI**
    (0.64 µs of 0.76). Caching it would take the 75-second test from 55 s
    to 25 s, but the lookup is CFFI's (§9).
19. **Tests of label matching need fresh strings.** On SBCL the compiler
    coalesces equal literals within a file, so a lookup by `eql` passed
    every footnote test and the fixture oracle. A new test copies its
    labels, as a parse makes them.

Found during M4a, by the first review's fix round:

20. **On SBCL and ECL, a reset unloads the pair from under other code
    that loaded the same files.** Each Lisp keeps one entry per library
    path, shared by every load of it. So when a user's own CFFI load of
    the pair's files is open, a reset unmaps it, and that code's next call
    fails: SBCL signals `undefined-alien-function-error`, and ECL a type
    error in `foreign-data-pointer`. This predates M4, from M2b. On CCL,
    the user's load keeps the pair mapped (finding 2), and the record
    stays (finding 15). No change: loading cmark-gfm's own files beside
    this library is unsupported, as another user of cmark-gfm in the same
    process already is (ADR-0017). M5's documentation says so.

Found during M4a, by Task 2 and the second review:

21. **Each Lisp needs its own way to end a child at once while a thread
    still runs.** In a child that parked threads spinning, sleeping in C,
    waiting on a semaphore and deadlocked, some with interrupts deferred:
    - **SBCL:** `(sb-ext:exit :code 0 :abort t)` ended it in 13 to 17 ms.
      Without `:abort`, `exit` waited its 60-second `*exit-timeout*`;
    - **CCL and ECL:** C's `_exit` through CFFI ended it in 9 to 11 ms.
      CCL's `quit` took 116 to 162 ms and runs cleanup first. ECL's
      `ext:quit` hung for good on a thread with interrupts deferred, and
      its `ext:exit` passed the probe but hung after a race.
22. **A saved CCL image can start with the pair already reopened.** CCL
    reopens, by soname, every record it still lists as an image starts,
    before the restore hook runs: a record that other code held open
    across the save, or any record when the save hook was skipped. That
    image has the pair mapped, and CFFI's lookups by name land in it. A
    restore hook that always cleared the pair record let such an image
    accept another pair and run the reopened pair's code: finding 3's
    hazard. The second review showed it by probe. So the restore hook
    records the reopened pair instead (§5.3).
    - **One gap remains:** if other code held only one of the two
      libraries open across the save, the image maps that one (and, when
      it is the extensions, the core too, which the loader pulls in as
      their dependency), but CCL lists only that one, so the hook clears
      the record. Finding 3's hazard stays open for that case. The third
      review probed both halves.
    - **macOS isn't tested.** There, CCL keeps the path it opened as a
      record's soname. The hook's macOS branch follows CCL 1.13's Darwin
      source (`reopen-user-libraries`), and hasn't run. The manual macOS
      run (ADR-0001) is to cover the two image tests.

## 4. What both slices keep

- The pure systems change only if §5.7 finds a fix there.
- The project still compiles no C of its own. The static recipe compiles
  Lisp through ECL's C backend, as every ECL build does.
- Reader conditionals stay in `/native` (ADR-0017). M4 adds three there:
  CCL's pair record (§5.3), CCL forgetting the libraries it closes
  (§5.4), and the method linked mode reads (§6.1).
- **"CFFI only" gains one exception** (finding 15): to keep a saved image
  from reopening cmark-gfm, `/native` may edit a Lisp's own records of the
  libraries it loaded, through that Lisp's internals. No foreign call goes
  around CFFI.
- Every native suite still ends with the open counters at zero.

## 5. M4a: CCL and ECL with dynamic FFI

### 5.1 Tests that run on every Lisp

- **No test thread lets a condition escape** (finding 1). A helper starts
  each thread a test needs, and hands back what its function returned or
  the condition it signalled. Every test thread goes through it.
- **Waiting on a lock with a time limit** is a loop of non-blocking tries
  until a deadline, on every Lisp. It replaces `with-lock-held`'s
  `:timeout`.
- **Joining a thread with a time limit** is a loop on `thread-alive-p`
  until a deadline, since bordeaux-threads' `join-thread` takes no time
  limit. The SBCL-only tests used `sb-thread:join-thread`'s.
- **The star-path test** makes its copies with the system's `cp`, through
  native namestrings, so no pathname holds the `*` (finding 4). ECL can't
  load a library from such a path (finding 12), so on ECL a test checks
  instead that such an override signals `native-library-not-found`.
- **The interrupts-enabled checks** in the startup-failure tests get CCL
  and ECL versions, beside SBCL's `sb-sys:*interrupts-enabled*`.

### 5.2 Children on every Lisp

The interrupt test and the saved-image tests run in a child process, with
a time limit, so a deadlock fails the test instead of hanging the suite
(M2 spec §8.4).

- **A child runner for each Lisp.** It starts this Lisp's own executable
  (and, for SBCL and CCL, an image), with this process's environment, and
  returns what the child reported, as SBCL's does now.
- **A child CCL that never starts is retried.** CCL's release binary
  sometimes hangs before any Lisp code runs (M2 finding 20). So a child
  prints a start line first. A CCL child that hasn't printed it within the
  window is killed and started again, up to three times, as
  `scripts/lisp-start-watchdog` does for the suites. Only a child that
  never started is retried. Once it has started, its outcome counts.
- **The interrupt race** (M2 finding 21) runs on CCL, as on SBCL: a
  worker rendering in a loop, interrupted 2,000 times with a `throw`,
  keeps rendering, and ends with no hold and the counters at zero. It
  doesn't run on ECL, where it fails with the deferral in place
  (finding 13).
- **On each Lisp, the race must be seen to fail without the deferral**
  (§7). A Lisp where it can't be made to fail, because interrupts never
  land inside a foreign call there, drops the test, with the reason
  recorded. A test that passes either way proves nothing.

### 5.3 CCL: one pair per process

CCL can't unload a library it has called into (finding 2), so a later pair
can run an earlier pair's code (finding 3). On CCL, startup therefore keeps
the first pair a process loads:
- **The record.** Once step 3 has loaded both libraries, and before step
  4's first call, startup records the pair's truenames, as native
  namestrings: the first time, as the process's pair; later, to compare.
- **A failed startup's pair stays recorded.** Step 4's first act calls
  into the core, which pins it (finding 2). So a pair that loads but then
  fails, such as one of another version or the core named twice, is the
  process's pair from then on. Another pair needs a new process.
  M5's documentation tells CCL users.
- **Another pair is refused.** When a later startup has loaded a pair whose
  truenames differ, it closes both, before any call into them, and signals
  `native-initialization-error`. The datum is the refused pair. The reason
  names the recorded pair, and says that CCL can't unload it and that
  another pair needs a new process.
- **An error while recording,** such as a truename that can't be read,
  is also signalled as `native-initialization-error`, and leaves the
  record as it was.
- **The same pair starts again**, after a reset or a failed startup.
- **Load failures keep their own conditions.** A missing file or a file
  that isn't a library fails at step 2 or 3, as before, and is never
  recorded.
- **A saved image starts with no record, unless CCL reopened the pair.**
  The restore hook clears the record with the published state. But when
  CCL has already reopened the pair by soname as the image starts
  (finding 22), the hook records the files it reopened instead, so that
  image refuses another pair, as any CCL process does.
- **SBCL and ECL keep no record.** They unload both libraries on close
  (finding 4), so another pair loads cleanly.
- **The mapping checks expect each Lisp's behavior.** On SBCL and ECL, a
  reset or failed startup leaves nothing mapped. On CCL, once a startup
  has called into the pair, both libraries stay mapped. The open counters,
  the published state and the holds are checked on all three, as now.
- **Tests that need a fresh process run in a child CCL:** the override
  naming the core twice, and the star path. In the suite's own process
  they would meet the refusal, since the suite's pair is already recorded.
- **A new test pins the refusal on CCL:** after the suite's pair, a copy
  of the pair at another path is refused, loads nothing, and the suite's
  pair still starts.

ADR-0009 records the rule, with findings 2 and 3.

### 5.4 Saved images on CCL

The three saved-image tests now run on CCL too, in children, with
`ccl:save-application` and `ccl:*save-exit-functions*`. ECL doesn't save
images.
- **Saving after startup.** The image starts with nothing published and
  nothing mapped, and starts up again on its first call. If CCL reopens
  the libraries when the image starts, the save hook also makes CCL forget
  them.
- **Saving with the save hook removed.** The image still starts with
  nothing published (the restore hook).
- **Saving while a worker holds the state** answers M2b's question: what
  CCL does when another thread is in a call during a save. SBCL refuses
  the save (M2 finding 18). CCL unwinds the worker if it can, and
  otherwise the save hook refuses (finding 14). Both outcomes are safe,
  and a test pins each: a worker waiting outside a call is unwound and the
  image starts clean; a worker inside a call keeps its hold, and the save
  fails with the worker untouched.
- **CCL forgets each library it closes** that nothing else holds open
  (finding 15), so an image never reopens by bare name a pair only we
  opened: after a startup, after a failed one, or after a reset. A test
  saves an image after a failed startup, and checks it starts with nothing
  mapped. Another saves one while other code holds the pair open, and
  checks that the image reopens it and still starts up.

### 5.5 What the suite checks on each Lisp

- **SBCL, CCL and ECL run every native test,** but for the image tests on
  ECL and any test §5.1 or §5.2 drops on a Lisp, with its reason. That
  includes the eight property tests, at ADR-0020's counts, from the same
  seed.
- **Each suite ends with the open counters at zero,** as now.

### 5.6 Makefile and CI

- **`NATIVE_LISPS` keeps its `sbcl` default** (D3). `make test` is what a
  PR runs. `main`'s run adds `make check-native NATIVE_LISPS="ccl ecl"`.
  `make help` says so.
- **The workflow** (ADR-0013, amended):
  - `workflow_dispatch` joins the triggers, with no inputs;
  - a step after `make -k test`, `make check-native NATIVE_LISPS="ccl
    ecl"`, runs only on a push to `main` or a dispatch:
    `if: ${{ !cancelled() && github.event_name != 'pull_request' }}`;
  - `timeout-minutes` goes from 20 to 30.
- **A run on `main` can be cancelled before it starts.** GitHub cancels a
  pending run in a concurrency group when a newer one queues, even with
  `cancel-in-progress` false. `main`'s run takes near 15 minutes, by
  finding 5's estimate, so a quick third merge can cancel the second
  merge's run, and with it that commit's CCL and ECL suites. Accepted
  (ADR-0013).
- **The local CI proof** runs `main`'s steps in `debian:trixie`: all three
  native suites.
- **Before M4a merges,** dispatch `main`'s steps on the branch. If GitHub
  refuses (finding 11), `main`'s first run after the merge is the
  evidence, and M4b's close-out records it.

### 5.7 Performance hand-offs

- **CCL's footnote labels** (M2a; finding 10). Measure the most distinct
  footnote labels the default 1 MiB input limit allows, through
  `markdown->html-tree`, on SBCL and CCL. If the converter's label tables
  take most of CCL's time, replace them with a structure that doesn't
  degrade, test first. Otherwise record the numbers.
- **ECL's 75-second test** (finding 5). Find where the time goes. Fix it
  only if the cause is in our code; record it otherwise.

### 5.8 Documents for M4a

- **ADR-0008,** amended: the shell reads a node's type string only for a
  node with an extension (finding 17).
- **ADR-0009,** amended: CCL's one pair per process, with findings 2 and 3;
  ECL's `*` paths (finding 12); a saved image recording the pair CCL
  reopened (finding 22).
- **ADR-0017,** amended: CCL's hooks and deferred interrupts exercised;
  ECL's deferred interrupts tried, and not holding where a region
  allocates, so the race skips ECL (finding 13); what CCL does on a save
  with a busy worker, and CCL's forgetting (§5.4).
- **ADR-0013,** amended: CCL and ECL's native suites on `main` and on
  dispatch, the 30-minute timeout, and cancelled runs (§5.6).
- **ADR-0020,** amended: the native properties run on CCL and ECL too, on
  `main` and on dispatch.
- **The plan:** the FFI and runtime sections, the Tests section, the CI
  paragraph, the M4 milestone, the risk register and the decision log.
- **`progress.md`:** the M4 checklist, M4a's close-out, and two global
  constraints: no test thread lets a condition escape, and a CCL process
  keeps the first pair it loads.

## 6. M4b: ECL static deployment

### 6.1 Linked programs (ADR-0021)

- **What makes a program linked.** An ECL program is linked when ECL
  compiled the native layer with `cffi-sys:*cffi-ecl-method*` set to
  `:c/c++`. Every cmark call in it is then a direct C call, bound when the
  program is linked (finding 6). `/native` records, when it is compiled,
  which method that was. Nothing is set at run time (D4).
- **What startup does when linked.** It skips step 1 (the dynamic-FFI
  check), step 2 (discovery) and step 3 (loading). Steps 4 to 9 run as
  now: the version string and number, registering and finding the five
  extensions, the allocator's `free`, the smoke parse, and publishing.
- **The state names no files.** Its paths are `:linked`.
- **The override and `CL_COMMONMARK_GFM_LIBS` are ignored** in a linked
  program, since there's nothing to load.
- **Closing a linked state closes nothing.** CCL's pair record (§5.3)
  never applies.
- **Every other program is unchanged:** SBCL, CCL, and ECL with the
  `:dffi` or `:dlopen` method.
- **What a linked build needs:**
  - its own fasl cache (finding 9). Otherwise a normal ECL session could
    load fasls whose calls name symbols it never linked;
  - the two archives first in `c::*ld-libs*`, the extensions before the
    core (finding 6).
- **A pure test covers the decision** on all three Lisps: which steps run,
  for each method. The smoke program (§6.3) covers the real thing.

### 6.2 `dynamic-ffi-unavailable`

- **When.** Only on an ECL without `:dffi` whose native layer isn't
  linked. It's signalled at step 1, as now, before discovery and before
  anything loads.
- **Its datum** is the missing feature, `:dffi`, not NIL (finding 8).
- **Its reason** says how to build a linked program instead: compile with
  `cffi-sys:*cffi-ecl-method*` set to `:c/c++`, and link
  `libcmark-gfm-extensions.a` and `libcmark-gfm.a`.

### 6.3 The recipe and `make check-ecl-static`

- **The recipe** is a build script and a small system for the smoke
  program, under `tests/static/`, outside the project's `.asd`:
  1. load ASDF and CFFI, and set `cffi-sys:*cffi-ecl-method*` to `:c/c++`;
  2. put both archives first in `c::*ld-libs*`;
  3. build a monolithic program with `asdf:make-build`, its fasls under
     `build/ecl-static/`.

  The Debian start failure (finding 7) is fixed here.
- **The smoke program:**
  - on an ECL with `:dffi`, first replaces `si:call-cfun` and
    `si:load-foreign-module` with functions that signal, so any use of
    dynamic FFI fails the check;
  - checks that the published state is linked, its paths `:linked`, and its
    version `0.29.0.gfm.13`;
  - runs each of the 28 oracle fixtures, with its case's flags, through
    `markdown->html` and through `(html-tree->string (markdown->html-tree
    …))`, each compared byte for byte with the committed HTML;
  - checks that the open counters end at zero;
  - prints one line per failure and a summary, and exits 1 on any
    failure.
- **`make check-ecl-static`** builds and runs it.
  - It takes the archives from beside the shared libraries that discovery
    finds (ADR-0009): the container's profile, through
    `CL_COMMONMARK_GFM_LIBS`, or Debian's multiarch directory.
  - It fails fast, naming what's missing: `ecl` through
    `scripts/require-tools`, or an archive, with the packages that ship
    it.

### 6.4 A real ECL without dynamic FFI

- **A second container.** `manifest-ecl-nodffi.scm` is `manifest.scm`
  with its ECL transformed by `--with-dffi=no` (finding 8). Guix builds it
  once, in about 5 minutes. `scripts/guix-env` takes another manifest from
  `GUIX_ENV_MANIFEST`, and `tests/guix-env-launcher.sh` covers it
  (ADR-0004, amended).
- **Its own fasl cache** (finding 9), set when the container starts with
  the other manifest.
- **`make check-ecl-nodffi`** runs on the host, as `make check-guix` does,
  and runs `make check-ecl-nodffi-inside` in that container. That target
  first checks that its ECL lacks `:dffi`, and fails otherwise. Then:
  - **the condition test:** the first `markdown->html` signals
    `dynamic-ffi-unavailable`, and leaves nothing behind: CFFI lists no
    library, `/proc/self/maps` holds no libcmark-gfm, and the open
    counters are zero. Its datum is `:dffi`, and its report names
    `:c/c++`;
  - **the smoke program** (§6.3), built and run on that ECL.
- **Not in CI** (D5). The close-outs record its result.

### 6.5 CI for M4b

On a push to `main` or a dispatch only, after the CCL and ECL native
suites:
- **a step installs `libcmark-gfm-dev` and `libcmark-gfm-extensions-dev`.**
  It comes after the native suites, so discovery always runs against
  runtime packages only, as a user's install would be (ADR-0013);
- **a step runs `make check-ecl-static`.**

ADR-0013 is amended again.

### 6.6 Documents for M4b

- **ADR-0021,** new: linked ECL programs.
- **ADR-0009,** amended: linked programs skip steps 1 to 3, and
  `dynamic-ffi-unavailable`'s datum and reason.
- **ADR-0004,** amended: the second container.
- **ADR-0013,** amended: the static step and the `-dev` packages.
- **The plan:** the ECL section, the support matrix's "ECL static
  deployment" row, the Tests section and the decision log.
- **`progress.md`:** M4b's close-out, with the second container's result
  and, if M4a needed it, `main`'s first run.

The user documentation of the recipe stays in M5.

## 7. Seen to fail

Each new check is seen to fail under a targeted change, and passes again
once it's undone. Fasls are deleted before every mutation run (global
constraint).

**M4a:**
- **The thread helper:** a test thread whose condition escapes ends CCL's
  run.
- **The lock and join waits:** a wait that ignores its deadline fails its
  test instead of hanging. A releaser thread frees the lock, or lets the
  thread end, only after the deadline, so such a wait still returns, late,
  and the test fails on what it got.
- **The CCL child retry:** a fake child that never prints its start line
  is retried, then reported. One that prints it and then hangs is not
  retried.
- **The interrupt race,** on SBCL and CCL: with `with-interrupts-deferred`
  made a plain `progn`, the race fails. SBCL's worker deadlocks, and CCL
  leaves parsers, roots and buffers open (§5.2; finding 13).
- **CCL's pair record:** without the comparison, the refusal test fails;
  without the restore hook's clearing, a child started from an image
  reports a recorded pair before its first call. With a restore hook that
  always clears, both images that CCL reopened the pair in accept the
  copies (finding 22); with one that lets an unreadable truename's error
  escape, the in-process restore test fails.
- **Saved images on CCL:** without the save hook, the image starts with
  cmark-gfm mapped; without the restore hook, the hookless image starts
  with something published; forgetting a record whatever its open count,
  the image saved while other code holds the pair open starts with nothing
  mapped.
- **The performance fix,** if any: its test fails on the old structure.

**M4b:**
- **Linked mode:**
  - the smoke program built with the `:dffi` method fails its linked-state
    check, or a poisoned function signals;
  - a startup that loads even when linked trips the poisoned
    `si:load-foreign-module`.
- **The linked decision's pure test:** each method mapped to the wrong
  steps fails it.
- **`dynamic-ffi-unavailable`:**
  - without step 1's check, CFFI's own error arrives instead, and the
    condition test fails;
  - without the instructions in its reason, the report check fails.
- **The smoke comparisons:** one fixture byte flipped fails both paths for
  that case.
- **The second container's guard:** `make check-ecl-nodffi-inside` run in
  the ordinary container fails at once, naming the reason.
- **The static check's preflight:** with no `ecl`, or no archive,
  `make check-ecl-static` fails at once, naming it. New
  `tests/make-preflight.sh` cases pin both.

## 8. Documents

§5.8 and §6.6 list each slice's. The plan's decision log gets two
entries: 27 for M4a (CCL's one pair per process, and CCL and ECL in CI on
`main`), and 28 for M4b (ADR-0021).

## 9. Out of scope

- **User documentation** of the recipe and of CCL's one pair per process:
  M5.
- **The manual macOS run:** before the release, in M5 (ADR-0001).
- **arm64 Linux:** unverified, as before (ADR-0001).
- **Static deployment on SBCL or CCL.**
- **Faster dynamic calls on ECL.** CFFI's per-call lookup is CFFI's
  (finding 5).
- **An ECL without dynamic FFI in CI** (D5).
- **The whole native suite as a linked program.** The smoke program
  covers linked startup and rendering, and the dynamic suites cover the
  rest.
