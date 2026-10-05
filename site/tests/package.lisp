;;;; The cl-commonmark-gfm.site.tests package: the site generator's tests.
;;;; They reach the generator's internals as cl-commonmark-gfm.site::name.

(defpackage #:cl-commonmark-gfm.site.tests
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm
                #:parse
                #:node-children
                #:html-tree->string)
  (:import-from #:cl-commonmark-gfm.site
                #:heading-id
                #:unique-ids
                #:heading-text
                #:rewrite-destination
                #:page-document
                #:render-site)
  (:import-from #:parachute
                #:define-test
                #:is
                #:true
                #:fail))
