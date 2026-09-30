;;;; The cl-commonmark-gfm.ast package: its public interface (M1 design §4;
;;;; M2 design §4.1, §4.2 add WALK-AST, the one AST traversal that FOLD-AST,
;;;; MAP-AST and TRANSFORM-AST are now built on).

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
