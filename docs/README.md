# cl-commonmark-gfm

cl-commonmark-gfm is a Common Lisp binding of cmark-gfm 0.29.0.gfm.13,
GitHub's CommonMark parser, for SBCL, CCL and ECL. It renders Markdown to
HTML, or to an HTML tree or an AST you can walk and change.

To turn a string of Markdown into HTML, call `markdown->html`:

```lisp
(markdown->html "Hello, *world*!")
;; => "<p>Hello, <em>world</em>!</p>\n"
```

The documentation is being written. The [API reference](reference.md)
describes every exported symbol.
