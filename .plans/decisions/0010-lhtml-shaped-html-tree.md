# ADR-0010: An LHTML-shaped HTML tree, not SXML; public `html-tree->string`

- **Status:** Accepted; amended by ADR-0014 (2026-09-27); amended
  2026-10-04, in M5a, by ADR-0022 and the
  [M5 spec](../2026-10-04-m5-documentation-design.md) D7 and §4: the
  serializer writes HTML's 13 void elements as void, where it wrote only
  the four cmark writes, `br`, `hr`, `img` and `input`. The nine new ones
  are `area`, `base`, `col`, `embed`, `link`, `meta`, `source`, `track`
  and `wbr`. Each of the 13 prints as `<tag ... />`, and signals
  `invalid-html-tree` when it has children. Trees from `ast->html-tree`
  don't change, since cmark writes only the four. `:document-wrapper`
  takes only a non-void element, so the nine new names are refused there
  too, with `invalid-render-option`. Before, they were accepted, and the
  wrapper printed with an end tag
- **Date:** 2026-09-27
- **Scope:** HTML tree format, serializer, `cl-commonmark-gfm/html-tree`
- **Spec:** [M0 close design](../2026-09-27-m0-close-design.md) §4.1, §4.2,
  §4.5
- **Related:** ADR-0011 (the oracle), ADR-0012 (render options)
- **Prior art:** chez-cmark-gfm ADR-0011 (the tree carries HTML vocabulary
  only)

## Context

The plan called the Lisp HTML projection "SXML". A survey on 2026-09-27
found that Common Lisp has no shared HTML-tree convention, and that SXML's
`@` marker does not survive the move from Scheme.

- **The package trap.** Scheme symbols are global. CL symbols belong to
  packages, so a bare `@` read in one package is not `eq` to one read in
  another, and the comparison fails silently. `cl-sxml`, the only SXML
  library in ocicl, interns `@` into the caller's package, and interns its
  comment nodes into whatever package is current at the time. It is
  GPL-licensed and documented as not working on ECL.
- **No consumer expects it.** The same fragment, in each library's format:
  - closure-html (LHTML): `(:p ((:class "x")) "hi " (:a ((:href "u")) "l"))`;
  - xmls: structs with string names;
  - Spinneret: `(:p :class "x" …)`, and it rejects `:@` as an unknown tag;
  - cl-who and hsx: compile-time macros only, no runtime trees.
- **LHTML is the nearest thing to a convention.** Attributes are always
  the second element, so every element destructures the same way.

## Decision

### Use the LHTML shape

- **Element:** `(tag attrs &rest children)`.
  - `tag` is a keyword.
  - `attrs` is `nil` or a list of `(:name "value")` two-element lists, in
    the order cmark emits them.
  - Each child is a string (text) or an element.
- **Omitted raw HTML** is `(:*comment* nil " raw HTML omitted ")`, the same
  three-part form.
- **Document:** a list of top-level nodes. `:document-wrapper` (an element
  keyword, default `nil`) wraps them as `(wrapper nil …)`.
- **No source positions and no `data-*` metadata** beyond what cmark's own
  HTML emits. Source positions live in the AST.
- Text is unescaped Lisp strings. Escaping is the serializer's job.

### Ship our own serializer: `html-tree->string`

A pure, public function from a tree (an element, or a list of nodes) to a
string.

- **cmark-exact on our trees.** Static tables of void elements and of where
  cmark puts newlines make its output equal cmark's HTML (ADR-0011).
- **Always escapes.** Text and attribute values are entity-escaped (`&`,
  `<`, `>`, `"`) exactly as houdini's HTML escaper does. Nothing is
  emitted raw.
- **Validates its input.** These signal `invalid-html-tree`, naming the
  offending node:
  - a tag or attribute name not matching `[a-z][a-z0-9-]*`, so a keyword
    can never smuggle in markup (e.g. a name containing `onclick="…"`);
  - a non-string attribute value;
  - comment text containing `--`;
  - a malformed element.
- **Unknown but valid tags are allowed** and print inline. Custom elements
  are legitimate.
- **It does not sanitize URLs.** `:link-policy` applies inside
  `ast->html-tree` (ADR-0012). A URL a user adds to the tree afterwards is
  escaped but not checked. The user docs say so.

### Rejected

- **SXML:** the package trap above, and no CL consumer reads it.
- **Spinneret's format:** it would tie our contract to Spinneret's parsing
  and output, which re-indents content.
- **Serializing LHTML with closure-html:** it prints HTML 4 style (`<P>`,
  `<BR>`) and cannot represent comments.

## Consequences

- The plan renames SXML to "HTML tree": system
  `cl-commonmark-gfm/html-tree`; API `ast->html-tree`,
  `markdown->html-tree`, `html-tree->string`.
- `invalid-html-tree` joins the plan's conditions.
- Every element destructures the same way: tag, attrs, children.
- The serializer is the one the oracle tests, so users get the tested one.
- Anything a user adds to a tree is escaped and name-checked, but its URLs
  are the user's responsibility.
- Adapters to other formats (SXML, Spinneret, xmls) are out of scope.
