# Security policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Please report a suspected vulnerability privately, through GitHub:
**Security → Report a vulnerability** on this repository. Don't open a
public issue. You can expect a reply within 7 days.

The library binds a C library and renders untrusted Markdown, so these
reports are especially welcome:
- **the native boundary:** memory safety, the lifetime of cmark-gfm's
  objects, and the values passed to it;
- **the rendering policy:**
  - raw HTML, or a dangerous URL, that gets through `markdown->html`
    without `:unsafe-html t`. [Safe by
    default](docs/safety.md#safe-by-default) says which URLs are
    dangerous;
  - raw HTML as markup in any HTML tree;
  - a dangerous URL in a tree from `markdown->html-tree` or
    `ast->html-tree` without `:link-policy :unsafe`;
  - text or an attribute value that `html-tree->string` writes as
    markup;
- **the size limits:** input that gets past `*max-input-octets*`,
  `*max-nodes*` or `*max-output-octets*`, and makes cmark-gfm end the
  process;
- **the footnote guard:** input that makes cmark-gfm read memory it
  doesn't own while footnotes are on.

Please say which system and Lisp you use, with their versions, and how
you installed cmark-gfm. If you named its libraries yourself, with
`*cmark-gfm-libraries*` or `CL_COMMONMARK_GFM_LIBS`, give the paths.

## What isn't a vulnerability

[Safety](docs/safety.md) says what the library guards and what remains.
These are by design:
- **An AST keeps raw HTML and every URL** as written. `parse` doesn't
  clean anything: the safe defaults govern what the renderers write.
- **Opting out is unsafe.** `:unsafe-html t` and `:link-policy :unsafe`
  are for Markdown you trust.
- **A URL you add to an HTML tree yourself** isn't checked.
- **cmark-gfm can end a process already short of memory,** even within
  the limits: see [What remains](docs/safety.md#what-remains).
- **Interrupting a call on ECL isn't safe:** see [Threads and
  timeouts](docs/safety.md#threads-and-timeouts).
- **Another binding of cmark-gfm in the same process** can make a parse
  come out wrong: see [Other code that loads
  cmark-gfm](docs/installing.md#other-code-that-loads-cmark-gfm).
