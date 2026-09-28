# M1 pure core: AST, HTML tree, serializer — design

- **Date:** 2026-09-27
- **Status:** Approved 2026-09-27; amended 2026-09-27 (final review)
- **Milestone:** M1 (pure core)
- **Inputs:** [project plan](cl-commonmark-gfm.org), ADR-0005, ADR-0007,
  ADR-0010, ADR-0011, ADR-0012, and cmark-gfm 0.29.0.gfm.13's `src/html.c`,
  `src/blocks.c`, `src/houdini_*.c` and `extensions/{table,tasklist}.c`
  (`vendor/cmark-gfm`)

## 1. Goal

Build the part of the library that needs no C:

1. **The AST:** a validated node type, queries, structural equality and pure
   transforms.
2. **`ast->html-tree`:** the AST as an LHTML-shaped tree, under the
   ADR-0012 policies.
3. **`html-tree->string`:** the public serializer.

**Success:** `make test` passes on SBCL, CCL and ECL, in the Guix container
and in a local `debian:trixie` run of the CI steps. Every check has been seen
to fail. The oracle fixtures cover every node kind and every row of the
mapping table (§5.3), and match the pinned CLI byte for byte.

## 2. Decisions made while brainstorming

| # | Question | Decision |
|---|----------|----------|
| D1 | Where M1's expected output comes from | **Hand-built ASTs checked against cmark's HTML.** The pinned CLI renders each fixture's Markdown; the output is committed and re-checked (§7.3). |
| D2 | Footnotes in an AST that wasn't just parsed | **Mirror cmark's parser**: move definitions to the end, drop unreferenced and duplicate ones, render a dangling reference as text (§5.4). |
| D3 | Numbering footnotes | **By definition order,** not first reference. It is exact on parsed ASTs, which already hold cmark's order. Amends ADR-0011. |
| D4 | Where cmark's newlines live | **In the tree,** as `"\n"` strings. The serializer adds no layout. Amends ADR-0010. |
| D5 | Constructors | **One schema-checked `make-node`, plus `copy-node`,** driven by one per-kind table. |
| D6 | Which Lisps run the pure suite | **SBCL, CCL and ECL,** from M1. |
| D7 | Package names | **Dotted:** `cl-commonmark-gfm.ast`, `cl-commonmark-gfm.html-tree`. ASDF system names keep their slashes. |
| D8 | Where conditions live | **`cl-commonmark-gfm/conditions`**, a small pure system that M2 extends. |
| D9 | What `check-purity` checks | **No `CFFI` package exists** after loading and running the pure suite. |
| D10 | `:extension` nodes in `ast->html-tree` | **Signal `unsupported-extension-node`.** Under the pin they cannot occur (ADR-0008). |
| D11 | How `ast->html-tree` takes options | **`&rest options`, validated by hand.** An unknown key signals `invalid-render-option`, as ADR-0012 promises, without the `&allow-other-keys` AGENTS.md reserves for wrappers. |
| D12 | Optimization declarations | **None in library source.** The "Optimization Declarations" section is removed from `AGENTS.md`. |

Found while checking facts against the pin:

1. **The same tree shape gets different layouts.** `- <div>` renders as
   `<li>\n<!-- raw HTML omitted -->\n</li>`, while `- a <b>` renders as
   `<li>a <!-- raw HTML omitted --></li>`. An empty footnote's `<li>` gets
   newlines that a list `<li>` holding a link does not. No serializer table
   can reproduce both. Hence D4.
2. **`'` is escaped by attribute.** In `href`, `src` and footnote `id`
   values, cmark writes `'` as `&#x27;` (`houdini_escape_href`). In text,
   `title` and `alt` it stays raw (`houdini_escape_html0`, not secure).
3. **Some attributes are bare.** cmark writes `data-footnotes`,
   `data-footnote-ref` and `data-footnote-backref` with no value, but the
   checkbox's `checked=""` and `disabled=""` with one.
4. **cmark's parser rewrites footnotes before rendering.**
   - It numbers definitions by first reference in **source** order. It
     then moves them to the end in that order, so a parsed tree has lost
     the source order: for `x[^a]`, `[^a]: see [^c]`, `y[^b]`, cmark
     numbers `c` as 2.
   - It drops unreferenced definitions. When two definitions share a
     label, it keeps the first and drops the rest. Labels match
     case-insensitively.
   - Ids use the kept definition's label as written.
   - A reference with no definition becomes the text `[^label]`.
