# M2b native layer — implementation plan

- **Spec:** [2026-09-30-m2-native-layer-design.md](2026-09-30-m2-native-layer-design.md)
  (approved 2026-09-30), §3 and §5 to §11, with its amendments: findings
  14 to 21, the finish lock, the input guard (§5.6), holds and the restore
  hook (§5.3), deferred interrupts (§5.4), and the CCL start watchdog
  (§8.5)
- **Branch:** `m2b-native-layer`
- **Scope:** the dependencies; `/util`'s encoder; the new conditions;
  `/native-core`, `/ffi` and `/native`; the copier; the four entry points;
  the corpus, the four oracles and the crash guards; the input guard;
  `make check-native`; ADRs 0016 to 0019 and the documents for this
  slice.

## Brief for every task

Each task goes to one subagent, which works only on the files its task
owns. If another file needs changing, the agent reports it instead of
editing it.

- **Read first:** `AGENTS.md`, the global constraints in
  `.plans/progress.md`, the spec sections the task names, and the ADRs
  they cite.
- **Run builds and tests only through the container.** Batch commands into
  one call, e.g. `scripts/guix-env sh -c 'make check-purity && make
  check-native'`; each call takes seconds to start. `check-purity` runs
  the pure suite on SBCL, CCL and ECL; `check-native` (from Task 4) runs
  the native suite on SBCL.
- **TDD.** Write the task's tests first, run them, and watch them fail for
  the right reason. Only then implement.
- **Seen to fail.** Every check the task adds must fail under the mutations
  listed for it. Apply each mutation, watch the failure, revert, and report
  what failed and how. ASDF compares file dates to the second, so a source
  mutated, run and restored within a second keeps its mutated fasl, and
  the next run silently reuses it (Task 4 saw impossible results this
  way). Delete the project's fasls under `.guix-env/cache/common-lisp/`
  before every run of a mutation series, and before the final run.
- **Read cmark's behavior from `vendor/cmark-gfm`, never from memory.**
  Every C fact a test or comment relies on names its file and function.
- **The pure core's contract stands.** M1's and M2a's tests and the 28
  oracle fixtures are not edited to make new code pass. Tests may be added
  beside them.
- **No recursion over a tree's depth, or over a list's length,** in library
  code: loops over explicit stacks (ADR-0015). That includes the native
  walker, the copier and the output-bound walk.
- **Large values stay out of assertions.** Parachute keeps every result
  until the run ends: the assertion's closure, what it captured, and the
  values it compared. In M2a that held 515 MB, and Debian's SBCL ran out of
  heap. So:
  - build large data (corpus results, deep documents, megabyte strings) in
    a helper, or inside the asserted form, never in a `let` around `is`,
    `true` or `false`;
  - compare large values inside the form, `(true (string= (expected)
    (actual)))`, so the result holds a boolean;
  - a corpus test computes, in a helper, the list of examples that fail,
    and asserts that list is empty. It also asserts how many examples it
    compared, so a reader that returns nothing can't pass.
- **Assert on what was signalled:** `fail` with the exact condition type,
  then the slots that carry the meaning. A test that something was
  rejected *before* cmark ran also shows it with the monotonic counters.
- **Restore what a test changes,** in `unwind-protect`: a redefined
  function, a rebound variable, the published native state. After a test
  that resets the native state, the next call starts it up again.
- **The open counters are zero** after every native test that takes a
  failure path (spec §8.4), and at the end of the suite.
- **Lisp style:**
  - follow AGENTS.md's conventions;
  - no optimization `declaim`s;
  - `:import-from`, never `:use`, apart from `cl` and the primary
    package's re-exports;
  - tests reach internal helpers as `package::symbol`;
  - reader conditionals only in `/native` and in tests.
- **Don't commit.** The user commits.
- **Report:** files changed; the pure suite's test counts per Lisp and the
  native suite's; each suite's run time; the mutations and how each
  failed; anything found.

## Execution

The code tasks share one working tree, and both runners load every file of
their systems, so they run **one at a time**. The documents never load
Lisp, so they run alongside the first code task.

| Step | Task | Model | Alongside |
|------|------|-------|-----------|
| 1 | 1 Dependencies, the encoder and the conditions | Sonnet | 10 Documents (Opus) |
| 2 | 2 `/native-core`: constants, classification and discovery | Sonnet | |
| 3 | 3 `/native-core`: options, option bits and limits | Sonnet | |
| 4 | 4 `/ffi` and `/native`: startup, lifetimes, walking and rendering | Opus | |
| 5 | 5 Threads and saved images | Opus | |
| 6 | 6 The copier and `parse` | Opus | |
| 7 | 7 The renderers, the corpus and two oracles | Sonnet | |
| 8 | 8 The XML oracle | Opus | |
| 9 | 9 Output bounds and the crash guards | Opus | |
| 9b | 9b The input guard (added after Task 9) | Sonnet | Documents for 9b (Opus) |
| 10 | 11 Review and close-out | Opus review, fixes, then a second review | |

Tasks that run alongside each other share no files.

## Interfaces the tasks share

**Systems and files,** all in `cl-commonmark-gfm.asd`, `:serial t`,
`:license "BSD-3-Clause"`. Each task adds its own systems and files.

| System | Files | Task |
|--------|-------|------|
| `/util` | `src/util.lisp` | 1 |
| `/conditions` | `src/conditions.lisp` | 1 |
| `/native-core` | `src/native-core/package.lisp`, `constants.lisp`, `classify.lisp`, `discovery.lisp` | 2 |
| | `options.lisp`, `limits.lisp` | 3 |
| | `output-bounds.lisp` | 9 |
| | `guard.lisp` | 9b |
| `/ffi` | `src/ffi.lisp` | 4 |
| `/native` | `src/native/package.lisp`, `counters.lisp`, `document.lisp`, `walk.lisp`, `render.lisp`, `startup.lisp` | 4 |
| | `image.lisp` | 5 |
| | `copy.lisp` | 6 |
| | `output-bounds.lisp` | 9 |
| `cl-commonmark-gfm` | `src/api.lisp` | 6, 7 |
| `/tests` | adds `tests/native-core.lisp` after `conditions`, and `tests/corpus.lisp` after it; `deep` stays last | 2, 7 |
| `/native-tests` | `tests/native/package.lisp`, `helpers.lisp`, then one file per area | 4 |

