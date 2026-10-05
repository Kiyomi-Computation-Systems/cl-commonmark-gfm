;;;; `make check-docs`'s runner: load the site generator, run the Lisp
;;;; examples of every page in docs/ with CHECK-EXAMPLES, and turn the
;;;; result into the process exit status. The Makefile puts site/ on
;;;; CL_SOURCE_REGISTRY, so ASDF finds cl-commonmark-gfm-site.asd. The
;;;; pages are read through site/build.lisp, the shell around the
;;;; generator's core: the core never touches a file.

(require :asdf)

(asdf:load-system "cl-commonmark-gfm-site")

(load (merge-pathnames "build.lisp" *load-truename*))

;; Finding a page's blocks parses Markdown, and the examples call
;; cmark-gfm: it must start before any page is read, rather than fail
;; obscurely as the first example runs.
(handler-case (cl-commonmark-gfm:parse "")
  (cl-commonmark-gfm:native-error (condition)
    (format *error-output* "~&check-docs: ~A~%" condition)
    (cl-commonmark-gfm.site::print-cmark-gfm-hint)
    (uiop:quit 2)))

(multiple-value-bind (problems examples pages)
    (cl-commonmark-gfm.site::check-examples
     (cl-commonmark-gfm.site::read-docs-pages (cl-commonmark-gfm.site::docs-markdown-names)))
  (cond (problems
         (cl-commonmark-gfm.site::report-problems "check-docs" problems)
         (uiop:quit 1))
        (t
         (format t "~&check-docs: ~D example~:P on ~D page~:P~%" examples pages)
         (uiop:quit 0))))
