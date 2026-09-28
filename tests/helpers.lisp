;;;; Small AST builders shared by the AST, HTML-tree and oracle tests.

(in-package #:cl-commonmark-gfm.tests)

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
