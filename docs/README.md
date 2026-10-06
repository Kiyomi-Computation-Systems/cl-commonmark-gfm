# cl-commonmark-gfm

cl-commonmark-gfm is a Common Lisp binding of cmark-gfm 0.29.0.gfm.13,
GitHub's CommonMark parser, for SBCL, CCL and ECL. It renders Markdown
to HTML, an HTML tree or plain text, and parses it into an AST you can
read and walk.

```lisp
(markdown->html "Meet at ~~two~~ three.")
;; => "<p>Meet at <del>two</del> three.</p>\n"

(markdown->html-tree "Meet at ~~two~~ three.")
;; => ((:p nil "Meet at " (:del nil "two") " three.") "\n")

(map-ast #'node-kind (parse "Meet at ~~two~~ three."))
;; => (:document :paragraph :text :strikethrough :text :text)
```

For what `;; =>` and `\n` mean, see [The package](usage.md#the-package).

Its HTML is [safe by default](safety.md#safe-by-default): raw HTML in
the Markdown becomes a comment, and dangerous URLs are blanked.

## Contents

- [Installing](installing.md): getting cmark-gfm and the library.
- [Usage](usage.md): the four functions, options and profiles, and large
  documents.
- [Options](options.md): every option, its values and its default.
- [The AST](ast.md): the nodes [`parse`](reference.md#parse) returns,
  and how to read, walk and build them.
- [The HTML tree](html-tree.md): the tree's shape, and how to write it
  out as HTML.
- [Safety](safety.md): safe defaults, size limits, the footnote guard,
  threads and timeouts.
- [Errors](errors.md): every condition the library signals, and what to
  do.
- [ECL](ecl.md): using ECL, and a program with cmark-gfm linked in.
- [Support](support.md): the Lisps and systems it runs on, and how each
  is checked.
- [API reference](reference.md): every exported symbol, from its
  docstring.
