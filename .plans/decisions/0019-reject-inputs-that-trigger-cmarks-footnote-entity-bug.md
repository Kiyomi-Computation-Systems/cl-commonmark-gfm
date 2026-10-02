# ADR-0019: Reject inputs that trigger cmark's footnote-entity bug

- **Status:** Accepted; amended 2026-10-01, after M2b's second review: a
  consequence no longer says ADR-0017's body is unchanged, since M2b's
  review amended it
- **Date:** 2026-10-01
- **Scope:** the input guard, in every entry point; `unsupported-input`
- **Spec:** [M2 design](../2026-09-30-m2-native-layer-design.md) §1, §2
  (finding 16), §5.6, §7.1, §7.4, §8.4, §11
- **Amends:** ADR-0017 (a new condition, `unsupported-input`; each entry
  point applies the input guard with the limits, before any native call)
- **Related:** ADR-0002 (the pin), ADR-0006 (`:gfm` enables footnotes),
  ADR-0016 (the limits)

## Context

M2's goal is that no Markdown input can crash the process by itself
(spec §1). M2b's Task 9 found inputs that can (finding 16):
- **The bug.** cmark copies a footnote reference's label from the text
  after its `[`, as if that text pointed into the input
  (`handle_close_bracket`, `src/inlines.c`). An entity that decodes to `^`
  gets its own 1-byte buffer instead (`handle_entity`). So the copy reads
  past that buffer, and cmark then frees it while the label still points
  into it.
- **What it does.** With footnotes on, the pinned CLI renders heap bytes
  for `[&#94;aaaa]`, and its HTML stops short. A long label faulted SBCL
  during the parse.
- **No fix upstream.** cmark-gfm's newest commit, `499789b`, has the same
  code.
- **Footnotes are on by default.** `:gfm` is the default profile, and it
  turns them on (ADR-0006, spec §7.2). So a call with no options is
  exposed.

The limits (ADR-0016) can't help: `[&#94;aaaa]` is 11 bytes.

## Decision

### Reject the input before parsing

With footnotes on, every entry point rejects an input in which a `[` is
immediately followed by an entity that decodes to `^`. Spec §5.6 states
which entities those are. The guard runs with the limits, after the
options are checked and before any native call (spec §7.1). So a rejected
input never reaches cmark, and no parser is created (spec §8.4).

### Read the raw input

The guard can't wait for cmark's parse, since the parse is what goes wrong.
So it reads the raw input, and matches the entities that cmark's own
decoder, `houdini_unescape_ent`, turns into `^` (spec §5.6). Near misses,
such as `&hat;` or nine digits, still parse (spec §8.4).

### Only with footnotes on

The faulty branch parses footnote references (finding 16). With footnotes
off, cmark never reaches it, so the guard doesn't run (spec §5.6).

### A new condition, `unsupported-input`

A match signals `unsupported-input`, a new subtype of
`commonmark-gfm-error` that isn't a `native-error` (spec §7.4). Nothing
failed to load or run: the pinned cmark-gfm can't parse this input safely,
on any machine. Spec §7.4 gives the datum and the reason.

### Rejected

- **Rewriting the `[` as `&#91;`** before parsing. The output would change
  silently: a link whose text starts with an encoded caret, such as
  `[&#94;a](/url)`, would lose its link, and positions after the `[` on its
  line would shift by 4 bytes. The guard rejects that link too, but says
  so.
- **Documenting the bug, and nothing else.** Heap bytes would reach the
  output, and a long label can fault the process. That misses M2's goal
  (spec §1).
- **Reusing `native-parse-error`.** Callers would read it as cmark failing,
  not as a problem with their input. A `native-error` means a missing or
  broken library, or a native call that failed (spec §7.4).

## Consequences

- ADR-0017 is amended, not replaced: its entry points apply the guard with
  the limits, and its conditions gain `unsupported-input`. Its status line
  says so.
- **Over-matching.** The guard also rejects the pattern where cmark would
  parse it safely, such as inside a code block or after an escaped `\[`
  (spec §5.6). Such a document parses with `:footnotes nil`, without its
  footnotes.
- **No check with footnotes off,** the `:commonmark` default. These inputs
  then parse, and render the entity as text (spec §8.4).
- **One new exported condition,** which `cl-commonmark-gfm` re-exports with
  the rest (spec §3). A handler for `commonmark-gfm-error` catches it; one
  for `native-error` doesn't.
- **Other bugs in cmark's parser remain a risk** (spec §11). The guard
  covers the one found. The corpus, cmark's stress inputs and the oracles
  found no other, but a fault in C is beyond any Lisp check.
