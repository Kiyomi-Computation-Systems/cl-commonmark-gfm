# M3: unknown extensions, version probes and property testing — design

- **Date:** 2026-10-02
- **Status:** Approved 2026-10-02. Amended 2026-10-02, during M3's spike:
  findings 7 to 10, and §4.1's definition of an unknown node. Amended
  2026-10-02, after M3's review: §6.3's foreign-pointer check, §6.4's
  repeat excuse made exact, and finding 9's fourth input
- **Milestone:** M3, in one slice: branch `m3-extensions-versions-properties`
- **Inputs:**
  - the [project plan](cl-commonmark-gfm.org)'s M3;
  - ADR-0005, 0007, 0008, 0009, 0014, 0016, 0017 and 0018;
  - the [M2 spec](2026-09-30-m2-native-layer-design.md) §5.2, §6.2, §8.2
    and §8.3;
  - from chez-cmark-gfm: its ADR-0010 and ADR-0016, its shimless-FFI
    design §3.10, `traps.md` and `tests/test-convert.sps`;
  - from cmark-gfm 0.29.0.gfm.13 (`vendor/cmark-gfm`):
    `src/{cmark,node,syntax_extension}.c`, `src/cmark-gfm.h`,
    `src/cmark-gfm-extension_api.h`, `src/cmark-gfm_version.h.in` and
    `CMakeLists.txt`;
  - check-it 0.1.0 and cl-quickcheck 0.4, as ocicl serves them (snapshots
    of 2024-05-03).

Each rule below is stated here once. ADR-0020 records the
property-testing decision and why (§8).

## 1. Goal

The plan's M3 exit: version probes and unknown-extension behavior are
tested, and property-based testing has been evaluated. So M3 delivers
three things:
1. **Unknown extensions** (§4). The copier's `:extension` path, and what
   each entry point does with an unknown node, are tested on real native
   nodes.
2. **Version probes** (§5). Startup also checks the version *number*
   cmark reports.
3. **Property-based testing** (§6). A spike pits check-it against a small
   generator of our own on real targets. ADR-0020 then adopts or rejects
   property testing on the evidence.

**Success:**
- The unknown-extension tests and the version cross-check pass, and each
  has been seen to fail (§7).
- ADR-0020 is decided. If it adopts property testing, the property suite
  runs in `make test` within its budget, with a fixed seed.
- Any real bug the spike finds is fixed, test first.
- `make test` passes in three places: the Guix container, a local
  `debian:trixie` run of the CI steps, and GitHub.

## 2. Decisions made while brainstorming

| # | Question | Decision |
|---|----------|----------|
| D1 | How far M3 takes property-based testing | **A spike, then a decision** (ADR-0020). check-it and a generator of our own do the same work, and the evidence decides. |
| D2 | How unknown-extension behavior is tested | **On real native nodes,** built through cmark's public API from a parsed document, with no C (finding 3). |
| D3 | What remains of version probes | **A cross-check of `cmark_version()`'s number** at startup. M2b's exact version-string check stands (finding 1). |
| D4 | A public function reporting the loaded version and library paths | **Not in M3.** It belongs with M5's documentation of installation and library lookup. |
| D5 | How M3 is delivered | **One branch, one PR.** |

## 3. Findings

Probed on 2026-10-02 in the Guix container, on SBCL 2.6.4, with
throwaway scripts. Other documents cite them as "M3 finding N".

1. **M2b already probes the version.** Startup's step 4 requires
   `cmark_version_string` to return `"0.29.0.gfm.13"`, and otherwise
   signals `native-abi-mismatch` (M2 spec §5.2). Two native tests cover
   it: another version string, and an error while reading it.
2. **`cmark_version()` packs the version as gfm does, not as its header
   says.**
   - It returns `CMARK_GFM_VERSION`: `(major << 24) | (minor << 16) |
     (patch << 8) | gfm` (`src/cmark-gfm_version.h.in`, `src/cmark.c`).
     For the pin that's `#x001D000D`, which is what the probe read.
   - The header's comment describes upstream cmark's layout: the major
     version in bits 16 to 23, the minor in bits 8 to 15, and the patch in
     bits 0 to 7 (`src/cmark-gfm.h`). Decoded by that comment, the pin
     would read as version 29.0.13.
