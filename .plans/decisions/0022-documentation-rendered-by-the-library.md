# ADR-0022: Documentation rendered by the library

- **Status:** Accepted 2026-10-04; amended 2026-10-05, in M5b, by the
  [M5 spec](../2026-10-04-m5-documentation-design.md) D13: backquoted text
  in an exported docstring shows as code in the reference
- **Date:** 2026-10-04
- **Scope:** the user documentation: `docs/` and its writing rules; the
  site, its generator in `site/` and its deployment; the generated
  reference, and the exported docstrings it shows; `make check-site`,
  `make check-reference` and `make check-docs`; the serializer's void
  elements
- **Spec:** [M5 design](../2026-10-04-m5-documentation-design.md) §1, §2
  (D1 to D9, and D13), §3 (findings 1 to 5, 10 to 14, 16, 18, 19, 23 and 25 to
  32), §4 to §8, §11
- **Amends:** ADR-0010 and ADR-0014 (the serializer writes HTML's 13 void
  elements as void, and `:document-wrapper` refuses all 13), ADR-0013
  (`make -k test` runs the three checks, and `pages.yml` reuses CI's
  container and toolchain, on tags and by hand only)
- **Related:** ADR-0012 (the defaults the site renders with), ADR-0017 (the
  public API, the only one the site calls), ADR-0019 (the footnote guard,
  whose pattern no page can quote whole)
- **Prior art:** chez-cmark-gfm at `e0118a3`: its site design
  (`.plans/2026-08-22-docs-site-design.md`), its generator (`site/`) and
  its `pages.yml`. D4 reuses its theme

## Context

M5 documents the library for its first release. A user should be able to
install and use it from `docs/` alone, and GitHub Pages should serve
`docs/` as a site from that release on (M5 design §1). Four facts shaped
the design:

- **The repository is private, and a Pages site is public.** The
  organization's GitHub Team plan serves Pages from a private repository,
  but the site itself is public. Deploying before the code is public would
  publish the docs first (M5 finding 1).
- **The serializer knew only cmark's four void elements,** `br`, `hr`,
  `img` and `input`. A page's `<meta>` and `<link>` printed with end tags.
  Browsers ignore those, but the HTML isn't valid (M5 findings 2 and 12).
- **The serializer escapes text inside `<script>` and `<style>`,** as it
  does everywhere, and a browser decodes no entities there. Inline
  JavaScript holding `&`, `<` or `>` would break (M5 finding 3).
- **GitHub gives each heading an id by github-slugger's rule:** lowercase
  the text; keep only letters, digits, `-`, `_` and spaces; turn each
  space into `-`. A repeated id gets `-1`, then `-2`, counted per id (M5
  findings 4 and 11). `docs/` is read on GitHub as well as on the site,
  so a link to a heading must name the id GitHub gives it.

## Decision

The library renders its own documentation. A generator in `site/` takes
each page of `docs/` through the public API alone: `parse`,
`transform-ast` to rewrite its links, `ast->html-tree` with the defaults,
which omit raw HTML and apply the safe link policy, and
`html-tree->string` (M5 design §6.2). A probe took a real page through
that path (M5 finding 12). Headings get the ids GitHub gives them, so a
link written as `page.md#id` names the same heading on GitHub and,
rewritten to `page.html#id`, on the site. The pure core, `render-site`,
reads and writes no file; `make site`, the shell, writes `build/site/`.

- **D1. The site goes live at the first release.** It is built and
  checked from now on, but deployed only from a release tag, a `v*` tag,
  the first one when the repository goes public (M5 finding 1). A manual
  run on a `v*` tag deploys that tag's site again. Any other manual run,
  such as one on a branch, builds, checks and uploads the site, but
  deploys nothing: before the first release, it is the workflow's dry run.
- **D2. Ten short pages, plus a home page:** installing, usage, options,
  the AST, the HTML tree, safety, errors, ECL, support, and the generated
  reference (M5 design §5). M5b writes the pages. M5a generates the
  reference, and writes a placeholder home page, so the site and its
  checks have one.
