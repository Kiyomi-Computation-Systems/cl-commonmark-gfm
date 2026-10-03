# M3 unknown extensions, version probes and property testing — implementation plan

- **Spec:**
  [2026-10-02-m3-extensions-versions-properties-design.md](2026-10-02-m3-extensions-versions-properties-design.md)
  (approved 2026-10-02)
- **Branch:** `m3-extensions-versions-properties`
- **Scope:**
  - the version cross-check;
  - the unknown-extension tests;
  - the property-testing spike: its harness, our contender, check-it, the
    five properties and the benchmark;
  - ADR-0020, and the integration or removal that follows it;
  - the documents for this slice.

## Brief for every task

Each task goes to one subagent, which works only on the files its task
owns. If another file needs changing, the agent reports it instead of
editing it.

- **Read first:**
  - `AGENTS.md`;
  - the global constraints in `.plans/progress.md`;
  - the spec sections the task names, and the ADRs they cite.
- **Run builds and tests only through the container.** Batch commands into
  one call, e.g. `scripts/guix-env sh -c 'make check-purity && make
  check-native'`; each call takes seconds to start.
  - `check-purity` runs the pure suite on SBCL, CCL and ECL.
  - `check-native` runs the native suite on SBCL.
  - The spike has its own runner, `tests/spike/run.lisp` (Task 3).
- **TDD, red first.** Write the task's tests first and run them. The
  report shows each new test failing, with its output, before any
  implementation exists. Then implement.
- **Seen to fail.** Every check the task adds must fail under the
  mutations listed for it:
  - apply each mutation, watch the failure, revert;
  - report what failed and how;
  - delete the fasl cache, `.guix-env/cache/common-lisp/`, before every
    run of a mutation series, the restoring run and the final run included
    (global constraint);
  - after a series, `git diff --stat src/` shows only the task's own
    changes.
- **Read cmark's behavior from `vendor/cmark-gfm`, never from memory.**
  Every C fact a test or comment relies on names its file and function.
- **Existing tests stand.** M1's and M2's tests, and the 28 oracle
  fixtures, are never edited to make new code pass. New tests go beside
  them.
- **Large values stay out of assertions** (global constraint). A property
  run computes its summary in a helper, and asserts on the summary only.
  No generated input is captured by an assertion's closure.
- **Assert on what was signalled.** Use `fail` with the exact condition
  type, then check the slots that carry the meaning.
- **Restore what a test changes,** in `unwind-protect`: a redefined
  function, a rebound variable, a native extension.
- **The open counters are zero** after every native test, and at the end
  of every suite and every spike run.
- **ocicl:** only Task 6 installs anything, from the repository root,
  with stdin from `/dev/null`. After an install, `git diff ocicl.csv`
  shows exactly the new rows, and `ocicl/` holds nothing else new.
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
  - the test counts per suite, per Lisp, and each suite's run time;
  - the mutations, and how each failed;
  - anything found.

## Execution

The code tasks share one working tree, so they run **one at a time**. The
documents never load Lisp, so they run alongside a code task.

| Step | Task | Model | Alongside |
|------|------|-------|-----------|
| 1 | 1 The version cross-check | Sonnet | 10 Documents, part 1 (Opus) |
| 2 | 2 Unknown extensions | Sonnet | |
| 3 | 3 The spike's harness, our contender and the UTF-8 property | Opus | |
| 4 | 4 The bounds and clean-outcome properties | Sonnet | |
| 5 | 5 The oracle properties and the divergences | Opus | |
| 6 | 6 check-it, the second contender | Sonnet | |
| 7 | 7 The benchmark | Sonnet | |
| 7b | Fixes for real bugs the spike finds, if any | per bug | |
| 8 | 8 ADR-0020, then the user confirms the decision | Opus | |
| 9 | 9 Integration, or removal | Sonnet | 10 Documents, part 2 (Opus) |
| 10 | 11 Review and close-out | Opus review, fixes, then a second review | |

Tasks that run alongside each other share no files.

## Interfaces the tasks share

**Files and systems,** in `cl-commonmark-gfm.asd`, `:serial t`:

