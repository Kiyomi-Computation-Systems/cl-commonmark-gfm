# Support

The library runs on SBCL, CCL and ECL, on Linux and macOS, with
cmark-gfm 0.29.0.gfm.13 alone: see [Installing](installing.md). Windows
isn't supported.

## Systems and Lisps

Each cell says how that system and Lisp are tested:

| | SBCL | CCL | ECL |
|---|---|---|---|
| Linux, amd64 | CI | CI | CI |
| Linux, arm64 | Untested | No | Untested |
| macOS, Apple silicon | By hand | Untested | By hand |
| macOS, Intel | Untested | Untested | Untested |

- **CI:** the tests run automatically on Linux amd64, in Debian 13, with
  its own cmark-gfm packages.
- **By hand:** before each release, the tests are run by hand on a Mac
  with Apple silicon, with Homebrew's cmark-gfm.
- **Untested:** supported, but no test runs there yet. On Apple silicon,
  CCL runs under Rosetta: see
  [CCL on Apple silicon](installing.md#ccl-on-apple-silicon).
- **No:** not supported. CCL has no build for arm64.

In the table, ECL means an ECL with dynamic FFI. An ECL program with
cmark-gfm linked in is tested on Linux amd64 alone: see [ECL](ecl.md).

## Versions

The versions tested, on Linux amd64, are SBCL 2.5.2 and 2.6.4, CCL 1.13
and ECL 24.5.10. On macOS, they are SBCL 2.6.5 and ECL 26.5.5.
