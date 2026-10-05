# M5a docs machinery — implementation plan

- **Spec:** [2026-10-04-m5-documentation-design.md](2026-10-04-m5-documentation-design.md)
  (approved 2026-10-04, amended by the probes and during M5a), §1, §2, §3
  (findings 1 to 31), §4, §5's writing rules and placeholder, §6 to §11
- **Branch:** `m5a-docs-machinery`
- **Scope:**
  - the serializer's void elements, a library change (spec §4);
  - the site generator, its pure core and its shell (spec §6);
  - `make site`, `make check-site`, `make reference`, `make
    check-reference` and `make check-docs` (spec §7);
  - the generated `docs/reference.md` and a placeholder `docs/README.md`;
  - `make test` running the three checks, and `pages.yml` (spec §8);
  - ADR-0022, ADR-0010's amendment, AGENTS.md's writing rules, and the
    close-out.

## Brief for every task

Each task goes to one subagent, which works only on the files its task
owns. If another file needs changing, the agent reports it instead of
editing it.

- **Read first:**
  - `AGENTS.md`;
  - the global constraints in `.plans/progress.md`;
  - the spec sections and findings the task names.
- **Run builds and tests only through the container.** Batch commands into
  one call, e.g. `scripts/guix-env sh -c 'make check-site && make
  check-docs'`; each call takes seconds to start.
  - The pure suite, `make check-purity`, runs on all three Lisps: about 2
    minutes.
  - The native suite on SBCL, `make check-native`: about 4 minutes.
  - Every site target runs on SBCL alone, and needs cmark-gfm, which the
    container names with `CL_COMMONMARK_GFM_LIBS`.
- **TDD, red first.** Write the task's checks first and run them. The
  report shows each new check failing, with its output, before any
  implementation exists. Then implement.
- **Seen to fail.** Every check the task adds must fail under the
  mutations listed for it:
  - apply each mutation, watch the failure, revert;
  - report what failed and how;
  - before every run of a mutation series, the restoring run and the
    final run included, delete the project's own fasls: `find
    .guix-env/cache*/common-lisp -type d \( -path
    '*/cl-commonmark-gfm/src' -o -path '*/cl-commonmark-gfm/tests' -o
    -path '*/cl-commonmark-gfm/site' \) -prune -exec rm -rf {} +`. The
    `site` tree is new: the generator compiles there;
  - after a series, `git diff --stat` shows only the task's own changes.
- **Two Parachute traps make vacuous tests:**
  - `(is < a b)` evaluates `(< b a)`. Write `(true (< a b))`;
  - a bare `(fail form)` passes on any error, an undefined function
    included. Always name the exact condition type.
- **The site dogfoods the library.** Its code calls only symbols that
  `cl-commonmark-gfm` exports: no `::` into the library. Its tests may
  reach the site's own internals as `cl-commonmark-gfm.site::name`.
- **Functional core, imperative shell.** The site's core functions take
  strings and lists and return them; they never read or write a file.
  Only the runners (`site/run-*.lisp`) and `site/build.lisp` touch files.
- **The site runs on SBCL,** in portable Common Lisp. Its one reader
  conditional is `#+sbcl` in `site/reference.lisp`, for lambda lists and a
  condition's parents (findings 5 and 6), with `#-sbcl` signalling an
  error that says the reference is generated on SBCL.
- **Stay inside the repository.** Never delete or change anything outside
  it, such as `~/.cache/common-lisp/`, even as a precaution. Scratch work
  goes under `.guix-env/tmp/`. The probes behind findings 12 to 15 are in
  `.guix-env/tmp/m5-docs/`: `pipeline.lisp` is a working sketch of spec
  §6.2.
- **Existing expectations stand.** No existing test changes to make new
  code pass, and no test is loosened.
- **Read chez-cmark-gfm's site from its source,** at
  `~/src/chez-cmark-gfm/site/` (`e0118a3`), never from memory: the
  template's structure and class names, `style.css`, and the theme
  script.
- **Lisp style:**
  - follow AGENTS.md's conventions, its comment rules included;
  - `:import-from`, never `:use`, apart from `cl`;
  - no optimization `declaim`s.
- **Don't commit.** The user commits.
- **Report:**
  - the files changed;
  - each new check's red output;
  - the counts and run times of what ran;
  - the mutations, and how each failed;
  - anything found, numbered for the spec if it's new: findings from 16.

## Execution

The code tasks share one working tree, so they run **one at a time**. The
documents never load Lisp, so they run alongside a code task.

