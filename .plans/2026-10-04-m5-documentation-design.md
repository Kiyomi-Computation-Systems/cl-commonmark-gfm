# M5: documentation — design

- **Date:** 2026-10-04
- **Status:** Approved 2026-10-04. Amended 2026-10-04 by the probes
  before M5a's plan: findings 11 to 15; finding 4's repeat rule, now seen
  on GitHub; §6.2's heading text; §6.5's and §7.1's need for cmark-gfm;
  §7.3's subtypes and nodes; §6.4's previous and next links, and its
  closing line. Amended during M5a: §6.4's `theme.js`, last in the body;
  §4's `:document-wrapper`; finding 16 and §8's deploy from tags only;
  §11's ADR-0014; findings 17 to 19, with §6.3's paths and §7.1's check 6;
  §7.2's order of kinds, and which symbols become code; §7.3's first
  value, errors, continuation lines and output; findings 20 to 28, with
  §5's two rules for examples. Amended by M5a's first review: §6.3's
  images, other files and ref; §7.1's checks 1, 3, 6 and 7; §7.3's
  fences, `#+`, markers, bindings, `*package*` and summary line; §8's
  checks, permissions and timeout; §11's ADR-0013; findings 27 and 28
  amended, and 29 to 31. Amended by the maintainer's decisions on that
  review: §7.2's narrow escaping, render check, opening line and code for
  what users type; every docstring the reviews found fixed in M5a (§11);
  §6.3's and §7.1's check that repository links exist. Amended by the
  second review: §6.3's links checked through git; §7.3's warnings; §8's
  permissions; §9's new rows. Amended by the third review: §6.3's ref
  segments; §6.5's git; §7.1's check 3 and §7.2's render check in
  `check-reference`; finding 32, with §5's rule
- **Milestone:** M5, the release candidate: its documentation, in two
  slices, each with its own plan, branch and PR. M5a builds the machinery
  (§4, §6 to §8), and M5b writes the pages (§5). The release itself is a
  later M5 step (§12).
- **Inputs:**
  - the [project plan](cl-commonmark-gfm.org)'s M5 and its support
    matrix;
  - the "For M5's documentation" hand-offs in [progress.md](progress.md),
    from M4a and M4b;
  - the documentation promises in ADR-0010, 0014, 0016, 0017, 0019, 0020
    and 0021;
  - chez-cmark-gfm at `e0118a3`: its `docs/`, its site design
    (`.plans/2026-08-22-docs-site-design.md`), its generator (`site/`)
    and its `.github/workflows/pages.yml`;
  - AGENTS.md's rules for `/docs`.

Each rule below is stated here once.

## 1. Goal

A user can install and use the library from `docs/` alone. The library
itself renders `docs/` into a site, which GitHub Pages serves from the
first release on.

**Success, M5a (the machinery):**
- `html-tree->string` writes HTML's 13 void elements as void (§4).
- `make site` renders `docs/` into `build/site/`, through the library's
  public API alone (§6).
- `make check-site`, `make check-reference` and `make check-docs` pass in
  `make test`, on every pull request (§7), and each has been seen to fail
  (§9).
- `docs/reference.md` is generated, for every export (§7.2).
- `.github/workflows/pages.yml` is in place. Its first run is at the first
  release (§8).
- `make test` and `main`'s CI steps pass in the Guix container and in a
  local `debian:trixie` run.

**Success, M5b (the pages):**
- `docs/` holds the home page and the ten pages of §5, each following §5's
  writing rules, every Lisp example run by `make check-docs`.
- The plan's M5 exit test, for the docs: `installing.md`'s Debian steps,
  followed in a fresh `debian:trixie` container, give a working install,
  or a condition the page explains. The release's manual macOS run checks
  the macOS steps (finding 7).

## 2. Decisions made while brainstorming

- **D1. Go-live at the first release.** The site is built and checked from
  now on, but deployed only from a release tag, the first one when the
  repository goes public (finding 1).
- **D2. Ten short pages, plus a home page** (§5).
- **D3. The reference is generated from the docstrings.** `make reference`
  writes `docs/reference.md`; `make check-reference` fails when it is out
  of date, or an export has no docstring (§7.2).
- **D4. The site reuses chez-cmark-gfm's theme:** its `style.css`, its
  layout and its light and dark modes.
