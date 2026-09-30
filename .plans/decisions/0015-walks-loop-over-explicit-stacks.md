# ADR-0015: Walks loop over explicit stacks

- **Status:** Accepted
- **Date:** 2026-09-30
- **Scope:** the AST walks, `ast->html-tree` and its footnote pre-pass,
  `html-tree->string`, `proper-list-p`
- **Spec:** [M2 design](../2026-09-30-m2-native-layer-design.md) §1, §2 (D2,
  D8, D9, finding 5), §3, §4
- **Amends:** ADR-0014 (footnote places are keyed by owner and ordinal, not
  by path)
- **Related:** ADR-0007 (Parachute), ADR-0010 (the serializer)

## Context

Every M1 walk was recursive, one Lisp call per level of the tree
([M1 spec](../2026-09-27-m1-pure-core-design.md) §9). The M2 design measured
them on a ladder of depths, in the main thread and in spawned threads alike
(finding 5):

- SBCL's `node=` ran out of stack first: fine at 2,000 levels, out by 4,000;
- the converter and the serializer ran out between 8,000 and 32,000 levels,
  depending on the Lisp;
- trees 300,000 children wide were fine on all three Lisps.

cmark goes much deeper: its own stress tests nest 130,000 levels
(`test/pathological_tests.py`). M1 left M2 a choice: iterative walks, or a
documented depth limit that signals a project condition.

Two M1 costs grow with depth even without recursion:
- the footnote pre-pass keys each place by its path from the root, in
  `equal` hash tables. In a deep chain every path starts with the same
  elements, and `sxhash` hashes only the first few, so lookups degrade to
  scans;
- the serializer finds an element that contains itself by scanning the list
  of open elements at every element, which is quadratic in depth.

M1's code review handed on two more items: a non-copying child accessor,
since `node-children` copies on every call, and one `proper-list-p` in place
of two copies.

## Decision

### No depth limit (D2)

Every walk over an AST or an HTML tree loops over an explicit stack
(spec §4). M1's output rules, conditions and tests stand.

### `walk-ast` is the one AST traversal (D8)

`walk-ast` is exported from `cl-commonmark-gfm.ast`, with the protocol in
spec §4.1. `fold-ast`, `map-ast`, `transform-ast` and every AST walk in the
HTML tree are built on it. `node=` compares two trees in step, so it has a
loop of its own (spec §4.2).

- The explicit stack is written and tested once, not once per walk.
- `walk-ast` reads child lists without copying, which answers M1's call for
  a non-copying accessor. The child list itself stays internal.

### The converter is a port of `html.c`'s event loop (D9)

cmark's HTML renderer is already a loop: it hands each enter and exit event
from `cmark_iter` to `S_render_node` (`src/html.c`).
`ast->html-tree` becomes the same loop over `walk-ast`'s events, keeping
M1's rules (spec §4.3). Each converter rule now sits beside the C code the
oracle runs, event by event.

### Footnote places are keyed by owner and ordinal (D9)

A reference place is keyed by its owner, the body or the innermost
definition place around it, and by its ordinal among that owner's
references (spec §4.4). ADR-0014's footnote rules are unchanged.

- Two small integers hash well at any depth; a path doesn't.
- Like a path, the key names a place, not a node object: one node at two
  places is still two references.
- Each definition renders away from its place: after the body, and after
  any definition around it. So the converter meets references in a
  different order from the tree. A count kept per owner still comes out the
  same in the pre-pass and in the converter; one count over the whole tree
  would not.

### The serializer's `eq` set and one `proper-list-p`

- The serializer loops over a stack of open elements, and looks each element
  up in an `eq` hash set of the open ones to find one that contains itself
  (spec §4.5). The check stays linear at any depth.
- One `proper-list-p`, a loop over Floyd's two pointers, replaces the two
  copies (spec §4.6). It lives in `cl-commonmark-gfm/util`, a new system
  (spec §3), so the AST and the HTML tree share one copy.

### Rejected

- **A depth limit enforced by `make-node`.** It was offered while
  brainstorming, and declined: it would reject documents cmark parses.
- **Importing the internal `%node-children` into the HTML-tree package.**
  It would stop the copying, not the recursion: each HTML-tree walk would
  still need a stack of its own. And it would tie the HTML tree to the
  node's representation, which the plan keeps private.
- **Keeping M1's pieces and adding a trampoline.** It would fix the stack
  only: path lookups and the serializer's scan would still slow down with
  depth. And each walk would carry its own trampoline, where `walk-ast`
  serves every AST walk.

## Consequences

- Memory, not the stack, bounds the depth of a tree the library can walk
  (spec §1).
- `walk-ast` is new public API: its protocol (spec §4.1) is now a promise.
- A caller's own recursive walk still meets the stack. `walk-ast` offers
  the library's loop instead.
- Deep values have to stay out of test failure messages. Parachute prints
  the values a failed check compares, so a deep tree would flood the report,
  or exhaust the printer's own stack. Deep tests compare strings, numbers or
  booleans (spec §4.7).
- ADR-0014 is amended, not replaced: its footnote rules stand, and only how
  a place is identified changes. Its status line says so; its body is
  unchanged.
- This settles three of M1's hand-offs: stack depth, the non-copying child
  accessor and the shared `proper-list-p`.