3. **No parse produces an unknown node, but cmark's public API builds
   one** (ADR-0008; M2 spec §6.2). The probe parsed a document, then
   built three kinds of node:
   - **An existing node given a new extension**
     (`cmark_syntax_extension_new`, then
     `cmark_node_set_syntax_extension`, on a paragraph). It classified as
     `:extension`, with the type string `"paragraph"`: the extension has
     no `get_type_string_func`, so cmark falls back to the core type's
     name (`src/node.c`). The copier kept it with its three children and
     its position.
   - **A node of a new extension type** (`cmark_syntax_extension_add_node`,
     then `cmark_node_new_with_ext`; the type was `#x800F` there). Its
     type string is `"<unknown>"`. The copier kept it, with no position,
     since its start line is 0.
   - **A custom block** (`CMARK_NODE_CUSTOM_BLOCK` from `cmark_node_new`).
     The copier signalled `unsupported-extension-node`.

   Three other operations also signalled `unsupported-extension-node` for
   the extension node: the HTML output bound, the plaintext output bound,
   and `ast->html-tree` on the copy.

   **Cleanup was safe.** cmark calls an extension's free function only
   when the extension has one. When it frees a node's payload, it ignores
   types it doesn't know (`src/node.c`). So the document freed cleanly.
   The extension was freed after it, with `cmark_syntax_extension_free`,
   and the open counters ended at zero.
4. **`cmark_syntax_extension_add_node` changes process-wide state without
   a lock.** Each call takes the next free type number
   (`src/syntax_extension.c`). The core extensions take theirs during
   startup, under the startup lock.
5. **check-it replays a run only on the Lisp that made it.**
   - It draws every value from `cl:random`. A run binds `*random-state*`
     to `(make-random-state random-state)`, a fresh state by default, and
     prints that state when a trial fails (`src/check-it.lisp`).
   - A printed random state can be read back only by the Lisp that
     printed it. So one seed can't give the same inputs on SBCL, CCL and
     ECL.
   - It depends on alexandria, closer-mop and optima.
   - While shrinking, it counts any error as a failure.
   - It can save failing cases to a regression file.
6. **Generated inputs will reach ADR-0014's two divergences.** Both need
   a footnote reference inside a footnote definition. The corpus reaches
   neither (M2b). *Corrected by finding 8: they rarely do.*

Found by the spike's runs (Tasks 5 and 6, 2026-10-02):

7. **cmark can report a negative column, and `parse` failed on it.**
   - **When it happens:** with tables and autolinks on, a paragraph's last
     line can turn it into a table header. `try_inserting_table_header_paragraph`
     (`extensions/table.c`) then rebuilds the lines before that one as a
     new paragraph, with no position: its start line is 0.
   - **What goes wrong:** inline positions inside that paragraph are
     computed from the missing origin (`cmark_parse_inlines`,
     `src/inlines.c`), so they are wrong. An autolink at the start of a
     line gets column -1 (`www_match`, `extensions/autolink.c`).
   - **Example:** for `"a\nwww.g\nb\n|-"`, cmark reports the link at
     `1:-1-1:4`, though it is on line 2. The pinned CLI's XML shows the
     same.
   - **Effect:** M2's AST schema required non-negative positions, so
     `parse`, with its default options, signalled `invalid-ast-node` on
     valid input. The full corpus never reached it.
   - **How it was found:** property 2 (the XML oracle), on corpus
     splices with our contender, first failed at seed 1, case 26,425. A
     sweep of seeds 1 to 5, 100,000 cases each, found it four more times:
     seed 1 at case 92,069, seed 2 at 85,901, and seed 4 at 26,904 and
     80,474.
   - **Decision** (the user, 2026-10-02): the AST accepts any integer in a
     position, as cmark reports it (ADR-0005 amended). The wrong positions
     in such a paragraph are documented, not repaired.
8. **The generators almost never produce footnotes.**
   - In seed 1's 10,000 cases, syntax soup produced no footnote reference
     or definition, and corpus splices produced one of each.
   - Across 1,000,000 cases, six differences were excused as
     `:excused-dropped`, and none as `:excused-repeat`.