| Step | Task | Model | Alongside |
|------|------|-------|-----------|
| 1 | 1 The serializer's void elements | Sonnet | 7 Documents, part 1 (Opus) |
| 2 | 2 The site's core | Opus | |
| 3 | 3 The shell, `make site` and the docs checks | Sonnet | |
| 4 | 4 The reference | Opus | |
| 5 | 5 `make check-docs` | Opus | |
| 6 | 6 CI | Sonnet | 7 Documents, part 2 (Opus) |
| 7 | 8 Review and close-out | Opus review, fixes, then a second review | |

Tasks that run alongside each other share no files. Everything passes
after every task. Any other failure stops the task.

## Interfaces the tasks share

**Files:**

| File | Change | Task |
|------|--------|------|
| `src/html-tree/serialize.lisp`, `tests/serialize.lisp` | the void elements | 1 |
| `site/cl-commonmark-gfm-site.asd` (new) | `cl-commonmark-gfm-site` and `cl-commonmark-gfm-site/tests` | 2, then 4 and 5 add their files |
| `site/package.lisp`, `site/ids.lisp`, `site/links.lisp`, `site/template.lisp`, `site/render.lisp`, `site/pages.lisp` (new) | the core | 2; 4 adds `reference.md` to `site/pages.lisp` |
| `site/style.css`, `site/theme.js` (new) | chez's theme | 2 |
| `site/tests/package.lisp`, `site/tests/core.lisp` (new) | the core's tests | 2 |
| `site/run-check-site.lisp` (new) | the check-site runner | 2, then 3 |
| `site/build.lisp`, `site/run-site.lisp` (new) | the shell | 3 |
| `docs/README.md` (new), `docs/.gitkeep` (removed) | the placeholder home page | 3; 4 links the reference; 5 adds an example |
| `site/reference.lisp`, `site/run-reference.lisp`, `site/tests/reference.lisp` (new); `docs/reference.md` (generated) | the reference | 4 |
| `site/examples.lisp`, `site/run-check-docs.lisp`, `site/tests/examples.lisp` (new) | `check-docs` | 5 |
| `Makefile` | `check-site` (2, 3); `site` (3); `reference`, `check-reference` (4); `check-docs` (5); `test` (6) | 2 to 6 |
| `.github/workflows/pages.yml` (new), `tests/make-preflight.sh` | CI | 6 |
| `.plans/decisions/0022-*.md` (new), ADR-0010, `AGENTS.md`, `.plans/progress.md` | documents | 7 |

**Make targets.** Each runs SBCL with `CL_SOURCE_REGISTRY` set to
`$(TEST_SOURCE_REGISTRY):$(CURDIR)/site/`, checks for `sbcl` first with
`scripts/require-tools`, carries a `##` help line, and is `.PHONY`:
- `make check-site`: the site's tests, then spec §7.1's checks over
  `docs/`. Prints the report-suite line, `check-site: <n> tests, <m>
  assertions`, then `check-site: <p> pages, <l> links, no problems`, or
  one `check-site: <page>: <problem>` line each and exit 1.
- `make site`: writes `build/site/`; `SITE_REF` sets the ref, `main` by
  default. Prints `site: wrote <p> pages to build/site/ (ref <ref>)`.
- `make reference`: writes `docs/reference.md`. Prints `reference: wrote
  docs/reference.md, <n> symbols`.
- `make check-reference`: prints `check-reference: <n> symbols;
  docs/reference.md is current`, or names the first symbol whose entry
  differs, or each export with no docstring, and exits 1.
- `make check-docs`: prints `check-docs: <e> examples on <p> pages`, or
  one line per failure naming the page, the block and the form, and exits
  1.

**The site's core,** package `cl-commonmark-gfm.site`:
- `(heading-id text)`: spec finding 4's rule. `(unique-ids texts)`: the ids
  of one page's headings, in order, repeats numbered per id (finding 11).
- `(heading-text heading)`: a `:heading` node's `:text` and `:code`
  literals, in order (finding 12).
- `(rewrite-destination destination page-names ref)`: spec §6.3. Returns
  the new destination and, as a second value, a problem string or NIL.
  `page-names` are the `docs/` file names, such as `"options.md"`.
- `(page-document &key nav current title body toc prev next ref)`: the
  whole page as an HTML tree, after chez's `site/template.sls`.
- `(render-site pages ref)`: `pages` is a list of `(name . markdown)`,
  `README.md` first, then `*pages*`' order. Returns four values: a list
  of `(html-name . html)`, `README.md`'s as `index.html`; each page's ids,
  as `(name . ids)`; the problems, a list of strings naming their page;
  and the number of links and images checked.
