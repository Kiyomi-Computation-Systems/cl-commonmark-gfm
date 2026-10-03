# M3 property-testing benchmark — results

- **Date:** 2026-10-02
- **Plan:** [2026-10-02-m3-extensions-versions-properties-implementation.md](2026-10-02-m3-extensions-versions-properties-implementation.md), Task 7
- **Spec:** [2026-10-02-m3-extensions-versions-properties-design.md](2026-10-02-m3-extensions-versions-properties-design.md) §6.5, §6.6
- **Evidence for:** [ADR-0020](decisions/0020-property-based-testing.md)

All runs below were made in the Guix container (`scripts/guix-env`), on the unmutated tree unless a
mutation is named, with `CL_SOURCE_REGISTRY="$PWD/:$PWD/ocicl//"` and
`sbcl --dynamic-space-size 2048 --non-interactive --no-sysinit --no-userinit --load tests/spike/run.lisp`
(CCL and ECL as `tests/spike/run.lisp` documented). The spike's runner and `tests/spike/` were
deleted when the properties joined the suites (plan Task 9). States facts only; this file makes no
recommendation.

## Headline

- Of the seven mutations, **all seven were caught by the existing suite** (`make -k test`), already
  without any property.
- Two mutations (1 and 7) were **missed by every property, at the chosen CI case count, on both
  contenders** — in both cases because the property that reads the mutated value compares it against
  a bound that already has enough slack (or whose failure mode needs a rare combination) that random
  generation did not close the gap within budget, even though hand-written adversarial fixtures do.
- Five mutations (2, 3, 4, 5 and 6) were each caught by at least one property, each with a specific,
  small, auto-shrunk counter-example (as small as the empty string).
- No unmutated run (100,000 cases, 22 runs total, 2 contenders) found a failure, a guard that
  shouldn't have fired, or an unexplained excuse.

## 1. The CI case count

### Method

`run-property`'s printed "cases/s" already excludes Lisp startup and ASDF compilation (it times
from inside `run-property`, after the system is loaded), so no fasl-cache discipline was needed for
these measurements — only for the mutation runs in §2.

Throughput was measured fresh, seed 1, on the unmutated tree, at 10,000 cases per native
(property, generator) pair on SBCL, and 20,000 cases for `utf8` on CCL and ECL. SBCL's `utf8`
runs about 0.1 s per 10,000 cases, so it isn't part of the budget:

| Property | Generator | own, cases/s | check-it, cases/s |
|---|---|---:|---:|
| bounds | syntax-soup | 9,425 | 10,142 |
| bounds | corpus-splices | 17,361 | 16,103 |
| clean-outcomes | syntax-soup | 3,495 | 3,499 |
| clean-outcomes | corpus-splices | 4,456 | 4,462 |
| html-oracle | syntax-soup | 11,561 | 11,947 |
| html-oracle | corpus-splices | 20,576 | 20,877 |
| xml-oracle | syntax-soup | 12,300 | 12,706 |
| xml-oracle | corpus-splices | 21,097 | 21,322 |
| utf8 (CCL) | octets | 29,940 | 73,260 |
| utf8 (ECL) | octets | 15,504 | 15,711 |

This matches the earlier tasks' reported ranges (roughly 3,400–20,000/s native, 15,000–120,000/s
`utf8`). For the four native properties, the two contenders' throughput is within about 10%:
generation cost is negligible next to a parse, render and copy through cmark. `utf8` has no such
round trip, and there `:check-it` was faster on CCL, 73,260 cases/s against 29,940.

### Arithmetic

One case count was chosen per **property** (shared by both its generators, and for `utf8` by all
three Lisps), sized from `:own`'s SBCL throughput above so that each native property's two
generators, and `utf8`'s CCL+ECL lanes, take about 6 seconds together — 4 native properties + 1
`utf8` lane ≈ 30 s:

