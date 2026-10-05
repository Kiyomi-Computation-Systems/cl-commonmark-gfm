;;;; `make check-site`'s runner: load the site generator's tests through
;;;; ASDF, run them under Parachute, then check docs/ itself: *PAGES*
;;;; against docs/*.md (check 1), then RENDER-SITE's problems over the home
;;;; page and *PAGES*, read from there. The Makefile puts site/ on
;;;; CL_SOURCE_REGISTRY, so ASDF finds cl-commonmark-gfm-site.asd. The
;;;; suite's report is tests/runner.lisp's, shared with the library's own
;;;; suites: "check-site: <n> tests, <m> assertions".

(require :asdf)

(asdf:load-system "cl-commonmark-gfm-site/tests")

(load (asdf:system-relative-pathname "cl-commonmark-gfm" "tests/runner.lisp"))
(load (merge-pathnames "build.lisp" *load-truename*))

;; The tests parse Markdown, and so does the check below: cmark-gfm must
;; start before either runs, rather than fail obscurely inside one test or
;; the first page read.
(handler-case (cl-commonmark-gfm:parse "")
  (cl-commonmark-gfm:native-error (condition)
    (format *error-output* "~&check-site: ~A~%" condition)
    (cl-commonmark-gfm.site::print-cmark-gfm-hint)
    (uiop:quit 2)))

(unless (report-suite (run-suite :cl-commonmark-gfm.site.tests "check-site") "check-site")
  (uiop:quit 1))

(multiple-value-bind (problems pages links)
    (cl-commonmark-gfm.site::check-site-problems cl-commonmark-gfm.site::*default-ref*)
  (cond (problems
         (cl-commonmark-gfm.site::report-problems "check-site" problems)
         (uiop:quit 1))
        (t
         (format t "~&check-site: ~D page~:P, ~D link~:P, no problems~%" pages links)
         (uiop:quit 0))))
