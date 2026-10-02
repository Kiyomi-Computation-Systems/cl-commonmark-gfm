;;;; `make fuzz`'s pure half (M3 plan, Task 9): load the pure suite, then run
;;;; only its property tests (tests/properties.lisp's *PROPERTY-TESTS*), not
;;;; the whole suite, with CL_COMMONMARK_GFM_SEED and CL_COMMONMARK_GFM_CASES
;;;; read from the environment as tests/run.lisp reads them. Shares its
;;;; reporting code, tests/runner.lisp.
;;;;
;;;; The very first form prints a fixed marker and flushes it, exactly as
;;;; tests/run.lisp's does: scripts/lisp-start-watchdog polls for this exact
;;;; line to tell a started CCL from one hung in its own startup (finding
;;;; 20, M2 design §8.5; ADR-0013).

(format t "~&;; lisp started~%")
(finish-output)

(require :asdf)

(asdf:load-system "cl-commonmark-gfm/tests")

(load (merge-pathnames "runner.lisp" *load-truename*))

;; A bad CL_COMMONMARK_GFM_SEED or CL_COMMONMARK_GFM_CASES must fail loudly
;; before any property runs, caught explicitly as tests/run.lisp catches it.
(handler-case (cl-commonmark-gfm.tests::initialize-property-settings)
  (cl-commonmark-gfm.tests::property-setting-error (condition)
    (format *error-output* "~&fuzz-purity: ~A~%" condition)
    (uiop:quit 2)))

(let ((passed (report-suite (run-suite cl-commonmark-gfm.tests::*property-tests* "fuzz-purity")
                            "fuzz-purity")))
  (uiop:quit (if passed 0 1)))
