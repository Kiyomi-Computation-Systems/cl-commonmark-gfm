# ADR-0009: Discover the pinned pair by absolute path

- **Status:** Accepted; amended 2026-10-02 by the
  [M3 spec](../2026-10-02-m3-extensions-versions-properties-design.md) §5
  and M3 findings 1 and 2: startup also checks `cmark_version()`'s number
  against the pin, `#x001D000D`
- **Date:** 2026-09-27
- **Scope:** native library discovery, loading, initialization
- **Spec:** [M0 close design](../2026-09-27-m0-close-design.md) §3.2
- **Related:** ADR-0002 (the pin), ADR-0004 (the Guix container sets the
  override), ADR-0008 (direct binding)
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

### ECL without `:dffi`

Signal `dynamic-ffi-unavailable` before discovery. Static deployment links
cmark-gfm into the application; no shim is involved.

## Consequences

- Nothing but the two absolute paths we resolved is ever handed to the
  loader. The plan's library-resolution order, including its CFFI
  conventional-name step, is replaced by this one.
- Users need only the runtime packages, never `-dev`.
- Only one filename per library matches, so there is no version choice to
  make within a directory.
- A library outside the listed directories (a Guix or Nix store, a custom
  prefix) is found only through the override.
- The version check runs after loading, on both paths. An override may
  name any file; the check still rejects a wrong version.
- `native-abi-mismatch` now means "runtime version ≠ pin".
- The Guix container sets `CL_COMMONMARK_GFM_LIBS` to its profile's two
  versioned paths. `LD_LIBRARY_PATH` stays there for ocicl's `libcrypto`
  only (ADR-0004, amended).
