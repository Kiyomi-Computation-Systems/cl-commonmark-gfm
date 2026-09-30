# M2a stack-safe walks — implementation plan

- **Spec:** [2026-09-30-m2-native-layer-design.md](2026-09-30-m2-native-layer-design.md)
  (approved 2026-09-30), §3 (`/util`) and §4
- **Branch:** `m2a-stack-safe-walks`
- **Scope:** `/util` and one `proper-list-p`; `walk-ast` and the AST walks;
  the serializer; the converter and footnotes; ADR-0015 and the documents
  for this slice. **No native code**: that is M2b, planned after this slice
  lands.

## Brief for every task

Each task goes to one subagent, which works only on the files its task
owns. If another file needs changing, the agent reports it instead of
editing it.

- **Run builds and tests only through the container.** Batch commands into
  one call, e.g. `scripts/guix-env sh -c 'make deps && make check-purity'`;
  each call takes seconds to start.
- **TDD.** Write the task's tests first, run them, and watch them fail for
  the right reason. Only then implement.
- **Seen to fail.** Every check the task adds must fail under the mutations
  listed for it. Apply each mutation, watch the failure, revert, and report
  what failed and how.
- **No output changes.** M1's 226 tests and the 28 oracle fixtures are the
  contract. None of them may be edited to make a rewrite pass.
- **No recursion over a tree's depth** in library code, and no recursion
  over a list's length either: loops, with explicit stacks.
- **Deep values stay out of failure messages.** Parachute prints the
  values an `is` compares, so a deep tree or a megabyte string would flood
  the report, or exhaust the printer's stack. Deep tests assert with
  `true` or `false` over `string=`, `node=`, `=` or `eq`.
- **Lisp style:**
  - follow AGENTS.md's conventions;
  - no optimization `declaim`s;
  - `:import-from`, never `:use`, apart from `cl`;
  - tests reach internal helpers as `package::symbol`.
- **Don't commit.** The user commits.
- **Report:** files changed, test counts per Lisp, the deep tests' run time
  per Lisp, and the mutation results.

## Execution

The code tasks share one working tree, and the runner loads every file, so
they run **one at a time**. The documents never load Lisp, so they run
alongside the first code task.

| Step | Task | Model | Alongside |
|------|------|-------|-----------|
| 1 | 1 `/util` and one `proper-list-p` | Sonnet | 5 Documents (Opus) |
| 2 | 2 `walk-ast` and the AST walks | Sonnet | |
| 3 | 3 The serializer | Sonnet | |
| 4 | 4 The converter and footnotes | Opus | |
| 5 | 6 Review and close-out | Opus review, fixes, then a second review | |

Tasks that run alongside each other share no files.

## Interfaces the tasks share

- **`cl-commonmark-gfm.util`** (Task 1) exports `proper-list-p`. The AST
  and HTML-tree packages import it.
- **`cl-commonmark-gfm.ast`** (Task 2) adds the export `walk-ast`, with
  spec §4.1's protocol: `(walk-ast function node)` calls
  `(funcall function :enter n)` and `(funcall function :exit n)`, and an
  `:enter` call that returns `:skip` skips n's children and n's `:exit`.
  The HTML-tree package imports it in Task 4.
- **`tests/deep.lisp`** (Task 2) defines the builders Tasks 3 and 4 reuse:
  - `(build-chain depth leaf wrap)`: starts from LEAF, a node, and applies
    WRAP, a function of one node, DEPTH times, in a loop. Returns the top
    node.
  - `(repeat-string string count)`: STRING repeated COUNT times.
  - `+deep+`, the depth every deep test uses: 100,000.
  - one builder per deep AST shape of spec §4.7, each taking a depth
    (listed under Task 2).
- **Files,** all in `cl-commonmark-gfm.asd` with `:serial t`:
  - `src/util.lisp` (new);
  - `tests/util.lisp` (new), after `tests/helpers.lisp`;
  - `tests/deep.lisp` (new), last.

## Task 1: `/util` and one `proper-list-p`

**Owns:**
- `cl-commonmark-gfm.asd`;
- `src/util.lisp` (new);
- `src/ast/package.lisp` and `src/ast/schema.lisp`;
- `src/html-tree/package.lisp` and `src/html-tree/serialize.lisp`, for
  the `proper-list-p` lines only;
- `tests/package.lisp`, `tests/util.lisp` (new), and `tests/deep.lisp`
  (new, a stub holding only `(in-package …)`).

1. **The system:** `cl-commonmark-gfm/util`, `:license "BSD-3-Clause"`,
   holding `src/util.lisp`: the `cl-commonmark-gfm.util` package, which
   exports `proper-list-p`. `cl-commonmark-gfm/ast` and
   `cl-commonmark-gfm/html-tree` depend on it. The tests system lists it,
   plus the two new test files.
2. **`proper-list-p`:** one `loop` over Floyd's two pointers. It returns
   what M1's two copies return: true for `nil` and for proper lists; false
   for dotted lists, circular lists and non-lists.
3. **Remove both copies,** in `schema.lisp` and `serialize.lisp`, and
   import the shared one. The serializer's comment about a "local"
   proper-list check goes too.

