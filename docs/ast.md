# The AST

Call [`parse`](reference.md#parse) to get a document's AST, a tree of
nodes with a `:document` node at its root:

```lisp
(defparameter *doc* (parse "# Hello, *world*!"))

(map-ast #'node-kind *doc*)
;; => (:document :heading :text :emph :text :text)
```

Here [`map-ast`](reference.md#map-ast) lists every node's kind. Each
node has a kind, attributes, children and a source position. The tree
holds Lisp data only, so it stays valid for as long as you keep it.
For the package the examples run in, see
[The package](usage.md#the-package).

## Reading a node

Read a node's attributes with
[`node-attribute`](reference.md#node-attribute):

```lisp
(defparameter *heading* (first (node-children *doc*)))

(node-attribute *heading* :level)
;; => 1

(node-attribute *heading* :levle)
;; signals invalid-ast-node
```

A key the node's kind doesn't have signals an error, so a typo can't
pass for `nil`. [`node-attributes`](reference.md#node-attributes) gives
every attribute, as a plist. [`node-kind`](reference.md#node-kind) gives
the kind, [`node-children`](reference.md#node-children) the children,
in order, and [`node-sourcepos`](reference.md#node-sourcepos) the
position. [`node=`](reference.md#node-1) says whether two trees are the
same, and [`node-p`](reference.md#node-p) whether an object is a node.
A position or an attribute's value that a reader returns is the node's
own: don't modify it.

## Node kinds

Every node's kind is one of these keywords. Where an attribute's values
are listed, the first is its default; a required one has none. A leaf
has no children.

| Kind | What it is | Attributes |
|------|------------|------------|
| `:document` | the root | `:profile`: `nil`, `:gfm` or `:commonmark`; `:extensions` and `:options`: lists of keywords, `nil` by default |
| `:paragraph` | a paragraph | none |
| `:heading` | a heading | `:level`: 1 to 6, required |
| `:block-quote` | a quote, `>` | none |
| `:list` | a list | `:type`: `:bullet` or `:ordered`; `:start`: `nil` or the first item's number; `:delimiter`: `nil`, `:period` or `:paren`; `:tight`: `nil` or `t` |
| `:item` | a list item | none |
| `:task-item` | a task list item, `[ ]` or `[x]` | `:checked`: `nil` or `t` |
| `:code-block` | a code block; a leaf | `:info`, the text after the opening fence, and `:literal`, the code: strings, `""` by default |
| `:html-block`, `:html-inline` | raw HTML, as a block or inside a line; leaves | `:literal`: a string, `""` by default |
| `:thematic-break` | a break, such as `***`; a leaf | none |
| `:table`, `:table-header`, `:table-row` | a table, its first row, and each other row | none |
| `:table-cell` | a cell | `:align`, its column's: `nil`, `:left`, `:center` or `:right` |
| `:footnote-definition` | a footnote, `[^a]: ...` | `:label`: a non-empty string, required |
| `:footnote-reference` | a reference to one, `[^a]`; a leaf | `:label`: a non-empty string, required |
| `:text` | text, which can be empty; a leaf | `:literal`: a string, `""` by default |
| `:code` | a code span; a leaf | `:literal`: a string, `""` by default |
| `:softbreak`, `:linebreak` | a line's end inside a paragraph, and a hard line break; leaves | none |
| `:emph`, `:strong`, `:strikethrough` | emphasis `*a*`, strong `**a**`, struck-out `~~a~~` | none |
| `:link`, `:image` | a link, autolinks included, and an image, whose children are its alt text | `:destination` and `:title`: strings, `""` by default |
| `:extension` | a node of an extension this library doesn't know: `parse` never makes one | `:extension-name`: `nil` or a string; `:type-name`: a string, required |

`parse` sets the document's attributes: its profile, the extensions it
attached, and which of `:footnotes` and `:smart` it turned on. An
`:ordered` list has a `:start` and a `:delimiter`, and a `:bullet` list
neither. A footnote reference's `:label` is spelled as its definition's,
so `string=` matches the two.

## Source positions

Read a node's position with `node-sourcepos`:

```lisp
(node-sourcepos *heading*)
;; => ((1 . 1) 1 . 17)

(node-sourcepos (first (node-children (parse "# Héllo, *world*!"))))
;; => ((1 . 1) 1 . 18)
```

The first is `((1 . 1) . (1 . 17))`: the heading runs from line 1,
column 1, to line 1, column 17, both included. Columns count UTF-8
octets, not characters: the second heading ends at column 18, since its
é takes two.

Positions are cmark-gfm's own, passed on as it reports them. Most are
right, but not all:

- a softbreak, a linebreak, an email address made into a link, and the
  text after that address have none: `nil`;
- an end can come early, even before its start, as on a `<script>`
  block, or at column 0 of the next line, as on a list before a blank
  line;
- a bare web address made into a link, such as `www.example.com`, can
  start in the wrong column, and the text before it, or before an email
  address, can end in the wrong one;
- each line that ends in a backslash, a hard line break, puts the rest
  of its paragraph a line too early, and the next line's text in the
  wrong columns too;
- when a table follows a paragraph's lines with no blank line between,
  those lines get no positions or wrong ones, even negative, and the
  table's start and its first row are wrong too.

So use a position to point near a place in the source, and check it
before you cut the source with it. To parse without positions, pass
`:sourcepos nil`: see [Options](options.md).

## Walking the tree

Pick one of four walks:

- `map-ast` calls a function on every node, each parent before its
  children, and returns the results in a list. Use it to collect
  something from each node.
- [`fold-ast`](reference.md#fold-ast) calls a function on every node,
  in the same order, passing each call's result to the next, and
  returns the last. Use it to count, or to build one result.
- [`walk-ast`](reference.md#walk-ast) calls a function as it enters a
  node and as it leaves it, and can skip a node's children. Use it to
  track nesting, or to pass over part of a tree.
- [`transform-ast`](reference.md#transform-ast) builds a new tree,
  children first. Use it to replace or drop nodes: see
  [Building new trees](#building-new-trees).

No walk has a depth limit:

```lisp
(length (map-ast #'node-kind
                 (parse (make-string 100000 :initial-element #\>))))
;; => 100001
```

Each `>` opens a quote inside the last. A walk you write yourself,
calling itself on each child, can run out of stack on such a tree.

## Building new trees

A node has no setters: to get a different tree, build a new one. To
build a node like another, call [`copy-node`](reference.md#copy-node)
with the attributes or children to replace:

```lisp
(ast->html-tree (copy-node *heading* :attributes '(:level 2)))
;; => ((:h2 nil "Hello, " (:em nil "world") "!") "\n")
```

The copy keeps the heading's children, and
[`ast->html-tree`](reference.md#ast-html-tree) renders any node, not
only a document. To build a node from nothing, call
[`make-node`](reference.md#make-node). `copy-node` and `make-node` check
what they build against the table above, and signal
[`invalid-ast-node`](reference.md#invalid-ast-node) for a mistake:

```lisp
(copy-node *heading* :attributes '(:level 7))
;; signals invalid-ast-node

(make-node :text :children (list *heading*))
;; signals invalid-ast-node
```

A level runs from 1 to 6, and a leaf has no children. They don't check
which kinds may hold which, so they accept a `:text` right inside a
`:document`.

To build a new tree from a whole one, call `transform-ast`. It calls
your function on each node, after the node's children. Return the node
to keep it, a list of nodes to put in its place, or `nil` to drop it:

```lisp
(defun unwrap-emph (node)
  (if (eql (node-kind node) :emph) (node-children node) node))

(ast->html-tree (transform-ast #'unwrap-emph *doc*))
;; => ((:h1 nil "Hello, world!") "\n")

(map-ast #'node-kind *doc*)
;; => (:document :heading :text :emph :text :text)
```

Each `:emph` gives way to its children in the new tree, and `*doc*` is
left as it was.
