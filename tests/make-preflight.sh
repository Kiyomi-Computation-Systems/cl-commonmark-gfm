#!/bin/sh
# Tests the Makefile's fail-fast tool checks (scripts/require-tools, wired
# into deps, check-vocabulary, check-fixtures, fixtures-html, run-suite,
# check-ecl-static, and the site's check-site, site, reference,
# check-reference and check-docs), check-ecl-static's search for
# cmark-gfm's static archives, check-ecl-nodffi-inside's hint on a Guix
# host, and the native runners' own library check (tests/run-native.lisp,
# tests/run-native-fuzz.lisp). `make check-preflight` runs this; it is
# mostly shell and fast, but case (h) below runs one real Lisp. Checks name
# themselves, and the exit status is non-zero if any failed.
#
# make exits 2 whenever a recipe fails, whatever the recipe's own status.
# So a case that pins a recipe's exit status checks make's report of it,
# "[TARGET] Error 2" (RECIPE_FAILED_WITH), not make's own exit status.
#
# Isolation: every case but (h) runs make, by its absolute path, from the
# repository root, with PATH set to a fresh directory of stub executables
# only -- no real ocicl, cmark-gfm, sbcl, ccl, ecl or guix, unless a case
# adds one. The recipes need only shell builtins before require-tools or
# run-suite's own check fires. A stub, when run, appends its own name to a
# marker file and exits 0, so a case can tell whether any tool or Lisp
# ever actually started, not just whether make reported failure.
#
# Case (g), `make test`: test's own prerequisites run check-watchdog and
# check-preflight before check-purity. check-watchdog needs a real `sh`
# and coreutils the stub PATH doesn't have, and check-preflight is this
# very script -- running it here for real would recurse forever. `make -o
# check-watchdog -o check-preflight test` tells make to treat both as
# already up to date, so neither recipe runs at all, while check-purity
# (and its own require-tools call) still does. This doesn't touch
# MAKECMDGOALS: -o only marks the targets it names as not needing a
# rebuild, so GOAL still resolves to "test" throughout (confirmed by hand
# against a scratch Makefile before relying on it here).
#
# Case (h) is the one real run: it needs a real sbcl and the ocicl/
# dependencies already installed, so it only runs when both are present
# (otherwise it prints "skip"), and it uses the real PATH throughout, not
# a stub one, with CL_COMMONMARK_GFM_LIBS pointing at two files that don't
# exist.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
make_bin=$(command -v make) || { echo "make-preflight: no make on PATH" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

pass=0
fail=0

ok()    { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad()   { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }
skip()  { printf 'skip %s\n' "$1"; }
check() { name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

out=$tmp/out
has()   { grep -Fq -- "$1" "$out"; }
lacks() { ! grep -Fq -- "$1" "$out"; }
# The report-suite summary line ("check-native: 183 tests, ..."), not just
# any line mentioning the suite's name -- our own hint mentions it too.
lacks_tests_line() { ! grep -Eq 'check-native: [0-9]+ tests,' "$out"; }

marker=$tmp/started
bindir=$tmp/bin

fresh_case() {  # resets the marker and the stub directory for a new case
  : >"$marker"
  rm -rf "$bindir"
  mkdir -p "$bindir"
}

stub() {  # NAME...: a fake that records its own name and exits 0
  for name in "$@"; do
    cat >"$bindir/$name" <<STUB
#!/bin/sh
echo "$name" >>"$marker"
exit 0
STUB
    chmod +x "$bindir/$name"
  done
}

stub_printing() {  # NAME OUTPUT: a fake that records its name and prints OUTPUT
  cat >"$bindir/$1" <<STUB
#!/bin/sh
echo "$1" >>"$marker"
echo "$2"
exit 0
STUB
  chmod +x "$bindir/$1"
}

nothing_started() { [ ! -s "$marker" ]; }
only_started() { [ "$(cat "$marker")" = "$1" ]; }  # NAME: that stub alone, once

# recipe_failed_with TARGET STATUS: make reported TARGET's recipe failing
# with exit status STATUS. GNU make 4.4.1, the container's and Debian's,
# names the recipe's place, "*** [Makefile:N: TARGET] Error N" (its
# src/job.c, child_error); 3.81, macOS's /usr/bin/make, names the target
# alone, "*** [TARGET] Error N" (its job.c).
recipe_failed_with() { grep -Eq "\\[(Makefile:[0-9]+: )?$1\\] Error $2\$" "$out"; }

# The pinned cmark-gfm release, as the Makefile names it.
version=$(sed -n 's/^CMARK_GFM_VERSION := //p' "$root/Makefile")
[ -n "$version" ] || { echo "make-preflight: no CMARK_GFM_VERSION in the Makefile" >&2; exit 2; }

# first_holding_pair DIRECTORY...: prints the first of DIRECTORY... that
# holds both pinned shared libraries, as check-ecl-static's search looks
# for them, and fails when none does.
first_holding_pair() {
  for directory in "$@"; do
    if [ -f "$directory/libcmark-gfm.so.$version" ] \
       && [ -f "$directory/libcmark-gfm-extensions.so.$version" ]; then
      echo "$directory"
      return 0
    fi
  done
  return 1
}

# run_make MAKE-ARG...: runs make, by absolute path, from the repository
# root, with the stub-only PATH and (when guix_environment is non-empty)
# that GUIX_ENVIRONMENT. Both stdout and stderr land in $out; $status is
# make's own exit status.
guix_environment=
run_make() {
  status=999
  if [ -n "$guix_environment" ]; then
    ( cd "$root" && env -i PATH="$bindir" GUIX_ENVIRONMENT="$guix_environment" \
        "$make_bin" "$@" ) >"$out" 2>&1
  else
    ( cd "$root" && env -i PATH="$bindir" "$make_bin" "$@" ) >"$out" 2>&1
  fi
  status=$?
}

# (a) make deps, nothing on PATH: fails, naming ocicl, and -- with no guix
# either -- points at ci/install-toolchain.sh.
fresh_case
guix_environment=
run_make deps
check "a deps, nothing on PATH: exit 2" [ "$status" -eq 2 ]
check "a deps: names ocicl" has "ocicl"
check "a deps: points at ci/install-toolchain.sh" has "ci/install-toolchain.sh"

# (b) make deps, a stub guix on PATH, GUIX_ENVIRONMENT unset: the
# container hint, naming this same goal.
fresh_case
stub guix
guix_environment=
run_make deps
check "b deps+guix: exit 2" [ "$status" -eq 2 ]
check "b deps+guix: hints the container" has "scripts/guix-env make deps"

# (c) make check-purity, sbcl and ecl stubbed, no ccl: fails, naming ccl,
# and nothing starts -- not even the Lisps that were actually found.
fresh_case
stub sbcl ecl
guix_environment=
run_make check-purity
check "c check-purity: exit 2" [ "$status" -eq 2 ]
check "c check-purity: names ccl" has "ccl"
check "c check-purity: nothing started" nothing_started

# (d) make fuzz, only sbcl stubbed: NATIVE_LISPS defaults to sbcl alone,
# so fuzz-native's own requirement would be satisfied on its own.
# fuzz-purity's missing ccl/ecl must stop the whole target first, before
# fuzz-native gets a chance to start that otherwise-available sbcl.
fresh_case
stub sbcl
guix_environment=
run_make fuzz
check "d fuzz: exit 2" [ "$status" -eq 2 ]
check "d fuzz: nothing started" nothing_started

# (e) make check-fixtures, no cmark-gfm: fails, naming cmark-gfm.
fresh_case
guix_environment=
run_make check-fixtures
check "e check-fixtures: exit 2" [ "$status" -eq 2 ]
check "e check-fixtures: names cmark-gfm" has "cmark-gfm"

# (i) make check-purity LISPS=bogus: an unknown Lisp is the loop's to
# report, as before the preflight existed -- not a missing tool, and not
# require-tools' usage error from an empty list of tools.
fresh_case
guix_environment=
run_make check-purity LISPS=bogus
check "i unknown Lisp: exit 2 (make's, for the loop's exit 1)" [ "$status" -eq 2 ]
check "i unknown Lisp: reported as unknown" has "unknown Lisp 'bogus'"
check "i unknown Lisp: no missing-tool line" lacks "not found"
check "i unknown Lisp: no usage error" lacks "usage:"

# (f) a stub guix, but GUIX_ENVIRONMENT already set, as inside the
# container: scripts/guix-env refuses to nest, so the hint must be the
# install-toolchain one, never the container one.
fresh_case
stub guix
guix_environment=/somewhere
run_make deps
check "f nested guix: exit 2" [ "$status" -eq 2 ]
check "f nested guix: install hint" has "ci/install-toolchain.sh"
check "f nested guix: no container hint" lacks "scripts/guix-env"
guix_environment=

# (g) make test, every tool missing: the hint must name "test", the goal
# actually typed, never check-purity, its inner prerequisite (see header
# for why check-watchdog and check-preflight are skipped with -o).
fresh_case
stub guix
guix_environment=
run_make -o check-watchdog -o check-preflight test
check "g test: exit non-zero" [ "$status" -ne 0 ]
check "g test: hints make test, not check-purity" has "scripts/guix-env make test"
check "g test: nothing started" nothing_started

# (j) make check-ecl-static, no ecl on PATH: fails, naming ecl, before the
# recipe goes on. "ecl not found", since the goal's own name holds "ecl".
# uname is stubbed: with neither CMARK_GFM_ARCHIVE_DIR nor
# CL_COMMONMARK_GFM_LIBS set, it is the first command the recipe would run
# past the check, looking for the archives.
fresh_case
stub uname
guix_environment=
run_make check-ecl-static
check "j check-ecl-static, no ecl: its recipe exits 2" recipe_failed_with check-ecl-static 2
check "j check-ecl-static: names ecl" has "ecl not found"
check "j check-ecl-static: nothing started" nothing_started

# (k) make check-ecl-static, a stub ecl, CMARK_GFM_ARCHIVE_DIR an empty
# directory: fails, naming each missing archive and the Debian packages
# that ship them, before the build starts. rm and mkdir are stubbed: the
# recipe would run them next, emptying the build directory.
fresh_case
stub ecl rm mkdir
mkdir -p "$tmp/no-archives"
guix_environment=
run_make check-ecl-static CMARK_GFM_ARCHIVE_DIR="$tmp/no-archives"
check "k check-ecl-static, no archives: its recipe exits 2" recipe_failed_with check-ecl-static 2
check "k check-ecl-static: names libcmark-gfm-extensions.a" \
  has "$tmp/no-archives/libcmark-gfm-extensions.a not found"
check "k check-ecl-static: names libcmark-gfm.a" has "$tmp/no-archives/libcmark-gfm.a not found"
check "k check-ecl-static: names libcmark-gfm-dev" has "libcmark-gfm-dev"
check "k check-ecl-static: names libcmark-gfm-extensions-dev" has "libcmark-gfm-extensions-dev"
check "k check-ecl-static: nothing started" nothing_started

# (l) make check-ecl-static, a stub ecl, no CMARK_GFM_ARCHIVE_DIR, and
# CL_COMMONMARK_GFM_LIBS naming two files, in two directories: the archives
# are looked for beside the first, the core, as in the containers. make
# passes a command-line variable to the recipe's environment. uname is
# stubbed too: the search of the system's directories would run it.
fresh_case
stub ecl rm mkdir uname
guix_environment=
run_make check-ecl-static \
  CL_COMMONMARK_GFM_LIBS="$tmp/core/libcmark-gfm.so.X:$tmp/extensions/libcmark-gfm-extensions.so.X"
check "l check-ecl-static, CL_COMMONMARK_GFM_LIBS: its recipe exits 2" \
  recipe_failed_with check-ecl-static 2
check "l check-ecl-static: looks beside the core" \
  has "$tmp/core/libcmark-gfm-extensions.a not found"
check "l check-ecl-static: nowhere else" lacks "$tmp/extensions/"
check "l check-ecl-static: nothing started" nothing_started

# (m) make check-ecl-static, a stub ecl, neither variable set, on a machine
# ADR-0009 names no multiarch directory for (uname -m says riscv64): the
# search covers discovery's other Linux directories, finds no pair, and
# says so, saying the search is Linux's. Only uname starts. Skipped where
# one of those directories really holds the pair.
if found=$(first_holding_pair /usr/lib64 /usr/lib /usr/local/lib); then
  skip "m check-ecl-static, no multiarch directory: $found holds the pinned pair here"
else
  fresh_case
  stub ecl rm mkdir
  stub_printing uname riscv64
  guix_environment=
  run_make check-ecl-static
  check "m check-ecl-static, no multiarch directory: its recipe exits 2" \
    recipe_failed_with check-ecl-static 2
  check "m check-ecl-static: no directory holds both" \
    has "make check-ecl-static: no directory holds both pinned cmark-gfm libraries."
  check "m check-ecl-static: names the directories searched" \
    has "Searched discovery's Linux directories: /usr/lib64 /usr/lib /usr/local/lib."
  check "m check-ecl-static: CMARK_GFM_ARCHIVE_DIR elsewhere" \
    has "Elsewhere than Linux, such as on macOS, it must be set."
  check "m check-ecl-static: looks for no archive" lacks "not found"
  check "m check-ecl-static: only uname started" only_started uname
fi

# (n) the same, on a machine whose multiarch directory ADR-0009 names
# (uname -m says aarch64): searched first, and named first. Skipped where
# one of the directories really holds the pair.
if found=$(first_holding_pair /usr/lib/aarch64-linux-gnu /usr/lib64 /usr/lib /usr/local/lib); then
  skip "n check-ecl-static, aarch64: $found holds the pinned pair here"
else
  fresh_case
  stub ecl rm mkdir
  stub_printing uname aarch64
  guix_environment=
  run_make check-ecl-static
  check "n check-ecl-static, aarch64: its recipe exits 2" recipe_failed_with check-ecl-static 2
  searched="/usr/lib/aarch64-linux-gnu /usr/lib64 /usr/lib /usr/local/lib"
  check "n check-ecl-static: the multiarch directory first" \
    has "Searched discovery's Linux directories: $searched."
  check "n check-ecl-static: only uname started" only_started uname
fi

# (o) make check-ecl-nodffi-inside on a Guix host, outside any Guix
# environment (a stub guix, GUIX_ENVIRONMENT unset): it points at make
# check-ecl-nodffi, which starts the container it runs in, before anything
# starts. ecl is stubbed, so a recipe going on would leave its mark.
fresh_case
stub guix ecl
guix_environment=
run_make check-ecl-nodffi-inside
check "o check-ecl-nodffi-inside, Guix host: its recipe exits 2" \
  recipe_failed_with check-ecl-nodffi-inside 2
check "o check-ecl-nodffi-inside: points at make check-ecl-nodffi" \
  has "run 'make check-ecl-nodffi', which starts it"
check "o check-ecl-nodffi-inside: nothing started" nothing_started

# (p) the same inside a Guix environment (GUIX_ENVIRONMENT set), as in the
# container: no hint, and the guard runs ecl.
fresh_case
stub guix ecl
guix_environment=/somewhere
run_make check-ecl-nodffi-inside
check "p check-ecl-nodffi-inside, nested: no hint" lacks "run 'make check-ecl-nodffi'"
check "p check-ecl-nodffi-inside: the guard ran ecl" only_started ecl
guix_environment=

# (q) make check-site, no sbcl on PATH: fails, naming sbcl, before the
# recipe goes on. Exit status 2, not the shell's 127 for a missing sbcl,
# shows require-tools ran: no stub runs before sbcl in any of the five
# recipes, so a stub's marker couldn't show that require-tools ran, and no
# "nothing started" check is made of it.
fresh_case
guix_environment=
run_make check-site
check "q check-site, no sbcl: its recipe exits 2" recipe_failed_with check-site 2
check "q check-site: names sbcl" has "sbcl not found"

# (r) make site, no sbcl on PATH: the same, for the renderer.
fresh_case
guix_environment=
run_make site
check "r site, no sbcl: its recipe exits 2" recipe_failed_with site 2
check "r site: names sbcl" has "sbcl not found"

# (s) make reference, no sbcl on PATH: the same, for the reference writer.
fresh_case
guix_environment=
run_make reference
check "s reference, no sbcl: its recipe exits 2" recipe_failed_with reference 2
check "s reference: names sbcl" has "sbcl not found"

# (t) make check-reference, no sbcl on PATH: the same, for the reference
# check.
fresh_case
guix_environment=
run_make check-reference
check "t check-reference, no sbcl: its recipe exits 2" recipe_failed_with check-reference 2
check "t check-reference: names sbcl" has "sbcl not found"

# (u) make check-docs, no sbcl on PATH: the same, for the examples check.
fresh_case
guix_environment=
run_make check-docs
check "u check-docs, no sbcl: its recipe exits 2" recipe_failed_with check-docs 2
check "u check-docs: names sbcl" has "sbcl not found"

# (v) make check-site and make site, a stub sbcl, no git: both need git as
# well as sbcl, so with sbcl present, only git's absence stops them, before
# either goes on to run it.
fresh_case
stub sbcl
guix_environment=
run_make check-site
check "v check-site, no git: its recipe exits 2" recipe_failed_with check-site 2
check "v check-site: names git" has "git not found"
check "v check-site: nothing started" nothing_started

fresh_case
stub sbcl
guix_environment=
run_make site
check "v site, no git: its recipe exits 2" recipe_failed_with site 2
check "v site: names git" has "git not found"
check "v site: nothing started" nothing_started

# (h) the native library check: only with a real sbcl and ocicl/'s
# dependencies in place, since it runs make for real, on the real PATH,
# with CL_COMMONMARK_GFM_LIBS pointing at two files that don't exist.
# Expects RESOLVE-CMARK-LIBRARIES' own failure to stop the suite before a
# single test runs.
if command -v sbcl >/dev/null 2>&1 \
   && [ -d "$root/ocicl" ] && [ -n "$(ls -A "$root/ocicl" 2>/dev/null)" ]; then
  bogus1=$tmp/no-such-core.so
  bogus2=$tmp/no-such-extensions.so
  status=999
  ( cd "$root" && CL_COMMONMARK_GFM_LIBS="$bogus1:$bogus2" \
      "$make_bin" check-native NATIVE_LISPS=sbcl ) >"$out" 2>&1
  status=$?
  check "h native library check: non-zero exit" [ "$status" -ne 0 ]
  check "h native library check: names check-native" has "check-native"
  check "h native library check: hints CL_COMMONMARK_GFM_LIBS" has "CL_COMMONMARK_GFM_LIBS"
  check "h native library check: no test ran" lacks_tests_line
else
  skip "h native library check: needs a real sbcl and ocicl/'s dependencies"
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