**Tests first,** in `tests/util.lisp`:
- `nil`; one element; several elements;
- dotted: `(1 . 2)`, `(1 2 . 3)`;
- circular, with cycles of length 1, 2 and 3, and a cycle entered after a
  prefix;
- non-lists: a string, a vector, a number;
- a list of 3,000,000 elements.

**Mutations:**
- claim a list is proper when the two pointers meet: the circular tests
  fail;
- a recursive version that isn't in tail position: the 3,000,000-element
  test fails on each Lisp.

**Verify:** `make check-help`; `make check-purity` passes on all three
Lisps.

## Task 2: `walk-ast` and the AST walks

**Owns:** `src/ast/package.lisp`, `src/ast/transform.lisp`,
`src/ast/node.lisp` (`node=` and its helpers only), `tests/package.lisp`,
`tests/ast.lisp` and `tests/deep.lisp`.

Implement spec §4.1 and §4.2:
- **`walk-ast`,** in `transform.lisp`, over an explicit stack of frames. It
  reads children with the internal `%node-children`, never
  `node-children`, which copies. It signals a `type-error` for a non-node,
  with `check-type`.
- **`fold-ast` and `map-ast`** act on `walk-ast`'s `:enter` events.
- **`transform-ast`** keeps a stack of frames, each collecting its node's
  transformed children. On `:exit`: rebuild the node with `copy-node`
  only when its children changed (compared as M1 does), call FUNCTION,
  check the result exactly as M1 does, with the same conditions and
  datums, and hand it to the parent's frame. The root must come back as
  exactly one node.
- **`node=`:** a loop over a stack of `(a . b)` pairs, making M1's
  comparisons (kind, attributes, source positions unless `:sourcepos nil`,
  child count). A pair of `eq` nodes is equal and isn't descended.

**Tests first:**
- **In `tests/ast.lisp`:**
  - the exact event sequence for a small mixed tree, leaves included;
  - `:skip` skips the children and the `:exit`, and other return values
    are ignored;
  - a node object at two places is visited at each;
  - a non-node signals `type-error`;
  - `walk-ast` returns `nil`.
- **In `tests/deep.lisp`:** the shared builders above, and one builder
  per deep shape of spec §4.7, which Task 4 renders too:
  - block quotes;
  - alternating `:emph` and `:strong`;
  - nested lists: list, item, list, item, …;
  - nested links;
  - an image whose only text is `+deep+` levels below it;
  - footnote definitions nested in definitions, each referenced from the
    body.

  Then, for every shape at `+deep+` levels:
  - the number of `walk-ast` events, and `fold-ast`'s node count;
  - `map-ast`'s length;
  - `transform-ast` with `identity` returns the same root, by `eq`;
  - `transform-ast` with a function that rebuilds every node with
    `copy-node` returns a tree `node=` to the original;
  - `node=` of two separately built trees is true, and false when only
    the deepest leaf differs.
- **Wide:** the same walks over a paragraph with 300,000 text children.

**Mutations:**
- each of `walk-ast`, `fold-ast`, `map-ast`, `transform-ast` and `node=`
  put back to plain recursion, one at a time: the deep tests fail on SBCL;
- `walk-ast` ignoring `:skip`: the skip test fails;
- `transform-ast` calling FUNCTION before the children are transformed:
  M1's transform tests fail.

## Task 3: The serializer

**Owns:** `src/html-tree/serialize.lisp`, `tests/serialize.lisp` and
`tests/deep.lisp` (a new serializer section).

Implement spec §4.5:
- a loop over a stack of open elements, each frame holding the element
  and its children still to write;
- the "element contains itself" check looks the element up in an `eq`
  hash set of open elements, adds it when it opens, and removes it when it
  closes;
- each element is validated when it opens, with M1's checks in M1's
  order, so a malformed tree signals the same condition with the same
  datum.

**Tests first:**
- M1's serializer tests pass unchanged, including the shared acyclic
  element as siblings and as cousins, and the element that contains
  itself.
- **Deep:** `(:div nil (:div nil … "x"))`, `+deep+` levels, against a
  string built by `repeat-string`.
- **A deep cycle:** an element that contains itself 50,000 levels down
  still signals `invalid-html-tree`, naming that element.

**Mutations:**
- recursion instead of the stack: the deep test fails on SBCL;
- not removing a closed element from the set: M1's shared-element tests
  fail.

## Task 4: The converter and footnotes

**Owns:** `src/html-tree/package.lisp` (importing `walk-ast`),
`src/html-tree/footnotes.lisp`, `src/html-tree/convert.lisp`,
`tests/html-tree.lisp` and `tests/deep.lisp` (a new converter section).

Implement spec §4.3 and §4.4:
- **Structure:** one renderer state, holding the stack of open elements,
  `bol`, plain mode (the image and its alt text), the ancestor stack, the
  count of open `:table-header`s, each open table's `tbody` flag, the
  options and the footnote plan. One handler, given to `walk-ast`,
  dispatches on the event and the node's kind, following the events
  table in spec §4.3 row by row.
