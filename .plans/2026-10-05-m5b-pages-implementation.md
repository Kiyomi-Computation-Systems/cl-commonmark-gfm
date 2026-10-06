# M5b pages — implementation plan

- **Spec:** [2026-10-04-m5-documentation-design.md](2026-10-04-m5-documentation-design.md)
  (approved 2026-10-04, amended through 2026-10-05), §1's M5b success,
  §2 (D10 to D13), §3 (findings 33 to 39 above all), §5, §7.2's
  backquotes, §9, §11
- **Branch:** `m5b-pages`
- **Scope:**
  - the home page and the nine pages of spec §5, each following
    AGENTS.md's `/docs` rules, every Lisp example run by `make check-docs`;
  - the exit test: `installing.md`'s Debian steps in a fresh
    `debian:trixie`, and its source build in a fresh `ubuntu:24.04` (D10,
    D11);
  - backquotes for typed text in exported docstrings (D13);
  - M5a's review nits A31 to A34 and B45 to B47;
  - README.org's Documentation section, AGENTS.md, ADR-0022, the
    project plan and the close-out.

## Execution

Code tasks share one working tree and its fasls, so they run **one at a
time**, and never alongside the page tasks. Page tasks change no Lisp,
so they run in parallel, each on its own pages, once the fasls are warm.

| Step | Task | Model | Alongside |
|------|------|-------|-----------|
| 1 | 1 M5a's nits | Sonnet | 7 Documents, part 1 (orchestrator) |
| 2 | 2 Backquotes in docstrings | Opus | |
| 3 | 3 Page stubs | orchestrator | |
| 4 | 4 The pilot, `usage.md`, then the maintainer's approval (D12) | Opus | |
| 5 | 5A to 5F, the other pages | Opus, six in parallel | |
| 6 | 6 The exit test | orchestrator | once 5A is done |
| 7 | 8 Review, fixes, second review, Docker run, close-out | Opus reviewers | 7 Documents, part 2 |

Everything passes after every step. Fixes go back to the agent that wrote
the work, by message, so it keeps its context.

## Brief for every code task (1 and 2)

- **Read first:** `AGENTS.md`; the global constraints in
  `.plans/progress.md`; the spec sections the task names.
- **Run builds and tests only through the container,** batched into one
  call: `scripts/guix-env sh -c 'make check-site && make
  check-reference'`. The site targets run on SBCL and take seconds;
  `make check-purity`, all three Lisps, about 2 minutes.
- **TDD, red first.** The report shows each new test failing, with its
  output, before any implementation.
- **Seen to fail.** Every new test fails under the mutations listed for
  it: apply, watch it fail, revert, report. Before every run of a series,
  the restoring and final runs included, delete the project's fasls:
  `find .guix-env/cache*/common-lisp -type d \( -path
  '*/cl-commonmark-gfm/src' -o -path '*/cl-commonmark-gfm/tests' -o -path
  '*/cl-commonmark-gfm/site' \) -prune -exec rm -rf {} +`.
- **Fix rounds** add a test that fails when the fix is reverted, not a
  hand run.
- **Two Parachute traps:** `(is < a b)` evaluates `(< b a)`, so write
  `(true (< a b))`; a bare `(fail form)` passes on any error, so name the
  condition type.
- **The site uses the public API alone;** its tests may reach
  `cl-commonmark-gfm.site::name`.
- **Stay inside the repository.** Scratch work goes under
  `.guix-env/tmp/`. A probe copy that runs `make check-site` needs the
  repository's `.git` copied in (global constraints).
- **Existing expectations stand:** no test loosened.
- **Don't commit.** Report: the files changed, each red output, the
  counts and times, each mutation and how it failed, and any finding,
  numbered from 40.

## Brief for every page task (4 and 5)

- **Read first:**
  - `AGENTS.md`'s `/docs` rules, which every page follows;
  - spec §5's row for each page, and the findings named below;
  - `docs/reference.md`, what the reference already says;
  - once approved, `docs/usage.md`: the model of voice and shape.
- **Users only:** what to do, then why, in short sentences and plain
  words. No ADRs, findings, milestones, history, or developer detail.
- **Each fact on one page,** as the outlines below place them; other
  pages link to it. The reference is generated from the docstrings: a
  page may restate a docstring's fact a reader needs at hand, such as
  the search's directories, and links to the reference for the rest.
- **Check every claim** against the code, its docstrings, the ADRs or a
  probe's log. The report lists each claim no example shows, with its
  source: a file and line, or a log in `.guix-env/tmp/m5b-probes/`. The
  first review checks this ledger.
