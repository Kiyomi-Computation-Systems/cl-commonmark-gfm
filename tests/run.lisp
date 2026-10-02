;;;; Load the pure suite through ASDF, run it under Parachute, and turn the
;;;; result into the process exit status (M1 design §7.2). The reporting
;;;; code lives in tests/runner.lisp, shared with tests/run-native.lisp.
;;;;
;;;; The very first form prints a fixed marker and flushes it. Output
;;;; redirected to a file is buffered, so an unflushed marker would look
;;;; like a hang: scripts/lisp-start-watchdog polls a run's captured
;;;; output for this exact line to tell a started CCL from one still
;;;; hung in its own startup (finding 20, M2 design §8.5; ADR-0013). Keep
;;;; this line identical to tests/run-native.lisp's and to the Makefile's
;;;; LISP_START_MARKER.

(format t "~&;; lisp started~%")
(finish-output)

(require :asdf)

(asdf:load-system "cl-commonmark-gfm/tests")

(load (merge-pathnames "runner.lisp" *load-truename*))

(let ((passed (report-suite (run-suite :cl-commonmark-gfm.tests "check-purity") "check-purity"))
      (pure (not (find-package "CFFI"))))
  (unless pure
    (format *error-output*
            "~&check-purity: the CFFI package is loaded; the pure suite must not depend on it~%"))
  (uiop:quit (if (and passed pure) 0 1)))
