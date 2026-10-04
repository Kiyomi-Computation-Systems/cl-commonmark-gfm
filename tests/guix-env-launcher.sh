#!/bin/sh
# Host-side tests for scripts/guix-env. Nothing here runs Guix: every case
# sets GUIX_ENV_DRY_RUN=1, under which the launcher prints `cd <cwd>` and
# then the guix command it would exec, one argument per line. `make
# check-guix` runs this before entering the container. Checks name
# themselves, and the exit status is non-zero if any failed.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
launcher=$root/scripts/guix-env
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0

ok()    { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad()   { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }
check() { name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
has()   { grep -Fxq -- "$1" "$tmp/out"; }
lacks() { ! grep -Fq -- "$1" "$tmp/out"; }
lines() { sed -n "$1" "$tmp/out" | tr '\n' '|'; }
tail_lines() { tail -n "$1" "$tmp/out" | tr '\n' '|'; }

# The fake HOME has a space and a non-ASCII letter in it, and holds the
# kinds of credential a developer's HOME does. The container must receive
# none of them.
home="$tmp/fake hôme"
mkdir -p "$home/.ssh" "$home/.config/gh"
: >"$home/.ssh/id_ed25519"
: >"$home/.gitconfig"

# run [VAR=value...] LAUNCHER [ARG...]
# Runs from $cwd in a scrubbed environment. stdout -> $tmp/out,
# stderr -> $tmp/err, exit -> $status.
cwd=$root
run() {
  status=999
  ( cd "$cwd" && env -i HOME="$home" PATH="$PATH" GUIX_ENV_DRY_RUN=1 \
      SSH_AUTH_SOCK="$home/ssh-agent.sock" "$@" ) >"$tmp/out" 2>"$tmp/err"
  status=$?
}

# T1: no arguments means an interactive bash, behind the pinned prefix.
run "$launcher"
check "T1 no-args exits 0" [ "$status" -eq 0 ]
check "T1 no-args runs from the repo root" [ "$(lines 1p)" = "cd $root|" ]
check "T1 pins guix via channels.scm" \
  [ "$(lines 2,8p)" = "guix|time-machine|-C|channels.scm|--|shell|-m|" ]
check "T1 uses manifest.scm" [ "$(lines 9p)" = "manifest.scm|" ]
check "T1 container flag" has --container
check "T1 network flag" has --network
check "T1 enters through guix-env-enter" \
  [ "$(tail_lines 4)" = "--|sh|scripts/guix-env-enter|bash|" ]

# T2: arguments pass through verbatim, spaces and dollars included.
run "$launcher" make "a b" '$HOME'
check "T2 args pass through verbatim" \
  [ "$(tail_lines 6)" = '--|sh|scripts/guix-env-enter|make|a b|$HOME|' ]

# T3: nothing from HOME, and no agent socket, enters the container.
for args in "make check-guix-inside" ""; do
  # shellcheck disable=SC2086
  run "$launcher" $args
  label=${args:-no-args}
  check "T3 [$label] no --share" lacks "--share"
  check "T3 [$label] no --expose" lacks "--expose"
  check "T3 [$label] nothing from HOME" lacks "$home"
  check "T3 [$label] no agent socket" lacks "SSH_AUTH_SOCK"
done

# T4: refuse to nest.
run GUIX_ENVIRONMENT=/gnu/store/fake-profile "$launcher" make info
check "T4 nested: exit 2" [ "$status" -eq 2 ]
check "T4 nested: names GUIX_ENVIRONMENT" grep -Fq "/gnu/store/fake-profile" "$tmp/err"
check "T4 nested: prints no command" [ ! -s "$tmp/out" ]

# T5: launched by relative path from a subdirectory, the container still
# gets the repo root.
cwd=$root/docs
run ../scripts/guix-env make info
cwd=$root
check "T5 subdirectory: exits 0" [ "$status" -eq 0 ]
check "T5 subdirectory: runs from the repo root" [ "$(lines 1p)" = "cd $root|" ]

# T6: the in-container entry refuses to run on the host, where it would
# point XDG dirs at .guix-env/ for the host's own tools.
( cd "$root" && env -i PATH="$PATH" sh scripts/guix-env-enter true ) \
  >"$tmp/out" 2>"$tmp/err"
status=$?
check "T6 enter on host: exit 2" [ "$status" -eq 2 ]

# T7: scripts/guix-env-enter's library resolution (ADR-0009), called
# directly (not through the launcher) so each case controls exactly what
# $GUIX_ENVIRONMENT/lib holds. A fake GUIX_ENVIRONMENT and a scratch cwd
# are both needed: the script mkdirs $PWD/.guix-env.
enter=$root/scripts/guix-env-enter
enter_env=$tmp/fake-guix-environment
enter_cwd=$tmp/enter-cwd

reset_enter_env() {
  rm -rf "$enter_env" "$enter_cwd"
  mkdir -p "$enter_env/lib" "$enter_cwd"
}

run_enter() {
  status=999
  ( cd "$enter_cwd" && env -i PATH="$PATH" GUIX_ENVIRONMENT="$enter_env" \
      sh "$enter" sh -c 'printf %s "$CL_COMMONMARK_GFM_LIBS"' ) \
    >"$tmp/out" 2>"$tmp/err"
  status=$?
}

# T7a: one core file and one extensions file resolve to their absolute
# paths, core first.
reset_enter_env
core=$enter_env/lib/libcmark-gfm.so.0.29.0.gfm.13
ext=$enter_env/lib/libcmark-gfm-extensions.so.0.29.0.gfm.13
: >"$core"
: >"$ext"
run_enter
check "T7a one core + one ext: exit 0" [ "$status" -eq 0 ]
check "T7a one core + one ext: CL_COMMONMARK_GFM_LIBS" \
  [ "$(cat "$tmp/out")" = "$core:$ext" ]

# T7b: two core matches refuse rather than guess, naming both in stderr.
reset_enter_env
core1=$enter_env/lib/libcmark-gfm.so.0.29.0.gfm.13
core2=$enter_env/lib/libcmark-gfm.so.0.30.0.gfm.1
ext=$enter_env/lib/libcmark-gfm-extensions.so.0.29.0.gfm.13
: >"$core1"
: >"$core2"
: >"$ext"
run_enter
check "T7b two core matches: exit 2" [ "$status" -eq 2 ]
check "T7b two core matches: names first" grep -Fq "$core1" "$tmp/err"
check "T7b two core matches: names second" grep -Fq "$core2" "$tmp/err"

# T7c: no extensions file refuses.
reset_enter_env
core=$enter_env/lib/libcmark-gfm.so.0.29.0.gfm.13
: >"$core"
run_enter
check "T7c no extensions file: exit 2" [ "$status" -eq 2 ]

# T8: GUIX_ENV_MANIFEST names another manifest (M4 design §6.4): the dry
# run uses it after -m, in place of manifest.scm, and the --preserve flag
# lets the variable itself through into the container, so
# scripts/guix-env-enter can read it too.
run GUIX_ENV_MANIFEST=manifest-ecl-nodffi.scm "$launcher" make check-ecl-nodffi-inside
check "T8 other manifest: exits 0" [ "$status" -eq 0 ]
check "T8 other manifest: names it after -m" \
  [ "$(lines 9p)" = "manifest-ecl-nodffi.scm|" ]
check "T8 other manifest: preserve flag lets GUIX_ENV_MANIFEST in" \
  has '--preserve=^(TERM|COLORTERM|LANG|GUIX_ENV_MANIFEST)$'

# T8b: set but empty is the same as unset (ADR-0004: "unset or empty,
# it's manifest.scm"), not an empty -m argument. Catches ":-" weakened to
# "-", which would leave an empty-but-set value alone instead of
# defaulting it.
run GUIX_ENV_MANIFEST= "$launcher" make info
check "T8b empty manifest: exits 0" [ "$status" -eq 0 ]
check "T8b empty manifest: uses manifest.scm" [ "$(lines 9p)" = "manifest.scm|" ]

# T9: a manifest that doesn't exist refuses before Guix starts -- and
# before the dry-run print, unlike every other case here.
run GUIX_ENV_MANIFEST=manifest-does-not-exist.scm "$launcher" make info
check "T9 missing manifest: exit 2" [ "$status" -eq 2 ]
check "T9 missing manifest: names it" grep -Fq "manifest-does-not-exist.scm" "$tmp/err"
check "T9 missing manifest: prints no command" [ ! -s "$tmp/out" ]

# T9b: a manifest name holding a / is refused outright, whether or not
# the file exists (ADR-0004: a file name at the repository root, never a
# path) -- a subdirectory, a leading ./, and an absolute path. The second
# and third name a file that really exists (manifest.scm itself, by
# relative and by absolute path), and every case must be refused for its
# /, not as a missing file. The assignment is quoted: the repository's
# path may hold a space, as the fake HOME above does.
for bad in sub/x.scm ./manifest.scm "$root/manifest.scm"; do
  run "GUIX_ENV_MANIFEST=$bad" "$launcher" make info
  check "T9b [$bad] exit 2" [ "$status" -eq 2 ]
  check "T9b [$bad] names it" grep -Fq "$bad" "$tmp/err"
  check "T9b [$bad] refused for its /" grep -Fq "holds a /" "$tmp/err"
  check "T9b [$bad] prints no command" [ ! -s "$tmp/out" ]
done

# T10: scripts/guix-env-enter's own fasl cache per manifest (finding 9),
# called directly as T7 is, so each case controls GUIX_ENV_MANIFEST
# exactly. Reuses T7's reset_enter_env/enter_env/enter_cwd, with one core
# and one extensions file so the script reaches its end.
run_enter_cache() {
  status=999
  ( cd "$enter_cwd" && env -i PATH="$PATH" GUIX_ENVIRONMENT="$enter_env" "$@" \
      sh "$enter" sh -c 'printf %s "$XDG_CACHE_HOME"' ) \
    >"$tmp/out" 2>"$tmp/err"
  status=$?
}

reset_enter_env
core=$enter_env/lib/libcmark-gfm.so.0.29.0.gfm.13
ext=$enter_env/lib/libcmark-gfm-extensions.so.0.29.0.gfm.13
: >"$core"
: >"$ext"

# T10a: with the variable set, the other manifest's own cache.
run_enter_cache GUIX_ENV_MANIFEST=manifest-ecl-nodffi.scm
check "T10a other manifest: exit 0" [ "$status" -eq 0 ]
check "T10a other manifest: its own cache" \
  [ "$(cat "$tmp/out")" = "$enter_cwd/.guix-env/cache-manifest-ecl-nodffi" ]

# T10b: without it, the shared cache, as before this manifest existed.
run_enter_cache
check "T10b no manifest: exit 0" [ "$status" -eq 0 ]
check "T10b no manifest: the shared cache" \
  [ "$(cat "$tmp/out")" = "$enter_cwd/.guix-env/cache" ]

# T10c: set but empty is the same as unset here too. Catches ":-"
# weakened to "-" in this script.
run_enter_cache GUIX_ENV_MANIFEST=
check "T10c empty manifest: exit 0" [ "$status" -eq 0 ]
check "T10c empty manifest: the shared cache" \
  [ "$(cat "$tmp/out")" = "$enter_cwd/.guix-env/cache" ]

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
