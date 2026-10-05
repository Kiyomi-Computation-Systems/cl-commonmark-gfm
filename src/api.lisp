;;;; The cl-commonmark-gfm package: the public API. One package for a
;;;; caller: it re-exports the public symbols of the conditions, the AST
;;;; and the HTML tree, and four variables of /native-core, and holds the
;;;; entry points. Each entry point checks its argument and its options,
;;;; and runs CHECK-INPUT's limits and input guard, before any native call.
;;;; It then starts cmark-gfm if it hasn't started, and holds its state
;;;; until the document is released, so cmark-gfm is never closed under the
;;;; parse: RESET-NATIVE-STATE, which the save hook calls before an image
;;;; is saved, refuses while any call holds the state.

(uiop:define-package #:cl-commonmark-gfm
  (:use #:cl)
  (:use-reexport #:cl-commonmark-gfm.conditions
                 #:cl-commonmark-gfm.ast
                 #:cl-commonmark-gfm.html-tree)
  (:import-from #:cl-commonmark-gfm.native-core
                #:*max-input-octets*
                #:*max-nodes*
                #:*max-output-octets*
                #:*cmark-gfm-libraries*
                #:check-options
                #:effective-maximum
                #:check-limit
                #:table-cell-bound
                #:checked-tree-options
                #:checked-footnotes
                #:footnote-entity-index)
  (:import-from #:cl-commonmark-gfm.util
                #:utf8-length)
  (:import-from #:cl-commonmark-gfm.native
                #:with-native-state
                #:with-native-document
                #:copy-native-tree
                #:render-html
                #:render-plaintext
                #:html-output-bound
                #:plaintext-output-bound)
  ;; CHECK-TREE-OPTIONS is internal to .HTML-TREE: it isn't exported, so
  ;; :USE-REEXPORT above never reaches it. MARKDOWN->HTML-TREE imports it by
  ;; name to validate its own tree options, with AST->HTML-TREE's own rules,
  ;; before any native call, so the rules for :RAW-HTML, :SOFTBREAK,
  ;; :LINK-POLICY and :DOCUMENT-WRAPPER stay in one place.
  (:import-from #:cl-commonmark-gfm.html-tree
                #:check-tree-options)
  (:export #:*max-input-octets*
           #:*max-nodes*
           #:*max-output-octets*
           #:*cmark-gfm-libraries*
           #:parse
           #:markdown->html
           #:markdown->plaintext
           #:markdown->html-tree))

(in-package #:cl-commonmark-gfm)

;;; The input limits and guard, shared by every entry point

(defparameter *limit-variables* '(*max-input-octets* *max-nodes* *max-output-octets*)
  "The three limits' variables, whose bindings CHECK-INPUT checks first.")

(defun check-input (markdown checked-options operation)
  "Apply the limits and the input guard that guard cmark's parse to
MARKDOWN, a string, naming OPERATION, the caller's entry point, with its
already-checked CHECKED-OPTIONS. cmark aborts the process, which no Lisp
handler can catch, when a buffer would pass 1,073,741,823 bytes or an
allocation fails; the three limits keep its buffers under that size and
bound its memory. Called before any native call:
- all three limit variables' bindings, first, whether or not OPERATION
  uses the limit: a bad one signals before any work, not after a parse;
- MARKDOWN's UTF-8 length against *MAX-INPUT-OCTETS*, measured before
  anything is encoded;
- MARKDOWN's table-cell bound against *MAX-NODES*: padded table cells are
  built while cmark parses, so a count taken later would come too late;
- while CHECKED-OPTIONS' footnotes are on, MARKDOWN against the guard's
  pattern: a [ immediately followed by an entity that decodes to ^. With
  footnotes on, cmark-gfm 0.29.0.gfm.13's handle_close_bracket
  (vendor/cmark-gfm/src/inlines.c) points such a reference's label into
  the entity's own short-lived buffer, with a length counted in source
  columns that runs past the buffer's end, then frees that buffer while
  the label still points into it -- a heap read no Lisp handler can
  catch, so this input is rejected instead of parsed. With footnotes off,
  cmark never takes that footnote branch, so the guard doesn't run.

Signals a TYPE-ERROR when any limit variable isn't bound to a
non-negative integer, RESOURCE-LIMIT-EXCEEDED for a breach of either
limit, and UNSUPPORTED-INPUT for a match of the guard's pattern -- its
datum the index of the [ that starts it."
  (dolist (variable *limit-variables*)
    (effective-maximum variable))
  (check-limit '*max-input-octets* (utf8-length markdown) operation)
  (check-limit '*max-nodes* (table-cell-bound markdown) operation)
  (when (checked-footnotes checked-options)
    (let ((index (footnote-entity-index markdown)))
      (when index
        (error 'unsupported-input
               :operation operation
               :datum index
               :reason (concatenate 'string "[ followed by an entity decoding to ^, which "
                                    "cmark-gfm 0.29.0.gfm.13 misreads")))))
  nil)

;;; PARSE

(defun parse (markdown &rest options)
  "Parse MARKDOWN, a string, with cmark-gfm, and return its AST: a :DOCUMENT
node holding Lisp data only, valid for as long as it is kept.

OPTIONS is a plist. When a key repeats, the leftmost value wins, but every
value must be valid.
- :PROFILE: :GFM, the default, or :COMMONMARK. A profile only supplies the
  defaults of :EXTENSIONS and :FOOTNOTES.
- :EXTENSIONS: the syntax extensions to attach, a list of distinct
  keywords from :TABLE, :STRIKETHROUGH, :AUTOLINK, :TAGFILTER and
  :TASKLIST, in any order. Defaults to all five under :GFM, and to none
  under :COMMONMARK.
- :FOOTNOTES: T or NIL. Defaults to T under :GFM, and to NIL under
  :COMMONMARK.
- :SMART: NIL, the default, or T for curly quotes, dashes and ellipses.
- :SOURCEPOS: T, the default, gives each node its position: a cons of its
  start and its end, each a cons of a line and a column, with columns
  counted in UTF-8 octets, as cmark-gfm reports them. A node cmark-gfm has
  no position for, such as a softbreak, gets NIL. With NIL, every node gets
  NIL.

The document node's attributes record the profile, the extensions
attached and the options on. A NUL character, and a lone surrogate, reach
the AST as U+FFFD.

Signals a TYPE-ERROR when MARKDOWN isn't a string, and
INVALID-PARSE-OPTION for any bad option, before cmark-gfm runs.

Signals RESOURCE-LIMIT-EXCEEDED for input past *MAX-INPUT-OCTETS* or
*MAX-NODES*, UNSUPPORTED-INPUT for input cmark-gfm can't parse safely, and
a NATIVE-ERROR when cmark-gfm fails to load or to run.
*CMARK-GFM-LIBRARIES* says where it is loaded from."
  (check-type markdown string)
  (let ((checked-options (check-options :parse 'parse options)))
    (check-input markdown checked-options 'parse)
    (with-native-state (state)
      (with-native-document (document markdown checked-options :state state)
        (copy-native-tree document checked-options 'parse)))))

;;; MARKDOWN->HTML

(defun markdown->html (markdown &rest options)
  "Render MARKDOWN, a string, to HTML with cmark-gfm's own HTML renderer, and
return the result as a string.

OPTIONS is a plist. When a key repeats, the leftmost value wins, but every
value must be valid.
- :PROFILE: :GFM, the default, or :COMMONMARK. A profile only supplies the
  defaults of :EXTENSIONS and :FOOTNOTES.
- :EXTENSIONS: the syntax extensions to attach, a list of distinct
  keywords from :TABLE, :STRIKETHROUGH, :AUTOLINK, :TAGFILTER and
  :TASKLIST, in any order. Defaults to all five under :GFM, and to none
  under :COMMONMARK.
- :FOOTNOTES: T or NIL. Defaults to T under :GFM, and to NIL under
  :COMMONMARK.
- :SMART: NIL, the default, or T for curly quotes, dashes and ellipses.
- :SOURCEPOS: NIL, the default, or T to add each element's position as a
  data-sourcepos attribute.
- :SOFTBREAK: :NEWLINE, the default, writes a newline; :SPACE writes a
  space; :BR writes \"<br />\" then a newline.
- :UNSAFE-HTML: NIL, the default, writes a comment in place of raw HTML
  (\"<!-- raw HTML omitted -->\") and blanks dangerous URLs; T keeps both,
  as cmark-gfm's own CMARK_OPT_UNSAFE does, though :TAGFILTER, when
  attached (the :GFM default), still escapes a few tags, such as
  \"<script>\".

Signals a TYPE-ERROR when MARKDOWN isn't a string; INVALID-PARSE-OPTION for
a bad :PROFILE, :EXTENSIONS, :FOOTNOTES, :SMART or :SOURCEPOS value; and
INVALID-RENDER-OPTION for everything else -- an odd-length option list, an
unknown key, or a bad :SOFTBREAK or :UNSAFE-HTML value -- before cmark-gfm
runs.

Signals RESOURCE-LIMIT-EXCEEDED for input past *MAX-INPUT-OCTETS* or
*MAX-NODES*, or output that could pass *MAX-OUTPUT-OCTETS*;
UNSUPPORTED-INPUT for input cmark-gfm can't parse safely; and a
NATIVE-ERROR when cmark-gfm fails to load or to run. *CMARK-GFM-LIBRARIES*
says where it is loaded from."
  (check-type markdown string)
  (let ((checked-options (check-options :html 'markdown->html options)))
    (check-input markdown checked-options 'markdown->html)
    (with-native-state (state)
      (with-native-document (document markdown checked-options :state state)
        (check-limit '*max-output-octets*
                     (html-output-bound document checked-options markdown 'markdown->html)
                     'markdown->html)
        (values (render-html document checked-options))))))

;;; MARKDOWN->PLAINTEXT

(defun markdown->plaintext (markdown &rest options)
  "Render MARKDOWN, a string, to plain text with cmark-gfm's own plaintext
renderer, and return the result as a string.

OPTIONS is a plist. When a key repeats, the leftmost value wins, but every
value must be valid.
- :PROFILE, :EXTENSIONS, :FOOTNOTES and :SMART: as PARSE.
- :SOFTBREAK: :NEWLINE, the default, writes a newline in place of a
  softbreak, but a space inside a heading, or wherever :WIDTH is above 0,
  where a line can wrap at it. :BR writes a newline everywhere, and turns
  :WIDTH off for the whole text: nothing wraps. :SPACE writes a space, and
  turns wrapping off too.
- :WIDTH: 0, the default, for no wrapping, or a column from 1 to
  2,147,483,647 to wrap text at. It wraps only under :SOFTBREAK :NEWLINE,
  never inside a heading.

This entry point parses without source positions: :SOURCEPOS isn't one of
its options.

Signals a TYPE-ERROR when MARKDOWN isn't a string; INVALID-PARSE-OPTION for
a bad :PROFILE, :EXTENSIONS, :FOOTNOTES or :SMART value; and
INVALID-RENDER-OPTION for everything else -- an odd-length option list, an
unknown key, or a bad :SOFTBREAK or :WIDTH value -- before cmark-gfm runs.

Signals RESOURCE-LIMIT-EXCEEDED for input past *MAX-INPUT-OCTETS* or
*MAX-NODES*, or output that could pass *MAX-OUTPUT-OCTETS*;
UNSUPPORTED-INPUT for input cmark-gfm can't parse safely; and a
NATIVE-ERROR when cmark-gfm fails to load or to run. *CMARK-GFM-LIBRARIES*
says where it is loaded from."
  (check-type markdown string)
  (let ((checked-options (check-options :plaintext 'markdown->plaintext options)))
    (check-input markdown checked-options 'markdown->plaintext)
    (with-native-state (state)
      (with-native-document (document markdown checked-options :state state)
        (check-limit '*max-output-octets*
                     (plaintext-output-bound document checked-options 'markdown->plaintext)
                     'markdown->plaintext)
        (values (render-plaintext document checked-options))))))

;;; MARKDOWN->HTML-TREE

(defun markdown->html-tree (markdown &rest options)
  "Render MARKDOWN, a string, into an HTML tree: (AST->HTML-TREE (PARSE
MARKDOWN ...) ...), without building a detached AST the caller keeps.

OPTIONS is a plist. When a key repeats, the leftmost value wins, but every
value must be valid.
- :PROFILE, :EXTENSIONS, :FOOTNOTES and :SMART: as PARSE.
- :SOFTBREAK: :NEWLINE, the default, writes a newline; :SPACE writes a
  space; :BR writes a (:BR NIL) element, then a newline.
- :RAW-HTML: :OMIT, the default, writes the comment MARKDOWN->HTML writes
  in place of raw HTML; :TEXT writes the raw HTML as text.
- :LINK-POLICY: :SAFE, the default, blanks dangerous URLs, as
  MARKDOWN->HTML does by default; :UNSAFE keeps them.
- :DOCUMENT-WRAPPER: NIL, the default, or a keyword naming a non-void
  element (see HTML-TREE->STRING), to wrap the whole tree in.
The last four, the tree options, are AST->HTML-TREE's own.

This entry point parses without source positions: :SOURCEPOS isn't one of
its options, since the tree carries none.

Signals a TYPE-ERROR when MARKDOWN isn't a string; INVALID-PARSE-OPTION for
a bad :PROFILE, :EXTENSIONS, :FOOTNOTES or :SMART value; and
INVALID-RENDER-OPTION for everything else -- an odd-length option list, an
unknown key, or a bad :SOFTBREAK, :RAW-HTML, :LINK-POLICY or
:DOCUMENT-WRAPPER value -- before cmark-gfm runs.

Signals RESOURCE-LIMIT-EXCEEDED for input past *MAX-INPUT-OCTETS* or
*MAX-NODES*, UNSUPPORTED-INPUT for input cmark-gfm can't parse safely, and
a NATIVE-ERROR when cmark-gfm fails to load or to run.
*CMARK-GFM-LIBRARIES* says where it is loaded from."
  (check-type markdown string)
  (let* ((checked-options (check-options :html-tree 'markdown->html-tree options))
         (tree-options (checked-tree-options checked-options)))
    (check-tree-options tree-options 'markdown->html-tree)
    (check-input markdown checked-options 'markdown->html-tree)
    (let ((ast (with-native-state (state)
                 (with-native-document (document markdown checked-options :state state)
                   (copy-native-tree document checked-options 'markdown->html-tree)))))
      (apply #'ast->html-tree ast tree-options))))
