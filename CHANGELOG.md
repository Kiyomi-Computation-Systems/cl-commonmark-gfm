# Changelog

Each release's notable changes, newest first. Versions follow
[Semantic Versioning](https://semver.org).

## Unreleased

## 0.1.0 — 2026-10-11

The first release: GitHub Flavored Markdown for Common Lisp, through
cmark-gfm 0.29.0.gfm.13, on SBCL, CCL and ECL, on Linux and macOS.

### Added

- Four functions: `markdown->html`, `markdown->html-tree`,
  `markdown->plaintext`, and `parse`, which gives an AST.
- Options for all four: the `:gfm` and `:commonmark` profiles, the five
  GFM extensions, footnotes, smart punctuation, source positions, soft
  breaks and wrapping.
- An AST of immutable nodes, with readers, `walk-ast`, `map-ast`,
  `fold-ast`, `transform-ast`, `make-node`, `copy-node` and `node=`.
- An HTML tree: `ast->html-tree` and `html-tree->string`, to change HTML
  as Lisp data before writing it out.
- Safe by default: raw HTML becomes a comment, and dangerous URLs are
  blanked. `:unsafe-html` and `:link-policy :unsafe` opt out, for
  Markdown you trust.
- Size limits, `*max-input-octets*`, `*max-nodes*` and
  `*max-output-octets*`, which refuse a document before cmark-gfm could
  end the process on it.
- A guard against the one known cmark-gfm bug that reads memory it
  doesn't own, a `[` before an entity for `^` while footnotes are on: it
  signals `unsupported-input`.
- Calls from any number of threads.
- Finding cmark-gfm's libraries in the usual directories, or where
  `*cmark-gfm-libraries*` or `CL_COMMONMARK_GFM_LIBS` names them, and
  checking their version as they start.
- ECL programs with cmark-gfm linked in, for an ECL without dynamic FFI,
  or a machine without cmark-gfm.
- A condition for each of the library's own errors, under
  `commonmark-gfm-error`.
- Documentation, with every Lisp example run as a test.

### Known limits

- CCL on Apple silicon, under Rosetta, is untested.
- Windows isn't supported.
