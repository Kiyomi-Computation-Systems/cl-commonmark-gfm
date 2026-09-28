;;;; ASDF system definitions for cl-commonmark-gfm (design §3). The native
;;;; layer that gives the primary system its real content arrives in M2.
;;;;
;;;; The empty primary system below is load-bearing, not a preview of M2:
;;;; ASDF's COMPONENT-DEPENDS-ON for any operation on a system S adds a
;;;; dependency on (DEFINE-OP (PRIMARY-SYSTEM-NAME S)), so a slash-named
;;;; system cannot be found or loaded unless its primary name is itself a
;;;; defined system. It has no components and no dependencies.

(asdf:defsystem "cl-commonmark-gfm"
  :description "cmark-gfm bindings for Common Lisp (the native layer arrives in M2)"
  :license "BSD-3-Clause")

(asdf:defsystem "cl-commonmark-gfm/conditions"
  :description "Conditions signalled by cl-commonmark-gfm"
  :license "BSD-3-Clause"
  :serial t
  :pathname "src/"
  :components ((:file "conditions")))

(asdf:defsystem "cl-commonmark-gfm/ast"
  :description "A validated AST node type, queries, equality and transforms"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/conditions")
  :serial t
  :pathname "src/ast/"
  :components ((:file "package")
               (:file "schema")
               (:file "node")
               (:file "transform")))

(asdf:defsystem "cl-commonmark-gfm/html-tree"
  :description "AST to LHTML-shaped HTML tree conversion, and its serializer"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/ast")
  :serial t
  :pathname "src/html-tree/"
  :components ((:file "package")
               (:file "url")
               (:file "serialize")
               (:file "footnotes")
               (:file "convert")))

(asdf:defsystem "cl-commonmark-gfm/tests"
  :description "Test suite for the pure conditions, AST and HTML-tree systems"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/conditions"
               "cl-commonmark-gfm/ast"
               "cl-commonmark-gfm/html-tree"
               "parachute")
  :serial t
  :pathname "tests/"
  :components ((:file "package")
               (:file "helpers")
               (:file "conditions")
               (:file "ast")
               (:file "url")
               (:file "serialize")
               (:file "html-tree")
               (:file "oracle")))
