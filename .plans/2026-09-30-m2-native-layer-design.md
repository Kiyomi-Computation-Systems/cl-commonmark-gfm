# M2: stack-safe walks and the native layer — design

- **Date:** 2026-09-30
- **Status:** Approved 2026-09-30
- **Milestone:** M2, delivered in two slices: M2a (stack-safe walks), then
  M2b (the native layer)
- **Inputs:** [project plan](cl-commonmark-gfm.org); ADR-0005, 0006, 0008,
  0009, 0011, 0012, 0013 and 0014; the
  [M1 spec](2026-09-27-m1-pure-core-design.md) §9; chez-cmark-gfm ADR-0006,
  0008, 0009 and 0010; and cmark-gfm 0.29.0.gfm.13's
  `src/{blocks,buffer,cmark,html,inlines,node,plaintext,render,xml}.c`,
  `extensions/{autolink,table,tasklist}.c`, `extensions/ext_scanners.re`
  and `test/{*.txt,spec_tests.py,cmark.py,pathological_tests.py}`
  (`vendor/cmark-gfm`)

Each rule below is stated here once. ADRs 0015 to 0018 record the
decisions and why, and link to the sections that state them (§9).

## 1. Goal

Parse and render with cmark-gfm, on SBCL, so that no Markdown input can
crash the process by itself (§5.5 states the remaining risk):

1. **M2a, stack-safe walks.** Every walk over an AST or an HTML tree loops
   over an explicit stack, so depth is limited by memory, not by the Lisp's
   stack. No output changes.
2. **M2b, the native layer.** CFFI bindings; finding, loading and starting
   the pinned libraries; native lifetimes; limits that keep cmark from
   aborting; a copier for every node kind; the public `parse` and render
   functions; and four oracles.

**Success:**
- **M2a:** `make test` passes on SBCL, CCL and ECL. M1's 226 tests and 28
  fixtures pass unchanged, and trees 100,000 levels deep pass through
  every walk.
- **M2b:** `make test` passes, now with the native suite on SBCL, in the
  Guix container and in a local `debian:trixie` run of the CI steps. The
  GitHub run waits for October, as M0's and M1's did. The plan's M2 exit
  holds:
  - ASTs stay valid after their native document is freed;
  - the open-handle counters are zero after every native suite;
  - the oracle passes over the whole corpus.
- Every check has been seen to fail.

## 2. Decisions made while brainstorming

| # | Question | Decision |
|---|----------|----------|
| D1 | How much of the copier M2 builds | **Every node kind but `:extension`.** M3 keeps unknown extensions, version probes and property tests. |
| D2 | Trees deeper than the Lisp stack | **No depth limit.** Every walk loops over an explicit stack (§4). |
| D3 | Which cmark options version 1 exposes | **A small set** (§7.2). More can be added later without breaking callers. |
| D4 | How the copied AST is checked | **Against cmark's own XML, corpus-wide** (chez ADR-0010), beside three other witnesses (§8.3). |
| D5 | How M2 is delivered | **One spec, two slices,** each with its own plan, branch and PR: M2a, then M2b. |
| D6 | Where the native layer's decisions live | **A pure `/native-core` system,** tested on all three Lisps. |
| D7 | New dependencies | **CFFI and bordeaux-threads,** for the native systems only. |
| D8 | M1's non-copying child accessor | **`walk-ast`,** one exported traversal function. The child list stays internal. |
| D9 | How the converter becomes iterative | **A port of `html.c`'s event loop.** Footnote places are keyed by owner and ordinal, not by path. |
| D10 | The crashes cmark can cause | **Three limits,** each checked before cmark does the work it guards (§5.5). |
| D11 | Starting the native layer | **On first use, once, under a lock.** A failed attempt closes what it loaded, and the next call tries again. |
| D12 | Saved Lisp images | **The Lisps' own save hooks** close the libraries and clear the state. |
| D13 | A native document used after release | **An alive flag** that every native accessor checks (chez ADR-0006). |
| D14 | Source positions | **On by default for `parse`, off for `markdown->html`,** and copied only from a parse with `CMARK_OPT_SOURCEPOS` (chez ADR-0008, ADR-0009). |
| D15 | A footnote reference's label | **From `cmark_node_parent_footnote_def`.** After parsing, the reference's own literal is its number. |
| D16 | New conditions | **Parents `invalid-option` and `native-error`,** and new `invalid-parse-option` and `resource-limit-exceeded`. |
| D17 | Where rules are written down | **Once, in this spec.** ADRs record decisions and link here. |

Found while checking facts against the pin, the pinned CLI, and probes in
the Guix container (SBCL 2.6.4, CCL 1.13, ECL 24.5.10):

1. **cmark kills the process in two ways,** and no Lisp handler can catch
   either:
   - `cmark_strbuf_grow` calls `abort()` when a buffer would pass
     1,073,741,823 bytes (`src/buffer.c`);
   - the default allocator calls `abort()` when `calloc` or `realloc`
     fails (`src/cmark.c`).
2. **Padded table cells blow up output and memory.** A row shorter than
   its table's header gets real, empty cell nodes (`try_opening_table_row`,
   `extensions/table.c`). cmark caps those at 524,288 per table
   (`MAX_AUTOCOMPLETED_CELLS`), but not per document.
   - A 5,053-byte table renders to 5,257,350 bytes of HTML.
   - 1,111,660 bytes of such tables made the CLI abort, with exit code 134
     and `cmark_strbuf_grow requests buffer with size > 1073741823`.
   - 252,650 bytes of them peaked at 6.6 GB of memory.
3. **Footnote references multiply HTML 69 times.** 40,010 bytes of `[^a]`
   render to 2,764,532 bytes.
4. **Plaintext repeats list indentation on every line.** Each list item
   adds its marker's width, at least 4, to a prefix written at the start of
   every line inside it; a footnote definition adds 4 (`src/plaintext.c`,
   `src/render.c`). 8,002 bytes rendered to 800,200. cmark opens at most
   100 new blocks on one line (`MAX_LIST_DEPTH`, `src/blocks.c`), which
   capped that example; nesting built up over many lines has no cap.
