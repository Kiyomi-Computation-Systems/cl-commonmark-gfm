# The HTML tree

An HTML tree is HTML as Lisp lists, which you can read and change.
[`markdown->html-tree`](reference.md#markdown-html-tree) makes one from
Markdown, and [`ast->html-tree`](reference.md#ast-html-tree) from an
AST. [`html-tree->string`](reference.md#html-tree-string) writes it out
as HTML. For the package the examples run in, see
[The package](usage.md#the-package).

## The shape

Read an element as its tag, its attributes, then its children:

```lisp
(markdown->html-tree "Hello, [world](https://example.com)!")
;; => ((:p nil "Hello, " (:a ((:href "https://example.com")) "world") "!") "\n")

(markdown->html-tree "# Hello

*world*")
;; => ((:h1 nil "Hello") "\n" (:p nil (:em nil "world")) "\n")
```

A tag is a keyword. The attributes are `nil`, or a list of
`(name "value")` lists, each name a keyword. The children are strings
and elements, and the tree is a list of them too. Each `"\n"` string
stands for a newline in cmark-gfm's HTML, so code that walks a tree
meets strings between the elements.

## Tree options

Pass a tree option to change what the tree holds:

```lisp
(markdown->html-tree "Hello, <br>world!")
;; => ((:p nil "Hello, " (:*comment* nil " raw HTML omitted ") "world!") "\n")

(markdown->html-tree "Hello, <br>world!" :raw-html :text)
;; => ((:p nil "Hello, <br>world!") "\n")
```

By default, raw HTML becomes a `:*comment*` element, where cmark-gfm's
HTML has a comment. With `:raw-html :text`, it stays as text, which is
escaped when the tree is written out. [Options](options.md) lists every
tree option, and [Safe by default](safety.md#safe-by-default) explains
why raw HTML is left out.

## Writing HTML

Call `html-tree->string` to write a tree out as HTML:

```lisp
(html-tree->string (markdown->html-tree "Hello, *world*!"))
;; => "<p>Hello, <em>world</em>!</p>\n"

(html-tree->string '((:p nil "1 < 2") (:p nil "Fish & chips")))
;; => "<p>1 &lt; 2</p><p>Fish &amp; chips</p>"
```

With the default options, a tree from Markdown writes out as the HTML
[`markdown->html`](reference.md#markdown-html) writes, but for a few
rare [footnotes](#footnotes). Strings and attribute values are escaped.
No newline or indentation is added: the HTML holds only what the tree
holds.

Check a URL yourself before you add it to a tree. `html-tree->string`
writes it as it is:

```lisp
(html-tree->string '(:a ((:href "javascript:alert(1)")) "Hi"))
;; => "<a href=\"javascript:alert(1)\">Hi</a>"
```

Dangerous URLs are blanked only by `:link-policy`, as the tree is made.
`html-tree->string` does check the tree's shape, and its tag and
attribute names: a malformed tree signals
[`invalid-html-tree`](reference.md#invalid-html-tree).

## A whole page

Wrap the tree in your own elements to write a whole page:

```lisp
(defparameter *body*
  (markdown->html-tree "Hello, *world*!" :document-wrapper :body))

(defparameter *page*
  `(:html nil (:head nil (:meta ((:charset "utf-8")))) ,*body*))

(html-tree->string *page*)
;; => "<html><head><meta charset=\"utf-8\" /></head><body><p>Hello,
;; <em>world</em>!</p>\n</body></html>"
```

`:document-wrapper` wraps the tree in one element, here `:body`. `:meta`
is one of HTML's void elements: it prints with no end tag, and can't
have children. A tree holds no doctype. Write `<!DOCTYPE html>` before
the HTML yourself, since a string in the tree is escaped:

```lisp
(html-tree->string "<!DOCTYPE html>")
;; => "&lt;!DOCTYPE html&gt;"
```

## Footnotes

The tree's footnotes match cmark-gfm's HTML, except in a few rare
inputs. Every known exception has a footnote whose own text cites a
footnote:

```lisp
(defparameter *notes* "[^a]: See [^b].
[^b]: B.
[^c]: C.

Hello[^c].")

(string= (markdown->html *notes*)
         (html-tree->string (markdown->html-tree *notes*)))
;; => nil
```

cmark-gfm's HTML still counts a citation inside a footnote it leaves
out, such as one that nothing cites, and the tree doesn't. So the two
can differ in which footnotes they keep, in their numbers, and in their
back links. Here nothing cites `[^a]`, but cmark-gfm's HTML counts its
citation of `[^b]`: it keeps `[^b]`, with a back link that leads
nowhere, and numbers `[^c]` 2. The tree leaves `[^b]` out, and numbers
`[^c]` 1.

The two can also count a footnote's citations in another order, when
some of them sit inside footnotes. Then the citations' ids, and the back
links that lead to them, come in another order.

On an AST you build yourself, footnotes are numbered in the order of
their `:footnote-definition` nodes. A `:footnote-reference` finds its
definition only by the same label, case included.
