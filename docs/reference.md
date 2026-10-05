# API reference

This page lists every exported symbol, from its docstring.

## Rendering and parsing

### `markdown->html`

Function

`(markdown->html markdown &rest options)`

Render `markdown`, a string, to HTML with cmark-gfm's own HTML renderer, and return the result as a string.

`options` is a plist. When a key repeats, the leftmost value wins, but every value must be valid.

- `:profile`: `:gfm`, the default, or `:commonmark`. A profile only supplies the defaults of `:extensions` and `:footnotes`.
- `:extensions`: the syntax extensions to attach, a list of distinct keywords from `:table`, `:strikethrough`, `:autolink`, `:tagfilter` and `:tasklist`, in any order. Defaults to all five under `:gfm`, and to none under `:commonmark`.
- `:footnotes`: `t` or `nil`. Defaults to `t` under `:gfm`, and to `nil` under `:commonmark`.
- `:smart`: `nil`, the default, or `t` for curly quotes, dashes and ellipses.
- `:sourcepos`: `nil`, the default, or `t` to add each element's position as a data-sourcepos attribute.
- `:softbreak`: `:newline`, the default, writes a newline; `:space` writes a space; `:br` writes `"<br />"` then a newline.
- `:unsafe-html`: `nil`, the default, writes a comment in place of raw HTML (`"<!-- raw HTML omitted -->"`) and blanks dangerous URLs; `t` keeps both, as cmark-gfm's own `CMARK_OPT_UNSAFE` does, though `:tagfilter`, when attached (the `:gfm` default), still escapes a few tags, such as `"<script>"`.

Signals a `type-error` when `markdown` isn't a string; `invalid-parse-option` for a bad `:profile`, `:extensions`, `:footnotes`, `:smart` or `:sourcepos` value; and `invalid-render-option` for everything else -- an odd-length option list, an unknown key, or a bad `:softbreak` or `:unsafe-html` value -- before cmark-gfm runs.

Signals `resource-limit-exceeded` for input past `*max-input-octets*` or `*max-nodes*`, or output that could pass `*max-output-octets*`; `unsupported-input` for input cmark-gfm can't parse safely; and a `native-error` when cmark-gfm fails to load or to run. `*cmark-gfm-libraries*` says where it is loaded from.

### `markdown->html-tree`

Function

`(markdown->html-tree markdown &rest options)`

Render `markdown`, a string, into an HTML tree: `(ast->html-tree (parse markdown ...) ...)`, without building a detached AST the caller keeps.

`options` is a plist. When a key repeats, the leftmost value wins, but every value must be valid.

- `:profile`, `:extensions`, `:footnotes` and `:smart`: as `parse`.
- `:softbreak`: `:newline`, the default, writes a newline; `:space` writes a space; `:br` writes a `(:br nil)` element, then a newline.
- `:raw-html`: `:omit`, the default, writes the comment `markdown->html` writes in place of raw HTML; `:text` writes the raw HTML as text.
- `:link-policy`: `:safe`, the default, blanks dangerous URLs, as `markdown->html` does by default; `:unsafe` keeps them.
- `:document-wrapper`: `nil`, the default, or a keyword naming a non-void element (see `html-tree->string`), to wrap the whole tree in.

The last four, the tree options, are `ast->html-tree`'s own.

This entry point parses without source positions: `:sourcepos` isn't one of its options, since the tree carries none.

Signals a `type-error` when `markdown` isn't a string; `invalid-parse-option` for a bad `:profile`, `:extensions`, `:footnotes` or `:smart` value; and `invalid-render-option` for everything else -- an odd-length option list, an unknown key, or a bad `:softbreak`, `:raw-html`, `:link-policy` or `:document-wrapper` value -- before cmark-gfm runs.

Signals `resource-limit-exceeded` for input past `*max-input-octets*` or `*max-nodes*`, `unsupported-input` for input cmark-gfm can't parse safely, and a `native-error` when cmark-gfm fails to load or to run. `*cmark-gfm-libraries*` says where it is loaded from.