- **D3. The reference is generated from the docstrings.** `make reference`
  writes `docs/reference.md`. `make check-reference` fails when the file
  is out of date, when an export has no docstring, or when an entry
  doesn't render as its own text, saying what to quote (the render check,
  below). Rendering parses each entry, so the check needs cmark-gfm, as
  the other two do. `cl-commonmark-gfm` exports all 49 public symbols, its
  own 8 and the 41 it re-exports, each with a docstring. So the reference
  documents that one package, with a section per home package (M5 finding
  5).
- **D4. The site reuses chez-cmark-gfm's theme:** its `style.css`, its
  layout, and its light and dark modes. The template keeps chez's class
  names, so `style.css` applies unchanged. chez inlines its theme script;
  here it is a file, `theme.js`, which may hold any character (M5 finding
  3).
- **D5. Every Lisp example in `docs/` runs,** in `make check-docs`, and
  nothing it claims goes unchecked:
  - a form's `;; =>` gives its first value, and `;; signals` the type of
    error it signals, or a supertype. A malformed expectation fails the
    check, and so does any other spelling of a marker, such as `;; ==>` or
    `;; Signals`, or one hidden after a block comment (M5 findings 25, 26
    and 31);
  - a block fenced `lisp no-run` is skipped. Any other fence that names
    Lisp, such as `cl`, fails the check, so a typo can't turn an example
    off, and so does an example read with `#+` or `#-` (M5 finding 27);
  - each page runs in a fresh package, under fresh bindings of the
    library's exported variables, so a `setf` stays on its page (M5
    finding 28);
  - any warning but a style-warning fails the check, and so does an
    example that ends the process: the check passes only with exit status
    0 and its summary line (M5 finding 30);
  - an example shows what a reader returns, never a whole node, which
    prints with every slot and its children's (M5 finding 13).
- **D6. The three checks run in `make test`,** on every pull request, on
  SBCL.
- **D7. `html-tree->string` learns HTML's void elements,** so the site can
  write a whole page as one tree. All 13, `area`, `base`, `br`, `col`,
  `embed`, `hr`, `img`, `input`, `link`, `meta`, `source`, `track` and
  `wbr`, print as `<tag ... />`, and signal `invalid-html-tree` when given
  children. Trees from `ast->html-tree` don't change, since cmark writes
  only `br`, `hr`, `img` and `input`. `:document-wrapper` takes only a
  non-void element, so the nine new names are refused there too, with
  `invalid-render-option`. Before, they were accepted, and the wrapper
  printed with an end tag. This amends ADR-0010 and ADR-0014.
- **D8. The home page is `docs/README.md`:** GitHub shows it when `docs/`
  is opened, and the site renders it as `index.html`.
- **D9. `pages.yml` reuses CI's container and toolchain script,**
  `debian:trixie` and `ci/install-toolchain.sh`, so the site is built with
  the SBCL and cmark-gfm that CI tests (M5 finding 10). It runs `make
  check-site`, `make check-reference` and `make check-docs` before `make
  site`, since a tag can name a commit that CI never checked. Only its
  deploy job has `pages: write` and `id-token: write`, and its build job
  has CI's 30-minute timeout.

### The maintainer's decisions on the first review

- **The reference escapes only what Markdown and GFM give meaning to,**
  by position: ``\ ` * _ [ ] < & | ~`` anywhere, and `# > + - =` or a
  leading number's `.` or `)` at the start of a paragraph or list item. A
  render check rests on it: `make check-reference`, and a test in `make
  check-site`, render every entry of the real reference, and fail when one
  comes out as anything but its own text in `p`, `ul`, `li` and `code`
  elements, saying what to quote (M5 finding 23). What users type
  shows as code, its case kept: a double-quoted string, an upper-case
  name holding an underscore, such as an environment variable, and an
  absolute path. Since M5b, so does what a docstring puts in backquotes,
  such as a file name, as written, the backquotes dropped (D13).
- **Every exported docstring the reviews found reading wrongly was
  rewritten for users,** in M5a (M5 design §11).
