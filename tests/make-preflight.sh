#!/bin/sh
# Tests the Makefile's fail-fast tool checks (scripts/require-tools, wired
# into deps, check-vocabulary, check-fixtures, fixtures-html and run-suite)
# and the native runners' own library check (tests/run-native.lisp,
# tests/run-native-fuzz.lisp). `make check-preflight` runs this; it is
# mostly shell and fast, but case (h) below runs one real Lisp. Checks
# name themselves, and the exit status is non-zero if any failed.
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

nothing_started() { [ ! -s "$marker" ]; }

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