### `markdown->plaintext`

Function

`(markdown->plaintext markdown &rest options)`

Render `markdown`, a string, to plain text with cmark-gfm's own plaintext renderer, and return the result as a string.

`options` is a plist. When a key repeats, the leftmost value wins, but every value must be valid.

- `:profile`, `:extensions`, `:footnotes` and `:smart`: as `parse`.
- `:softbreak`: `:newline`, the default, writes a newline in place of a softbreak, but a space inside a heading, or wherever `:width` is above 0, where a line can wrap at it. `:br` writes a newline everywhere, and turns `:width` off for the whole text: nothing wraps. `:space` writes a space, and turns wrapping off too.
- `:width`: 0, the default, for no wrapping, or a column from 1 to 2,147,483,647 to wrap text at. It wraps only under `:softbreak` `:newline`, never inside a heading.

This entry point parses without source positions: `:sourcepos` isn't one of its options.

Signals a `type-error` when `markdown` isn't a string; `invalid-parse-option` for a bad `:profile`, `:extensions`, `:footnotes` or `:smart` value; and `invalid-render-option` for everything else -- an odd-length option list, an unknown key, or a bad `:softbreak` or `:width` value -- before cmark-gfm runs.

Signals `resource-limit-exceeded` for input past `*max-input-octets*` or `*max-nodes*`, or output that could pass `*max-output-octets*`; `unsupported-input` for input cmark-gfm can't parse safely; and a `native-error` when cmark-gfm fails to load or to run. `*cmark-gfm-libraries*` says where it is loaded from.

### `parse`

Function

`(parse markdown &rest options)`

Parse `markdown`, a string, with cmark-gfm, and return its AST: a `:document` node holding Lisp data only, valid for as long as it is kept.

`options` is a plist. When a key repeats, the leftmost value wins, but every value must be valid.

- `:profile`: `:gfm`, the default, or `:commonmark`. A profile only supplies the defaults of `:extensions` and `:footnotes`.
- `:extensions`: the syntax extensions to attach, a list of distinct keywords from `:table`, `:strikethrough`, `:autolink`, `:tagfilter` and `:tasklist`, in any order. Defaults to all five under `:gfm`, and to none under `:commonmark`.
- `:footnotes`: `t` or `nil`. Defaults to `t` under `:gfm`, and to `nil` under `:commonmark`.
- `:smart`: `nil`, the default, or `t` for curly quotes, dashes and ellipses.
- `:sourcepos`: `t`, the default, gives each node its position: a cons of its start and its end, each a cons of a line and a column, with columns counted in UTF-8 octets, as cmark-gfm reports them. A node cmark-gfm has no position for, such as a softbreak, gets `nil`. With `nil`, every node gets `nil`.

The document node's attributes record the profile, the extensions attached and the options on. A NUL character, and a lone surrogate, reach the AST as U+FFFD.

Signals a `type-error` when `markdown` isn't a string, and `invalid-parse-option` for any bad option, before cmark-gfm runs.

Signals `resource-limit-exceeded` for input past `*max-input-octets*` or `*max-nodes*`, `unsupported-input` for input cmark-gfm can't parse safely, and a `native-error` when cmark-gfm fails to load or to run. `*cmark-gfm-libraries*` says where it is loaded from.

### `*cmark-gfm-libraries*`

Variable

Where to load cmark-gfm from: `nil`, the default, to search a fixed list of directories, never the loader's own search path; or a list of two absolute paths, strings or pathnames, naming the pinned libcmark-gfm, then libcmark-gfm-extensions. Read when cmark-gfm starts, at the first call that needs it.

The search tries, in order, `/usr/lib/<multiarch>` (x86\_64-linux-gnu or aarch64-linux-gnu), `/usr/lib64`, `/usr/lib` and `/usr/local/lib` on Linux, or `/opt/homebrew/lib` and `/usr/local/lib` on macOS, and takes the first that holds both libraries under their versioned names, such as libcmark-gfm.so.0.29.0.gfm.13.