| System | Files | Task |
|--------|-------|------|
| `/native-core` | adds `src/native-core/version.lisp` after `constants.lisp` | 1 |
| `/native-tests` | adds `tests/native/extensions.lisp` after `copier.lisp` | 2 |
| `/spike` (new, pure) | `tests/spike/package.lisp`, `random.lisp`, `generators.lisp`, `shrink.lisp`, `harness.lisp`, `utf8-property.lisp`, `self-tests.lisp` | 3 |
| | `check-it.lisp` | 6 |
| `/spike-native` (new) | `tests/spike/native-properties.lisp` | 4 |
| | `divergences.lisp`, `oracle-properties.lisp` | 5 |

- **`/spike`** depends on `/util` and `/tests`, for the corpus reader. From
  Task 6 it also depends on check-it.
- **`/spike-native`** depends on `/spike` and `/native-tests`.
- **The spike's runner,** `tests/spike/run.lisp`, loads one of the two
  systems and runs what its environment asks for. No `make` target runs
  the spike, and `make test` doesn't load it.

**`cl-commonmark-gfm.native-core`** exports, from Task 1:
- `(version-number string)`, which turns `"M.m.p.gfm.N"` into `(M << 24) |
  (m << 16) | (p << 8) | N`;
- `(number-version integer)`, the inverse.

Each component is 0 to 255. A malformed string, or a number outside 0 to
#xFFFFFFFF, signals an `error` that names it.

**`cl-commonmark-gfm.ffi`** exports `cmark-version` (Task 1).

**The spike's package, `cl-commonmark-gfm.spike`** (Task 3):
- **A property** is a function of an input and an options plist. It
  returns one outcome:
  - `:pass` or `:fail`;
  - `:guard`, when the input guard rejected the input;
  - `:excused-repeat` or `:excused-dropped`, when spec §6.4 excuses a
    difference.

  A second value carries a short detail: a string, never the input.
- **A generator** is a keyword:
  - `:syntax-soup` and `:corpus-splices`, which give a string and an
    options plist;
  - `:octets`, which gives an octet vector, for the UTF-8 property.
- **A contender** is `:own` or `:check-it`. It implements two generic
  functions:
  - `(contender-source contender generator seed)`, which returns a
    function of no arguments that yields the next case, as two values:
    the input and its options;
  - `(contender-shrink contender generator input still-fails-p)`, which
    returns the smallest failing input it finds.
- **`(run-property property &key contender generator seed cases)`**
  returns a summary plist:
  - `:property`, `:contender`, `:generator`, `:seed` and `:cases`;
  - `:passed`, `:failed`, `:guard`, and `:excused`, an alist of kind and
    count;
  - `:first-failure`: the shrunk input, its detail, and the original
    input's length;
  - `:seconds`.
- **The runner** reads these environment variables:
  - `SPIKE_PROPERTIES` and `SPIKE_CONTENDER`;
  - `SPIKE_GENERATOR`, `SPIKE_SEED` and `SPIKE_CASES`;
  - `SPIKE_SELF_TEST`.

  It prints one summary line per property, and the first failure in full.
  It exits non-zero when any property failed.

## Task 1: The version cross-check

Spec §5; M3 findings 1 and 2. **Owns:**
- `src/native-core/version.lisp` (new), `src/native-core/package.lisp` and
  `cl-commonmark-gfm.asd`;
- `src/ffi.lisp`;
- `src/native/startup.lisp` and `src/native/package.lisp`;
- `tests/native-core.lisp`, `tests/package.lisp`,
  `tests/native/startup.lisp` and `tests/native/package.lisp`.

1. **`version-number` and `number-version`,** pure, in `/native-core`
   (Interfaces).
2. **`cmark_version`** in `/ffi`, returning `:int`.
3. **Startup's step 4** (`check-version`):
   - after the string check, call a new wrapper, `%version-number`. Like
     `%version-string`, it is declaimed `notinline` and calls cmark with
     interrupts deferred;
   - when the number differs from `(version-number *cmark-gfm-version*)`,
     signal `native-abi-mismatch`:
     - `:expected-version` is `*cmark-gfm-version*`;
     - `:found-version` is `(number-version found)`;
     - the reason names both versions and both numbers, in hex
       (`#x001D000D`);
   - an error inside the wrapper is handled as step 4's other errors
     already are.