The runners: `tests/run.lisp` (pure) and `tests/run-native.lisp` (Task 4).

**`cl-commonmark-gfm.util`** exports, besides `proper-list-p` (Task 1):
- `(char-utf8-octets char)`, moved from the URL helpers;
- `(utf8-length string)`: the octets STRING encodes to;
- `(encode-utf8 string octets)`: writes them into OCTETS, an
  `(unsigned-byte 8)` vector, from index 0, and returns the count;
- `(decode-utf8 octets &key start end)`: the string OCTETS encodes from
  START to END, with U+FFFD for each maximal subpart of an ill-formed
  sequence (spec §6.5; added in the review, for finding 19).

A lone surrogate encodes as U+FFFD everywhere.

**`cl-commonmark-gfm.conditions`** exports the spec §7.4 conditions
(Task 1). Their extra slots have initargs `:limit`, `:maximum`,
`:override`, `:paths`, `:expected-version` and `:found-version`, and the
readers `condition-limit`, `condition-maximum`, `condition-override`,
`condition-paths`, `condition-expected-version` and
`condition-found-version`.

**`cl-commonmark-gfm.native-core`** exports:
- **Task 2:**
  - the constants `+cmark-node-…+`, `+cmark-opt-…+` and the list enums,
    named after their C names, with `*cmark-header-constants*` mapping
    each C name to its value;
  - `*cmark-gfm-version*`, `"0.29.0.gfm.13"`, and `*extension-keywords*`,
    which lists `(:table :strikethrough :autolink :tagfilter :tasklist)`,
    the canonical order. Both are `defparameter`s: a `defconstant` of a
    string or a list breaks when a file is loaded again, since the new
    value isn't `eql` to the old;
  - `(classify-node type-code extension type-string)`;
  - `(resolve-cmark-libraries &key libraries environment os multiarch
    regular-file-p)`, which returns `(core extensions)`;
  - `*cmark-gfm-libraries*`.
- **Task 3:**
  - `(check-options entry-point operation options)`. ENTRY-POINT is
    `:parse`, `:html`, `:plaintext` or `:html-tree`, and OPERATION is the
    symbol conditions name. It returns a `checked-options`, read with
    `checked-profile`, `checked-extensions`, `checked-footnotes`,
    `checked-smart`, `checked-sourcepos`, `checked-softbreak`,
    `checked-unsafe-html`, `checked-width` and `checked-tree-options`;
  - `parse-option-bits`, `html-option-bits` and `plaintext-option-bits`,
    each of a `checked-options`;
  - `(document-attributes checked-options)`;
  - `*max-input-octets*`, `*max-nodes*` and `*max-output-octets*`;
  - `(effective-maximum symbol)`;
  - `(check-limit symbol value operation)`;
  - `(table-cell-bound string)`.
- **Task 9:** the per-node terms of the output bounds.
- **Task 9b:** `(footnote-entity-index string)`, the input guard's
  scanner.

**`cl-commonmark-gfm.ffi`** (Task 4) exports one function per C function of
spec §5.1, named by turning `_` into `-`: `cmark-parser-new`, and so on.

**`cl-commonmark-gfm.native`** is internal. Other systems and tests use:
- **Task 4:**
  - `(native-state)`: the published state, starting up first when none is
    published. It takes no hold;
  - `(with-native-state (state) &body body)`: runs BODY with STATE bound to
    that state, held until BODY exits, so closing refuses meanwhile
    (spec §5.3; added in the review, for finding 18). Every entry point
    parses inside one;
  - `(with-native-document (document string checked-options &key state)
    &body body)`. Given no STATE, it holds the published state itself;
  - `(walk-native function document)`, with `walk-ast`'s `:enter`,
    `:exit` and `:skip` protocol;
  - the node accessors, each `(native-… document node)`;
  - `(render-html document checked-options)`,
    `(render-plaintext document checked-options)` and
    `(render-xml document)`. The XML renderer uses the document's own
    parse bits;
  - for tests:
    - `reset-native-state` and `native-state-published-p`;
    - `native-open-counts`, a plist of `:parsers`, `:roots` and
      `:buffers`;
    - `native-created-counts`, a plist of `:parsers` and `:buffers`;
    - `native-startup-count`;
    - the internal condition `native-document-released`.
- **Task 6:** `(copy-native-tree document checked-options &optional
  operation)`.
- **Task 9:** `(html-output-bound document checked-options markdown
  &optional operation)`, where MARKDOWN is the string DOCUMENT was parsed
  from, and `(plaintext-output-bound document checked-options &optional
  operation)`.

OPERATION is the symbol conditions name, as in `check-options`. It
defaults to the function's own name; the entry points pass theirs.

**`cl-commonmark-gfm`** (Tasks 6 and 7): the four entry points, the
re-exports, and one internal helper every entry point calls before any
native call, `(check-input markdown checked-options operation)`. It
first checks all three limit bindings, then applies `*max-input-octets*`,
the table-cell bound and, with footnotes on, the input guard (Task 9b
changed its signature; the review added the binding checks).

**Test helpers** in `tests/native/helpers.lisp` (Task 4), for every later
task:
- `(with-redefined ((name function) …) &body body)`;
- `(open-counts-zero-p)`;
- `(created-parsers)` and `(created-buffers)`;
- `(fixture-path name)`;
- `(call-with-native-document string options function)`, which runs
  FUNCTION on a live document. The tests use it until the entry points
  exist.

The pure tests package exports its corpus reader (Task 7) and
`*oracle-cases*` for the native suite.

## Task 1: Dependencies, the encoder and the conditions

**Owns:**
- `ocicl.csv` and `cl-commonmark-gfm.asd`;
- `src/util.lisp` and `src/conditions.lisp`;
- `src/html-tree/url.lisp` and `src/html-tree/package.lisp`, for moving
  `char-utf8-octets`;
- `tests/package.lisp`, `tests/util.lisp` and `tests/conditions.lisp`;
- `tests/url.lisp`, for one new test: `href-encode` writes a lone
  surrogate as `%EF%BF%BD` (spec §6.5).