Takes priority over the `CL_COMMONMARK_GFM_LIBS` environment variable, which names the same two paths, separated by a colon. Either override is used as given, with no fallback to the other or to the search: one that isn't two absolute paths, or names something that isn't a regular file, signals `native-library-not-found`, whose report names that override.

On CCL, which can't unload a library, the first pair a process loads stays its pair, even if starting cmark-gfm then fails: naming another pair after that signals `native-initialization-error`, and only a new process can load it. An ECL program with cmark-gfm linked in loads nothing, and ignores both.

### `*max-input-octets*`

Variable

The most UTF-8 octets of Markdown that `parse`, `markdown->html`, `markdown->plaintext` and `markdown->html-tree` accept. Default 1,048,576 (1 MiB). Larger input signals `resource-limit-exceeded` before cmark-gfm sees it. Bind it higher for larger documents, up to a hard cap of 268,435,456 (256 MiB): a higher binding is held to the cap. The limit guards cmark-gfm's parse buffers, which can reach three times the input's octets (a NUL or a smart quote becomes three bytes). Bound to anything but a non-negative integer, it makes every entry point signal a `type-error`.

### `*max-nodes*`

Variable

The most AST nodes, the document node included, a parse accepts. Default 1,000,000. Every entry point checks it before parsing, against an upper bound on the table cells cmark-gfm would build; `parse` and `markdown->html-tree` also count the nodes of the AST they build against it. A breach of either signals `resource-limit-exceeded`. The limit guards cmark-gfm's own memory -- padded table cells can multiply nodes well past the input's size -- and the Lisp heap that holds the AST. No hard cap: raise it as far as the machine's memory allows. Bound to anything but a non-negative integer, it makes every entry point signal a `type-error`.

### `*max-output-octets*`

Variable

The most UTF-8 octets `markdown->html` and `markdown->plaintext` may produce. Default 67,108,864 (64 MiB). After parsing and before rendering, each works out an upper bound on its output, and signals `resource-limit-exceeded` when that is above the limit. The bound takes the worst case, such as every octet of text escaped as \&quot; in HTML, so a document can be rejected whose output would have fit. Bind it higher for larger documents, up to a hard cap of 536,870,912 (512 MiB), half the 1,073,741,823 bytes past which a cmark-gfm buffer aborts the process; a higher binding is held to the cap. Bound to anything but a non-negative integer, it makes every entry point signal a `type-error`, `parse` and `markdown->html-tree` included.

## The AST

### `node`

Structure

An immutable CommonMark/GFM AST node. Build one with `make-node` or `copy-node`, which validate it.

### `copy-node`

Function

`(copy-node node &key attributes children sourcepos)`

Return a new node like `node`, with `attributes` merged over its own, and `children` or `sourcepos` replaced only when supplied (so `:sourcepos` `nil` clears it). A supplied `children` is copied, as `make-node` copies it, so mutating the list you passed afterwards does not change the node. There is no way to change `node`'s kind. Validates the result exactly as `make-node` would.

### `fold-ast`

Function

`(fold-ast function initial-value node)`

Fold `function` over `node` and its descendants, depth-first and parent before children: `function` is called with each node and the accumulator, which starts as `initial-value`, and returns the next accumulator. Returns the final accumulator.

Memory, not the Lisp call stack, bounds `node`'s depth. Signals a `type-error` when `node` is not a `node`.

### `make-node`

Function

`(make-node kind &key attributes children sourcepos)`

Build and validate a `node` of `kind`. `attributes` is a plist; any key `kind`'s schema does not require takes its default when `attributes` omits it. `children` is a list of nodes, and must be empty when `kind` is a leaf kind; `make-node` stores a copy of it, so mutating the list you passed afterwards does not change the node. `sourcepos` is `nil` or a source position, as `parse` gives them. Signals `invalid-ast-node` for any schema violation.

### `map-ast`

Function

`(map-ast function node)`

Return a list of `function`'s results on `node` and each descendant, depth-first, parent before children, in that order.

Memory, not the Lisp call stack, bounds `node`'s depth. Signals a `type-error` when `node` is not a `node`. Linear in the number of nodes.