- **D5. Every Lisp example in `docs/` runs,** in `make check-docs` (§7.3).
- **D6. The three checks run in `make test`,** on every pull request, on
  SBCL.
- **D7. `html-tree->string` learns HTML's void elements** (§4), so the site
  can write a whole page as a tree. This amends ADR-0010.
- **D8. The home page is `docs/README.md`:** GitHub shows it when `docs/`
  is opened, and the site renders it as `index.html`.
- **D9. `pages.yml` reuses CI's container and toolchain script,** so the
  site is built with the SBCL and cmark-gfm that CI tests.

## 3. Findings

1. **The repository is private.** The organization's GitHub Team plan
   serves Pages from a private repository, but the site itself is public.
   Deploying before the code is public would publish the docs first. So:
   D1.
2. **`html-tree->string` knows only cmark's void elements:** `br`, `hr`,
   `img` and `input` (`*void-element-names*`). A page's `<meta>` and
   `<link>` would print with end tags. Browsers ignore those, but the HTML
   isn't valid. So: D7.
3. **It escapes text inside `<script>` and `<style>`,** as everywhere
   else. A browser doesn't decode entities there, so inline JavaScript
   holding `&`, `<` or `>` would break. chez inlines its theme script and
   keeps it free of those three characters; here it lives in `theme.js`
   instead, with no such limit.
4. **GitHub's heading ids follow github-slugger's rule.** GitHub's file
   viewer adds them; the contents API returns its HTML
   (`Accept: application/vnd.github.html`), and the `/markdown` API adds
   no ids at all. Read from chez's public `docs/`:
   - `markdown->html (procedure)` gives `markdown-html-procedure`;
   - `hardbreaks? and nobreaks?` gives `hardbreaks-and-nobreaks`;
   - `Serializing: your serializer, not ours` gives
     `serializing-your-serializer-not-ours`.

   The rule: lowercase the heading's text; drop every character but
   letters, digits, `-`, `_` and spaces; turn each space into `-`, with no
   collapsing. A repeated id on one page gets `-1`, then `-2`, counted per
   id (finding 11).
5. **The main package re-exports every public symbol.** `cl-commonmark-gfm`
   exports 49: its own 8, the AST package's 14, the HTML tree's 2 and the
   conditions' 25. Every one has a docstring. So the reference documents
   `cl-commonmark-gfm`, one section per home package (§7.2). Two of its
   names slug alike, `node` and `node=`, so the reference needs finding
   4's repeat rule.
6. **SBCL's lambda lists need care.** `sb-introspect:function-lambda-list`
   gives package-qualified names (`cl-commonmark-gfm::markdown`), an
   internal one for `node-p` (`sb-kernel::object`), and `(function node)`,
   which `prin1` prints as `#'node`. The generator prints each parameter
   by its lowercase name alone.
7. **Homebrew's cmark-gfm is 0.29.0.gfm.13,** pinned against automatic
   updates. No manual macOS run has been recorded yet (progress.md), so
   the macOS steps are checked only by the release's run (ADR-0001).
8. **The AST carries what the generator rewrites:** `:link` and `:image`
   nodes' `:destination`, `:heading`'s `:level`, `:code-block`'s `:info`,
   and `:html-block` and `:html-inline` nodes for raw HTML.
9. **The system has no `:version`.** The site's footer names the release
   tag instead (§6.4).
10. **CI's toolchain** installs Debian's SBCL 2.5.2 and cmark-gfm's two
    libraries (`ci/install-toolchain.sh`), all the site needs. So: D9.

Probes before M5a's plan (§10) found the rest:

11. **GitHub numbers repeated ids per id.** In keep-a-changelog's
    `CHANGELOG.md`, the "Added" headings get `added`, `added-1`,
    `added-2`, and the "Fixed" ones `fixed`, `fixed-1`, in step. A heading
    `2.0.0 - 2026-06-07` gets `200---2026-06-07`.