**Tests first:**
- **Pure** (`tests/native-core.lisp`, all three Lisps):
  - `(version-number "0.29.0.gfm.13")` is `#x001D000D`;
  - `(number-version #x001D000D)` is `"0.29.0.gfm.13"`;
  - round trips for `"0.0.0.gfm.0"`, `"1.2.3.gfm.4"` and
    `"255.255.255.gfm.255"`;
  - each of these signals: `"0.29.0"`, `"0.29.0.gfm"`, `"a.29.0.gfm.13"`,
    `"0.256.0.gfm.1"`, `""` and `"0.29.0.gfm.13 "`; so do `-1` and
    `#x100000000` for `number-version`.
- **Native** (`tests/native/startup.lisp`), with `with-redefined` as for
  the string:
  - a wrapper returning `#x001D000E` signals `native-abi-mismatch`, with
    expected `"0.29.0.gfm.13"`, found `"0.29.0.gfm.14"`, and both numbers
    in the reason;
  - a wrapper that signals an error makes startup signal
    `native-abi-mismatch`;
  - the open counters are zero after each test.

**Mutations:**
- remove the number comparison: the native mismatch test fails;
- shift the minor version by 8, not 16: the pure tests fail;
- drop the gfm component in `number-version`: the round trips fail.

**Verify:** `make check-purity` on all three Lisps, and `make
check-native`.

## Task 2: Unknown extensions

Spec §4; M3 findings 3 and 4. **Owns:**
- `tests/native/extensions.lisp` (new);
- `cl-commonmark-gfm.asd`, for that file;
- `tests/native/package.lisp`, for any import.

**Reference:** the probe that established M3 finding 3,
`.guix-env/tmp/m3-probes/inject.lisp`, a throwaway script. Read it; don't
reuse it.

1. **Test-only bindings,** with `cffi:defcfun` in the native tests'
   package, never in `/ffi`:
   - `cmark_syntax_extension_new`, `cmark_syntax_extension_free` and
     `cmark_syntax_extension_add_node`;
   - `cmark_node_new` and `cmark_node_new_with_ext`;
   - `cmark_node_set_syntax_extension` and `cmark_node_append_child`.

   Each docstring quotes the C declaration and its header,
   `src/cmark-gfm-extension_api.h` or `src/cmark-gfm.h`.
2. **`call-with-unknown-extension`** makes an extension named
   `"m3-unknown"`, and calls a function with it. In `unwind-protect`, after
   the function returns, it frees the extension with
   `cmark_syntax_extension_free` and the default allocator. The function
   releases its document before returning.
3. **New node types** come from `cmark_syntax_extension_add_node`, one
   block type and one inline type per process, cached in two `defvar`s
   (M3 finding 4).
4. **The tests** of spec §4.3, built on `call-with-native-document`:
   1. a paragraph given the extension is copied as `:extension`, with
      `:type-name` `"paragraph"`, `:extension-name` `nil`, its three
      children, and its position;
   2. a node of the new block type, appended to the document, is copied as
      `:extension` named `"<unknown>"`, with no position and no children;
      a node of the new inline type, appended to a paragraph, is that
      paragraph's last child in the copy, after the text before it;
   3. a `CMARK_NODE_CUSTOM_BLOCK` appended to the document, and a
      `CMARK_NODE_CUSTOM_INLINE` appended to a paragraph, each make the
      copier signal `unsupported-extension-node`;
   4. `html-output-bound` and `plaintext-output-bound` each signal
      `unsupported-extension-node` for the paragraph of test 1;
   5. `ast->html-tree` signals `unsupported-extension-node` on test 1's
      copy;
   6. the open counters are zero after each test.

**Mutations** (spec §7), each in library code, then reverted:
- the copier skips an `:extension` node's children: test 1 fails;
- the copier records `(princ-to-string (native-type …))` as `:type-name`:
  tests 1 and 2 fail;
- `classify-node` returns `:paragraph` for `:other`: test 1 fails, and so
  does the pure classification test;
- the output-bound walks count an unknown node as zero octets: test 4
  fails;
- `classify-node` returns `:extension` for a custom node: test 3 fails.

**Verify:** `make check-native`.

## Task 3: The spike's harness, our contender and the UTF-8 property

