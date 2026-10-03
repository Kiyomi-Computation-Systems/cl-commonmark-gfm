# ADR-0014: The HTML tree carries cmark's newlines; footnotes follow definition order

- **Status:** Accepted; amended by ADR-0015 (2026-09-30): places are keyed
  by owner and ordinal, not by path; and by ADR-0018 (2026-09-30): its
  hand-offs to M2 (the copier's labels, the two divergences and the fixture
  ASTs) are settled in M2b; amended 2026-10-02 by M3 finding 9
  ([M3 spec](../2026-10-02-m3-extensions-versions-properties-design.md)
  §3): three more divergence shapes, with the same two causes, and repeat
  references can differ with no body reference
- **Date:** 2026-09-27
- **Scope:** HTML tree layout and footnotes, serializer rules, M1's tree
  tests, `ast->html-tree`'s options
- **Spec:** [M1 pure core design](../2026-09-27-m1-pure-core-design.md) §2,
  §5, §6, §7.3, §8
- **Amends:** ADR-0005 (footnote numbering), ADR-0010 (its newline tables
  move into the converter), ADR-0011 (footnote numbering, and how M1
  tests), ADR-0012 (the `:br` value and the `:document-wrapper` rule)
- **Related:** ADR-0002 (the pinned CLI)

## Context

ADR-0010 gave the serializer static tables of void elements and of where
cmark puts newlines. ADR-0011 numbered footnotes by first reference, and had
M1 compare hand-built ASTs with expected trees written out by hand.
Checking facts against the pin (spec §2) found:

- **The same tree shape gets different layouts.**
  - `- <div>` renders as `<li>\n<!-- raw HTML omitted -->\n</li>`;
  - `- a <b>` renders as `<li>a <!-- raw HTML omitted --></li>`;
  - an empty footnote's `<li>` gets newlines that a list `<li>` holding a
    link does not.

  No serializer table can reproduce both.
- **cmark's parser rewrites footnotes before rendering.**
  - It numbers definitions by first reference in **source** order, then
    moves them to the end in that order. A parsed tree has lost the source
    order: for `x[^a]`, `[^a]: see [^c]`, `y[^b]`, cmark numbers `c` as 2.
  - It drops unreferenced definitions. When two definitions share a label,
    it keeps the first. Labels match case-insensitively.
  - Ids use the kept definition's label as written.
  - A reference with no definition becomes the text `[^label]`.
- **`'` is escaped by attribute.** In `href`, `src` and footnote `id`
  values, cmark writes it as `&#x27;` (`houdini_escape_href`). In text,
  `title` and `alt` it stays raw (`houdini_escape_html0`, not secure).
- **Some attributes are bare.** cmark writes `data-footnotes`,
  `data-footnote-ref` and `data-footnote-backref` with no value, but the
  checkbox's `checked=""` and `disabled=""` with one.

Two more gaps:
- Expected trees written by hand can be wrong in the same way as the code
  (ADR-0011). M1 has no parser, but the pinned CLI can render each
  fixture's Markdown.
- ADR-0012 promises that an unknown option key signals
  `invalid-render-option`. `&key` can only do that with
  `&allow-other-keys`, which AGENTS.md reserves for wrappers that forward a
  `&rest` plist.

## Decision

### The tree carries cmark's newlines (D4)

- `ast->html-tree` emits a `"\n"` string wherever cmark's renderer writes a
  newline. Spec §5.3 says where, node by node.
- Where cmark calls `cr` (`cmark_html_render_cr`), the converter emits
  `"\n"` unless the output so far is empty or already ends in a newline.
  It can tell, because it knows everything it has emitted.
- Children are normalized: adjacent strings are merged and empty strings
  dropped.
- `html-tree->string` adds no layout. Its output is the plain
  concatenation of the tree, so it is exact for any tree.

The two list items above, as trees:

```lisp
(:li nil "\n" (:*comment* nil " raw HTML omitted ") "\n")   ; from "- <div>"
(:li nil "a " (:*comment* nil " raw HTML omitted "))        ; from "- a <b>"
```

A tight task item is
`(:li nil (:input ((:type "checkbox") (:disabled ""))) " open task")`. A
`:linebreak`, and a `:softbreak` under `:softbreak :br`, is
`(:br nil) "\n"`.

### Footnotes follow definition order (D2, D3)

A pure pre-pass mirrors cmark's parser (spec §5.4):

1. **Definitions.** Collect every place in the tree that holds a
   `:footnote-definition`, depth-first. For each label, the first one the
   walk *leaves* is kept, as cmark's parser registers definitions on exit;
   the others are dropped. That differs from tree order only for a nested
   definition, which only a hand-built tree can have.