12. **One page goes through §6.2 on the public API alone.** A probe page
    with a table, a code block, a ⚠️ blockquote and a link of each §6.3
    kind went through `parse`, `transform-ast` (with `copy-node` for each
    link), `fold-ast` (for each heading's text), `ast->html-tree` and
    `html-tree->string`:
    - a heading's text is its `:text` and `:code` nodes' literals, in
      order: `` `markdown->html` and `*max-nodes*` `` gives
      `markdown-html-and-max-nodes`, and a second "A table" `a-table-1`;
    - a code block keeps cmark's `class="language-lisp"`;
    - the tree keeps cmark's `"\n"` strings between blocks, so the pages'
      HTML is laid out as cmark's;
    - `<meta charset="utf-8"></meta>` and `<link ...></link>`, as finding 2
      said.
13. **Printing, for §7.3.** Strings, trees and keywords print short:
    `"<p><em>hi</em></p>\n"`, `((:p nil (:em nil "hi")) "\n")`,
    `:document`. A node prints as `#S(node ...)`, with every slot and its
    children's, so the examples show what the readers return, not whole
    nodes. `(markdown->html 42)` signals `simple-type-error`, a subtype of
    `type-error`.
14. **Time.** In the Guix container, a process that loads the compiled
    library and renders the probe page took about 1.1 s, the container's
    start included.
15. **The same in `debian:trixie`.** With CI's toolchain, Debian's SBCL
    2.5.2 and the directory search, the probe page's HTML and the printing
    were byte for byte the Guix container's.

Found during M5a:

16. **chez's site has never been deployed from a tag.** Its four Pages
    runs were all started by hand, from `main`: its tags predate its
    `pages.yml`. Its `github-pages` environment allows deployments from
    `main` alone, a branch policy, so a tag's deploy job would be refused.
    Here, the environment must allow `v*` tags before the first release's
    deploy (§8).
17. **A path starting with `/` is read from the repository's root,** as
    GitHub reads it in a Markdown file: `/src/api.lisp` goes to the same
    `/blob/` URL as `../src/api.lisp` (§6.3).
18. **An image inside `docs/` would show broken on the site.** Its
    `/blob/` URL is GitHub's page for the file, not the image. No page
    plans one. If M5b needs an image, the shell must copy it into the site,
    or the link must use GitHub's raw URL.
19. **Finding 4's rule can give two headings one id.** Headings `A`, `A 1`
    and `A` get `a`, `a-1` and `a-1`. What GitHub does then isn't known, so
    the site refuses it (§7.1).
20. **A remark in parentheses isn't a form.** The entry points' docstrings
    hold "(*CMARK-GFM-LIBRARIES*, CL_COMMONMARK_GFM_LIBS, or a search of a
    fixed list of directories)", whose first word names something. So a
    parenthesized form becomes code only when it has no lower-case letter
    outside its strings, and its strings keep their case (§7.2).
21. **The code rule looks words up in `cl-commonmark-gfm`,** the package
    the reference documents. The conditions' docstrings name `make-node`
    and `parse`, which the conditions package can't see, and the home of
    the three limit variables and `*cmark-gfm-libraries*`,
    `cl-commonmark-gfm.native-core`, can't see `parse`. Sections still go
    by home package; those four variables fall in the first (§7.2).
22. **The first differing entry can't be found by the first differing
    character.** The blank line between two entries belongs to neither,
    so a character position can name a neighbour; both placements were
    seen to fail. `make check-reference` cuts both texts before each `##`
    and `###` line and compares the pieces.
23. **Escaping every other ASCII punctuation character makes the raw
    Markdown noisy:** `a string\, to HTML\.`. It renders as written, on
    GitHub and on the site. The review found that GitHub ignores the
    escapes for its own extensions anyway: `\:smile\:` still renders an
    emoji, and `\$x\$` math. The maintainer chose to escape only
    Markdown's and GFM's syntax characters, by position, with a check
    that renders every entry back (§7.2).
24. **Functions and macros sort as one group.** No macro is exported.
25. **A marker with the wrong number of semicolons would be skipped.** A
    `; =>` or `;;; =>` reads as a remark, so its value would go unchecked.
    `make check-docs` finds markers whatever their semicolons, and refuses
    any but two (§7.3).
26. **A malformed expectation is refused, not ignored:** a marker before a
    block's first form, a second marker after one form, `;; =>` with no
    value, `;; signals` with no type or with `nil`, and text the reader
    refuses. Each would otherwise leave a claim unchecked.