1. **Dependencies** (spec §3). In the container, add these to `ocicl.csv`
   with `ocicl install … </dev/null`:
   - CFFI and bordeaux-threads;
   - everything they load: alexandria, babel and trivial-features, then
     global-vars and trivial-garbage.

   Every new line carries a sha256 digest. Show that `cffi` and
   `bordeaux-threads` load on SBCL with the Makefile's
   `CL_SOURCE_REGISTRY`. No project system depends on them yet.
2. **The encoder** (spec §6.5), in `src/util.lisp`:
   - **`char-utf8-octets`** moves here unchanged, except that a lone
     surrogate (U+D800 to U+DFFF) encodes as U+FFFD, `EF BF BD`. One
     encoder, one rule; cmark never sees a surrogate, and an href holding
     one now reads `%EF%BF%BD`. `url.lisp` imports it.
   - **`utf8-length` and `encode-utf8`** loop over the string and write
     octets directly. They make no list per character: inputs reach
     256 MiB.
3. **The conditions** (spec §7.4), in `src/conditions.lisp`:
   - `invalid-option`, with `invalid-parse-option` and M1's
     `invalid-render-option` under it;
   - `resource-limit-exceeded`;
   - `native-error`, with its six subtypes.

   Every slot defaults to `nil`, and the report stays "operation: reason:
   datum", bounded as in M1. Each docstring says what signals it.

**Tests first:**
- **`tests/util.lisp`:**
  - each length boundary: U+7F and U+80, U+7FF and U+800, U+FFFF and
    U+10000, and U+10FFFF;
  - `#\Nul` as one zero octet;
  - a lone surrogate as `EF BF BD` on SBCL and ECL. On CCL, assert that
    `(code-char #xD800)` is `nil` (spec finding 11);
  - `utf8-length` agrees with `encode-utf8`'s count on a mixed string, and
    the vector holds the right octets;
  - the empty string.

  M1's `href-encode` tests pass unchanged.
- **`tests/conditions.lisp`:** each new condition's parents, with
  `subtypep`; each new reader, with and without its initarg; and the
  report of every new subtype.

**Mutations:**
- encode a surrogate as its own code point: the surrogate test fails on
  SBCL and ECL;
- move a boundary by one: a boundary test fails;
- put `invalid-render-option` directly under `commonmark-gfm-error`: the
  hierarchy test fails;
- drop a reader's initarg: its test fails.

**Verify:** `make check-help`, and `make check-purity` on all three
Lisps, with no CFFI package after the pure run.

## Task 2: `/native-core`: constants, classification and discovery

**Owns:**
- `cl-commonmark-gfm.asd`, for the `/native-core` system and the tests
  system's new file;
- `src/native-core/package.lisp`, `constants.lisp`, `classify.lisp` and
  `discovery.lisp`;
- `tests/package.lisp` and `tests/native-core.lisp`.

1. **The system** `cl-commonmark-gfm/native-core`, depending on
   conditions and util. It is pure: no CFFI, and no UIOP either.
   Everything from outside the image comes in as an argument.
2. **Constants** (spec §8.1):
   - a `defconstant` for each `cmark_node_type` enumerator but
     `CMARK_NODE_NONE`;
   - the option bits `SOURCEPOS`, `HARDBREAKS`, `NOBREAKS`,
     `VALIDATE_UTF8`, `SMART`, `FOOTNOTES` and `UNSAFE`;
   - `CMARK_BULLET_LIST`, `CMARK_ORDERED_LIST`, `CMARK_PERIOD_DELIM` and
     `CMARK_PAREN_DELIM`.

   `*cmark-header-constants*` maps each C name to its value.
3. **`classify-node`** (spec §6.2, ADR-0008). It returns a kind. For
   `:extension`, the copier sets `:type-name` and `:extension-name`.
4. **`resolve-cmark-libraries`** (ADR-0009). Its arguments:
   - LIBRARIES: the value of `*cmark-gfm-libraries*`;
   - ENVIRONMENT: the value of `CL_COMMONMARK_GFM_LIBS`, or `nil` when
     it's unset;
   - OS: `:linux` or `:macos`;
   - MULTIARCH: `"x86_64-linux-gnu"`, `"aarch64-linux-gnu"` or `nil`;
   - REGULAR-FILE-P: a function of one path string.

   It signals `native-library-not-found`, with `override` and `paths`.
   `*cmark-gfm-libraries*` is a `defvar`, `nil`, whose docstring gives
   the value's shape.

**Tests first,** in `tests/native-core.lisp`:
- **Header constants:**
  - read `vendor/cmark-gfm/src/cmark-gfm.h` as text, and evaluate its
    `#define`s and the `cmark_node_type`, `cmark_list_type` and
    `cmark_delim_type` enums. The reader handles hex and decimal literals,
    `|`, `<<`, names defined earlier, and implicit enum values;
  - every entry of `*cmark-header-constants*` must match;
  - every `cmark_node_type` enumerator but `NONE` must have an entry.
- **`classify-node`,** over synthetic inputs:
  - every core type code;
  - the four table type strings, strikethrough, and tasklist on an item;
  - `:extension` for tasklist on a node that isn't an item, for an unknown
    table type string, and for `:autolink`, `:tagfilter` and `:other`;
  - custom blocks and inlines signal `unsupported-extension-node`.
- **`resolve-cmark-libraries`,** over synthetic `regular-file-p`
  functions:
  - the special variable over the environment variable;
  - an empty-but-set environment variable;
  - malformed values of each: one path, three paths, a relative path;
  - a missing file, which is named;
  - the directory order;
  - a directory holding only one of the pair, skipped;
  - the multiarch and macOS filenames;
  - nothing found, listing every directory searched.

**Mutations:**
- change one constant: the header test fails, naming it;
- delete one node-type constant: the completeness test fails;
- classify tasklist on any node as `:task-item`: a classification test
  fails;
- pair a core from one directory with extensions from another: the skip
  test fails;
- prefer the environment over the special variable: its test fails;
- treat an empty environment variable as unset: its test fails.

**Verify:** `make check-purity` on all three Lisps.

## Task 3: `/native-core`: options, option bits and limits