### `node-attribute`

Function

`(node-attribute node key)`

Return the value of `node`'s `key` attribute. Signals `invalid-ast-node` when `node`'s kind has no such attribute.

### `node-attributes`

Function

`(node-attributes node)`

Return a fresh copy of `node`'s canonical attribute plist.

### `node-children`

Function

`(node-children node)`

Return a fresh copy of `node`'s list of child nodes, like `node-attributes`, so a destructive operation on the result (e.g. `sort`) cannot corrupt `node`.

### `node-kind`

Function

`(node-kind node)`

Return `node`'s kind keyword.

### `node-p`

Function

`(node-p object)`

True when `object` is a `node`.

### `node-sourcepos`

Function

`(node-sourcepos node)`

Return `node`'s source position, or `nil` when it has none.

### `node=`

Function

`(node= a b &key sourcepos)`

True when nodes `a` and `b` have the same kind, attributes and children, and, unless `sourcepos` is `nil`, the same source position at every depth. Signals a `type-error` when `a` or `b` is not a `node` -- `a` is checked first, so its datum is the one named when both are bad.

Memory, not the Lisp call stack, bounds the depth it compares. Two `eql` nodes are equal without being descended into.

### `transform-ast`

Function

`(transform-ast function node)`

Transform `node` bottom-up: `function` is called on each node after its children have already been transformed, and returns a node, a list of nodes to splice into the parent, or `nil` to delete the node. Returns the single resulting root node. Signals `invalid-ast-node` when `function` returns anything else, or when the root doesn't come back as exactly one node, bare or alone in a list; its datum is then what `function` returned. When no child of a node changed, `function` is called on that same node object, not a copy.

Memory, not the Lisp call stack, bounds `node`'s depth. Signals a `type-error` when `node` is not a `node`.

### `walk-ast`

Function

`(walk-ast function node)`

Visit `node` and its descendants depth-first, children in order, calling `function` with `:enter` and each node before its children, and with `:exit` and the node after them; a leaf gets both calls. When an `:enter` call returns `:skip`, that node's children and its `:exit` call are skipped; every other returned value is ignored. Returns `nil`.

Memory, not the Lisp call stack, bounds `node`'s depth, and, unlike `node-children`, it reads each node's children without copying them. Signals a `type-error` when `node` is not a `node`, before `function` is ever called. Whatever `function` signals propagates out of `walk-ast`, abandoning the walk.

## The HTML tree

### `ast->html-tree`

Function

`(ast->html-tree node &rest options)`

Convert the AST `node` into an HTML tree, as cmark-gfm's HTML renderer would render it. Returns a list of top-level items, strings and elements, whose strings carry the newlines cmark-gfm writes; or, with `:document-wrapper`, one element of that tag holding them. A `node` that isn't a `:document` converts as a document's only child.

`options` is a plist. When a key repeats, the leftmost value wins, but every value must be valid.

- `:raw-html`: `:omit`, the default, turns raw HTML into cmark-gfm's comment, `(:*comment* nil " raw HTML omitted ")`; `:text` keeps its markup as text.
- `:softbreak`: `:newline`, the default, turns a soft break into a newline; `:space`, into a space; `:br`, into `(:br nil)` and a newline.
- `:link-policy`: `:safe`, the default, blanks a link or image URL that starts, in any case, with `"javascript:"`, `"vbscript:"`, `"file:"` or `"data:"`, but not `"data:image/png"`, `"data:image/gif"`, `"data:image/jpeg"` or `"data:image/webp"`, as cmark-gfm does; `:unsafe` keeps every URL.
- `:document-wrapper`: `nil`, the default, or a keyword naming a non-void element (see `html-tree->string`), which wraps the result in one element of that tag.

Signals `invalid-render-option` for a malformed option list, an unknown key or a bad value, before converting anything; and `unsupported-extension-node`, naming the first `:extension` node depth-first, when the tree holds one. Memory, not the Lisp call stack, bounds `node`'s depth. Returns a fresh tree, and leaves `node` as it was.

