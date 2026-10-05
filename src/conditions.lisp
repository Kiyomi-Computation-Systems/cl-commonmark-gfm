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
  (:documentation
   "Base of every condition cl-commonmark-gfm exports. Its readers,
CONDITION-OPERATION, CONDITION-DATUM and CONDITION-REASON, apply to them
all."))

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
value of one of PARSE's options they take."))

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
*MAX-INPUT-OCTETS*, *MAX-NODES* or *MAX-OUTPUT-OCTETS*. CONDITION-LIMIT
names the limit, CONDITION-MAXIMUM gives the maximum that applied, and
CONDITION-DATUM the value found; CONDITION-REASON says whether the hard
cap applied.

Even within the limits, on a machine already short of memory, cmark-gfm's
allocator can still abort the process, and no Lisp handler can catch
that."))

(setf (documentation 'condition-limit 'function)
      "Return CONDITION's limit: the symbol naming the special variable whose
limit was exceeded.")

(setf (documentation 'condition-maximum 'function)
      "Return CONDITION's maximum: the effective maximum that applied, the
limit or its hard cap when that is lower.")

;;; The input guard

(define-condition unsupported-input (commonmark-gfm-error) ()
  (:documentation
   "Signalled by PARSE, MARKDOWN->HTML, MARKDOWN->PLAINTEXT and
MARKDOWN->HTML-TREE, while :FOOTNOTES is on, as it is by default, for
input holding \"[\" immediately followed by an entity that decodes to
\"^\", such as \"&#94;\", \"&#x5e;\" or \"&Hat;\". cmark-gfm 0.29.0.gfm.13
can't parse that safely, so the input is refused before cmark-gfm sees it,
wherever the pattern is, even in a code block. To parse such input, pass
:FOOTNOTES NIL, and do without footnotes. CONDITION-DATUM gives the index
of the \"[\" that starts the pattern."))

;;; The native layer

(define-condition native-error (commonmark-gfm-error) ()
  (:documentation
   "Parent of NATIVE-LIBRARY-NOT-FOUND, NATIVE-ABI-MISMATCH,
DYNAMIC-FFI-UNAVAILABLE, NATIVE-INITIALIZATION-ERROR, NATIVE-PARSE-ERROR and
NATIVE-RENDER-ERROR. Not signalled directly.

The first four are signalled when cmark-gfm fails to start. It starts at
the first call that needs it, loading the pinned version as
*CMARK-GFM-LIBRARIES* says, then checking it. An ECL program with
cmark-gfm linked in skips the loading, but not the checks."))

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
names them is malformed, or when loading one of them fails.
CONDITION-OVERRIDE gives the override in effect, and CONDITION-PATHS the
paths involved."))

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
   "Signalled when the loaded cmark-gfm isn't the pinned version, or when
reading its version fails, as when a function is missing from the loaded
libraries. CONDITION-EXPECTED-VERSION gives the pinned version,
CONDITION-FOUND-VERSION the one it reported, and CONDITION-PATHS the
libraries loaded."))

(define-condition dynamic-ffi-unavailable (native-error) ()
  (:documentation
   "Signalled on an ECL built without dynamic FFI (no :DFFI feature) when
cmark-gfm isn't linked into the program: such an ECL can't load a library
at run time. Starting cmark-gfm signals it first, before looking for or
loading anything. CONDITION-DATUM is :DFFI, and CONDITION-REASON says how
to link cmark-gfm into a program instead: compile with
CFFI-SYS:*CFFI-ECL-METHOD* set to :C/C++, and link
libcmark-gfm-extensions.a and libcmark-gfm.a. A program with cmark-gfm
linked in never signals it."))

(define-condition native-initialization-error (native-error) ()
  (:documentation
   "Signalled when cmark-gfm's libraries load but cmark-gfm fails to start,
such as when a GFM extension is missing or its test parse fails. Also
signalled on CCL for a pair of libraries other than the process's first,
as *CMARK-GFM-LIBRARIES* explains: CONDITION-DATUM gives the refused
pair's truenames, and CONDITION-REASON names the pair the process keeps."))

(define-condition native-parse-error (native-error) ()
  (:documentation
   "Signalled when cmark-gfm fails to parse, or its result holds something
this library can't read, such as a footnote reference with no
definition."))

(define-condition native-render-error (native-error) ()
  (:documentation
   "Signalled when one of cmark-gfm's renderers fails."))

;;; As above, the readers get their own docstrings. CONDITION-PATHS is
;;; shared by two sibling conditions, so its docstring covers both.

(setf (documentation 'condition-override 'function)
      "Return CONDITION's override: the override value in effect when the
search that failed was using one -- *CMARK-GFM-LIBRARIES*' value, or
CL_COMMONMARK_GFM_LIBS' when that was used instead -- or NIL when it was the
ordinary directory search.")

(setf (documentation 'condition-paths 'function)
      "Return CONDITION's paths. For NATIVE-LIBRARY-NOT-FOUND, a list of the
directories searched, or of the one path that isn't a regular file or
failed to load; or NIL for a malformed override. For NATIVE-ABI-MISMATCH,
the paths of the two libraries loaded, or :LINKED in a linked program,
which loads none.")

(setf (documentation 'condition-expected-version 'function)
      "Return CONDITION's expected-version: the cmark-gfm version string this
library is pinned to.")

(setf (documentation 'condition-found-version 'function)
      "Return CONDITION's found-version: the version the loaded cmark-gfm
reported, or NIL when reading it failed.")
