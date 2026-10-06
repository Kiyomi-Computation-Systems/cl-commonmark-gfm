# Usage

First, load the library: see
[The library, through ocicl](installing.md#the-library-through-ocicl).
Then call one of four functions with a string of Markdown. Each gives
back something different: HTML, an HTML tree, plain text or an AST.

## The package

Everything the library offers is exported from one package,
`cl-commonmark-gfm`. Import what you call into your own package:

```lisp
(defpackage #:my-app
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm #:markdown->html #:parse))
```

The examples on these pages run in a package that uses
`cl-commonmark-gfm`, so they leave off its prefix. `;; =>` shows what a
form returns, and `;; signals` the error it signals. In a result, `\n`
inside a string is a newline, which the REPL shows as a line break.

## HTML

Call [`markdown->html`](reference.md#markdown-html) to turn Markdown into
HTML:

```lisp
(markdown->html "Hello, *world*!")
;; => "<p>Hello, <em>world</em>!</p>\n"
```

The HTML comes from cmark-gfm's own renderer. It is
[safe by default](safety.md#safe-by-default).

## An HTML tree

Call [`markdown->html-tree`](reference.md#markdown-html-tree) to get
HTML as a Lisp tree. You can change the tree before you write it out:

```lisp
(markdown->html-tree "Hello, *world*!")
;; => ((:p nil "Hello, " (:em nil "world") "!") "\n")
```

The tree is [safe by default](safety.md#safe-by-default) too.
[The HTML tree](html-tree.md) explains its shape, and how to write it
out.

## Plain text

Call [`markdown->plaintext`](reference.md#markdown-plaintext) to get
plain text, such as for a search index:

```lisp
(markdown->plaintext "Hello, *world*!")
;; => "Hello, world!\n"
```

The text comes from cmark-gfm's own plain text renderer. To wrap its
lines, pass `:width`: see [Options](options.md).

## An AST

Call [`parse`](reference.md#parse) to get the document as an AST, a tree
of nodes. Use it to read the document's structure, or to build a new
tree from it before you render it:

```lisp
(map-ast #'node-kind (parse "Hello, *world*!"))
;; => (:document :paragraph :text :emph :text :text)
```

Here [`map-ast`](reference.md#map-ast) calls
[`node-kind`](reference.md#node-kind) on every node, each parent before
its children. [The AST](ast.md) shows every kind of node, and how to
read nodes, walk a tree and build new ones. To render an AST, pass it to
[`ast->html-tree`](reference.md#ast-html-tree): it returns an HTML tree.

## Passing options

Pass options as keyword arguments, after the Markdown:

```lisp
(markdown->html "Don't panic..." :smart t)
;; => "<p>Don’t panic…</p>\n"
```

[Options](options.md) lists every option, its values and its default,
and the functions that take it.

## Profiles

All four functions take `:profile`, which picks the kind of Markdown to
read. `:gfm`, the default, turns on GitHub's extensions, such as tables
and strikethrough, and footnotes. `:commonmark` turns them all off, for
plain CommonMark:

```lisp
(markdown->html "~~gone~~")
;; => "<p><del>gone</del></p>\n"

(markdown->html "~~gone~~" :profile :commonmark)
;; => "<p>~~gone~~</p>\n"
```

A profile only sets the defaults of two options, `:extensions` and
`:footnotes`. Pass either one to choose for yourself:

```lisp
(markdown->html "~~gone~~" :profile :commonmark :extensions '(:strikethrough))
;; => "<p><del>gone</del></p>\n"
```

## Large documents

The library refuses a document past one of its size limits. The call
signals [`resource-limit-exceeded`](reference.md#resource-limit-exceeded),
and its message names the limit:

```lisp
(defparameter *large* (make-string 2000000 :initial-element #\a))

(markdown->html *large*)
;; signals resource-limit-exceeded
```

To take a larger document, bind that limit higher around the call:

```lisp
(let ((*max-input-octets* (* 4 1024 1024)))
  (length (markdown->html *large*)))
;; => 2000008
```

Bind it with `let`, so the rest of your program keeps the default.
[Size limits](safety.md#size-limits) explains each limit, its default,
and how high it can go.

## Saved images

Save an image with the library loaded as you would any other, such as
with SBCL's `sb-ext:save-lisp-and-die` or CCL's `ccl:save-application`:

```lisp no-run
(sb-ext:save-lisp-and-die "my-app" :executable t)
```

Before the image is written, the library closes cmark-gfm. The image
loads it again at its first call, so cmark-gfm must be found where the
image runs: see
[Where the library looks](installing.md#where-the-library-looks). A
value you set for
[`*cmark-gfm-libraries*`](reference.md#cmark-gfm-libraries) before
saving stays in the image: see
[Choosing the libraries yourself](installing.md#choosing-the-libraries-yourself).

Save when no other thread is inside a call. SBCL won't save while other
threads run anyway. CCL ends the other threads first, but one still
inside cmark-gfm makes the save fail with an error.

ECL makes no saved images. To ship a program on ECL, see [ECL](ecl.md).
