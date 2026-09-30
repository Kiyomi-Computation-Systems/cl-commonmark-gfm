;;;; The cl-commonmark-gfm.html-tree package: its public interface (M1 design §5, §6).

(defpackage #:cl-commonmark-gfm.html-tree
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm.conditions
                #:invalid-render-option
                #:invalid-html-tree
                #:unsupported-extension-node)
  (:import-from #:cl-commonmark-gfm.ast
                #:make-node
                #:node-kind
                #:node-attribute
                #:node-children
                #:walk-ast)
  (:import-from #:cl-commonmark-gfm.util
                #:proper-list-p)
  (:export #:ast->html-tree
           #:html-tree->string))