- `*pages*`, in `site/pages.lisp`: the sidebar's file names, in order.

## Task 1: The serializer's void elements

Spec §4; findings 2 and 12. **Owns:** `src/html-tree/serialize.lisp`,
`tests/serialize.lisp`, and in `tests/html-tree.lisp` the test that
refuses a void `:document-wrapper`, which gains one of the nine new names.

1. **Red:** one test over all 13 names (`area`, `base`, `br`, `col`,
   `embed`, `hr`, `img`, `input`, `link`, `meta`, `source`, `track`,
   `wbr`), in `tests/serialize.lisp`'s style:
   - each, with one attribute, serializes as `<name attr="v" />`;
   - each, given a child, signals `invalid-html-tree`.

   Run the pure suite on SBCL: the nine new names fail both assertions,
   and the four old ones pass.
2. **Implement:** `*void-element-names*` holds the 13. Its docstring, and
   `void-element-p`'s, say they are HTML's void elements. One sentence in
   `html-tree->string`'s docstring, which is for users: a void element,
   such as `:br` or `:meta`, prints as `<tag />`, and signals with
   children.
3. **Green:** `make check-purity`, all three Lisps, and `make
   check-native`: the oracle tests compare trees with cmark's HTML, and
   must not change.
4. **Mutations:**
   - `meta` dropped from the list: its two assertions fail;
   - the children check skipped for void elements: every "signals"
     assertion fails.

## Task 2: The site's core

Spec §6.1 to §6.4; findings 3, 4, 11 and 12. **Owns:**
`site/cl-commonmark-gfm-site.asd`, `site/package.lisp`, `site/ids.lisp`,
`site/links.lisp`, `site/template.lisp`, `site/render.lisp`,
`site/pages.lisp`, `site/style.css`, `site/theme.js`,
`site/tests/package.lisp`, `site/tests/core.lisp`,
`site/run-check-site.lisp`, and the Makefile's `check-site` target, its
help line and `.PHONY` entry.

1. **The systems:** `cl-commonmark-gfm-site`, depending on
   `cl-commonmark-gfm`, and `cl-commonmark-gfm-site/tests`, adding
   Parachute. `*pages*` starts empty.
2. **Red,** in `site/tests/core.lisp`:
   - **ids:** finding 4's three examples; finding 11's, `added`,
     `added-1`, `added-2` beside `fixed`, `fixed-1`, and
     `200---2026-06-07`; and finding 12's
     `markdown-html-and-max-nodes`, through `heading-text` on a parsed
     heading;
   - **links:** one assertion per row of spec §6.3, `README.md` included,
     each with and without `#id`; and the two problems, a `.md` that
     names no page and a path that climbs out of the repository;
   - **the template:** `page-document`'s tree has chez's structure and
     class names: the head (charset, viewport, title, `style.css`); the
     top bar's theme toggle; the side's project name and nav, the current
     page marked `on` with `aria-current`; `main`'s column with the body,
     the previous and next links, and the closing line with the ref; the
     "On this page" list; `theme.js` last in the body. Serialized, it
     holds `<meta charset="utf-8" />` (Task 1);
   - **`render-site`,** on small pages built in the tests: the outputs'
     names; each heading's id; the "On this page" list from `##`
     headings; a ⚠️-led blockquote wrapped in `div.callout.warning`; and
     the problems of spec §7.1's checks 2, 4 and 5: a missing anchor, raw
     HTML, and a page not starting with exactly one `#` heading. Check 3's
     scan for a relative `.md` link is tested on a hand-built tree: the
     rewrite leaves none, so only a broken rewrite can (Task 3's
     mutation).
3. **Implement,** following spec §6.2. `site/style.css` is chez's, byte
   for byte. `site/theme.js` is chez's theme script as a file: it may use
   any character now (finding 3).
4. **`make check-site`,** for now: the site's tests alone, through
   `site/run-check-site.lisp`, which loads `tests/runner.lisp` for its
   report.
5. **Mutations:**
   - the id rule keeps `.`: finding 4's examples fail;
   - repeats numbered across all ids, not per id: finding 11's fail;
   - `README.md` left as `README.html`; a URL with a scheme rewritten;
     the climb out of the repository allowed: their link assertions fail;
   - each problem not reported, in turn, check 3's scan included: its
     assertion fails;
   - the callout not wrapped: its assertion fails.

## Task 3: The shell, `make site` and the docs checks

