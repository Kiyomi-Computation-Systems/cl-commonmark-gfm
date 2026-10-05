;;;; `make reference`'s and `make check-reference`'s runner: load the site
;;;; generator, read the symbols cl-commonmark-gfm exports from this image,
;;;; and write docs/reference.md from them, or check it against the page
;;;; they make; then turn the result into the process exit status. The
;;;; Makefile puts site/ on CL_SOURCE_REGISTRY, so ASDF finds
;;;; cl-commonmark-gfm-site.asd, and says which to do in REFERENCE_ACTION,
;;;; write or check, an environment variable as SITE_REF is for
;;;; run-site.lisp. Writing needs no cmark-gfm: the docstrings come from
;;;; the image, and the page is built as text. Checking renders each
;;;; docstring's Markdown through the library, so it starts cmark-gfm
;;;; first.

(require :asdf)

(asdf:load-system "cl-commonmark-gfm-site")

(load (merge-pathnames "build.lisp" *load-truename*))

(let* ((action (uiop:getenv "REFERENCE_ACTION"))
       (entries (cl-commonmark-gfm.site::read-entries cl-commonmark-gfm.site::*reference-package*))
       (pathname (cl-commonmark-gfm.site::docs-path cl-commonmark-gfm.site::*reference-page*)))
  (cond ((and action (string= action "write"))
         ;; Refuse before writing anything: a page with an empty entry
         ;; would only fail check-reference later.
         (let ((problems (cl-commonmark-gfm.site::docstring-problems entries)))
           (cond (problems
                  (cl-commonmark-gfm.site::report-problems "reference" problems)
                  (uiop:quit 1))
                 (t
                  (cl-commonmark-gfm.site::write-utf8-file
                   pathname
                   (cl-commonmark-gfm.site::reference-text
                    (cl-commonmark-gfm.site::reference-parts entries)))
                  (format t "~&reference: wrote docs/reference.md, ~D symbols~%" (length entries))
                  (uiop:quit 0)))))
        ((and action (string= action "check"))
         ;; The check renders each docstring's Markdown: cmark-gfm must
         ;; start before it does, rather than fail obscurely at the first
         ;; docstring.
         (handler-case (cl-commonmark-gfm:parse "")
           (cl-commonmark-gfm:native-error (condition)
             (format *error-output* "~&check-reference: ~A~%" condition)
             (cl-commonmark-gfm.site::print-cmark-gfm-hint)
             (uiop:quit 2)))
         (let ((problems (cl-commonmark-gfm.site::reference-problems
                          entries
                          (and (probe-file pathname)
                               (uiop:read-file-string pathname :external-format :utf-8)))))
           (cond (problems
                  (cl-commonmark-gfm.site::report-problems "check-reference" problems)
                  (uiop:quit 1))
                 (t
                  (format t "~&check-reference: ~D symbols; docs/reference.md is current~%"
                          (length entries))
                  (uiop:quit 0)))))
        (t
         (format *error-output* "~&run-reference.lisp: REFERENCE_ACTION is ~S, not write or check~%"
                 action)
         (uiop:quit 2))))