27. **The reader can still swallow an expectation:** after a `#+` or `#-`
    whose feature is false, which skips the next form and the comments
    after it; and a `;; =>` inside a form that spans lines. The pages use
    neither (§5). Since M5a's first review, both are detected: the check
    refuses `#+` and `#-`, and a marker inside a form's own text (§7.3).
28. **Pages share the image's global state.** Each page has its own
    package, but an example that `setf`s a library variable, such as
    `*max-nodes*`, would carry into later pages. Examples bind such
    variables with `let` (§5). Since M5a's first review, each page also
    runs under fresh bindings of the library's exported variables, so a
    `setf` stays on its page.
29. **GitHub's published id rules differ from §6.2's outside ASCII.**
    github-slugger and html-pipeline both keep combining marks and U+FE0F,
    which finding 4's rule drops, and they disagree with each other on
    lowercasing non-ASCII letters. A heading's image and footnote
    reference fall outside the text they slug. What github.com does today
    wasn't checked, so the site refuses such headings, as finding 19 does
    (§7.1).
30. **An example that ends the process passed `make check-docs`.**
    `(uiop:quit 0)` exited 0 with no summary line, and the pages after it
    never ran. The recipe requires the summary line as well as exit status
    0, as the global constraints require of ECL programs.
31. **Other spellings of a marker read as remarks:** `;; ==>`, `;; ->`,
    `;; →`, `;; Signals`, and a `;; =>` after a block comment on its line.
    Each would leave a claim unchecked, so each fails the check (§7.3).
32. **The footnote guard refuses a page that shows its own pattern.**
    `parse` refuses `[` followed by an entity that decodes to `^`
    anywhere in its input, a code span included, so a page or a
    docstring quoting `[&#94;` can't be parsed. `check-site`, `make site`
    and `check-reference` report it as that page's or entry's problem.
    In a page, to show the pattern outside code, write its `&` as
    `&amp;`: `[&amp;#94;` renders as `[&#94;`. Inside a code span `&amp;`
    shows as written, so split the pattern into two spans with a word
    between, as in "a `[` then `&#94;`", which renders as code and isn't
    refused. In a docstring, the generator escapes the `[` and the `&`
    itself, so write the pattern plainly, outside double quotes; as code,
    split it into two quoted strings, as `unsupported-input`'s docstring
    does (§5).

## 4. The serializer's void elements (M5a)

- `*void-element-names*` becomes HTML's list: `area`, `base`, `br`, `col`,
  `embed`, `hr`, `img`, `input`, `link`, `meta`, `source`, `track` and
  `wbr`.
- Each prints as `<tag ... />`, as `br` does now. Given children, each
  signals `invalid-html-tree`.
- Trees from `ast->html-tree` don't change: cmark writes only `br`, `hr`,
  `img` and `input`. A hand-built tree changes if it holds one of the nine
  new names: it prints void, or signals if it has children.
- `:document-wrapper` takes only a non-void element, so the nine new names
  are refused there too, with `invalid-render-option`. Before, they were
  accepted, and the wrapper printed with an end tag.
- **Tests,** in the pure suite: each of the 13 prints as `<tag />` with an
  attribute, and signals with a child. The nine new ones fail before the
  change. The test that refuses a void `:document-wrapper` names one of
  the nine.
- `html-tree->string`'s docstring, `*void-element-names*`' docstring and
  ADR-0010's status line say so.

## 5. The pages (M5b)