5. **M1's walks run out of stack long before cmark does.** Measured on a
   ladder of depths, in the main thread and in spawned threads alike:
   - SBCL's `node=` runs out first: fine at 2,000 levels, out of stack by
     4,000;
   - the converter and the serializer run out between 8,000 and 32,000
     levels, depending on the Lisp;
   - trees 300,000 children wide are fine on all three.

   cmark's own stress tests nest 130,000 levels
   (`test/pathological_tests.py`).
6. **cmark's parser rewrites footnotes, and a reference loses its label**
   (`process_footnotes`, `src/blocks.c`):
   - a resolved reference's literal becomes its number, such as `"1"`. Its
     definition is `cmark_node_parent_footnote_def`, which is public, and
     the definition's literal is the label as written;
   - unreferenced and duplicate definitions are unlinked and freed. Kept
     ones are appended to the document, in number order;
   - a dangling reference is replaced by a text node, `[^label]`.

   ADR-0005's finding 2 says `cmark_node_get_literal` returns the label for
   both footnote kinds. For a parsed reference, it doesn't.
7. **Positions are only right with `CMARK_OPT_SOURCEPOS`.** Without it,
   cmark skips `adjust_subj_node_newlines` (`src/inlines.c`), so positions
   after a multi-line code span or raw HTML drift (chez ADR-0009).
8. **The corpus:**
   - six files, 749 examples: `spec.txt` 672 (2 marked `disabled`),
     `extensions.txt` 30, `regression.txt` 26, `smart_punct.txt` 16,
     `extensions-full-info-string.txt` 4 and
     `extensions-table-prefer-style-attributes.txt` 1;
   - an example's fence line can name extensions (`example autolink`,
     `example footnotes table`), and `spec_tests.py` turns `→` into a tab
     and skips `disabled` examples;
   - cmark's harness runs with `--unsafe` (`test/cmark.py`). It adds
     `--smart` for `smart_punct.txt`, and all five extensions plus
     footnotes for the three `extensions*.txt` files; the last two add
     `--full-info-string` and `--table-prefer-style-attributes`;
   - run that way, the pinned CLI reproduces the expected HTML of 746 of
     the 747 enabled examples byte for byte. The other expects `<IGNORE>`,
     which `spec_tests.py` doesn't compare.
9. **Autolinks carry no extension.** The autolink extension builds plain
   `CMARK_NODE_LINK` nodes and never sets their extension
   (`extensions/autolink.c`), so ADR-0008's classification holds.
10. **`cmark_parser_attach_syntax_extension` always returns 1**
    (`src/blocks.c`).
11. **Lone surrogates:** `(code-char #xD800)` is a character on SBCL and
    ECL, and `nil` on CCL.
12. **UIOP's image hooks don't run on a direct save.** They run only inside
    `uiop:dump-image` and `uiop:restore-image`. SBCL's `sb-ext:*save-hooks*`
    and CCL's `ccl:*save-exit-functions*` run on every save, including one
    made by `uiop:dump-image`.
13. **cmark's XML hides three things:**
    - footnote nodes have no type string, so they print as `<<unknown>`,
      with no label;
    - `align` appears only on header-row cells (`extensions/table.c`);
    - task items carry `completed="true"` or `completed="false"`
      (`extensions/tasklist.c`).

## 3. Systems, packages and dependencies

All systems are defined in `cl-commonmark-gfm.asd`. Package names are the
system names with the slash replaced by a dot.

| System | Depends on | CFFI | Slice |
|--------|------------|------|-------|
| `cl-commonmark-gfm/util` | — | no | M2a; M2b adds the encoder |
| `cl-commonmark-gfm/conditions` | — | no | M2b extends it |
| `cl-commonmark-gfm/ast` | conditions, util | no | M2a changes it |
| `cl-commonmark-gfm/html-tree` | ast, util | no | M2a changes it |
| `cl-commonmark-gfm/native-core` | conditions, util | no | M2b |
| `cl-commonmark-gfm/ffi` | cffi | yes | M2b |
| `cl-commonmark-gfm/native` | native-core, ffi, ast, util, cffi, bordeaux-threads | yes | M2b |
| `cl-commonmark-gfm` | native, html-tree | yes | M2b |
| `cl-commonmark-gfm/tests` | the pure systems, Parachute | no | both |
| `cl-commonmark-gfm/native-tests` | `cl-commonmark-gfm`, tests, Parachute | yes | M2b |

- **What each new system holds:**
  - `/util`: `proper-list-p` (M2a). In M2b, `char-utf8-octets` moves here
    from the URL helpers, and `utf8-length` and `encode-utf8` join it
    (§6.5).
  - `/native-core`: cmark's constants; option checking and option bits
    (§7); `classify-node` (§6.2); `resolve-cmark-libraries` (ADR-0009);
    the limit variables, the hard caps and the table-cell bound, plus the
    per-node terms of the output bounds (§5.5); and
    `*cmark-gfm-libraries*`.
  - `/ffi`: the C declarations (§5.1).
  - `/native`: startup, saved images, lifetimes, counters, the native
    walker, the output-bound walk, the copier and the render calls.
  - `cl-commonmark-gfm`: the four entry points (§7.1). It is defined with
    `uiop:define-package`, and re-exports every exported symbol of
    `.conditions`, `.ast` and `.html-tree`, and the four variables of
    `.native-core`.
- **The pure systems** are `util`, `conditions`, `ast`, `html-tree`,
  `native-core` and `tests`. They still depend on nothing outside the
  project, and `check-purity` still fails if a `CFFI` package exists after
  the pure run.
- **New in `ocicl.csv`,** pinned by sha256 like the rest: CFFI (with
  alexandria, babel and trivial-features) and bordeaux-threads (with
  global-vars and trivial-garbage).
- **Reader conditionals** appear only in `/native`: the save hooks (§5.3)
  and ECL's `:dffi` check (§5.2).

## 4. M2a: stack-safe walks

Every walk over an AST or an HTML tree loops over an explicit stack (D2).
Nothing else changes: M1's output rules, conditions and tests stand.

### 4.1 `walk-ast`

```lisp
(walk-ast function node)
```

- Visits NODE and its descendants depth-first, children in order. It calls
  `(funcall function :enter n)` before n's children and
  `(funcall function :exit n)` after them. A leaf gets both calls.
- When an `:enter` call returns `:skip`, n's children and n's `:exit` call
  are skipped. Every other return value is ignored.
- Returns `nil`. A node object that sits at several places is visited at
  each. Child lists are read without copying.
