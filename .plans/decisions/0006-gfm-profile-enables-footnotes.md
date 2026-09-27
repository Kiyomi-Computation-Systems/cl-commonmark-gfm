# ADR-0006: The `:gfm` profile enables footnotes

- **Status:** Accepted
- **Date:** 2026-09-27
- **Scope:** default parse options

## Context

GitHub renders footnotes. cmark-gfm leaves them off unless the caller sets
`CMARK_OPT_FOOTNOTES`, an option bit rather than a syntax extension
(ADR-0005). So the plan's `:gfm` profile, which listed only the five core
extensions, would not have matched GitHub.

## Decision

- `:gfm` = tables, strikethrough, autolinks, tag filter, task lists, **plus
  `CMARK_OPT_FOOTNOTES`**.
- `:commonmark` sets neither extensions nor footnotes.
- Footnotes are an option like the others, so a caller can turn them off
  under `:gfm`.
- The document's `:options` attribute records whether footnotes were on.

## Consequences

- `:footnote-definition` and `:footnote-reference` appear under the default
  profile. Their HTML-tree shape is settled by ADR-0010/0011 (cmark's
  footnote HTML).
- HTML rendering uses the same option set as parsing.