| Page | Covers |
|---|---|
| `README.md` (home) | What the library does, in two sentences. A taste: `markdown->html`, an HTML tree and `parse`, one short example each. Safe by default. A link to every page. |
| `installing.md` | cmark-gfm 0.29.0.gfm.13: exactly that version, and why. Packages for Debian and Ubuntu, macOS (Homebrew) and Guix. The library through ocicl. Which directories are searched, and why both libraries must come from one of them. The two overrides; the Lisp variable wins. Each condition startup can signal, with its fix. Loading cmark-gfm's library files yourself beside this library is unsupported. |
| `usage.md` | The four entry points, one example each. Options as keyword arguments; the `:gfm` and `:commonmark` profiles. Binding the limits for large documents, linking to `safety.md`. |
| `options.md` | One table: each option, its values, its default, the entry points that take it, and what it does. |
| `ast.md` | What `parse` returns: each node's kind, attributes, children and position. A table of kinds and their attributes. Reading nodes; building and copying them, checked. The four walks, and when to use each; no depth limit. Positions are cmark's own, counted in UTF-8 bytes, and a few are wrong or negative. |
| `html-tree.md` | The tree's shape, with an example. The tree options. `html-tree->string` escapes, adds no layout, and doesn't check URLs added to the tree afterwards. Writing a whole page. The rare footnote inputs whose numbering differs from cmark's HTML. |
| `safety.md` | Safe by default: raw HTML becomes a comment, dangerous URLs are blanked; how to opt out, and why not to with untrusted input. The three size limits: what each guards, its default and cap, binding it. The footnote guard: `unsupported-input`, and how to avoid it. What remains: a machine short of memory can still make cmark abort, and cmark has other parser bugs. Threads: parallel parses are safe; another cmark-gfm user in the same process can race. Timeouts are coarse, and on ECL interrupting a call isn't safe. A CCL process keeps the first library pair it loads. |
| `errors.md` | Every condition: when it is signalled, and what to do. The readers. One `handler-case` example. |
| `ecl.md` | ECL with dynamic FFI works like SBCL. Without it: `dynamic-ffi-unavailable`. A linked program's recipe; Debian's ECL loads its own ASDF as the program starts; on macOS, `CMARK_GFM_ARCHIVE_DIR`, and the static check hasn't run there. A link to the interrupt warning. |
| `support.md` | The support matrix, and how each cell is verified: CI on Linux amd64; macOS by hand before each release. CCL is amd64 only; arm64 Linux is unverified; Windows is unsupported. The Lisp versions tested. |
| `reference.md` | Generated (§7.2). |

**Writing rules,** added to AGENTS.md:
- **Short and plain:** short sentences, one idea each, plain words; what
  to do first, then why. Most pages stay under about 150 lines.
- **Users only:** no ADRs, findings, milestones or project history.
- **Each fact on one page;** others link to it.
- **Symbols in lower case,** as users type them: `markdown->html`,
  `*max-nodes*`.
- **Every Lisp example runs** (§7.3), its results shown with `;; =>`. An
  example shows what a reader returns, never a whole node (finding 13).
  It binds a library variable with `let`, never `setf`, and uses no `#+`
  or `#-` (findings 27 and 28).
- **The footnote guard's pattern,** a `[` before an entity for `^`, is
  never written whole in a page: outside code its `&` is written `&amp;`,
  and as code it is split into two spans. In a docstring it is written
  plainly, which the generator escapes, or as two quoted strings for code
  (finding 32).
- **Markdown only:** no raw HTML (§7.1).

M5a writes `docs/README.md` as a short placeholder, so the site and its
checks have a home page; M5b replaces it.

## 6. The generator (M5a)

### 6.1 Files

- `site/cl-commonmark-gfm-site.asd`: the generator's system, and its
  tests'. It stays out of `cl-commonmark-gfm.asd`, so it never ships with
  the library. The Makefile adds `site/` to `CL_SOURCE_REGISTRY` for its
  targets, as it adds `tests/static/` for the static check.
- `site/*.lisp`: the pure core (§6.2 to §6.4) and the shell (§6.5).
- `site/pages.lisp`: the sidebar's pages, in order. Each label is the
  page's first heading.
- `site/style.css`: chez's, as it is (D4). `site/theme.js`: chez's theme
  script, as a file (finding 3).

### 6.2 One page, through the library's public API

1. `parse` the page as GFM.
2. `transform-ast` rewrites each `:link` and `:image` destination (§6.3).
3. Each heading gets an id from its text, its `:text` and `:code`
   literals in order, by finding 4's rule. The page's `##` headings make
   its "On this page" list.
4. `ast->html-tree` converts the AST, with the defaults: raw HTML omitted
   and the safe link policy. The ids go onto the heading elements, in
   order. A blockquote whose text starts with ⚠️ gets chez's warning
   class.
5. The template (§6.4) wraps the page, and `html-tree->string` writes it.

`render-site` is the pure core: the pages' texts and the release ref in;
each page's HTML, every page's ids, and the problems found out (§7.1).
It reads and writes no file.

### 6.3 Links

