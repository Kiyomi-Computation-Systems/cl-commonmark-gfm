;;;; Load the pure suite through ASDF, run it under Parachute, and turn the
;;;; result into the process exit status (design §7.2).

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

(let* ((report (parachute:test :cl-commonmark-gfm.tests :report 'parachute:quiet))
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