- **Examples:**
  - a ```` ```lisp ```` block runs in `make check-docs`; ```` ```lisp
    no-run ```` only for what can't run here, such as ECL's recipe, and
    each such block is tried by hand (Task 5E);
  - show what a reader returns, never a whole node; bind a library
    variable with `let`; no `#+` or `#-`;
  - build the footnote guard's pattern from two strings, as
    `(concatenate 'string "[" "&#94;")`; outside code write its `&` as
    `&amp;`; as code, two spans with a word between;
  - **seen to fail:** on each page with examples, make one `;; =>` wrong,
    watch `make check-docs` name the page, then restore it.
- **Checks:** `scripts/guix-env sh -c 'make check-site && make
  check-docs'` passes before the report. Other agents run them at the
  same time on their own pages: a failure on a page you don't own isn't
  yours, unless it is still there when you finish; then report it.
- **Own only your pages.** Keep the headings the outlines mark as fixed:
  other pages and the exit test link to their ids. Add other sections
  freely. A change another page needs is reported, not made.
- **No Lisp changes,** so the fasls stay warm and shared. Scratch work
  goes under `.guix-env/tmp/m5b-<page>/`. Don't commit.
- **Report:** the files changed and their line counts; each page's
  example count and its mutation's output; the claims ledger; links into
  other pages; anything found, numbered from 40.

## The pages

Each page's fixed headings, the facts it owns, and where they come from.
Headings are ASCII, and none repeats on a page (spec §7.1). A page's other
sections are its writer's.

| Page | Fixed `##` headings, with their ids | Owns | Sources |
|------|------------------------------------|------|---------|
| `README.md` (home) | none | what the library is, in two sentences; one short example each of `markdown->html`, an HTML tree and `parse`; safe by default, in two lines, linking `safety.md`; a line and a link for every page | `src/api.lisp`; the pages |
| `usage.md` (the pilot) | The package (`the-package`); Passing options (`passing-options`); Profiles (`profiles`); Large documents (`large-documents`): set by the pilot, and linked from other pages | the four entry points, one example each; options as keyword arguments, and the two profiles; binding the limits for large documents, linking `safety.md#size-limits` | `src/api.lisp` and its docstrings |
| `installing.md` | Debian and Ubuntu (`debian-and-ubuntu`); Building cmark-gfm from source (`building-cmark-gfm-from-source`); The library, through ocicl (`the-library-through-ocicl`); Where the library looks (`where-the-library-looks`); Choosing the libraries yourself (`choosing-the-libraries-yourself`); When cmark-gfm can't start (`when-cmark-gfm-cant-start`) | exactly 0.29.0.gfm.13, and why; the packages for Debian 13 and Ubuntu 26.04 LTS, the supported releases seen to ship it (25.04 and 25.10 are past their support), Homebrew and Guix; the source build; ocicl's steps; the search and its directories, both libraries from one directory; the two overrides, the Lisp variable first; the four startup conditions and their fixes; loading cmark-gfm's own files beside this library is unsupported | findings 7, 33 to 39; `src/native-core/discovery.lisp`; ADR-0002, ADR-0009; the startup conditions' docstrings; M4a finding 20; the probe logs |
| `options.md` | none | one table: each option, its values, default, the entry points that take it, and what it does; how options are passed, and the leftmost repeat winning | the docstrings of the four entry points and `ast->html-tree`; `src/native-core/options.lisp` |
| `ast.md` | Node kinds (`node-kinds`); Source positions (`source-positions`); Walking the tree (`walking-the-tree`) | what `parse` returns; a table of kinds and their attributes; the readers; building and copying, checked; the four walks, when to use each, no depth limit; positions in UTF-8 octets, cmark's own, some wrong or negative | `src/ast/`; ADR-0005, ADR-0015, ADR-0018; the project plan's Source positions |
| `html-tree.md` | Writing HTML (`writing-html`) | the tree's shape, with an example; the tree options in use, linking `options.md`; `html-tree->string` escapes, adds no layout, and checks no URL added after conversion; a whole page; the rare footnote inputs numbered unlike cmark's HTML | `src/html-tree/`; ADR-0010, ADR-0011, ADR-0012, ADR-0014 |
| `safety.md` | Safe by default (`safe-by-default`); Size limits (`size-limits`); The footnote guard (`the-footnote-guard`); Threads and timeouts (`threads-and-timeouts`) | raw HTML as a comment and dangerous URLs blanked, and how to opt out, and why not with untrusted input; the three limits, what each guards, defaults and caps, binding them; `unsupported-input` and avoiding it; what remains: a machine short of memory, cmark's other bugs; threads; coarse timeouts; ECL interrupts; CCL's first pair | ADR-0012, ADR-0016, ADR-0017, ADR-0019; M4a findings 13 and 20; the limits' docstrings |
| `errors.md` | none | every condition: when it is signalled and what to do, the startup four linking `installing.md#when-cmark-gfm-cant-start`; the readers; one `handler-case` example | `src/conditions.lisp`; the conditions' docstrings |
| `ecl.md` | A program with cmark-gfm linked in (`a-program-with-cmark-gfm-linked-in`) | ECL with dynamic FFI works as SBCL does; without it, `dynamic-ffi-unavailable`; the linked program's recipe; Debian's ECL loading its own ASDF as the program starts; on macOS, naming the archives' directory, untested there; a link to the interrupt warning | ADR-0021; `tests/static/`; the Makefile's `check-ecl-static`; CI's archives step; M4b's close-out |
| `support.md` | none | the support matrix, and how each cell is checked: CI on Linux amd64, macOS by hand before each release; CCL amd64 only; arm64 Linux unverified; no Windows; the Lisp versions tested | the project plan's support matrix; ADR-0001, ADR-0013; `make info` in CI and in the container |
| `reference.md` | generated | | |