| Destination | Becomes |
|---|---|
| `page.md`, or `page.md#id`, for a page in `docs/` | `page.html#id`; `README.md` becomes `index.html` |
| `#id` | unchanged |
| a URL with a scheme, or starting with `//` | unchanged |
| any other relative path, such as `../src/api.lisp`, or a path from the repository's root, such as `/src/api.lisp` (finding 17) | `https://github.com/Kiyomi-Computation-Systems/cl-commonmark-gfm/blob/<ref>/src/api.lisp` |

A `.md` path inside `docs/` that names no page, or a path that climbs
out of the repository, is a problem (§7.1). A `.md` path outside `docs/`,
such as `../CHANGELOG.md`, goes to GitHub like any other file. An image
with a relative path is a problem too: its `/blob/` URL is GitHub's page
for the file, not the image (finding 18). So is any other relative
destination inside `docs/` that isn't a page, such as `usage.html`: the
site copies no files. A link that goes to GitHub must name a file or
directory that GitHub's `/blob/` URL serves: the core reports each such
path, and the shell asks git, through `git ls-files --cached --others
--exclude-standard`. So an ignored file, such as one under `build/`, and
a path inside the cmark-gfm submodule are refused, as GitHub doesn't
serve them. The ref is `SITE_REF`: in
`pages.yml`, the tag or the ref a manual run was started on, and `main` by
default. It must be non-empty, hold no character a URL's path can't
carry as it is, and keep its links inside `/blob/`: no `.` or `..`
segment, and no leading, trailing or doubled `/`.

### 6.4 The template

Built as an HTML tree, after chez's `site/template.sls`, with its class
names, so `style.css` applies unchanged:
- `<head>`: `meta` charset and viewport; the title, from the page's first
  heading (the home page's is the project's name); `style.css`.
- a sidebar: the project's name, linking home, and the pages of
  `site/pages.lisp`, the current one marked;
- the content, then links to the previous and next pages, as chez's
  `pagenav`, then a closing line: "Rendered from Markdown by
  cl-commonmark-gfm", and the ref. chez's `style.css` has no footer rule,
  so the line closes the content's column;
- the "On this page" list;
- the theme toggle, and `theme.js` last in the body, where chez's inline
  script is: it looks the toggle up as it runs, so the toggle must come
  first.

The shell writes `<!DOCTYPE html>` before the serialized tree.

### 6.5 The shell, and `make site`

`make site` reads `docs/*.md`, calls `render-site`, writes
`build/site/<page>.html`, and copies `style.css` and `theme.js`. It fails
on any problem `render-site` reports. `SITE_REF` sets the ref. Links are
relative, so `build/site/index.html` opens from disk. `parse` calls
cmark-gfm, so `make site`, like `check-site`, `check-docs` and
`check-reference`, whose render check parses each entry, needs it,
as `check-native` does. `make site` and `check-site` also need git, to
check the repository links (§6.3).

## 7. The checks (M5a)

All three run in `make test`, on SBCL (D6). Each names what fails.

### 7.1 `make check-site`

First the generator's own tests: ids against finding 4's examples, the
link table, the docstring conversion (§7.2) and the example reader
(§7.3). Then `render-site` over `docs/`, failing when:
1. `site/pages.lisp` and `docs/*.md`, less `README.md`, don't name the
   same pages, `site/pages.lisp` names one twice, or a `.md` file sits in
   a directory below `docs/`, where the site would never render it;
2. a link inside the site doesn't resolve: `page.html#id` must name a page,
   and an id on it; `#id` an id on its own page;
3. a relative link still ends in `.md`, or climbs out of the repository,
   or names a file in `docs/` that isn't a page, or names a repository
   path GitHub's `/blob/` doesn't serve (§6.3); or an image has a
   relative path;
4. a page holds raw HTML, which the site would turn into a comment;
5. a page doesn't start with exactly one `#` heading;
6. two headings on one page get the same id (finding 19), or a heading's
   id is empty;
7. a heading holds a non-ASCII character, an image or a footnote
   reference (finding 29).

### 7.2 `make reference` and `make check-reference`

`make reference` writes `docs/reference.md`; `make check-reference` builds
the same text in memory and fails when the file differs, naming the first
symbol whose entry differs, when an export has no docstring, or when an
entry fails the render check below.

