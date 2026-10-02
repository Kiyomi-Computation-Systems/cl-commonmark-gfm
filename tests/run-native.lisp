;;;; Load the native suite through ASDF, run it under Parachute, and turn the
;;;; result into the process exit status (M2 design §8.5). Like
;;;; tests/run.lisp, whose reporting code it shares (tests/runner.lisp), but
;;;; with no CFFI check: the native suite needs CFFI. It fails instead unless
;;;; the open counters (parsers, roots and buffers) are zero when it ends
;;;; (ADR-0008).
;;;;
;;;; The very first form prints a fixed marker and flushes it. Output
;;;; redirected to a file is buffered, so an unflushed marker would look
;;;; like a hang: scripts/lisp-start-watchdog polls a run's captured
;;;; output for this exact line to tell a started CCL from one still
;;;; hung in its own startup (finding 20, M2 design §8.5; ADR-0013). Keep
;;;; this line identical to tests/run.lisp's and to the Makefile's
;;;; LISP_START_MARKER.

(format t "~&;; lisp started~%")
(finish-output)

(require :asdf)

(asdf:load-system "cl-commonmark-gfm/native-tests")

;; Fail fast, before any test compiles or runs, when cmark-gfm's pinned
;; libraries can't be found (ADR-0009), instead of every test and property
;; case failing on its own with NATIVE-LIBRARY-NOT-FOUND, the real cause
;; buried in the details. RESOLVE-CMARK-LIBRARIES
;; runs with the same arguments START-NATIVE-LAYER gives it
;; (src/native/startup.lisp): the override, as native namestrings;
;; CL_COMMONMARK_GFM_LIBS; this machine's OS and multiarch; and a real file
;; check. So the search that fails here is exactly the one a parse would
;; run, just before any test, not during one.
(handler-case
    (cl-commonmark-gfm.native-core:resolve-cmark-libraries
     :libraries (cl-commonmark-gfm.native::native-override
                 cl-commonmark-gfm.native-core:*cmark-gfm-libraries*)
     :environment (uiop:getenv "CL_COMMONMARK_GFM_LIBS")
     :os (cl-commonmark-gfm.native::current-os)
     :multiarch (cl-commonmark-gfm.native::current-multiarch)
     :regular-file-p #'cl-commonmark-gfm.native::regular-file-p)
  (cl-commonmark-gfm.conditions:native-library-not-found (condition)
    (format *error-output* "~&check-native: ~A~%" condition)
    (format *error-output*
            "~&On a Guix host, run it in the project's container: scripts/guix-env ~
             make <target>, which sets CL_COMMONMARK_GFM_LIBS. Elsewhere, install ~
             libcmark-gfm 0.29.0.gfm.13, or set CL_COMMONMARK_GFM_LIBS to the two ~
             library paths.~%")
    (uiop:quit 2)))

(load (merge-pathnames "runner.lisp" *load-truename*))

;; CL_COMMONMARK_GFM_SEED and CL_COMMONMARK_GFM_CASES (M3 plan, Task 9) must
;; be read, and a bad value must fail loudly, before any property test runs.
;; Caught explicitly, rather than left to escape: an uncaught condition
;; doesn't reliably exit non-zero on every Lisp (progress.md: ECL's top
;; level can exit 0 after one).
(handler-case (cl-commonmark-gfm.tests::initialize-property-settings)
  (cl-commonmark-gfm.tests::property-setting-error (condition)
    (format *error-output* "~&check-native: ~A~%" condition)
    (uiop:quit 2)))

(let* ((passed (report-suite (run-suite :cl-commonmark-gfm.native-tests "check-native")
                             "check-native"))
       (counts (cl-commonmark-gfm.native:native-open-counts))
       (closed (loop for (nil count) on counts by #'cddr always (zerop count))))
  (unless closed
    (format *error-output* "~&check-native: native handles left open at exit:~{ ~(~A~) ~D~}~%"
            counts))
  (uiop:quit (if (and passed closed) 0 1)))
