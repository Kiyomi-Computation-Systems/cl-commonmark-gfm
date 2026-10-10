#!/bin/sh
# tests/install-docs.sh
#
# Follows docs/installing.md as a user would, in a fresh container, and
# passes when the library then loads and its first call gives the value
# the page shows. It starts its own container, so it runs on the host,
# with Docker, not through scripts/guix-env:
#
#   tests/install-docs.sh debian   # debian:trixie, with Debian's packages
#   tests/install-docs.sh source   # ubuntu:24.04, building cmark-gfm
#
# It runs the page's ```sh blocks, in order, under its heading "Debian and
# Ubuntu" (debian) or "Building cmark-gfm from source" (source), then
# under "The library, through ocicl", as a user who has sudo. Then, in the
# same directory, it evaluates the ```lisp block under that last heading,
# form by form, and compares the last form's value with the block's last
# ";; =>". A heading or block missing from the page fails the test.
#
# The page says to install SBCL from the system's packages, and ocicl as
# ocicl's README says. The test does both itself, before the page's
# blocks: SBCL with apt, and ocicl from ocicl's own apt repository, as its
# README gives it for Debian and Ubuntu.
#
# ocicl can't install cl-commonmark-gfm until the library is published. So
# unless STAND_IN=0, the test stands in for the page's one line `ocicl
# install cl-commonmark-gfm`: it unpacks the files a release ships, the
# working tree's tracked files less those .gitattributes leaves out of an
# archive, where ocicl puts a system, ocicl/cl-commonmark-gfm-0.0.0/, and
# writes the ocicl.csv row ocicl would. The files are made into an archive
# on the host, by `git stash create` and `git archive`, and passed in on
# stdin, so the container needs no git of its own, a page whose steps
# forget git can't pass, and the host keeps no copy of the archive.
# ocicl's runtime then fetches the library's dependencies at its first
# load, as it would after the real step.
#
# Environment:
#   STAND_IN=0       run the page's `ocicl install cl-commonmark-gfm`
#   PAGE=<path>      another copy of the page, relative to the repository
#                    (default docs/installing.md), to see the test fail
#   SKIP_CMARK=1     skip the page's cmark-gfm steps, to see the first
#                    call fail as the page says it would
set -eu

if [ "${1:-}" != --inside ]; then
  case "${1:-}" in
    debian) image=debian:trixie ;;
    source) image=ubuntu:24.04 ;;
    *) echo "usage: $0 debian|source" >&2; exit 2 ;;
  esac
  command -v docker >/dev/null 2>&1 || { echo "install-docs: docker not found" >&2; exit 2; }
  repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
  # The stand-in's files, on the container's stdin: a commit of the working
  # tree's tracked files, which `git stash create` makes without touching
  # the tree or any ref, or HEAD when nothing has changed.
  commit=$(git -C "$repo" stash create) || exit 2
  git -C "$repo" archive "${commit:-HEAD}" | docker run --rm -i \
    -e MODE="$1" -e STAND_IN="${STAND_IN:-1}" -e PAGE="${PAGE:-docs/installing.md}" \
    -e SKIP_CMARK="${SKIP_CMARK:-0}" \
    -v "$repo":/repo:ro "$image" sh /repo/tests/install-docs.sh --inside
  exit
fi

# Inside the container, as root.
export DEBIAN_FRONTEND=noninteractive
page=/repo/$PAGE
work=/tmp/install-docs
mkdir -p "$work"
# The stand-in's archive, read before anything else can read stdin.
cat > "$work/library.tar"
say() { printf '\n=== install-docs: %s\n' "$*"; }
fail() { printf '\ninstall-docs: FAILED: %s\n' "$*"; exit 1; }

[ -f "$page" ] || fail "no page at $PAGE"
. /etc/os-release
say "$PRETTY_NAME, mode $MODE, page $PAGE, stand-in $STAND_IN"

# The page's blocks run as written; a user answers apt's question, which
# a script can't, so apt is told to assume yes.
echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90install-docs

say "SBCL, and the tools the test itself needs: no git, which the page's
steps must install where they use it"
apt-get update -qq >/dev/null
apt-get install -qq --no-install-recommends sbcl sudo ca-certificates curl >/dev/null
sbcl --version

say "ocicl, from ocicl's apt repository, as its README says"
curl -fsSL https://ocicl.github.io/ocicl/deb-repo/ocicl-archive-keyring.gpg \
  > /usr/share/keyrings/ocicl-archive-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/ocicl-archive-keyring.asc] https://ocicl.github.io/ocicl/deb-repo stable main" \
  > /etc/apt/sources.list.d/ocicl.list
apt-get update -qq >/dev/null
apt-get install -qq ocicl >/dev/null
ocicl version </dev/null 2>/dev/null | grep -i 'ocicl version' || true

useradd -m -s /bin/bash user
echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user
chown user "$work"