9. **ADR-0014's list of divergences is incomplete.** Three more shapes have
   the same two causes, each confirmed with the pinned CLI:
   - `"[^a]: [^b]\n\n[^b]: B\n\nx[^c]\n\n[^c]: C\n"`: the dangling `b`
     takes number 1 in cmark, so `c` becomes 2 there but 1 in the tree;
   - `"x[^b] y[^a]\n\n[^a]: [^c]\n\n[^b]: [^c]\n\n[^c]: C\n"`: repeat
     references in two definitions, with no body reference, are swapped;
   - `"[^a]: [^b]\n\nx[^b]\n\n[^b]: text\n"`: a footnote referenced from
     the body and from a dropped definition gets two backrefs in cmark, one
     of them dangling.

   The excuses (§6.4) don't cover these, by design, so property 1 reports
   each as a failure. No generated input reached them.

   A fourth input fails property 1 too, with no new cause:
   `"[^b]:[^b]\n\n[^b] ![x[^b]](u)\n"`, the repeat divergence with a
   reference in an image's alt text. cmark writes no anchor there
   (`src/html.c`), so the tree's ids for `b` skip a number, and the repeat
   excuse's check on them fails (found by M3's second review).
10. **check-it's generator language can't express the spike's generators**
    (Task 6).
    - Its `character` generator stops at code 127, whatever its bounds.
    - Its `list` lengths are capped by its own size parameter.
    - Its `or` picks alternatives almost uniformly, so weights would take
      one alternative per unit of weight.

    So the `:check-it` contender draws uniform integers through check-it,
    and builds the same three generators from them. What check-it adds is
    its random source and its shrinker. Only SBCL can seed that random
    source from an integer (`sb-ext:seed-random-state`); CCL and ECL have no
    public way, so a check-it failure there can't be replayed from its seed.

## 4. Unknown extensions

### 4.1 The behavior under test

No library change is planned: the tests pin down what M2b built. An
unknown node is a node whose extension is none of the five core
extensions that startup caches (M2 spec §6.2), whichever of them the
parse attached.
- **`parse`** keeps an unknown node as `:extension`:
  - `:type-name` is cmark's type string, and `:extension-name` is `nil`;
  - it keeps its children and, with `:sourcepos`, its position.
- **A custom node** (`custom_block` or `custom_inline`) makes the copier
  signal `unsupported-extension-node`.
- **`markdown->html` and `markdown->plaintext`** signal
  `unsupported-extension-node` from the output-bound walk. So cmark's
  renderers never meet an unknown node.
- **`markdown->html-tree`** copies the node. Then `ast->html-tree`
  signals `unsupported-extension-node`.

### 4.2 Building unknown nodes

- **Test-only bindings:** `cmark_syntax_extension_new`,
  `cmark_syntax_extension_free`, `cmark_syntax_extension_add_node`,
  `cmark_node_new`, `cmark_node_new_with_ext`,
  `cmark_node_set_syntax_extension` and `cmark_node_append_child`. They
  live in `/native-tests`, not `/ffi`; the library binds none of them.
- **One helper** makes the extension, calls a function, and frees the
  extension in an `unwind-protect` after the function returns. The
  function releases its document first, since the document's nodes point
  at the extension.
- **New node types** are taken once per process and cached (finding 4).
- **The tests reuse the entry points' internal steps.** They parse with
  `with-native-document`, add the unknown nodes, then copy, bound or
  convert. An entry point has no hook between its parse and its copy,
  and gets none for tests.

### 4.3 Tests

On SBCL, in the native suite:
1. A parsed paragraph given an unknown extension is copied as
   `:extension` named `"paragraph"`, with its children and its position.
2. A node of a new block type is copied as `:extension` named
   `"<unknown>"`, with no position. A node of a new inline type, added
   inside a paragraph, is kept in its place among its siblings.
3. A `custom_block` signals `unsupported-extension-node`, and so does a
   `custom_inline`.
4. The HTML and plaintext output bounds signal
   `unsupported-extension-node` for an unknown node.
5. `ast->html-tree` signals `unsupported-extension-node` on the copy.
6. After each test, the open counters are zero.

## 5. The version cross-check

- **`/native-core` gains two pure functions:**
  - `version-number` turns `"M.m.p.gfm.N"` into `(M << 24) | (m << 16) |
    (p << 8) | N`, and signals on a malformed string;
  - `number-version` turns such a number back into the string.

  Pure tests on all three Lisps: the pin gives `#x001D000D`; other
  versions round-trip through both functions; malformed strings signal.