**Owns:** `cl-commonmark-gfm.asd`; `src/native-core/package.lisp`,
`options.lisp` and `limits.lisp`; and `tests/package.lisp` and
`tests/native-core.lisp`, in new sections.

1. **Options** (spec §7.2, §7.3 and §6.3):
   - **`check-options`** resolves every option to its value or default.
     It signals what §7.2's "Which condition" says.
   - **The tree options of `:html-tree`:** `:softbreak`, `:raw-html`,
     `:link-policy` and `:document-wrapper` are known keys there. Their
     values are checked by the HTML tree's own checker (Task 7).
     `checked-tree-options` returns them as a plist, in the caller's
     order, repeats included.
   - **The bits** follow §7.3.
   - **`document-attributes`** follows §6.3's `:document` row.
2. **Limits** (spec §5.5):
   - **The three variables** and the hard caps. The variables'
     docstrings state the remaining risk (§5.5, §9).
   - **`effective-maximum`** returns the variable's value, or its hard cap
     when that is lower, and a second value: whether the cap applied. A
     value that isn't a non-negative integer signals a `type-error`.
   - **`check-limit`** signals `resource-limit-exceeded` when VALUE
     exceeds the effective maximum. It sets `datum`, `limit` and
     `maximum`, and its reason says when the hard cap applied.
   - **`table-cell-bound`** makes one pass over the string, and builds no
     list of lines.

**Tests first:**
- **Options, for each entry point:**
  - every key, and every bad value, with the condition each signals;
  - an odd-length list, an unknown key, and a key only another entry
    point takes (`:width` given to `parse`);
  - a repeated key, whose leftmost value wins, while a bad later value
    still signals;
  - a repeated or unknown extension;
  - each profile's defaults; `:profile :commonmark :footnotes t`;
    `:extensions nil`;
  - `:width` at 0, at 2,147,483,647, and one past it;
  - `checked-tree-options` keeping order and repeats.
- **Bits:** each bit of §7.3, against the constants, for each option that
  sets one, and the bits of the defaults.
- **Document attributes:**
  - each profile;
  - explicit extensions given out of order come back in canonical order;
  - `:options` with neither, either and both of `:footnotes` and
    `:smart`.
- **Limits:**
  - each default;
  - `effective-maximum` below, at and above each hard cap, and for
    `*max-nodes*`, which has none;
  - a negative, a non-integer and a `nil` binding signal `type-error`;
  - `check-limit` at the maximum passes, and one past it signals, with
    every slot set;
  - the reason when the cap applied.
- **The table-cell bound,** each against a number worked out by hand:
  - LF, CR and CRLF line ends;
  - blank lines of spaces and tabs;
  - container prefixes: `>`, and list-item indentation;
  - VT and FF;
  - several delimiter rows in one run, and a run whose widest candidate
    line isn't its first;
  - a line holding text, which isn't a candidate;
  - the empty string.

**Mutations:**
- swap `HARDBREAKS` and `NOBREAKS`: a bits test fails;
- let a repeated key's rightmost value win: its test fails;
- ignore a hard cap: an effective-maximum test fails;
- split lines at LF only: the CR tests fail;
- count `-` characters instead of runs of them: a bound test fails.

**Verify:** `make check-purity` on all three Lisps.

## Task 4: `/ffi` and `/native`: startup, lifetimes, walking and rendering

**Owns:**
- `cl-commonmark-gfm.asd`, for `/ffi`, `/native` and `/native-tests`;
- `src/ffi.lisp`;
- `src/native/package.lisp`, `counters.lisp`, `document.lisp`,
  `walk.lisp`, `render.lisp` and `startup.lisp`;
- `tests/native/package.lisp`, `helpers.lisp`, `startup.lisp`,
  `lifetimes.lisp`, `walk.lisp` and `render.lisp`;
- `tests/run-native.lisp`, `tests/run.lisp` (to share the reporting code)
  and `Makefile`.

1. **`/ffi`** (spec §5.1) depends on CFFI only. It has one
   `cffi:defcfun` per function, with the header's types. Strings come
   back as `:pointer`, never `:string`. There's no
   `define-foreign-library`: `/native` loads the libraries by path.
2. **`/native`** depends on native-core, ffi, ast, util, CFFI and
   bordeaux-threads.
   - **The state:** the two library objects `cffi:load-foreign-library`
     returns, the paths, the five extension pointers by keyword, and the
     allocator's `free`.
   - **Startup** (spec §5.2), run by `native-state` under the startup
     lock:
     - steps 1 to 9;
     - ECL's `:dffi` check is a reader conditional;
     - the OS and multiarch come from UIOP;
     - a failure in steps 3 to 8 closes what the attempt loaded,
       extensions first, and publishes nothing;
     - step 8's smoke parse runs through `with-native-document` with the
       unpublished state.
   - **`reset-native-state`** closes both libraries and clears the
     published state, under the startup lock. The tests and Task 5's save
     hooks use it.
   - **`with-native-document`** (spec §5.4) takes steps 1 to 6. It encodes
     with `utf8-length` and `encode-utf8` into
     `cffi:make-shareable-byte-vector`, pinned only for the
     `cmark_parser_feed` call. The document keeps its parse bits.
   - **The alive flag:** every node accessor checks it, and signals
     `native-document-released`, a subtype of `error` that isn't
     exported.
   - **Internal wrappers.** Each cmark call that can fail or return null
     gets an ordinary global function, called by name, so a test can
     redefine it: the version string, finding an extension, the parser's
     finish, and each render. A free and its counter update live in one
     function, so skipping the free also skips the count.
   - **Counters** (spec §5.4), under their own lock: open parsers, roots
     and buffers; parsers and buffers ever created; startups published.
   - **The walker** (spec §5.1) uses first-child, next and parent.
   - **The accessors** read type, type string, extension (a keyword, `nil`
     or `:other`), literal, URL, title, fence info, heading level, list
     type, delimiter, start and tightness, the four positions, the
     footnote definition, the table's columns and alignments, and the
     task's checked byte.
     - They decode strings with `cffi:foreign-string-to-lisp`, `:encoding
       :utf-8`.
     - A null string signals `native-parse-error`. `cmark_chunk_to_cstr`
       (`src/chunk.h`) never returns null on the kinds the accessors
       serve.
   - **Rendering** (spec §5.4) decodes the buffer, then frees it through
     the allocator's `free`, in `unwind-protect`.
