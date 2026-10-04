# ADR-0009: Discover the pinned pair by absolute path

- **Status:** Accepted; amended 2026-10-02 by the
  [M3 spec](../2026-10-02-m3-extensions-versions-properties-design.md) §5
  and M3 findings 1 and 2: startup also checks `cmark_version()`'s number
  against the pin, `#x001D000D`; amended 2026-10-03 by the
  [M4 spec](../2026-10-03-m4-ccl-ecl-design.md) §5.3 and M4 findings 2, 3,
  12, 15 and 22: a CCL process keeps the first pair it loads, even one
  whose startup then fails, and refuses any other; on ECL, an override
  path holding a `*` is reported as not found; a saved CCL image reopens
  by soname any record of the pair that the save hook didn't forget
  (ADR-0017), and then records the pair it reopened
- **Date:** 2026-09-27
- **Scope:** native library discovery, loading, initialization
- **Spec:** [M0 close design](../2026-09-27-m0-close-design.md) §3.2
- **Related:** ADR-0002 (the pin), ADR-0004 (the Guix container sets the
  override), ADR-0008 (direct binding), ADR-0017 (the restore hook and
  CCL's pair record; CCL's forgetting)
- **Prior art:** chez-cmark-gfm ADR-0016

## Context

With no shim (ADR-0008), Lisp must find `libcmark-gfm` and
`libcmark-gfm-extensions` itself.

Loading by bare name (`dlopen("libcmark-gfm.so")`) lets the system loader
decide what that means. On Debian the unversioned name exists only with the
`-dev` packages. And picking the two libraries independently can load two
cores: the extensions library depends on the core itself, so the loader
may pull in a second core beside the one we chose (chez-cmark-gfm
ADR-0016). Nothing about that fails loudly.

## Decision

Load **the exact pinned pair, by absolute path.** Never by bare name.

`resolve-cmark-libraries` is a pure function. Its filesystem access
(directory listing, file existence) is passed in, so every branch is tested
against synthetic listings with no files on disk.

### 1. Override

If `*cmark-gfm-libraries*` is non-`nil`, use it. Otherwise, if
`CL_COMMONMARK_GFM_LIBS` is set, use that.

- The value is two absolute paths: `core:extensions` in the environment
  variable, a two-element list in the special variable.
- Both are used verbatim. Both must exist as regular files.
- **No fallback.** A wrong override signals `native-library-not-found`,
  naming the override and which path failed.
- An empty-but-set variable counts as set, so it is invalid.
- **On ECL, a path holding a `*` is reported as not found** (M4 finding
  12). ECL parses that path as a wildcard pathname, so `probe-file` finds
  no file there, though one exists, and nothing loads. That is a clear
  condition, so the library keeps no ECL branch for it. A test on ECL
  checks it (M4 spec §5.1).

### 2. Directory search

Otherwise, walk a fixed list. The first directory holding **both** pinned
filenames wins.

| OS | Directories, in order | Core / extensions filenames |
|----|-----------------------|-----------------------------|
| Linux | `/usr/lib/<multiarch>`, `/usr/lib64`, `/usr/lib`, `/usr/local/lib` | `libcmark-gfm.so.0.29.0.gfm.13` / `libcmark-gfm-extensions.so.0.29.0.gfm.13` |
| macOS | `/opt/homebrew/lib`, `/usr/local/lib` | `libcmark-gfm.0.29.0.gfm.13.dylib` / `libcmark-gfm-extensions.0.29.0.gfm.13.dylib` |

- `<multiarch>` is `x86_64-linux-gnu` or `aarch64-linux-gnu`.
- Only the versioned names match. On Debian, the unversioned symlinks come
  only with the `-dev` packages.
- A directory holding only one of the two is **skipped**, never paired with
  another directory. This closes the double-load hazard.
- Nothing found signals `native-library-not-found`, listing every directory
  searched and the override variable's name.

### 3. Load and verify

1. `cffi:load-foreign-library` the core, then the extensions, by absolute
   path.
