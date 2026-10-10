# Contributing to cl-commonmark-gfm

Thanks for wanting to improve this. A **small fix**, such as a typo, a
page's wording, or a bug with its test, needs only the gates below.
**Feature-sized work** should start as an issue, so we can agree on the
design before the code. Two things need a design conversation first:
- the safe defaults: raw HTML omitted and dangerous URLs blanked (see
  [Safety](docs/safety.md));
- the pure core: the AST, the HTML tree, and the native layer's
  decisions in `src/native-core/` never load CFFI, and `make
  check-purity` holds them to that.

## Setup

Clone with the cmark-gfm submodule. The tests need its sources and its
spec files; the library itself doesn't:

```sh
git clone --recurse-submodules https://github.com/Kiyomi-Computation-Systems/cl-commonmark-gfm
cd cl-commonmark-gfm
```

In a clone made without it, run `git submodule update --init`.

**On a Guix host,** run every build and test through `scripts/guix-env`.
It starts a pinned container that holds every tool the Makefile needs.
Run git on the host: the container has no git identity.

```sh
scripts/guix-env make ocicl    # once: builds the pinned ocicl
scripts/guix-env make deps     # installs the Lisp dependencies
scripts/guix-env make test
```

**On Debian 13, amd64,** install the toolchain CI uses, then run the
suite:

```sh
sudo sh ci/install-toolchain.sh
make deps
make test
```

The script installs SBCL, ECL, CCL 1.13, ocicl 2.9.0, and cmark-gfm
0.29.0.gfm.13 with its `cmark-gfm` command. Elsewhere, install the same
yourself, with git, make and tar. [Installing](docs/installing.md) says
how to get cmark-gfm. CCL has no build for arm64, so there, run `make
test LISPS="sbcl ecl"`. `make help` lists every target.

## The gates

A pull request's CI runs these, and must stay green. A first-time
contributor's run waits for a maintainer to approve it.
- `make test`:
  - the pure suite on SBCL, CCL and ECL;
  - the native suite on SBCL;
  - the HTML fixtures, against the `cmark-gfm` command;
  - the documentation checks: `check-site`, `check-reference` and
    `check-docs`;
  - `check-citations` and `check-package`, below;
  - the tests of the Makefile's tool checks and of its scripts.
- `make check-vocabulary`, `make check-pins`, `make check-notice` and
  `make check-help`.
- `sh tests/guix-env-launcher.sh`, which tests `scripts/guix-env` without
  Guix.

Three more steps are slow, so they run only on a push to `main`, or when
a maintainer runs CI by hand: the native suite on CCL and ECL, and `make
check-ecl-static`. If you touch `src/ffi.lisp`, `src/native/`, or how
the library starts cmark-gfm, run them yourself:

```sh
make check-native NATIVE_LISPS="ccl ecl"
sudo apt-get install libcmark-gfm-dev libcmark-gfm-extensions-dev
make check-ecl-static
```

`make check-ecl-static` links cmark-gfm's static archives, which only
those `-dev` packages ship. Install them after the native suites, as CI
does, so that the suites find only what a user's system holds. A
maintainer can also push your branch here and run CI on it, with `gh
workflow run ci.yml --ref <branch>`.

**Tests come with code.** A change in behaviour needs a test that fails
on the old code. A test is not finished when it passes. It is finished
when you have watched it fail: say in the pull request what change made
it fail.

**CI runs on Linux only.** macOS is tested by hand before each release.
`src/native-core/discovery.lisp` searches other directories on macOS,
for other file names, and CI can only catch a mistake in the Linux
branch. If you change it, run the gates on a Mac too.

## Conventions

- [Conventional Commits](https://www.conventionalcommits.org) for
  commits and pull request titles: `feat:`, `fix:`, `docs:`, `test:`,
  `refactor:`, `chore:`. Pull requests are squash-merged, so the title
  becomes the commit on `main`.
- The Lisp style, and the rules for comments and docstrings, are in
  [AGENTS.md](AGENTS.md). A comment says why, in its own words: `make
  check-citations` refuses references to the project's plans.
- The pages in `docs/` follow the rules in AGENTS.md too. `make
  check-docs` runs every Lisp example in them. After changing an export
  or its docstring, run `make reference`.
- A user-visible change gets an entry in [CHANGELOG.md](CHANGELOG.md),
  under the next release.
- A release ships only `src/`, `docs/`, the system file, README.org,
  LICENSE, NOTICE and CHANGELOG.md. Mark a new file only developers use
  `export-ignore` in `.gitattributes`. Once git tracks the file, `make
  check-package` checks it.

## How this repository is developed

For feature work, the house style is this, though a small fix needn't
follow it:
- **Designs before code.** A design is written and agreed in `/.plans`
  before the work starts. Each decision gets a numbered record in its
  `decisions` folder, which says why the code is the way it is.
- **Every test is watched to fail.** AGENTS.md has the discipline.
- **LLMs are used extensively** in planning and development, as the
  README says. AGENTS.md is written for people and agents alike.

## Security

Please don't open a public issue for a suspected vulnerability: see
[SECURITY.md](SECURITY.md).