- **A link to a repository file must name one that GitHub's `/blob/` URL
  serves.** The core lists each such path, and the shell asks git, through
  `git ls-files --cached --others --exclude-standard`. So an ignored file,
  such as one under `build/`, and a path inside the cmark-gfm submodule
  are refused, as GitHub serves neither. `make check-site` and `make site`
  therefore need a git checkout, which CI, `pages.yml` and the containers
  all have.

### Rejected

- **Deploying from `main` now.** The site would be public while the code
  is private, so the docs would go out first (M5 finding 1).
- **A hand-written reference.** It would restate 49 docstrings, and could
  drift from them. The generated one is checked against them.
- **Escaping every other ASCII punctuation character,** the reference's
  first rule. The raw Markdown read noisily, `a string\, to HTML\.`, and
  GitHub ignores such escapes in its own extensions anyway: `\:smile\:`
  still renders an emoji (M5 finding 23).
- **Examples in separate files.** Markdown can't include a file, so each
  page would show a copy, which could drift from the file that runs.
  `make check-docs` runs the blocks the reader sees.
- **Checks only at release.** A stale reference or a broken example would
  then show up far from the change that caused it, and the checks are
  cheap: about a second per SBCL process (M5 finding 14).

## Consequences

- **`make test` runs the three checks,** so every pull request does. Each
  runs SBCL; M5 finding 14 estimated about a second per process. Measured
  in the container, before M5a's fix rounds, they took `make test` from
  127 s to 128 s warm, and from 157 s to 159 s cold. After those rounds,
  the three take 1.5 s together, warm, in one container call. `pages.yml`
  runs only on tags and by hand, so pull requests pay for nothing more.
- **`docs/reference.md` is regenerated whenever an export or its
  docstring changes,** with `make reference`. Until it is, `make
  check-reference` fails.
- **Every Lisp example in `docs/` must run,** or be fenced `lisp no-run`.
  A change to a result a page shows fails `make check-docs` until the page
  is updated.
- **`make check-site` holds `docs/` to the site's rules:**
  - `*pages*` names every page once, and no `.md` file sits in a
    directory below `docs/`, where the site would never render it;
  - each page starts with exactly one `#` heading, and holds no raw HTML;
  - every heading's id is its own, neither empty nor shared on its page
    (M5 finding 19);
  - no heading holds a non-ASCII character, an image or a footnote
    reference, where the site's ids and GitHub's could differ (M5 finding
    29);
  - every link inside the site resolves, and none climbs out of the
    repository. No link names a file in `docs/` that isn't a page, since
    the site copies no files, nor a repository file that GitHub doesn't
    serve, such as a missing or ignored one;
  - no image has a relative path, whose `/blob/` URL is GitHub's page for
    the file, not the image (M5 finding 18).
- **AGENTS.md holds the writing rules for `docs/`** (M5 design §5).
- **The footnote guard's pattern,** a `[` before an entity for `^`, makes
  `parse` refuse its whole input, code spans included, so the site reports
  it as that page's or entry's problem. A page writes the pattern's `&` as
  `&amp;` outside code, and splits it into two code spans with a word
  between; a Lisp example builds the string from two pieces, as
  `(concatenate 'string "[" "&#94;")`. A docstring writes it plainly,
  outside double quotes and backquotes, which the generator escapes, or as
  two quoted strings for code (M5 finding 32, D13).
- **Two changes reach users of the HTML tree:** a hand-built tree holding
  one of the nine new void names prints it void, or signals if it has
  children; and `:document-wrapper` refuses those names (M5 design §4).
- **The generator never ships with the library.** Its system,
  `site/cl-commonmark-gfm-site.asd`, stays out of `cl-commonmark-gfm.asd`.
- **The first release brings two manual steps, before its tag is
  pushed** (M5 finding 16):
  - Settings → Pages → Source: GitHub Actions;
  - in the `github-pages` environment, a deployment rule that allows `v*`
    tags. chez-cmark-gfm's environment allows `main` alone, so it would
    refuse a tag's deploy job.