Sidebar order, `*pages*`: `installing.md`, `usage.md`, `options.md`,
`ast.md`, `html-tree.md`, `safety.md`, `errors.md`, `ecl.md`,
`support.md`, `reference.md`.

## Task 1: M5a's nits

**Owns:** `site/render.lisp`, `site/pages.lisp`, `site/reference.lisp`
(only `*reference-page*`'s definition), `site/checks.lisp`,
`site/run-site.lisp`, `site/examples.lisp`, their tests in
`site/tests/`, and `tests/make-preflight.sh`.

1. **Red,** one test each:
   - **A31, B47:** a page holding the guard's pattern: `check-site`'s and
     `check-docs`' reports both say how to write it in a code block,
     building the string from two pieces, and give "a word between" for
     two code spans;
   - **A33:** a tracked entry `100644 <object> 0<TAB>tab<TAB>name.txt`
     reads as the path `tab<TAB>name.txt`, and an untracked entry holding
     a tab reads whole;
   - **B46:** each refused ref names its offending character or segment:
     a space, a `#`, a `.` segment, a `..` segment, a leading, a trailing
     and a doubled `/`;
   - **B45:** a preflight case with a stub `sbcl` and no `git`: `make
     check-site` and `make site` each exit 2, naming `git`.
2. **Implement.** Also, with no new test, since behavior doesn't change:
   - **A32:** `*reference-page*` is defined in `site/pages.lisp`, beside
     `*home-page*` and `*pages*`, and `render.lisp` drops its local
     special declaration;
   - **A34:** the comment in `site/run-site.lisp` no longer splits
     `REF-PROBLEM` across lines.
3. **Green:** `make check-site`, `make check-reference`, `make
   check-docs`, and the preflight.
4. **Mutations:** each fix reverted in turn fails its test; B45's case
   fails with `git` dropped from either target's `require-tools` line.

## Task 2: Backquotes in docstrings

Spec §7.2 and D13. **Owns:** `site/reference.lisp`,
`site/tests/reference.lisp`, the exported docstrings in `src/` that hold
typed text, and `docs/reference.md`.

1. **Red,** in `site/tests/reference.lisp`:
   - `` `libcmark-gfm.a` `` becomes the code span `libcmark-gfm.a`, the
     backquotes dropped;
   - what lies between is kept as written: its case, and its `*`, `_` and
     `<`, unescaped;
   - a lone backquote on its line stays escaped;
   - a backquote inside a double-quoted string stays in that string's
     span, and a double quote inside a backquoted run stays in that run;
   - the render check passes an entry holding backquoted runs.
2. **Implement.**
3. **The docstrings:** mark with backquotes the typed text no other rule
   makes code: file names, such as `libcmark-gfm.so.0.29.0.gfm.13` and
   `libcmark-gfm.a`; multiarch names, such as `x86_64-linux-gnu`; and
   `data-sourcepos`. Prose names, such as "libcmark-gfm" for the
   library, stay prose. A form check, as M5a's in
   `.guix-env/tmp/docstrings/`, shows only docstrings changed.
4. **Generate** `docs/reference.md` with `make reference`. Green: `make
   check-reference`, `make check-site`, `make check-docs`, and `make
   check-purity` on all three Lisps.
5. **Mutations:**
   - backquoted runs escaped as before: the first two tests fail;
   - a lone backquote made a code span: its test fails;
   - a docstring's backquotes dropped without `make reference`: `make
     check-reference` names the symbol.

## Task 3: Page stubs

**Owns:** the nine new `docs/*.md` and `*pages*` in `site/pages.lisp`.

Each stub has its `#` heading, a line saying the page is being written,
and the outline's fixed headings, so every link the pages make resolves
from the start. `*pages*` lists them in the sidebar's order. Then warm
the fasls with one `make check-site check-docs`, which must pass.

## Task 4: The pilot, `usage.md`

D12. **Owns:** `docs/usage.md`.

Write it from its outline row and the page brief. It sets the voice and
shape the other pages follow: how a section opens, how long an example
is, how a page links the reference. Then **stop**: the maintainer reads
it. Their changes go back to the same agent. The pilot's settled
headings become fixed.

## Task 5: The other pages

Six Opus agents in parallel, each with the page brief, its outline rows,
and the approved `usage.md`:

| Task | Pages |
|------|-------|
| 5A | `installing.md`, `support.md` |
| 5B | `options.md`, `html-tree.md` |
| 5C | `ast.md` |
| 5D | `safety.md`, `errors.md` |
| 5E | `ecl.md` |
| 5F | `README.md`, the home page, by the pilot's agent |

- **5A** writes `installing.md`'s shell steps for the exit test (Task 6):
  `debian-and-ubuntu` holds one ```` ```sh ```` block installing the two
  packages; `building-cmark-gfm-from-source` holds the build's ```` ```sh
  ```` blocks; `the-library-through-ocicl` holds the ```` ```sh ````
  blocks from `ocicl setup >> ~/.sbclrc` to `ocicl install
  cl-commonmark-gfm`, then one ```` ```lisp ```` block that loads the
  library and makes a first call, with its `;; =>`. The page says to
  install SBCL from the system's packages, and ocicl as its README says,
  linking it: neither is the page's to restate. macOS's steps can't run
  here; the release's macOS run checks them (finding 7).
- **5E** tries the recipe by hand: it builds a small program by the
  page's steps, in the Guix container with dynamic FFI and in the one
  without (`GUIX_ENV_MANIFEST`), and reports both runs.

## Task 6: The exit test

Spec §1, D10 and D11. **Owns:** `tests/install-docs.sh` (new).

A host script that starts its own container, so it runs on the host, not
through `scripts/guix-env`: `tests/install-docs.sh debian` uses
`debian:trixie`, and `tests/install-docs.sh source` uses `ubuntu:24.04`.

1. In the container, as a user with `sudo`: install SBCL from the system's
   packages, and ocicl by its README's apt repository.
2. Run, in order, the ```` ```sh ```` blocks under `installing.md`'s
   `debian-and-ubuntu` heading, or under `building-cmark-gfm-from-source`,
   then those under `the-library-through-ocicl`, read from the working
   tree's page. A missing heading or block fails the test.
3. **The stand-in (D10):** in place of `ocicl install cl-commonmark-gfm`,
   copy the repository's tracked files into
   `ocicl/cl-commonmark-gfm-0.0.0/`, and write the `ocicl.csv` row ocicl
   would. `STAND_IN=0` runs the real step, for the release.
4. Run the page's ```` ```lisp ```` block in SBCL, started in the
   project's directory, and compare its last value with its `;; =>`.
5. **Seen to fail:**
   - with the package or build step skipped, the first call signals
     `native-library-not-found`, which the page explains;
   - with a package name misspelled in a copy of the page, its step
     fails.
6. Run both modes on the final pages, and record them.

## Task 7: Documents

**Owned by the orchestrator.**

- **Part 1,** alongside Task 1:
  - **AGENTS.md:** the guard's pattern in a Lisp example; backquotes for
    typed text in an exported docstring (D13); then, as the pages showed
    the need, real line breaks in an example's Markdown, only `usage.md`
    defining a package, and the pilot's conventions;
  - **ADR-0022:** amended by D13, its status and its list of what the
    reference shows as code;
  - **the project plan's M5:** M5b's plan, and the exit test's stand-in.
- **Part 2,** alongside Task 8:
  - **README.org:** a Documentation section linking `docs/`. The site's
    link waits for the release;
  - **`progress.md`:** the M5 row and checklist, "For the release" (the
    exit test rerun with the real ocicl step, README.org's site link),
    and the close-out.

## Task 8: Review and close-out

- **Two Opus reviewers,** read-only, in parallel:
  - **A, the facts:** every page's claims against the code, the
    docstrings, the ADRs and the probe logs, starting from the writers'
    ledgers; and whether each example shows what it says;
  - **B, the writing and the rest:** AGENTS.md's rules on every page, one
    voice across them, each fact on one page, links and headings; Tasks 1
    and 2's code and tests; the exit test; the documents.

  Probes go on copies under `.guix-env/tmp/`, with the repository's `.git`
  copied in.
- **Fixes** go back to their writers. Decisions go to the maintainer in
  one batch. A second review follows the fixes, scoped to them.
- **`main`'s CI steps and `pages.yml`'s build steps in `debian:trixie`,**
  against the working tree, with `.guix-env/tmp/ci-proof-m5a/run-tree.sh`.
- **The exit test,** both modes, on the final pages (Task 6).
- **Close-out** in `progress.md`: what was written, the evidence, the
  counts, anything for the release, and new findings in the spec.
