# M1 pure core — implementation plan

- **Spec:** [2026-09-27-m1-pure-core-design.md](2026-09-27-m1-pure-core-design.md)
  (approved 2026-09-27)
- **Branch:** `m1-pure-core`
- **Scope:** the conditions, AST and HTML-tree systems, their tests, the
  oracle fixtures, the Makefile targets and the CI steps. **No native
  code**: that starts in M2.

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
- **Lisp style:**
  - follow AGENTS.md's conventions;
  - no optimization `declaim`s;
  - `:import-from`, never `:use`, apart from `cl`;
  - tests reach internal helpers as `package::symbol`.
- **Don't commit.** The user commits.
- **Report:** files changed, test counts per Lisp, and the mutation results.

## Execution

The code tasks share one working tree, and the runner loads every file. An
agent's half-written file would break another agent's test run, so the
code tasks run **one at a time**. The documents and the CI edit never load
Lisp, so they run alongside.

| Step | Task | Model | Alongside |
|------|------|-------|-----------|
| 1 | 1 Skeleton, dependencies, runner | Sonnet | 7 Documents (Opus) |
| 2 | 2 AST | Sonnet | |
| 3 | 3 URL helpers | Sonnet | |
| 4 | 4 Serializer | Sonnet | |
| 5 | 5 Oracle fixtures | Sonnet | |
| 6 | 6 Converter and footnotes | Opus | 8 CI workflow (Sonnet) |
| 7 | 9 Review and close-out | Opus review, then fixes | |

Tasks that run alongside each other share no files.

## Interfaces the tasks share

Fixed here, so that tasks running in parallel agree on them:

- **Conditions,** exported from `cl-commonmark-gfm.conditions`:
  - `commonmark-gfm-error`, a subtype of `error`, with the readers
    `condition-operation`, `condition-datum` and `condition-reason`;
  - its subtypes `invalid-ast-node`, `invalid-render-option`,
    `invalid-html-tree` and `unsupported-extension-node`.

  Signal them as `(error 'invalid-ast-node :operation 'make-node :datum x
  :reason "…")`.
- **`cl-commonmark-gfm.ast` exports:** `node`, `node-p`, `make-node`,
  `copy-node`, `node-kind`, `node-attributes`, `node-attribute`,
  `node-children`, `node-sourcepos`, `node=`, `fold-ast`, `map-ast` and
  `transform-ast`.
- **`cl-commonmark-gfm.html-tree` exports** `ast->html-tree` and
  `html-tree->string`. Its internal helpers:
  - `(href-encode string)` returns a string, per spec §5.5 (Task 3);
  - `(dangerous-url-p string)` returns true for a destination the
    `:safe` policy blanks (Task 3);
  - `(valid-html-name-p keyword)` returns true when the lowercased name
    matches `[a-z][a-z0-9-]*`, and false for `:*comment*` (Task 4);
  - `(void-element-p keyword)` returns true for `:br`, `:hr`, `:img` and
    `:input` (Task 4).
- **Files,** all listed in `cl-commonmark-gfm.asd` with `:serial t`:
  - `src/conditions.lisp`;
  - `src/ast/`: `package`, `schema`, `node`, `transform`;
  - `src/html-tree/`: `package`, `url`, `serialize`, `footnotes`,
    `convert`;
  - `tests/`: `package`, `helpers`, `conditions`, `ast`, `url`,
    `serialize`, `html-tree`, `oracle`.

## Task 1: Skeleton, dependencies and runner

**Owns:**
- `cl-commonmark-gfm.asd`, `ocicl.csv` and `Makefile`;
- `src/conditions.lisp`, `src/ast/package.lisp` and
  `src/html-tree/package.lisp`;
- `tests/package.lisp`, `tests/helpers.lisp`, `tests/conditions.lisp` and
  `tests/run.lisp`;
- a stub, containing only `(in-package …)`, for every other file listed
  above.

