# ADR-0005: The shim classifies nodes by type code; vocabulary verified against 0.29.0.gfm.13

- **Status:** Accepted
- **Date:** 2026-09-27
- **Scope:** shim ABI, AST vocabulary, copier
- **Evidence:** `tests/fixtures/vocabulary.md` and cmark-gfm's XML for it,
  `tests/fixtures/vocabulary.xml`. `make check-vocabulary` re-derives the XML
  from the pinned CLI and diffs it. Source references are to the
  0.29.0.gfm.13 tree.

## Context

The first plan draft had the shim return each node's type *string*
(`cl_cmark_node_type_name`) and listed `:autolink` and `:task-item` among
the node kinds. None of this had been checked against a real release.

## Findings

1. **Footnote nodes have no type string.** `cmark_node_get_type_string`
   (`src/node.c`) has no case for `CMARK_NODE_FOOTNOTE_DEFINITION` or
   `CMARK_NODE_FOOTNOTE_REFERENCE`. It returns `"<unknown>"`, and the XML
   renderer prints `<<unknown>>`. Their type *codes* are fixed in
   `cmark-gfm.h`.
2. **Footnotes are an option, not an extension:** `CMARK_OPT_FOOTNOTES`
   (`1 << 13`). The CLI lists `footnotes` among extensions only as spelling.
   `cmark_node_get_literal` returns the label for both footnote kinds. The
   reference's number lives in a private struct field.
3. **Autolinks are ordinary `link` nodes.** There is no autolink node kind.
   Email autolinks, and the empty text node after one, carry no source
   position.
4. **Task items are `CMARK_NODE_ITEM` owned by the `tasklist` extension.**
   The type string is `"tasklist"`. The checked state comes from
   `cmark_gfm_extensions_get_tasklist_item_checked`.
5. **Tables use four type strings:** `table`, `table_header` (the header
   row), `table_row`, `table_cell`. The header row is marked explicitly, so
   `thead` is known, not inferred. Alignment is per column, on the table
   (`cmark_gfm_extensions_get_table_alignments`). The table, row and cell
   type codes are assigned at registration, so they are dynamic.
6. **The GFM metadata accessors are public** API in
   `extensions/cmark-gfm-core-extensions.h`. Nothing needs a private header.
7. **Tagfilter changes HTML rendering only.** The AST keeps
   `<script>…</script>` as an `html_block`.
8. **Source positions are reported as-is and can look wrong:**
   - an end before the start (`23:1-22:0` on an `html_block`);
   - end column 0 (`9:0` on a list);
   - a child starting before its parent (a `www.` autolink at `8:3` inside a
     paragraph at `8:4`);
   - absent altogether (finding 3).
9. **Empty text nodes occur**, e.g. the trailing spaces of a hard line
   break leave a `text` node with literal `""`.
10. **`custom_block` / `custom_inline` never come from parsing.** Only API
    callers build them.

## Decision

- **The shim classifies every node into a stable project kind**, exposed as
  `int cl_cmark_node_kind(void *node)`:
  - For a node **without an extension**, classify by `cmark_node_get_type`.
    These are the core codes fixed in the header, footnotes included.
  - For a node **with an extension**, classify by its extension name plus
    type string: `table`, `table_header`, `table_row`, `table_cell`,
    `strikethrough`, `tasklist`.
  - Anything else is `CL_CMARK_KIND_EXTENSION`. The copier then asks
    `cl_cmark_node_extension_name` and `cl_cmark_node_type_string` and emits
    `:extension`.
  - `custom_block` and `custom_inline` are `CL_CMARK_KIND_UNSUPPORTED`. The
    copier signals `unsupported-extension-node` for them.
- **Vocabulary:** the table in the plan's "AST vocabulary" section. It has no
  `:autolink` kind; it adds `:table-header`, `:footnote-definition` and
  `:footnote-reference`; `:task-item` maps from `tasklist`.
- **Alignment is copied onto each `:table-cell` as `:align`**, looked up
  by column index. A cell then renders without its table, and pure rewrites
  cannot desynchronize a table-level vector from its cells.
- **Source positions may be `nil`.** The AST stores what cmark reports and
  never repairs it.
- **Footnote numbers are computed in Lisp** (first-reference order) during
  SXML conversion. The AST carries labels only.
- **The SXML raw-HTML policy is the only guard on raw HTML.** Tagfilter does
  not sanitize the AST.

## Consequences

- Classification sits behind one shim function. A pin bump that renames a
  type string, or adds a core type, fails `check-vocabulary` first and the
  native kind tests second.
- The Lisp side never sees cmark's dynamic extension type codes.