Spec §5's placeholder, §6.5 and §7.1. **Owns:** `site/build.lisp`,
`site/run-site.lisp`, `site/run-check-site.lisp` (from Task 2),
`docs/README.md`, `docs/.gitkeep`, and the Makefile's `site` target and
`check-site`'s second part.

1. **The placeholder home page,** `docs/README.md`: one `#` heading, two
   sentences on what the library does, and a line saying the
   documentation is being written. No raw HTML. `docs/.gitkeep` goes.
2. **`site/build.lisp`:** reads `docs/*.md` and `*pages*`, calls
   `render-site`, and writes `build/site/`: each page's HTML after
   `<!DOCTYPE html>`, then `style.css` and `theme.js`. It writes nothing
   when `render-site` reports a problem; it prints them and exits 1.
3. **`make check-site`,** second part: after the site's tests, spec §7.1's
   checks over `docs/`: check 1, the sidebar's pages against `docs/*.md`
   less `README.md`, then `render-site`'s problems. Nothing is written.
4. **`make site`:** `site/run-site.lisp`, with `SITE_REF`.
5. **Seen to fail,** each on a copy of `docs/` or a scratch edit,
   reverted after: a page in `docs/` missing from `*pages*`; a link to
   `README.md#nowhere`; a raw `<b>`; a page whose first heading is `##`.
   Each fails `make check-site`, naming the page and the problem. The
   `.md` rewrite disabled in `site/links.lisp` fails it too.
6. **Check `make site`'s output:** `build/site/index.html` starts with
   `<!DOCTYPE html>`, holds `<meta charset="utf-8" />`, and links
   `style.css` and `theme.js`, which are there.

## Task 4: The reference

Spec §7.2; findings 5 and 6. **Owns:** `site/reference.lisp`,
`site/run-reference.lisp`, `site/tests/reference.lisp`,
`docs/reference.md`, `site/pages.lisp`'s entry, `docs/README.md`'s link to
it, the Makefile's `reference` and `check-reference` targets, and the
system's new files.

1. **Red,** in `site/tests/reference.lisp`:
   - **the docstring rules,** one assertion each: paragraphs; a `- `
     item and its indented continuation; `:GFM`, `*MAX-NODES*`,
     `RESOURCE-LIMIT-EXCEEDED` and `NIL` become lower-case code; a
     parenthesized form whose first word is a symbol, such as
     `(AST->HTML-TREE (PARSE MARKDOWN ...) ...)`, becomes one code span;
     an upper-case word that is no symbol, such as `UTF-8` or `HTML`,
     stays text; `*`, `_`, `[`, `<`, `` ` `` and `&` are escaped;
   - **lambda lists:** bare lowercase names, with no defaults or
     supplied-p variables: `copy-node`'s is `(node &key attributes
     children sourcepos)`, `map-ast`'s `(function node)` (finding 6);
   - **the layout:** sections in spec §7.2's order; kinds in order;
     names alphabetical; `node` before `node=`, whose heading takes
     `node-1` (finding 5); each entry's kind line, a condition's naming
     its parents, such as `resource-limit-exceeded`'s;
   - **the check:** an entry that differs is named; an export with no
     docstring is named.
2. **Implement.** The image's symbols are read in one function, under
   `#+sbcl`; everything else is pure over the entries it returns.
3. **Generate** `docs/reference.md` with `make reference`. Add
   `reference.md` to `*pages*`, and link it from `docs/README.md`. `make
   check-site` passes over it: its links and ids resolve.
4. **Mutations:**
   - a docstring edited, without `make reference`: `make
     check-reference` fails, naming the symbol;
   - a docstring removed: it fails, naming the symbol;
   - each docstring rule broken in turn: its assertion fails.

## Task 5: `make check-docs`

Spec §7.3; finding 13. **Owns:** `site/examples.lisp`,
`site/run-check-docs.lisp`, `site/tests/examples.lisp`, the Makefile's
`check-docs` target, the system's new files, and one example in
`docs/README.md`.

1. **Red,** in `site/tests/examples.lisp`:
   - **reading a block:** a form and its `;; =>` on the same line; on the
     next line; continued over two `;;` lines; `;; signals type-error`;
     a form with neither; blocks whose info string is `lisp` run, and
     `lisp no-run` or any other language doesn't;
   - **printing:** `(markdown->html "*hi*")`'s value prints as
     `"<p><em>hi</em></p>\n"`, a tree as `((:p nil (:em nil "hi"))
     "\n")`, a keyword as `:document` (finding 13);
   - **comparing:** runs of whitespace compare as one space;
   - **reporting:** a failure names the page, the block's number and the
     form.
