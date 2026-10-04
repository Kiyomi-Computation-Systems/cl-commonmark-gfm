;;;; The conditions cl-commonmark-gfm signals. Each is a
;;;; COMMONMARK-GFM-ERROR, which names the operation that failed, the
;;;; offending datum and the reason, and reports as "operation: reason:
;;;; datum".

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

;;; ASTs and HTML trees

(define-condition invalid-ast-node (commonmark-gfm-error) ()
  (:documentation
   "Signalled by MAKE-NODE and COPY-NODE when a node fails schema
validation, by NODE-ATTRIBUTE for a key its node's kind lacks, and by
TRANSFORM-AST when its function returns anything but a node, a list of
nodes or NIL, or the root doesn't come back as exactly one node."))

(define-condition invalid-html-tree (commonmark-gfm-error) ()
  (:documentation
   "Signalled by HTML-TREE->STRING for a malformed HTML tree."))

(define-condition unsupported-extension-node (commonmark-gfm-error) ()
  (:documentation
   "Signalled by AST->HTML-TREE for an :EXTENSION node."))

;;; Options

(define-condition invalid-option (commonmark-gfm-error) ()
  (:documentation
   "Parent of INVALID-PARSE-OPTION and INVALID-RENDER-OPTION. Not signalled
directly."))

(define-condition invalid-parse-option (invalid-option) ()
  (:documentation
   "Signalled by PARSE for any malformed, unknown or out-of-range option, and
by MARKDOWN->HTML, MARKDOWN->PLAINTEXT and MARKDOWN->HTML-TREE for a bad
:PROFILE, :EXTENSIONS, :FOOTNOTES, :SMART or :SOURCEPOS value."))

(define-condition invalid-render-option (invalid-option) ()
  (:documentation
   "Signalled by AST->HTML-TREE for a malformed or unknown rendering option,
and by MARKDOWN->HTML, MARKDOWN->PLAINTEXT and MARKDOWN->HTML-TREE for any
option problem that isn't INVALID-PARSE-OPTION's: an unknown key, an
odd-length option list, or a bad non-parse value."))

;;; Resource limits

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
   "Signalled when a value exceeds one of the three limits,
*MAX-INPUT-OCTETS*, *MAX-NODES* or *MAX-OUTPUT-OCTETS*. DATUM is the value
found; REASON says when the hard cap applied."))

(setf (documentation 'condition-limit 'function)
      "Return CONDITION's limit: the symbol naming the special variable whose
limit was exceeded.")

(setf (documentation 'condition-maximum 'function)
      "Return CONDITION's maximum: the effective maximum that applied,
LIMIT's value or its hard cap when that is lower.")

;;; The input guard

(define-condition unsupported-input (commonmark-gfm-error) ()
  (:documentation
   "Signalled by PARSE, MARKDOWN->HTML, MARKDOWN->PLAINTEXT and
MARKDOWN->HTML-TREE, with footnotes on, when MARKDOWN holds a [
immediately followed by an entity that decodes to ^ (U+005E). cmark-gfm
0.29.0.gfm.13 can't parse that safely: its footnote code
(handle_close_bracket, vendor/cmark-gfm/src/inlines.c) points such a
reference's label into the entity's own short-lived buffer, with a length
counted in source columns that runs past the buffer's end, then frees that
buffer while the label still points into it. So the input is rejected
before cmark-gfm sees it. DATUM is the index in MARKDOWN of the [ that
starts the pattern; REASON names the pattern."))

;;; The native layer

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
          :documentation
          "The directories searched; the one path that isn't a regular file or
failed to load; or NIL for a malformed override."))
  (:documentation
   "Signalled when starting cmark-gfm can't find the pinned version's two
libraries, libcmark-gfm and libcmark-gfm-extensions, when an override that
names them is malformed, or when loading one of them fails. PATHS lists
the directories searched; holds the one path that isn't a regular file or
failed to load; or is NIL for a malformed override."))

(define-condition native-abi-mismatch (native-error)
  ((expected-version :reader condition-expected-version
                      :initarg :expected-version
                      :initform nil
                      :documentation "The cmark-gfm version string this library is pinned to.")
   (found-version :reader condition-found-version
                  :initarg :found-version
                  :initform nil
                  :documentation
                  "The version the loaded cmark-gfm reported, or NIL when reading it failed.")
   (paths :reader condition-paths
          :initarg :paths
          :initform nil
          :documentation
          "The library paths that were loaded when the mismatched version was found, or
:LINKED in a linked program, which loads none."))
  (:documentation
   "Signalled when the loaded cmark-gfm isn't the pinned version, by the
string cmark_version_string() returns or by cmark_version()'s number, or
when checking it signals any other error from the loaded libraries, such as
a missing function."))

(define-condition dynamic-ffi-unavailable (native-error) ()
  (:documentation
   "Signalled on an ECL built without dynamic FFI (no :DFFI feature) when
cmark-gfm isn't linked into the program: such an ECL can't load a library
at run time. Starting cmark-gfm signals it first, before looking for or
loading anything. DATUM is the missing feature, :DFFI; REASON says how to
link cmark-gfm into a program instead: compile with
CFFI-SYS:*CFFI-ECL-METHOD* set to :C/C++, and link
libcmark-gfm-extensions.a and libcmark-gfm.a. A program with cmark-gfm
linked in loads nothing, and never signals it."))

(define-condition native-initialization-error (native-error) ()
  (:documentation
   "Signalled when starting cmark-gfm fails after its libraries load: a
missing GFM extension, a null allocator free pointer, a failed smoke parse
(a null root included), or any other error from the loaded libraries during
those steps. Also signalled on CCL, which can't unload a library, so a
process keeps the first pair of cmark-gfm libraries it loads: when a later
startup loads a different pair, DATUM then the refused pair's truenames and
REASON naming the process's pair; and for any error while recording a
pair, such as a truename that can't be read, DATUM then the original
error."))

(define-condition native-parse-error (native-error) ()
  (:documentation
   "Signalled when cmark-gfm's parser returns a null root, when a node
accessor that never returns null for the kinds it serves does anyway, or
when the copier meets a footnote reference with no definition or a table
cell whose column has no entry in its table's alignments."))

(define-condition native-render-error (native-error) ()
  (:documentation
   "Signalled when one of cmark-gfm's renderers returns a null buffer."))

;;; As above, the readers get their own docstrings. CONDITION-PATHS is
;;; shared by two sibling conditions, so its docstring covers both.

(setf (documentation 'condition-override 'function)
      "Return CONDITION's override: the override value in effect when the
search that failed was using one -- *CMARK-GFM-LIBRARIES*' value, or
CL_COMMONMARK_GFM_LIBS' when that was used instead -- or NIL when it was the
ordinary directory search.")

(setf (documentation 'condition-paths 'function)
      "Return CONDITION's paths: the directories searched, the one path that
isn't a regular file or failed to load, NIL for a malformed override, or
the library paths involved, depending on CONDITION's type. In a linked
program, which loads no library, NATIVE-ABI-MISMATCH's are :LINKED.")

(setf (documentation 'condition-expected-version 'function)
      "Return CONDITION's expected-version: the cmark-gfm version string this
library is pinned to.")

(setf (documentation 'condition-found-version 'function)
      "Return CONDITION's found-version: the version the loaded cmark-gfm
reported, or NIL when reading it failed.")
