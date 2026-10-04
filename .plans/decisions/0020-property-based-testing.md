# ADR-0020: Property-based testing, with a generator and shrinker of our own

- **Status:** Accepted 2026-10-02, confirmed by the user after the spike;
  amended 2026-10-03 by the [M4 spec](../2026-10-03-m4-ccl-ecl-design.md)
  D3 and §5.5: the native properties run on CCL and ECL too, in CI on
  `main` and on dispatch, at the same counts from the same seed
- **Date:** 2026-10-02
- **Scope:** property-based tests: their generators, shrinker and
  properties; their seeds and case counts; `make fuzz`
- **Spec:**
  [M3 design](../2026-10-02-m3-extensions-versions-properties-design.md)
  §2 (D1), §3 (findings 5 to 10), §6, §9
- **Evidence:** [the M3 benchmark](../2026-10-02-m3-benchmark.md)
- **Amends:** ADR-0007 (property-based testing, deferred to M3, is
  adopted, with neither check-it nor cl-quickcheck)
- **Related:** ADR-0005 (positions as cmark reports them), ADR-0011 and
  ADR-0018 (the oracles properties 1 and 2 reuse), ADR-0013 (CI), ADR-0014
  (the divergences property 1 excuses), ADR-0016 (the bounds property 3
  checks), ADR-0019 (the input guard, whose rejections the properties
  count)
- **Prior art:** chez-cmark-gfm ADR-0010 and ADR-0012 (cmark's XML and HTML
  as oracles over the corpus), and its AGENTS.md's "Tests must be seen to
  fail"

## Context

- **ADR-0007 deferred property-based testing to M3,** where it has a
  target: fuzzing the native copier. It named check-it and cl-quickcheck,
  and required an ADR to adopt either.
- **The oracles are bounded by the corpus.** M2b's witnesses compare the
  copier, the converter and the renderers with cmark over the corpus's 747
  examples (ADR-0018). A shape the corpus lacks is never compared.
- **chez-cmark-gfm,** which binds the same pin, relies on such oracles (its
  ADR-0010 and ADR-0012) and on mutation testing: every test is seen to
  fail. It has no property tests.

So M3 ran a spike (spec §6). Two contenders did the same work, under one
harness:
- **check-it,** through ocicl, with its random source and its shrinker;
- **`:own`,** in the test systems, with no dependency: a splitmix64 stream
  from an integer seed, and a shrinker in the style of delta debugging.

Both built the same three generators: syntax soup of up to 400 characters,
corpus splices of up to 20 lines, and octets for property 5. Five
properties ran on them (spec §6.3):
1. the HTML oracle;
2. the XML oracle, positions included;
3. the bounds: the output bounds and the table-cell bound;
4. clean outcomes;
5. UTF-8, the one pure property.

The spike's findings (spec §3, cited elsewhere as "M3 finding N"):
- **5. check-it replays a run only on the Lisp that made it.** It draws
  from `cl:random`, and a printed random state reads back only on the Lisp
  that printed it.
- **6, corrected by 8. Generated inputs rarely reach ADR-0014's two
  divergences,** since the generators almost never build footnotes. In
  seed 1's 10,000 cases, syntax soup built none. Across 1,000,000 cases,
  six differences were excused as `:excused-dropped`, and none as
  `:excused-repeat`.
- **7. cmark can report a negative column, and `parse` failed on it:** the
  real bug, below.
- **9. ADR-0014's list of divergences is incomplete.** Three more shapes
  have its two causes. No generated input reached them.
- **10. check-it's generator language can't express the generators.** Its
  characters stop at code 127, its list lengths are capped, and its `or`
  picks almost uniformly. So its contender draws integers through
  check-it, and builds the same generators from them. Only SBCL can seed
  check-it from an integer.

## Evidence

From the [benchmark](../2026-10-02-m3-benchmark.md), run in the Guix
container.

### Seven mutations, each alone

`make test`, without the properties, failed on all seven. Each contender
then ran properties 1 to 4, from seed 1, at the CI case counts below.

| # | Mutation | Properties that failed | First failing case, `:own` / check-it | Shrunk to, in characters, `:own` / check-it |
|---|----------|------------------------|---------------------------------------|---------------------------------------------|
| 1 | The HTML bound counts the parse's references (M2 finding 17 undone) | none | — | — |
| 2 | Strict UTF-8 decoding (M2 finding 19 undone) | all four, from syntax soup only | 1,062 / 71 | 9 / 12; the HTML oracle's, 37 / 19 |
| 3 | The copier copies a start position as the end | the XML oracle | 1 / 1 | 0 / 2 |
| 4 | The copier drops a list's delimiter | all four | 8 / 12 | 2 / 2 |
| 5 | The converter keeps `<p>` in tight list items | the HTML oracle | 7 / 2 | 3 / 3 |
| 6 | `plaintext-prefix-width` returns 0 | the bounds | 10 / 7 | 5 / 5 |
| 7 | The table-cell bound counts one row too few | none | — | — |

- **The suite caught all seven; the properties caught five,** the same
  five on both contenders. No mutation was caught by the properties alone.
