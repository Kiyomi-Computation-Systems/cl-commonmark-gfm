;;;; Helpers for the native suite: redefining an internal wrapper for one
;;;; test, reading the counters, finding fixtures, and running a function
;;;; on a live native document.

(in-package #:cl-commonmark-gfm.native-tests)

;;; Redefining a function for one test

(defmacro with-redefined ((&rest bindings) &body body)
  "Run BODY with each (NAME FUNCTION) of BINDINGS installed as NAME's global
function, and restore every original in UNWIND-PROTECT, however BODY exits.
FUNCTION is evaluated before any NAME changes. This is how a test makes an
internal wrapper around a cmark call fail or return null: the library
itself has no test hooks."
  (let ((originals (loop repeat (length bindings) collect (gensym "ORIGINAL")))
        (replacements (loop repeat (length bindings) collect (gensym "REPLACEMENT"))))
    `(let (,@(loop for (name) in bindings
                   for original in originals
                   collect `(,original (fdefinition ',name)))
           ,@(loop for (nil function) in bindings
                   for replacement in replacements
                   collect `(,replacement ,function)))
       (unwind-protect
            (progn
              ,@(loop for (name) in bindings
                      for replacement in replacements
                      collect `(setf (fdefinition ',name) ,replacement))
              ,@body)
         ,@(loop for (name) in bindings
                 for original in originals
                 collect `(setf (fdefinition ',name) ,original))))))

(defun call-with-redefined (name function thunk)
  "Call THUNK with FUNCTION installed as NAME's global function, and restore
the original in UNWIND-PROTECT: WITH-REDEFINED for a NAME known only at
run time."
  (let ((original (fdefinition name)))
    (unwind-protect
         (progn
           (setf (fdefinition name) function)
           (funcall thunk))
      (setf (fdefinition name) original))))

;;; Asserting on what was signalled

(defmacro raised (type form &optional description &rest format-arguments)
  "Assert that FORM signals a condition of exactly TYPE, with Parachute's
FAIL, and return the condition, or NIL when FORM signalled nothing of TYPE.
A subtype of TYPE fails the second assertion: the test asserts on what was
signalled, not on something that merely satisfies TYPEP. DESCRIPTION and
FORMAT-ARGUMENTS describe both assertions, as in FAIL."
  (let ((condition (gensym "CONDITION")))
    `(let ((,condition (fail ,form ',type ,description ,@format-arguments)))
       (is eql ',type (type-of ,condition) ,description ,@format-arguments)
       (and (typep ,condition ',type) ,condition))))

;;; The counters

(defun open-counts-zero-p ()
  "True when no parser, root or buffer is open."
  (loop for (nil count) on (native-open-counts) by #'cddr always (zerop count)))

(defun created-parsers ()
  "The number of parsers ever created: a monotonic counter."
  (getf (native-created-counts) :parsers))

(defun created-buffers ()
  "The number of render buffers ever created: a monotonic counter."
  (getf (native-created-counts) :buffers))

;;; Fixtures

(defun fixture-path (name)
  "The absolute pathname of tests/fixtures/NAME."
  (asdf:system-relative-pathname "cl-commonmark-gfm" (concatenate 'string "tests/fixtures/" name)))

(defun fixture-string (name)
  "tests/fixtures/NAME's contents, read as UTF-8."
  (uiop:read-file-string (fixture-path name) :external-format :utf-8))

;;; A live document

(defun call-with-native-document (string options function &key (entry-point :parse))
  "Check OPTIONS, a plist, as ENTRY-POINT's options (:PARSE, :HTML,
:PLAINTEXT or :HTML-TREE), parse STRING with them, and call FUNCTION with
the live document and the CHECKED-OPTIONS. Returns what FUNCTION returns.
The native tests use this to reach a live document, which no entry point
hands out."
  (let ((checked-options (check-options entry-point 'call-with-native-document options)))
    (with-native-document (document string checked-options)
      (funcall function document checked-options))))

(defun type-strings-entered (document)
  "The type string of every node of DOCUMENT, in the order WALK-NATIVE
enters them."
  (let ((type-strings '()))
    (walk-native (lambda (event node)
                   (when (eql event :enter)
                     (push (native-type-string document node) type-strings)))
                 document)
    (nreverse type-strings)))

(defun nodes-of-kind (document kind)
  "Every node of DOCUMENT whose classified kind is KIND, in walk order."
  (let ((nodes '()))
    (walk-native (lambda (event node)
                   (when (and (eql event :enter) (eql (native-kind document node) kind))
                     (push node nodes)))
                 document)
    (nreverse nodes)))

;;; The native state

(defun state-paths ()
  "The two library paths of the published native state, starting up first
when nothing is published."
  (native::state-paths (native-state)))

(defun loaded-library-namestrings ()
  "The native namestring of every foreign library CFFI lists as loaded.
CFFI keeps the pathname it parsed from the path it loaded: from a string
holding a *, as CCL's loads are given, that pathname is wild, and has no
native namestring, so its namestring, the string it was parsed from, is
taken instead (on CCL and SBCL; CCL's NATIVE-TRANSLATED-NAMESTRING signals
on it)."
  (loop for library in (cffi:list-foreign-libraries)
        for pathname = (cffi:foreign-library-pathname library)
        when pathname
          collect (if (wild-pathname-p pathname)
                      (namestring pathname)
                      (uiop:native-namestring pathname))))

(defun loaded-p (path)
  "True when CFFI lists a loaded foreign library at PATH."
  (and (member path (loaded-library-namestrings) :test #'string=) t))

(defun startup-failure ()
  "Call NATIVE-STATE and return the ERROR it signals, or NIL when startup
succeeds."
  (handler-case (progn (native-state) nil)
    (error (condition) condition)))

;;; Test threads, locks and joins with a time limit. A condition that
;;; escapes a thread bordeaux-threads started ends CCL's whole batch run,
;;; exit 255, and every result is lost. On CCL, a lock wait with :TIMEOUT
;;; signals one, BT2::KEYARG-NOT-IMPLEMENTED. So every test thread goes
;;; through MAKE-TEST-THREAD, and every lock wait and join with a deadline
;;; polls: CCL's bordeaux-threads doesn't implement WITH-LOCK-HELD's or
;;; ACQUIRE-LOCK's :TIMEOUT
;;; (ocicl/bordeaux-threads-0.9.4/apiv2/impl-clozure.lisp,
;;; BT2::SIGNAL-NOT-IMPLEMENTED, raised only when TIMEOUT is non-NIL: a
;;; plain :WAIT NIL calls CCL:TRY-LOCK, which it does implement), and
;;; JOIN-THREAD takes no time limit on any Lisp
;;; (ocicl/bordeaux-threads-0.9.4/apiv2/api-threads.lisp). Semaphore waits
;;; still use :TIMEOUT, which CCL's does implement, by
;;; CCL:TIMED-WAIT-ON-SEMAPHORE (impl-clozure.lisp).

(defun make-test-thread (function &key name)
  "Start FUNCTION in a new thread, as BT2:MAKE-THREAD, with no condition
able to escape it: FUNCTION runs inside a HANDLER-CASE on SERIOUS-
CONDITION, so a test thread can signal without ending the whole run. On
CCL, a condition that otherwise escapes a thread ends the whole batch run.
Returns the thread; THREAD-OUTCOME (threads.lisp) gives back FUNCTION's
value, or (:SIGNALLED CONDITION) for a condition that would have escaped
it."
  (bt2:make-thread (lambda ()
                     (handler-case (funcall function)
                       (serious-condition (condition) (list :signalled condition))))
                   :name name))

(defun seconds-since (start)
  "The seconds elapsed since START, a GET-INTERNAL-REAL-TIME value."
  (float (/ (- (get-internal-real-time) start) internal-time-units-per-second)))

(defun ended-within-p (thread seconds)
  "True once THREAD has ended, within SECONDS; NIL when it is still alive
at the deadline. Polls BT2:THREAD-ALIVE-P, and never joins THREAD: a
caller that can't join, such as CCL's save hooks, uses it alone."
  (let ((deadline (+ (get-internal-real-time) (* seconds internal-time-units-per-second))))
    (loop
      (unless (bt2:thread-alive-p thread)
        (return t))
      (when (>= (get-internal-real-time) deadline)
        (return nil))
      (sleep 0.01))))

(defun join-within (thread seconds)
  "THREAD-OUTCOME of THREAD once it ends within SECONDS, or :TIMED-OUT
when it is still alive at the deadline. Polls, by ENDED-WITHIN-P:
bordeaux-threads' JOIN-THREAD takes no time limit on any Lisp."
  (if (ended-within-p thread seconds)
      (thread-outcome thread)
      :timed-out))

(defun call-with-lock-within (lock seconds function)
  "Call FUNCTION holding LOCK, and return (VALUES RESULT T). Return
(VALUES NIL NIL), without calling FUNCTION, when LOCK can't be had within
SECONDS. Polls BT2:ACQUIRE-LOCK with :WAIT NIL, never passing :TIMEOUT
-- CCL's bordeaux-threads doesn't implement it -- and releases LOCK
however FUNCTION exits."
  (let ((deadline (+ (get-internal-real-time) (* seconds internal-time-units-per-second))))
    (loop
      (when (bt2:acquire-lock lock :wait nil)
        (return (unwind-protect (values (funcall function) t)
                  (bt2:release-lock lock))))
      (when (>= (get-internal-real-time) deadline)
        (return (values nil nil)))
      (sleep 0.01))))

(defun interrupts-enabled-p ()
  "True when this thread's interrupts are enabled, by each Lisp's own
indicator, each true outside and false inside NATIVE::WITH-INTERRUPTS-
DEFERRED, even nested, as INTERRUPTS-ENABLED-P-IS-TRUE-IN-A-TEST-AND-FALSE-
WHILE-DEFERRED checks on each Lisp:
- SBCL: SB-SYS:*INTERRUPTS-ENABLED*;
- CCL: CCL::*INTERRUPT-LEVEL* is 0 outside and -1 inside CCL:WITHOUT-
  INTERRUPTS, so the test is that it isn't negative. CCL's package has no
  external symbol of this name (apropos found it only as CCL::, not
  CCL:): reading it needs the internal symbol;
- ECL: EXT:*INTERRUPTS-ENABLED* -- SI:*INTERRUPTS-ENABLED* names the same
  symbol, both exported -- is T outside and NIL inside MP:WITHOUT-
  INTERRUPTS."
  #+sbcl sb-sys:*interrupts-enabled*
  #+ccl (not (minusp ccl::*interrupt-level*))
  #+ecl ext:*interrupts-enabled*
  #-(or sbcl ccl ecl)
  (error "cl-commonmark-gfm.native-tests reads interrupts-enabled-p on SBCL, CCL and ECL ~
         only, not ~A" (lisp-implementation-type)))

(define-test a-signalling-test-thread-gives-signalled-and-the-suite-goes-on
  ;; On CCL, a thread whose function signals an uncaught condition ends the
  ;; whole batch run: without MAKE-TEST-THREAD's handler, there would be no
  ;; later test, this one included, to report this.
  (destructuring-bind (status condition)
      (thread-outcome (make-test-thread (lambda () (error "a test thread's own error"))
                                        :name "signalling test thread"))
    (is eql :signalled status)
    (is eql 'simple-error (type-of condition))))

;;; A wait that ignored its deadline must fail these tests, not hang them.
;;; So what each wait is kept waiting on is freed after 5 seconds even if
;;; the test never frees it: such a wait would return then, late and with
;;; what it waited for, and fail. No thread is joined twice: CCL's
;;; JOIN-PROCESS waits on the thread's termination semaphore, which the
;;; first join takes (CCL 1.13's level-1/l1-processes.lisp).

(define-test join-within-times-out-then-gives-the-outcome-once-released
  (let* ((semaphore (bt2:make-semaphore :name "join-within probe"))
         (release-now (bt2:make-semaphore :name "release the probe thread now"))
         (thread (make-test-thread (lambda () (bt2:wait-on-semaphore semaphore) :released)
                                   :name "join-within probe thread"))
         (releaser (make-test-thread (lambda ()
                                       (bt2:wait-on-semaphore release-now :timeout 5)
                                       (bt2:signal-semaphore semaphore))
                                     :name "join-within releaser"))
         (start (get-internal-real-time))
         (outcome (join-within thread 0.2))
         (seconds (seconds-since start)))
    (is eql :timed-out outcome "the thread was still waiting at the deadline")
    (true (< seconds 1) "join-within returned at its deadline: ~,2F s" seconds)
    (bt2:signal-semaphore release-now)
    ;; A join that waited past its deadline has joined the thread already.
    (is eql :released (if (eql outcome :timed-out) (join-within thread 10) outcome)
        "the outcome, once released")
    (join-within releaser 10)))

(define-test call-with-lock-within-while-held-gives-nil-and-nil
  (let* ((lock (bt2:make-lock :name "call-with-lock-within probe"))
         (holding (bt2:make-semaphore :name "the lock is held"))
         (release (bt2:make-semaphore :name "release the lock"))
         (holder (make-test-thread (lambda ()
                                     (bt2:with-lock-held (lock)
                                       (bt2:signal-semaphore holding)
                                       (bt2:wait-on-semaphore release :timeout 5)))
                                   :name "lock holder")))
    (unwind-protect
         (progn
           (true (bt2:wait-on-semaphore holding :timeout 5) "the holder took the lock")
           (let ((start (get-internal-real-time)))
             (multiple-value-bind (result got-it)
                 (call-with-lock-within lock 0.2 (lambda () :unreached))
               (let ((seconds (seconds-since start)))
                 (false got-it "the lock wasn't had")
                 (false result "the function wasn't called")
                 (true (< seconds 1) "call-with-lock-within gave up at its deadline: ~,2F s"
                       seconds)))))
      (bt2:signal-semaphore release)
      (join-within holder 10))))

(define-test call-with-lock-within-on-a-free-lock-returns-the-value-and-frees-it
  (let ((lock (bt2:make-lock :name "call-with-lock-within free probe")))
    (multiple-value-bind (result got-it) (call-with-lock-within lock 5 (lambda () :done))
      (is eql :done result)
      (true got-it))
    (true (bt2:acquire-lock lock :wait nil) "the lock is free afterward")
    (bt2:release-lock lock)))

(define-test interrupts-enabled-p-is-true-in-a-test-and-false-while-deferred
  (true (interrupts-enabled-p) "the control: interrupts are enabled in the test")
  (native::with-interrupts-deferred
    (false (interrupts-enabled-p) "false inside with-interrupts-deferred")
    (native::with-interrupts-deferred
      (false (interrupts-enabled-p) "false inside a nested with-interrupts-deferred"))
    (false (interrupts-enabled-p) "still false once the nested region ends"))
  (true (interrupts-enabled-p) "true again once the outer region ends"))
