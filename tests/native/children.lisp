;;;; Children on every Lisp. The saved-image tests (image.lisp) and the
;;;; interrupt race (interrupts.lisp) run in a child of this Lisp, with a
;;;; time limit, so a child that deadlocks fails its test instead of
;;;; hanging the suite. A child reports facts back by printing them, and the
;;;; parent reads them from its output.
;;;;
;;;; CCL's release binary sometimes hangs before any Lisp code runs. So a
;;;; child prints *CHILD-START-LINE* as its first act, and one that hasn't
;;;; printed it within *CHILD-START-SECONDS* is killed and started again, up
;;;; to three times on CCL, as scripts/lisp-start-watchdog does for the
;;;; suites. Only a child that never started is started again: once it has
;;;; started, its outcome counts. That hang never happened in the Guix
;;;; container's CCL, so the tests below show the retry with fake children,
;;;; through RUN-CHILD's COMMAND.

(in-package #:cl-commonmark-gfm.native-tests)

;;; Reports. A child reports a fact by printing a line: *REPORT-PREFIX*, a
;;; key, then a value. The parent reads the reports back from its output.

(defparameter *report-prefix* "saved-image-report"
  "What starts each line a child prints to report a fact.")

(defun report-to-parent (key value)
  "In a child that loaded this suite: report KEY's VALUE to the parent, on
a line CHILD-REPORTS reads."
  (format t "~&~A ~S ~S~%" *report-prefix* key value)
  (finish-output))

(defun child-reports (output)
  "What a child's OUTPUT reports, as a plist: for each line that starts
with *REPORT-PREFIX*, the key and then the value printed after it, read
with *READ-EVAL* off. A value can run onto the lines after it, as a string
holding a newline does. Reading stops at the first report it can't read."
  (let ((*read-eval* nil)
        (marker (format nil "~%~A " *report-prefix*))
        (text (concatenate 'string (string #\Newline) output))
        (index 0)
        (reports '()))
    (handler-case
        (loop for start = (search marker text :start2 index)
              while start
              do (multiple-value-bind (key after-key)
                     (read-from-string text t nil :start (+ start (length marker))
                                                  :preserve-whitespace t)
                   (multiple-value-bind (value after-value)
                       (read-from-string text t nil :start after-key :preserve-whitespace t)
                     (push key reports)
                     (push value reports)
                     (setf index after-value))))
      (error () nil))
    (nreverse reports)))

;;; Temporary directories

(defun string-head (string length)
  "The first LENGTH characters of STRING, or all of it when it is shorter."
  (subseq string 0 (min (length string) length)))

(defun new-temporary-directory ()
  "Create a directory, under the temporary directory, that no other
process is using, and return its pathname."
  (let ((random-state (make-random-state t)))
    (loop for directory = (uiop:ensure-directory-pathname
                           (merge-pathnames (format nil "cl-commonmark-gfm-~36R"
                                                    (random (expt 36 8) random-state))
                                            (uiop:temporary-directory)))
          when (nth-value 1 (ensure-directories-exist directory))
            return directory)))

(defun call-with-temporary-directory (function)
  "Call FUNCTION with a new, empty directory, and delete the directory and
everything in it however FUNCTION exits."
  (let ((directory (new-temporary-directory)))
    (unwind-protect (funcall function directory)
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

;;; The runner

(defparameter *child-seconds* 120
  "How long a child may run before it is killed, and its test fails.")

(defparameter *child-start-seconds* 30
  "How long a child may take to print *CHILD-START-LINE* before it is
killed and, while it has tries left, started again.")

(defparameter *child-start-tries* #+ccl 3 #-ccl 1
  "How many times RUN-CHILD starts a child that never prints its start
line: three times on CCL, whose release binary sometimes hangs before any
Lisp code runs, as scripts/lisp-start-watchdog does for the suites; once
elsewhere.")

(defparameter *child-start-line* ";; child started"
  "The line a child prints, and flushes, as its first act. Output written
to a file is buffered, so an unflushed line would look like a hang.")

(defun child-start-form ()
  "The form, as a string, with which a child prints *CHILD-START-LINE* and
flushes it. RUN-CHILD puts it before a child's own forms."
  (format nil "(progn (fresh-line) (write-line ~S) (finish-output))" *child-start-line*))

(defun form-arguments (option forms)
  "The command-line arguments that give a Lisp each of FORMS, strings, to
evaluate in turn: OPTION before each."
  (loop for form in forms
        append (list option form)))

(defun lisp-command-line (forms image)
  "The command line of a child of this Lisp that starts from IMAGE, a saved
image, or from this Lisp's own image when IMAGE is NIL, and evaluates
FORMS, strings, in turn, reading no init file:
- SBCL: its runtime, --core and the image, --non-interactive, and one
  --eval a form;
- CCL: its kernel, -I and the image, -n for no init file, -b to exit at
  the end of its input (ccl --help), the null device, and one -e a form;
- ECL: the name it was started by, (SI:ARGV 0), looked up on PATH, -norc,
  and one -eval a form. ECL saves no images."
  #+sbcl (list* sb-ext:*runtime-pathname*
                "--core" (uiop:native-namestring (or image sb-ext:*core-pathname*))
                "--noinform" "--non-interactive" "--no-sysinit" "--no-userinit"
                (form-arguments "--eval" forms))
  #+ccl (list* (ccl::kernel-path)
               "-I" (if image (uiop:native-namestring image) ccl::*heap-image-name*)
               "-n" "-b"
               (form-arguments "-e" forms))
  #+ecl (if image
            (error "ECL saves no images, so no child of ECL starts from ~A" image)
            (list* (si:argv 0) "-norc" (form-arguments "-eval" forms)))
  #-(or sbcl ccl ecl)
  (error "cl-commonmark-gfm.native-tests runs children of SBCL, CCL and ECL only, not ~A"
         (lisp-implementation-type)))

(defun printed-start-line-p (output)
  "True when the file OUTPUT, a child's output, holds *CHILD-START-LINE*.
Read as Latin-1, which decodes any byte, so output that isn't UTF-8 can't
make the check signal."
  (let ((text (with-open-file (stream output :if-does-not-exist nil :external-format :latin-1)
                (and stream (uiop:slurp-stream-string stream)))))
    (and text (search *child-start-line* text) t)))

(defun run-child-once (command output errors seconds)
  "Start COMMAND, a list of strings, once: its input the null device, its
output and error output the files OUTPUT and ERRORS, and its environment
this process's, CL_SOURCE_REGISTRY, the fasl cache and, in the container,
CL_COMMONMARK_GFM_LIBS among it. Kill it with SIGKILL when it hasn't
printed *CHILD-START-LINE* within *CHILD-START-SECONDS*, or is still
running after SECONDS. Return a plist: :KILLED, whether it was; :STARTED,
whether its output holds the start line, read once it has ended, so a line
printed at the last moment counts; :EXIT-CODE, NIL when it was killed."
  (let* ((process (uiop:launch-program command
                                       :input nil
                                       :output output :if-output-exists :supersede
                                       :error-output errors :if-error-output-exists :supersede))
         (launched (get-internal-real-time))
         (deadline (+ launched (* seconds internal-time-units-per-second)))
         (start-deadline (min deadline (+ launched (* *child-start-seconds*
                                                      internal-time-units-per-second))))
         (started nil))
    (loop
      (let ((now (get-internal-real-time)))
        (cond ((not (uiop:process-alive-p process)) (return))
              ((>= now deadline) (return))
              ((and (not started) (>= now start-deadline))
               (if (printed-start-line-p output)
                   (setf started t)
                   (return)))))
      (sleep 0.05))
    (let ((killed (and (uiop:process-alive-p process) t)))
      (when killed
        (uiop:terminate-process process :urgent t))
      (let ((exit-code (uiop:wait-process process)))
        (list :killed killed
              :started (printed-start-line-p output)
              :exit-code (if killed nil exit-code))))))

(defun start-again-p (outcome tries start-tries)
  "True when a child whose try ended in OUTCOME, RUN-CHILD-ONCE's plist, is
started again: it was killed before it printed its start line, and fewer
than START-TRIES tries have run. A child that started, or that ended on
its own, is never started again: its outcome counts."
  (and (getf outcome :killed)
       (not (getf outcome :started))
       (< tries start-tries)))

(defun run-child (forms &key image (seconds *child-seconds*) (start-tries *child-start-tries*)
                          command)
  "Run a child of this Lisp, from IMAGE, a saved image, or this Lisp's own
on SBCL and CCL (ECL takes no image), which evaluates FORMS, strings, in
turn, after printing *CHILD-START-LINE* as its first act. The child gets
the null device as its input, and this process's environment. A child
still running after SECONDS is killed with SIGKILL, so one that deadlocks
fails its test instead of hanging the suite. A child that hasn't printed
its start line within *CHILD-START-SECONDS* is killed and started again,
up to START-TRIES times. COMMAND, a list of strings, replaces this Lisp's
command line, for testing the runner with fake children; FORMS and IMAGE
are then unused. Return a plist, of the last try when there were
several:
- :KILLED, whether the child was killed;
- :EXIT-CODE, NIL when it was;
- :REPORTS, CHILD-REPORTS of its output;
- :ERRORS, the start of its error output, where a Lisp names a condition
  that ended it;
- :STARTED, whether it printed its start line;
- :TRIES, how many times it was started."
  (let ((command (or command (lisp-command-line (cons (child-start-form) forms) image))))
    (call-with-temporary-directory
     (lambda (directory)
       (let ((output (merge-pathnames "output.txt" directory))
             (errors (merge-pathnames "errors.txt" directory)))
         (loop for tries from 1
               for outcome = (run-child-once command output errors seconds)
               unless (start-again-p outcome tries start-tries)
                 return (destructuring-bind (&key killed started exit-code) outcome
                          (list :killed killed
                                :exit-code exit-code
                                :reports (child-reports (uiop:read-file-string output))
                                :errors (string-head (uiop:read-file-string errors) 2000)
                                :started started
                                :tries tries))))))))

;;; A child that loads this suite

(defun child-exit-form ()
  "The form, as a string, that ends a child of this Lisp at once, with exit
code 0, abandoning its other threads, whatever they are doing: _exit(2),
which runs no cleanup. SBCL's EXIT with :ABORT calls it (EXIT's
docstring); CCL and ECL call it through CFFI, which the child has loaded
with this suite. A report is flushed before (REPORT-TO-PARENT).

A child that loaded this suite and left threads that never end --
spinning, sleeping in C, waiting on a semaphore, and deadlocked, some with
interrupts deferred -- is gone within milliseconds of each form below. The
other exits fall short. Without :ABORT, SBCL's EXIT waits its 60-second
*EXIT-TIMEOUT* for those threads. ECL's EXT:QUIT hangs for good on a thread
whose interrupts are deferred, and its EXT:EXIT can hang after a race.
CCL's QUIT is slower, and runs cleanup first.
A-CHILD-OF-THIS-LISP-REPORTS-BACK-AND-EXITS-PAST-A-RUNNING-THREAD holds each
form to that: it ends a child past a thread spinning with interrupts
deferred, within its 30-second limit."
  #+sbcl "(sb-ext:exit :code 0 :abort t)"
  #+(or ccl ecl) "(cffi:foreign-funcall \"_exit\" :int 0 :void)"
  #-(or sbcl ccl ecl)
  (error "cl-commonmark-gfm.native-tests runs children of SBCL, CCL and ECL only, not ~A"
         (lisp-implementation-type)))

(defun suite-child-forms (key form)
  "The forms, as strings, of a child that loads this suite, reports FORM's
value under KEY, and exits at once, abandoning any thread still running
(CHILD-EXIT-FORM). FORM is a string, read in CL-USER."
  (list "(require :asdf)"
        "(asdf:load-system \"cl-commonmark-gfm/native-tests\")"
        (format nil "(cl-commonmark-gfm.native-tests::report-to-parent ~S ~A)" key form)
        (child-exit-form)))

;;; The runner, on fake children: the system shell. A fake that sleeps EXECs
;;; its sleep, so the kill reaches the sleep itself and leaves no orphan.

(defun process-exists-p (pid)
  "True when a process PID exists: kill(PID, 0) succeeds (POSIX)."
  (zerop (cffi:foreign-funcall "kill" :int pid :int 0 :int)))

(defun this-process-id ()
  "This process's ID: getpid() (POSIX)."
  (cffi:foreign-funcall "getpid" :int))

(defun recorded-pids (path)
  "The process IDs the fake children appended to PATH, one a line, in
order."
  (with-open-file (stream path :if-does-not-exist nil)
    (and stream
         (loop for line = (read-line stream nil)
               while line
               collect (parse-integer line)))))

(define-test a-child-that-never-starts-is-killed-and-started-again
  ;; CCL's release binary can hang before any Lisp code runs. This fake
  ;; never prints the start line: each try is killed at the end of its
  ;; start window, and the runner gives up after three.
  (call-with-temporary-directory
   (lambda (directory)
     (let ((pids (merge-pathnames "pids.txt" directory)))
       (destructuring-bind (&key killed exit-code started tries &allow-other-keys)
           (let ((*child-start-seconds* 1))
             (run-child '()
                        :command (list "/bin/sh" "-c"
                                       (format nil "echo $$ >> '~A'; exec sleep 60"
                                               (uiop:native-namestring pids)))
                        :start-tries 3))
         (is eql 3 tries "tries")
         (false started "it never printed the start line")
         (true killed "it was killed")
         (is eql nil exit-code "a killed child has no exit code")
         (let ((started-pids (recorded-pids pids)))
           (is = 3 (length (remove-duplicates started-pids))
               "three children started: ~S" started-pids)
           (true (process-exists-p (this-process-id))
                 "the control: PROCESS-EXISTS-P finds this process")
           (false (some #'process-exists-p started-pids)
                  "none is left running: ~S" started-pids)))))))

(define-test a-child-that-started-is-killed-at-its-limit-and-never-tried-again
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((pids (merge-pathnames "pids.txt" directory))
            (start (get-internal-real-time))
            (outcome (run-child '()
                                :command (list "/bin/sh" "-c"
                                               (format nil "echo $$ >> '~A'; echo '~A'; ~
                                                            exec sleep 60"
                                                       (uiop:native-namestring pids)
                                                       *child-start-line*))
                                :seconds 3
                                :start-tries 3))
            (elapsed (float (/ (- (get-internal-real-time) start)
                               internal-time-units-per-second))))
       (destructuring-bind (&key killed exit-code started tries &allow-other-keys) outcome
         (is eql 1 tries "tries: a child that started is never started again")
         (true started "it printed the start line")
         (true killed "it was killed")
         (is eql nil exit-code "a killed child has no exit code")
         (true (<= 3 elapsed 20) "killed at its 3-second limit, not its own end: ~,1F s" elapsed)
         (let ((started-pids (recorded-pids pids)))
           (is = 1 (length started-pids) "one child started: ~S" started-pids)
           (true (process-exists-p (this-process-id))
                 "the control: PROCESS-EXISTS-P finds this process")
           (false (some #'process-exists-p started-pids)
                  "it isn't left running: ~S" started-pids)))))))

(define-test a-child-that-started-and-exited-is-tried-once-with-its-exit-code
  (destructuring-bind (&key killed exit-code started tries &allow-other-keys)
      (run-child '()
                 :command (list "/bin/sh" "-c"
                                (format nil "echo '~A'; exit 7" *child-start-line*))
                 :start-tries 3)
    (is eql 1 tries "tries")
    (true started "it printed the start line")
    (false killed "it exited on its own")
    (is eql 7 exit-code "its own exit code")))

(define-test a-child-that-ends-before-it-starts-is-tried-once-with-its-exit-code
  ;; As scripts/lisp-start-watchdog treats a run that exits before its
  ;; marker, such as a load error: it isn't hung, so its outcome counts.
  (destructuring-bind (&key killed exit-code started tries &allow-other-keys)
      (run-child '() :command (list "/bin/sh" "-c" "exit 3") :start-tries 3)
    (is eql 1 tries "tries")
    (false started "it never printed the start line")
    (false killed "it exited on its own")
    (is eql 3 exit-code "its own exit code")))

;;; A real child

(defun answer-past-a-running-thread ()
  "In a child: start a thread that never ends and that no interrupt can
stop, since it spins with interrupts deferred, then return a list: 42,
whether that thread is running, and this Lisp's implementation type. The
child's exit form then has to end it with that thread still running."
  (let* ((running (bt2:make-semaphore :name "spinning"))
         (thread (make-test-thread (lambda ()
                                     (native::with-interrupts-deferred
                                       (bt2:signal-semaphore running)
                                       (loop)))
                                   :name "spinning, interrupts deferred")))
    (list 42
          (and (bt2:wait-on-semaphore running :timeout 10) (bt2:thread-alive-p thread) t)
          (lisp-implementation-type))))

(define-test a-child-of-this-lisp-reports-back-and-exits-past-a-running-thread
  ;; 30 seconds, well past the few a child takes to load this suite, and
  ;; short of SBCL's 60-second *EXIT-TIMEOUT*: an exit form that waited for
  ;; the spinning thread, at all or for that long, gets the child killed.
  (destructuring-bind (&key killed exit-code reports errors started &allow-other-keys)
      (run-child (suite-child-forms
                  :answer "(cl-commonmark-gfm.native-tests::answer-past-a-running-thread)")
                 :seconds 30)
    (true started "the child printed its start line")
    (false killed "the child ended within 30 seconds, its spinning thread abandoned")
    (is eql 0 exit-code "the child exits 0; its error output starts:~%~A" errors)
    (is equal (list 42 t (lisp-implementation-type)) (getf reports :answer :unreported)
        "the child reports 42, with its thread still running, from this Lisp")))
