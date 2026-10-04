# ADR-0021: Linked ECL programs

- **Status:** Accepted 2026-10-04
- **Date:** 2026-10-04
- **Scope:** ECL programs with cmark-gfm linked in: how startup knows it
  runs in one, and what it skips; `dynamic-ffi-unavailable`; the recipe,
  `make check-ecl-static` and `make check-ecl-nodffi`
- **Spec:** [M4 design](../2026-10-03-m4-ccl-ecl-design.md) §2 (D4, D5),
  §3 (findings 6 to 9 and 23 to 31), §4, §6, §9
- **Amends:** ADR-0004 (a second container, whose ECL has no dynamic FFI),
  ADR-0009 (a linked startup finds and loads nothing;
  `dynamic-ffi-unavailable`'s datum and reason), ADR-0013 (the static
  check on `main` and on dispatch), ADR-0017 (a linked startup ignores
  the override, and its reset closes nothing)
- **Related:** ADR-0008 (direct binding: the project compiles no C)

## Context

- **An ECL without dynamic FFI can't load a library at run time.** Guix
  builds one: its features have `:dlopen` but not `:dffi` (M4 finding 8).
  CFFI refuses every load there, whatever its method (M4 finding 29).
  - Before M4b, the first call there signalled `dynamic-ffi-unavailable`
    with a NIL datum and no advice (M4 finding 8).
  - Without that check, startup fails only when it loads the pair, as
    `native-library-not-found`. CFFI's message then points at ECL's
    `ffi:load-foreign-library`, not at a linked program (M4 finding 29).
- **A user may want one program with cmark-gfm inside it,** and no
  cmark-gfm library to install where it runs. The plan made ECL's path
  without dynamic FFI a documented deployment case (its decision 6).
- **ECL can link cmark-gfm into a program** (M4 finding 6). With CFFI's
  `cffi-sys:*cffi-ecl-method*` set to `:c/c++` as code compiles, each
  foreign call is a direct C call, which the linker binds. Guix and Debian
  ship cmark-gfm's two static archives (M4 findings 6 and 7). Such a
  program runs on an ECL without dynamic FFI too (M4 finding 8).

## Decision

### Linked, by the build (M4 design D4)

- **What makes a program linked.** ECL compiled the native layer with
  `cffi-sys:*cffi-ecl-method*` set to `:c/c++`. Every cmark call in it is
  then a direct C call, bound when the program was linked (M4 finding 6).
  Nothing is set at run time.
- **`src/ffi.lisp` records the method, as its calls compile.** Every cmark
  call compiles there, so record and calls always agree, even in a program
  whose files were compiled under different methods (M4 finding 31).
  - A macro reads `cffi-sys:*cffi-ecl-method*` as the file compiles, and
    `ffi-method` returns what it read; `/native` imports it. The macro
    finds the variable by name, so the file needs no reader conditional.
  - The variable itself won't do at run time: as a program starts, CFFI
    sets it again from ECL's features, to `:dffi` or `:dlopen`, whatever
    the build set (M4 finding 25).
  - On SBCL and CCL the method is NIL. `linked-method-p`, in
    `/native-core`, is true for `:c/c++` alone.
- **A linked startup skips steps 1 to 3** (M2 design §5.2; M4 design
  §6.1): the dynamic-FFI check, discovery and loading. Steps 4 to 9 run
  as before: the version string and number, registering and finding the
  five extensions, the allocator's `free`, the smoke parse, and
  publishing.
  - Its state names no files: its paths are `:linked`.
  - `*cmark-gfm-libraries*` and `CL_COMMONMARK_GFM_LIBS` are ignored,
    since there is nothing to load.
  - Closing it closes nothing. After a reset, the next call starts again.
- **Every other program is unchanged:** SBCL, CCL, and ECL with the
  `:dffi` or `:dlopen` method.
- **`dynamic-ffi-unavailable` is signalled only on an ECL without `:dffi`
  whose native layer isn't linked,** at step 1, before anything loads.
  Its datum is `:dffi`, and its reason says how to link instead
  (ADR-0009; M4 design §6.2).