| Property | Chosen cases | Arithmetic (own, SBCL throughput above) | Predicted time |
|---|---:|---|---:|
| bounds | 36,000 | 36000/9425 + 36000/17361 | 3.820 + 2.073 = 5.893 s |
| clean-outcomes | 12,000 | 12000/3495 + 12000/4456 | 3.434 + 2.693 = 6.127 s |
| html-oracle | 44,000 | 44000/11561 + 44000/20576 | 3.806 + 2.139 = 5.945 s |
| xml-oracle | 46,000 | 46000/12300 + 46000/21097 | 3.740 + 2.180 = 5.920 s |
| utf8 (CCL+ECL) | 60,000 | 60000/29940 + 60000/15504 | 2.004 + 3.870 = 5.874 s |
| **Total** | | | **29.76 s** |

### Validation (fresh run, seed 1, both contenders, at the chosen counts)

| Property | Generator | own, seconds | check-it, seconds |
|---|---|---:|---:|
| bounds | syntax-soup | 3.720 | 3.532 |
| bounds | corpus-splices | 2.014 | 1.970 |
| clean-outcomes | syntax-soup | 3.445 | 3.458 |
| clean-outcomes | corpus-splices | 2.720 | 2.734 |
| html-oracle | syntax-soup | 3.733 | 3.655 |
| html-oracle | corpus-splices | 2.166 | 2.139 |
| xml-oracle | syntax-soup | 3.845 | 3.636 |
| xml-oracle | corpus-splices | 2.215 | 2.201 |
| **SBCL subtotal** | | **23.858** | **23.325** |
| utf8 | octets (CCL) | 1.979 | 0.819 |
| utf8 | octets (ECL) | 3.809 | 3.791 |
| **Grand total** | | **29.65 s** | **27.94 s** |

Both contenders land within about 2 s of the 30 s target at these counts. (`utf8` on SBCL itself,
not part of the 30 s budget, ran in 0.608 s for `:own` and 0.513 s for `:check-it` at 60,000 cases —
negligible, which is why the budget sentence only names CCL and ECL for `utf8`.)

GitHub's runner was about 1.3 to 1.4 times slower than local runs for M2b's `make test`: 158 s on
GitHub, against 115 to 117 s in local `debian:trixie` Docker and 122 s in the Guix container
(`progress.md`, M2b close-out). At this budget that projects to roughly 39 to 41 s (`:own`) of
GitHub runner time, on top of `make test`'s own time — a fact to weigh, not a recommendation.

**Used below:** bounds 36,000; clean-outcomes 12,000; html-oracle 44,000; xml-oracle 46,000 — each
seed 1 for the mutation runs in §2.

## 2. The seven mutations

Method, repeated for each mutation: apply the single change → delete
`.guix-env/cache/common-lisp/` → `make -k test` → (same fasl cache, no revert yet) run all four
native properties, both contenders, seed 1, at the §1 case counts → revert → delete the fasl cache
→ confirm with a fresh `make check-native` (and `make check-purity` for mutations touching
`src/html-tree/` or `src/native-core/`). `git diff src/` was byte-identical to the saved baseline
after every revert (confirmed individually each time; see §4 for the final check).

All four properties were run for every mutation, whether or not each could structurally see it, so
that "0 failed" below is evidence, not an assumption.

### Mutation 1 — `html-footnotes-bound` uses the tree's reference count, not the input's openers

`src/native/output-bounds.lisp`, undoing finding 17: `(openers (- candidates definitions))` →
`(openers references)`.

- **`make -k test`:** FAILS. `check-native`, `tests/native/limits.lisp`,
  `neither-output-bound-undercounts-crafted-inputs`, on the hand-built "references in a dropped
  definition" fixture: `(>= bound octets)` — bound 249, rendered 9020. A ~36× undercount.

| Property | Generator | own | check-it |
|---|---|---|---|
| bounds | syntax-soup | pass (0/36,000, 438 guard) | pass (0/36,000, 431 guard) |
| bounds | corpus-splices | pass (0/36,000) | pass (0/36,000) |
| clean-outcomes | syntax-soup | pass (0/12,000, 141 guard) | pass (0/12,000, 151 guard) |
| clean-outcomes | corpus-splices | pass (0/12,000) | pass (0/12,000) |
| html-oracle | syntax-soup | pass (0/44,000, 533 guard) | pass (0/44,000, 515 guard) |
| html-oracle | corpus-splices | pass (0/44,000) | pass (0/44,000) |
| xml-oracle | syntax-soup | pass (0/46,000, 554 guard) | pass (0/46,000, 536 guard) |
| xml-oracle | corpus-splices | pass (0/46,000) | pass (0/46,000) |

