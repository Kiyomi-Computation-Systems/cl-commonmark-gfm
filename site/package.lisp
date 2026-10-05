;;;; The cl-commonmark-gfm.site package: the documentation site's generator.
;;;; It renders docs/ through the library's public API alone, so it imports
;;;; only symbols that cl-commonmark-gfm exports. A test in tests/core.lisp
;;;; checks every symbol of the library's packages that this package can
;;;; reach.

(defpackage #:cl-commonmark-gfm.site
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm
                #:commonmark-gfm-error
                #:unsupported-input
                #:parse
                #:ast->html-tree
                #:html-tree->string
                #:node-kind
                #:node-attribute
                #:node-children
                #:copy-node
                #:fold-ast
                #:transform-ast)
  (:export #:*pages*
           #:heading-id
           #:unique-ids
           #:heading-text
           #:rewrite-destination
           #:page-document
           #:render-site))
