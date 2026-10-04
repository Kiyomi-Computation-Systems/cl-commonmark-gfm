# AGENTS.md

## Project guidelines

### Architecture & portability

* Use the functional core / imperative shell pattern
* Follow the 12 Factor Apps philosophy
* Project is built in Common Lisp for SBCL, CCL and ECL, through CFFI
* Project should be portable across macos (darwin) and linux. No Windows.
* Project should be portable across amd64 and arm64
* **DO NOT** setup macos CI runners: linux only! macOS is verified by hand on
  the maintainer's laptop (ADR-0001)
* Use ocicl (https://github.com/ocicl/ocicl) for package management and distribution

### Dependencies

* cmark-gfm https://github.com/github/cmark-gfm, pinned to 0.29.0.gfm.13
  (ADR-0002)
* `NOTICE` reproduces cmark-gfm's `COPYING`; update it with the pin

### Guix development container

* **On a Guix host, run every build and test through `scripts/guix-env`**,
  e.g. `scripts/guix-env make check-vocabulary`. Batch commands with
  `scripts/guix-env sh -c 'make a && make b'`: each call takes seconds to
  start.
* Edit, commit and push on the host. The container has no git identity,
  agents or tokens (ADR-0004).
* First time: `scripts/guix-env make ocicl`. Verify with `make check-guix`.
* The container exports `CL_COMMONMARK_GFM_LIBS`: the two absolute paths the
  library loads cmark-gfm from (ADR-0009). Outside the container, discovery
  searches system directories.
* Never pass `ocicl` a terminal it can block on in scripts: redirect stdin
  from `/dev/null`.

### Layout, process & libraries

* Plans live in `/.plans`, decision records in `/.plans/decisions`
* `/.plans/progress.md` is the spine: milestone status, the global
  constraints that bind every task brief, manual macOS runs, and close-outs.
  Read it before starting slice work; record close-outs there.
* Add entries to `CHANGELOG.md` for each release
* `/docs` is for user facing documentation only.
* Documentation should be very concise, focused, to the point, ELI5 style.
* `Makefile` should have a `help` command which lists all of its commands

### Testing & mutation discipline

* Use TDD / test-driven development
* A test that passes whether the code is right or wrong is worse than no test.
* A test is not finished when it passes. It is finished when you have watched
  it fail.
* Prefer a check to a comment.
* **Do not** write tests that rely on reading code comments

## Closing ritual

We run this when we're done and ready to merge the PR.

**Important**: ALWAYS ask before running this.

1. Squash merge the PR.
2. Catch up local `main`.
3. Clean up branches. Delete the merged branch locally and on the remote.
4. Reflect.

## Lisp Conventions

### Naming

- Lowercase with hyphens: `user-count` not `userCount`
- Special variables: `*variable*`
- Constants: `+constant+`
- Predicates: `abstractp` (single word), `largest-planet-p` (multi-word)
- Functions: use `&optional` and `&key` (never both together); avoid `&aux`. Use `&allow-other-keys` only in wrappers that forward a `&rest` plist.

### Formatting

- Two-space indentation
- Max 100 columns
- Comments: `;;;;` file, `;;;` section, `;;` within code, `;` inline
- Comments and docstrings describe the code as it is. The docstrings of
  the symbols the `cl-commonmark-gfm` package exports are for its users;
  every other comment and docstring is for developers. Cite nothing in
  `/.plans` (ADRs, plans, design documents, findings, milestones) and no
  review labels, and tell no history: where a citation stood in for a
  reason, write the reason out.
- Spell C identifiers as cmark-gfm's source does. Give its paths in full
  (`vendor/cmark-gfm/src/inlines.c`), unless the file's header has already
  given that path in full or said what its paths are relative to.

### Flow Control

- `if` for two branches, `when`/`unless` for one, `cond` for many.
- Never use `progn` in an `if` clause — use `cond`, `when`, or `unless`.
- Factor complex conditions into predicate functions.
- `case`/`ecase` for numbers, characters, and symbols only; prefer `ecase`/`etypecase` over `case`/`typecase`.
- Never use `ccase` or `ctypecase` in server processes.

### Identity, Equality and Comparisons

**Prefer `eql` over `eq`** — never use `eq` on numbers or characters; `eq` is for performance-critical pointer identity only.

| Type | Case-sensitive | Case-insensitive |
|------|---------------|-----------------|
| Numbers | `=` | — |
| Characters | `char=` | `char-equal` |
| Strings | `string=` | `string-equal` |
| Symbols / objects | `eql` | — |

- Use `zerop` / `plusp` / `minusp` rather than `(= x 0)`.
- Floats: never exact comparison — use a threshold. Use `eql` only when `0` / `0.0` / `-0.0` identity matters.
- `search` on strings: `:test` receives **characters**, so use `char=` / `char-equal`, not `string=` / `string-equal` (functionally correct but slower in many implementations).

### CLOS Slot Order

`:accessor` → `:initarg` → `:initform` → `:type` → `:documentation`

### Packages

- Use `:import-from` over `:use`
- Hierarchical names: `project.module.submodule`

## Common Pitfalls

### SBCL double-float stringification

`(princ-to-string 40.7d0)` → `"40.7d0"` — includes the `d0` suffix. When building URLs or external API strings, coerce to single-float first: `(float val 0.0)`.