Spec §6.1 to §6.3; M3 finding 5. **Owns:**
- `tests/spike/package.lisp`, `random.lisp`, `generators.lisp`,
  `shrink.lisp`, `harness.lisp`, `utf8-property.lisp`, `self-tests.lisp`
  and `run.lisp`, all new;
- `cl-commonmark-gfm.asd`, for the `/spike` system.

1. **`random.lisp`:**
   - a splitmix64 stream, from an integer seed, in 64-bit modular
     arithmetic;
   - `(draw-below stream n)`, and a weighted choice over a list of
     `(weight . value)`.

   No `cl:random` anywhere in our contender.
2. **`generators.lisp`,** spec §6.2:
   - **syntax soup:** strings of 0 to 400 characters from a weighted
     alphabet. It holds:
     - the ASCII punctuation;
     - digits, letters, space and tab;
     - `#\Newline`, `#\Return` and `#\Nul`;
     - `é`, `日` and `😀`, of two, three and four octets;
     - the fragments `[^`, `]:`, `|---|`, `&#94;`, `&amp;`, `<div>`,
       `` ``` `` and `- [ ] `;
   - **corpus splices:** 1 to 20 lines drawn from the corpus examples'
     Markdown, joined with `#\Newline`. One case in four changes one
     character to a syntax-soup character;
   - **options:** one of the option sets M2b's HTML oracle compares. Read
     them in `tests/native/oracles.lisp` and the corpus reader, then write
     them out as plists in `generators.lisp`, so the pure system never
     loads native code;
   - **octets:** vectors of 0 to 64 octets. Half are random bytes; half
     mix valid UTF-8 sequences with truncated and overlong ones.
3. **`shrink.lisp`:** delta debugging over a string, deterministic.
   - It removes runs of lines, then runs of characters, halving the run
     size each time, while `still-fails-p` holds.
   - It stops after 2,000 calls of `still-fails-p`.
   - An octet vector shrinks the same way, octet by octet.
4. **`harness.lisp`:** `run-property` and the two generic functions
   (Interfaces), with the `:own` methods.
   - Each case runs inside `handler-case`. A signalled condition that the
     property doesn't expect is a `:fail`, whose detail is the
     condition's type and message, cut to 200 characters.
   - It shrinks only the first failure.
5. **`utf8-property.lisp`,** property 5, pure:
   - `decode-utf8` returns on every vector;
   - decoding, encoding the result and decoding again equals the first
     decoding;
   - a string with no lone surrogate survives `encode-utf8` then
     `decode-utf8`.
6. **`run.lisp`:** the runner (Interfaces). With `SPIKE_SELF_TEST` set,
   it runs `self-tests.lisp` through Parachute's quiet reporter instead.

**Tests first** (`self-tests.lisp`, on all three Lisps):
- **splitmix64's known answers:** seed 0 gives `#xE220A8397B1DCDAF`,
  `#x6E789E6AA1B965F4` and `#x06C45D188009454F`, in that order;
- **the generators:**
  - the same seed gives the same first 100 cases on every Lisp: compare a
    checksum of their octets, recorded in the test;
  - every case stays within its size bounds;
  - syntax soup draws only from its alphabet;
- **the shrinker:**
  - for "fails when the input contains `*a*`", a 400-character failing
    input shrinks to exactly `"*a*"`;
  - for "fails when the input has three lines", the result has exactly
    three empty lines;
- **the harness:**
  - a property that fails on every third case reports one third of the
    cases as failed;
  - a property that returns `:excused-repeat` is counted under that kind;
  - an unexpected condition counts as a failure, and its detail names the
    condition's type.

**Mutations:**
- change splitmix64's first multiplier: the known answers fail;
- stop the shrinker after its first pass: the `*a*` test fails;
- count an excuse as a pass: the harness test fails.

**Verify:**
- the self tests on SBCL, CCL and ECL;
- property 5 with `:own`, 10,000 cases, on each Lisp;
- in the report: the cases per second for each Lisp.

## Task 4: The bounds and clean-outcome properties

Spec §6.3, properties 3 and 4. **Owns:**
- `tests/spike/native-properties.lisp` (new);
- `cl-commonmark-gfm.asd`, for the `/spike-native` system.