No property saw it. Only `bounds` ever compares `html-output-bound`'s numeric value (against
`render-html`'s actual octets); `clean-outcomes` and `html-oracle` call `markdown->html`, which
checks the same bound only against `*max-output-octets*` (64 MiB — far above anything a ≤400-char
or ≤20-line case renders), so an undercount there changes nothing observable; `xml-oracle` never
calls `html-output-bound` at all. Within `bounds`, the gap the mutation opens needs a *dropped*
footnote definition (a duplicate label) that still carries backrefs, a specific, multi-definition
shape that a rare, already-small `[^...]`-producing generator (finding 8) essentially never
assembles by chance inside 36,000 cases — but the hand-written fixture engineers it directly.

### Mutation 2 — strict UTF-8 decoding (finding 19 undone)

`src/native/document.lisp` (`foreign-utf8-string`) and `src/native/render.lisp`
(`decoded-render`): `decode-utf8` → `(babel:octets-to-string octets :encoding :utf-8)`.

- **`make -k test`:** FAILS. `check-native`, `tests/native/renderers.lisp`,
  `ill-formed-utf-8-from-cmark-decodes-through-every-entry-point` (the e-acute/emoji
  split-footnote-label fixtures: `(parse ...)`, `(markdown->html ...)` and
  `(markdown->plaintext ...)` all signal instead of returning); and
  `tests/native/limits.lisp`, `neither-output-bound-undercounts-crafted-inputs` ("HTML of a split
  label" — `render-html` now signals where the bound expected a count).

| Property | Generator | own | check-it |
|---|---|---|---|
| bounds | syntax-soup | **FAIL** case 1,062/36,000 | **FAIL** case 71/36,000 |
| bounds | corpus-splices | pass (0/36,000) | pass (0/36,000) |
| clean-outcomes | syntax-soup | **FAIL** case 1,062/12,000 | **FAIL** case 71/12,000 |
| clean-outcomes | corpus-splices | pass (0/12,000) | pass (0/12,000) |
| html-oracle | syntax-soup | **FAIL** case 1,132/44,000 | **FAIL** case 3,303/44,000 |
| html-oracle | corpus-splices | pass (0/44,000, 1 excused-dropped) | pass (0/44,000, 1 excused-dropped) |
| xml-oracle | syntax-soup | **FAIL** case 1,062/46,000 | **FAIL** case 71/46,000 |
| xml-oracle | corpus-splices | pass (0/46,000) | pass (0/46,000) |

All four properties can see it, through either a native string accessor (literals, labels) or a
renderer; only `syntax-soup` produced the triggering shape within budget (a bracket/footnote
fragment immediately followed by a multibyte character cmark then cuts). `bounds`, `clean-outcomes`
and `xml-oracle` failed on the identical case and input for a given (contender, generator) — they
share one input stream and the decode happens on the same call path (through `parse`/`copy`).
`html-oracle` diverged, failing later on a different input, because it first calls cmark's own
`markdown->html`, which can render some of these cases without tripping the same decode; it only
fails once its own `tree-path` (→ `markdown->html-tree` → `parse` → copy) meets a cut character.

Shrunk inputs (all `BABEL-ENCODINGS:INVALID-UTF8-CONTINUATION-BYTE`):
- own, syntax-soup, bounds/clean-outcomes/xml-oracle: `"[^[]\n\u{1F600}[]]"` (294/192/… → 9
  characters, 840 calls).
- own, syntax-soup, html-oracle: `"@$```~ x4]:.N[^u\u{E9}[\r*)']#c&#94;?;/ |L]"` (379 → 37
  characters, 141 calls).
- check-it, syntax-soup, bounds/clean-outcomes/xml-oracle: ``` "``[^\u{1F600}\n`@=g~]" ``` (176 → 12
  characters, 1,538 calls).