3. **`cl-commonmark-gfm/native-tests`** depends on `/native`, `/tests`,
   Parachute and trivial-garbage. Its package is
   `cl-commonmark-gfm.native-tests`. Task 6 adds the primary system.
4. **The runner** (spec §8.5):
   - `tests/run-native.lisp` works like `tests/run.lisp`, minus the CFFI
     check, and fails unless the open counters are zero when it ends;
   - both runners load their shared reporting code from one file;
   - `tests/run.lisp` behaves as before. A failing test, no tests, a CFFI
     package and an escaped serious condition each still exit 1.
5. **The Makefile** (spec §8.5):
   - `NATIVE_LISPS ?= sbcl`;
   - `check-native` runs the native runner on each Lisp in it. SBCL gets
     `--dynamic-space-size 2048`, and every Lisp gets `check-purity`'s
     `CL_SOURCE_REGISTRY`;
   - `make test` becomes `check-purity check-fixtures check-native`;
   - `.PHONY` stays on one line, and the target gets its `## `
     description.

**Tests first,** in `tests/native/`:
- **Discovery, both ways** (spec §8.4). With `CL_COMMONMARK_GFM_LIBS` set,
  as in the container, the state's paths are the override's. Unset, as in
  CI, they come from the directory search. The test asserts whichever
  applies.
- **Startup:**
  - the version is the pin;
  - the five extension pointers are non-null and distinct;
  - after a reset, two calls raise the startup count by one.
- **Every startup condition** (spec §8.4), each after
  `reset-native-state`:
  - a bad override signals `native-library-not-found`, naming the path.
    One override names a missing file (step 2). Another names the real
    core and, for the extensions, a file that isn't a library (step 3),
    so the core loads and must be closed again;
  - a redefined version wrapper signals `native-abi-mismatch`, with both
    versions;
  - a find-extension wrapper redefined to return null signals
    `native-initialization-error`.

  After each, nothing is published, CFFI's list of loaded libraries holds
  neither library, and the next normal call starts up.
- **Lifetimes:**
  - a null root signals `native-parse-error`, and a null buffer
    `native-render-error`;
  - a non-local exit from the body;
  - every accessor on a document used after its scope signals
    `native-document-released`;
  - after each, the open counters are zero, and the created counters rose
    as expected.
- **ABI beliefs** (ADR-0008):
  - the allocator's three slots are non-null and distinct;
  - in `tests/fixtures/vocabulary.md`, the checked and unchecked task
    items read differently.
- **Walking:** over `vocabulary.md` under `:gfm`, the walker's `:enter`
  events give the same sequence of type strings as the elements of
  `tests/fixtures/vocabulary.xml`. `:skip` skips a subtree.
- **Rendering:** `render-xml` of `vocabulary.md`, parsed with `:sourcepos
  t` under `:gfm`, equals `vocabulary.xml` byte for byte. `render-html`
  and `render-plaintext` return non-empty strings, with the counters at
  zero after.
- **Collections:** parse and render loops, with
  `(trivial-garbage:gc :full t)` between iterations, give the same result
  every time.

**Mutations:**
- skip the root's free: the counters fail, and so does the runner's exit
  check;
- drop the alive check from one accessor: the use-after-release test
  fails;
- publish the state before the smoke parse: a startup-condition test finds
  state published;
- don't close the libraries after a failed attempt: CFFI's list still
  holds them, and the test fails;
- make discovery ignore `CL_COMMONMARK_GFM_LIBS`: the discovery test fails
  in the container;
- leave one test's document open: `tests/run-native.lisp` exits 1;
- empty the native suite: the runner reports no tests and exits 1.

**Verify:** `make check-help`, `make check-purity` (all three Lisps,
still with no CFFI package), and `make check-native`.

## Task 5: Threads and saved images

**Owns:** `cl-commonmark-gfm.asd`; `src/native/document.lisp` (the
finish lock) and `src/native/image.lisp`; `tests/native/threads.lisp` and
`tests/native/image.lisp`.

1. **The finish lock** (spec §5.4 step 4, §7.5, finding 14) is one
   bordeaux-threads lock for the process. It is held around the
   `cmark_parser_finish` call and nothing else, in §5.2's lock order.
2. **Save hooks** (spec §5.3), in `image.lisp`: a function on
   `sb-ext:*save-hooks*` and on `ccl:*save-exit-functions*` calls
   `reset-native-state`, behind reader conditionals. CCL's runs in M4.

**Tests first:**
- **The race** (spec §8.4, finding 14):
  - 8 threads, each rendering 40 times, through `with-native-document` and
    `render-html`;
  - half render a GFM document of about 140 KB, full of strikethroughs
    and autolinks; the other half a CommonMark document full of
    `a~_b_~c`;
  - every result must equal its sequential render.

  The probes behind finding 14 are in `.guix-env/tmp/thread-probe/`, if
  they still exist.
- **Concurrent startup:** after a reset, many threads make their first
  call at once. The startup count rises by one, and every thread gets the
  same state.
- **A saved image** (spec §8.4):
  - a child SBCL loads `/native`, parses and renders through its
    internals (`parse` arrives in Task 6), and saves an image with
    `sb-ext:save-lisp-and-die`;
  - a second child starts from that image, reports that nothing is
    published, then parses and renders;
  - both children inherit the parent's environment. The image goes in a
    temporary directory, which the test deletes.
- **Render stress** (ADR-0008): documents up to the default input limit,
  rendered repeatedly, give the same output every time, and leave the
  counters at zero.

**Mutations:**
- remove the finish lock: the race test fails;
- remove the startup lock, with a startup step slowed by a redefined
  wrapper: concurrent startup publishes more than once;
- remove the save hook: the second child finds state already published.

**Verify:** `make check-purity` and `make check-native`.

## Task 6: The copier and `parse`

**Owns:**
- `cl-commonmark-gfm.asd`: the primary system, which `/native-tests` now
  depends on;