- Signals a `type-error` when NODE isn't a node. Whatever FUNCTION signals
  passes through, and abandons the walk.
- Exported from `cl-commonmark-gfm.ast`. It is the one AST traversal
  (D8): `fold-ast`, `map-ast`, `transform-ast` and every AST walk in
  `html-tree` are built on it.

### 4.2 The other AST walks

- **`fold-ast` and `map-ast`** act on `walk-ast`'s `:enter` events.
- **`transform-ast`** opens a frame per node on `:enter`, to collect its
  transformed children. On `:exit` it rebuilds the node, calls FUNCTION,
  checks the result and hands it to the parent's frame. M1's contract
  stands (M1 spec §4.5), including returning the same node object when no
  child changed.
- **`node=`** is its own loop over a stack of node pairs, making M1's
  comparisons. A pair of `eq` nodes is equal without being descended.

### 4.3 The converter

`ast->html-tree` becomes a port of cmark's renderer loop: `S_render_node`
in `src/html.c`, which runs on enter and exit events, and the
`html_render` functions of `extensions/{table,tasklist,strikethrough}.c`
(D9). The rules are M1's (M1 spec §5.2 to §5.4). This section says how
they are organized, and the table restates them event by event.

**Output state:**
- **A stack of open elements,** each with its tag, its attributes and its
  children so far. Opening an element pushes one. Closing pops it,
  normalizes its children (adjacent strings merged, empty strings dropped)
  and adds it to its parent. The bottom of the stack collects the
  top-level items.
- **`bol`,** true when the output so far is empty or ends in a newline. A
  start tag, an end tag or a void element clears it. A non-empty string
  sets it from its last character. `cr` writes `"\n"` unless `bol` is
  true.

**Context,** from the event handler's own stack of ancestors:
- a paragraph is *tight* when its grandparent is a `:list` with `:tight t`;
- a `:strong` whose parent is a `:strong` adds no element;
- a cell is a `th` while any `:table-header` is open, by a count of open
  ones;
- each `:table` records whether its `tbody` is open.

**Events:**