1. **The `.asd`:** the four systems from spec §3, with the files above and
   `:license "BSD-3-Clause"` (the project's `LICENSE`). There's also an
   empty primary `cl-commonmark-gfm` system: ASDF won't load a slash-named
   system without it (found while doing this task).
2. **Packages:**
   - the three library packages, exporting exactly the interface lists
     above;
   - `cl-commonmark-gfm.tests`, which imports the whole public API and
     Parachute's `define-test`, `is`, `isnt`, `true`, `false`, `fail` and
     `of-type`.
3. **Conditions,** in `src/conditions.lisp`. Each report names the
   operation, the reason and the datum, e.g.
   `make-node: unknown kind: :FOO`.
4. **`tests/helpers.lisp`:** a small builder,
   `(n kind attributes &rest children)` calling `make-node`, plus
   `(txt "…")` for a `:text` node. Tasks 2, 5 and 6 use them.
5. **Dependencies:** `scripts/guix-env sh -c 'ocicl install parachute
   </dev/null'` writes `ocicl.csv`, which pins Parachute and its four
   dependencies by digest. `ocicl/` stays ignored.
6. **`tests/run.lisp`** (spec §7.2):
   1. `(require :asdf)`;
   2. load `cl-commonmark-gfm/tests`;
   3. `(parachute:test :cl-commonmark-gfm.tests :report 'parachute:quiet)`;
   4. on failure, print each failed result to `*error-output*`;
   5. fail if `(find-package "CFFI")`;
   6. `(uiop:quit 0|1)`.
7. **Makefile:**
   - `deps`: `ocicl install </dev/null`.
   - `check-purity`: runs `tests/run.lisp` for each Lisp in `LISPS ?=
     sbcl ccl ecl`, with `CL_SOURCE_REGISTRY=$(CURDIR)/:$(CURDIR)/ocicl//`
     (no empty entry, so nothing is inherited) and stdin from `/dev/null`.
     The invocations were probed on 2026-09-27:
     - `sbcl --non-interactive --no-sysinit --no-userinit --load tests/run.lisp`
     - `ccl -n -b -l tests/run.lisp`
     - `ecl -norc -load tests/run.lisp`

     Every Lisp runs even if an earlier one failed; the target names each
     failure, and fails if there was any.
   - `test`: `check-purity` for now (Task 5 adds `check-fixtures`).
   - Each new target gets a `## ` description and goes on the one-line
     `.PHONY`.
8. **Tests:** `tests/conditions.lisp` checks the subtype chain, the readers
   and the report text.

**Verify:** `make check-help`; `make deps && make check-purity` passes on
all three Lisps. Then, after `rm -rf ocicl`, `make deps` restores what the
suite needs.

**Mutations:**
- a deliberately failing test fails `check-purity` on each Lisp;
- `(defpackage "CFFI")` added to `tests/helpers.lisp` fails it;
- a syntax error in `src/conditions.lisp` fails it without hanging;
- `LISPS=sbcl` runs SBCL only.

## Task 2: The AST

**Owns:** `src/ast/schema.lisp`, `src/ast/node.lisp`,
`src/ast/transform.lisp` and `tests/ast.lisp`.

Implement spec §4:

- **The struct:** `(defstruct (node (:constructor %make-node) (:copier nil)
  (:conc-name %node-)) …)` with read-only slots. `:copier nil` keeps
  `copy-node` free for ours; the `%node-` readers stay internal, because
  `node-attributes` must return a copy.
- **The schema:** one table in `schema.lisp`. For each kind it lists every
  key with its type and its default, or marks the key required; and it says
  whether the kind is a leaf. Validation reads the table: no rule for a
  particular kind is written out by hand, apart from the one cross-field
  rule for `:list`.

**Tests first:**
- `make-node` for every kind, with defaults filled and the plist in schema
  order;
- each rejection:
  - an unknown kind;
  - an unknown key, a repeated key, an odd-length plist;
  - a wrong type, one case per typed attribute;
  - a missing required key; an empty label;
  - a leaf given children; a child that isn't a node; an improper list;
  - each malformed sourcepos;
  - both halves of the `:list` rule;
- an inverted sourcepos is accepted;
- `copy-node`: merging attributes, replacing children, clearing with
  `:sourcepos nil`, keeping what isn't supplied, and re-validation;
- `node-attributes` returns a fresh copy; `node-attribute` signals for a
  key the kind lacks;
- `node=`: each component, `:sourcepos nil` at depth, and case-sensitive
  strings;
- the order `fold-ast` and `map-ast` visit nodes in;
- `transform-ast`:
  - identity, replacing, splicing and deleting;
  - that `function` sees children already transformed;
  - each root failure, and a non-node inside a returned list.

**Mutations:**
- removing the leaf check;
- storing attributes in the caller's order;
- transforming top-down;
- comparing strings with `string-equal` in `node=`.

## Task 3: URL helpers

**Owns:** `src/html-tree/url.lisp` and `tests/url.lisp`.

`href-encode` and `dangerous-url-p`, per spec §5.5, with a private UTF-8
encoder.

**Tests first:**
- every ASCII byte from 0 to 127 against the spec's list of characters
  that pass through, written out in the test independently of the code;
- `&` and `'` pass through; `%` does too, so there's no double encoding;
- `" "` → `%20`; `é` → `%C3%A9`; `€` → `%E2%82%AC`; U+1D11E →
  `%F0%9D%84%9E`; hex is uppercase;
- `dangerous-url-p`:
  - dangerous: each scheme in any case (`JavaScript:`), `data:text/html`,
    `data:image/svg+xml`;
  - safe: `data:image/png`, `gif`, `jpeg` and `webp` in any case; also
    `data:image/pngx` (only the prefix counts), `javascript` with no colon,
    ` javascript:` with a leading space, `http:`, and `""`.

**Mutations:**
- dropping `%` from the safe set;
- lowercase hex;
- dropping the `data:image/` exception;
- a case-sensitive scheme match.

## Task 4: The serializer

**Owns:** `src/html-tree/serialize.lisp` and `tests/serialize.lisp`.

`html-tree->string`, `valid-html-name-p` and `void-element-p`, per spec §6.

**Tests first:**
- escaping in text: `& < > "` are escaped, `'` is not;
- escaping in attributes: in `title`, `'` stays raw; in `href`, `src` and
  `id`, `'` becomes `&#x27;`;
- void elements print as `<br />` and `<img src="u" alt="a" />`;
- bare `data-footnote-ref` versus `disabled=""`;
- comments;
- a string, a list of nodes, and `nil` → `""`;
- nothing is added: `(:p nil "a")` → `<p>a</p>`;
- lowercase names;
- one case for every `invalid-html-tree` rule in §6.

**Mutations:**
- no `"` escaping;
- printing `data-footnote-ref=""`;
- printing a void element with an end tag;
- accepting `--` in a comment.

## Task 5: Oracle fixtures

**Owns:** `tests/fixtures/html/` (the `cases` manifest and the `.md` and
`.html` files), `tests/oracle.lisp`, and the fixture targets in the
`Makefile`.

1. **The manifest** holds one case per line, `name file.md flags…`, per
   spec §7.3. The default flags are cmark's GFM set:
   `-e footnotes -e table -e strikethrough -e autolink -e tagfilter -e tasklist`.
   Cases:

   | Group | Cases |
   |-------|-------|
   | Blocks | `paragraphs`, `headings` (ATX and setext), `blockquotes` (nested, and an empty `>`), `code-blocks` (info, info with more words, info ending in a tab, none, indented, empty), `thematic-break` |
   | Inlines | `emphasis` (em, strong, `****s****`, strikethrough, code), `breaks-hard` |
   | Lists | `lists-tight` (with a nested list), `lists-loose`, `lists-ordered` (starts 1, 3 and 0; `)` delimiter), `tasks-tight`, `tasks-loose` |
   | Raw HTML | `raw-html`: a block, inline HTML in a paragraph, `- <div>` and `- a <b>` |
   | Links | `links` (title; none; autolinks; `&`, `'`, a space, non-ASCII and `%20` in a destination), `images` (emphasis, code, a hard break, raw HTML and a link inside `alt`; title), `links-dangerous`, and `links-unsafe` (the same file with `--unsafe`; it holds no raw HTML) |
   | Tables | `tables` (all alignments, inline content, an escaped pipe), `table-header-only` |
   | Softbreaks | `softbreak-space` (`--nobreaks`), `softbreak-br` (`--hardbreaks`) |
   | Footnotes | `footnotes-basic`, `footnotes-repeat`, `footnotes-order` (spec §2 finding 4), `footnotes-nested` (from `regression.txt`), `footnotes-nonparagraph`, `footnotes-empty`, `footnotes-labels` (`it's` and `café`) |

2. **Makefile:**
   - `check-fixtures` re-renders every case with `cmark-gfm` and diffs it
     against the case's `.html`. It fails on any difference, and on a
     missing file.
   - `fixtures-html` writes only the `.html` files that are missing.
   - `test` becomes `check-purity check-fixtures`.
3. **Generate** with `make fixtures-html`. Read every `.html` before
   accepting it.
4. **`tests/oracle.lisp`:** each case's hand-built AST (using
   `tests/helpers.lisp`) and its options.
   - To build the AST, run `cmark-gfm -t xml` on the case and transcribe
     the parse, without committing the XML. It shows tightness, list
     attributes and structure. Footnote nodes print as `<unknown>`, so take
     their labels from the Markdown.
   - The test first asserts that the manifest and the Lisp cases name the
     same set, with no duplicates. Then, for each case, it asserts that
     `(html-tree->string (apply #'ast->html-tree ast options))` equals the
     `.html` file read as UTF-8 (`uiop:read-file-string`).