- **The footnote pre-pass:** one `walk-ast` with a stack of owners, per
  spec §4.4. It keys each reference by its owner and its ordinal within
  that owner, and signals `unsupported-extension-node` at the first
  `:extension` node. `root-path`, `child-path`, `occurrences` and every
  key built from a path go.
- **The section** renders each surviving definition in number order: each
  child walked separately, nested definitions skipped, the definition as
  parent and the document as grandparent, and the backrefs placed per
  spec §4.4.
- **After the walk:** the section, normalization of the top-level items,
  and `:document-wrapper`, as in M1.

**Tests first:**
- M1's HTML-tree tests and all 28 oracle fixtures pass unchanged.
- **A new explicit case:** a definition whose references render later
  than their place in the tree. For example, the body cites `b` then `a`,
  and `a`'s definition, which comes first in the tree, cites `b` again.
  The expected tree is M1's output for the same AST, captured before the
  rewrite starts.
- **Deep:** each of Task 2's six shapes at `+deep+` levels, through
  `ast->html-tree` and `html-tree->string`, compared with `string=` to a
  string built by `repeat-string`. The lists are tight, and the section
  holds `+deep+` items.

**Mutations,** each failing a named test:
- render a node's children through a recursive helper instead of
  `walk-ast`: the deep tests fail on SBCL;
- the footnote pre-pass as a recursive walk: the nested-definitions deep
  test fails on SBCL;
- key references by one preorder counter over the whole tree instead of
  owner and ordinal: the new explicit case, or M1's
  `ast->html-tree-footnote-references-resolve-in-nested-definitions-and-their-images`,
  fails;
- open a `tbody` at every body row: M1's table tests fail;
- give a `:strong` inside a `:strong` its own element: M1's nested-strong
  test fails.

## Task 5: Documents

Runs alongside Task 1. **Owns:**
`.plans/decisions/0015-walks-loop-over-explicit-stacks.md` (new),
ADR-0014's status line, `.plans/cl-commonmark-gfm.org` and
`.plans/progress.md`.

1. **ADR-0015: "Walks loop over explicit stacks".** Use ADR-0014's format,
   and link to spec §4 rather than restating its rules (spec D17). Cover:
   - **Context:** M1's walks were recursive; spec finding 5's
     measurements; cmark's own stress tests nest 130,000 levels.
   - **Decision:** no depth limit (D2); `walk-ast` as the one AST
     traversal (D8); the converter as a port of `html.c`'s event loop
     (D9); footnote places keyed by owner and ordinal; the serializer's
     `eq` set; the shared `proper-list-p`.
   - **Rejected:**
     - a depth limit enforced by `make-node`: it was offered while
       brainstorming, and declined, because it would reject documents
       cmark parses;
     - importing the internal `%node-children` into the HTML-tree
       package;
     - keeping M1's pieces and adding a trampoline.
   - **Consequences:** memory, not the stack, bounds depth; `walk-ast` is
     new public API; deep values have to stay out of test failure
     messages.
2. **ADR-0014's status line:** "amended by ADR-0015 (2026-09-30): places
   are keyed by owner and ordinal, not by path". Its body is unchanged.
3. **The plan** (spec §10, the parts for this slice):
   - the systems table gains `cl-commonmark-gfm/util`;
   - the AST exports gain `walk-ast`;
   - the M2 and M3 milestone texts: M2 as the spec's §1 describes it, in
     two slices; M3 left with unknown extensions, version probes and the
     property-based testing evaluation;
   - a risk row: trees deeper than the Lisp stack, mitigated by ADR-0015;
   - decision log entry 21, for ADR-0015.
4. **`progress.md`:**
   - M2 becomes "in progress: M2a";
   - an M2 checklist with M2a's tasks, and M2b's items from the spec (§5
     to §8) as one unticked line each;
   - a global constraint: no walk over a tree recurses on its depth
     (ADR-0015).

**Verify:** ADR-0015 states no rule that spec §4 doesn't; every link
resolves.

## Task 6: Review and close-out

1. **In the container:** `make check-help`, `make deps`, `make test` and
   `make check-guix`, all green.
2. **Opus review** of the combined diff against spec §3 and §4 and this
   plan. Fix what it finds, sending mechanical fixes to Sonnet. **Then a
   second review** of the fixes: a fix round can break what the first
   review passed, as `copy-node`'s validation order did in M1.
3. **Close-out** in `progress.md`: tasks done, test counts per Lisp, the
   deep tests' run time per Lisp, the mutations seen, and anything found.
   Tick the M1 hand-offs this slice settles: stack depth, the non-copying
   accessor, and the shared `proper-list-p`.
4. **Ask the user** to commit and open the PR.
5. **After the commit, the local CI proof,** as for M1:
   - clone the commit, with its submodules, into `debian:trixie`;
   - run `ci/install-toolchain.sh`, then every workflow step in order;
   - check each step's exit status, never piping through `tail`;
   - then flip a byte in one fixture `.html`, and see `make test` fail.

   Record both in `progress.md`, and push that as a follow-up commit.

**M2a is done when** `make test` is green on all three Lisps, in the
container and in the local `debian:trixie` run. The GitHub run waits for
October.