1. **Property 3, the bounds:**
   - `html-output-bound` is at least the octets `render-html` writes, for
     the same document and options;
   - so is `plaintext-output-bound`, against `render-plaintext`;
   - `table-cell-bound` of the input is at least the count of
     `:table-cell` nodes in `parse`'s AST.

   An input the guard rejects is `:guard`.
2. **Property 4, clean outcomes:**
   - `parse`, `markdown->html`, `markdown->plaintext` and
     `markdown->html-tree` each return, or signal `unsupported-input`
     (`:guard`). Anything else is `:fail`;
   - the open counters are zero after the case;
   - the AST holds no foreign pointer: a walk finds no `cffi:pointerp`
     value in any attribute;
   - a second `parse` gives a `node=` AST;
   - a full GC, `(trivial-garbage:gc :full t)`, runs every 100 cases.

**Tests first,** in the spike's self tests, on crafted inputs:
- a pipe table with a short row passes property 3;
- a footnote reference passes property 4;
- `x [&#94;a]` under `:gfm` gives `:guard`;
- property 3 fails when `html-output-bound` is redefined to return 0,
  with `with-redefined`.

**Mutations:** the property-3 test above is its own mutation. In
addition, make property 4 skip its counter check while a test leaks a
parser on purpose: the test fails.

**Verify:** both properties with `:own`, 10,000 cases per generator, on
SBCL. Report each one's cases per second, its failures with their shrunk
inputs, and its guard counts.

## Task 5: The oracle properties and the divergences

Spec §6.3, properties 1 and 2, and §6.4; M3 finding 6. **Owns:**
`tests/spike/divergences.lisp` and `oracle-properties.lisp`, both new.

1. **Property 1, the HTML oracle.** It compares as
   `the-html-oracle-matches-every-example-but-the-known-divergences` does
   (`tests/native/oracles.lisp`), reusing its helpers, under the case's
   options.
2. **Property 2, the XML oracle.** `ast->cmark-xml` of `parse` with
   `:sourcepos t` equals `render-xml` of the same input
   (`tests/native/xml.lisp`).
3. **The excuses** (spec §6.4), in `divergences.lisp`:
   - **`:excused-repeat`** needs both:
     - the AST holds a repeat reference inside a definition that comes, in
       the source, before a body reference with the same label;
     - the outputs are equal once the repeat numbers in `fnref-…` ids,
       and in the backrefs' `href`s to them, are replaced by one
       placeholder.
   - **`:excused-dropped`:** the outputs are equal once cmark's footnote
     items are removed wherever every backref points at no `id` in
     cmark's output.

   Read cmark's footnote markup from `src/html.c` and
   `src/footnotes.c`, not from memory.

**Tests first,** on the two pinned inputs of
`repeat-references-counted-in-tree-order-still-diverges` and
`a-definition-referenced-only-from-a-dropped-definition-still-diverges`:
- each is excused, as its own kind;
- either pin's tree HTML with one other byte changed is a `:fail`;
- a mismatch that the repeat normalization would hide, but with no
  in-definition repeat reference in the AST, is a `:fail`;
- property 2 passes on `vocabulary.md`, and fails when
  `copied-sourcepos` is redefined to drop end positions.

**Mutations:**
- make `:excused-repeat` skip its AST check: the third test fails;
- make the normalization replace every number: the second test fails.

**Verify:** both properties with `:own`, 10,000 cases per generator, on
SBCL. Report the excuse counts, and every unexcused failure with its
shrunk input. A failure that M2's documents don't explain goes to step
7b.

## Task 6: check-it, the second contender

Spec §6.1; M3 finding 5. **Owns:**
- `ocicl.csv`;
- `tests/spike/check-it.lisp` (new);
- `cl-commonmark-gfm.asd`, for `/spike`'s dependency on check-it.

1. **Install check-it,** from the repository root:
   `ocicl install check-it </dev/null`. It brings closer-mop and optima.
   - Show `git diff ocicl.csv`: the new rows, each with a sha256 digest.
   - List what's new in `ocicl/`.
   - `make check-purity` still passes: no pure system depends on check-it.
2. **The `:check-it` methods** of the two generic functions:
   - the same three generators, built from check-it's generator language
     (its `README.md` and `src/generators.lisp`);
   - shrinking by check-it's own shrinker.