**Verify:**
- `make check-fixtures` passes;
- the set-equality test passes;
- the per-case tests fail because `ast->html-tree` is still a stub. That
  is expected, and those tests are Task 6's target.

**Mutations:**
- a flipped byte in one `.html` fails `check-fixtures`;
- a case in the manifest with no Lisp case, and the other way round, each
  fail the set test.

## Task 6: Converter and footnotes

**Owns:** `src/html-tree/footnotes.lisp`, `src/html-tree/convert.lisp` and
`tests/html-tree.lisp`.

Implement spec §5 with Tasks 3 and 4's helpers.

- **Structure:** a port of `vendor/cmark-gfm/src/html.c` and
  `extensions/{table,tasklist}.c`, producing tree nodes instead of bytes.
- **The `cr` rule:** thread one piece of state through the conversion:
  whether the output so far is empty or ends in a newline. After a start
  or end tag it is false; after a string, it depends on the string's last
  character.
- **Context:** pass down what the port needs: whether the grandparent is a
  tight list, whether the parent is a `:strong`, and whether the row is
  the header row.
- **The footnote pre-pass** (spec §5.4) is a pure function of the root. It
  keys its bookkeeping by each place's path from the root, not by node
  identity: an immutable node can sit at more than one place.

**Tests first,** in `tests/html-tree.lisp`, comparing whole trees:
- one case per row of §5.3, `"\n"` strings included;
- option validation: an odd-length plist, an unknown key, a bad value, a
  bad wrapper, and the leftmost of repeated keys winning;
