;;;; Conditions signalled by cl-commonmark-gfm (M1 design §3; extended for
;;;; the native layer by M2 design §7.4).

(defpackage #:cl-commonmark-gfm.conditions
  (:use #:cl)
  (:export #:commonmark-gfm-error
           #:condition-operation
           #:condition-datum
           #:condition-reason
           #:invalid-ast-node
           #:invalid-option
           #:invalid-parse-option
           #:invalid-render-option
           #:invalid-html-tree
           #:unsupported-extension-node
           #:resource-limit-exceeded
           #:condition-limit
           #:condition-maximum
           #:unsupported-input
           #:native-error
           #:native-library-not-found
           #:condition-override
           #:condition-paths
           #:native-abi-mismatch
           #:condition-expected-version
           #:condition-found-version
           #:dynamic-ffi-unavailable
           #:native-initialization-error
           #:native-parse-error
           #:native-render-error))

(in-package #:cl-commonmark-gfm.conditions)

;;; Report

(defun report-commonmark-gfm-error (condition stream)
  "Print CONDITION to STREAM as \"operation: reason: datum\". Binds the
printer so a pathological :DATUM -- a rejected circular list, or simply a
very long one -- prints safely instead of hanging or exhausting memory:
*PRINT-CIRCLE* lets a circular DATUM print at all, *PRINT-LENGTH*
and *PRINT-LEVEL* bound it, and *PRINT-READABLY* is off since ~S need not
round-trip here."
  (let ((*print-circle* t)
        (*print-length* 10)
        (*print-level* 4)
        (*print-readably* nil))
    (format stream "~(~A~): ~A: ~S"
            (condition-operation condition)
            (condition-reason condition)
            (condition-datum condition))))

;;; Base condition

(define-condition commonmark-gfm-error (error)
  ((operation :reader condition-operation
              :initarg :operation
              :initform nil
              :documentation "The symbol naming the operation that failed.")
   (datum :reader condition-datum
          :initarg :datum
          :initform nil
          :documentation "The offending value.")
   (reason :reader condition-reason
           :initarg :reason
           :initform nil
           :documentation "A short phrase describing what is wrong with the datum."))
  (:report report-commonmark-gfm-error)
  (:documentation "Base condition for every error cl-commonmark-gfm signals."))

;;; DEFINE-CONDITION's :READER option documents the slot, not the reader
;;; function it generates, so the three readers get their own docstrings here.

(setf (documentation 'condition-operation 'function)
      "Return CONDITION's operation: the symbol naming what failed.")

(setf (documentation 'condition-datum 'function)
      "Return CONDITION's datum: the offending value.")

(setf (documentation 'condition-reason 'function)
      "Return CONDITION's reason: a short phrase describing what is wrong with
the datum.")

;;; M1 subtypes

(define-condition invalid-ast-node (commonmark-gfm-error) ()
  (:documentation
   "Signalled by MAKE-NODE, COPY-NODE, NODE-ATTRIBUTE and TRANSFORM-AST when
a node fails schema validation."))

(define-condition invalid-html-tree (commonmark-gfm-error) ()
  (:documentation
   "Signalled by HTML-TREE->STRING for a malformed HTML tree."))

(define-condition unsupported-extension-node (commonmark-gfm-error) ()
  (:documentation
   "Signalled by AST->HTML-TREE for an :EXTENSION node."))

;;; Option conditions (M2 design §7.2, §7.4, D16)

(define-condition invalid-option (commonmark-gfm-error) ()
  (:documentation
   "Parent of INVALID-PARSE-OPTION and INVALID-RENDER-OPTION. Not signalled
directly."))

(define-condition invalid-parse-option (invalid-option) ()
  (:documentation
   "Signalled by PARSE for any malformed, unknown or out-of-range option, and
by MARKDOWN->HTML, MARKDOWN->PLAINTEXT and MARKDOWN->HTML-TREE for a bad
:PROFILE, :EXTENSIONS, :FOOTNOTES, :SMART or :SOURCEPOS value (M2 design
§7.2)."))

(define-condition invalid-render-option (invalid-option) ()
  (:documentation
   "Signalled by AST->HTML-TREE for a malformed or unknown rendering option
(M1 design §5; ADR-0012). Also signalled by MARKDOWN->HTML,
MARKDOWN->PLAINTEXT and MARKDOWN->HTML-TREE for any option problem that
isn't INVALID-PARSE-OPTION's: an unknown key, an odd-length option list, or
a bad non-parse value (M2 design §7.2). M1's condition; now a subtype of
INVALID-OPTION."))

;;; Resource limits (M2 design §5.5, §7.4, D10)

(define-condition resource-limit-exceeded (commonmark-gfm-error)
  ((limit :reader condition-limit
          :initarg :limit
          :initform nil
          :documentation "The symbol naming the special variable whose limit was exceeded.")
   (maximum :reader condition-maximum
            :initarg :maximum
            :initform nil
            :documentation
            "The effective maximum that applied: LIMIT's value, or its hard
cap when that is lower."))
  (:documentation
   "Signalled when a value exceeds one of the three limits of M2 design §5.5:
*MAX-INPUT-OCTETS*, *MAX-NODES* or *MAX-OUTPUT-OCTETS*. DATUM is the value
found; REASON says when the hard cap applied."))

(setf (documentation 'condition-limit 'function)
      "Return CONDITION's limit: the symbol naming the special variable whose
limit was exceeded.")

(setf (documentation 'condition-maximum 'function)
      "Return CONDITION's maximum: the effective maximum that applied,
LIMIT's value or its hard cap when that is lower.")

;;; The input guard (M2 design §5.6, §7.4; finding 16; M2b plan Task 9b)

(define-condition unsupported-input (commonmark-gfm-error) ()
  (:documentation
   "Signalled by the four entry points' shared input guard when MARKDOWN
holds a [ immediately followed by an entity that decodes to ^ (U+005E),
while footnotes are on: cmark-gfm 0.29.0.gfm.13's footnote branch
(handle_close_bracket, vendor/cmark-gfm/src/inlines.c) copies such a
reference's label past the end of the entity's own short-lived buffer,
then frees that buffer while the label still points into it (M2 design
§5.6, finding 16). DATUM is the index in MARKDOWN of the [ that starts the
pattern; REASON names the pattern."))

;;; Native-layer conditions (M2 design §5.2, §5.4, §6.3, §7.4, D16)

(define-condition native-error (commonmark-gfm-error) ()
  (:documentation
   "Parent of NATIVE-LIBRARY-NOT-FOUND, NATIVE-ABI-MISMATCH,
DYNAMIC-FFI-UNAVAILABLE, NATIVE-INITIALIZATION-ERROR, NATIVE-PARSE-ERROR and
NATIVE-RENDER-ERROR. Not signalled directly."))

(define-condition native-library-not-found (native-error)
  ((override :reader condition-override
             :initarg :override
             :initform nil
             :documentation
             "The override value in effect when the search that failed was
using one: *CMARK-GFM-LIBRARIES*' value, or CL_COMMONMARK_GFM_LIBS' when
that was used instead. NIL when it was the ordinary directory search.")
   (paths :reader condition-paths
          :initarg :paths
          :initform nil
          :documentation "The directories searched, or the one path that failed to load."))
  (:documentation
   "Signalled when RESOLVE-CMARK-LIBRARIES cannot find the pinned cmark-gfm
pair, or when loading a resolved path fails (M2 design §5.2 steps 2 and 3).
PATHS lists the directories searched, or the one path that failed to load."))

(define-condition native-abi-mismatch (native-error)
  ((expected-version :reader condition-expected-version
                      :initarg :expected-version
                      :initform nil
                      :documentation "The cmark-gfm version string this library is pinned to.")
   (found-version :reader condition-found-version
                  :initarg :found-version
                  :initform nil
                  :documentation "The version string CMARK_VERSION_STRING actually returned.")
   (paths :reader condition-paths
          :initarg :paths
          :initform nil
          :documentation
          "The library paths that were loaded when the mismatched version was found, or
:LINKED in a linked program, which loads none (M4 design §6.1)."))
  (:documentation
   "Signalled when the loaded library's CMARK_VERSION_STRING isn't the pinned
cmark-gfm version, or when checking it signals any other error from the
loaded libraries, such as a missing function (M2 design §5.2 step 4)."))

(define-condition dynamic-ffi-unavailable (native-error) ()
  (:documentation
   "Signalled on an ECL built without dynamic FFI (:DFFI) whose native layer
isn't linked, at startup's first step, before discovery and before
anything loads (M2 design §5.2 step 1; M4 design §6.2): on such an ECL,
CFFI refuses to load a library at run time, so startup can't load the
pinned pair (M4 finding 29). DATUM is the missing feature, :DFFI;
REASON says how to link cmark-gfm into a program instead: compile with
CFFI-SYS:*CFFI-ECL-METHOD* set to :C/C++, and link
libcmark-gfm-extensions.a and libcmark-gfm.a. A linked program's startup
loads nothing, and never signals it (M4 design §6.1)."))

(define-condition native-initialization-error (native-error) ()
  (:documentation
   "Signalled when starting the native layer fails after its libraries load:
a missing GFM extension, a null allocator free pointer, a failed smoke parse
(a null root included), or any other error from the loaded libraries during
those steps (M2 design §5.2 steps 5 to 8). On CCL, also signalled in two
cases once both libraries load (M4 design §5.3): for any error while
recording the pair, such as a truename that can't be read, DATUM then the
original error; and when a startup loads a pair other than the one the
process loaded first, which CCL can't unload, DATUM then the refused pair's
truenames, and REASON naming the process's pair."))

(define-condition native-parse-error (native-error) ()
  (:documentation
   "Signalled when cmark-gfm's parser returns a null root, when a node
accessor that never returns null for the kinds it serves does anyway, or
when the copier meets a footnote reference with no definition or a table
cell whose column has no entry in its table's alignments (M2 design §5.1,
§5.4, §6.3)."))

(define-condition native-render-error (native-error) ()
  (:documentation
   "Signalled when one of cmark-gfm's renderers returns a null buffer (M2
design §5.4)."))

;;; DEFINE-CONDITION's :READER option documents the slot, not the reader
;;; function it generates, so the new readers get their own docstrings here
;;; too. CONDITION-PATHS is shared by two sibling conditions, so it gets one
;;; docstring covering both.

(setf (documentation 'condition-override 'function)
      "Return CONDITION's override: the override value in effect when the
search that failed was using one -- *CMARK-GFM-LIBRARIES*' value, or
CL_COMMONMARK_GFM_LIBS' when that was used instead -- or NIL when it was the
ordinary directory search.")

(setf (documentation 'condition-paths 'function)
      "Return CONDITION's paths: the directories searched, the one path that
failed to load, or the library paths involved, depending on CONDITION's
type. In a linked program, which loads no library, NATIVE-ABI-MISMATCH's
are :LINKED (M4 design §6.1).")

(setf (documentation 'condition-expected-version 'function)
      "Return CONDITION's expected-version: the cmark-gfm version string this
library is pinned to.")

(setf (documentation 'condition-found-version 'function)
      "Return CONDITION's found-version: the version string
CMARK_VERSION_STRING actually returned.")