- check-it, syntax-soup, html-oracle: `"[^J|+_>h\r\u{E9}l|%#f^h(]"` (110 → 19 characters, 1,795
  calls).

### Mutation 3 — `copied-sourcepos` copies the start position as the end

`src/native/copy.lisp`: the end `cons` becomes `(cons start-line (native-start-column document
node))` instead of reading the real end line/column.

- **`make -k test`:** FAILS, broadly. `check-native`: `tests/native/copier.lisp`
  (`kinds-and-positions` on several inputs, e.g. `:document ((1 . 1) . (2 . 1))` expected vs.
  `((1 . 1) . (1 . 1))` got; `positions-are-copied-as-cmark-reports-them` on `vocabulary.md`, all 76
  positions wrong); `tests/native/parse.lisp` (the negative-column link test, finding 7); and
  `tests/native/oracles.lisp` (the corpus-wide XML-sourcepos regression — 672 `spec.txt` examples
  plus `regression.txt`, `smart_punct.txt`, `extensions*.txt` all reported as mismatched at once).

| Property | Generator | own | check-it |
|---|---|---|---|
| bounds | syntax-soup | pass (0/36,000) | pass (0/36,000) |
| bounds | corpus-splices | pass (0/36,000) | pass (0/36,000) |
| clean-outcomes | syntax-soup | pass (0/12,000) | pass (0/12,000) |
| clean-outcomes | corpus-splices | pass (0/12,000) | pass (0/12,000) |
| html-oracle | syntax-soup | pass (0/44,000) | pass (0/44,000) |
| html-oracle | corpus-splices | pass (0/44,000, 1 excused-dropped) | pass (0/44,000, 1 excused-dropped) |
| xml-oracle | syntax-soup | **FAIL** 45,328/46,000 (case 1) | **FAIL** 45,355/46,000 (case 1) |
| xml-oracle | corpus-splices | **FAIL** 45,916/46,000 (case 1) | **FAIL** 45,941/46,000 (case 1) |

Only `xml-oracle` sets `:sourcepos t`; the 33 HTML-oracle option sets `bounds`, `clean-outcomes` and
`html-oracle` draw from never do, so `copied-sourcepos`'s wrong value is built but never read by
them (and `bounds` never calls the copier for this check at all). `xml-oracle` fails on
essentially every case, from the first.

Shrunk inputs:
- own, syntax-soup: `""` (248 → 0 characters, 2 calls — the empty document's own mismatched
  position was already enough).
- own, corpus-splices: `""` (17 → 0 characters, 2 calls).
- check-it, syntax-soup: `"--"` (37 → 2 characters, 37 calls).
- check-it, corpus-splices: `"ar"` (34 → 2 characters, 34 calls).

### Mutation 4 — `copied-list-attributes` records `:delimiter` as `nil`

`src/native/copy.lisp`: `:delimiter (native-list-delimiter document node)` → `:delimiter nil`.

- **`make -k test`:** FAILS, broadly. `check-native`: every native test that parses an ordered list
  now hits `CL-COMMONMARK-GFM.CONDITIONS:INVALID-AST-NODE` from `src/ast/node.lisp`'s own schema
  rule ("`:ordered list needs an integer :start and a non-nil :delimiter`") — including
  `tests/native/oracles.lisp`'s `oracle case lists-ordered` and the `vocabulary.md` sourcepos test
  (vocabulary.md itself contains an ordered list).