- **`/ffi` binds `cmark_version`.**
- **Startup's step 4 also checks the number,** after the string:
  `cmark_version()` must equal `(version-number *cmark-gfm-version*)`.
  Otherwise it signals `native-abi-mismatch`:
  - `found-version` is the version the number encodes, from
    `number-version`;
  - the reason gives both versions and both numbers, in hex.

  An error while reading the number is handled as an error while reading
  the string already is.
- **Native tests:**
  - a wrapper returning another number signals `native-abi-mismatch`,
    naming both versions;
  - an error from the wrapper signals it too.

## 6. The property-testing spike

### 6.1 Two contenders, doing the same work

- **check-it,** with its own generators and shrinking, installed through
  ocicl. Its three dependencies join `ocicl.csv` for the test systems
  only.
- **Our own,** in the test systems, with no dependency:
  - **a seeded generator:** a splitmix64 stream from an integer seed, so
    one seed gives the same inputs on SBCL, CCL and ECL (finding 5);
  - **a shrinker over strings,** in the style of delta debugging. It
    deletes runs of lines, then runs of characters, halving their size
    each time, while the property still fails.

Both use the generators of §6.2 and run the properties of §6.3. One
harness counts cases, failures and excuses for both.

### 6.2 Generators

- **Syntax soup.** Strings of up to 400 characters, from an alphabet
  weighted toward Markdown's syntax:
  - the punctuation cmark treats specially, plus digits, letters, spaces
    and tabs;
  - `\n`, `\r` and NUL;
  - multibyte characters of two to four octets;
  - fragments such as `[^`, `]:`, `|---|`, `&#94;` and `&amp;`.
- **Corpus splices.** Up to 20 lines drawn from the corpus's 747 examples
  (M2 spec §8.2) and joined, with an occasional character changed.
- **Options.** Each case draws one of the option sets that M2b's oracles
  use (M2 spec §8.3).
- **Sizes.** Inputs stay far below the three limits, so a limit never
  decides a case.

### 6.3 Properties

The native properties (1 to 4) run on SBCL, as the native suite does
until M4. The pure one (5) runs on all three Lisps.
1. **The HTML oracle.** The tree's HTML equals cmark's, compared as M2b's
   HTML oracle compares them, unless §6.4 excuses the difference.
2. **The XML oracle.** The copied AST, written as cmark's XML, equals
   cmark's XML, positions included.
3. **The bounds.**
   - The HTML and plaintext output bounds are at least the octets cmark
     writes.
   - The table-cell bound is at least the number of table cells in the
     parse.
4. **Clean outcomes.**
   - Each entry point returns. The one other allowed outcome is
     `unsupported-input`, from the input guard, which is counted.
   - After each case, the open counters are zero.
   - The AST holds no foreign pointer. *Amended during M3's review:* the
     schema guarantees this, since `make-node` rejects a pointer
     attribute, so the property no longer checks it.
   - A second parse gives an AST that is `node=` to the first.
   - A full GC runs every 100 cases.
5. **UTF-8, pure.**
   - `decode-utf8` never signals on random octets.
   - Decoding, encoding the result and decoding again gives the first
     decoding's string.
   - A string with no lone surrogates survives `encode-utf8` then
     `decode-utf8` unchanged.

**Each property and generator is one Parachute test** with one assertion,
over a summary: the case count, the failures, and the first failure,
shrunk. No assertion captures a generated input, per `progress.md`'s
global constraint.

### 6.4 ADR-0014's divergences

Property 1 excuses a difference only when it has one of the two
documented shapes. Each excuse is counted.
- **Repeat references are counted in tree order.** cmark numbers a
  label's repeat references in source order, the tree in tree order, and
  nothing else differs: cmark's backrefs don't depend on reference order
  (`S_put_footnote_backref`, `src/html.c`). So three things must hold:
  - the AST has a repeat reference inside a definition, and in the source
    it comes before a body reference with the same label;
  - the tree's ids for each such label L, in output order, are exactly
    `fnref-L`, `fnref-L-2` … `fnref-L-n`, one per reference in the AST;
  - once each of those ids is rewritten to the one cmark gives that
    reference, by its rank in source position, the two HTML outputs are
    equal byte for byte, backrefs included.

  *Amended during M3's review:* the first version replaced every repeat
  number, in ids and backrefs, with one placeholder. That excused real
  converter bugs, such as a reference id with no repeat suffix.