2. **References.** Collect every place that holds a `:footnote-reference`,
   depth-first, including places inside definitions and images. One node
   object at two places is two references. A reference **resolves** when a
   kept definition has its label.
3. **Survival.** A kept definition survives when at least one reference
   resolves to it. Survivors are numbered 1, 2, … in the order they appear
   in the tree.
4. **Ids.** The k-th resolving reference to a definition gets the id
   `fnref-L` when k = 1, and `fnref-L-k` otherwise. L is the label,
   percent-encoded (spec §5.5).
5. **Placement.** Definitions leave their places in the tree. Survivors
   render, in number order, in one section after everything else. There's
   no `cr` before the section, as in cmark.
6. **Dangling references.** An unresolved reference renders as the text
   `[^label]`, in an image's `alt` too.

The pre-pass keys its bookkeeping by each place's path from the root, not
by node identity: an immutable node can sit at more than one place.

A parsed tree already holds cmark's order, so numbering by definition order
is exact on it. In the example under Context, the parsed tree holds the
definitions as `a`, `c`, `b`, so `c` gets 2.

For a definition labelled `note`, numbered 1, with one reference:

```lisp
;; x[^note]
(:p nil "x" (:sup ((:class "footnote-ref"))
                  (:a ((:href "#fn-note") (:id "fnref-note") (:data-footnote-ref ""))
                      "1")))
"\n"
;; [^note]: Text.
(:section ((:class "footnotes") (:data-footnotes "")) "\n"
          (:ol nil "\n"
               (:li ((:id "fn-note")) "\n"
                    (:p nil "Text. "
                        (:a ((:href "#fnref-note") (:class "footnote-backref")
                             (:data-footnote-backref "") (:data-footnote-backref-idx "1")
                             (:aria-label "Back to reference 1"))
                            "↩"))
                    "\n")
               "\n")
          "\n")
"\n"
```

Ids and `href`s carry the label; the link text, the backref index and the
`aria-label` carry the number. ADR-0011's examples use a footnote labelled
`1`, which hides that distinction.

**Backrefs.** A definition numbered N with R references gets R anchors,
separated by `" "`:
- the first is the one above: it links to `#fnref-L`, and has N as its
  index and in its `aria-label`;
- the k-th, for k ≥ 2, links to `#fnref-L-k`, has `N-k` as its index and
  in its `aria-label`, and has the children
  `"↩" (:sup ((:class "footnote-ref")) "k")`.

If the definition's last child, not counting nested definitions, is a
`:paragraph`, the anchors go at its end, after a `" "`. Otherwise they
follow the definition's children, then a `"\n"`.

**Labels match with `string=`.** cmark matches case-insensitively, but M2's
copier gives each reference its definition's label as written, so a parsed
AST always matches. A hand-built reference whose case differs from its
definition renders as `[^label]`.

**Known divergences.** Both come from information a parsed tree no longer
has. M2's oracle showed that the corpus hits neither (ADR-0018).
- **Repeat references are counted in tree order.** cmark counts them in
  source order. The two differ when a repeat reference inside a
  definition came before a body reference in the source. They can also
  differ with no body reference: repeat references in two definitions can
  be swapped (M3 finding 9, below). Ordering by source position would fix
  that, if needed.
- **A definition referenced only from a dropped (unreferenced or
  duplicate) definition** survives in cmark, with a dangling backref. The
  parsed tree has no reference left to it, so the pre-pass drops it.

**Three more shapes** have the same two causes (M3 finding 9), each
confirmed with the pinned CLI:
- `"[^a]: [^b]\n\n[^b]: B\n\nx[^c]\n\n[^c]: C\n"`: the dangling `b` takes
  number 1 in cmark, so `c` becomes 2 there but 1 in the tree;
- `"x[^b] y[^a]\n\n[^a]: [^c]\n\n[^b]: [^c]\n\n[^c]: C\n"`: repeat
  references in two definitions, with no body reference, are swapped;
- `"[^a]: [^b]\n\nx[^b]\n\n[^b]: text\n"`: a footnote referenced from the
  body and from a dropped definition gets two backrefs in cmark, one of
  them dangling.

Property 1's excuses don't cover these, by design, so it reports each as a
failure (ADR-0020). No generated input reached them. Nor do they cover the
repeat divergence with a reference in an image's alt text, such as
`"[^b]:[^b]\n\n[^b] ![x[^b]](u)\n"`. cmark writes no anchor in alt
text, so the tree's ids for `b` skip a number (M3 finding 9).

### The serializer's rules (spec §6)

ADR-0010's rules stand, except its newline tables. These are added:

- **`'` in `href`, `src` and `id`.** `&`, `<`, `>` and `"` are escaped in
  text and in attribute values. In `href`, `src` and `id` values, `'` also
  becomes `&#x27;`.
- **Bare attributes.** `data-footnotes`, `data-footnote-ref` and
  `data-footnote-backref` print without a value when it is `""`. Every
  other attribute prints as `name="value"`, so the checkbox keeps
  `checked=""` and `disabled=""`.
- **Void elements.** `br`, `hr`, `img` and `input` print as `<br />`,
  `<img src="…" alt="…" />` and so on. A void element with children
  signals `invalid-html-tree`.
- **Comments.** `(:*comment* nil "text")` prints as `<!--text-->`, and
  the text is escaped like any other text. Inside a `textarea`, `title`,
  `script` or `style`, `<!--` starts no comment, so unescaped text such as
  `</textarea><script>` would close the parent. cmark's one comment,
  `" raw HTML omitted "`, has nothing to escape. `:*comment*` is the one
  tag outside the name rule. A comment that isn't exactly that shape, or
  whose text contains `--`, starts with `>` or `->`, or ends with `-`,
  signals `invalid-html-tree`.
- **Names** print lowercase, and must match `[a-z][a-z0-9-]*` once
  lowercased. They are classified by that lowercased string too, so
  `:|href|` is `:href` and `:|br|` is `:br` for the void, bare, URL and
  repeat rules.
- **A tag alone,** `(:p)`, reads as `(:p nil)`.

### M1's fixtures are checked against the pinned CLI (D1)

For M1, this replaces ADR-0011's "hand-built ASTs with the expected trees
written out" (spec §7.3):

- `tests/fixtures/html/cases` lists one case per line:
  `name file.md cmark-flags…`.
- `tests/fixtures/html/name.html` is the pinned CLI's output for that file
  under those flags, committed.
- `make check-fixtures` re-runs the CLI for every case and diffs against
  the committed files. `make fixtures-html` writes only the missing ones,
  and never overwrites one.
- In Lisp, each case has a hand-built AST and its `ast->html-tree`
  options. `(html-tree->string (ast->html-tree ast …))` must equal the
  `.html` file, and the Lisp cases and the manifest must name exactly the
  same set, so no case can be skipped quietly.

The corpus oracle still arrives with the parser, in M2 and M3 (ADR-0011).
M2 also shows that each fixture's hand-built AST equals the copier's AST
for the same Markdown, ignoring source positions and how text is split into
nodes.

### Options arrive as `&rest` (D11)

The signature is `(ast->html-tree node &rest options)`. The options are
validated by hand, before any node is converted. Each of these signals
`invalid-render-option`:
- an odd-length plist;
- an unknown key;
- a value outside ADR-0012's lists;
- a `:document-wrapper` that isn't a keyword naming a non-void element,
  under the serializer's name rule.

A repeated key: the leftmost value wins, as with `&key`, but every value
must be valid, so `:softbreak :space :softbreak :bogus` signals
`invalid-render-option`.

### Rejected

- **Newline tables in the serializer** (ADR-0010): no table gives both
  layouts above.
- **Numbering by first reference** (ADR-0011): a parsed tree has lost the
  source order it depends on.
- **Case-insensitive label matching:** a parsed AST doesn't need it, and
  Unicode case folding of labels is out of scope (spec §9).
- **Expected trees written by hand**, for M1 (ADR-0011): they can be wrong
  in the same way as the code.
- **`&key` with `&allow-other-keys`:** AGENTS.md reserves
  `&allow-other-keys` for wrappers that forward a `&rest` plist.

## Consequences

- `html-tree->string` adds no layout. A converted tree prints as cmark's
  HTML; a hand-built one gets no newline it doesn't carry.
- Code that walks a converted tree meets `"\n"` strings beside elements.
- A misplaced `"\n"` is a byte difference against the pinned CLI's HTML.
- Footnote numbers are exact on parsed ASTs. On a hand-built AST,
  definitions are numbered in the order they appear.
- M2's copier must give each reference its definition's label as written.
- The divergences stay open, and documented: the corpus hits none of them
  (ADR-0018).
- M1 checks conversion and serialization against cmark before any native
  code exists. Whether each hand-built AST is what the parser builds waits
  for M2.
- An unknown option key signals `invalid-render-option`, as ADR-0012
  promises.
- ADR-0005, ADR-0010, ADR-0011 and ADR-0012 are amended, not replaced:
  their status lines say so. The bodies of ADR-0010 and ADR-0011 are
  unchanged; ADR-0005's footnote bullet and two cells of ADR-0012's table
  cite ADR-0014. The plan's HTML tree contract and tests follow this ADR.