- `src/native/copy.lisp` and `src/api.lisp`;
- `tests/native/package.lisp`, `copier.lisp`, `parse.lisp` and
  `limits.lisp`.

1. **`copy-native-tree`** (spec §6):
   - one `walk-native`, with a stack of frames that collect each node's
     children, building nodes bottom-up with `make-node`;
   - it counts nodes with `check-limit` against `*max-nodes*`;
   - attributes come from §6.3, positions from §6.4 and text from §6.5;
   - a cell's column past the table's column count signals
     `native-parse-error`. It can't happen under the pin.
2. **The primary system `cl-commonmark-gfm`** (spec §3):
   - it depends on `/native` and `/html-tree`;
   - its package is defined with `uiop:define-package`, and re-exports
     every exported symbol of `.conditions`, `.ast` and `.html-tree`,
     and the four variables of `.native-core`;
   - the `.asd`'s comment on the empty primary system goes. Check that
     ASDF still finds each slash-named system through the primary one.
3. **`parse`** (spec §7.1):
   - `check-type` on MARKDOWN, then `check-options`, then `check-input`,
     then `native-state`, then `with-native-document` and
     `copy-native-tree`;
   - `check-input` lives in `src/api.lisp`, for Task 7's renderers too;
   - the docstring states the options, the limits and the remaining risk.

**Tests first:**
- **The fixture ASTs** (spec §8.3, witness 4; an M1 hand-off). Parse each
  of the 28 cases in `tests/fixtures/html/cases` with the defaults. Each
  must equal its hand-built AST in `tests/oracle.lisp`. The comparison
  ignores source positions and the document's attributes, and merges
  adjacent `:text` nodes on both sides first.
- **Direct tests** (spec §8.3):
  - a reference's label as written, including one whose case differs from
    its definition's;
  - body cells' alignment;
  - the document's attributes, under each profile and option;
  - `:sourcepos nil`: no position anywhere.
- **Positions** (spec §6.4, §8.4):
  - columns count bytes;
  - a multi-line code span leaves later positions right;
  - a softbreak has none.
- **Text** (spec §6.5): non-ASCII text round-trips, and `#\Nul` and a lone
  surrogate become U+FFFD.
- **Limits through `parse`:**
  - an input at `*max-input-octets*` is accepted, and one octet more is
    rejected. Bind the variable small, and straddle a multi-byte
    character;
  - a padded table past the table-cell bound is rejected;
  - a document past `*max-nodes*` is rejected mid-copy;
  - the monotonic counters show the first two came before any parser.
    The open counters are zero after all three.
- **Option errors** create no parser.
- **The table-cell bound is sound** on crafted tables, padded and not, and
  on cmark's stress inputs. It is never below the `:table-cell` count of
  the parse.
- **ASTs outlive their document** (the plan's M2 exit). Parse, force a
  full collection, and parse other documents; the first AST still equals
  a fresh parse's.
- **Deep inputs** (spec §8.4): cmark's three stress inputs parse. Their
  node counts are checked against counts worked out from each input's
  shape.
- **The re-exports:** every exported symbol of the three packages, and the
  four variables, is external in `cl-commonmark-gfm` and `eq` to the
  original.
- **`parse` given a non-string** signals a `type-error`.

**Mutations:**
- drop the link title from the copy: the fixture comparison fails;
- edit one hand-built fixture AST: the fixture comparison fails;
- take a reference's label from its own literal: the label test fails;
- give alignment to header cells only: the body-cell test fails;
- parse without `CMARK_OPT_SOURCEPOS` when `:sourcepos t`: the code-span
  test fails;
- skip the table-cell check: the padded-table test sees a parser created,
  and fails;
- put `walk-native` back to plain recursion: the deep inputs exhaust
  SBCL's stack.

**Verify:** `make check-purity`, still with no CFFI package after the pure
run now that the primary system depends on CFFI, and `make check-native`.

## Task 7: The renderers, the corpus and two oracles

**Owns:**
- `cl-commonmark-gfm.asd`;
- `src/api.lisp`, for the three renderers;
- `src/html-tree/convert.lisp`, for the option checker only;
- `tests/package.lisp` and `tests/corpus.lisp` (pure);
- `tests/native/renderers.lisp`, `oracles.lisp` and `deep.lisp`.

1. **The renderers** (spec §7.1): `markdown->html`,
   `markdown->plaintext` and `markdown->html-tree`. Each runs
   `check-type`, `check-options` and `check-input`, then `native-state`,
   then `with-native-document`. Their docstrings state the options, the
   limits and the remaining risk.
2. **`markdown->html-tree`'s tree options** are checked before any native
   call, by the HTML tree's own checker, so their rules stay in one place
   (ADR-0012).
   - `check-options` in `convert.lisp` becomes
     `(check-tree-options options operation)`, and `ast->html-tree`
     passes its own name.
   - `src/api.lisp` imports that internal symbol by name, with a comment
     saying why.
   - M1's tests, which check the operation `ast->html-tree`, pass
     unchanged.
3. **The corpus reader** (spec §8.2), pure, in `tests/corpus.lisp`. It
   mirrors `get_tests` in `vendor/cmark-gfm/test/spec_tests.py`:
   - the fence lines, and `.` between the Markdown and the HTML;
   - `→` becomes a tab;
   - `disabled` examples are skipped, but keep their place in the
     numbering;
   - sections come from `#` headings.

   Each example gives its file, section, number, Markdown, expected HTML
   and options. The options are the file's base options, from §8.2's
   table, plus its fence-line names: `footnotes` sets `:footnotes t`, and
   any other name joins `:extensions`, which stays in canonical order with
   no repeats.

**Tests first:**
- **The corpus counts** (pure suite): 670, 26, 16, 30, 4 and 1 enabled
  examples, 747 in all. One example per file is checked field by field,
  including a tab and a fence line with two names.
- **cmark's expectations** (spec §8.3, witness 1). `markdown->html`, with
  `:unsafe-html t` and the example's options, reproduces the expected HTML
  byte for byte. That's every enabled example of the first four files but
  `extensions.txt` example 20, the `<IGNORE>`: 741 examples.
- **The HTML oracle** (spec §8.3, witness 2):
  - for all 747 examples, under each `:softbreak` value,
    `(html-tree->string (markdown->html-tree md …))` equals
    `(markdown->html md …)`;
  - on the examples whose parsed AST holds no `:html-block` or
    `:html-inline`, `:link-policy :unsafe` equals `:unsafe-html t`;
  - `*known-divergences*` lists each example that hits one of ADR-0014's
    two divergences, with its reason. The test requires the failures to
    be exactly that list, so a fix has to remove one from it.

  If an oracle finds a difference that isn't one of those divergences,
  don't change the copier or the converter. Report the examples, with
  both outputs for one of each kind.
- **The table-cell bound** is sound on every corpus example: never below
  the parse's `:table-cell` count.
- **Deep documents** (spec §8.4). cmark's three stress inputs give the
  same bytes through the tree path as through `markdown->html`.
- **The API** (spec §8.4):
  - every option through each entry point;
  - option errors create no parser;
  - non-ASCII text round-trips through every entry point;
  - a non-string signals a `type-error`.
- **Threads, through the entry points.** Concurrent `parse`,
  `markdown->html` and `markdown->html-tree` calls equal sequential ones.

**Mutations:**
- change one converter rule: the HTML oracle fails;
- flip one option bit in the mapping: cmark's expectations fail;
- stop turning `→` into a tab: the counts test still passes, but the
  field test and cmark's expectations fail;
- let `markdown->html-tree` check tree options after parsing: the "no
  parser" test fails.

**Verify:** `make check-purity` and `make check-native`.

## Task 8: The XML oracle

**Owns:** `cl-commonmark-gfm.asd` and `tests/native/xml.lisp`.

The test-only writer (spec §8.3, witness 3; chez ADR-0010) prints an AST in
cmark's XML. It is written against `src/xml.c` (`S_render_node`,
`escape_xml`, and `MAX_INDENT`, which caps indentation at 40 spaces) and
the extensions' `xml_attr` functions (`extensions/table.c` and
`tasklist.c`). It follows finding 13's three rules.