- **Layout:** an opening line saying the page lists every exported
  symbol, from its docstring; then one section
  per home package (rendering and parsing, the AST, the HTML tree,
  conditions); within each, types (structures, then conditions), then
  functions and macros, then variables, each kind alphabetical. `node`
  names a structure, so it comes before `node=` and keeps the id `node`.
- **Each entry:** a heading with the symbol's name; its kind (a condition
  also names its parents); a function's lambda list, by bare lowercase
  names (finding 6); then its docstring.
- **Docstrings into Markdown:**
  - blank lines separate paragraphs;
  - a line starting with `- ` starts a list item, and its indented lines
    continue it;
  - an upper-case keyword, `*special*` name, or symbol that names
    something becomes lower-case code: in `cl-commonmark-gfm`, a function,
    macro, variable, class or type, or one of the entry's parameters; or
    an external symbol of `common-lisp` (finding 21). A symbol that is
    merely interned, such as a local variable's name, doesn't count. So
    does a parenthesized form whose first word is such a symbol and which
    has no lower-case letter, and no comma, outside its strings, whole,
    its strings keeping their case (finding 20);
  - what users type as written becomes code too, its case kept: a
    double-quoted string, quotes included; an upper-case name holding an
    underscore, such as an environment variable or a C macro; and an
    absolute path;
  - only the characters Markdown and GFM give meaning to are escaped:
    ``\ ` * _ [ ] < & | ~`` anywhere, and at the start of a paragraph or
    list item `# > + - =` and the `.` or `)` after a leading number. The
    rest stay as written, so the raw file reads cleanly (finding 23);
  - **the render check:** `make check-reference`, and a test in `make
    check-site`, render every entry of the real reference and fail when
    one comes out as anything but its own text in `p`, `ul`, `li` and
    `code` elements, saying what to quote. The narrow escaping rests on
    it.

### 7.3 `make check-docs`

Runs every ```` ```lisp ```` block in `docs/`, page by page, each page in
a fresh package that uses `common-lisp` and `cl-commonmark-gfm`. Blocks
run in order, so a page's later examples can use its earlier ones. It
needs cmark-gfm, as `check-native` does.
- **`;; => value`** after a form: the form's first value is that value.
  The value is printed with `prin1`, symbols in lower case, and each
  newline written `\n`: `(markdown->html "*hi*") ;; =>
  "<p><em>hi</em></p>\n"`. The expected text may continue on the `;;`
  lines directly after it, so a prose comment below an expectation needs a
  blank line first; runs of whitespace compare as one space.
- **`;; signals name`:** the form signals an error of that type, or of a
  subtype (finding 13).
- **Neither:** the form must not signal an error.
- An example's output to `*standard-output*` is discarded.
- Blocks are found by `parse`, as cmark reads the fences. Every page in
  `docs/` runs, listed or not.
- Markers take two semicolons, and a malformed expectation fails the check
  (findings 25 and 26). Each form is read after the one before it has run,
  so a `defpackage` example works.
- **```` ```lisp no-run ````** marks a block that can't run here, such as
  ECL's linked-program recipe. Any other info string that starts with
  `lisp`, or names Lisp another way (`Lisp`, `common-lisp`, `cl`), fails
  the check, so a typo can't turn an example off.
- An example read with `#+` or `#-` fails the check, and so does a marker
  inside a form's own text (finding 27). So does any other spelling of a
  marker, or one hidden after a block comment (finding 31).
- Each page runs under fresh bindings of the library's exported
  variables (finding 28). A form that leaves `*package*` changed fails the
  check: every form is read in the page's package.
- `make check-docs` passes only with exit status 0 and its summary line,
  which needs at least one example in `docs/` (finding 30).
- Style-warnings and compiler notes from examples are muffled. Any other
  warning fails the check: an undefined variable means the example is
  wrong. So does a type the compiler can see is wrong, such as `(let ((x
  "a")) (+ 1 x))`, even under `;; signals type-error`; an example shows a
  type error through a library call, such as `(markdown->html 42)`, which
  draws no warning.

## 8. Deployment (M5a)

`.github/workflows/pages.yml` runs on a `v*` tag push, or by hand
(`workflow_dispatch`):
- in CI's `debian:trixie` container, with `ci/install-toolchain.sh` and
  `make deps` (D9);
