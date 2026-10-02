;;;; Interrupts (M2 design §5.4, §8.4; finding 21): a worker rendering in a
;;;; loop, interrupted again and again with a THROW, as SB-EXT:WITH-TIMEOUT
;;;; would unwind it, keeps rendering, and ends with no hold and the open
;;;; counters at zero. A throw out of cmark's malloc or free would leave a
;;;; lock of the C heap held, and the worker's next allocation would wait on
;;;; it forever. So the race runs in a child SBCL with a time limit
;;;; (RUN-CHILD, in image.lisp), and a deadlock fails the test instead of
;;;; hanging the suite. CCL's and ECL's runs arrive in M4.

(in-package #:cl-commonmark-gfm.native-tests)

(defparameter *interrupts* 2000
  "How many times the race interrupts its worker.")

(defparameter *interrupted-markdown* (format nil "*a* [^1]~%~%[^1]: b~%")
  "What the race's worker renders: small, so an interrupt often lands
inside a render, with a footnote, so each render also allocates and frees
in cmark's footnote pass.")

(defvar *cuttable* nil
  "True in the race's worker while it is inside its CATCH of CUT. An
interrupt throws only then: a throw with no catch would be an error.")

(defstruct (tally (:constructor make-tally ()))
  "What the race's worker has done: its RENDERS; the interrupts it has
TAKEN, and of those, the CUTS that threw; the type of each condition it
signalled, in FAULTS. STOP tells it to stop. Only the worker writes the
counts, its interrupts included, since they run in its thread."
  (renders 0)
  (taken 0)
  (cuts 0)
  (faults '())
  (stop nil))

(defun race-worker (tally)
  "The race's worker, a function of no arguments: render
*INTERRUPTED-MARKDOWN* until TALLY says stop, each render inside a CATCH
of CUT, and count in TALLY each one that completes."
  (lambda ()
    (loop until (tally-stop tally)
          do (catch 'cut
               (let ((*cuttable* t))
                 (handler-case
                     (progn (markdown->html *interrupted-markdown*)
                            (incf (tally-renders tally)))
                   (serious-condition (condition)
                     (push (type-of condition) (tally-faults tally)))))))))

(defun cut-function (tally)
  "The interrupt the race sends its worker: count it in TALLY as taken
and, when the worker is inside its CATCH, throw there, unwinding whatever
it was doing, as a timeout would."
  (lambda ()
    (incf (tally-taken tally))
    (when *cuttable*
      (incf (tally-cuts tally))
      (throw 'cut nil))))

(defun wait-until (predicate seconds)
  "Call PREDICATE, yielding between calls, until it returns true or SECONDS
have passed. Return whether it returned true."
  (let ((deadline (+ (get-internal-real-time) (* seconds internal-time-units-per-second))))
    (loop until (funcall predicate)
          while (< (get-internal-real-time) deadline)
          do (bt2:thread-yield))
    (and (funcall predicate) t)))

#+sbcl
(defun interrupt-race (interrupts)
  "In a child SBCL: start a worker rendering in a loop, and interrupt it
INTERRUPTS times with CUT-FUNCTION's throw. The interrupts are paced as
the probe that found finding 21 paced them: a random number of yields
before each, and the next sent only once the last was taken, since a flood
of pending interrupts overflows SBCL's interrupt nesting. Then wait for
the worker to render 100 more times, and stop it. Return a plist:
- :SENT and :TAKEN, the interrupts sent and taken, and :CUTS, those that
  threw;
- :RENDERS-AFTER, the renders completed after the last interrupt, within
  10 seconds;
- :JOINED, whether the worker then stopped within 10 seconds;
- :FAULTS, the type of each condition the worker signalled;
- :HOLDS and :OPEN, the holds and the open counters left."
  (let* ((tally (make-tally))
         (worker (sb-thread:make-thread (race-worker tally) :name "interrupted worker"))
         (cut (cut-function tally))
         (random-state (sb-ext:seed-random-state 1))
         (sent 0))
    (wait-until (lambda () (plusp (tally-renders tally))) 30)
    (loop repeat interrupts
          for taken = (tally-taken tally)
          do (loop repeat (random 2000 random-state)
                   do (sb-thread:thread-yield))
             (sb-thread:interrupt-thread worker cut)
             (incf sent)
          while (wait-until (lambda () (/= taken (tally-taken tally))) 10))
    (let* ((renders (tally-renders tally))
           (renders-after (progn
                            (wait-until (lambda () (<= (+ renders 100) (tally-renders tally))) 10)
                            (- (tally-renders tally) renders))))
      (setf (tally-stop tally) t)
      (list :sent sent
            :taken (tally-taken tally)
            :cuts (tally-cuts tally)
            :renders-after renders-after
            :joined (not (eql :timed-out
                              (sb-thread:join-thread worker :default :timed-out :timeout 10)))
            :faults (remove-duplicates (tally-faults tally))
            :holds (startup-holds)
            :open (native-open-counts)))))

#+sbcl
(defun interrupt-race-run ()
  "Run INTERRUPT-RACE, for *INTERRUPTS* interrupts, in a child that loads
this suite, and return the child's RUN-CHILD plist."
  (run-child sb-ext:*core-pathname*
             (suite-child-forms
              :race
              (format nil "(cl-commonmark-gfm.native-tests::interrupt-race ~D)" *interrupts*))))

#+sbcl
(define-test a-worker-interrupted-again-and-again-keeps-rendering
  ;; Without interrupts deferred around each cmark call, the worker soon
  ;; stops for good (finding 21), still holding the state, and leaves
  ;; parsers, roots or buffers open.
  (destructuring-bind (&key killed exit-code reports errors) (interrupt-race-run)
    (false killed "the child reported within ~D seconds" *child-seconds*)
    (is eql 0 exit-code "the child exits 0; its error output starts:~%~A" errors)
    (destructuring-bind (&key sent taken cuts renders-after joined faults holds open)
        (getf reports :race)
      (is eql *interrupts* sent "interrupts sent")
      (is eql *interrupts* taken "interrupts taken")
      (true (and cuts (plusp cuts)) "interrupts that threw: ~A" cuts)
      (true (and renders-after (<= 100 renders-after))
            "renders completed after the interrupts: ~A" renders-after)
      (true joined "the worker stopped when told")
      (is equal '() faults "what the worker signalled")
      (is eql 0 holds "holds left")
      (is equal '(:parsers 0 :roots 0 :buffers 0) open "the child's open counts"))))
