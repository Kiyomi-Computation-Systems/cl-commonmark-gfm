# Errors

Every error the library's functions signal is a
[`commonmark-gfm-error`](reference.md#commonmark-gfm-error), apart from
CL's own `type-error`. This page lists them all, and what to do about
each. For the package the examples run in, see
[The package](usage.md#the-package).

## Catching errors

Catch an error with `handler-case`, here keeping the condition to read
it later:

```lisp
(defparameter *large* (make-string 2000000 :initial-element #\a))

(defparameter *error*
  (handler-case (markdown->html *large*)
    (commonmark-gfm-error (condition) condition)))
```

Print the condition to read its report: what failed, why, and the value
at fault:

```lisp
(princ-to-string *error*)
;; => "markdown->html: *max-input-octets* exceeded: 2000000"
```

Handle `commonmark-gfm-error` to catch every condition the library
exports. To catch one family, handle its parent instead:
[`invalid-option`](reference.md#invalid-option) for a bad option, or
[`native-error`](reference.md#native-error) for cmark-gfm failing to
start or to run. None of these three is signalled by itself.

A wrong argument, such as a number in place of Markdown, signals CL's
own `type-error`, and so does a size limit bound to anything but a
non-negative integer:

```lisp
(markdown->html 42)
;; signals type-error

(let ((*max-nodes* nil))
  (markdown->html "Hello"))
;; signals type-error
```

A walk given anything but a node signals one too.

## The conditions

Look up what to do about each condition:

| Condition | Signalled when | What to do |
|-----------|----------------|------------|
| [`invalid-parse-option`](reference.md#invalid-parse-option) | a bad value for one of [`parse`](reference.md#parse)'s options that the function takes, such as `:profile :html`; from `parse`, any bad option | Fix the option: see [Options](options.md). |
| [`invalid-render-option`](reference.md#invalid-render-option) | any other bad option: an unknown key, an odd-length list, or a bad value for a rendering option | Fix the option: see [Options](options.md). |
| [`resource-limit-exceeded`](reference.md#resource-limit-exceeded) | the input, its nodes or its output would pass a size limit | Refuse the document, or bind the limit higher: see [Size limits](safety.md#size-limits). |
| [`unsupported-input`](reference.md#unsupported-input) | with footnotes on, the input holds a `[` right before an entity for `^` | Refuse the document, or pass `:footnotes nil`: see [The footnote guard](safety.md#the-footnote-guard). |
| [`native-library-not-found`](reference.md#native-library-not-found) | cmark-gfm can't start: its two libraries aren't found, an override naming them is malformed, or one fails to load | See [When cmark-gfm can't start](installing.md#when-cmark-gfm-cant-start). |
| [`native-abi-mismatch`](reference.md#native-abi-mismatch) | cmark-gfm can't start: the libraries loaded aren't version 0.29.0.gfm.13, or their version can't be read | See [When cmark-gfm can't start](installing.md#when-cmark-gfm-cant-start). |
| [`dynamic-ffi-unavailable`](reference.md#dynamic-ffi-unavailable) | cmark-gfm can't start: ECL has no dynamic FFI, and cmark-gfm isn't linked into the program | See [When cmark-gfm can't start](installing.md#when-cmark-gfm-cant-start). |
| [`native-initialization-error`](reference.md#native-initialization-error) | cmark-gfm can't start: its libraries load, but an extension is missing or its test parse fails; or, on CCL, they aren't the process's first pair: see [Libraries on CCL](safety.md#libraries-on-ccl) | See [When cmark-gfm can't start](installing.md#when-cmark-gfm-cant-start). |
| [`native-parse-error`](reference.md#native-parse-error) | cmark-gfm fails to parse, or gives back something the library can't read | It isn't expected: [report it](https://github.com/Kiyomi-Computation-Systems/cl-commonmark-gfm/issues) as a bug, with the input. |
| [`native-render-error`](reference.md#native-render-error) | one of cmark-gfm's renderers fails | It isn't expected: [report it](https://github.com/Kiyomi-Computation-Systems/cl-commonmark-gfm/issues) as a bug, with the input. |
| [`invalid-ast-node`](reference.md#invalid-ast-node) | a node you build or copy breaks its kind's rules; [`node-attribute`](reference.md#node-attribute) asks for an attribute the kind lacks; or [`transform-ast`](reference.md#transform-ast)'s function returns something other than a node, a list of nodes or `nil`, or anything but one node for the root | Fix the node or the function: see [The AST](ast.md). |
| [`invalid-html-tree`](reference.md#invalid-html-tree) | [`html-tree->string`](reference.md#html-tree-string) is given a malformed tree | Fix the tree: see [The HTML tree](html-tree.md). |
| [`unsupported-extension-node`](reference.md#unsupported-extension-node) | [`ast->html-tree`](reference.md#ast-html-tree) meets an `:extension` node, which no parse makes | Remove or replace the node before converting. |

## The readers

Read any condition's parts with these three readers:

```lisp
(condition-operation *error*)
;; => markdown->html

(condition-reason *error*)
;; => "*max-input-octets* exceeded"

(condition-datum *error*)
;; => 2000000
```

[`condition-operation`](reference.md#condition-operation) names what
failed, [`condition-reason`](reference.md#condition-reason) says what's
wrong, and [`condition-datum`](reference.md#condition-datum) gives the
value at fault. They work on every condition the library exports. For
`unsupported-input`, the datum is the index of the `[` where the pattern
starts.

`*error*` is a `resource-limit-exceeded`, which has two more readers:

```lisp
(condition-limit *error*)
;; => *max-input-octets*

(condition-maximum *error*)
;; => 1048576
```

[`condition-limit`](reference.md#condition-limit) names the limit, and
[`condition-maximum`](reference.md#condition-maximum) gives the maximum
that applied: the limit's value, or its hard cap when that is lower.
The reason says which.

`native-library-not-found` and `native-abi-mismatch` have readers of
their own:

| Reader | Condition | Returns |
|--------|-----------|---------|
| [`condition-override`](reference.md#condition-override) | `native-library-not-found` | the override in effect, or `nil` for the directory search |
| [`condition-paths`](reference.md#condition-paths) | `native-library-not-found` | a list of the directories searched, or of the one path that failed; `nil` for a malformed override |
| `condition-paths` | `native-abi-mismatch` | the two libraries loaded, or `:linked` in a program with cmark-gfm linked in |
| [`condition-expected-version`](reference.md#condition-expected-version) | `native-abi-mismatch` | the version the library is pinned to |
| [`condition-found-version`](reference.md#condition-found-version) | `native-abi-mismatch` | the version the libraries reported, or `nil` when reading it failed |