3. **Seeds.** check-it draws from `cl:random` (M3 finding 5).
   - Map the harness's integer seed to a random state where the Lisp can:
     `sb-ext:seed-random-state` on SBCL, and whatever CCL and ECL offer.
   - Record what each Lisp supports, and how a failure is replayed on it.

**Tests first,** in the spike's self tests:
- the `:check-it` cases stay within each generator's bounds and alphabet;
- check-it shrinks the `*a*` failure to a short input. Report its length;
  don't require `"*a*"` exactly;
- on SBCL, one seed gives the same cases twice.

**Mutations:** turn off check-it's shrinking: the shrink test fails.

**Verify:**
- properties 1 to 4 with `:check-it`, 10,000 cases per generator, on
  SBCL;
- property 5 on SBCL, CCL and ECL;
- in the report: cases per second next to Task 3's and Task 4's.

## Task 7: The benchmark

Spec §6.5. **Owns:**
- `.plans/2026-10-02-m3-benchmark.md` (new): the results;
- the library files the mutations touch, which are always reverted.

1. **The CI case count.** On the unmutated code, measure each property's
   cases per second with each contender. Choose one case count per
   property so that properties 1 to 4 on SBCL, plus property 5 on CCL and
   ECL, take about 30 s together. Record the choice.
2. **The seven mutations,** each alone, then reverted:
   1. **finding 17 undone:** in `html-output-bound`
      (`src/native/output-bounds.lisp`), the footnote terms use the
      tree's reference count in place of the input's openers;
   2. **finding 19 undone:** both places that decode cmark's output, the
      string accessor in `src/native/document.lisp` and the renderers in
      `src/native/render.lisp`, decode with `babel:octets-to-string` and
      `:encoding :utf-8` in place of `decode-utf8`. That signals on a cut
      character;
   3. **`copied-sourcepos`** (`src/native/copy.lisp`) copies the start
      position as the end;
   4. **`copied-list-attributes`** records `:delimiter` as `nil`;
   5. **the converter** (`src/html-tree/convert.lisp`) emits `<p>` even
      in a tight list (`tight-list-p`);
   6. **`plaintext-prefix-width`** (`src/native-core/output-bounds.lisp`)
      returns 0;
   7. **`table-cell-bound`** (`src/native-core/limits.lisp`) counts one
      row too few.

   For each mutation, record:
   - **without the properties:** whether `make test` fails, and which
     test;
   - **for each contender,** with the CI case count and seed 1:
     - whether it fails;
     - the cases until the first failure;
     - the shrunk input's length, and the input itself;
     - the run time.
3. **Unmutated runs:** 100,000 cases per property, per contender and per
   generator, with seeds drawn at random and recorded. Record:
   - every failure, shrunk;
   - the excuse and guard counts;
   - the run times.

**Verify:** `git diff --stat src/` is empty at the end. Every number in
the results file comes from a run the report shows.

## Step 7b: Fixes for real bugs the spike finds

Only if Task 5's or Task 7's runs find a bug that M2's documents don't
explain. For each bug:
- add a failing test to the existing suite it belongs to, with the shrunk
  input, and show it red;
- fix it, then show the test and the whole suite green;
- record it as an M3 finding in the spec.

Bugs in the native layer or the converter go to Opus; mechanical ones to
Sonnet.

## Task 8: ADR-0020, then the user confirms the decision

Spec §6.6. **Owns:**
- `.plans/decisions/0020-property-based-testing.md` (new);
- ADR-0007's status line.

1. **ADR-0020,** in ADR-0019's format:
   - **context:** ADR-0007's deferral, M3 findings 5 and 6, and chez's
     choice of oracles and mutation testing;
   - **evidence:** the benchmark's table, summarized, with a link to the
     results file;
   - **decision:** what spec §6.6's rule gives, and which contender, by
     its order of criteria;
   - **rejected:** the other contender, and either adoption or rejection,
     each with its numbers;
   - **consequences.**
2. **ADR-0007's status line:** amended by ADR-0020.
3. **The orchestrator asks the user to confirm,** showing the evidence
   and the rule's outcome. The ADR's status stays "Proposed" until the
   user answers.

## Task 9: Integration, or removal