**Tests first:**
- **All 747 enabled examples.** Inside one `with-native-document`, parsed
  with the example's options and `:sourcepos t`, the writer's output for
  `copy-native-tree` equals `render-xml`'s.
- **The guard.** Change one attribute of a copied AST, such as a heading's
  level, and the comparison must report a difference.
- **The second witness.** The writer's output for `vocabulary.md`, parsed
  with `:sourcepos t` under `:gfm`, equals `tests/fixtures/vocabulary.xml`.
- **Deep nesting.** 25 nested block quotes, past the indentation cap,
  compare equal.

**Mutations:**
- drop the indentation cap: the deep-nesting test fails;
- print `align` on body cells: the corpus comparison fails;
- copy every ordered list's delimiter as `:period` in the copier: the
  corpus comparison fails. Dropping the attribute outright fails
  `make-node`'s list rule first, before any oracle runs.

**Verify:** `make check-native`.

## Task 9: Output bounds and the crash guards

**Owns:**
- `cl-commonmark-gfm.asd`;
- `src/native-core/output-bounds.lisp` and `src/native/output-bounds.lisp`;
- `src/api.lisp`, for the output check in `markdown->html` and
  `markdown->plaintext`;
- `tests/native-core.lisp`, in a new section, and
  `tests/native/limits.lisp`.

1. **The per-node terms** (spec §5.5), pure, in `/native-core`. They are
   read off `src/html.c` (`S_render_node`, `S_put_footnote_backref`),
   `src/plaintext.c`, `src/render.c` and the extensions' renderers. Each
   constant names the function it comes from.
2. **The walk,** in `/native`: `html-output-bound` and
   `plaintext-output-bound`, one `walk-native` each. The plaintext walk
   keeps a stack of line prefixes.
3. **The check.** `markdown->html` and `markdown->plaintext` apply
   `check-limit` to `*max-output-octets*` after parsing and before
   rendering.

**Tests first:**
- **Each per-node term** (pure suite), against a value worked out by hand
  from the C source.
- **Rejection** (spec §8.4): crafted inputs for each source of blowup,
  under small bindings of the limits:
  - padded tables;
  - footnote references;
  - escaped quotes;
  - reference-link expansion;
  - plaintext prefixes from nested lists with lazy lines.

  Each signals `resource-limit-exceeded`. The monotonic counters show
  when: before any parser for the input and table-cell limits, and before
  any buffer for the output limit.
- **Soundness** (spec §8.4). Below the limits, neither output bound is
  ever below the UTF-8 length of what was rendered:
  - on the crafted inputs, and on cmark's stress inputs;
  - on every corpus example, under each option set the HTML oracle uses;
  - for plaintext, at `:width` 0 and 20.
- **Deep documents still fit** the default limits through every entry
  point.

**Mutations:**
- drop the footnote reference's repeated label from the HTML term:
  soundness fails;
- drop the line prefix from the plaintext term: soundness fails;
- skip the output check: the rejection test sees a buffer created, and
  fails.

**Verify:** `make check-purity` and `make check-native`.

## Task 9b: The input guard

Added on 2026-10-01, after Task 9 found cmark's footnote-entity bug (spec
finding 16). **Owns:**
- `cl-commonmark-gfm.asd`;
- `src/conditions.lisp`, for `unsupported-input`;
- `src/native-core/package.lisp` and `src/native-core/guard.lisp` (new);
- `src/api.lisp`, for `check-input` and the docstrings;
- `tests/package.lisp`, `tests/conditions.lisp` and `tests/native-core.lisp`
  (a new section);
- `tests/native/guard.lisp` (new).

1. **The condition** `unsupported-input` (spec §7.4) is a subtype of
   `commonmark-gfm-error`, not of `native-error`, and is exported.
2. **The scanner** (spec §5.6), pure, in `/native-core`:
   `(footnote-entity-index string)` returns the index of the first `[`
   immediately followed by an entity that decodes to `^`, or `nil`. It
   matches `houdini_unescape_ent`'s grammar exactly, and makes one pass.
3. **`check-input`** becomes `(check-input markdown checked-options
   operation)`. After the two limits, when `checked-footnotes` is true, it
   signals `unsupported-input` for a match. The datum is the index, and the
   reason names the pattern and finding 16. Every entry point passes its
   checked options, and the docstrings say what's rejected and why.

