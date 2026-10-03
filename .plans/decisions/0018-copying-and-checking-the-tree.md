# ADR-0018: Copying and checking the tree

- **Status:** Accepted; amended 2026-10-01, after M2b's review (spec §6.5,
  finding 19): cmark can return bytes that aren't UTF-8, so its output is
  decoded with U+FFFD for them; and the Rejected text is corrected;
  amended 2026-10-01, after M2b's second review (spec §8.3): ADR-0014's
  two divergences are also pinned directly; amended 2026-10-02 by the
  [M3 spec](../2026-10-02-m3-extensions-versions-properties-design.md) §4
  and M3 findings 3 and 7: the copier already keeps an unknown node as
  `:extension`, and M3 tests that path on nodes built through cmark's
  public API; positions copied as reported can be negative
- **Date:** 2026-09-30
- **Scope:** `copy-native-tree`, with its attributes, positions and text;
  the UTF-8 encoder and decoder; the corpus reader; the four oracles
- **Spec:** [M2 design](../2026-09-30-m2-native-layer-design.md) §2 (D1, D4,
  D15, findings 6 to 9, 11, 13 and 19), §6, §8.2, §8.3
- **Amends:** ADR-0005 (finding 2: a parsed reference's literal is its
  number), ADR-0011 (the whole corpus runs in M2, with two more witnesses),
  ADR-0013 (the full oracle arrives in M2), ADR-0014 (its hand-offs to M2
  are settled in M2b)
- **Related:** ADR-0008 (classification), ADR-0015 (the walks), ADR-0016
  (`*max-nodes*`), ADR-0017 (`:sourcepos` by entry point)
- **Prior art:** chez-cmark-gfm ADR-0009 (positions need `SOURCEPOS`) and
  ADR-0010 (cmark's XML as the AST oracle)

## Context

The plan split the copier over two milestones. M2 would copy one standard
node family, tables and task items, and run the oracle on the families it
copied. M3 would copy the rest, and run the oracle over the whole corpus.

M1 handed M2 three items that need a parser (ADR-0014): give each
reference its definition's label as written; settle the two footnote
divergences against the oracle; and show that each hand-built fixture AST
is what the parser builds. The 28 fixtures cover every node kind but
`:extension`.

Checking facts against the pin found (spec §2):
- **A parsed reference has lost its label** (finding 6). Its literal
  becomes its number, such as `"1"`. Its definition is
  `cmark_node_parent_footnote_def`, whose literal is the label as written.
  ADR-0005's finding 2 says a reference's literal is its label.
- **Positions are only right with `CMARK_OPT_SOURCEPOS`** (finding 7).
  Without it, cmark skips `adjust_subj_node_newlines` (`src/inlines.c`),
  so positions after a multi-line code span or raw HTML drift.
- **A lone surrogate** is a character on SBCL and ECL, and not on CCL
  (finding 11). UTF-8 can't encode one.
- **The corpus** has 747 enabled examples in six files. With the flags
  cmark's harness uses, the pinned CLI reproduces the expected HTML of
  every one but the example that expects `<IGNORE>` (finding 8).
- **cmark's XML** prints every node with its attributes, and with
  `SOURCEPOS` its position. It has three quirks (finding 13): footnotes
  print as `<<unknown>` with no label, `align` appears only on header-row
  cells, and task items carry `completed`.
- **cmark can return bytes that aren't UTF-8** (finding 19, from M2b's
  review). A dangling reference that spans lines can be cut inside a
  multi-byte character, and the text cmark makes of it keeps the cut
  bytes.

ADR-0011's oracle has a weak spot: both sides share one parse. A wrong
option bit, or a broken corpus reader, would let the tree and cmark agree
while both are wrong.

## Decision

### Every node kind (D1)

`copy-native-tree` copies every kind of the vocabulary. It walks the
parsed tree with the one native walker, and builds nodes bottom-up through
`make-node`, so a copied AST passes the schema (spec §6).
- **M2 tested every kind a parse produces.** No parse produces
  `:extension` under the pin (ADR-0008, finding 9), so M2 left that kind,
  version probes and property tests to M3.
- **M3 tests `:extension`** on real nodes built through cmark's public
  API (M3 spec §4; M3 finding 3).

### Labels from the parent definition (D15)