5. **A `strong` directly inside a `strong` is not wrapped again**
   (`****s****` renders as `<strong>s</strong>`).
6. **An image's `alt` is plain text** made from every literal under it.
   That includes raw HTML, escaped, even when raw HTML is otherwise
   omitted. Breaks inside it become spaces.
7. **A code block's language word ends at a space, tab, LF or CR**
   (`cmark_isspace`). VT and FF don't end it.
8. **`houdini_escape_href` passes some characters through.** ASCII
   alphanumerics and ``-_.+!*(),%#@?=;:/$~`` pass through, and so do `&`
   and `'`, which the HTML layer then entity-escapes. Every other byte of
   the UTF-8 encoding becomes `%XX`. Since `%` passes, existing escapes
   are never re-encoded.
9. **A loaded file's `declaim` leaks into the image on two of our Lisps.**
   A probe loaded a file that declaims `(optimize (safety 0) (speed 3)
   (debug 0))`. On CCL 1.13 and ECL 24.5.10 the image's global policy
   changed after `load`. SBCL 2.6.4, the Guix container's version (CI's is
   Debian's 2.5.2), rebinds the policy around `load`, so it didn't. Hence
   D12.

## 3. Systems, packages and conditions

All four systems are defined in one `cl-commonmark-gfm.asd`, next to an
empty primary `cl-commonmark-gfm` system. The empty system is needed because
ASDF won't load a slash-named system unless its primary system is defined
(found in Task 1). M2 gives it the native layer.

| System | Package | Depends on |
|--------|---------|------------|
| `cl-commonmark-gfm/conditions` | `cl-commonmark-gfm.conditions` | — |
| `cl-commonmark-gfm/ast` | `cl-commonmark-gfm.ast` | conditions |
| `cl-commonmark-gfm/html-tree` | `cl-commonmark-gfm.html-tree` | ast |
| `cl-commonmark-gfm/tests` | `cl-commonmark-gfm.tests` | the above, Parachute |

The pure systems depend on nothing outside the project. There's no
alexandria, and no UTF-8 library: `ast->html-tree` carries its own small
encoder.

**Conditions.** `commonmark-gfm-error` (a subtype of `error`) is the base.
M1 adds:

| Condition | Signalled by |
|-----------|--------------|
| `invalid-ast-node` | `make-node`, `copy-node`, `node-attribute`, `transform-ast` |
| `invalid-render-option` | `ast->html-tree` |
| `invalid-html-tree` | `html-tree->string` |
| `unsupported-extension-node` | `ast->html-tree` |

Each carries the operation, the offending datum and a reason, and its report
names all three. The report prints the datum with `*print-circle*` on and
its length and depth bounded, so a circular or deeply nested datum can't
hang it. `invalid-ast-node` is new, and joins the plan's conditions table.

## 4. The AST

### 4.1 Node

A `defstruct` with read-only slots `kind`, `attributes`, `children` and
`sourcepos`. Its constructor is private: every node is built through the
schema (§4.2), and the public package exports no mutators.

### 4.2 Schema

One table, one row per vocabulary kind (ADR-0005), drives all validation:

| Kind | Attributes: type, default | Leaf |
|------|---------------------------|------|
| `:document` | `:profile` `(member nil :gfm :commonmark)`, `nil`; `:extensions` list of keywords, `nil`; `:options` list of keywords, `nil` | |
| `:block-quote`, `:item`, `:paragraph`, `:table`, `:table-header`, `:table-row`, `:emph`, `:strong`, `:strikethrough` | — | |
| `:list` | `:type` `(member :bullet :ordered)`, `:bullet`; `:start` `(or null (integer 0))`, `nil`; `:delimiter` `(member nil :period :paren)`, `nil`; `:tight` boolean, `nil` | |
| `:task-item` | `:checked` boolean, `nil` | |
| `:code-block` | `:info` string, `""`; `:literal` string, `""` | yes |
| `:html-block`, `:html-inline`, `:text`, `:code` | `:literal` string, `""` | yes |
| `:heading` | `:level` `(integer 1 6)`, **required** | |
| `:thematic-break`, `:softbreak`, `:linebreak` | — | yes |
| `:footnote-definition` | `:label` non-empty string, **required** | |
| `:footnote-reference` | `:label` non-empty string, **required** | yes |
| `:table-cell` | `:align` `(member nil :left :center :right)`, `nil` | |
| `:link`, `:image` | `:destination` string, `""`; `:title` string, `""` | |
| `:extension` | `:extension-name` `(or null string)`, `nil`; `:type-name` string, **required** | |

