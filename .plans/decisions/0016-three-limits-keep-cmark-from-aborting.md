# ADR-0016: Three limits keep cmark from aborting or exhausting memory

- **Status:** Accepted; amended 2026-10-01, after M2b's review (spec
  §5.5, finding 17): every entry point checks all three bindings first;
  and the bound on footnote backrefs is tighter, counting the input's
  possible reference openers less the definitions kept
- **Date:** 2026-09-30
- **Scope:** `*max-input-octets*`, `*max-nodes*` and `*max-output-octets*`;
  the table-cell and output bounds; `resource-limit-exceeded`
- **Spec:** [M2 design](../2026-09-30-m2-native-layer-design.md) §1, §2 (D10,
  findings 1 to 4 and 17), §5.5, §7.4, §8.4, §11
- **Related:** ADR-0015 (no depth limit), ADR-0017 (the entry points that
  apply the limits), ADR-0019 (the input guard, applied with the limits)

## Context

M2's goal is that no Markdown input can crash the process by itself
(spec §1). cmark kills the process in two ways, and no Lisp handler can
catch either (finding 1):
- `cmark_strbuf_grow` calls `abort()` when a buffer would pass
  1,073,741,823 bytes (`src/buffer.c`);
- the default allocator calls `abort()` when `calloc` or `realloc` fails
  (`src/cmark.c`).

Small inputs get there (findings 2 to 4):
- **Padded table cells.** A row shorter than its table's header gets real,
  empty cells while cmark parses. cmark caps them per table, not per
  document. 1,111,660 bytes of such tables made the CLI abort, and
  252,650 bytes peaked at 6.6 GB of memory.
- **Footnote references** multiply HTML 69 times: 40,010 bytes of `[^a]`
  render to 2,764,532 bytes.
- **Plaintext** writes each enclosing list item's indentation at the start
  of every line: 8,002 bytes rendered to 800,200. Nesting built up over
  many lines has no cap.

## Decision

### Three limits, each checked before the work it guards (D10)

`*max-input-octets*`, `*max-nodes*` and `*max-output-octets*` are special
variables in `/native-core`, re-exported by `cl-commonmark-gfm`. Their
defaults, their hard caps, and where each is checked are spec §5.5's
table. A breach signals `resource-limit-exceeded` (spec §7.4).

Every check runs before cmark does the work, since the abort can't be
caught once it happens:
- **Input octets** guard cmark's parse buffers, which hold at most three
  times the input. The input is measured before it is encoded, so one
  that's too large is never encoded.
- **Nodes** guard cmark's memory and the Lisp heap. Padded cells are built
  while cmark parses, so a count taken afterwards would come too late. The
  table-cell bound is worked out from the text, before parsing. The copier
  also counts the nodes it builds (spec §6.1).
- **Output octets** guard the renderers' abort. cmark renders into its own
  buffer, in one call, and aborts inside that call. So the output bounds
  are summed over the parsed tree, after parsing and before rendering.

The bindings come first: every entry point checks all three before any
native call (spec §5.5). So a bad binding fails every call at once, before
cmark does any work, even a call that never applies that limit.

### Bounds that never undercount

The table-cell bound and the output bounds (spec §5.5) are upper bounds,
read off the pinned C source. They take the worst case, such as every byte
of text escaped as `&quot;`. Spec §8.4 tests that they never undercount.

References inside a dropped definition leave no node, but their backrefs
still render (finding 17). So the walk can't count those backrefs, and the
input bounds them: its possible reference openers, less the definitions
kept, since each definition's own `[^label]:` is one of those openers
(spec §5.5).

### Hard caps

A caller can raise a limit above its default, but not past its hard cap
(spec §5.5). The two caps keep cmark's buffers under the abort threshold:
- at the 256 MiB input cap, the parse buffers hold at most 768 MiB;
- the output cap, 512 MiB, is half the threshold.

### Rejected

- **No limits, and a documented risk.** It misses M2's goal: an input of
  about a megabyte aborts the process (finding 2), and nothing in Lisp can
  catch the abort.
- **A depth limit.** ADR-0015 declined it: it would reject documents cmark
  parses, and the walks no longer need one. Nor would it stop findings 2
  and 3: neither input is deep.

## Consequences

- Callers bind the variables for larger inputs:
  `(let ((*max-input-octets* (* 16 1024 1024))) (parse large-document))`
  (spec §7.1).
- The hard caps hold whatever a caller binds. No input above 256 MiB is
  parsed, and `markdown->html` and `markdown->plaintext` render nothing
  whose output bound passes 512 MiB.
- `*max-nodes*` has no hard cap, so a caller who raises it decides how much
  memory a parse may take.
- The bounds overcount. A document can be rejected whose real output would
  have fit.
- Every entry point makes a pass over the input before parsing, and the
  two renderers make a walk over the parsed tree before rendering.
- The per-node terms come from the pinned renderers. A pin bump can change
  them; the soundness tests (spec §8.4) are what would catch an undercount.
- **The remaining risk:** on a machine already short of memory, cmark's
  allocator can still abort (spec §5.5, §11). The docstrings of the entry
  points and of the limit variables say so.
