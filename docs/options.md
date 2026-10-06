# Options

Pass options as keyword arguments: see
[Passing options](usage.md#passing-options). This page lists them all.
For the package the examples run in, see
[The package](usage.md#the-package).

## Every option

In the table, "all four" means the four functions that take Markdown:
[`parse`](reference.md#parse),
[`markdown->html`](reference.md#markdown-html),
[`markdown->plaintext`](reference.md#markdown-plaintext) and
[`markdown->html-tree`](reference.md#markdown-html-tree).
[`ast->html-tree`](reference.md#ast-html-tree) takes only the tree
options: `:softbreak`, `:raw-html`, `:link-policy` and
`:document-wrapper`.

| Option | Values | Default | Taken by | What it does |
|---|---|---|---|---|
| `:profile` | `:gfm` or `:commonmark` | `:gfm` | all four | Sets the defaults of `:extensions` and `:footnotes`: see [Profiles](usage.md#profiles) |
| `:extensions` | a list of [extensions](#extensions), each once, in any order | all five under `:gfm`, none under `:commonmark` | all four | Reads GitHub's extensions to Markdown, such as tables |
| `:footnotes` | `t` or `nil` | `t` under `:gfm`, `nil` under `:commonmark` | all four | Reads footnotes, such as `[^1]` |
| `:smart` | `t` or `nil` | `nil` | all four | Turns straight quotes curly, `--` and `---` into dashes, and `...` into an ellipsis |
| `:sourcepos` | `t` or `nil` | `t` for `parse`, `nil` for `markdown->html` | `parse` and `markdown->html` | `parse` gives each node its position; `markdown->html` gives most blocks, such as a paragraph, a `data-sourcepos` attribute: see [Source positions](ast.md#source-positions) |
| `:softbreak` | `:newline`, `:space` or `:br` | `:newline` | `markdown->html`, `markdown->plaintext`, `markdown->html-tree` and `ast->html-tree` | Says what a soft break becomes: see [Soft breaks](#soft-breaks) |
| `:width` | an integer from 0 to 2,147,483,647 | 0 | `markdown->plaintext` | Wraps lines at that column, or not at all for 0 |
| `:unsafe-html` | `t` or `nil` | `nil` | `markdown->html` | With `t`, keeps raw HTML and dangerous URLs |
| `:raw-html` | `:omit` or `:text` | `:omit` | `markdown->html-tree` and `ast->html-tree` | Writes raw HTML as a comment, or as text |
| `:link-policy` | `:safe` or `:unsafe` | `:safe` | `markdown->html-tree` and `ast->html-tree` | Blanks dangerous URLs, or keeps them |
| `:document-wrapper` | `nil`, or the keyword of an element that isn't void | `nil` | `markdown->html-tree` and `ast->html-tree` | Wraps the whole tree in one element of that tag: see [A whole page](html-tree.md#a-whole-page) |

Before you pass `:unsafe-html t` or `:link-policy :unsafe`, see
[Safe by default](safety.md#safe-by-default).

## Extensions

Pass `:extensions` a list of the extensions you want:

```lisp
(markdown->html "~~gone~~ www.example.com" :extensions '(:autolink))
;; => "<p>~~gone~~ <a href=\"http://www.example.com\">www.example.com</a></p>\n"
```

Only `:autolink` is on, so the address becomes a link, and `~~gone~~`
stays as written. There are five:

- `:table`: tables, with `|` between cells.
- `:strikethrough`: struck-through text, between `~` or `~~`.
- `:autolink`: links from bare web and email addresses, such as
  `www.example.com`.
- `:tagfilter`: escapes a few tags, such as `<script>`, in the raw HTML
  that `markdown->html` keeps under `:unsafe-html t`. It changes nothing
  else.
- `:tasklist`: list items with a checkbox, such as `- [x] done`.

## Soft breaks

Pass `:softbreak` to choose what a line break inside a paragraph
becomes:

```lisp
(defparameter *lines* "Hello,
*world*!")

(markdown->html *lines* :softbreak :br)
;; => "<p>Hello,<br />\n<em>world</em>!</p>\n"

(markdown->html-tree *lines* :softbreak :space)
;; => ((:p nil "Hello, " (:em nil "world") "!") "\n")
```

In HTML and in a tree, `:newline` writes a newline, `:space` a space,
and `:br` a line break, then a newline. In a tree, that line break is a
`(:br nil)` element.

In plain text, pass `:width` to wrap lines:

```lisp
(defparameter *twice* "Hello, *world*! Hello, *world*!")

(markdown->plaintext *twice* :width 15)
;; => "Hello, world!\nHello, world!\n"

(markdown->plaintext *lines* :width 15)
;; => "Hello, world!\n"
```

In plain text, `:newline` keeps each soft break as a newline, but
writes a space inside a heading. With `:width` above 0, `:newline`
writes a space instead, so lines can wrap.
`:space` writes a space, and `:br` a newline. Both turn wrapping off:

```lisp
(markdown->plaintext *twice* :width 15 :softbreak :space)
;; => "Hello, world! Hello, world!\n"
```

## Repeated and bad options

Put the value you want first. When an option repeats, the leftmost
value wins:

```lisp
(markdown->html "~~gone~~" :profile :commonmark :profile :gfm)
;; => "<p>~~gone~~</p>\n"
```

Every option is checked before cmark-gfm runs, a repeated one too. A
value a function doesn't accept, or an option it doesn't take, signals
an error:

```lisp
(markdown->html "~~gone~~" :profile :commonmark :profile :html)
;; signals invalid-parse-option

(markdown->html "~~gone~~" :width 40)
;; signals invalid-render-option
```

`:width` is `markdown->plaintext`'s alone. Both errors are kinds of
[`invalid-option`](reference.md#invalid-option): see [Errors](errors.md).