- **Mutations 1 and 7 escaped both contenders.** Only property 3 reads
  either value, over 36,000 cases per generator.
  - Mutation 1 shows only with references inside a dropped footnote
    definition (M2 finding 17), and the generators rarely build footnotes.
  - Mutation 7 takes one line from a bound that already overcounts: it
    multiplies the widest dash run by every line of the run. Only a table
    within one line of its bound shows it. The crafted tests build one,
    exactly tight; the generators didn't, at the CI counts.

### The CI case counts

The benchmark chose one count per property from `:own`'s throughput, so
that properties 1 to 4 on SBCL and property 5 on CCL and ECL take about
30 s together:

| Property | Cases, from seed 1 |
|----------|--------------------|
| 1. The HTML oracle | 44,000 per generator |
| 2. The XML oracle | 46,000 per generator |
| 3. The bounds | 36,000 per generator |
| 4. Clean outcomes | 12,000 per generator |
| 5. UTF-8 | 60,000 on each Lisp |

They took 29.65 s with `:own` and 27.94 s with check-it. Property 5 on
SBCL, outside that budget, took 0.608 s more with `:own`.

### Unmutated runs

Every property, generator and contender ran 100,000 cases from a random
seed, and property 5 ran on each Lisp: 22 runs, 2.2 million cases, with M3
finding 7 already fixed. None failed, and none was excused.

### The real bug: M3 finding 7

- **The bug.** With tables and autolinks on, the table extension can
  rebuild a paragraph with no position, and cmark computes inline
  positions inside it from the missing origin. For `"a\nwww.g\nb\n|-"` it
  reports the link at `1:-1-1:4`, though the link is on line 2. M2's AST
  schema required non-negative positions, so `parse`, with its default
  options, signalled `invalid-ast-node` on valid input.
- **Found by property 2,** with `:own`, on corpus splices: from seed 1,
  first at case 26,425, and from other seeds too (Task 5's exploratory
  sweep). The full corpus never reached it, and neither did any existing
  test.
- **CI would have caught it.** Property 2's CI run includes seed 1's first
  46,000 corpus splices.
- **Fixed in step 7b.** The user decided that the AST accepts any integer
  in a position, as cmark reports it (ADR-0005). The wrong positions stay
  documented, not repaired. A native test pins the example, and a pure
  test pins negative positions.

### The contenders, by spec §6.6's criteria