**Tests first:**
- **The scanner** (pure suite):
  - each form: `&#94;`, `&#094;`, `&#00000094;`, `&#x5e;`, `&#X5E;`,
    `&#x0000005E;` and `&Hat;`, each right after a `[`;
  - the near misses: 9 digits, a missing `;`, `&hat;`, `&#95;`, `&#x;`, a
    space after the `[`, and no `[` at all;
  - the first of two matches, and the index returned.
- **The condition** (pure suite): its parents, and its report.
- **Every entry point** (native suite):
  - each form, under the default options, signals `unsupported-input`,
    with no parser created;
  - the near misses parse;
  - with `:footnotes nil`, each form parses, and `markdown->html` renders
    the entity as text.

  Keep every label short: without the guard, a long one can fault the test
  process.

**Mutations:**
- don't call the guard: the native rejection tests fail;
- accept 9 digits: a near-miss test fails;
- match `&hat;` too: a near-miss test fails;
- run the guard with footnotes off: the footnotes-off test fails.

**Verify:** `make check-purity` and `make check-native`.

## Task 10: Documents

Runs alongside Task 1. **Owns:**
- `.plans/decisions/0016-three-limits-keep-cmark-from-aborting.md`,
  `0017-public-api-and-how-it-runs.md` and
  `0018-copying-and-checking-the-tree.md`, all new;
- the status lines of ADRs 0005, 0011, 0013 and 0014, and ADR-0013's
  steps table;
- `.plans/cl-commonmark-gfm.org` and `.plans/progress.md`.

1. **Three ADRs** in ADR-0015's format. Each links to the spec's
   sections rather than restating their rules (spec D17).
   - **ADR-0016, the three limits** (§5.5):
     - *context:* findings 1 to 4;
     - *rejected:* no limits and a documented risk; a depth limit (see
       ADR-0015);
     - *consequences:* callers bind the variables for larger inputs; the
       hard caps; the remaining risk.
   - **ADR-0017, the public API and how it runs** (§5.2 to §5.4, §7):
     - *decisions:* the entry points, the options and their per-function
       defaults (D14), the conditions and the re-exports; startup on
       first use, under a lock (D11); the finish lock (finding 14); the
       Lisps' own save hooks (D12); the alive flag (D13);
     - *rejected:*
       - every cmark option, since the HTML tree has nothing like the
         three HTML-only ones (D3);
       - UIOP's image hooks, which a direct save skips (finding 12);
       - running parses in parallel without a lock, which finding 14's
         probes show is wrong.
   - **ADR-0018, copying and checking the tree** (§6, §8.2, §8.3):
     - *decisions:* every kind but `:extension` (D1); labels from the
       parent definition (D15); positions only with `SOURCEPOS`; the
       encoder's U+FFFD; the four witnesses and the corpus (D4);
     - *rejected:* the plan's thin slice (D1); leaving the XML oracle to
       M3 (D4).
2. **Status lines,** naming the amending ADR (spec §10):
   - ADR-0005 finding 2: after parsing, a reference's literal is its
     number (ADR-0018);
   - ADR-0011: the whole corpus runs in M2, with cmark's expectations and
     its XML as further witnesses (ADR-0018);
   - ADR-0013: its steps table gets the native suite and the full oracle
     in M2;
   - ADR-0014: its hand-offs to M2 are settled in M2b (ADR-0018).
3. **The plan** (spec §10):
   - the systems table gains `/native-core` and `/native-tests`;
   - the ABI rule: option bitsets are `int`, as the header declares them;
   - the API sketch, the ownership protocol's example, and the conditions
     table follow spec §7;
   - the Tests section follows spec §8;
   - risk rows: cmark aborting or running out of memory (ADR-0016), and
     parses racing in cmark's global tables (ADR-0017);
   - decision-log entries 22 to 24, for ADRs 0016 to 0018.
4. **`progress.md`:**
   - the M2 row becomes "in progress: M2b". M2a merged on 2026-09-30, as
     PR #4;
   - the M2b checklist becomes this plan's tasks, one line each, with the
     plan linked beside the spec;
   - three new global constraints:
     - no input reaches cmark past the three limits (ADR-0016);
     - every native suite ends with the open counters at zero (ADR-0008);
     - tests keep large values out of assertions, since Parachute keeps
       every result until the run ends.

**Verify:** no ADR states a rule the spec doesn't, and every link
resolves.

## Task 11: Review and close-out

1. **In the container:** `make check-help`, `make deps`, `make test` and
   `make check-guix`, all green.
2. **Opus review** of the combined diff, against spec §3 and §5 to §11 and
   this plan. Fix what it finds, sending mechanical fixes to Sonnet.
   **Then a second review** of the fixes, since a fix round can break what
   the first review passed.
3. **The local CI run, before any commit.** M2a's heap failure surfaced
   only after its PR was open. Copy the working tree, with its untracked
   files and `vendor/cmark-gfm`, into `debian:trixie` under Docker. Run
   `ci/install-toolchain.sh`, then every workflow step in order, with no
   override set.
   - Check each step's exit status, and never pipe through `tail`.
   - Note the native suite's time against the job's 20-minute timeout.
4. **Close-out** in `progress.md`:
   - the tasks done, and the test counts per Lisp and per suite;
   - the run times, the mutations seen, and anything found;
   - tick the M1 hand-offs this slice settles: the footnote divergences,
     the labels as written, and the fixture ASTs.
5. **Ask the user** to commit and open the PR. Its CI check will fail;
   confirm the failure is the billing refusal.
6. **After the commit, the local CI proof,** as for M1 and M2a:
   - clone the commit, with its submodules, into `debian:trixie`, and run
     the steps again;
   - then flip one byte of a fixture `.html`, and see `make test` fail.

   Record both in `progress.md`, and push that as a follow-up commit.

**M2b is done when** `make test` is green: the pure suite on SBCL, CCL and
ECL, and the native suite on SBCL. It must pass in the container and in the
local `debian:trixie` run. The open counters must be zero after every
native suite, the oracles must pass over the whole corpus, and every check
must have been seen to fail. The GitHub run waits for October.