# blocks HEADING LANGUAGE: the page's blocks fenced ```LANGUAGE under the
# "## HEADING" line, up to the next "## " line, each block's lines as
# written.
blocks() {
  awk -v heading="## $1" -v fence="\`\`\`$2" '
    /^## / { inside = ($0 == heading); next }
    inside && !in_block && $0 == fence { in_block = 1; next }
    in_block && /^```/ { in_block = 0; next }
    in_block { print }
  ' "$page"
}

# section HEADING: the section's sh blocks, as one script; fails the test
# when the heading or its blocks are missing.
section() {
  grep -qx "## $1" "$page" || fail "the page has no heading \"## $1\""
  script=$(blocks "$1" sh)
  [ -n "$script" ] || fail "\"## $1\" holds no \`\`\`sh block"
  printf '%s\n' "$script"
}

case "$MODE" in
  debian) cmark_heading="Debian and Ubuntu" ;;
  source) cmark_heading="Building cmark-gfm from source" ;;
esac
library_heading="The library, through ocicl"

section "$cmark_heading" > "$work/cmark.sh"
section "$library_heading" > "$work/library.sh"
blocks "$library_heading" lisp > "$work/first-call.lisp"
[ -s "$work/first-call.lisp" ] || fail "\"## $library_heading\" holds no \`\`\`lisp block"

if [ "$STAND_IN" != 0 ]; then
  [ -s "$work/library.tar" ] || fail "no stand-in archive on stdin"
  grep -qx 'ocicl install cl-commonmark-gfm' "$work/library.sh" \
    || fail "the page has no line \"ocicl install cl-commonmark-gfm\" to stand in for"
  # The working tree's tracked files, where ocicl puts a system, and the
  # row ocicl writes for it: name, image reference, .asd path under ocicl/.
  cat > "$work/stand-in.sh" <<'STANDIN'
mkdir -p ocicl/cl-commonmark-gfm-0.0.0
tar -xf /tmp/install-docs/library.tar -C ocicl/cl-commonmark-gfm-0.0.0
echo "cl-commonmark-gfm, ghcr.io/ocicl/cl-commonmark-gfm@sha256:0000000000000000000000000000000000000000000000000000000000000000, cl-commonmark-gfm-0.0.0/cl-commonmark-gfm.asd" >> ocicl.csv
echo "install-docs: stood in for ocicl install cl-commonmark-gfm"
STANDIN
  awk -v stand_in="$work/stand-in.sh" '
    $0 == "ocicl install cl-commonmark-gfm" { while ((getline line < stand_in) > 0) print line; next }
    { print }
  ' "$work/library.sh" > "$work/library-stand-in.sh"
  mv "$work/library-stand-in.sh" "$work/library.sh"
fi

# The first call: each form read after the one before it runs, in
# CL-USER, as typed at the REPL; the last value printed as make
# check-docs prints it, newlines as \n.
cat > "$work/run-first-call.lisp" <<'LISP'
(let ((*package* (find-package "CL-USER"))
      (last nil))
  (handler-case
      (with-open-file (in "/tmp/install-docs/first-call.lisp")
        (loop for form = (read in nil in)
              until (eq form in)
              do (setf last (eval form))))
    (error (condition)
      (format t "~&install-docs: the first call signalled ~(~A~): ~A~%"
              (symbol-name (type-of condition)) condition)
      (with-open-file (out "/tmp/install-docs/signalled.txt" :direction :output
                                                              :if-exists :supersede)
        (format out "~(~A~)" (symbol-name (type-of condition))))
      (uiop:quit 1)))
  (let ((printed (with-output-to-string (out)
                   (loop for char across (let ((*print-case* :downcase)) (prin1-to-string last))
                         do (if (char= char #\Newline)
                                (write-string "\\n" out)
                                (write-char char out))))))
    (format t "~&install-docs: the first call gave ~A~%" printed)
    (with-open-file (out "/tmp/install-docs/value.txt" :direction :output :if-exists :supersede)
      (write-string printed out))))
LISP
# The block's last ";; =>": its text, and any ";;" lines straight after.
awk '
  /;; =>/ { sub(/.*;; => ?/, ""); expected = $0; collecting = 1; next }
  collecting && /^[ \t]*;;/ { sub(/^[ \t]*;; ?/, ""); expected = expected " " $0; next }
  { collecting = 0 }
  END { print expected }
' "$work/first-call.lisp" > "$work/expected.txt"
[ -s "$work/expected.txt" ] || fail "the \`\`\`lisp block has no \";; =>\""
# The page's steps leave the shell in the project's directory, where the
# first call runs.
echo "pwd > $work/project-dir" >> "$work/library.sh"
chown -R user "$work"

if [ "${SKIP_CMARK:-0}" = 1 ]; then
  say "skipping \"$cmark_heading\", as SKIP_CMARK asks"
else
  say "the page's \"$cmark_heading\" steps"
  cat "$work/cmark.sh"
  runuser -u user -- bash -c "cd ~ && bash -e $work/cmark.sh" \
    || fail "a step under \"$cmark_heading\" failed"
fi

say "the page's \"$library_heading\" steps"
cat "$work/library.sh"
runuser -u user -- bash -c "cd ~ && bash -e $work/library.sh" \
  || fail "a step under \"$library_heading\" failed"

say "the first call, in $(cat "$work/project-dir")"
cat "$work/first-call.lisp"
runuser -u user -- bash -c "cd $(cat "$work/project-dir") && sbcl --non-interactive --load $work/run-first-call.lisp" \
  2>&1 | grep -v -e '^;' -e MPFR -e '^WARNING:$' || true

[ -f "$work/signalled.txt" ] && fail "the first call signalled $(cat "$work/signalled.txt")"
[ -f "$work/value.txt" ] || fail "the first call gave no value"
normalize() { tr -s ' \t\n' '   ' | sed 's/^ //; s/ $//'; }
got=$(normalize < "$work/value.txt")
want=$(normalize < "$work/expected.txt")
[ "$got" = "$want" ] || fail "the first call gave $got, where the page shows $want"
say "passed: the first call gave what the page shows"