| Property | Generator | own | check-it |
|---|---|---|---|
| bounds | syntax-soup | **FAIL** 18/36,000, first at case 669 | **FAIL** 18/36,000, first at case 1,136 |
| bounds | corpus-splices | **FAIL** 3,469/36,000, first at case 8 | **FAIL** 3,476/36,000, first at case 12 |
| clean-outcomes | syntax-soup | **FAIL** 7/12,000, first at case 669 | **FAIL** 5/12,000, first at case 1,136 |
| clean-outcomes | corpus-splices | **FAIL** 1,139/12,000, first at case 8 | **FAIL** 1,158/12,000, first at case 12 |
| html-oracle | syntax-soup | **FAIL** 22/44,000, first at case 669 | **FAIL** 25/44,000, first at case 1,136 |
| html-oracle | corpus-splices | **FAIL** 4,257/44,000, first at case 8 (1 excused-dropped) | **FAIL** 4,262/44,000, first at case 12 |
| xml-oracle | syntax-soup | **FAIL** 25/46,000, first at case 669 | **FAIL** 25/46,000, first at case 1,136 |
| xml-oracle | corpus-splices | **FAIL** 4,475/46,000, first at case 8 | **FAIL** 4,479/46,000, first at case 12 |

Every ordered list anywhere in the input reaches `copy-native-tree` (through `parse`, hence through
`markdown->html-tree` and `ast->cmark-xml` too), so all four properties see it. For a given
(contender, generator), all four failed at the identical case with the identical shrunk input — they
share one input stream, and the schema check fires deterministically on the first ordered list each
draws. `corpus-splices` (real corpus text, full of ordered lists) fails far more densely than
`syntax-soup` (which needs to assemble "digit + `.`/`)` + space" by chance).

Shrunk inputs: own/syntax-soup → `"0."` (294 → 2 characters, 22 calls); own/corpus-splices →
`"2."` (228 → 2, 22 calls); check-it/syntax-soup → `"5)"` (319 → 2, 1,045 calls);
check-it/corpus-splices → `"1."` (222 → 2, 622 calls).

### Mutation 5 — the converter keeps `<p>` inside a tight list

`src/html-tree/convert.lisp`, `render-paragraph`: the `(unless (tight-list-p (grandparent
renderer)) ...)` guard removed, so `<p>`/`</p>` are always emitted.

- **`make -k test`:** FAILS. `check-purity` fails identically on **sbcl, ccl and ecl**:
  `tests/html-tree.lisp`, e.g. `ast->html-tree-tight-bullet-list` (expects
  `((:ul nil "~%" (:li nil "a") "~%" (:li nil "b") "~%") "~%")`, gets `<p>`-wrapped items instead).
  `check-native` also fails (the native suite exercises `ast->html-tree` on real parsed documents
  too).

| Property | Generator | own | check-it |
|---|---|---|---|
| bounds | syntax-soup | pass (0/36,000) | pass (0/36,000) |
| bounds | corpus-splices | pass (0/36,000) | pass (0/36,000) |
| clean-outcomes | syntax-soup | pass (0/12,000) | pass (0/12,000) |
| clean-outcomes | corpus-splices | pass (0/12,000) | pass (0/12,000) |
| html-oracle | syntax-soup | **FAIL** 5,046/44,000, first at case 8 | **FAIL** 5,127/44,000, first at case 2 |
| html-oracle | corpus-splices | **FAIL** 15,803/44,000, first at case 7 | **FAIL** 15,638/44,000, first at case 7 |
| xml-oracle | syntax-soup | pass (0/46,000) | pass (0/46,000) |
| xml-oracle | corpus-splices | pass (0/46,000) | pass (0/46,000) |

Only `html-oracle` compares rendered HTML text that goes through `html-tree`; `clean-outcomes` only
checks that `markdown->html-tree` *returns* (it does, just with different content), and `bounds`/
`xml-oracle` never call it at all. Once a tight list appears — easy for both generators — the
mismatch is dense (up to 36% of cases).

Shrunk inputs: own/syntax-soup → `"- ]"` (346 → 3 characters, 20 calls); own/corpus-splices →
`"- ]"` (110 → 3, 15 calls); check-it/syntax-soup → `"- ]"` (384 → 3, 397 calls);
check-it/corpus-splices → `"- e"` (259 → 3, 625 calls). Every shrink converged on "one tight
bullet item holding one character."

### Mutation 6 — `plaintext-prefix-width` returns 0

`src/native-core/output-bounds.lisp`: the whole function replaced by `(declare (ignore kind
marker-width)) 0`.