| Node | `:enter` | `:exit` |
|------|----------|---------|
| `:document` | — | — |
| `:block-quote` | cr, open `blockquote`, `"\n"` | cr, close, `"\n"` |
| `:list` | cr, open `ul`, or `ol` with a `start` attribute when `:start` isn't 1; `"\n"` | close, `"\n"` |
| `:item` | cr, open `li` | close, `"\n"` |
| `:task-item` | cr, open `li`, the checkbox `input`, `" "` | close, `"\n"` |
| `:paragraph`, tight | — | — |
| `:paragraph` | cr, open `p` | the backrefs, when this is a definition's backref paragraph (§4.4); close, `"\n"` |
| `:heading` | cr, open `h1` to `h6` | close, `"\n"` |
| `:code-block` | cr, open `pre`, open `code` (with `class="language-W"` when `:info` isn't empty), the literal, close, close, `"\n"` | — |
| `:html-block` | cr, the raw HTML by `:raw-html`, cr | — |
| `:thematic-break` | cr, `hr`, `"\n"` | — |
| `:table` | cr, open `table` | if its `tbody` is open: cr, close `tbody`, cr. Then cr, close `table`, cr |
| `:table-header` | cr, open `thead`, cr, open `tr` | cr, close `tr`, cr, close `thead` |
| `:table-row` | if the parent is a `:table` whose `tbody` isn't open: cr, open `tbody`, cr, and mark it open. Then cr, open `tr` | cr, close `tr` |
| `:table-cell` | cr, open `th` or `td`, with `align` from `:align` | close |
| `:text` | the literal | — |
| `:softbreak` | `"\n"`; `" "`; or `br` then `"\n"`; by `:softbreak` | — |
| `:linebreak` | `br`, `"\n"` | — |
| `:code` | open `code`, the literal, close | — |
| `:html-inline` | the raw HTML by `:raw-html` | — |
| `:emph`, `:strikethrough` | open `em` or `del` | close |
| `:strong` | open `strong`, unless the parent is a `:strong` | close, likewise |
| `:link` | open `a`, with `href` and `title` | close |
| `:image` | start plain mode | end plain mode; `img` with `src`, `alt` and `title` |
| `:footnote-reference` | the reference's `sup`, or `[^label]` when it dangles | — |
| `:footnote-definition` | return `:skip` | — |
| `:extension` | ruled out by the pre-pass (§4.4) | — |

A leaf does all its work on `:enter`. The leaves are `:code-block`,
`:html-block`, `:thematic-break`, `:text`, `:softbreak`, `:linebreak`,
`:code`, `:html-inline` and `:footnote-reference`.

- **Plain mode,** cmark's `renderer->plain`, runs from an image's `:enter`
  to its `:exit`. Inside it, nodes only add to the image's alt text:
  - `:text`, `:code` and `:html-inline` add their literal;
  - `:softbreak` and `:linebreak` add a space;
  - a dangling `:footnote-reference` adds its `[^label]`, and a resolving
    one adds nothing, though it still counts as a reference;
  - a `:footnote-definition` is skipped;
  - every other node adds nothing of its own, and its children are
    visited. That includes nested images.
- **After the walk,** the footnote section (§4.4) is added, the top-level
  items are normalized, and `:document-wrapper` applies, all as in M1.

### 4.4 Footnotes without paths

The footnote rules are ADR-0014's (M1 spec §5.4). What changes is how a
place in the tree is identified.

- **Owners.** Every reference place has an *owner*: the document body, or
  the innermost definition place that contains it. A nested definition
  owns the references inside it.
- **The pre-pass** is one `walk-ast` over the document. It:
  - numbers definition places in the order it enters them, and records
    the order it leaves them;
  - keeps a stack of owners, starting with the body, and pushes each
    definition place when it enters one;
  - keys each reference place by its owner and its ordinal among that
    owner's references, and records the order of all reference places;
  - signals `unsupported-extension-node` at the first `:extension` node,
    as M1 does before converting;
  - then applies ADR-0014's steps 1 to 4 to these records.
- **The converter counts the same way.** The main walk is the body's
  owner, and skips definitions where they stand. The section then renders
  each surviving definition, in number order, as its own owner with a
  fresh count:
  - each child of the definition is walked separately, skipping nested
    definitions, with the definition as parent and the document as
    grandparent;
  - the *backref paragraph* is the definition's last child that isn't a
    definition, when that child is a `:paragraph`. Its `:exit` writes
    `" "` and the backrefs before closing the `p`. With no backref
    paragraph, the backrefs and a `"\n"` follow the children.
- **Why:** M1 keyed places by their path from the root, in `equal` hash
  tables. In a deep chain every path starts with the same elements, and
  `sxhash` hashes only the first few, so lookups degrade to scans. An
  owner and an ordinal are two small integers.

### 4.5 The serializer

`html-tree->string` loops over a stack of open elements. Its "element
contains itself" check looks elements up in an `eq` hash set of open
elements instead of scanning a list, so it stays linear at any depth.
Elements are checked in M1's order, so a malformed tree signals the same
condition, with the same datum, as it did in M1.

### 4.6 `/util`

`proper-list-p`, written as a loop over Floyd's two pointers, replaces the
copies in `schema.lisp` and `serialize.lisp`.

### 4.7 Tests

- M1's suite and fixtures, unchanged.
- **Deep trees,** 100,000 levels, on all three Lisps. Each goes through
  `walk-ast`, `fold-ast`, `map-ast`, `transform-ast` (identity, and a
  rebuilding function), `node=` (of two separately built trees),
  `ast->html-tree` and `html-tree->string`:
  - block quotes;
  - alternating `:emph` and `:strong`;
  - nested lists, as list, item, list, item, …;
  - nested links;
  - an image whose alt text comes from 100,000 levels below it;
  - footnote definitions nested in definitions, each referenced from the
    body;
  - a hand-built HTML tree 100,000 elements deep, for the serializer
    alone.

  Expected strings are built by plain loops, not by the code under test.
  No deep value reaches a failure message: the assertions compare strings,
  numbers or booleans.
- **Wide trees:** 300,000 children under one node.
- **`walk-ast`:** the event order, `:skip`, a node at two places, and a
  non-node.
- **Seen to fail:** putting each walk back to plain recursion, one at a
  time, fails the deep tests on SBCL, which has the smallest stack.

## 5. M2b: the native layer

### 5.1 Bindings

`/ffi` declares the functions below, with the types `cmark-gfm.h` and
`cmark-gfm-core-extensions.h` give them:
- C `int` is `:int`, `size_t` is `:size` and `uint16_t` is `:uint16`;
- every pointer is `:pointer`;
- the task checkbox's C `bool` is `:uint8`, tested against zero
  (ADR-0008's second ABI assumption).

| Group | Functions |
|-------|-----------|
| Parser | `cmark_parser_new`, `cmark_parser_attach_syntax_extension`, `cmark_parser_feed`, `cmark_parser_finish`, `cmark_parser_get_syntax_extensions`, `cmark_parser_free`, `cmark_node_free` |
| Walking | `cmark_node_first_child`, `cmark_node_next`, `cmark_node_parent` |
| Node facts | `cmark_node_get_type`, `…_get_type_string`, `…_get_syntax_extension`, `…_get_literal`, `…_get_url`, `…_get_title`, `…_get_fence_info`, `…_get_heading_level`, `…_get_list_type`, `…_get_list_delim`, `…_get_list_start`, `…_get_list_tight`, `…_get_start_line`, `…_get_start_column`, `…_get_end_line`, `…_get_end_column`, `cmark_node_parent_footnote_def` |
| GFM | `cmark_gfm_core_extensions_ensure_registered`, `cmark_find_syntax_extension`, `cmark_gfm_extensions_get_table_columns`, `…_get_table_alignments`, `…_get_tasklist_item_checked` |
| Rendering | `cmark_render_html`, `cmark_render_plaintext`, and `cmark_render_xml` for the XML oracle |
| Other | `cmark_version_string`, `cmark_get_default_mem_allocator` |

- **Strings cmark lends** come back as pointers and are decoded
  explicitly, as UTF-8 (§6.5). The string accessors are only called on
  the kinds they serve, where they never return null, so a null signals
  `native-parse-error`.
- **One native walker.** `/native` walks a parsed tree with
  `cmark_node_first_child`, `cmark_node_next` and `cmark_node_parent`,
  keeping its own stack, with no `cmark_iter` to free. The copier, the
  output-bound walk and the startup check all use it.

### 5.2 Startup

The first call that needs cmark runs these steps, once per process, under
a bordeaux-threads lock (D11):

1. On ECL without `:dffi`, signal `dynamic-ffi-unavailable`.
2. Resolve the library pair (ADR-0009): the override, or the directory
   search. If neither finds it, signal `native-library-not-found`.
3. Load the core, then the extensions, with `cffi:load-foreign-library` by
   absolute path. A load error signals `native-library-not-found`, naming
   the path and the loader's message.
4. `cmark_version_string` must return `"0.29.0.gfm.13"`. Otherwise signal
   `native-abi-mismatch`.
5. Call `cmark_gfm_core_extensions_ensure_registered`.
6. Cache the five extensions: `cmark_find_syntax_extension` for `table`,
   `strikethrough`, `autolink`, `tagfilter` and `tasklist`. A null signals
   `native-initialization-error`.
7. Read the default allocator's `free`, `(cffi:mem-aref allocator
   :pointer 2)` (ADR-0008's first ABI assumption). A null signals
   `native-initialization-error`.
8. Run a smoke parse under `:gfm`, through the lifetime machinery of §5.4
   with the state from steps 3 to 7, not yet published: a table, a
   checked task item and a footnote. The classified nodes must include
   `:table`, `:task-item` and `:footnote-reference`, or
   `native-initialization-error` is signalled.
9. Publish the state.

- **A failure in steps 3 to 8** closes whatever this attempt loaded, the
  extensions library first, and publishes nothing. The next call starts
  again at step 1.
- **The published state** is read under the same lock and used after the
  lock is released, so the lock is held for startup, never for a parse.

### 5.3 Saved images

A function in `sb-ext:*save-hooks*` (SBCL) and `ccl:*save-exit-functions*`
(CCL) runs before an image is saved (D12, finding 12). Under the startup
lock, it closes both libraries and clears the published state. So a saved
image never asks the loader to reopen cmark at a path from the machine
that built it, and holds no stale pointer. Its first call runs startup
again, on whatever machine it runs on. ECL doesn't save images.

### 5.4 Lifetimes and counters

- **`with-native-document`:**
  1. calls `cmark_parser_new` with the parse bits (§7.3); a null signals
     `native-parse-error`;
  2. attaches the selected extensions;
  3. feeds the input in one call, from a byte vector made by
     `cffi:make-shareable-byte-vector` and pinned with
     `cffi:with-pointer-to-vector-data` for that call only. cmark copies
     whatever it keeps;
  4. calls `cmark_parser_finish`; a null root signals
     `native-parse-error`;
  5. runs the body;
  6. on any exit, in `unwind-protect`: clears the document's alive flag,
     then frees the root, then the parser, each exactly once.
- **Every native accessor checks the alive flag** (D13). A document used
  after its scope signals an internal error instead of touching freed
  memory.
- **Render output** comes from `cmark_render_html` (given
  `cmark_parser_get_syntax_extensions` of the document's parser, so the
  parser outlives rendering), `cmark_render_plaintext` or
  `cmark_render_xml`. A null signals `native-render-error`. The buffer is
  decoded into a Lisp string, then freed through the allocator's `free`,
  in `unwind-protect`, never with `cffi:foreign-free`.
- **Counters,** under a lock: open parsers, roots and buffers, plus
  monotonic counts of the parsers and buffers ever created. Tests read
  them through internal functions.
- **Interrupts.** A non-local exit out of a foreign call, a timeout for
  instance, can leak cmark memory. It never frees anything twice: the
  alive flag is cleared before anything is freed.

### 5.5 Limits

Three special variables, defined in `/native-core` and re-exported (D10).
Each is checked before cmark does the work it guards. A breach signals
`resource-limit-exceeded`. The hard caps apply whatever a caller binds, so
the effective maximum is the variable's value, or the hard cap when that
is lower. A variable bound to anything but a non-negative integer signals
a `type-error`.

| Variable | Default | Hard cap | Checked | Guards |
|----------|---------|----------|---------|--------|
| `*max-input-octets*` | 1,048,576 (1 MiB) | 268,435,456 (256 MiB) | the input's UTF-8 length, before it is encoded, by every entry point | cmark's parse buffers, at most 3× the input: a NUL or a smart quote becomes 3 bytes |
| `*max-nodes*` | 1,000,000 | — | the table-cell bound, before parsing, by every entry point; the node count, while copying, by `parse` and `markdown->html-tree` | cmark's memory (finding 2) and the Lisp heap |
| `*max-output-octets*` | 67,108,864 (64 MiB) | 536,870,912 (512 MiB), half the abort threshold | the output bound, after parsing and before rendering, by `markdown->html` and `markdown->plaintext` | cmark's abort (finding 1) |

**The table-cell bound** is an upper bound on the table cells cmark would
build, computed from the input before parsing:
- The input is split into lines at LF, CR or CRLF.
- A *run* is a maximal sequence of lines that aren't blank. A blank line
  holds only spaces and tabs, as cmark's `is_blank` has it. A table ends
  at a blank line, so every table lies within one run.
- A *candidate* line holds only `>`, `|`, `:`, `-`, space, tab, VT and FF:
  container prefixes, then a delimiter row's characters (`table_marker`
  in `extensions/ext_scanners.re`). Each column of a delimiter row holds
  one run of `-`.
- The bound sums, over runs, the most `-` runs on any candidate line of
  the run, times the run's number of lines.

**The output bounds** are upper bounds on the bytes `cmark_render_html` and
`cmark_render_plaintext` would write. The output-bound walk sums per-node
terms over the parsed tree, derived from `src/html.c`, `src/plaintext.c`,
`src/render.c` and the extensions' renderers:
- **HTML:** each node's largest fixed markup (tags, attributes, newlines,
  and with `:sourcepos t` its `data-sourcepos`), plus 6 bytes for each byte
  of every string the node writes: 6 is the largest escape, `"` becoming
  `&quot;`, while a percent-escape is 3. A footnote reference writes its
  definition's label three times and adds its backref's markup. A
  definition writes its label once, and the section adds a constant.
- **Plaintext:** every line starts with the prefix of the node it is in:
  4 or the ordered marker's width for each enclosing item, and 4 for each
  enclosing footnote definition. Each node adds its content bytes
  (plaintext doesn't escape), its fixed markers, and the prefix plus one
  for each line it can start. A block starts at most two lines, a break
  one, and a code block one per line of its literal plus two. With
  `:width` above 0, text can start one line per byte.
- The constants are read off the C source during implementation. §8.4
  tests that the bounds never undercount.

**The remaining risk,** stated in the docstrings and in ADR-0016: on a
machine already short of memory, cmark's allocator can still abort.

## 6. The copier

`copy-native-tree` builds a detached AST from a parsed tree, inside
`with-native-document` (D1).

### 6.1 Walk

- It uses the native walker (§5.1): no recursion and no iterator to free.
- It builds nodes bottom-up through `make-node`, so the AST passes the
  schema. A schema violation would be a copier bug, and signals
  `invalid-ast-node`.
- It counts nodes, the document included, and signals
  `resource-limit-exceeded` past `*max-nodes*`.
- Text nodes stay split where cmark split them.

### 6.2 Classification

`(classify-node type-code extension type-string)` is pure (ADR-0008).
EXTENSION is `nil` for a node without an extension; otherwise the keyword
naming which of the five cached extension pointers the node's extension
pointer equals (`:table`, `:strikethrough`, `:autolink`, `:tagfilter` or
`:tasklist`), or `:other` when it equals none of them.

- **No extension:** the core type code decides, from constants checked
  against the pinned header.
- **`:table`:** the type string picks `:table`, `:table-header`,
  `:table-row` or `:table-cell`.
- **`:strikethrough`:** `:strikethrough`.
- **`:tasklist`,** on an item: `:task-item`.
- **`custom_block` and `custom_inline`:** signal
  `unsupported-extension-node`.
- **Anything else,** including `:tasklist` on a node that isn't an item, a
  table node with another type string, and `:autolink`, `:tagfilter` or
  `:other`: `:extension`, with the type string as `:type-name` and
  `:extension-name` `nil`. This can't occur under the pin.

### 6.3 Attributes

| Kind | Source |
|------|--------|
| `:document` | the parse's options, not cmark: `:profile`; `:extensions`, those attached, in the order `:table :strikethrough :autolink :tagfilter :tasklist`; `:options`, `:footnotes` and `:smart` when they are on, in that order |
| `:list` | `:type`, from the list type. For an ordered list, `:start`, and `:delimiter` (`:period` or `:paren`); a bullet list has neither. `:tight` |
| `:heading` | `:level` |
| `:code-block` | `:info`, the fence info; `:literal` |
| `:text`, `:code`, `:html-block`, `:html-inline` | `:literal` |
| `:link`, `:image` | `:destination`, the URL; `:title` |
| `:task-item` | `:checked` |
| `:table-cell` | `:align`: the table's alignment for the cell's column (`l`, `c`, `r`, or 0 for none). The column is the cell's position in its row |
| `:footnote-definition` | `:label`: its literal |
| `:footnote-reference` | `:label`: the literal of `cmark_node_parent_footnote_def` (finding 6). A reference without one signals `native-parse-error`: cmark has already turned dangling references into text |

### 6.4 Source positions

- With `:sourcepos t`, the parse sets `CMARK_OPT_SOURCEPOS` (finding 7).
  With `:sourcepos nil`, no position reaches the AST.
- A `start_line` of 0 means cmark has no position, and becomes `nil`. This
  happens for softbreaks, linebreaks and email autolinks.
- Every other position is copied as reported, as
  `((start-line . start-column) . (end-line . end-column))`, inverted
  ranges and zero columns included (ADR-0005). Columns are byte offsets.

### 6.5 Text

- **Input.** `utf8-length` measures the input first, for
  `*max-input-octets*`, and `encode-utf8` then fills the shareable vector.
  A lone surrogate (finding 11) is encoded as U+FFFD, so cmark only ever
  sees valid UTF-8. `CMARK_OPT_VALIDATE_UTF8` is set anyway, as a second
  guard.
- **`#\Nul`** reaches cmark as a zero byte, and cmark turns it into
  U+FFFD.
- **Output.** Every string cmark returns is decoded as UTF-8, with CFFI's
  decoder.

## 7. Public API, options and conditions

### 7.1 Entry points

```lisp
(parse markdown &rest options)                ; → a :document node
(markdown->html markdown &rest options)       ; → a string, from cmark's HTML renderer
(markdown->plaintext markdown &rest options)  ; → a string, from cmark's plaintext renderer
(markdown->html-tree markdown &rest options)  ; → (ast->html-tree (parse …) …)

*max-input-octets* *max-nodes* *max-output-octets* *cmark-gfm-libraries*
```

For example:

```lisp
(markdown->html "*hi*")       ; => "<p><em>hi</em></p>\n"
(markdown->html-tree "*hi*")  ; => ((:p nil (:em nil "hi")) "\n")
(let ((*max-input-octets* (* 16 1024 1024)))
  (parse large-document))
```

MARKDOWN is a string; anything else signals a `type-error`. Each entry
point checks all its options before any native call, then applies the
limits, then runs startup if needed.

### 7.2 Options

In each cell, the first value is the default. A dash means the function
doesn't take the option.

| Option | `parse` | `markdown->html` | `markdown->plaintext` | `markdown->html-tree` |
|--------|---------|------------------|-----------------------|-----------------------|
| `:profile` | `:gfm`, `:commonmark` | same | same | same |
| `:extensions` | the profile's: all five for `:gfm`, none for `:commonmark` | same | same | same |
| `:footnotes` | the profile's: `t` for `:gfm`, `nil` for `:commonmark` | same | same | same |
| `:smart` | `nil`, `t` | same | same | same |
| `:sourcepos` | `t`, `nil` | `nil`, `t` | — | — |
| `:softbreak` | — | `:newline`, `:space`, `:br` | same | same, as the tree option |
| `:unsafe-html` | — | `nil`, `t` | — | — |
| `:width` | — | — | `0` (no wrapping), or a column | — |
| `:raw-html`, `:link-policy`, `:document-wrapper` | — | — | — | as in ADR-0012 |

- **Values.** The booleans are exactly `t` or `nil`. `:extensions` is a
  proper list of distinct keywords from `:table`, `:strikethrough`,
  `:autolink`, `:tagfilter` and `:tasklist`, in any order; `nil` attaches
  none. `:width` is an integer from 0 to 2,147,483,647.
- **The profile only supplies defaults.** An explicit `:extensions` or
  `:footnotes` overrides it, so `:profile :commonmark :footnotes t` parses
  footnotes with no extensions attached.
- **Checking** is pure, in `/native-core`, and follows ADR-0014's D11.
  These signal: an odd-length list, an unknown key, a bad value, and a
  repeated or unknown extension. When a key repeats, the leftmost value
  wins, but every value must be valid.
- **Which condition.** `parse` signals `invalid-parse-option` for any
  problem. The three renderers signal `invalid-parse-option` for a bad
  `:profile`, `:extensions`, `:footnotes`, `:smart` or `:sourcepos`
  value, and `invalid-render-option` for everything else, including an
  unknown key and an odd-length list.
- **Defaults differ by function on purpose** (D14). An AST is worth more
  with positions, and HTML reads better without `data-sourcepos`.
  `markdown->html-tree` parses without positions, since the tree has none.

### 7.3 Option bits

- **Parse bits:** `VALIDATE_UTF8`, plus `FOOTNOTES`, `SMART` and
  `SOURCEPOS` when they are on.
- **HTML bits:** the parse bits, plus `HARDBREAKS` for `:softbreak :br`,
  `NOBREAKS` for `:softbreak :space`, and `UNSAFE` for `:unsafe-html t`.
- **Plaintext bits:** the parse bits, plus the same softbreak bits.

Rendering always carries the parse's bits (ADR-0006).

### 7.4 Conditions

All are subtypes of `commonmark-gfm-error`, and keep M1's slots and
report, "operation: reason: datum". Every slot defaults to `nil`.

| Condition | Extra slots | Signalled when |
|-----------|-------------|----------------|
| `invalid-option` (new) | — | the parent of the two below |
| `invalid-parse-option` (new) | — | §7.2 |
| `invalid-render-option` | — | §7.2 and ADR-0012. M1's condition, now under `invalid-option` |
| `resource-limit-exceeded` (new) | `limit`, `maximum` | a limit in §5.5. The datum is the value found, `limit` is the variable's symbol, and `maximum` is the effective maximum; the reason says when the hard cap applied |
| `native-error` (new) | — | the parent of the six below |
| `native-library-not-found` | `override`, `paths` | §5.2 steps 2 and 3. `paths` lists the directories searched, or the path that failed |
| `native-abi-mismatch` | `expected-version`, `found-version`, `paths` | §5.2 step 4 |
| `dynamic-ffi-unavailable` | — | §5.2 step 1. ECL is exercised in M4 |
| `native-initialization-error` | — | §5.2 steps 6 to 8 |
| `native-parse-error` | — | §5.1, §5.4 and §6.3 |
| `native-render-error` | — | §5.4 |

M1's `invalid-ast-node`, `invalid-html-tree` and
`unsupported-extension-node` are unchanged. A native document used after
release signals an internal condition that isn't exported (§5.4).

### 7.5 Threads

Every entry point can be called from several threads at once. Startup
happens once, under its lock, and each call has its own parser.

## 8. Tests and tooling

### 8.1 Pure suite additions

These run on all three Lisps, under `make check-purity`:
- **Header constants:** the type codes, option bits and list enums in
  `/native-core` are checked against `vendor/cmark-gfm/src/cmark-gfm.h`,
  read as text.
- **`classify-node`,** every rule, over synthetic inputs.
- **`resolve-cmark-libraries`,** over synthetic filesystem listings:
  - the special variable over the environment variable, and an
    empty-but-set variable;
  - a missing file, and the directory order;
  - a directory holding only one of the two libraries, which is skipped;
  - the multiarch and macOS filenames;
  - nothing found.
- **Options and bits:** every key and every bad value for each entry
  point, and which condition each one signals.
- **The limits' pure parts:** the effective maximum under each hard cap,
  the table-cell bound, and the per-node output-bound terms.
- **The UTF-8 encoder,** including lone surrogates and `#\Nul`.
- **The corpus reader** (§8.2): the counts per file.

### 8.2 The corpus

A pure reader in `/tests` mirrors `spec_tests.py`: `→` becomes a tab,
`disabled` examples are skipped, and each example keeps its section,
number and fence-line extensions. A fence-line `footnotes` sets
`:footnotes t`; any other name is added to `:extensions`.

| File | Base options | Enabled examples |
|------|--------------|------------------|
| `spec.txt` | `:profile :commonmark` | 670 |
| `regression.txt` | `:profile :commonmark` | 26 |
| `smart_punct.txt` | `:profile :commonmark :smart t` | 16 |
| `extensions.txt` | `:profile :gfm` | 30 |
| `extensions-full-info-string.txt` | `:profile :gfm`; `--full-info-string` has no version-1 option | 4 |
| `extensions-table-prefer-style-attributes.txt` | `:profile :gfm`; nor does `--table-prefer-style-attributes` | 1 |

### 8.3 Oracles

Four witnesses, each independent of the others (D4):

1. **cmark's own expectations.** `markdown->html` with `:unsafe-html t`,
   as cmark's harness runs, must reproduce each example's expected HTML
   byte for byte. That covers every enabled example of the first four
   files but the one `<IGNORE>`: 741 examples, with no exceptions
   (finding 8). This witness guards ADR-0011's weak spot: a broken corpus
   reader or a wrong option bit would otherwise let the tree and cmark
   agree while both are wrong.
2. **The HTML oracle** (ADR-0011). For all 747 enabled examples,
   `(html-tree->string (markdown->html-tree md …))` must equal
   `(markdown->html md …)`, under each `:softbreak` value. On examples
   whose AST has no raw HTML, `:link-policy :unsafe` is compared with
   `:unsafe-html t`.
3. **The XML oracle** (chez ADR-0010). A test-only writer in
   `/native-tests`, written against `src/xml.c` and the extensions'
   `xml_attr` functions, prints a copied AST in cmark's XML format,
   including the 40-space indentation cap and finding 13's three rules.
   For all 747 enabled examples, its output for the AST copied with
   `:sourcepos t` must equal `cmark_render_xml` with `SOURCEPOS`, from the
   same native document.
   - A guard changes one attribute of a copied AST and requires the
     comparison to report a difference, so a comparator that always says
     "equal" can't pass.
   - A second witness: the writer's output for
     `tests/fixtures/vocabulary.md` must equal the CLI's committed
     `vocabulary.xml`.
4. **The fixture ASTs** (the M1 hand-off). Each of the 28 cases, parsed
   with the defaults, equals its hand-built AST. The comparison ignores
   source positions and the document node's attributes, and merges
   adjacent `:text` nodes on both sides first. The cases' extra flags are
   render flags, so they don't change the parse.

- **Direct tests cover what no witness sees:**
  - reference labels as written, including a reference whose case differs
    from its definition's;
  - body-cell alignment;
  - the document's attributes;
  - `:sourcepos nil`.
- **The known footnote divergences.** If a corpus example hits one of
  ADR-0014's two divergences, it is listed by name with the reason, and
  the test requires it to keep differing, so a fix has to remove it from
  the list. A quick scan during this design found no such example; the
  oracle settles it.

### 8.4 Other native tests

- **Deep documents:** cmark's own stress inputs, compared byte for byte,
  the tree path against `markdown->html`. They are 50,000 nested block
  quotes; `*a **a ` 65,000 times, 130,000 levels of emphasis and strong;
  and 1,000-level nested lists. Each fits the default limits.
- **Crash guards:**
  - **Rejection.** Crafted inputs for each source of blowup: padded
    tables, footnote references, escaped quotes, reference-link
    expansion, and plaintext prefixes from nested lists with lazy lines.
    Each is rejected with `resource-limit-exceeded`. The monotonic
    counters show when: before any parser was created for the input and
    table-cell limits, and before any buffer for the output limit.
  - **Soundness.** Below the limits, neither bound undercounts: the
    table-cell bound against the cells actually copied, and the output
    bounds against the UTF-8 length of what was actually rendered. This
    holds on those inputs, on cmark's stress inputs, and on every corpus
    example under each option set the HTML oracle uses, and for plaintext
    at `:width` 0 and 20.
  - **Edges.** An input exactly at `*max-input-octets*` is accepted, and
    one byte more is rejected. That a binding above a hard cap is held to
    the cap is a pure test (§8.1), since a native one would need a
    256 MiB input.
- **Every native condition is signalled at least once:** a bad override
  for `native-library-not-found`; internal wrappers temporarily redefined
  to report another version (`native-abi-mismatch`), a null extension
  (`native-initialization-error`), a null root (`native-parse-error`) and
  a null buffer (`native-render-error`).
- **Lifetimes:**
  - the open counters are zero at the end of the suite, and after every
    failure-path test;
  - failure paths without hooks in production code: real failures (a
    limit hit mid-copy, a non-local exit from the body), and tests that
    temporarily redefine an internal wrapper around a cmark call to fail
    or return null;
  - a document used after release signals;
  - parse and render loops run with forced collections
    (`trivial-garbage:gc :full t`), and a render stress test runs large
    documents repeatedly;
  - the ABI assumptions: the allocator's three slots are non-null and
    distinct, and checked and unchecked task items read differently.
- **Threads:** concurrent parses and renders give the same results as
  sequential ones. After an internal reset, a first call from many threads
  at once publishes one startup state, counted by an internal counter.
- **Saved image:** a child SBCL parses, then saves an image with
  `sb-ext:save-lisp-and-die`. A second child starts from that image,
  reports that nothing is published yet, then parses.
- **UTF-8 and positions:** non-ASCII text round-trips through every entry
  point; a NUL and a lone surrogate both become U+FFFD; columns count
  bytes; a multi-line code span leaves later positions right.
- **The API:** every option through each entry point. Option errors come
  before any parser is created.
- **Discovery,** both ways: with `CL_COMMONMARK_GFM_LIBS` set, as in the
  container, the resolved paths are the override's; unset, as in CI, they
  come from the fixed directory list. A test asserts whichever applies.

### 8.5 Runner, Makefile and CI

- **`tests/run-native.lisp`** is like `tests/run.lisp`. It runs
  `cl-commonmark-gfm/native-tests` under the quiet reporter, prints the
  counts, fails when no tests ran, and fails unless the open counters are
  zero on exit.
- **`make check-native`** runs it on each Lisp in `NATIVE_LISPS`, which
  defaults to `sbcl`. M4 adds CCL and ECL. `make test` becomes
  `check-purity`, `check-fixtures` and `check-native`.
- **CI:** `.github/workflows/ci.yml` doesn't change. `make deps` installs
  the new dependencies, and `make -k test` runs the native suite with no
  override set, so discovery searches `/usr/lib/x86_64-linux-gnu`
  (ADR-0013).

### 8.6 Seen to fail

Each check is seen to fail under a targeted change:
- change one converter rule, or drop one copied attribute: the HTML or
  XML oracle fails;
- flip one option bit in the mapping: cmark's expectations fail;
- edit one hand-built fixture AST: the fixture comparison fails;
- skip the table-cell check: the rejection now comes after a parser was
  created, and the test fails;
- drop a term from an output bound: soundness fails;
- skip one `free`: the counters fail;
- remove the save hook: the restarted child finds state already
  published;
- put back a recursive walk: the deep tests fail.

## 9. Documents

- **Rules live here, once** (D17). ADRs record decisions with their
  reasons and link to sections of this spec. The plan summarizes and
  links. `progress.md` holds checklists and close-outs.
- **New ADRs:**

  | ADR | Decision | Slice |
  |-----|----------|-------|
  | 0015 | Walks loop over explicit stacks, with no depth limit; `walk-ast`; footnote places keyed by owner and ordinal (§4) | M2a |
  | 0016 | Three limits keep cmark from aborting or exhausting memory (§5.5), with findings 1 to 4 as evidence | M2b |
  | 0017 | The public API: entry points, options and their defaults, conditions, re-exports. How it runs: startup, bordeaux-threads, save hooks, the alive flag (§5.2 to §5.4, §7) | M2b |
  | 0018 | Copying and checking the tree: labels, positions and text (§6), the four oracles and the corpus (§8.2, §8.3) | M2b |

- **Plans and branches:** one implementation plan per slice, written after
  this spec is approved. Branches `m2a-stack-safe-walks`, then
  `m2b-native-layer`.
- **`progress.md`:** the M2 checklist, split into M2a and M2b; new global
  constraints (no recursion over tree depth; the three limits; the open
  counters at zero after every native suite); a close-out after each
  slice.
- **`/docs`** stays for M5, as the plan says. The entry points and the
  limit variables get full docstrings now, the remaining risk included.

## 10. Corrections this design makes elsewhere

Each amended ADR gets a status line naming the ADR that amends it.

- **ADR-0005,** finding 2: after parsing, a reference's literal is its
  number, and its label comes from `cmark_node_parent_footnote_def`
  (ADR-0018).
- **ADR-0011:** the whole corpus runs in M2, not M3, and cmark's
  expectations and its XML join as witnesses (ADR-0018).
- **ADR-0013:** the steps table. The native suite and the full oracle
  arrive in M2.
- **ADR-0014:** footnote places are keyed by owner and ordinal, not by
  path (ADR-0015). Its hand-offs to M2 (the copier's labels, the two
  divergences and the fixture ASTs) are settled in M2b (ADR-0018).
- **The plan (`cl-commonmark-gfm.org`):**
  - the systems table (§3) and the AST exports (`walk-ast`);
  - the ABI rule "C option bitsets use an explicit unsigned 32-bit CFFI
    type" becomes "as the header declares them: `int`";
  - the API sketch (§7.1), and the conditions table (§7.4);
  - the Tests section (§8);
  - the milestones: M2 as designed here, and M3 left with unknown
    extensions, version probes and property tests;
  - two new risk rows: cmark aborting or running out of memory (§5.5),
    and deep trees (§4);
  - decision-log entries 21 to 24, for ADRs 0015 to 0018.
- **`progress.md`:** the M1 close-out's "Handed to M2" items are ticked as
  they land.

## 11. Out of scope

- **M3:** unknown extensions, version probes, and the property-based
  testing evaluation (ADR-0007).
- **M4:** the native suite on CCL and ECL, ECL's `:dffi` check in
  practice, and static deployment.
- **M5:** user documentation in `/docs`, and the release.
- **Other cmark options** (liberal HTML tags, double-tilde strikethrough,
  GitHub `pre` languages, table style attributes, full info strings). Each
  can be added later with an ADR, without breaking callers.
- **The two footnote divergences** stay documented (ADR-0014), unless the
  corpus or a real document hits one.
- **Memory pressure:** cmark's allocator can still abort on a machine
  already short of memory (§5.5), and an interrupted foreign call can leak
  (§5.4).
