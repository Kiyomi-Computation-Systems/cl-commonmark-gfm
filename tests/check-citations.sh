#!/bin/sh
# Tests scripts/check-citations on small repositories built here, one per
# case. `make check-citations` runs this, then the check itself on the
# repository. Checks name themselves, and the exit status is non-zero if
# any failed.
#
# Every reference below is assembled from pieces at run time, as in
# "$adr-0013", so that this file holds none for the check to find.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
script=$root/scripts/check-citations

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

pass=0
fail=0

ok()    { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad()   { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }
check() { name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

out=$tmp/out
has()   { grep -Fq -- "$1" "$out"; }
line()  { grep -Fxq -- "$1" "$out"; }

adr=ADR
plans=.plans
section=$(printf '\302\247')
finding=find''ing
Finding=Find''ing
task=ta''sk
Task=Ta''sk
M=M

# A fresh repository holding one clean file, src/clean.lisp.
fresh() {
  repo=$tmp/repo
  rm -rf "$repo"
  mkdir -p "$repo/src"
  git init -q "$repo"
  printf ';;; Reads a node.\n' >"$repo/src/clean.lisp"
}

# Writes TEXT as FILE's only line, in the current repository.
put() { # FILE TEXT
  mkdir -p "$(dirname -- "$repo/$1")"
  printf '%s\n' "$2" >"$repo/$1"
}

# Runs the check on the current repository; its status lands in $status.
# CI sets no locale, and in the C locale `.` matches one byte, never a
# whole curly apostrophe, so the check runs in it here too.
run() {
  LC_ALL=C sh "$script" "$repo" >"$out" 2>&1
  status=$?
}

passes() { [ "$status" -eq 0 ] && has "check-citations: no references to the plans in"; }
refuses() { [ "$status" -eq 1 ] && has "$1" && has "check-citations: 1 reference to the plans"; }

# A clean repository passes, and says how many files it searched.
fresh
run
check "a clean repository passes" passes
check "the summary counts the files searched" \
  line "check-citations: no references to the plans in 1 file"

# Each pattern is refused, naming the file and line.
for text in \
  "(see $adr-0013)" \
  "read $plans/decisions/0002-pin.md" \
  "(${M}2 design ${section}8.2)" \
  "the plan's ${section}3 says so" \
  "(${finding} 9)" \
  "(${Finding}s 12 and 30)" \
  "(${M}2b plan, ${Task} 9b)" \
  "as the ${task} 3 brief says" \
  "(${M}4 design D3)" \
  "${M}3's ${finding} shows it" \
  "${M}5b close-out" \
  "(${M}2b review p4)" \
  "the ${M}1 slice" \
  "${M}3 milestone" \
  "${M}4 spec D3" \
  "design ${section}7.3)" \
  "${Task} 9" \
  "the plan’s ${section}3 says so" \
  "${M}3’s ${finding} shows it"
do
  fresh
  put tests/case.lisp ";;; $text"
  run
  check "refuses: $text" refuses "tests/case.lisp:1:"
done

# A reference anywhere else on a line is found too, and in any file type.
for file in Makefile scripts/tool ci/install.sh .github/workflows/ci.yml docs/page.md README.org \
            tests/fixtures/html/cases; do
  fresh
  put "$file" "x (${finding} 3) y"
  run
  check "refuses a reference in $file" refuses "$file:1:"
done

# What isn't a reference to the plans passes.
for text in \
  "as the Unicode Standard recommends (${section}3.9)" \
  "CommonMark spec example 1" \
  "the plan for each footnote" \
  "a design choice" \
  "HTML5 and M10 are not milestones" \
  "Bfinding 9" \
  "X${adr}-0013" \
  "a subtask 3" \
  "HM2 design" \
  "the CommonMark spec ${section}4.3"
do
  fresh
  put src/case.lisp ";;; $text"
  run
  check "passes: $text" passes
done

# Files where references belong are not searched.
for file in "$plans/progress.md" "$plans/decisions/0001-x.md" AGENTS.md CHANGELOG.md \
            LICENSE NOTICE; do
  fresh
  put "$file" "(see $adr-0013)"
  run
  check "skips $file" passes
done

# The Makefile's PIN_ADR line names the record check-pins reads, so it
# passes; any other line naming the plans in the Makefile is refused.
fresh
put Makefile "PIN_ADR := $plans/decisions/0002-pin-cmark-gfm-0.29.0.gfm.13.md"
run
check "passes the Makefile's PIN_ADR line" passes
fresh
put Makefile "OTHER := $plans/decisions/0002-pin-cmark-gfm-0.29.0.gfm.13.md"
run
check "refuses another Makefile line naming the plans" refuses "Makefile:1:"
fresh
put scripts/tool "PIN_ADR := $plans/decisions/0002-pin-cmark-gfm-0.29.0.gfm.13.md"
run
check "refuses a PIN_ADR line outside the Makefile" refuses "scripts/tool:1:"
fresh
put sub/Makefile "PIN_ADR := $plans/decisions/0002-pin-cmark-gfm-0.29.0.gfm.13.md"
run
check "refuses a PIN_ADR line in another Makefile" refuses "sub/Makefile:1:"
fresh
put Makefile "PIN_ADR := $plans/decisions/0002-pin.md  # (${finding} 9)"
run
check "refuses a PIN_ADR line holding more than the path" refuses "Makefile:1:"

# An ignored file is not searched; an untracked one is.
fresh
put .gitignore "build/"
put build/out.txt "(${finding} 9)"
run
check "skips an ignored file" passes
fresh
put notes.txt "(${finding} 9)"
run
check "searches an untracked file" refuses "notes.txt:1:"

# A binary file is not searched.
fresh
printf 'x\000(%s 9)\n' "$finding" >"$repo/src/data.bin"
run
check "skips a binary file" passes

# A file git tracks is searched and counted, as an untracked one is.
fresh
git -C "$repo" add src/clean.lisp
run
check "counts a tracked file" line "check-citations: no references to the plans in 1 file"
fresh
put src/tracked.lisp ";;; (${finding} 9)"
git -C "$repo" add src/tracked.lisp
run
check "searches a tracked file" refuses "src/tracked.lisp:1:"

# When git grep itself fails, the check fails and says so.
mkdir -p "$tmp/bin"
real_git=$(command -v git)
cat >"$tmp/bin/git" <<EOF
#!/bin/sh
for arg in "\$@"; do [ "\$arg" = grep ] && { echo "fatal: grep broke" >&2; exit 128; }; done
exec "$real_git" "\$@"
EOF
chmod +x "$tmp/bin/git"
fresh
PATH="$tmp/bin:$PATH" LC_ALL=C sh "$script" "$repo" >"$out" 2>&1
status=$?
check "fails when git grep fails" \
  sh -c '[ "$1" -eq 2 ] && grep -Fq "check-citations: git grep failed" "$2"' - "$status" "$out"

# Two references are counted and both are named.
fresh
put src/a.lisp ";;; (${finding} 1)"
put src/b.lisp ";;; (see $adr-0013)"
run
check "counts two references" \
  sh -c '[ "$1" -eq 1 ] && grep -Fq "check-citations: 2 references to the plans" "$2" &&
         grep -Fq "src/a.lisp:1:" "$2" && grep -Fq "src/b.lisp:1:" "$2"' - "$status" "$out"

# Outside a git repository, the check fails and says why.
mkdir -p "$tmp/plain"
GIT_CEILING_DIRECTORIES=$tmp LC_ALL=C sh "$script" "$tmp/plain" >"$out" 2>&1
status=$?
check "fails outside a git repository" \
  sh -c '[ "$1" -eq 2 ] && grep -Fq "check-citations: " "$2" && grep -Fq "not a git repository" "$2"' \
  - "$status" "$out"

# The repository's own check script and this file hold no reference.
fresh
cp "$script" "$repo/scripts-check-citations"
cp "$root/tests/check-citations.sh" "$repo/check-citations.sh"
run
check "the script and its test hold no reference" passes

printf 'check-citations tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
