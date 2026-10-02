;;;; Small AST builders and condition helpers shared across the test suite.

(in-package #:cl-commonmark-gfm.tests)

;;; Condition helpers

(defun signalled (type thunk)
  "Call THUNK. Return the condition of TYPE it signalled, or NIL when it
returned normally or signalled a COMMONMARK-GFM-ERROR of another type."
  (handler-case (progn (funcall thunk) nil)
    (commonmark-gfm-error (condition)
      (and (typep condition type) condition))))

;;; AST builders

(defun n (kind attributes &rest children)
  "Build a NODE of KIND with plist ATTRIBUTES and the given CHILDREN."
  (make-node kind :attributes attributes :children children))

(defun txt (string)
  "Build a :TEXT node whose :LITERAL is STRING."
  (make-node :text :attributes (list :literal string)))

(defun call-with-args (function args)
  "Call FUNCTION on ARGS via APPLY, both taken as opaque runtime values. Some
Lisps statically flag an unrecognized keyword argument even through a literal
(APPLY #'FOO ... 'ARGS) call, once they know FOO's lambda list; routing the
call through this ordinary higher-order function keeps such a test (an
argument copy-node's schema must reject at runtime) from also failing to
compile cleanly."
  (apply function args))