- **One cross-field rule:** an `:ordered` list needs an integer `:start`
  and a non-`nil` `:delimiter`, and a `:bullet` list has neither.
- **Sourcepos** is `nil` or `((line . column) . (line . column))` of
  non-negative integers. Inverted ranges are allowed (ADR-0005).
- **Not checked:** which kinds may nest inside which, and whether a node is
  block or inline. cmark promises neither, and conversion renders whatever
  it is given.

### 4.3 Constructors

```lisp
(make-node kind &key attributes children sourcepos)
(copy-node node &key attributes children sourcepos)
```

- `make-node` checks every rule in §4.2:
  - the kind is in the table;
  - `attributes` is a plist whose keys belong to the kind, with no key
    repeated and values of the right type;
  - required keys are present, and every other key the node lacks is
    filled from its default;
  - `children` is a proper list of nodes, and is empty for a leaf.

  Any failure signals `invalid-ast-node`.
- **Canonical form:** the stored plist holds every key, in schema order, so
  equal nodes have `equal` attributes.
- `copy-node` merges `attributes` over the node's own, and replaces
  `children` and `sourcepos` only when they are supplied (so
  `:sourcepos nil` clears it). The result is checked like a new node.
  There is no way to change a node's kind.

### 4.4 Queries and equality

- `node-p`, `node-kind`, `node-sourcepos`.
- `node-children` returns a fresh list, and `node-attributes` a fresh copy
  of the canonical plist. A node stores a copy of the children it is given,
  so no list the caller holds can change it.
- `(node-attribute node key)` signals `invalid-ast-node` for a key the kind
  doesn't have, rather than returning `nil` for a typo.
- `(node= a b &key (sourcepos t))` compares kind, attributes, children and
  (unless `:sourcepos nil`) source positions. `equalp` can't be used,
  because it compares strings case-insensitively.

### 4.5 Transforms

- `(fold-ast function initial-value node)` visits nodes depth-first, parent
  before children. It calls `(function node accumulator)` and returns the
  final accumulator.
- `(map-ast function node)` returns the list of `(function node)` results,
  in the same order.
- `(transform-ast function node)` works bottom-up. `function` receives each
  node with its children already transformed, and returns one of:
  - a node;
  - a list of nodes, spliced into the parent;
  - `nil`, which deletes the node.

  Anything else, or a root that doesn't come back as exactly one node
  (bare, or alone in a list), signals `invalid-ast-node`. Rebuilt nodes go
  through the schema check.

## 5. `ast->html-tree`

### 5.1 Signature and options

```lisp
(ast->html-tree node &rest options)
;; options: :raw-html :omit|:text  :softbreak :newline|:space|:br
;;          :link-policy :safe|:unsafe  :document-wrapper nil|<element keyword>
```

- **Validation happens first.** Each of these signals
  `invalid-render-option` before any node is converted:
  - an odd-length plist;
  - an unknown key;
  - a value outside the list above;
  - a `:document-wrapper` that isn't a keyword naming a non-void element
    under §6's name rule.

  A repeated key: the leftmost value wins, as with `&key`, but every value
  must be valid, so `:softbreak :space :softbreak :bogus` signals
  `invalid-render-option`.
- **What it returns:** a list of top-level items (elements and strings), or
  `(wrapper nil item …)`.
- **A root that isn't a `:document`** is converted as if it were a
  document's only child.
- **No re-validation of the AST.** `make-node` already did that. A node
  outside its usual place converts mechanically, as cmark's renderer would
  convert it.

### 5.2 Layout: cmark's newlines are in the tree

The converter emits a `"\n"` string wherever cmark's renderer writes a
newline. `cr` below is cmark's `cmark_html_render_cr`: emit `"\n"` unless
the output so far is empty or already ends in a newline. The converter can
evaluate it, because it knows everything it has emitted.