2. `cmark_version_string()` must equal `"0.29.0.gfm.13"`, else signal
   `native-abi-mismatch` with both versions. Then `cmark_version()` must
   return the pin as a number, `#x001D000D`: one byte per component, not
   the header comment's layout (M3 finding 2). A mismatch also signals
   `native-abi-mismatch`, naming both versions and both numbers
   (M3 spec §5).
3. Register the core extensions.
4. Smoke parse: a table, a checked task item and a footnote under `:gfm`.
   They must classify to `:table`, `:task-item` and `:footnote-reference`,
   else signal `native-initialization-error`.

All of this runs **once per process, under a lock**, before the first
parse.

### CCL: one pair per process

CCL never unloads a library it has called into (M4 finding 2). After a
call into the core, closing leaves it mapped, even with
`ccl:close-shared-library :completely t`. And CFFI's CCL backend calls a
function by its name alone, ignoring which library it is in
(`src/cffi-openmcl.lisp`). So a later pair can run an earlier pair's code
(M4 finding 3). An override naming the core twice should fail when
startup registers the extensions, since their registration function isn't
in the core. On CCL, after an earlier startup, it starts up instead: the
earlier extensions library is still mapped, and the name resolves there.

So a CCL process keeps the first pair it loads (M4 spec §5.3):
- **The record.** Once both libraries have loaded, and before any call
  into them, startup records the pair's truenames, as native namestrings:
  the first time, as the process's pair; later, to compare.
- **A pair that loads stays the process's pair,** however its startup
  ends. The version check's first call pins the core (M4 finding 2), so a
  pair that loads and then fails, such as one of another version or the
  core named twice, is the process's pair from then on.
- **Another pair is refused.** A later startup whose pair has other
  truenames closes both, before any call into them, and signals
  `native-initialization-error`. Its datum is the refused pair's
  truenames. Its reason names the recorded pair, and says that CCL can't
  unload it and that another pair needs a new process.
- **An error while recording,** such as a truename that can't be read,
  also signals `native-initialization-error`, and leaves the record as it
  was.
- **The same pair starts again,** after a reset or a failed startup.
- **Load failures keep their own conditions.** A missing file, or one that
  isn't a library, fails before both have loaded, as before, and is never
  recorded.
- **A saved image starts with no record, unless CCL reopened the pair.**
  The restore hook clears the record with the published state. When CCL
  has already reopened the pair as the image starts, the hook records the
  files CCL reopened instead, so the image refuses another pair
  (ADR-0017). It can't when CCL reopened only one of the two, which
  leaves finding 3's hazard open there (M4 finding 22).

SBCL and ECL keep no record. They unload both libraries on close (M4
finding 4), so another pair loads cleanly.

### ECL without `:dffi`

Signal `dynamic-ffi-unavailable` before discovery. Static deployment links
cmark-gfm into the application; no shim is involved.

## Consequences

- Nothing but the two absolute paths we resolved is ever handed to the
  loader, except on CCL, where a saved image reopens by soname a record of
  the pair that other code still holds open, or, if the save hook was
  skipped, any record of it (ADR-0017). The plan's library-resolution
  order, including its CFFI conventional-name step, is replaced by this
  one.
- Users need only the runtime packages, never `-dev`.
- Only one filename per library matches, so there is no version choice to
  make within a directory.
- A library outside the listed directories (a Guix or Nix store, a custom
  prefix) is found only through the override.
- The version check runs after loading, on both paths. An override may
  name any file; the check still rejects a wrong version.
- **On CCL, a process has one pair.** Once a pair has loaded, even one
  whose startup failed, any other pair needs a new process. M5's
  documentation tells CCL users.
- `native-abi-mismatch` now means "runtime version ≠ pin".
- The Guix container sets `CL_COMMONMARK_GFM_LIBS` to its profile's two
  versioned paths. `LD_LIBRARY_PATH` stays there for ocicl's `libcrypto`
  only (ADR-0004, amended).