2. **Implement.** Forms are read with `read` from the block's text; the
   text between one form's end and the next form's start holds its
   expectation. Each page runs in a fresh package that uses `cl` and
   `cl-commonmark-gfm`, deleted afterwards. `;; signals` passes for the
   type or a subtype.
3. **Add one example to `docs/README.md`:**
   `(markdown->html "Hello, *world*!")` with its `;; =>`.
4. **Mutations:**
   - a wrong `;; =>` in `docs/README.md`: `make check-docs` fails, naming
     it;
   - a `;; signals` on a form that returns: it fails;
   - a form that signals with no `;; signals`: it fails;
   - the newline rule dropped from printing: the printing assertion
     fails.

## Task 6: CI

Spec §8; D6 and D9. **Owns:** the Makefile's `test` line,
`.github/workflows/pages.yml` and `tests/make-preflight.sh`.

1. **`make test`** runs `check-site`, `check-reference` and `check-docs`
   after `check-native`.
2. **Preflight:** for each new target, a case with `sbcl` missing: exit 2,
   naming `sbcl`, in `tests/make-preflight.sh`'s style. Exit 2, not the
   shell's 127, shows `require-tools` ran: no stub runs before `sbcl` in
   any of the five recipes, so a stub's marker couldn't show it.
3. **`pages.yml`:** spec §8.
   - Its first four steps are `ci.yml`'s, copied: git, checkout with
     submodules, the trusted workspace, the toolchain. Then `make deps`,
     `make check-site`, `make check-reference`, `make check-docs`, and
     `make site SITE_REF="${GITHUB_REF_NAME}"`.
   - `actions/upload-pages-artifact` uploads `build/site`, and a second
     job, `needs: build`, runs `actions/deploy-pages` in the
     `github-pages` environment.
   - Triggers: `push` of tags `v*`, and `workflow_dispatch`. Permissions:
     `contents: read` at the top, and `pages: write` and `id-token: write`
     on the deploy job alone. A 30-minute timeout on the build job.
     Concurrency group `pages`, not cancelling a run in progress.
   - The deploy job runs only when the ref is a `v*` tag, so a manual run
     on a branch is a dry run (spec §8, D1).
   - Check the file parses as YAML, and use the newest major versions of
     the two Pages actions, read from their repositories.
4. **Measure** `make test` in the container before and after: report the
   time the three checks add.

## Task 7: Documents

Spec §11. **Owns:** `.plans/decisions/0022-documentation-rendered-by-the-library.md`,
ADR-0010's and ADR-0014's status lines, the project plan's line on void
elements and its decision log, `AGENTS.md`, and `.plans/progress.md`'s
Milestones table and M5 checklist.

- **Part 1,** alongside Task 1:
  - **ADR-0022:** D1 to D9 in short, in the house style (status, date,
    scope, spec, context, decision, rejected, consequences). Rejected:
    deploying from `main` now; a hand-written reference; examples in
    separate files; checks only at release.
  - **ADR-0010:** amended by D7: the serializer writes HTML's 13 void
    elements as void.
  - **ADR-0014,** whose serializer rules list the four, and the project
    plan's line on void elements: amended the same way. ADR-0010's,
    ADR-0014's and ADR-0022's text on D7 also says `:document-wrapper`
    refuses the nine new names (spec §4).
  - **AGENTS.md:** spec §5's writing rules, under the `/docs` bullets.
- **Part 2,** alongside Task 6: M5a's checklist entries in
  `progress.md`, under M5, ticked as the tasks closed; and ADR-0022's
  entry in the project plan's decision log.

## Task 8: Review and close-out

- **Two Opus reviewers,** read-only, in parallel:
  - the library change and the site's code: the API used, purity, the
    rules of spec §6, and the tests' power to fail;
  - the checks, the Makefile, CI and the documents, against the spec.

  Probes go on copies under `.guix-env/tmp/`, with `CL_SOURCE_REGISTRY`
  pointed at the copy and their own `XDG_CACHE_HOME`.
- **Fixes** go back to the agent that wrote the code. Decisions a review
  raises go to the user in one batch. A second review follows the fixes.
- **`main`'s CI steps in `debian:trixie`,** against the working tree, with
  `.guix-env/tmp/ci-proof-m5/run-tree.sh`.
- **Close-out** in `progress.md`: what was built, the red and mutation
  evidence, the counts, the time `make test` gained, the Docker run, and
  anything for M5b. The spec is amended for any new finding.
