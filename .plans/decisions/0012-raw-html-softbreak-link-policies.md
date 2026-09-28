# ADR-0012: Raw-HTML, softbreak and link policies

- **Status:** Accepted; amended by ADR-0014 (2026-09-27)
- **Date:** 2026-09-27
- **Scope:** `ast->html-tree` options, HTML tree safety
- **Spec:** [M0 close design](../2026-09-27-m0-close-design.md) §4.4
- **Related:** ADR-0005 (tagfilter does not sanitize the AST), ADR-0010
  (the serializer does not check URLs), ADR-0011 (the oracle)
- **Prior art:** chez-cmark-gfm ADR-0011 (no trusted raw-HTML mode)

## Context

The AST keeps raw HTML verbatim, `<script>` included; tagfilter changes
cmark's HTML output only (ADR-0005). So the HTML tree is where raw HTML and
dangerous URLs must be handled.

The plan listed three raw-HTML modes: `:preserve` (a tagged value for a
downstream renderer), `:drop` and `:text`.

## Decision

`ast->html-tree` validates its options **before** converting anything. An
unknown key or value signals `invalid-render-option`.

| Option | Values (default first) | cmark equivalent (oracle) |
|--------|------------------------|---------------------------|
| `:raw-html` | `:omit`: `(:*comment* nil " raw HTML omitted ")` for each `html_inline` / `html_block`<br>`:text`: the literal as an ordinary string | `:omit` = default safe HTML; `:text` has none, so it gets direct tests |
| `:softbreak` | `:newline` → `"\n"`<br>`:space` → `" "`<br>`:br` → `(:br nil) "\n"` (ADR-0014) | default, `CMARK_OPT_NOBREAKS`, `CMARK_OPT_HARDBREAKS` |
| `:link-policy` (link `href`, image `src`) | `:safe`: blank the URL when it starts, case-insensitively, with `javascript:`, `vbscript:`, `file:` or `data:`, except `data:image/png`, `data:image/gif`, `data:image/jpeg` and `data:image/webp`<br>`:unsafe`: keep every URL | default; `CMARK_OPT_UNSAFE` for links only |
| `:document-wrapper` | `nil` or a non-void element keyword (ADR-0014) | none |

- `:safe` is cmark's own rule, `_scan_dangerous_url`.
- **No trusted raw-HTML mode.** A caller who needs the markup reads
  `:literal` from the AST's `:html-inline` / `:html-block` nodes.

## Consequences

- From the plan's three modes: `:text` stays, `:omit` replaces `:drop` and
  leaves cmark's comment where the markup was, and `:preserve` is gone.
- Every tree is safe by default: raw HTML becomes a comment and dangerous
  URLs are blanked, exactly as cmark's default HTML does.
- Raw markup never enters the tree as markup. `:text` makes it a string,
  which the serializer escapes.
- `:omit`, the softbreak values and `:link-policy` are oracle-tested
  (ADR-0011). `:unsafe` is compared only on examples with no raw HTML
  nodes, since `CMARK_OPT_UNSAFE` also emits raw HTML verbatim.
- `:raw-html :text` has no cmark equivalent, so it gets direct tests.
- The link policy runs only inside `ast->html-tree`. URLs a user adds to a
  tree later are not checked (ADR-0010).
- A typo in an option fails loudly instead of silently falling back to a
  default.
