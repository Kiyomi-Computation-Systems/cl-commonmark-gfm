;;;; The cl-commonmark-gfm.ast package: its public interface (design §4).

(defpackage #:cl-commonmark-gfm.ast
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm.conditions
                #:invalid-ast-node)
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
           #:fold-ast
           #:map-ast
           #:transform-ast))
