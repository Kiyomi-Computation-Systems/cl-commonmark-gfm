# ADR-0007: Parachute for tests; property-based testing evaluated in M3

- **Status:** Accepted; amended by ADR-0020 (2026-10-02): property tests
  join the suites, with a seeded generator and shrinker of our own, not
  check-it or cl-quickcheck
- **Date:** 2026-09-27
- **Scope:** test framework, CI reporting

## Context

The test framework must:
- behave the same on SBCL, CCL and ECL;
- give CI a clean exit code and quiet output;
- test "signals this condition" (the plan defines eight conditions);
- rebind globals such as `*native-library-pathname*` per test;
- keep the dependency tree small and free of CFFI, because the pure suites
  must load with no C library.

On 2026-09-27 each candidate was installed through ocicl in the Guix
container and loaded on SBCL 2.6.4, ECL 24.5.10 and CCL 1.13:

| Framework | Loads on all three | Transitive deps | ocicl snapshot |
|-----------|--------------------|-----------------|----------------|
| FiveAM | yes | 4 | 2024-09 |
| Parachute | yes | 5 | 2026-08 |
| Rove | yes | 24 | 2026-08 |
| Try | yes | 13 | 2026-07 |
| 1am | yes | 1 | 2024-05 |
| Fiasco | yes | 3 | 2024-05 |
| clunit2 | yes | 1 | 2023-09 |
| lisp-unit2 | no: ocicl's package lacks `flexi-streams` for `cl-unicode/build` | — | 2024-05 |

## Decision

- **Use Parachute.** It meets every requirement above:
  - swappable reporters, including a quiet one;
  - `fail` for expected conditions;
  - fixtures that save and restore global state;
  - time limits and skips.

  It has 5 dependencies and was updated in 2026.
- Each suite runs with the quiet reporter and the result becomes the
  process's exit status, so `make` and CI need no output parsing.
- The pure and native suites are separate systems, so the pure one can be
  loaded with no C library.
- **Property-based testing is deferred to M3**, where it has a target: fuzzing
  the native copier. check-it (generators with shrinking) and cl-quickcheck
  both load on all three Lisps through ocicl. Adopting either needs its own
  ADR.

## Consequences

- Parachute enters `ocicl.csv` with the first test system in M1.
- FiveAM was the familiar alternative. If a FiveAM suite is ever imported,
  Parachute's `parachute-fiveam` compatibility layer can run it.
