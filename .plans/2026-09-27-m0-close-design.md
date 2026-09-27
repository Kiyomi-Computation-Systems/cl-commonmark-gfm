# M0 close: native boundary, HTML tree contract, Linux CI — design

- **Date:** 2026-09-27
- **Status:** Approved 2026-09-27
- **Milestone:** closes M0 (design freeze)
- **Inputs:** [project plan](cl-commonmark-gfm.org), ADR-0001…0007, and
  chez-cmark-gfm's ADR-0005, 0011, 0012, 0015 and 0016 (prior art on this
  machine)

## 1. Goal

Freeze the three interfaces later milestones build on:

1. **The native boundary:** how Lisp finds, loads and calls cmark-gfm.
2. **The HTML tree contract:** the shape of every node, the raw-HTML and
   link policies, the public serializer, and how shapes are tested.
3. **Linux CI:** what runs, where, and on which toolchain.

Once this is approved and written into the plan and ADRs, M1 (pure core) and
M2 (SBCL slice) can start without reopening any of it.

**Success:** a user with only a system cmark-gfm package, a Lisp and ocicl can
load the library and either get working results or a named project
condition. Never a crash, an unresolved symbol, or a silent second core.

## 2. Decisions made while brainstorming

| # | Question | Decision |
|---|----------|----------|
| D1 | Keep the C shim? | **No. Bind libcmark-gfm directly.** Add a shim later only if a concrete need appears. |
| D2 | Library discovery | **The exact pinned pair, loaded by absolute path.** Override or fixed directory search; no bare-name `dlopen`. |
| D3 | How the tree is tested | **cmark's HTML is the oracle**, byte for byte, over the pinned spec corpus. |
| D4 | Raw-HTML policies | **`:omit` (default) and `:text` only.** No trusted mode. |
| D5 | CI toolchain | **One amd64 job in a `debian:trixie` container.** |
| D6 | Tree format | **LHTML shape (closure-html's convention), not SXML.** Attributes are always the second element. |
| D7 | Serializer | **Ship `html-tree->string` publicly.** It is the same serializer the oracle tests. |

Found while checking facts:

- **CCL 1.13 has no arm64 build** on any OS. Its releases are `darwinx86`,
  `linuxx86` and 32-bit `linuxarm`. ADR-0001 wrongly says CCL on arm64 is
  checked on the Mac. On Apple Silicon, CCL runs as x86_64 under Rosetta and
  needs an x86_64 cmark-gfm.
- **Debian trixie ships exactly the pin:** cmark-gfm 0.29.0.gfm.13-4, with
  SBCL 2.5.2 and ECL 24.5.10.
- **The repository is private.** CI minutes are billed, and the free arm64
  Linux runners are not available to it.

## 3. Native boundary

### 3.1 No shim

`cl-commonmark-gfm/native` binds `libcmark-gfm` and
`libcmark-gfm-extensions` through CFFI. The project compiles no C. This
reverses plan decision #2 and the shim sections of the plan. ADR-0005's
*findings* stand; its `cl_cmark_node_kind` decision is replaced by §3.4.

Every job the plan gave the shim has a public-API replacement in
0.29.0.gfm.13:

| Shim job | Replacement |
|----------|-------------|
| Register core extensions | `cmark_gfm_core_extensions_ensure_registered`, once per process, under a lock |
| Attach the selected extensions | `cmark_find_syntax_extension(name)` + `cmark_parser_attach_syntax_extension` |
| Extension list for HTML rendering | `cmark_parser_get_syntax_extensions(parser)`; the parser outlives rendering (§3.3) |
| Free render output | the `free` slot of `cmark_get_default_mem_allocator()` (§3.5) |
| Classify nodes | pure Lisp over the type code, extension identity and type string (§3.4) |
| Table and task metadata | `cmark_gfm_extensions_get_table_alignments`, `…_get_table_columns`, `…_get_table_row_is_header`, `…_get_tasklist_item_checked` |
| Version probe | `cmark_version_string()` |

**What we give up:** there is no public getter for an extension's *name*.
Only the five core extensions are ever attached, so every extension node is
identified by comparing pointers (§3.4). An `:extension` fallback node
therefore cannot occur under this pin. The fallback keeps the type string
and records `:extension-name` as `nil`.

**When a shim would come back:** a need no public entry point can meet, or
an ABI belief (§3.5) that fails. Either one is recorded in an ADR first.

### 3.2 Discovery

`resolve-cmark-libraries` is a pure function. Its filesystem access
(directory listing, file existence) is passed in as arguments, so every
branch is tested against synthetic listings with no files on disk.

**1. Override.** If `*cmark-gfm-libraries*` is non-`nil`, use it. Otherwise,
if `CL_COMMONMARK_GFM_LIBS` is set, use that.
- The value is two absolute paths: `core:extensions` in the environment
  variable, a two-element list in the special variable.
- Both are used verbatim, and both must exist as regular files.
- There is **no fallback**. A wrong override signals
  `native-library-not-found`, naming the override and which path failed.
- An empty-but-set variable counts as set, so it is invalid.

**2. Directory search.** Otherwise, walk a fixed candidate list. The first
directory holding **both** pinned filenames wins:

| OS | Directories, in order | Core / extensions filenames |
|----|-----------------------|-----------------------------|
| Linux | `/usr/lib/<multiarch>`, `/usr/lib64`, `/usr/lib`, `/usr/local/lib` | `libcmark-gfm.so.0.29.0.gfm.13` / `libcmark-gfm-extensions.so.0.29.0.gfm.13` |
| macOS | `/opt/homebrew/lib`, `/usr/local/lib` | `libcmark-gfm.0.29.0.gfm.13.dylib` / `libcmark-gfm-extensions.0.29.0.gfm.13.dylib` |

- `<multiarch>` is `x86_64-linux-gnu` or `aarch64-linux-gnu`.
- Only the versioned names match. On Debian, the unversioned symlinks come
  only with the `-dev` packages.
- A directory holding only one of the two is skipped, never paired with
  another directory. This closes the double-load hazard: the extensions
  library's own dependency on the core would otherwise pull a second core
  into the process.
- Nothing found signals `native-library-not-found`, listing every directory
  searched and the override variable's name.

**3. Load and verify.**
1. `cffi:load-foreign-library` the core, then the extensions, by absolute
   path.
2. `cmark_version_string()` must equal `"0.29.0.gfm.13"`, else signal
   `native-abi-mismatch` with both versions.
3. Register the core extensions.
4. Run a smoke parse: a table, a checked task item and a footnote under
   `:gfm`. It must classify to `:table`, `:task-item` and
   `:footnote-reference`, else signal `native-initialization-error`.

All of this runs once per process, under a lock, before the first parse.

**Guix container:** `scripts/guix-env-enter` sets `CL_COMMONMARK_GFM_LIBS` to
the profile's two versioned paths. `LD_LIBRARY_PATH` stays for ocicl's
`libcrypto` only. ADR-0004 is amended to say so.

**ECL without `:dffi`:** signal `dynamic-ffi-unavailable` before discovery,
as the plan says. Static deployment links cmark-gfm into the application;
no shim is involved.

### 3.3 Lifetimes

A Lisp `native-document` handle owns one `cmark_parser *` and its finished
root, together.

- **Parse:**
  1. `cmark_parser_new(options)`;
  2. attach the selected extensions;
  3. `cmark_parser_feed(bytes, length)` with the UTF-8 octet vector pinned
     for the call;
  4. `cmark_parser_finish` → root.

  A null root signals `native-parse-error`.
- **Render:** `cmark_render_html(root, options,
  cmark_parser_get_syntax_extensions(parser))`, or
  `cmark_render_plaintext(root, options, width)`, while the handle is alive.
- **Release:** `with-native-document` (`unwind-protect`) calls
  `cmark_node_free(root)`, then `cmark_parser_free(parser)`, exactly once, on
  normal exit, on a condition and on a non-local exit.
- **Counters:** the native layer counts live parsers, roots and buffers.
  Every native test suite asserts all three are zero when it ends. This is
  the leak check (§5.4).

### 3.4 Node classification

The shell reads three facts per node and hands them to a pure function:

1. `cmark_node_get_type(node)`, an integer;
2. which of the cached extension pointers (`table`, `strikethrough`,
   `autolink`, `tagfilter`, `tasklist`) equals
   `cmark_node_get_syntax_extension(node)`, or `nil`;
3. `cmark_node_get_type_string(node)`.

`classify-node (type-code extension type-string) → kind` rules:

- **No extension:** map the core type code to a kind. The core codes are
  constants transcribed from `cmark-gfm.h`, including both footnote kinds. A
  check compares them with the header in the pinned submodule (§4.5), so
  drift fails a test rather than a comment.
- **`table` extension:** the type string decides `:table`, `:table-header`,
  `:table-row` or `:table-cell`.
- **`strikethrough`:** `:strikethrough`.
- **`tasklist`, when the type code is `CMARK_NODE_ITEM`:** `:task-item`.
- **Any other extension node:** `:extension`.
- **`custom_block` / `custom_inline`:** signal `unsupported-extension-node`.

The vocabulary table in the plan (ADR-0005) is unchanged.

### 3.5 Two ABI beliefs

These replace checks a C compiler would have made. Each gets a test and an
ADR entry that says what the test cannot catch.

1. **The allocator's `free` is its third function pointer.** It is read as
   `(cffi:mem-aref allocator :pointer 2)`, and every render buffer is freed
   through it. A test asserts the three slots are non-null and distinct. That
   catches a null or shrunken struct, **not a reordering**. The render stress
   and GC-pressure cycles (§5.4) are what would expose a reordering.
2. **The tasklist accessor's C `bool` is one byte.** Its return is declared
   `:uint8` and tested against zero, so only the defined byte is read. The
   vocabulary fixture has both a checked and an unchecked item.

## 4. HTML tree contract

### 4.1 Why not SXML

The plan called this projection "SXML". A survey on 2026-09-27 found that
Common Lisp has no shared HTML-tree convention, and that SXML's `@` marker
does not survive the move from Scheme:

- **The package trap.** Scheme symbols are global. CL symbols belong to
  packages, so a bare `@` read in one package is not `eq` to one read in
  another, and the comparison fails silently. `cl-sxml`, the only SXML
  library in ocicl, interns `@` into the caller's package, and interns its
  comment nodes into whatever package is current at the time. It is
  GPL-licensed and documented as not working on ECL.
- **No consumer expects it.** The same fragment, in each library's own
  format:
  - closure-html (LHTML): `(:p ((:class "x")) "hi " (:a ((:href "u")) "l"))`;
  - xmls: structs with string names;
  - Spinneret: `(:p :class "x" …)`, and it rejects `:@` as an unknown tag;
  - cl-who and hsx: compile-time macros only, no runtime trees.
- **LHTML is the nearest thing to a convention.** Its attributes are always
  the second element, so every element destructures the same way. We use its
  shape.
- **Spinneret's format was rejected.** It would tie our contract to
  Spinneret's parsing and output, which re-indents content.
- **Serializing LHTML with closure-html was rejected.** closure-html prints
  HTML 4 style (`<P>`, `<BR>`) and cannot represent comments. We ship our own
  serializer instead (§4.5).

### 4.2 Tree shape

- **Element:** `(tag attrs &rest children)`.
  - `tag` is a keyword.
  - `attrs` is `nil` or a list of `(:name "value")` two-element lists, in the
    order cmark emits them.
  - Each child is a string (text) or an element.
- **Omitted raw HTML** is `(:*comment* nil " raw HTML omitted ")`, the same
  three-part form.
- **Document:** a list of top-level nodes. `:document-wrapper` (an element
  keyword, default `nil`) wraps them as `(wrapper nil …)`.
- **No source positions and no `data-*` metadata** beyond what cmark's own
  HTML emits. Source positions live in the AST.
- Text is unescaped Lisp strings. Escaping is the serializer's job.

### 4.3 Mapping

Each node takes the shape cmark 0.29.0.gfm.13's `html.c` and extension
renderers produce, under the options in effect. The oracle (§4.6) settles
every detail.

- **Links and images:** `href` and `src` values carry cmark's percent-encoding
  (houdini's `HREF_SAFE` set). The serializer then only entity-escapes them.
  An image's `alt` is the plain text of its children.
- **Task items:** `(:li nil (:input ((:type "checkbox") (:disabled ""))) " text")`,
  with `(:checked "")` before `(:disabled "")` when ticked. There is **no
  `task-list-item` class**; this corrects the plan.
- **Footnote references:**
  `(:sup ((:class "footnote-ref")) (:a ((:href "#fn-1") (:id "fnref-1") (:data-footnote-ref "")) "1"))`.
- **Footnote definitions** are collected at the end of the document:
  `(:section ((:class "footnotes") (:data-footnotes "")) (:ol nil (:li ((:id "fn-1")) … backref …)))`.
  Numbering, ids for repeated references, and the back-reference `aria-label`
  follow cmark exactly. They are computed in Lisp from the AST's labels, in
  order of first reference.
- **Tables:** `:thead` wraps the `:table-header` row and `:tbody` the others;
  the `align` attributes come from each cell's `:align`.
- **Tight lists** unwrap their paragraphs, as cmark does.

### 4.4 Options

`ast->html-tree` validates its options before converting anything. An
unknown key or value signals `invalid-render-option`.

| Option | Values (default first) | cmark equivalent (oracle) |
|--------|------------------------|---------------------------|
| `:raw-html` | `:omit`: `(:*comment* nil " raw HTML omitted ")` for each `html_inline`/`html_block`<br>`:text`: the literal as an ordinary string | `:omit` = default safe HTML; `:text` has none, so it gets direct tests |
| `:softbreak` | `:newline` → `"\n"`<br>`:space` → `" "`<br>`:br` → `(:br nil)` | default, `CMARK_OPT_NOBREAKS`, `CMARK_OPT_HARDBREAKS` |
| `:link-policy` (link `href` and image `src`) | `:safe`: blank the URL when it starts, case-insensitively, with `javascript:`, `vbscript:`, `file:` or `data:`, except `data:image/png`, `data:image/gif`, `data:image/jpeg` and `data:image/webp` (cmark's `_scan_dangerous_url`)<br>`:unsafe`: keep every URL | default; `CMARK_OPT_UNSAFE` for links only |
| `:document-wrapper` | `nil` or an element keyword | none |

There is **no trusted raw-HTML mode**. A caller who needs the markup reads
`:literal` from the AST's `:html-inline` / `:html-block` nodes.

### 4.5 Serializer: `html-tree->string`

A pure, public function from a tree (an element, or a list of nodes) to a
string.

- **cmark-exact on our trees.** Static tables of void elements and of where
  cmark places newlines make its output equal cmark's HTML (§4.6).
- **Always escapes.** Text and attribute values are entity-escaped (`&`, `<`,
  `>`, `"`) exactly as houdini's HTML escaper does. Nothing is emitted raw.
- **Validates what it is given.** These signal `invalid-html-tree`, naming
  the offending node:
  - a tag or attribute name not matching `[a-z][a-z0-9-]*`, so a keyword can
    never smuggle in markup (e.g. a name containing `onclick="…"`);
  - a non-string attribute value;
  - comment text containing `--`;
  - a malformed element.
- **Unknown but valid tags are allowed** and print inline, since custom
  elements are legitimate.
- **It does not sanitize URLs.** `:link-policy` applies inside
  `ast->html-tree`. A URL a user adds to the tree afterwards is escaped but
  not checked; the user docs say so.

### 4.6 The oracle

- For every example in the pinned corpus (`test/spec.txt`,
  `test/extensions.txt`, `test/regression.txt` and the other `test/*.txt`
  files), `(html-tree->string (ast->html-tree (parse md)))` must equal
  `(markdown->html md)` byte for byte, under each oracle-backed option in
  §4.4. The serializer under test is the public one.
- `:link-policy :unsafe` is compared with `CMARK_OPT_UNSAFE` output only on
  examples whose AST has no `:html-inline` or `:html-block` node. That option
  also emits raw HTML verbatim, which `:omit` deliberately does not.
- The oracle needs a real parse, so it arrives with the native layer:
  - M2 runs it for the node families M2 copies;
  - M3 runs it over the whole corpus.

  M1's pure tests use hand-built ASTs with the expected trees written out,
  and direct serializer tests, including every `invalid-html-tree` case.

### 4.7 Corpus source

`vendor/cmark-gfm` is a git submodule pinned to commit
`587a12bb54d95ac37241377e6ddc93ea0e45439b` (tag `0.29.0.gfm.13`). It is a
**development-only** dependency: nothing is built from it and nothing ships
from it. It supplies:
- the corpus files;
- `src/cmark-gfm.h`, for the core type-code and option-bit checks;
- `COPYING`, for a check that `NOTICE` reproduces it verbatim.

A `make check-pins` target fails if the submodule's commit differs from
ADR-0002.

## 5. Linux CI

### 5.1 Shape

- **One file, one job:** `.github/workflows/ci.yml`, running on
  `ubuntu-latest` (amd64) in `container: debian:trixie`.
- **Triggers:** `pull_request`, and `push` to `main`.
- **Limits:** `concurrency` cancels superseded runs on the same ref;
  `timeout-minutes: 20`.
- **The three Lisps run in sequence in one job**, since private-repo minutes
  are billed per job. Each runs even if an earlier one fails, and the job
  fails if any did.

### 5.2 Toolchain

| Tool | Source | Pin |
|------|--------|-----|
| SBCL 2.5.2, ECL 24.5.10 | Debian apt | the trixie release |
| cmark-gfm | apt: `libcmark-gfm0.29.0.gfm.13`, `libcmark-gfm-extensions0.29.0.gfm.13`, `cmark-gfm` (CLI) | exact version; **no `-dev` packages**, so discovery sees what a user sees |
| CCL 1.13 | `ccl-1.13-linuxx86.tar.gz` from the GitHub release | SHA-256 recorded in the repo |
| ocicl 2.9.0 | `ocicl_2.9.0-1_amd64.deb` from the GitHub release | SHA-256 recorded in the repo |
| Lisp dependencies | `ocicl install` from `ocicl.csv` | lockfile; `./ocicl/` cached on its hash |
| Corpus | `actions/checkout` with submodules | ADR-0002 commit |

### 5.3 Steps

Each step comes into use as its milestone arrives.

| Step | From |
|------|------|
| `make info`: Lisp versions, architecture, cmark-gfm version | now |
| `make check-help`; `sh tests/guix-env-launcher.sh` (dry run, needs no Guix) | now |
| `make check-vocabulary` against Debian's CLI | now |
| `make check-pins` | now |
| `make check-purity`: the pure suites on each Lisp with `CL_COMMONMARK_GFM_LIBS=/nonexistent:/nonexistent` must pass | M1 |
| The native suites on each Lisp, **with no override set**, so discovery searches `/usr/lib/x86_64-linux-gnu` | M2 |
| The corpus oracle (§4.6) | M2 (partial) / M3 (full) |

### 5.4 Left out on purpose

- **macOS, arm64 and Windows runners** (ADR-0001).
- **`make check-guix`**, which stays local (ADR-0004).
- **Valgrind and sanitizer gates.** We compile no C. None of the three Lisp
  runtimes is a good fit for Valgrind: their collectors use signals and
  memory protection. Native memory safety is checked by:
  - the live-handle counters (§3.3);
  - repeated parse/render cycles under GC pressure;
  - the render stress tests behind ABI belief 1.

  This is revisited in M2 if the counters prove too weak.

## 6. Corrections this design makes elsewhere

| Where | Change |
|-------|--------|
| ADR-0001 | CCL is amd64-only: Linux amd64 (CI), macOS amd64 (Intel or Rosetta, manual) |
| ADR-0004 | The container sets `CL_COMMONMARK_GFM_LIBS`; `LD_LIBRARY_PATH` is for ocicl only |
| ADR-0005 | "Decision" on `cl_cmark_node_kind` superseded by §3.4; findings stand |
| Plan | Remove the shim sections, suggested C ABI and shim risk rows; replace the library-resolution order with §3.2; rename SXML to "HTML tree" throughout (systems table: `cl-commonmark-gfm/html-tree`; API: `ast->html-tree`, `markdown->html-tree`, `html-tree->string`; M1; risks); mapping table per §4.3; policies per §4.4; tests and CI per §4.6–5; support matrix per ADR-0001's fix; decision log entries 14–19 |
| Plan conditions | `native-abi-mismatch` now means "runtime version ≠ pin"; add `invalid-html-tree` (§4.5); the others are unchanged |

New ADRs:

| ADR | Records |
|-----|---------|
| 0008 | Bind libcmark-gfm directly; no shim for now (§3.1, §3.5) |
| 0009 | Pinned pair, absolute-path discovery (§3.2) |
| 0010 | LHTML-shaped HTML tree, not SXML; public `html-tree->string` (§4.1, §4.2, §4.5) |
| 0011 | cmark's HTML is the tree's oracle; `vendor/cmark-gfm` submodule (§4.3, §4.6, §4.7) |
| 0012 | Raw-HTML `:omit`/`:text`, softbreak and link policies (§4.4) |
| 0013 | Linux CI in a Debian trixie container (§5) |

## 7. Out of scope

- Writing any library code: that starts in M1/M2.
- Adapters to other tree formats (SXML, Spinneret, xmls).
- Property-based testing (M3, ADR-0007).
- Supporting any cmark-gfm version but the pin.
