;;;; Conditions signalled by cl-commonmark-gfm (design §3).

(defpackage #:cl-commonmark-gfm.conditions
  (:use #:cl)
  (:export #:commonmark-gfm-error
           #:condition-operation
           #:condition-datum
           #:condition-reason
           #:invalid-ast-node
           #:invalid-render-option
           #:invalid-html-tree
           #:unsupported-extension-node))

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

;;; Subtypes

(define-condition invalid-ast-node (commonmark-gfm-error) ()
  (:documentation
   "Signalled by MAKE-NODE, COPY-NODE, NODE-ATTRIBUTE and TRANSFORM-AST when
a node fails schema validation."))

(define-condition invalid-render-option (commonmark-gfm-error) ()
  (:documentation
   "Signalled by AST->HTML-TREE for a malformed or unknown rendering option."))

(define-condition invalid-html-tree (commonmark-gfm-error) ()
  (:documentation
   "Signalled by HTML-TREE->STRING for a malformed HTML tree."))

(define-condition unsupported-extension-node (commonmark-gfm-error) ()
  (:documentation
   "Signalled by AST->HTML-TREE for an :EXTENSION node."))