Spec §6.7. **Owns:**
- `tests/spike/` and the two spike systems, which this task deletes;
- `tests/properties.lisp` and `tests/native/properties.lisp`, both new
  if adopted;
- `cl-commonmark-gfm.asd`, `ocicl.csv` and the `Makefile`.

**If adopted:**
1. **Move the winning contender's code into the suites:**
   - the harness, the generators and the UTF-8 property into
     `tests/properties.lisp` (`/tests`, all three Lisps);
   - the native properties into `tests/native/properties.lisp`
     (`/native-tests`);
   - one Parachute test per property, asserting on its summary
     (global constraint).
2. **Seeds and case counts:**
   - `CL_COMMONMARK_GFM_SEED` and `CL_COMMONMARK_GFM_CASES` set them;
   - by default, seed 1 and Task 7's CI case counts.
3. **`make fuzz`** runs every property with a random seed and ten times
   the cases. On a failure, it prints the seed and the shrunk input.
   `make help` lists it, and `check-help` passes.
4. **Remove the loser:** check-it's five rows from `ocicl.csv` if it
   lost (`check-it`, `closer-mop`, and `optima` with `optima.ppcre` and
   `optima.test`), or our contender's files if check-it won.
5. **Delete `tests/spike/`** and both spike systems.

**If rejected:** delete `tests/spike/`, both spike systems, and check-it's
five rows.

**Mutations (if adopted):** take two of Task 7's mutations that the
properties caught, and put each back alone. Each must make `make test`
fail at a property's test.

**Verify:**
- `make check-help` and `make test`;
- the properties' share of `make test`'s time, against the budget;
- `make fuzz` once, with its seed in the report.

## Task 10: Documents

**Part 1,** alongside Task 1. **Owns:**
- the status lines of ADR-0008 and ADR-0009, and the paragraphs they
  amend;
- `.plans/cl-commonmark-gfm.org`'s M3 section;
- `.plans/progress.md`'s milestones row and M3 checklist.

1. **ADR-0008:** unknown nodes are now tested on nodes built through
   cmark's public API (spec §4; M3 finding 3). Its claim that the node
   "cannot occur under this pin" stands.
2. **ADR-0009:** startup also checks `cmark_version()`'s number (spec §5;
   M3 finding 2).
3. **The plan's M3:** the spec linked; the three deliverables; the exit,
   unchanged.
4. **`progress.md`:**
   - the M3 row becomes "in progress";
   - an M3 checklist of this plan's tasks, one line each, with the spec
     and this plan linked.

**Part 2,** alongside Task 9. **Owns:**
- `.plans/cl-commonmark-gfm.org`'s decision log and Tests section;
- `.plans/progress.md`'s global constraints.

1. **Decision 26,** for ADR-0020.
2. **The plan's Tests section:** the properties, if adopted.
3. **A global constraint, if adopted:** CI runs the properties with a
   fixed seed and fixed case counts; `make fuzz` explores with random
   seeds.

**Verify:** no document states a rule the spec doesn't, and every link
resolves.

## Task 11: Review and close-out

1. **In the container:** `make check-help`, `make deps`, `make test` and
   `make check-guix`, all green.
2. **An Opus review** of the combined diff, against the spec and this
   plan. Fix what it finds, sending mechanical fixes to Sonnet. **Then a
   second review** of the fixes, since a fix round can break what the
   first review passed. Keep reviewing until a round comes back clean.
3. **The local CI run, before any commit.** Run
   `.guix-env/tmp/ci-proof-m2b/run-tree.sh` in `debian:trixie` under
   Docker:
   - every workflow step must pass;
   - `make -k test` must fail with one fixture byte flipped;
   - check each step's exit status in `steps.txt`.
4. **Close-out** in `progress.md`:
   - the tasks done, and the test counts per suite and per Lisp;
   - the benchmark's headline, and ADR-0020's decision;
   - the run times, the mutations seen, and anything found.
5. **Ask the user** to commit and open the PR. Its GitHub run must pass.

**M3 is done when:**
- the unknown-extension tests and the version cross-check pass, and each
  has been seen to fail;
- ADR-0020 is decided, and the code matches the decision;
- `make test` passes in the container, in the local `debian:trixie` run,
  and on the PR's GitHub run.