- **`make -k test`:** FAILS. `check-purity` fails identically on **sbcl, ccl and ecl**:
  `tests/native-core.lisp`, `plaintext-prefix-width-is-what-each-container-adds` (direct unit test,
  e.g. `(is = 5 (plaintext-prefix-width :item 5))` now gets 0). `check-native` also fails.

| Property | Generator | own | check-it |
|---|---|---|---|
| bounds | syntax-soup | **FAIL** 1,034/36,000, first at case 124 | **FAIL** 1,013/36,000, first at case 42 |
| bounds | corpus-splices | **FAIL** 3,184/36,000, first at case 10 | **FAIL** 3,196/36,000, first at case 7 |
| clean-outcomes | syntax-soup | pass (0/12,000) | pass (0/12,000) |
| clean-outcomes | corpus-splices | pass (0/12,000) | pass (0/12,000) |
| html-oracle | syntax-soup | pass (0/44,000) | pass (0/44,000) |
| html-oracle | corpus-splices | pass (0/44,000, 1 excused-dropped) | pass (0/44,000) |
| xml-oracle | syntax-soup | pass (0/46,000) | pass (0/46,000) |
| xml-oracle | corpus-splices | pass (0/46,000) | pass (0/46,000) |

Only `bounds` compares `plaintext-output-bound` against `render-plaintext`'s actual octets; the
other three never inspect that bound's value, and `*max-output-octets*` is unaffected at this input
size. Any list item, task item, or footnote definition (common in both generators) widens the real
prefix, so the mismatch is dense (3–9% of cases).

Shrunk inputs: own/syntax-soup → `"- o\r<"` (251 → 5 characters, 37 calls); own/corpus-splices →
`"- c\nr"` (160 → 5, 32 calls); check-it/syntax-soup → `"- ~\n!"` (275 → 5, 568 calls);
check-it/corpus-splices → `` "- \\\ne" `` (259 → 5, 696 calls).

### Mutation 7 — `table-cell-bound` counts one row too few

`src/native-core/limits.lisp`, `close-run`: `(incf total (* run-max-dashes run-lines))` →
`(incf total (* run-max-dashes (1- run-lines)))`.

- **`make -k test`:** FAILS. `check-purity` fails identically on **sbcl, ccl and ecl**:
  `tests/native-core.lisp`'s `table-cell-bound-*` tests, e.g. `table-cell-bound-lf-line-ends`
  (`"|-|-|\n|-|-|\n"`, expects 4, gets 2), `table-cell-bound-cr-line-ends` (expects 4, gets 2),
  `table-cell-bound-crlf-is-one-line-end` (expects 6, gets 3), and
  `table-cell-bound-without-a-trailing-newline` (expects 2, gets 0). `check-native` also fails.

| Property | Generator | own | check-it |
|---|---|---|---|
| bounds | syntax-soup | pass (0/36,000, 438 guard) | pass (0/36,000, 431 guard) |
| bounds | corpus-splices | pass (0/36,000) | pass (0/36,000) |
| clean-outcomes | syntax-soup | pass (0/12,000) | pass (0/12,000) |
| clean-outcomes | corpus-splices | pass (0/12,000) | pass (0/12,000) |
| html-oracle | syntax-soup | pass (0/44,000) | pass (0/44,000) |
| html-oracle | corpus-splices | pass (0/44,000, 1 excused-dropped) | pass (0/44,000, 1 excused-dropped) |
| xml-oracle | syntax-soup | pass (0/46,000) | pass (0/46,000) |
| xml-oracle | corpus-splices | pass (0/46,000) | pass (0/46,000) |

No property saw it, on either contender. `bounds` is the only one that reads `table-cell-bound`'s
value at all, but the bound is already a generous over-estimate by construction — it multiplies the
*widest* candidate line's dash-run count by *every* line in the whole non-blank run, not just the
table's own rows — so losing one line's worth of credit rarely closes the gap down to the actual
`:table-cell` count for the small (≤400-character / ≤20-line) tables either generator builds. The
hand-written tests that do catch it are built exactly tight against the arithmetic (two lines,
bound 4, actual 4), a shape random generation essentially never lands on by chance.

## 3. Unmutated runs (100,000 cases, random seeds)

