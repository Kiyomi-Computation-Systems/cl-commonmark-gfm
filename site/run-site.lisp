;;;; `make site`'s runner: load the site generator, render docs/ into
;;;; build/site/, and turn the result into the process exit status. The
;;;; Makefile puts site/ on CL_SOURCE_REGISTRY, so ASDF finds
;;;; cl-commonmark-gfm-site.asd, and passes SITE_REF as an environment
;;;; variable, as it passes PROPERTY_SEED: scripts/guix-env carries no
;;;; other environment into the container.

(require :asdf)

(asdf:load-system "cl-commonmark-gfm-site")

(load (merge-pathnames "build.lisp" *load-truename*))

;; BUILD-SITE parses Markdown, so it needs cmark-gfm. Say so once, before
;; any page is read, rather than however a native error happens to surface.
(handler-case (cl-commonmark-gfm:parse "")
  (cl-commonmark-gfm:native-error (condition)
    (format *error-output* "~&site: ~A~%" condition)
    (cl-commonmark-gfm.site::print-cmark-gfm-hint)
    (uiop:quit 2)))

;; SITE_REF, unset, is MAKE's own default, main; set but unfit to use
;; (make site SITE_REF=, or one holding a character or a segment REF-
;; PROBLEM refuses) is refused here, with the rule it breaks, rather than
;; written into a broken link or an empty one.
(let* ((ref (or (uiop:getenv "SITE_REF") cl-commonmark-gfm.site::*default-ref*))
       (ref-problem (cl-commonmark-gfm.site::ref-problem ref)))
  (when ref-problem
    (format *error-output* "~&site: SITE_REF ~S ~A.~%" ref ref-problem)
    (uiop:quit 2))
  (multiple-value-bind (pages problems) (cl-commonmark-gfm.site::build-site ref)
    (cond (problems
           (cl-commonmark-gfm.site::report-problems "site" problems)
           (uiop:quit 1))
          (t
           (format t "~&site: wrote ~D page~:P to build/site/ (ref ~A)~%" pages ref)
           (uiop:quit 0)))))
