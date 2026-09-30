;;;; Load the pure suite through ASDF, run it under Parachute, and turn the
;;;; result into the process exit status (M1 design §7.2).

(require :asdf)

(asdf:load-system "cl-commonmark-gfm/tests")

(defun failing-leaves (result)
  "Return a fresh list of RESULT's failing leaves, recursing into parent
results. A parent with no failing children of its own (a bare evaluation
error) counts as a leaf, so a failure is never silently dropped."
  (let ((children (and (typep result 'parachute:parent-result)
                       (parachute:results-with-status :failed result))))
    (if children
        (mapcan #'failing-leaves children)
        (list result))))

(defun distinct-report-results (report)
  "REPORT's own RESULTS, deduplicated: Parachute files every result under
both its own test and the top-level report, so the same object can appear
more than once when a report's results are walked (as FAILING-LEAVES walks
them); REMOVE-DUPLICATES with EQL leaves one of each."
  (remove-duplicates (coerce (parachute:results report) 'list) :test #'eql))

(defun run-suite ()
  "Run the suite under the quiet reporter and return Parachute's report.
Parachute records a test's errors, but a serious condition that isn't an
error, such as a stack overflow, escapes it. Exit 1 when one does: ECL's
top level would otherwise exit 0 after an overflow, and check-purity would
report a pass."
  (handler-case (parachute:test :cl-commonmark-gfm.tests :report 'parachute:quiet)
    (serious-condition (condition)
      (format *error-output* "~&check-purity: the run was aborted by ~S~%" (type-of condition))
      (uiop:quit 1))))

(let* ((report (run-suite))
       (passed (eql :passed (parachute:status report)))
       (pure (not (find-package "CFFI")))
       (results (distinct-report-results report))
       (test-count (count-if (lambda (result) (typep result 'parachute:test-result)) results))
       (assertion-count (- (length results) test-count))
       (ran-any-tests (plusp test-count)))
  (unless passed
    (format *error-output* "~&;; Failures:~%~%")
    ;; Parachute files each result under its test and under the report, so
    ;; the same leaf is reached twice: print each one once.
    (dolist (leaf (remove-duplicates
                   (mapcan #'failing-leaves (parachute:results-with-status :failed report))
                   :test #'eql :from-end t))
      (format *error-output* "~&~a~%~%" (parachute:format-result leaf :extensive))))
  (unless pure
    (format *error-output*
            "~&check-purity: the CFFI package is loaded; the pure suite must not depend on it~%"))
  (unless ran-any-tests
    (format *error-output* "~&check-purity: no tests ran~%"))
  (format t "~&check-purity: ~D tests, ~D assertions~%" test-count assertion-count)
  (uiop:quit (if (and passed pure ran-any-tests) 0 1)))