No library mutation. Every (property, contender, generator) ran once at 100,000 cases with
`SPIKE_SEED=random`; `utf8` ran on all three Lisps.

| Property | Generator | Contender | Seed | Passed | Failed | Guard | Excused | Seconds | Cases/s |
|---|---|---|---:|---:|---:|---:|---|---:|---:|
| bounds | syntax-soup | own | 4,161,657,470 | 98,833 | 0 | 1,167 | none | 10.087 | 9,914 |
| bounds | corpus-splices | own | 4,171,934,501 | 100,000 | 0 | 0 | none | 5.718 | 17,489 |
| clean-outcomes | syntax-soup | own | 4,177,928,519 | 98,835 | 0 | 1,165 | none | 28.306 | 3,533 |
| clean-outcomes | corpus-splices | own | 4,206,928,606 | 100,000 | 0 | 0 | none | 22.471 | 4,450 |
| html-oracle | syntax-soup | own | 4,229,932,675 | 98,785 | 0 | 1,215 | none | 8.589 | 11,643 |
| html-oracle | corpus-splices | own | 4,238,931,702 | 100,000 | 0 | 0 | none | 5.064 | 19,747 |
| xml-oracle | syntax-soup | own | 4,243,930,716 | 98,816 | 0 | 1,184 | none | 8.302 | 12,045 |
| xml-oracle | corpus-splices | own | 4,252,936,744 | 100,000 | 0 | 0 | none | 4.757 | 21,022 |
| bounds | syntax-soup | check-it | 4,257,926,758 | 98,810 | 0 | 1,190 | none | 9.932 | 10,068 |
| bounds | corpus-splices | check-it | 4,267,931,788 | 100,000 | 0 | 0 | none | 5.883 | 16,998 |
| clean-outcomes | syntax-soup | check-it | 4,274,928,810 | 98,785 | 0 | 1,215 | none | 28.423 | 3,518 |
| clean-outcomes | corpus-splices | check-it | 8,943,600 | 100,000 | 0 | 0 | none | 22.124 | 4,520 |
| html-oracle | syntax-soup | check-it | 30,962,666 | 98,819 | 0 | 1,181 | none | 7.930 | 12,610 |
| html-oracle | corpus-splices | check-it | 38,952,690 | 100,000 | 0 | 0 | none | 4.783 | 20,907 |
| xml-oracle | syntax-soup | check-it | 44,954,709 | 98,830 | 0 | 1,170 | none | 7.728 | 12,940 |
| xml-oracle | corpus-splices | check-it | 52,947,733 | 100,000 | 0 | 0 | none | 4.692 | 21,313 |
| utf8 (SBCL) | octets | own | 72,777,791 | 100,000 | 0 | 0 | none | 0.969 | 103,199 |
| utf8 (SBCL) | octets | check-it | 73,777,794 | 100,000 | 0 | 0 | none | 0.835 | 119,760 |
| utf8 (CCL) | octets | own | 78,797,247 | 100,000 | 0 | 0 | none | 3.538 | 28,265 |
| utf8 (CCL) | octets | check-it | 82,246,468 | 100,000 | 0 | 0 | none | 1.360 | 73,529 |
| utf8 (ECL) | octets | own | 116,714,505 | 100,000 | 0 | 0 | none | 6.403 | 15,618 |
| utf8 (ECL) | octets | check-it | 107,114,528 | 100,000 | 0 | 0 | none | 6.373 | 15,691 |

**No failures, in any of the 22 runs, on either contender.** No `:excused-repeat` or
`:excused-dropped` occurred in this batch either (consistent with finding 8's roughly 6-per-million
rate for `:excused-dropped` and 0 for `:excused-repeat`: at 100,000 cases each, seeing none is
unsurprising). There is nothing to investigate: a failure on unmutated code would need
investigating to tell a library bug from a spike mistake (per the brief), but none occurred.

## 4. Final state