- `:raw-html :text`, in block and in inline position;
- `:document-wrapper`;
- a root that isn't a document;
- the pre-pass cases in spec §7.4;
- `unsupported-extension-node`;
- determinism.

**Done when:** those tests pass and Task 5's oracle cases pass on all three
Lisps.

**Mutations,** from spec §7.5. Each must fail a named test:
- dropping the `'` escape. That lives in Task 4's code, so apply it
  temporarily and revert;
- emitting `"\n"` where `cr` would not;
- numbering by first reference;
- re-wrapping a nested `strong`;
- dropping the `data:image/` exception.

## Task 7: Documents

**Owns:**
- `.plans/decisions/0014-*.md`;
- the status lines of ADR-0010 and ADR-0011;
- `.plans/cl-commonmark-gfm.org`;
- `.plans/progress.md`.

1. **ADR-0014:** "The HTML tree carries cmark's newlines; footnotes follow
   definition order". Use the same format as ADR-0010, and cite the spec's
   sections. Cover:
   - D4: newlines live in the tree;
   - the §5.4 rules and the two known divergences;
   - the §6 rules for URL attributes, bare attributes and void elements;
   - D1: M1's fixtures are checked against the pinned CLI;
   - D11: options come in as `&rest`.

   Its footnote example uses a label other than `1`.
2. **ADR-0010 and ADR-0011** get "Amended by ADR-0014 (2026-09-27)" in
   their status lines. Their bodies are unchanged.
3. **The plan:** the edits listed in spec §8:
   - the AST contract;
   - `invalid-ast-node` in the conditions table;
   - the HTML tree contract: a new layout paragraph, the mapping rows, and
     the serializer bullets;
   - the tests section, including the real `check-purity`;
   - M1's wording;
   - decision log entry 20.
4. **`progress.md`:**
   - M1 becomes "in progress";
   - add an M1 checklist, one item per task;
   - the constraint about the HTML tree cites ADR-0014;
   - a new constraint: the pure systems depend on nothing outside the
     project.

**Verify:**
- `grep -n 'static tables\|first reference' .plans/cl-commonmark-gfm.org`
  finds nothing outside the decision log;
- ADR-0014 states nothing the spec doesn't.

## Task 8: CI workflow

**Owns:** `.github/workflows/ci.yml`, and `ci/install-toolchain.sh` only
if the checkpoint below needs it.

- Add `make deps` and `make test` after `make check-notice`.
- **Checkpoint:** Debian's `ecl` compiles through a C compiler. If the
  local run (Task 9) shows `ecl` failing for want of `gcc`, add `gcc` to
  `install-toolchain.sh`'s apt list and note why.
- `timeout-minutes: 20` stays, unless the local run takes more than 12
  minutes.

## Task 9: Review and close-out

1. **In the container:** `make check-help`, `make deps`, `make test` and
   `make check-guix`, all green.
2. **Opus review** of the combined diff against the spec and this plan.
   Fix what it finds, sending mechanical fixes to Sonnet.
3. **Close-out** in `progress.md`: tasks done, test counts per Lisp, the
   mutations seen, and anything found along the way.
4. **Ask the user** to commit and open the PR.
5. **After the commit, the local CI proof,** as for M0:
   - clone the commit, with its submodules, into `debian:trixie`;
   - run `ci/install-toolchain.sh`, then every workflow step in order;
   - check each step's exit status, never piping through `tail`;
   - then flip a byte in one fixture `.html`, and see `make test` fail.

   Record both in `progress.md`, and push that as a follow-up commit.

**M1 exits when** `make test` is green on all three Lisps, in the container
and in the local `debian:trixie` run. The GitHub run waits for October, as
M0's did.