Children are normalized: adjacent strings are merged and empty strings
dropped. So a tight task item is
`(:li nil (:input ((:type "checkbox") (:disabled ""))) " open task")`.

### 5.3 Mapping

| AST | Tree | Newlines |
|-----|------|----------|
| `:document` | its children, then the footnote section (§5.4) | — |
| `:block-quote` | `(:blockquote nil "\n" …)` | `cr` before; `"\n"` after the start tag; `cr` before the end tag; `"\n"` after it |
| `:list` | `(:ul nil …)`; `(:ol nil …)`, or `(:ol ((:start "N")) …)` when `:start` isn't 1 | `cr` before; `"\n"` after the start tag and after the end tag |
| `:item` | `(:li nil …)` | `cr` before; `"\n"` after the end tag |
| `:task-item` | `(:li nil (:input ((:type "checkbox") (:checked "") (:disabled ""))) " " …)`; no `:checked` pair when unticked | as `:item` |
| `:paragraph` | `(:p nil …)`. In a tight list (its parent's parent is a `:list` with `:tight t`) its children stand in its place | `cr` before; `"\n"` after; none when unwrapped |
| `:heading` | `(:h1 nil …)` … `(:h6 nil …)` | `cr` before; `"\n"` after |
| `:code-block` | `(:pre nil (:code nil "literal"))`; with a non-empty `:info`, `(:code ((:class "language-W")) …)`, where W is `:info` up to its first space, tab, LF or CR | `cr` before; `"\n"` after |
| `:html-block` | `:omit`: `(:*comment* nil " raw HTML omitted ")`; `:text`: the literal | `cr` before and after |
| `:thematic-break` | `(:hr nil)` | `cr` before; `"\n"` after |
| `:table` | `(:table nil …)`. The `:table-header` row goes in `(:thead nil …)`; the first other row opens one `(:tbody nil …)` that holds the rest, and there's no `tbody` without one | `cr` before every table start and end tag except `</th>` and `</td>`, and after `</table>` |
| `:table-header`, `:table-row` | `(:tr nil …)` | as `:table` |
| `:table-cell` | `(:th …)` in the header row, `(:td …)` elsewhere; `((:align "left"))`, `"center"` or `"right"` from `:align`, none for `nil` | as `:table` |
| `:text` | its literal | — |
| `:softbreak` | `"\n"`, `" "` or `(:br nil) "\n"`, by `:softbreak` | — |
| `:linebreak` | `(:br nil) "\n"` | — |
| `:code` | `(:code nil "literal")` | — |
| `:html-inline` | as `:html-block` | none |
| `:emph`, `:strong`, `:strikethrough` | `(:em nil …)`, `(:strong nil …)`, `(:del nil …)`. A `:strong` directly inside a `:strong` contributes only its children | — |
| `:link` | `(:a ((:href "URL") (:title "T")) …)`; no `title` pair when `:title` is `""` | — |
| `:image` | `(:img ((:src "URL") (:alt "ALT") (:title "T")))`; `title` as for links. ALT is the plain text of the image's descendants: `:text`, `:code` and `:html-inline` literals (the last even under `:omit`), with `:softbreak` and `:linebreak` as `" "` whatever the policy. A `:footnote-reference` under the image adds nothing to ALT when it resolves (it still counts as a reference) and its `[^label]` text when it dangles, as cmark's parser has already made it text | — |
| `:footnote-reference` | §5.4 | — |
| `:footnote-definition` | §5.4 | — |
| `:extension` | signals `unsupported-extension-node` | — |

### 5.4 Footnotes

A pure pre-pass mirrors cmark's parser (D2, D3):

1. **Definitions.** Collect every place in the tree that holds a
   `:footnote-definition`, depth-first. For each label (compared with
   `string=`), one is kept and the others are dropped. The kept one is the
   first the walk *leaves*, because cmark's parser registers definitions on
   exit and keeps the first registered. Among siblings that is the first in
   tree order; a nested definition beats the one containing it, which only
   a hand-built tree can have.
2. **References.** Collect every place that holds a `:footnote-reference`,
   depth-first, including places inside definitions and images. One node
   object at two places is two references. A reference **resolves** when a
   kept definition has its label.
3. **Survival.** A kept definition survives when at least one reference
   resolves to it. Survivors are numbered 1, 2, … in the order they appear
   in the tree.
4. **Ids.** The k-th resolving reference to a definition gets the id
   `fnref-L` when k = 1, and `fnref-L-k` otherwise. L is the label,
   percent-encoded (§5.5).
5. **Placement.** Definitions leave their places in the tree. Survivors
   render, in number order, in one section after everything else. There's
   no `cr` before the section, as in cmark.
6. **Dangling references.** An unresolved reference renders as the text
   `[^label]`, in an image's `alt` too.

The pre-pass keys its bookkeeping by each place's path from the root, not
by node identity: an immutable node can sit at more than one place.

The tree, for a definition labelled `note` that is numbered 1:

```lisp
;; a reference
(:sup ((:class "footnote-ref"))
      (:a ((:href "#fn-note") (:id "fnref-note") (:data-footnote-ref "")) "1"))
;; the section
(:section ((:class "footnotes") (:data-footnotes "")) "\n"
          (:ol nil "\n"
               (:li ((:id "fn-note")) "\n"
                    (:p nil "Text. " <backrefs>) "\n")
               "\n")
          "\n")
"\n"
```

**Backrefs.** A definition numbered N with R references gets R anchors,
separated by `" "`:
- the first is
  `(:a ((:href "#fnref-L") (:class "footnote-backref") (:data-footnote-backref "") (:data-footnote-backref-idx "N") (:aria-label "Back to reference N")) "↩")`;
- the k-th, for k ≥ 2, uses `#fnref-L-k`, with `N-k` as both the index and
  the label, and has the children `"↩" (:sup ((:class "footnote-ref")) "k")`.

If the definition's last child, not counting nested definitions, is a
`:paragraph`, the anchors go at its end, after a `" "`. Otherwise they
follow the definition's children, then a `"\n"`.

**Known divergences.** Both come from information a parsed tree no longer
has. The M2 oracle will show whether the corpus hits either one.
- **Repeat references are counted in tree order.** cmark counts them in
  source order. The two differ only when a repeat reference inside a
  definition came before a body reference in the source. Ordering by
  source position would fix that, if needed.
- **A definition referenced only from a dropped (unreferenced or
  duplicate) definition** survives in cmark, with a dangling backref. For
  `x[^a]`, `[^a]: first`, `[^a]: second [^c]`, `[^c]: C`, cmark keeps `c`
  as number 2. The parsed tree has no reference left to `c`, so step 3
  drops it.

Label matching is `string=`. cmark matches case-insensitively, but M2's
copier gives each reference its definition's label as written, so a
parsed AST always matches. A hand-built reference whose case differs from
its definition renders as `[^label]`.

### 5.5 URLs

- **Percent-encoding** applies to `:destination` (a link's `href`, an
  image's `src`) and to footnote labels in `href`s and `id`s. Encode the
  string as UTF-8. ASCII alphanumerics and ``-_.+!*(),%#@?=;:/$~&'`` stay
  as they are; every other byte becomes `%XX`, in uppercase hex. The small
  UTF-8 encoder is our own, since the pure systems take no dependencies.
- **`:link-policy :safe`** replaces a destination with `""` when it starts,
  ignoring ASCII case, with `javascript:`, `vbscript:`, `file:` or
  `data:`. The exception is `data:` followed by `image/png`, `image/gif`,
  `image/jpeg` or `image/webp`. This is cmark's `_scan_dangerous_url`,
  which checks prefixes only, and it runs on the destination before
  encoding. `:unsafe` keeps every destination. Footnote links are not
  subject to the policy.
- **`dangerous-url-p` ignores case with `string-equal`**, as AGENTS.md
  asks. On conforming Lisps, CL's one-to-one case pairs fold only ASCII
  letters into ASCII letters, which matches cmark's scanner.

## 6. `html-tree->string`

`(html-tree->string tree)`, where the tree is an element, a string, or a
list of elements and strings. A list whose first item is a keyword is an
element, and a tag alone, `(:p)`, reads as `(:p nil)`. Output is the plain
concatenation: the serializer adds no layout (D4).

- **Escaping:** `&`, `<`, `>` and `"` in text, in comment text and in
  attribute values. In `href`, `src` and `id` values, `'` also becomes
  `&#x27;`.
- **Void elements:** `br`, `hr`, `img` and `input` print as
  `<br />`, `<img src="…" alt="…" />` and so on.
- **Bare attributes:** `data-footnotes`, `data-footnote-ref` and
  `data-footnote-backref` print without a value when it is `""`. Every
  other attribute prints as `name="value"`.
- **Comments:** `(:*comment* nil "text")` prints as `<!--text-->`, and
  the text is escaped like any other text. Inside a `textarea`, `title`,
  `script` or `style`, `<!--` starts no comment, so unescaped text such as
  `</textarea><script>` would close the parent. cmark's one comment,
  `" raw HTML omitted "`, has nothing to escape. `:*comment*` is the one
  tag outside the name rule below.
- **Names** are printed lowercase, and classified by that lowercased
  string: `:|href|` is `:href` and `:|br|` is `:br` for the void, bare,
  URL and repeat rules.

These signal `invalid-html-tree`, naming the offending node:
- a malformed element:
  - not a proper list;
  - a tag that isn't a keyword;
  - `attrs` not `nil` or a proper list of `(name value)` pairs;
  - a repeated attribute name;
  - a child that isn't a string or an element;
- a tag or attribute name that doesn't match `[a-z][a-z0-9-]*` once
  lowercased;
- an attribute value that isn't a string;
- a void element with children;
- a comment that isn't exactly `(:*comment* nil "text")`, or whose text
  contains `--`, starts with `>` or `->`, or ends with `-`.

It does not check URLs (ADR-0010).

## 7. Tests and tooling

### 7.1 Dependencies

- `ocicl.csv` pins Parachute and its dependencies, and nothing else.
- `make deps` runs `ocicl install </dev/null`.
- `CL_SOURCE_REGISTRY` lists the repository root (not recursively, which
  would reach `vendor/` and `.guix-env/`) and `ocicl//`, and inherits no
  other configuration.

### 7.2 Runner and `check-purity`

`tests/run.lisp`:
1. loads `cl-commonmark-gfm/tests` through ASDF;
2. runs Parachute with the quiet reporter;
3. fails if a `CFFI` package exists;
4. exits 0 or 1 through `uiop:quit`.

`make check-purity` runs it on each Lisp in `LISPS` (default
`sbcl ccl ecl`), with stdin from `/dev/null` so a debugger can't wait for
input. Every Lisp runs even if an earlier one failed, and any failure fails
the target. In M1, `make test` is `check-purity` plus `check-fixtures`; the
native suites join it in M2.

### 7.3 Oracle fixtures

- **The manifest** is `tests/fixtures/html/cases`: one case per line,
  `name file.md cmark-flags…`. Blank lines and `#` comments are ignored.
- **The expected HTML** is `tests/fixtures/html/name.html`: the pinned
  CLI's output for that file under those flags, committed.
- **`make check-fixtures`** re-runs the CLI for every case and diffs
  against the committed files, as `check-vocabulary` does.
- **`make fixtures-html`** writes only the `.html` files that are missing,
  and never overwrites one.
- **In Lisp,** each case has a hand-built AST and its `ast->html-tree`
  options. The test asserts that `(html-tree->string (ast->html-tree ast
  …))` equals the `.html` file's contents. It also asserts that the
  manifest and the Lisp cases name exactly the same set, so no case can be
  skipped quietly.

Coverage:
- every vocabulary kind except `:extension`, and every row of §5.3;
- `:softbreak :space` and `:br`, via `--nobreaks` and `--hardbreaks`;
- `:link-policy :unsafe` via `--unsafe`, only on cases without raw HTML
  (ADR-0011);
- dangerous and allowed `data:` URLs, percent-encoding, and `&` and `'`
  inside URLs;
- tight and loose lists, nested lists, and task items in both;
- a table with only a header row;
- footnotes:
  - repeat references;
  - `regression.txt`'s nested footnote;
  - a definition whose last child isn't a paragraph;
  - an empty definition;
  - a label containing `'` and one needing `%XX`;
  - the "numbered 2" case from §2 finding 4.

### 7.4 Direct tests

These cover what cmark has no equivalent for:
- every schema rule in §4.2, `copy-node`, `node-attribute`, `node=`, and
  the three transforms, including splicing, deleting and the root rule;
- `:raw-html :text`, in both block and inline position;
- `:document-wrapper`;
- the footnote pre-pass on hand-built ASTs:
  - definitions out of order;
  - an unreferenced definition;
  - a missing definition;
  - a duplicate label;
  - a case mismatch;
- every `invalid-render-option` case and every `invalid-html-tree` case,
  and `unsupported-extension-node`;
- determinism: converting twice gives `equal` trees, and a tree holds
  nothing but lists, strings and keywords.

### 7.5 Seen to fail

Each check has a mutation that must break it before it counts:
- a flipped byte in a committed `.html` breaks both `check-fixtures` and
  the Lisp oracle test;
- a stray `CFFI` package breaks `check-purity`;
- converter mutations, each of which must break a named test:
  - dropping the `'` escape;
  - emitting `"\n"` where `cr` would not;
  - numbering footnotes by first reference;
  - re-wrapping a nested `strong`;
  - omitting the `data:image/` exception.

### 7.6 Makefile

New targets: `deps`, `test`, `check-purity`, `check-fixtures` and
`fixtures-html`. Each has a `## ` description and goes on the one-line
`.PHONY`, so `check-help` covers it.

### 7.7 CI

`.github/workflows/ci.yml` gains `make deps` and `make -k test` after the
M0 steps. Both run with `if: ${{ !cancelled() }}`, so a failed M0 check
doesn't skip them, and `-k` runs `check-fixtures` even when `check-purity`
fails. The Actions minutes are out until October, so these are proved the
same way as M0, by a local `debian:trixie` run of the workflow's steps,
recorded in `progress.md`.

## 8. Corrections this design makes elsewhere

- **`AGENTS.md`:** the "Optimization Declarations" section is removed (D12;
  already done on this branch).
- **ADR-0014** (new): the tree carries cmark's newlines (D4); footnotes are
  numbered by definition order, with the §5.4 rules; the §6 escaping,
  void-element, bare-attribute, comment and name rules; M1's fixtures are
  checked against the pinned CLI (D1).
  - **ADR-0010** is marked "Amended by ADR-0014": its newline tables move
    into the converter.
  - **ADR-0011** is marked "Amended by ADR-0014": footnote numbering, and
    how M1 tests. Its examples use a footnote labelled `1`, which hides
    that ids carry the label and the link text the number; ADR-0014's
    example uses a distinct label.
  - **ADR-0005** and **ADR-0012** are marked amended by ADR-0014:
    ADR-0005's footnote numbering, and ADR-0012's `:br` value and
    `:document-wrapper` rule.
- **ADR-0013:** its M1 step becomes `make deps` then `make test` (D9). Its
  cache line and step conditions match `ci.yml` (§7.7).
- **ADR-0003:** its registry example becomes non-recursive at the root
  (§7.1).
- **The plan:**
  - AST contract: the §4 API;
  - conditions: `invalid-ast-node`;
  - HTML tree contract: §5 and §6, replacing the static-tables bullet;
  - tests: §7, including the real `check-purity`;
  - M1 wording;
  - decision log entry 20 (ADR-0014).
- **`progress.md`:** M1 marked in progress, then a close-out.

## 9. Out of scope

- **Anything native:** bindings, discovery, the copier, `parse`,
  `markdown->html`, `markdown->html-tree`, and the primary system's
  content (M2).
- **Handed to M2:**
  - show that each fixture's hand-built AST equals the copier's AST for the
    same Markdown, ignoring source positions and how text is split into
    nodes;
  - settle the two footnote divergences (§5.4) against the corpus.
- **Stack depth:** every M1 traversal is recursive. 10,000 nested block
  quotes exhaust the stack on SBCL and CCL (ECL at 50,000), while cmark
  parses 50,000 (its `pathological_tests.py`). M2 decides: iterative
  walks, or a documented depth limit that signals a project condition.
- **Internal accessors** (code review, 2026-09-28): `node-children` copies
  on every call, and every internal traversal uses it, so one conversion
  copies each child list about five times. M2 adds a non-copying accessor
  for read-only walks. `proper-list-p` is duplicated in `schema.lisp` and
  `serialize.lisp`; M2 moves it somewhere both can share.
- **Property-based tests** (M3, ADR-0007).
- **Unicode case folding** of footnote labels.