- `make check-site`, `make check-reference` and `make check-docs`, since
  a tag can name a commit that CI never checked; then `make site
  SITE_REF=<ref>`, the tag or the ref a manual run was started on;
- `actions/upload-pages-artifact`, then `actions/deploy-pages`;
- permissions `pages: write` and `id-token: write` on the deploy job alone,
  and `contents: read` for the build job; a 30-minute timeout, as CI's; a
  concurrency group, so two deploys don't race.

The deploy job runs only for a `v*` tag (D1). A manual run on a branch
builds and checks the site, and uploads it, but deploys nothing: a dry
run of the workflow before the first release. A manual run on a tag
deploys it again.

Nothing it generates is committed. It runs only on tags and by hand, so
pull requests cost nothing more than §7's checks. Two manual steps come
with the first release, before its tag is pushed: Settings → Pages →
Source: GitHub Actions; and, in the `github-pages` environment, a
deployment rule allowing `v*` tags (finding 16).

## 9. Seen to fail

| Check | The change that must make it fail |
|---|---|
| §4's void-element tests | the nine new names absent from `*void-element-names*` (before the change) |
| §7.1, 1 | a page left out of `site/pages.lisp` |
| §7.1, 2 | an id rule that keeps `.`; a link to a missing anchor |
| §7.1, 3 | the `.md` rewrite disabled |
| §7.1, 4 | a raw `<b>` in a page |
| §7.1, 5 | a page whose first heading is `##` |
| §7.1, 6 | headings `## A`, `## A 1` and `## A` on one page; `## !!!` |
| §7.1, 7 | a heading holding `é`, an image or a footnote reference |
| §6.3's repository links | a link to `../src/nope.lisp`, or to an ignored file |
| §7.2's render check | no escape at a block's start; the `*` escape dropped |
| §7.3's fences and markers | a block fenced `lisp norun`; `#+nil`; `;; ==>`; a marker after `#\| … \|#` |
| §7.3's summary line | an example that calls `(uiop:quit 0)` |
| §7.3's warnings | `(defun h (x) (+ x free-y))`, an undefined variable |
| §6.3's ref | `SITE_REF` empty, holding a space or `#`, or `../x` |
| §7.2 | a docstring edited without `make reference`; a docstring removed |
| §7.3 | a wrong `;; =>` result; a `;; signals` form that returns |
| the generator's own tests | each rule of §6.3 and finding 4, broken in turn |

## 10. Slices, and probes before each plan

**M5a, the machinery,** on its own branch: §4, §6, §7, §8, the placeholder
home page, the generated reference, and AGENTS.md's writing rules.
Probes before its plan, all run (findings 11 to 15):
- one real page through §6.2 end to end, with a table, a code block and
  links of each §6.3 kind, on SBCL in the Guix container and in
  `debian:trixie`;
- finding 4's repeat rule, read through the contents API from a public
  file with repeated headings, such as a changelog's "Fixed" under each
  version;
- §7.3's printing on the values the pages will show: strings, trees,
  nodes and conditions;
- how long §7's checks add to `make test`: about a second for each Lisp
  process, warm (finding 14). M5a's plan measures the real cost.

**M5b, the pages,** on its own branch once M5a has merged: §5's pages,
README.org's Documentation section, and the fresh-container check of §1.

## 11. Documents

- **ADR-0022, the documentation:** D1 to D9, in short.
- **The exported docstrings:** every one the reviews found reading
  wrongly in `docs/reference.md` is rewritten for users, in M5a.
- **ADR-0013's status and Steps table:** `make -k test` runs the three
  checks, and `pages.yml` reuses CI's container on tags and by hand.
- **ADR-0010's and ADR-0014's status:** amended by D7. ADR-0014 holds the
  serializer's rules, and the project plan's line on void elements
  follows.
- **AGENTS.md:** §5's writing rules, under `/docs`.
- **README.org,** in M5b: a Documentation section linking `docs/`, and the
  site once it is live.
- **progress.md:** M5's checklist, and each slice's close-out.

## 12. Out of scope

- The release: the CHANGELOG entry, the version, the tag, making the
  repository public, and publishing to ocicl.
- The release's manual macOS run (ADR-0001).
- Syntax highlighting, search, and versioned docs.
- Checking external links.
- Converting README.org to Markdown.
