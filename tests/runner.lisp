;;;; The reporting code both test runners share: tests/run.lisp runs the pure
;;;; suite, tests/run-native.lisp the native one (M1 design §7.2; M2 design
;;;; §8.5). A runner loads its test system through ASDF, then this file, then
;;;; calls RUN-SUITE and REPORT-SUITE and adds its own exit checks.

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

(defun run-suite (designator label)
  "Run DESIGNATOR's tests under the quiet reporter and return Parachute's
report. DESIGNATOR is a package, as tests/run.lisp and tests/run-native.lisp
give it, or a list of test names, as the fuzz runners give it
(tests/run-fuzz.lisp, tests/run-native-fuzz.lisp): whatever Parachute's own
TEST accepts. Parachute records a test's errors, but a serious condition
that isn't an error, such as a stack overflow, escapes it. Exit 1 when one
does, naming LABEL: ECL's top level would otherwise exit 0 after an
overflow, and the make target would report a pass."
  (handler-case (parachute:test designator :report 'parachute:quiet)
    (serious-condition (condition)
      (format *error-output* "~&~A: the run was aborted by ~S~%" label (type-of condition))
      (uiop:quit 1))))

(defun report-suite (report label)
  "Print REPORT's failures, then LABEL's line of test and assertion counts.
Return true when REPORT passed and at least one test ran."
  (let* ((passed (eql :passed (parachute:status report)))
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
    (unless ran-any-tests
      (format *error-output* "~&~A: no tests ran~%" label))
    (format t "~&~A: ~D tests, ~D assertions~%" label test-count assertion-count)
    (and passed ran-any-tests)))
