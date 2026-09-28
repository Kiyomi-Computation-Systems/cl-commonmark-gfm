# ADR-0011: cmark's HTML is the tree's oracle; `vendor/cmark-gfm` submodule

- **Status:** Accepted; amended by ADR-0014 (2026-09-27)
- **Date:** 2026-09-27
- **Scope:** AST → HTML tree mapping, tree tests, corpus source
- **Spec:** [M0 close design](../2026-09-27-m0-close-design.md) §4.3, §4.6,
  §4.7
- **Related:** ADR-0002 (the pin), ADR-0010 (tree and serializer),
  ADR-0012 (render options)
- **Prior art:** chez-cmark-gfm ADR-0012

## Context

`ast->html-tree` must produce the right tree for every node. Expected trees
written by hand can be wrong in the same way as the code. cmark emits no
tree, but it does emit HTML, and our serializer turns a tree into HTML.
The pinned cmark-gfm tag ships a corpus of example documents.

## Decision

### The mapping follows cmark

Each node takes the shape cmark 0.29.0.gfm.13's `html.c` and extension
renderers produce, under the options in effect. The oracle settles every
detail.

- **Links and images:** `href` and `src` carry cmark's percent-encoding
  (houdini's `HREF_SAFE` set). The serializer then only entity-escapes
  them. An image's `alt` is the plain text of its children.
- **Task items:**
  `(:li nil (:input ((:type "checkbox") (:disabled ""))) " text")`, with
  `(:checked "")` before `(:disabled "")` when ticked. There is **no
  `task-list-item` class**; this corrects the plan.
- **Footnote references:**
  `(:sup ((:class "footnote-ref")) (:a ((:href "#fn-1") (:id "fnref-1") (:data-footnote-ref "")) "1"))`.
- **Footnote definitions** are collected at the end of the document:
  `(:section ((:class "footnotes") (:data-footnotes "")) (:ol nil (:li ((:id "fn-1")) … backref …)))`.
  Numbering, ids for repeated references, and the back-reference
  `aria-label` follow cmark exactly. Lisp computes them from the AST's
  labels, in order of first reference.
- **Tables:** `:thead` wraps the `:table-header` row, `:tbody` the others.
  `align` attributes come from each cell's `:align`.
- **Tight lists** unwrap their paragraphs, as cmark does.

### The oracle

- For every example in the pinned corpus (`test/spec.txt`,
  `test/extensions.txt`, `test/regression.txt` and the other `test/*.txt`
  files), `(html-tree->string (ast->html-tree (parse md)))` must equal
  `(markdown->html md)` **byte for byte**, under each oracle-backed option
  (ADR-0012). The serializer under test is the public one.
- `:link-policy :unsafe` is compared with `CMARK_OPT_UNSAFE` output only on
  examples whose AST has no `:html-inline` or `:html-block` node. That cmark
  option also emits raw HTML verbatim, which `:omit` deliberately does not.
- The oracle needs a real parse, so it arrives with the native layer:
  - **M2** runs it for the node families M2 copies;
  - **M3** runs it over the whole corpus.
- **M1**'s pure tests use hand-built ASTs with the expected trees written
  out, plus direct serializer tests, including every `invalid-html-tree`
  case.

### The corpus source

`vendor/cmark-gfm` is a git submodule pinned to commit
`587a12bb54d95ac37241377e6ddc93ea0e45439b` (tag `0.29.0.gfm.13`). It is
**development-only**: nothing is built from it and nothing ships from it.
It supplies:

- the corpus files;
- `src/cmark-gfm.h`, for the core type-code and option-bit checks;
- `COPYING`, for the `NOTICE` check.

Two Makefile targets guard it:

- **`make check-pins`** fails if the submodule's recorded commit differs
  from ADR-0002. It reads the recorded gitlink, so it needs no checkout.
- **`make check-notice`** fails unless `NOTICE`'s COPYING section equals
  `vendor/cmark-gfm/COPYING` byte for byte. A missing checkout fails, with
  a message naming `git submodule update --init`. It never skips.

## Consequences

- A wrong tag, attribute, attribute order, child, escape or newline shows
  up as a byte difference against an expectation cmark wrote, not us.
- `:raw-html :text` and `:document-wrapper` have no cmark equivalent, so
  they sit outside the oracle (ADR-0012).
- Both sides of the comparison share one parse. A wrong option bit would
  make them agree while both are wrong; the option-bit check against
  `cmark-gfm.h` guards that, not this oracle.
- Byte equality is a property of our serializer. Another HTML serializer
  given the same tree may produce equivalent but different bytes.
- A pin bump means moving the submodule, which `check-pins` ties to
  ADR-0002.
