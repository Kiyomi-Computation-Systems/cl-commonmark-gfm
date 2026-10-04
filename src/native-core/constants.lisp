;;;; cmark-gfm's C constants, transcribed from
;;;; vendor/cmark-gfm/src/cmark-gfm.h. The project compiles no C, so no C
;;;; compiler checks them. tests/native-core.lisp evaluates the header text
;;;; independently and checks every value here against it, so a
;;;; transcription slip, or a pin bump that moves one, fails a test instead
;;;; of drifting silently.

(in-package #:cl-commonmark-gfm.native-core)

;;; The pin

(defparameter *cmark-gfm-version* "0.29.0.gfm.13"
  "The cmark-gfm release this library is pinned to, as cmark_version_string()
must return it. A DEFPARAMETER, not a DEFCONSTANT: a DEFCONSTANT of a
string isn't EQL to itself across a reload, which breaks a second LOAD of
this file.")

;;; Node types (vendor/cmark-gfm/src/cmark-gfm.h, lines 34-69).
;;; CMARK_NODE_TYPE_BLOCK and CMARK_NODE_TYPE_INLINE are themselves built
;;; from CMARK_NODE_TYPE_PRESENT; every cmark_node_type enumerator but
;;; CMARK_NODE_NONE ORs one of the two with a small per-kind value. The two
;;; tag constants stay internal: nothing outside this file needs them, only
;;; the 22 node-type constants they build.

(defconstant +cmark-node-type-block+ (logior #x8000 #x0000))
(defconstant +cmark-node-type-inline+ (logior #x8000 #x4000))

(defconstant +cmark-node-document+ (logior +cmark-node-type-block+ #x0001))
(defconstant +cmark-node-block-quote+ (logior +cmark-node-type-block+ #x0002))
(defconstant +cmark-node-list+ (logior +cmark-node-type-block+ #x0003))
(defconstant +cmark-node-item+ (logior +cmark-node-type-block+ #x0004))
(defconstant +cmark-node-code-block+ (logior +cmark-node-type-block+ #x0005))
(defconstant +cmark-node-html-block+ (logior +cmark-node-type-block+ #x0006))
(defconstant +cmark-node-custom-block+ (logior +cmark-node-type-block+ #x0007))
(defconstant +cmark-node-paragraph+ (logior +cmark-node-type-block+ #x0008))
(defconstant +cmark-node-heading+ (logior +cmark-node-type-block+ #x0009))
(defconstant +cmark-node-thematic-break+ (logior +cmark-node-type-block+ #x000a))
(defconstant +cmark-node-footnote-definition+ (logior +cmark-node-type-block+ #x000b))

(defconstant +cmark-node-text+ (logior +cmark-node-type-inline+ #x0001))
(defconstant +cmark-node-softbreak+ (logior +cmark-node-type-inline+ #x0002))
(defconstant +cmark-node-linebreak+ (logior +cmark-node-type-inline+ #x0003))
(defconstant +cmark-node-code+ (logior +cmark-node-type-inline+ #x0004))
(defconstant +cmark-node-html-inline+ (logior +cmark-node-type-inline+ #x0005))
(defconstant +cmark-node-custom-inline+ (logior +cmark-node-type-inline+ #x0006))
(defconstant +cmark-node-emph+ (logior +cmark-node-type-inline+ #x0007))
(defconstant +cmark-node-strong+ (logior +cmark-node-type-inline+ #x0008))
(defconstant +cmark-node-link+ (logior +cmark-node-type-inline+ #x0009))
(defconstant +cmark-node-image+ (logior +cmark-node-type-inline+ #x000a))
(defconstant +cmark-node-footnote-reference+ (logior +cmark-node-type-inline+ #x000b))

;;; Option bits (vendor/cmark-gfm/src/cmark-gfm.h, lines 695-769). The
;;; header defines more CMARK_OPT_ bits than this: SAFE and NORMALIZE,
;;; which have no effect, and GITHUB_PRE_LANG, LIBERAL_HTML_TAG,
;;; STRIKETHROUGH_DOUBLE_TILDE, TABLE_PREFER_STYLE_ATTRIBUTES and
;;; FULL_INFO_STRING. No entry point sets them, so they are left
;;; untranscribed rather than carried as dead constants.

(defconstant +cmark-opt-sourcepos+ (ash 1 1))
(defconstant +cmark-opt-hardbreaks+ (ash 1 2))
(defconstant +cmark-opt-nobreaks+ (ash 1 4))
(defconstant +cmark-opt-validate-utf8+ (ash 1 9))
(defconstant +cmark-opt-smart+ (ash 1 10))
(defconstant +cmark-opt-footnotes+ (ash 1 13))
(defconstant +cmark-opt-unsafe+ (ash 1 17))

;;; cmark_list_type and cmark_delim_type (vendor/cmark-gfm/src/cmark-gfm.h,
;;; lines 80-90). Both enums give their first entry, CMARK_NO_LIST or
;;; CMARK_NO_DELIM, the implicit value 0; this library never needs either
;;; "no" sentinel (a bullet list has no :DELIMITER, so nothing ever tests
;;; for CMARK_NO_DELIM), so only the other two values of each enum get a
;;; Lisp name.

(defconstant +cmark-bullet-list+ 1)
(defconstant +cmark-ordered-list+ 2)
(defconstant +cmark-period-delim+ 1)
(defconstant +cmark-paren-delim+ 2)

;;; *CMARK-HEADER-CONSTANTS*: every constant above, by its C name, for the
;;; header test in tests/native-core.lisp.

(defparameter *cmark-header-constants*
  (list (cons "CMARK_NODE_DOCUMENT" +cmark-node-document+)
        (cons "CMARK_NODE_BLOCK_QUOTE" +cmark-node-block-quote+)
        (cons "CMARK_NODE_LIST" +cmark-node-list+)
        (cons "CMARK_NODE_ITEM" +cmark-node-item+)
        (cons "CMARK_NODE_CODE_BLOCK" +cmark-node-code-block+)
        (cons "CMARK_NODE_HTML_BLOCK" +cmark-node-html-block+)
        (cons "CMARK_NODE_CUSTOM_BLOCK" +cmark-node-custom-block+)
        (cons "CMARK_NODE_PARAGRAPH" +cmark-node-paragraph+)
        (cons "CMARK_NODE_HEADING" +cmark-node-heading+)
        (cons "CMARK_NODE_THEMATIC_BREAK" +cmark-node-thematic-break+)
        (cons "CMARK_NODE_FOOTNOTE_DEFINITION" +cmark-node-footnote-definition+)
        (cons "CMARK_NODE_TEXT" +cmark-node-text+)
        (cons "CMARK_NODE_SOFTBREAK" +cmark-node-softbreak+)
        (cons "CMARK_NODE_LINEBREAK" +cmark-node-linebreak+)
        (cons "CMARK_NODE_CODE" +cmark-node-code+)
        (cons "CMARK_NODE_HTML_INLINE" +cmark-node-html-inline+)
        (cons "CMARK_NODE_CUSTOM_INLINE" +cmark-node-custom-inline+)
        (cons "CMARK_NODE_EMPH" +cmark-node-emph+)
        (cons "CMARK_NODE_STRONG" +cmark-node-strong+)
        (cons "CMARK_NODE_LINK" +cmark-node-link+)
        (cons "CMARK_NODE_IMAGE" +cmark-node-image+)
        (cons "CMARK_NODE_FOOTNOTE_REFERENCE" +cmark-node-footnote-reference+)
        (cons "CMARK_OPT_SOURCEPOS" +cmark-opt-sourcepos+)
        (cons "CMARK_OPT_HARDBREAKS" +cmark-opt-hardbreaks+)
        (cons "CMARK_OPT_NOBREAKS" +cmark-opt-nobreaks+)
        (cons "CMARK_OPT_VALIDATE_UTF8" +cmark-opt-validate-utf8+)
        (cons "CMARK_OPT_SMART" +cmark-opt-smart+)
        (cons "CMARK_OPT_FOOTNOTES" +cmark-opt-footnotes+)
        (cons "CMARK_OPT_UNSAFE" +cmark-opt-unsafe+)
        (cons "CMARK_BULLET_LIST" +cmark-bullet-list+)
        (cons "CMARK_ORDERED_LIST" +cmark-ordered-list+)
        (cons "CMARK_PERIOD_DELIM" +cmark-period-delim+)
        (cons "CMARK_PAREN_DELIM" +cmark-paren-delim+))
  "Every constant above, paired with its C name from
vendor/cmark-gfm/src/cmark-gfm.h, as (\"C_NAME\" . VALUE). The header test
evaluates the pinned header text independently of this file and checks each
pair here against it, so a transcription slip, or a pin bump that moves a
value, fails a test.

A DEFPARAMETER, not a DEFCONSTANT: a DEFCONSTANT of a list isn't EQL to
itself across a reload, which breaks a second LOAD of this file.")

;;; The five GFM extensions, in the canonical order an :EXTENSIONS list is
;;; checked and reported back in.

(defparameter *extension-keywords* '(:table :strikethrough :autolink :tagfilter :tasklist)
  "The five core GFM extensions cl-commonmark-gfm can attach, in their
canonical order: the order the :GFM profile attaches them, an explicit
:EXTENSIONS list is reported back in, and a :DOCUMENT node's :EXTENSIONS
attribute lists them in.

A DEFPARAMETER, not a DEFCONSTANT: a DEFCONSTANT of a list isn't EQL to
itself across a reload, which breaks a second LOAD of this file.")
