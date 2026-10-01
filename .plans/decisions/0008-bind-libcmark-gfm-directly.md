# ADR-0008: Bind libcmark-gfm directly; no C shim for now

- **Status:** Accepted; amended 2026-10-01 (found in M2b's Task 5, and
  corrected in M2b's second review): the first ABI belief says render
  stress and GC-pressure cycles would expose a reordered allocator. They
  might not. Calling another slot as `free` is undefined behavior: cmark's
  `calloc` or `realloc` wrapper (`src/cmark.c`) gets the buffer and
  whatever a register holds. On SBCL 2.6.4 x86-64 both aborted the
  process at the first render, so the native suite dies there. Elsewhere,
  a reordering could leak silently
- **Date:** 2026-09-27
- **Scope:** native boundary, node classification, native lifetimes
- **Spec:** [M0 close design](../2026-09-27-m0-close-design.md) §3.1, §3.3,
  §3.4, §3.5
- **Supersedes:** plan decision #2 ("A narrow C shim is required …");
  ADR-0005's `cl_cmark_node_kind` decision. ADR-0005's findings stand.
- **Related:** ADR-0002 (the pin), ADR-0009 (how the libraries are found)
- **Prior art:** chez-cmark-gfm ADR-0015 (the same move, shim deleted) and
  chez-cmark-gfm ADR-0005 (the parser outlives rendering)

## Context

The plan put a small C shim between Lisp and cmark-gfm. It would register
and attach extensions, free render output, read table and task metadata,
classify nodes and probe the version.

A shim has to be compiled. That means a C compiler on every user's machine,
or prebuilt binaries per platform. The goal (spec §1) is a user with only a
system cmark-gfm package, a Lisp and ocicl.

cmark-gfm 0.29.0.gfm.13 has a public replacement for every shim job. One
thing is missing: a getter for an extension's name.

## Decision

`cl-commonmark-gfm/native` binds `libcmark-gfm` and
`libcmark-gfm-extensions` through CFFI. The project compiles no C.

### Each shim job, and what replaces it

| Shim job | Replacement |
|----------|-------------|
| Register core extensions | `cmark_gfm_core_extensions_ensure_registered`, once per process, under a lock |
| Attach the selected extensions | `cmark_find_syntax_extension(name)` + `cmark_parser_attach_syntax_extension` |
| Extension list for HTML rendering | `cmark_parser_get_syntax_extensions(parser)`; the parser outlives rendering |
| Free render output | the `free` slot of `cmark_get_default_mem_allocator()` |
| Classify nodes | pure Lisp over type code, extension identity and type string |
| Table and task metadata | `cmark_gfm_extensions_get_table_alignments`, `…_get_table_columns`, `…_get_table_row_is_header`, `…_get_tasklist_item_checked` |
| Version probe | `cmark_version_string()` |

### What we give up

There is no public getter for an extension's **name**. We only ever attach
the five core extensions, so we identify an extension node by comparing its
extension pointer with the five we cached. An `:extension` fallback node
therefore cannot occur under this pin. If one ever does, it keeps its type
string and records `:extension-name` as `nil`.

### Lifetimes

A Lisp `native-document` handle owns one `cmark_parser *` and its finished
root, together.

- **Parse:** `cmark_parser_new(options)`; attach the selected extensions;
  `cmark_parser_feed(bytes, length)` with the UTF-8 octet vector pinned for
  the call; `cmark_parser_finish` → root. A null root signals
  `native-parse-error`.
- **Render** only while the handle is alive:
  `cmark_render_html(root, options, cmark_parser_get_syntax_extensions(parser))`
  or `cmark_render_plaintext(root, options, width)`. The extension list
  belongs to the parser and is freed with it (chez-cmark-gfm ADR-0005), so
  the parser must outlive rendering.
- **Release:** `with-native-document` (`unwind-protect`) calls
  `cmark_node_free(root)`, then `cmark_parser_free(parser)`. Exactly once,
  on normal exit, on a condition, and on a non-local exit.
- **Counters:** the native layer counts live parsers, roots and buffers.
  Every native test suite asserts all three are zero when it ends. This is
  the leak check.

### Node classification

The shell reads three facts per node and passes them to a pure function:

1. `cmark_node_get_type(node)`, an integer;
2. which cached extension pointer (`table`, `strikethrough`, `autolink`,
   `tagfilter`, `tasklist`) equals `cmark_node_get_syntax_extension(node)`,
   or `nil`;
3. `cmark_node_get_type_string(node)`.

`(classify-node type-code extension type-string)` returns a kind:

- **No extension:** map the core type code. The codes are constants
  transcribed from `cmark-gfm.h`, both footnote kinds included. A check
  compares them with the header in the pinned submodule (ADR-0011), so
  drift fails a test.
- **`table`:** the type string picks `:table`, `:table-header`,
  `:table-row` or `:table-cell`.
- **`strikethrough`:** `:strikethrough`.
- **`tasklist` on a `CMARK_NODE_ITEM`:** `:task-item`.
- **Any other extension node:** `:extension`.
- **`custom_block` / `custom_inline`:** signal
  `unsupported-extension-node`.

The vocabulary (ADR-0005) is unchanged.

### Two ABI beliefs

A C compiler used to check these. Now we believe them, and test them.

1. **The allocator's `free` is its third function pointer.** We read it as
   `(cffi:mem-aref allocator :pointer 2)` and free every render buffer
   through it.
   - *The test* asserts the three slots are non-null and distinct.
   - *It catches* a null slot or a struct that shrank.
   - *It cannot catch* a reordering: three distinct non-null pointers stay
     that way in any order. The render stress tests and the GC-pressure
     parse/render cycles (ADR-0013) are what would expose one.
2. **The tasklist accessor's C `bool` is one byte.** Its return is
   declared `:uint8` and tested against zero, so we read only the defined
   byte.
   - *The test* is the vocabulary fixture, which has one checked and one
     unchecked task item.
   - *It catches* a read that cannot tell them apart (always true or always
     false).
   - *It cannot catch* a wrong width in general. It only shows that the
     byte we read differs between the two items on the machine running the
     test.

### When a shim would come back

When a need arises that no public entry point meets, or an ABI belief
fails. Either one is recorded in an ADR first.

## Consequences

- No C compiler is needed to use the library.
- The plan's shim sections, suggested C ABI and shim risk rows go.
- Classification is pure Lisp and fully unit-testable without cmark.
- The two ABI beliefs are new fragility. A cmark that inserts a member
  before `free` passes the slot test; the first render then calls the wrong
  function.
- Core type codes live in Lisp now. The header check is what keeps them
  honest.
- An `:extension` node's `:extension-name` is always `nil`. Under this pin
  no such node occurs.