A footnote reference's `:label` is its definition's literal, read through
`cmark_node_parent_footnote_def` (spec §6.3). That is the label as written,
which the converter matches with `string=` (ADR-0014).

### Positions only with `SOURCEPOS`

`:sourcepos t` sets `CMARK_OPT_SOURCEPOS`. With `:sourcepos nil`, no
position reaches the AST (spec §6.4). Positions parsed without the bit are
present, but wrong after a multi-line code span or raw HTML, so the copier
never copies them (chez ADR-0009). The others stay as ADR-0005 has them:
copied as reported, never repaired, negative ones included (M3 finding 7).

### One encoder, with U+FFFD for a lone surrogate

One UTF-8 encoder in `/util` measures the input and fills the byte vector
(spec §6.5). It encodes a lone surrogate as U+FFFD, so cmark only ever
sees valid UTF-8. `CMARK_OPT_VALIDATE_UTF8` stays on, as a second guard.

### Output decoded with U+FFFD for bad bytes

Every string cmark returns is decoded as UTF-8, and ill-formed bytes
become U+FFFD, as Unicode recommends (spec §6.5).
- **Decoding never fails.** cmark can return bad bytes for a valid input
  (finding 19), so a strict decoder would turn that input into an error.
- **Lengths never shrink.** U+FFFD is never shorter than the bytes it
  replaces. The soundness tests measure decoded output (spec §8.4), so a
  bound that passes them covers cmark's own bytes too.

### Four witnesses, over the whole corpus (D4)

A pure corpus reader mirrors `spec_tests.py` (spec §8.2). Four witnesses
check the result, each independent of the others (spec §8.3):
1. **cmark's expectations** cover ADR-0011's weak spot. `markdown->html`
   must reproduce the HTML cmark's own tests expect, so the corpus reader
   and the option bits answer to something this project didn't write.
2. **The HTML oracle** (ADR-0011) checks the converter against cmark's
   HTML.
3. **The XML oracle** (chez ADR-0010) checks the copied AST itself, against
   `cmark_render_xml` of the same document. It sees what the HTML oracle
   can't: positions, a list's delimiter, a code block's whole info string.
4. **The fixture ASTs** show that M1's hand-built ASTs are what the parser
   builds.

ADR-0014's two divergences are pinned twice (spec §8.3):
- **In the corpus.** An example that hits one is listed by name, and must
  keep differing, so a fix has to remove it from the list.
- **Directly.** Each is pinned by a minimal input whose tree-path HTML is
  asserted exactly. The corpus may hit neither, and then the list alone
  would never notice a fix.

### Rejected

- **The plan's thin slice** (D1). M1's hand-offs need more than one family
  with tables and task items: the fixtures cover every kind but
  `:extension`, and two of the items need footnotes. The oracle would also
  skip every example that uses a kind not yet copied.
- **Leaving the XML oracle to M3** (D4). The HTML oracle sees the copied AST
  only through the converter. That writes no positions (ADR-0010), and, like
  cmark's HTML, no list delimiter and only the first word of a code block's
  info (`src/html.c`). So the HTML oracle alone can't see a copier drop a
  position or a delimiter, or cut an info string short:
  - the fixture ASTs (a `:paren` list, the info `lisp extra words`) and a
    direct test of positions catch those only on their own shapes;
  - the XML oracle catches them over the whole corpus.

## Consequences

- ADR-0005's finding 2 now holds for definitions only. A parsed reference's
  literal is its number.
- The whole corpus runs in M2, not M3 (ADR-0011, ADR-0013). M3 keeps
  unknown extensions, version probes and property tests.
- ADR-0014's three hand-offs to M2 are settled in M2b.
- The XML writer is test-only. Its expectation comes from cmark, so the
  writer can't be tuned to hide a copier bug (chez ADR-0010).
- What no corpus-wide witness sees in the AST itself gets a direct test: a
  reference's label as written, body-cell alignment, the document's
  attributes, and `:sourcepos nil` (spec §8.3).
- Text nodes stay split where cmark split them (spec §6.1), so the fixture
  comparison merges adjacent text on both sides first (spec §8.3).
- `#\Nul`, a lone surrogate and a character cmark cuts in two (finding 19)
  all reach the AST as U+FFFD: cmark replaces the first, the encoder the
  second, and the decoder the third.
- With `:sourcepos nil`, an AST has no positions at all, rather than wrong
  ones.