### The recipe

`tests/static/build.lisp` builds a program with ECL's own ASDF
(M4 design §6.3):
1. **First,** it loads CFFI, sets `cffi-sys:*cffi-ecl-method*` to
   `:c/c++`, and puts both archives first in `c::*ld-libs*`, the
   extensions before the core. ECL's builder puts that variable after the
   objects on the link line (M4 finding 6). It links every compiled file
   with it too, not only the program, so the archives must be there
   before the library compiles (M4 finding 28). Blanks and quotes in an
   archive's path are escaped for ECL's split of that variable. A
   directory holding a `*`, a `?` or a `\` is refused, since ECL reads
   those as wildcards (M4 finding 30).
2. **It compiles everything,** CFFI included, with `asdf:load-system` and
   `:force :all`: Debian's ASDF, 3.1.8.8, can't compile the library
   inside `make-build` (M4 finding 23).
   - The script sets ASDF's output translations itself, ignoring
     inherited ones, so every fasl goes under `build/ecl-static/cache/`.
     Before anything compiles, it checks that ASDF finds this
     repository's library, and that the library's fasls, the smoke
     program's and CFFI's would go there.
   - `make check-ecl-static` empties `build/ecl-static/` first.
     Otherwise a normal ECL session could load fasls whose calls name
     symbols it never linked, or one ECL load another's (M4 finding 9).
3. **`asdf:make-build` links one monolithic program.** CFFI's compiled
   code refers to ASDF's packages, so the program needs ASDF as it starts
   (M4 finding 23). Where ECL ships `libasdf.a`, as Guix's does, ASDF is
   linked in, and the program loads nothing as it starts. Where it
   doesn't, as on Debian, the program's prologue requires ECL's own ASDF
   before any compiled file starts. The user chose this split.
4. **The program ends with `ext:exit`:** the epilogue always, after the
   smoke program's `main`, with status 0 only when it passes; the
   prologue only when loading ASDF fails. ECL runs both under
   `ext:safe-eval`, which stops the unwind that `ext:quit` starts (M4
   finding 27).

The script handles every serious condition itself, and exits 1: ECL's
command line leaves any serious condition but an `error` to its debugger
(M4 finding 26).

### The checks

Both checks are plain programs, not Parachute suites: each loads the
library alone. `make` judges each by its exit status and its summary
line, which must report 0 failed. An ECL program or process that fails as
it starts lands in ECL's debugger, which quits with status 0 at the end
of stdin (M4 finding 26).

- **`make check-ecl-static`** builds the smoke program,
  `tests/static/smoke.lisp`, and runs it with `CL_COMMONMARK_GFM_LIBS`
  naming two files that don't exist, so a startup that looks for files
  fails. Its 65 checks, on Linux:
  - the method is `:c/c++`, and the published state is linked: its paths
    `:linked`, its version `0.29.0.gfm.13`;
  - right after that first startup, and again at the end, CFFI lists no
    library, and no line of `/proc/self/maps` names libcmark-gfm. The end
    alone wouldn't show a load: the restart's reset closes whatever the
    first startup loaded;
  - the manifest's 28 oracle fixtures, each through `markdown->html` and
    through `html-tree->string` of `markdown->html-tree`, byte for byte
    against its committed HTML;
  - after a reset, with `*cmark-gfm-libraries*` naming files that don't
    exist, a fixture renders again, and startup has run once more;
  - at the end, the open counters are zero.

  It takes the archives from `CMARK_GFM_ARCHIVE_DIR`, or else from beside
  the shared libraries discovery finds on Linux (ADR-0009). Elsewhere,
  such as on macOS, the variable must name the directory. It fails fast,
  naming a missing archive and the Debian packages that ship it.
- **`make check-ecl-nodffi`** runs on the host, and runs
  `make check-ecl-nodffi-inside` in the second container, whose ECL has
  no dynamic FFI (ADR-0004). Run on a Guix host outside any Guix
  environment, that target points at `make check-ecl-nodffi` instead. In
  the container it runs:
  1. a guard, which fails at once unless that ECL lacks `:dffi`;
  2. the condition test, `tests/static/nodffi.lisp`, in a process of its
     own, with `CL_COMMONMARK_GFM_LIBS` malformed (`not-a-pair`). Its 5
     checks:
     - `method`: the native layer was compiled with `:dlopen`, that
       ECL's default;
     - `discovery`: discovery itself signals `native-library-not-found`
       for that value, so a startup that ran discovery before step 1
       would fail with it;
     - `signalled`, `datum` and `report`: the first `markdown->html`
       signals exactly `dynamic-ffi-unavailable`, so step 1 came first;
       its datum is `:dffi`; and its report names
       `cffi-sys:*cffi-ecl-method*`, `:c/c++` and both archives;
  3. the smoke program, built and run on that ECL.
- **The checks look at what was loaded,** not at which functions ran.
  Replacing ECL's own FFI functions with ones that signal catches nothing:
  ECL compiles a call to `si:load-foreign-module` or `si:call-cfun` as a
  direct C call (M4 finding 24).
- **Where they run:**
  - **in CI,** on pushes to `main` and on dispatch: `make
    check-ecl-static`, with Debian's ECL, so through the prologue
    (ADR-0013);
  - **in the Guix containers,** where ASDF is linked in: `make
    check-ecl-static` on the ECL with dynamic FFI, and `make
    check-ecl-nodffi` on the one without. The second container isn't in
    CI (M4 design D5). The close-outs record its result.

### Rejected

- **A flag that says a program is linked,** set in the environment or the
  build. The build already says it: the method the native layer was
  compiled with. So there is nothing to set (M4 design D4).
- **The method record in `src/native/startup.lisp`,** beside the startup
  that reads it. ASDF doesn't recompile a file because the method
  changed, so a program can hold files compiled under different methods.
  With the record there, a program whose calls were compiled with `:dffi`
  took the linked path, loaded nothing, and failed at step 4 with a
  misattributed `native-abi-mismatch` (M4 finding 31). The user chose
  `src/ffi.lisp` after the first review.
- **An ECL without dynamic FFI in CI** (M4 design D5). A second Guix
  container runs one locally instead. Guix builds its ECL once, in about
  5 minutes (M4 finding 8).
- **Checks in the condition test that nothing was left behind.** On that
  ECL they couldn't fail: CFFI refuses every load, and step 1 comes before
  any parse. By the user's choice, the check of the order of steps 1 and
  2 replaced them (M4 design §6.4).
- **Always loading ASDF as the program starts.** Where ECL ships
  `libasdf.a`, the program links it in, and loads nothing as it starts.
  By the user's choice, only an ECL without one, such as Debian's, takes
  the prologue.
- **A newer ASDF over ECL's own,** Debian's `cl-asdf` 3.3.7.3. The
  compile went through, but the link failed on the missing `libcmp.a`
  (M4 finding 23).
- **Replacing ECL's own FFI functions to catch dynamic use.** It catches
  nothing (M4 finding 24).

## Consequences

- **On Debian's ECL, a linked program loads ECL's own ASDF as it
  starts.** Compiling ASDF into such a program is out of scope (M4 design
  §9).
- **A linked program needs ECL where it runs:** ECL's shared library,
  `libecl`, and, on Debian, ECL's `asdf.fas`. It needs no cmark-gfm
  library.
- **Building one needs cmark-gfm's archives.** Debian ships them in
  `libcmark-gfm-dev` and `libcmark-gfm-extensions-dev`. The library's
  other uses need only the runtime packages (ADR-0009).
- **The project still compiles no C of its own.** The recipe compiles
  Lisp through ECL's C backend, as every ECL build does (M4 design §4).
- **The method record adds no reader conditional:** `src/ffi.lisp` finds
  CFFI's variable by name (M4 design §4).
- **The smoke program covers linked startup and rendering.** The whole
  native suite doesn't run as a linked program; the dynamic suites cover
  the rest (M4 design §9).
- **Static deployment on SBCL or CCL is out of scope** (M4 design §9).
- **Users get the recipe in M5's documentation.** Until then it lives in
  `tests/static/`, outside the project's `.asd`.