- **A definition is referenced only from a dropped definition.** The two
  HTML outputs are equal once cmark's footnote items are removed
  wherever every backref points at no reference.

Any other difference is a failure.

### 6.5 The benchmark

Each mutation is applied on its own. The fasl cache is deleted before
every run, per `progress.md`'s global constraint.
1. **Finding 17 undone:** the HTML bound counts the references in the
   parse, not the openers in the input.
2. **Finding 19 undone:** cmark's output is decoded strictly, so a cut
   character signals.
3. **The copier** drops an end position.
4. **The copier** drops a list's delimiter.
5. **The converter** keeps `<p>` in tight list items.
6. **The plaintext bound** drops the list items' prefix term.
7. **The table-cell bound** counts one row too few.

**The CI case count** is the number of cases that fits §6.6's budget of
about 30 s, as the spike measures it on the unmutated code.

For each mutation the benchmark records:
- whether `make test` without the properties catches it;
- whether each contender catches it within the CI case count;
- how many cases each needs until the first failure;
- how large each one's shrunk input is;
- each one's run time.

**Unmutated runs.** Each contender also runs 100,000 cases on the
unchanged code, with random seeds, looking for real bugs and false
failures.

### 6.6 The decision (ADR-0020)

**Adopt property testing when both of these hold:**
- it catches at least one benchmark mutation that the existing suite
  misses, or it finds a real bug;
- the CI properties fit in about 30 s and run deterministically, with a
  fixed seed, and a failure's report is enough to replay it.

**Between the contenders,** these criteria decide, in this order:
1. mutations caught;
2. the shrunk inputs' size;
3. replay on every Lisp;
4. dependencies and code size;
5. speed.

The losing contender's code is deleted before the PR.

### 6.7 What follows

- **If property testing is adopted:**
  - the properties join the existing suites: the native ones in
    `/native-tests`, the pure one in `/tests`;
  - `CL_COMMONMARK_GFM_SEED` and `CL_COMMONMARK_GFM_CASES` set the seed
    and the case count. Their defaults are fixed, for CI;
  - `make fuzz` runs many more cases with a random seed. On a failure, it
    prints the seed and the shrunk input;
  - `progress.md`'s global constraints gain a rule: CI runs properties
    with a fixed seed.
- **If it is rejected,** ADR-0020 records why, and the harness is deleted.
  The benchmark's results stay in `progress.md`.

## 7. Seen to fail

- **The unknown-extension tests (§4.3)** must fail on each of these
  mutations:
  - the copier drops an `:extension` node's children;
  - the copier records the core type instead of the type string;
  - classification gives `:paragraph` for an unknown extension;
  - the output-bound walks skip an unknown node;
  - the copier accepts a custom node.
- **The version cross-check (§5)** must fail with the number check
  removed, and with a wrong shift in `version-number`.
- **The properties (§6)** get their own mutation run: the benchmark of
  §6.5.

## 8. Documents

- **ADR-0020:** property-based testing, adopted or rejected, with the
  benchmark. It amends ADR-0007.
- **ADR-0008, amended:** unknown nodes are tested on nodes built through
  cmark's public API.
- **ADR-0009, amended:** startup also checks `cmark_version()`'s number.
  ADR-0002 already says the version is "checked at load (ADR-0009)".
- **The plan (`cl-commonmark-gfm.org`):**
  - M3's text and exit;
  - decision 26, for ADR-0020.
- **`progress.md`:** the M3 checklist and close-out.

## 9. Out of scope

- **A public function reporting the version and library paths:** M5 (D4).
- **Fixing ADR-0014's two divergences.** They stay documented, unless the
  spike shows that real documents hit them often.
- **Native properties on CCL and ECL:** M4, with the native suite.
- **Markdown built from a grammar, and coverage-guided fuzzing.** The
  spike's generators come first.
- **Making unknown extensions reachable.** Version 1 attaches only the
  five core extensions (the plan's decision 5).
