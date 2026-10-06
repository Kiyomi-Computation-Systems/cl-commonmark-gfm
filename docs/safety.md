# Safety

Markdown from strangers, such as comments on a website, can hold HTML
that runs script, or be built to make cmark-gfm crash your Lisp. The
library guards against both by default. This page says how, what you
can change, and what remains. For the package the examples run in, see
[The package](usage.md#the-package).

## Safe by default

Render Markdown from anyone with the defaults:

```lisp
(markdown->html "<b>Hi</b>")
;; => "<p><!-- raw HTML omitted -->Hi<!-- raw HTML omitted --></p>\n"

(markdown->html "[Hi](javascript:go)")
;; => "<p><a href=\"\">Hi</a></p>\n"
```

Raw HTML becomes a comment, and a dangerous URL is blanked, so neither
can run script in your readers' browsers. A URL is dangerous when it
starts with `javascript:`, `vbscript:`, `file:` or `data:`, in any case.
A `data:` URL is kept only for a PNG, GIF, JPEG or WebP image.

An HTML tree is safe the same way:

```lisp
(markdown->html-tree "[Hi](javascript:go)")
;; => ((:p nil (:a ((:href "")) "Hi")) "\n")
```

So is the tree [`ast->html-tree`](reference.md#ast-html-tree) makes from
an AST, though the AST itself keeps raw HTML and every URL. A URL you
add to a tree yourself isn't checked: see
[Writing HTML](html-tree.md#writing-html).

To keep raw HTML and every URL in Markdown you trust, such as your own,
pass `:unsafe-html t` to [`markdown->html`](reference.md#markdown-html):

```lisp
(markdown->html "<b>Hi</b>" :unsafe-html t)
;; => "<p><b>Hi</b></p>\n"
```

For an HTML tree, pass `:link-policy :unsafe` to keep every URL:

```lisp
(markdown->html-tree "[Hi](javascript:go)" :link-policy :unsafe)
;; => ((:p nil (:a ((:href "javascript:go")) "Hi")) "\n")
```

Even then, a tree never holds raw HTML as markup.

Never opt out for Markdown from strangers. The `:tagfilter` extension,
on by default, doesn't make it safe. It lets this through:

```lisp
(markdown->html "<img src=x onerror=go()>" :unsafe-html t)
;; => "<img src=x onerror=go()>\n"
```

## Size limits

Read the three size limits from their variables:

```lisp
(list *max-input-octets* *max-nodes* *max-output-octets*)
;; => (1048576 1000000 67108864)
```

| Variable | What it limits | Default | Hard cap |
|----------|----------------|---------|----------|
| [`*max-input-octets*`](reference.md#max-input-octets) | the Markdown, in UTF-8 octets | 1 MiB | 256 MiB |
| [`*max-nodes*`](reference.md#max-nodes) | the nodes a parse builds | 1,000,000 | none |
| [`*max-output-octets*`](reference.md#max-output-octets) | the HTML or text, in UTF-8 octets | 64 MiB | 512 MiB |

A call past a limit signals
[`resource-limit-exceeded`](reference.md#resource-limit-exceeded) before
cmark-gfm does the work. cmark-gfm itself would end the whole process,
and no Lisp handler could stop it, when one of its buffers reached 1 GiB
or memory ran out. Some small documents grow huge inside it, such as
tables whose rows are shorter than their header.

What each limit guards:
- `*max-input-octets*` guards the buffers cmark-gfm parses into, which
  can grow to three times the input.
- `*max-nodes*` guards memory, cmark-gfm's and Lisp's. Before parsing,
  every function checks it against the most table cells the input could
  make. [`parse`](reference.md#parse) and
  [`markdown->html-tree`](reference.md#markdown-html-tree) also count
  the nodes they build.
- `*max-output-octets*` guards the HTML and text that `markdown->html`
  and [`markdown->plaintext`](reference.md#markdown-plaintext) write.
  Before rendering, each works out the most its output could be.

The output limit takes the worst case, so it can refuse a document
whose output would have fit:

```lisp
(length (markdown->html "Hello, *world*!"))
;; => 30

(let ((*max-output-octets* 30))
  (markdown->html "Hello, *world*!"))
;; signals resource-limit-exceeded
```

To take a larger document, bind its limit higher with `let`: see
[Large documents](usage.md#large-documents). A binding above the hard
cap is held to the cap. `*max-nodes*` has no cap: raise it as far as
the machine's memory allows.

## The footnote guard

While footnotes are on, as they are by default, the library refuses
one pattern:

```lisp
(defparameter *caret* (concatenate 'string "[" "&#94;"))

(markdown->html *caret*)
;; signals unsupported-input
```

The pattern is a `[` right before an entity that decodes to `^`, such
as `&#94;`, `&#x5e;` or `&Hat;`. cmark-gfm 0.29.0.gfm.13 misreads it: it
reads memory it doesn't own, which can put stray bytes in its output, or
crash the process. So the library refuses such input before cmark-gfm
sees it, and signals
[`unsupported-input`](reference.md#unsupported-input). It refuses the
pattern anywhere, even in a code block, where cmark-gfm would read it
safely.

To parse such input, pass `:footnotes nil`, and do without footnotes:

```lisp
(markdown->html *caret* :footnotes nil)
;; => "<p>[^</p>\n"
```

The `:commonmark` profile turns footnotes off too.

## What remains

Two risks remain, beyond any Lisp check:
- On a machine already short of memory, cmark-gfm can still end the
  process, even within the limits. No Lisp handler can catch that.
- cmark-gfm may have other bugs in its parser. The footnote guard
  covers the one that is known.

## Threads and timeouts

Call the library from as many threads as you like. Each call gives the
result it would give alone. Threads parse in parallel, but take turns
for one step of each parse, since cmark-gfm keeps some state that every
thread shares.

Another binding of cmark-gfm in the same process doesn't take turns
with this library, so a parse of either can come out wrong.

On SBCL and CCL, a timeout, or any other interrupt, waits until the
current call into cmark-gfm returns. Waiting for a turn is part of the
call, and so is starting cmark-gfm, at the first call. So a timeout
can't cut a long call short. In exchange, no interrupt stops cmark-gfm
halfway, which could leave the thread stuck for good, or the C heap
broken. The size limits keep each call short.

On ECL, don't interrupt or time out a thread during a call. ECL can't
hold the interrupt back until the call returns, so it isn't safe.

## Libraries on CCL

On CCL, choose cmark-gfm's libraries before the first call: see
[Choosing the libraries yourself](installing.md#choosing-the-libraries-yourself).
A CCL process keeps the first pair it loads, even if starting cmark-gfm
then fails. Naming another pair after that signals
[`native-initialization-error`](reference.md#native-initialization-error),
and only a new process can load it. CCL can't unload a library, so a new
pair's calls could run the old pair's code.
