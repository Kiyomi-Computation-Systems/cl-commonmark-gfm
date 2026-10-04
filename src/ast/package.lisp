;;;; The cl-commonmark-gfm.ast package: its public interface. WALK-AST is
;;;; the traversal that FOLD-AST and MAP-AST are built on.

(defpackage #:cl-commonmark-gfm.ast
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm.conditions
                #:invalid-ast-node)
  (:import-from #:cl-commonmark-gfm.util
                #:proper-list-p)
  (:export #:node
           #:node-p
           #:make-node
           #:copy-node
           #:node-kind
           #:node-attributes
           #:node-attribute
           #:node-children
           #:node-sourcepos
           #:node=
           #:walk-ast
           #:fold-ast
           #:map-ast
           #:transform-ast))
