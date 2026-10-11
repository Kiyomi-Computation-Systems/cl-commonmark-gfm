#!/bin/sh
# Passes when an archive of the working tree, as `git archive` makes it,
# holds exactly the files a user needs, and no file only developers use.
# GitHub's archive of a release tag is made the same way, and ocicl
# packages that archive, so .gitattributes' export-ignore lines decide what
# users install. `make check-package` runs this.
#
# The archive is of the working tree's tracked files, edits included: a
# copy of the index, updated from the tree, gives the tree object to
# archive, so the real index is never touched. Attributes come from the
# working tree's .gitattributes.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root" || exit 2

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# What a user needs: the library's sources and system file, its pages, and
# the files that say what it is and under which licenses it ships.
shipped='src docs cl-commonmark-gfm.asd README.org LICENSE NOTICE CHANGELOG.md'

index=$(git rev-parse --git-path index) || exit 2
cp "$index" "$tmp/index" || exit 2
export GIT_INDEX_FILE="$tmp/index"
git add -u || exit 2
tree=$(git write-tree) || exit 2

# shellcheck disable=SC2086 # $shipped is a list of paths
git ls-files -- $shipped | sort > "$tmp/expected" || exit 2
git archive --worktree-attributes "$tree" > "$tmp/archive.tar" || exit 2
tar -tf "$tmp/archive.tar" > "$tmp/listing" || exit 2
grep -v '/$' "$tmp/listing" | sort > "$tmp/actual"

# A directory holding no needed file, such as a submodule's, which the
# archive keeps as an empty directory, fails too.
status=0
for dir in $(grep '/$' "$tmp/listing"); do
  awk -v d="$dir" 'index($0, d) == 1 { found = 1 } END { exit !found }' "$tmp/expected" || {
    echo "package-contents: the archive holds a directory with no needed file: $dir" >&2
    status=1
  }
done

if diff "$tmp/expected" "$tmp/actual" > "$tmp/diff"; then
  [ "$status" = 0 ] || exit 1
  printf 'package-contents: %s files, as expected\n' "$(wc -l < "$tmp/actual" | tr -d ' ')"
  exit 0
fi
echo "package-contents: the archive differs from what users need" >&2
echo "('<' a needed file it lacks, '>' a file it should leave out):" >&2
grep '^[<>]' "$tmp/diff" >&2
exit 1