| Criterion, in order | Result |
|---------------------|--------|
| 1. Mutations caught | A tie: five each, mutations 2 to 6 |
| 2. Shrunk size | `:own` ahead. Mutation 3: 0 characters to check-it's 2. Mutations 4 to 6: equal. Mutation 2: split, each contender shrinking its own failing case |
| 3. Replay on every Lisp | `:own` replays from its seed on SBCL, CCL and ECL, with the same cases on each (Task 3's recorded checksums). check-it replays from its seed only on SBCL; on CCL and ECL each run draws new cases (M3 finding 10) |
| 4. Dependencies and code | `:own`: none, and 204 lines (`random.lisp` 112, `shrink.lisp` 92). check-it: check-it, closer-mop and optima, plus a 328-line adapter; its generator language couldn't express the generators (M3 finding 10) |
| 5. Speed, at the CI counts | check-it, 27.94 s to 29.65 s. On properties 1 to 4 throughput was within about 10%: a round trip through cmark costs far more than drawing a case. On property 5 under CCL, check-it drew 73,260 cases/s to 29,940 |

## Decision

### Adopt property-based testing

Spec §6.6 adopts property testing when both of its conditions hold. Both
do, the first by its second half only:
- **A benchmark mutation the suite misses, or a real bug.**
  - No mutation qualifies: the suite caught all seven.
  - A real bug does: M3 finding 7, which the corpus and the suite missed.
- **About 30 s in CI, deterministic with a fixed seed, and replayable from
  a failure's report.** `:own` meets it: 29.65 s in the container; the same
  cases from seed 1 on SBCL, CCL and ECL; and a failure reports its seed
  and its shrunk input.

### With `:own`, our own generator and shrinker

**The contenders found the same bugs:** five mutations each, and nothing
on the unmutated code. That was no test of check-it as designed. Its
generator language couldn't express the generators (M3 finding 10), so its
contender ran our generator algorithms on check-it's random source, with
check-it's shrinker. The spike compared two random sources and two
shrinkers, not two ways of describing inputs.

**So `:own` doesn't find more bugs. It is as effective, and it fits the
project better.** The criteria decide in order (table above):
1. **Mutations caught** tie.
2. **Shrunk size** leans to `:own`, by mutation 3. Mutation 2 splits.
3. **Replay on every Lisp** settles it. CI runs property 5 on CCL and ECL,
   and check-it can't be seeded there, so each run would draw new cases,
   which the rule's second condition rules out.

Criteria 4 and 5 don't change the outcome:
- `:own` needs no dependency, and less code;
- check-it was faster on property 5: 2.4 times on CCL;
- check-it also shrinks octet values toward zero, where `:own` only
  removes octets.

### The suite

As spec §6.7 sets out:
- **The properties join the existing suites.** The native ones go to
  `/native-tests`, on SBCL in M3, and on SBCL, CCL and ECL from M4a, at
  the same counts from the same seed. CI runs them on SBCL in every run,
  and on CCL and ECL on `main` and on dispatch (ADR-0013). The harness,
  the generators, the shrinker and property 5 go to `/tests`, on all three
  Lisps.
- **One Parachute test per property and generator:** nine tests, each
  with one assertion over its summary. No assertion captures a generated
  input (`progress.md`'s global constraint).
  - **A run fails** when any case failed, or when no case passed, so a
    run that only hit the input guard can't pass. A native run also fails
    when the open counters aren't zero after it.
  - **A failure's report** names the property, the generator, the seed,
    the case number and its options; the shrunk input and its detail; and
    the original input's length and detail.
  - **Shrinking keeps to one kind of failure:** a smaller input counts
    only if it fails the same way: with the same condition type, or as a
    failure the property reports itself. So a shrink can't slide from a
    signalled bug to another kind of failure.
  - **Every run prints its seed and case counts** at the start, whether or
    not they are the defaults.
- **`CL_COMMONMARK_GFM_SEED` and `CL_COMMONMARK_GFM_CASES`** set the seed
  and the case count. By default the seed is 1 and the counts are the CI
  case counts above, so CI runs the same cases every time. `make
  check-purity` and `make check-native` pass `PROPERTY_SEED` and
  `PROPERTY_CASES` to them, since the Guix container drops the host's
  environment.
- **`make fuzz`** runs many more cases, `FUZZ_CASES` each, from
  `FUZZ_SEED`, which is random by default. On a failure, it prints the seed
  and the shrunk input.
- **A failure replays from its seed:** `make fuzz FUZZ_SEED=N
  FUZZ_CASES=M`, or `make check-native PROPERTY_SEED=N PROPERTY_CASES=M`,
  which runs the whole native suite with each native property at M
  cases.
- **Property 1 keeps spec §6.4's two excuses,** and counts them. Any other
  difference fails.

### Rejected

- **check-it.** It tied on mutations caught.
  - **In its favor:** it was 1.71 s faster at the CI counts, most of it on
    property 5 under CCL, and it shrinks octet values deeper.
  - **Against it:** its generator language couldn't express the generators
    (M3 finding 10), so it brought only a random source and a shrinker. It
    replays from a seed only on SBCL. And it needs check-it, closer-mop and
    optima, and a 328-line adapter, where `:own` needs no dependency and
    204 lines.
- **Not adopting.** The suite caught all seven mutations, and 2.2 million
  unmutated cases found no second bug, so the case for properties rests on
  one bug. But the rule counts one. M3 finding 7 made `parse` fail on valid
  input with its default options, and it lay outside the corpus. Property
  2's CI run reaches it, within about 30 s of CI for all five properties.
- **cl-quickcheck,** named by ADR-0007 beside check-it, wasn't evaluated:
  version 0.4 has no shrinker, and draws from `cl:random` as check-it does,
  so its seeds can't replay across Lisps either (M3 finding 5).

## Consequences

- **CI grows by about 30 s in the container:** 29.65 s for the budget, and
  0.608 s for property 5 on SBCL. GitHub's runner was 1.3 to 1.4 times
  slower than local runs for M2b's `make test` (`progress.md`), so about 39
  to 42 s there.
  - **Measured on PR #8:** `make -k test` took 213 s on GitHub, against
    M2b's 158 s. In its first run, the native suite grew from 34 s to
    71 s, and the pure suite from 101 s to 119 s, M3's other new tests
    included.
  - **So the properties take roughly 40 to 45 s there,** as projected.
- **CI is a regression guard.** A fixed seed gives it the same cases on
  every run, so it never fails by chance; M3 finding 7's case is among
  them. `make fuzz` explores new cases, and a failure there replays from
  the seed it prints.
- **The properties complement the crafted tests, and don't replace them.**
  Mutations 1 and 7 show crafted tests catching shapes the generators
  rarely build: a dropped footnote definition holding references, and a
  table exactly as tight as its bound.
- **The spike goes.** `:own`'s code moves into the suites. check-it's
  adapter is deleted (spec §6.6), and check-it, closer-mop and optima
  leave `ocicl.csv`. `:own` adds no dependency.
- **`progress.md` gains a global constraint:** CI runs the properties with
  a fixed seed (spec §6.7).
- **ADR-0007 is amended, not replaced.** Parachute stays; the properties
  are Parachute tests.
- **Follow-ups, outside M3:**
  - **A footnote-aware generator.** It would reach the inputs of M3
    finding 9, which property 1 reports as failures. It needs excuses for
    them, or fixes.
  - **The native properties on CCL and ECL,** with the native suite, in M4
    (spec §9). M4a takes this up: they run on CCL and ECL with the native
    suite, and CI runs them there on `main` and on dispatch. In the Guix
    container, at the CI counts from seed 1, the eight native property
    tests took 24 s on SBCL, 61 s on CCL and 198 s on ECL (M4 finding 5).