### `html-tree->string`

Function

`(html-tree->string tree)`

Serialize `tree` to an HTML string. `tree` is a string; an element, meaning a list whose first item is a keyword; or a list of strings and elements (`nil` is the empty list, so it serializes as `""`). Adds no newlines or indentation of its own: the output is `tree`'s plain concatenation. Signals `invalid-html-tree` for a malformed `tree`, naming the offending node or value. The void elements, `:area`, `:base`, `:br`, `:col`, `:embed`, `:hr`, `:img`, `:input`, `:link`, `:meta`, `:source`, `:track` and `:wbr`, print with no end tag, as `"<tag />"`, and signal `invalid-html-tree` if they have children.

Text and attribute values are entity-escaped, but URLs aren't checked: the link policy applies only in `ast->html-tree`. Memory, not the Lisp call stack, bounds `tree`'s depth.

## Conditions

### `commonmark-gfm-error`

Condition, a subtype of `error`

Base of every condition cl-commonmark-gfm exports. Its readers, `condition-operation`, `condition-datum` and `condition-reason`, apply to them all.

### `dynamic-ffi-unavailable`

Condition, a subtype of [`native-error`](#native-error)

Signalled on an ECL built without dynamic FFI (no `:dffi` feature) when cmark-gfm isn't linked into the program: such an ECL can't load a library at run time. Starting cmark-gfm signals it first, before looking for or loading anything. `condition-datum` is `:dffi`, and `condition-reason` says how to link cmark-gfm into a program instead: compile with `cffi-sys:*cffi-ecl-method*` set to `:c/c++`, and link libcmark-gfm-extensions.a and libcmark-gfm.a. A program with cmark-gfm linked in never signals it.

### `invalid-ast-node`

Condition, a subtype of [`commonmark-gfm-error`](#commonmark-gfm-error)

Signalled by `make-node` and `copy-node` when a node fails schema validation, by `node-attribute` for a key its node's kind lacks, and by `transform-ast` when its function returns anything but a node, a list of nodes or `nil`, or the root doesn't come back as exactly one node.

### `invalid-html-tree`

Condition, a subtype of [`commonmark-gfm-error`](#commonmark-gfm-error)

Signalled by `html-tree->string` for a malformed HTML tree.

### `invalid-option`

Condition, a subtype of [`commonmark-gfm-error`](#commonmark-gfm-error)

Parent of `invalid-parse-option` and `invalid-render-option`. Not signalled directly.

### `invalid-parse-option`

Condition, a subtype of [`invalid-option`](#invalid-option)

Signalled by `parse` for any malformed, unknown or out-of-range option, and by `markdown->html`, `markdown->plaintext` and `markdown->html-tree` for a bad value of one of `parse`'s options they take.

### `invalid-render-option`

Condition, a subtype of [`invalid-option`](#invalid-option)

Signalled by `ast->html-tree` for a malformed or unknown rendering option, and by `markdown->html`, `markdown->plaintext` and `markdown->html-tree` for any option problem that isn't `invalid-parse-option`'s: an unknown key, an odd-length option list, or a bad non-parse value.

### `native-abi-mismatch`

Condition, a subtype of [`native-error`](#native-error)

Signalled when the loaded cmark-gfm isn't the pinned version, or when reading its version fails, as when a function is missing from the loaded libraries. `condition-expected-version` gives the pinned version, `condition-found-version` the one it reported, and `condition-paths` the libraries loaded.

### `native-error`

Condition, a subtype of [`commonmark-gfm-error`](#commonmark-gfm-error)

Parent of `native-library-not-found`, `native-abi-mismatch`, `dynamic-ffi-unavailable`, `native-initialization-error`, `native-parse-error` and `native-render-error`. Not signalled directly.

The first four are signalled when cmark-gfm fails to start. It starts at the first call that needs it, loading the pinned version as `*cmark-gfm-libraries*` says, then checking it. An ECL program with cmark-gfm linked in skips the loading, but not the checks.

### `native-initialization-error`

Condition, a subtype of [`native-error`](#native-error)

Signalled when cmark-gfm's libraries load but cmark-gfm fails to start, such as when a GFM extension is missing or its test parse fails. Also signalled on CCL for a pair of libraries other than the process's first, as `*cmark-gfm-libraries*` explains: `condition-datum` gives the refused pair's truenames, and `condition-reason` names the pair the process keeps.

### `native-library-not-found`

Condition, a subtype of [`native-error`](#native-error)

Signalled when starting cmark-gfm can't find the pinned version's two libraries, libcmark-gfm and libcmark-gfm-extensions, when an override that names them is malformed, or when loading one of them fails. `condition-override` gives the override in effect, and `condition-paths` the paths involved.

### `native-parse-error`

Condition, a subtype of [`native-error`](#native-error)

Signalled when cmark-gfm fails to parse, or its result holds something this library can't read, such as a footnote reference with no definition.

### `native-render-error`

Condition, a subtype of [`native-error`](#native-error)

Signalled when one of cmark-gfm's renderers fails.

### `resource-limit-exceeded`

Condition, a subtype of [`commonmark-gfm-error`](#commonmark-gfm-error)

Signalled when a value exceeds one of the three limits, `*max-input-octets*`, `*max-nodes*` or `*max-output-octets*`. `condition-limit` names the limit, `condition-maximum` gives the maximum that applied, and `condition-datum` the value found; `condition-reason` says whether the hard cap applied.

Even within the limits, on a machine already short of memory, cmark-gfm's allocator can still abort the process, and no Lisp handler can catch that.

### `unsupported-extension-node`

Condition, a subtype of [`commonmark-gfm-error`](#commonmark-gfm-error)

Signalled by `ast->html-tree` for an `:extension` node.

### `unsupported-input`

Condition, a subtype of [`commonmark-gfm-error`](#commonmark-gfm-error)

Signalled by `parse`, `markdown->html`, `markdown->plaintext` and `markdown->html-tree`, while `:footnotes` is on, as it is by default, for input holding `"["` immediately followed by an entity that decodes to `"^"`, such as `"&#94;"`, `"&#x5e;"` or `"&Hat;"`. cmark-gfm 0.29.0.gfm.13 can't parse that safely, so the input is refused before cmark-gfm sees it, wherever the pattern is, even in a code block. To parse such input, pass `:footnotes` `nil`, and do without footnotes. `condition-datum` gives the index of the `"["` that starts the pattern.

### `condition-datum`

Function

`(condition-datum condition)`

Return `condition`'s datum: the offending value.

### `condition-expected-version`

Function

`(condition-expected-version condition)`

Return `condition`'s expected-version: the cmark-gfm version string this library is pinned to.

### `condition-found-version`

Function

`(condition-found-version condition)`

Return `condition`'s found-version: the version the loaded cmark-gfm reported, or `nil` when reading it failed.

### `condition-limit`

Function

`(condition-limit condition)`

Return `condition`'s limit: the symbol naming the special variable whose limit was exceeded.

### `condition-maximum`

Function

`(condition-maximum condition)`

Return `condition`'s maximum: the effective maximum that applied, the limit or its hard cap when that is lower.

### `condition-operation`

Function

`(condition-operation condition)`

Return `condition`'s operation: the symbol naming what failed.

### `condition-override`

Function

`(condition-override condition)`

Return `condition`'s override: the override value in effect when the search that failed was using one -- `*cmark-gfm-libraries*`' value, or `CL_COMMONMARK_GFM_LIBS`' when that was used instead -- or `nil` when it was the ordinary directory search.

### `condition-paths`

Function

`(condition-paths condition)`

Return `condition`'s paths. For `native-library-not-found`, a list of the directories searched, or of the one path that isn't a regular file or failed to load; or `nil` for a malformed override. For `native-abi-mismatch`, the paths of the two libraries loaded, or `:linked` in a linked program, which loads none.

### `condition-reason`

Function

`(condition-reason condition)`

Return `condition`'s reason: a short phrase describing what is wrong with the datum.
