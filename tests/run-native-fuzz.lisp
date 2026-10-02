;;;; `make fuzz`'s native half (M3 plan, Task 9): load the native suite, then
;;;; run only its property tests (tests/native/properties.lisp and
;;;; divergences.lisp's *PROPERTY-TESTS*), not the whole suite, with
;;;; CL_COMMONMARK_GFM_SEED and CL_COMMONMARK_GFM_CASES read from the
;;;; environment as tests/run-native.lisp reads them. Shares its reporting
;;;; code, tests/runner.lisp, and its open-counters check (ADR-0008).
;;;;
;;;; The very first form prints a fixed marker and flushes it, exactly as
;;;; tests/run-native.lisp's does (ADR-0013).

(format t "~&;; lisp started~%")
(finish-output)

(require :asdf)

(asdf:load-system "cl-commonmark-gfm/native-tests")

(load (merge-pathnames "runner.lisp" *load-truename*))

;; A bad CL_COMMONMARK_GFM_SEED or CL_COMMONMARK_GFM_CASES must fail loudly
;; before any property runs, caught explicitly as tests/run-native.lisp
;; catches it.
(handler-case (cl-commonmark-gfm.tests::initialize-property-settings)
  (cl-commonmark-gfm.tests::property-setting-error (condition)
    (format *error-output* "~&fuzz-native: ~A~%" condition)
    (uiop:quit 2)))

(let* ((passed (report-suite (run-suite cl-commonmark-gfm.native-tests::*property-tests*
                                        "fuzz-native")
                             "fuzz-native"))
       (counts (cl-commonmark-gfm.native:native-open-counts))
       (closed (loop for (nil count) on counts by #'cddr always (zerop count))))
  (unless closed
    (format *error-output* "~&fuzz-native: native handles left open at exit:~{ ~(~A~) ~D~}~%"
            counts))
  (uiop:quit (if (and passed closed) 0 1)))