- `git diff --stat src/` after the last revert:
  ```
  src/ast/node.lisp            | 14 ++++++++++----
  src/ffi.lisp                 |  8 ++++++++
  src/native-core/package.lisp |  3 +++
  src/native/package.lisp      |  3 +++
  src/native/startup.lisp      | 36 +++++++++++++++++++++++++++++++++---
  5 files changed, 57 insertions(+), 7 deletions(-)
  ```
  Byte-identical to the baseline saved before the first mutation (Tasks 1–6's own changes only;
  `src/native-core/version.lisp` stays untracked and unmodified). Checked after every individual
  revert in §2, and once more here.
- Fresh fasl cache, full `make test` (`check-watchdog`, `check-purity` on sbcl/ccl/ecl,
  `check-fixtures`, `check-native`): all green, exit 0.

## 5. Summary

- **Existing suite vs. properties, on these seven mutations:** the existing suite (`make -k test`)
  caught all seven. No mutation here was caught by a property alone. Two (1, 7) were caught by the
  existing suite only — both are cases where a property reads the mutated value but compares it
  against a bound with enough built-in slack, or needing an input shape rare enough (a duplicate
  footnote definition; an exactly-tight multi-row table), that the generators didn't close the gap
  in 12,000–46,000 cases, while a hand-written adversarial fixture hits it directly. The other five
  were each caught by exactly the property whose comparison actually reads the mutated code's
  output (`xml-oracle` for a sourcepos bug, since only it parses with `:sourcepos t`;
  `html-oracle` for an HTML-tree rendering bug, since only it compares tree HTML text; `bounds` for
  a plaintext-bound bug, since only it compares that bound's number) — except mutation 2 (decoding)
  and mutation 4 (an ordered list's schema), which are reachable from all four properties' call
  paths and so were caught by all four.
- **Unmutated runs:** 100,000 cases × 2 contenders × (4 native properties × 2 generators, plus
  `utf8` on 3 Lisps) = 22 runs, 0 failures, 0 unexplained excuses. No real bug surfaced at this
  scale; §3 has every seed.
- **Shrinking:** both contenders reduced every failing case to a short input, from the empty string
  (mutation 3, `:own`) to 37 characters (mutation 2, `:own`, `html-oracle`). They differed in two
  places:
  - **mutation 3:** `:own` reached the empty string on both generators, and `:check-it` stopped at 2
    characters (`"--"`, `"ar"`);
  - **mutation 2:** `:own` gave 9 characters (`bounds`, `clean-outcomes`, `xml-oracle`) and 37
    (`html-oracle`); `:check-it` gave 12 and 19.

  Elsewhere they converged on inputs of the same size and shape (e.g. `"- ]"` for mutation 5 on
  three of four runs).
- **Speed:**
  - **properties 1 to 4:** within about 10% of each other, either direction. Generation cost is
    negligible next to the native round trip the property times;
  - **`utf8`:** `:check-it` was faster on CCL (73,260 against 29,940 cases/s) and on SBCL (0.513 s
    against 0.608 s for its run), and level on ECL (15,711 against 15,504 cases/s).
- **Replay:** not exercised by this benchmark's failures (all occurred on SBCL, where both
  contenders are seeded and both replay). Separately established (finding 5; `tests/spike/check-it.lisp`'s
  header, from probing `sb-ext:seed-random-state`, `ccl::init-random-state-seeds`/`ccl::seed`, and
  `ext:random-state-array`): `:own`'s splitmix64 stream replays identically from one integer seed on
  SBCL, CCL and ECL; `:check-it` can only be seeded from an integer on SBCL — on CCL and ECL it draws
  from a fresh, OS-seeded state regardless of `SPIKE_SEED`, so only the shrunk input text (not the
  seed) is replayable there.
- **Dependencies and code size:** `:check-it` adds five ocicl rows from three packages (`check-it`,
  `closer-mop`, and `optima` with `optima.ppcre` and `optima.test`, per `git diff ocicl.csv`); `:own`
  adds none. `:check-it`'s adapter alone
  (`tests/spike/check-it.lisp`, 328 lines) is larger than `:own`'s entire generator-plus-shrinker
  stack (`random.lisp` + `shrink.lisp`, 112 + 92 = 204 lines) — before counting check-it's own
  library.
