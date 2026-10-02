;;;; Threads (M2 design §5.2, §7.5, §8.4; finding 14): renders from many
;;;; threads at once give the results they give alone, and a first call
;;;; from many threads at once starts up once.

(in-package #:cl-commonmark-gfm.native-tests)

;;; Threads that start together. Parachute records results only in the
;;; test's own thread, so each thread hands back what it returned or
;;; signalled, for the test to assert on. Every thread is joined, however
;;; the caller exits.

(defun thread-outcome (thread)
  "Join THREAD and return its outcome: what its function returned, or
(:SIGNALLED CONDITION) for a condition bordeaux-threads saw escape it,
which it reports on joining as BT2:ABNORMAL-EXIT."
  (handler-case (bt2:join-thread thread)
    (bt2:abnormal-exit (exit)
      (list :signalled (bt2:abnormal-exit-condition exit)))))

(defstruct (gate (:constructor make-gate ()))
  "Where CALL-TOGETHER's threads wait, to start together: its LOCK, the
ARRIVAL and OPENING condition variables, how many threads have ARRIVED,
and whether it is OPEN."
  (lock (bt2:make-lock :name "call-together"))
  (arrival (bt2:make-condition-variable :name "call-together arrival"))
  (opening (bt2:make-condition-variable :name "call-together opening"))
  (arrived 0)
  (open nil))

(defun count-arrival (gate counted)
  "Count this thread as arrived at GATE, unless COUNTED, the thread's own
cons, says in its CAR that it already was."
  (bt2:with-lock-held ((gate-lock gate))
    (unless (car counted)
      (setf (car counted) t)
      (incf (gate-arrived gate))
      (bt2:condition-broadcast (gate-arrival gate)))))

;;; NOTINLINE so a test can redefine it: CLHS 3.2.2.3 lets a compiler
;;; assume a call within one file refers to the definition in that file.
(declaim (notinline arrive-at-gate))

(defun arrive-at-gate (gate counted)
  "Count this thread at GATE, by COUNT-ARRIVAL, then wait until it opens."
  (count-arrival gate counted)
  (bt2:with-lock-held ((gate-lock gate))
    (loop until (gate-open gate)
          do (bt2:condition-wait (gate-opening gate) (gate-lock gate)))))

(defun open-gate (gate arrivals)
  "Wait until ARRIVALS threads have been counted at GATE, then open it."
  (bt2:with-lock-held ((gate-lock gate))
    (loop until (>= (gate-arrived gate) arrivals)
          do (bt2:condition-wait (gate-arrival gate) (gate-lock gate)))
    (setf (gate-open gate) t)
    (bt2:condition-broadcast (gate-opening gate))))

(defun call-at-gate (gate function)
  "In a thread of CALL-TOGETHER's: wait at GATE, then call FUNCTION, and
return the outcome, (:RETURNED VALUE) or (:SIGNALLED CONDITION) for a
serious condition. The thread is counted at GATE however it leaves, even
before it gets there, so the gate still opens for the others."
  (let ((counted (list nil)))
    (unwind-protect
         (handler-case (progn
                         (arrive-at-gate gate counted)
                         (list :returned (funcall function)))
           (serious-condition (condition)
             (list :signalled condition)))
      (count-arrival gate counted))))

(defun call-together (functions)
  "Call each of FUNCTIONS, functions of no arguments, in a thread of its
own, and return the threads' outcomes, in order: (:RETURNED VALUE), or
(:SIGNALLED CONDITION) when the function signalled a serious condition.
The threads start together: each waits at a gate, which opens once every
thread has reached it. Every thread is joined, however this exits."
  (let ((gate (make-gate))
        (threads '())
        (outcomes '()))
    (unwind-protect
         (progn
           (dolist (function functions)
             (let ((function function))
               (push (bt2:make-thread (lambda () (call-at-gate gate function))
                                      :name "cl-commonmark-gfm native test")
                     threads)))
           (open-gate gate (length threads)))
      ;; However we got here, no thread is left waiting at the gate.
      (open-gate gate 0)
      (setf outcomes (mapcar #'thread-outcome (reverse threads))))
    outcomes))

(defun returned-values (outcomes)
  "The value of each of OUTCOMES whose function returned, in order."
  (loop for (status value) in outcomes
        when (eql status :returned)
          collect value))

(defun signalled-conditions (outcomes)
  "The condition of each of OUTCOMES whose function signalled, in order."
  (loop for (status value) in outcomes
        when (eql status :signalled)
          collect value))

;;; Concurrent startup (M2 design §5.2, §8.4)

(defparameter *startup-threads* 8
  "How many threads make their first call at once.")

(defun slow-version-string (seconds)
  "A replacement for NATIVE::%VERSION-STRING that sleeps SECONDS, then
returns the real version: it holds step 4 of a startup open long enough for
every thread to make its call while the startup runs."
  (let ((version-string (fdefinition 'native::%version-string)))
    (lambda ()
      (sleep seconds)
      (funcall version-string))))

(define-test concurrent-first-calls-start-up-once
  ;; Without the startup lock, every thread would find nothing published,
  ;; start up, and publish a state of its own.
  (with-startup-reset
    (let* ((startups (native-startup-count))
           (outcomes (with-redefined ((native::%version-string (slow-version-string 0.25)))
                       (call-together (loop repeat *startup-threads* collect #'native-state))))
           (states (returned-values outcomes)))
      (false (signalled-conditions outcomes) "no thread signalled")
      (is = *startup-threads* (length states) "every thread got a state")
      (is = (1+ startups) (native-startup-count) "startups published")
      (is = 1 (length (remove-duplicates states)) "distinct states the threads got")
      (true (eql (native-state) (first states)) "the threads got the published state")
      (true (open-counts-zero-p)))))

;;; Concurrent renders (M2 design §7.5, §8.4; finding 14). Inline parsing
;;; happens only in cmark_parser_finish (finalize_document, then
;;; process_inlines, src/blocks.c). process_inlines adds the attached
;;; extensions' special characters, ~ for strikethrough and : and w for
;;; autolink, to two process-wide tables, SPECIAL_CHARS and SKIP_CHARS
;;; (cmark_inlines_add_special_character, src/inlines.c), and removes them
;;; when it is done. Two finishes at once corrupt each other's inlines. The
;;; inputs are finding 14's.

(defparameter *race-threads* 8
  "How many threads render at once, half of them each race document.")

(defparameter *race-renders* 40
  "How many times each race thread renders its document.")

(defun paragraphs (text count)
  "COUNT paragraphs of TEXT, each followed by a blank line."
  (cl-commonmark-gfm.tests::repeat-string (format nil "~A~%~%" text) count))

(defun gfm-race-markdown ()
  "Finding 14's GFM input, 136,000 octets: 2,000 paragraphs, each with a
strikethrough and two autolinks. A parse loses them when another parse's
finish removes ~, : and w from the tables while it runs."
  (paragraphs "Some ~~struck~~ text and www.example.com and https://x.org/y here." 2000))

(defun commonmark-race-markdown ()
  "Finding 14's CommonMark input, 84,000 octets: 4,000 paragraphs of
a~_b_~c. While a GFM parse holds ~ in SKIP_CHARS, a parse without
extensions skips the ~ when it reads the characters around each _, finds
letters on both sides, and the _ can neither open nor close (scan_delims,
src/inlines.c): the emphasis is lost."
  (paragraphs "a~_b_~c and a~_d_~e" 4000))

(defun render-html-of (markdown options)
  "MARKDOWN rendered by RENDER-HTML with OPTIONS, :HTML options, through a
live native document."
  (call-with-native-document markdown options #'render-html :entry-point :html))

(defun occurrences (part string)
  "How many times PART occurs in STRING, without overlapping."
  (loop with start = 0
        for position = (search part string :start2 start)
        while position
        count t
        do (setf start (+ position (length part)))))

(define-test the-race-documents-hold-what-a-race-loses
  ;; The race's control: rendered alone, the documents hold what finding
  ;; 14's races lost. The counts are the pinned CLI's.
  (is = 2000 (occurrences "<del>" (render-html-of (gfm-race-markdown) '())))
  (is = 4000 (occurrences "<a href=" (render-html-of (gfm-race-markdown) '())))
  (is = 8000 (occurrences "<em>" (render-html-of (commonmark-race-markdown)
                                                 '(:profile :commonmark)))))

(defun race-results ()
  "Race *RACE-THREADS* threads, started together, each rendering one race
document *RACE-RENDERS* times: half the GFM one under :GFM, half the
CommonMark one under :COMMONMARK. Return a plist:
- :GFM-COMPARED and :GFM-WRONG, how many GFM renders were compared with
  the GFM document's render made alone, and how many differed;
- :COMMONMARK-COMPARED and :COMMONMARK-WRONG, the same for the other;
- :MOST-AT-ONCE, the most renders under way at one moment;
- :SIGNALLED, the conditions threads signalled."
  (let* ((jobs (list (list :gfm (gfm-race-markdown) '())
                     (list :commonmark (commonmark-race-markdown) '(:profile :commonmark))))
         (alone (loop for (nil markdown options) in jobs
                      collect (render-html-of markdown options)))
         (lock (bt2:make-lock :name "race meter"))
         (under-way 0)
         (most-at-once 0))
    (flet ((metered-render (markdown options)
             (bt2:with-lock-held (lock)
               (setf most-at-once (max most-at-once (incf under-way))))
             (unwind-protect (render-html-of markdown options)
               (bt2:with-lock-held (lock)
                 (decf under-way)))))
      (let ((outcomes
              (call-together
               (loop for index below *race-threads*
                     collect (let ((job (nth (mod index (length jobs)) jobs))
                                   (expected (nth (mod index (length jobs)) alone)))
                               (lambda ()
                                 (destructuring-bind (label markdown options) job
                                   (loop repeat *race-renders*
                                         count t into compared
                                         count (string/= expected (metered-render markdown options))
                                           into wrong
                                         finally (return (list label compared wrong))))))))))
        (flet ((total (label position)
                 (loop for result in (returned-values outcomes)
                       when (eql (first result) label)
                         sum (nth position result))))
          (list :gfm-compared (total :gfm 1)
                :gfm-wrong (total :gfm 2)
                :commonmark-compared (total :commonmark 1)
                :commonmark-wrong (total :commonmark 2)
                :most-at-once (bt2:with-lock-held (lock) most-at-once)
                :signalled (signalled-conditions outcomes)))))))

(define-test concurrent-renders-equal-renders-made-alone
  ;; Without the finish lock, dozens of each document's renders come out
  ;; wrong: GFM ones lose strikethroughs and links, CommonMark ones their
  ;; emphasis.
  (destructuring-bind (&key gfm-compared gfm-wrong commonmark-compared commonmark-wrong
                         most-at-once signalled)
      (race-results)
    (false signalled "no thread signalled")
    (true (<= 2 most-at-once) "renders overlapped: at most ~D at once" most-at-once)
    (is = (* (floor *race-threads* 2) *race-renders*) gfm-compared "GFM renders compared")
    (is = 0 gfm-wrong "GFM renders unlike the render made alone")
    (is = (* (floor *race-threads* 2) *race-renders*) commonmark-compared
        "CommonMark renders compared")
    (is = 0 commonmark-wrong "CommonMark renders unlike the render made alone")
    (true (open-counts-zero-p))))

;;; CALL-TOGETHER's gate survives a thread that dies before reaching it. It
;;; opens once every thread is counted, and a thread is counted however it
;;; leaves, even before it arrives: otherwise the others would wait forever.

(defun call-together-with-a-failed-arrival (seconds)
  "Run CALL-TOGETHER, in a thread of its own, on four functions, with the
first thread to reach the gate failing before it is counted there. Return
the outcomes, or :TIMED-OUT when CALL-TOGETHER hasn't returned within
SECONDS: its threads are then left waiting."
  (let ((arrive (fdefinition 'arrive-at-gate))
        (lock (bt2:make-lock :name "failed arrival"))
        (failed nil))
    (with-redefined ((arrive-at-gate
                      (lambda (gate counted)
                        (when (bt2:with-lock-held (lock)
                                (prog1 (not failed) (setf failed t)))
                          (error "a thread failed before it reached the gate"))
                        (funcall arrive gate counted))))
      (let* ((outcomes :timed-out)
             (caller (bt2:make-thread
                      (lambda ()
                        (setf outcomes (call-together (loop for index below 4
                                                            collect (let ((index index))
                                                                      (lambda () index))))))
                      :name "call-together caller")))
        (loop repeat (* 20 seconds)
              while (bt2:thread-alive-p caller)
              do (sleep 0.05))
        (cond
          ((bt2:thread-alive-p caller) :timed-out)
          (t (bt2:join-thread caller)
             outcomes))))))

(define-test call-together-returns-when-a-thread-fails-before-the-gate
  (let ((outcomes (call-together-with-a-failed-arrival 10)))
    (false (eql outcomes :timed-out) "call-together returned")
    (when (listp outcomes)
      (is = 1 (count :signalled outcomes :key #'first) "threads that signalled")
      (is = 3 (count :returned outcomes :key #'first) "threads that returned"))))

;;; Closing cmark under a parse (M2 design §5.3; finding 18). A call holds
;;; the published state from the moment the startup lock hands it over
;;; until its document is released. While any call holds it, closing
;;; signals and closes nothing: the state stays published, both libraries
;;; stay loaded, and the call goes on unharmed.

(defstruct (rendezvous (:constructor make-rendezvous ()))
  "Where a worker waits for the main thread: its LOCK and CHANGED
condition variable, whether the worker has ARRIVED, and whether the main
thread has RELEASED it."
  (lock (bt2:make-lock :name "rendezvous"))
  (changed (bt2:make-condition-variable :name "rendezvous"))
  (arrived nil)
  (released nil))

(defparameter *rendezvous-seconds* 30
  "The longest either side waits at a rendezvous before giving up.")

(defun rendezvous-wait (rendezvous predicate)
  "Wait until PREDICATE, a function of RENDEZVOUS read under its lock, is
true, or *RENDEZVOUS-SECONDS* have passed. Return whether it is true."
  (let ((deadline (+ (get-internal-real-time)
                     (* *rendezvous-seconds* internal-time-units-per-second))))
    (bt2:with-lock-held ((rendezvous-lock rendezvous))
      (loop until (funcall predicate rendezvous)
            while (< (get-internal-real-time) deadline)
            do (bt2:condition-wait (rendezvous-changed rendezvous) (rendezvous-lock rendezvous)
                                   :timeout 1))
      (and (funcall predicate rendezvous) t))))

(defun rendezvous-note (rendezvous writer)
  "Call WRITER, a function of RENDEZVOUS, under its lock, and wake every
thread waiting there."
  (bt2:with-lock-held ((rendezvous-lock rendezvous))
    (funcall writer rendezvous)
    (bt2:condition-broadcast (rendezvous-changed rendezvous))))

(defun waiting-once (rendezvous original)
  "A replacement for ORIGINAL, a function, that on its first call notes its
arrival at RENDEZVOUS and waits there to be released, then calls ORIGINAL;
on any later call, just calls ORIGINAL."
  (let ((first t))
    (lambda (&rest arguments)
      (when (bt2:with-lock-held ((rendezvous-lock rendezvous))
              (prog1 first (setf first nil)))
        (rendezvous-note rendezvous (lambda (r) (setf (rendezvous-arrived r) t)))
        (rendezvous-wait rendezvous #'rendezvous-released))
      (apply original arguments))))

(defparameter *held-markdown* "*hi* ~~gone~~ and www.example.com, with a note[^a].

[^a]: A note."
  "What each worker renders: emphasis, a strikethrough, an autolink and a
footnote.")

(defparameter *held-entry-points*
  (list (list 'parse (lambda (markdown) (html-tree->string (ast->html-tree (parse markdown)))))
        (list 'markdown->html #'markdown->html)
        (list 'markdown->plaintext #'markdown->plaintext)
        (list 'markdown->html-tree (lambda (markdown)
                                     (html-tree->string (markdown->html-tree markdown)))))
  "Each entry point, as (NAME FUNCTION): FUNCTION turns Markdown into a
string through it.")

(defparameter *held-moments* '(native::%parser-new native::free-root)
  "Where a worker waits while the main thread closes: before cmark creates
its parser, and as its document is released, after rendering.")

(defun reset-while-held (render moment)
  "Start a worker calling RENDER on *HELD-MARKDOWN*. Once it reaches
MOMENT, a native function it then waits in, call RESET-NATIVE-STATE, note
what is left, and let the worker go on. Return a plist:
- :ARRIVED, whether the worker reached MOMENT;
- :RESET, the type of what the reset signalled, or :RETURNED;
- :PUBLISHED and :LOADED, whether right after it the state was still
  published and both its libraries still loaded;
- :STARTUPS, the startups published meanwhile;
- :WORKER, (:RETURNED STRING) or (:SIGNALLED CONDITION);
- :EXPECTED, RENDER's result made alone."
  (let ((expected (funcall render *held-markdown*))
        (paths (state-paths))
        (startups (native-startup-count))
        (rendezvous (make-rendezvous))
        (worker nil)
        (facts '()))
    (call-with-redefined
     moment (waiting-once rendezvous (fdefinition moment))
     (lambda ()
       (unwind-protect
            (progn
              (setf worker (bt2:make-thread
                            (lambda ()
                              (handler-case (list :returned (funcall render *held-markdown*))
                                (serious-condition (condition) (list :signalled condition))))
                            :name "held-state worker"))
              (let ((arrived (rendezvous-wait rendezvous #'rendezvous-arrived)))
                (setf facts
                      (list :arrived arrived
                            :reset (handler-case (progn (reset-native-state) :returned)
                                     (error (condition) (type-of condition)))
                            :published (native-state-published-p)
                            :loaded (every #'loaded-p paths)))))
         (rendezvous-note rendezvous (lambda (r) (setf (rendezvous-released r) t)))
         (when worker
           (setf facts (append facts (list :worker (thread-outcome worker))))))))
    (append facts (list :startups (- (native-startup-count) startups)
                        :expected expected))))

(define-test closing-under-a-held-state-signals-and-closes-nothing
  (native-state)
  (dolist (entry-point *held-entry-points*)
    (destructuring-bind (name render) entry-point
      (dolist (moment *held-moments*)
        (destructuring-bind (&key arrived reset published loaded worker startups expected)
            (reset-while-held render moment)
          (let ((where (format nil "~(~A~), waiting in ~(~A~)" name moment)))
            (true arrived "~A: the worker arrived" where)
            (is eql 'native::native-state-held reset "~A: the reset signalled" where)
            (true published "~A: the state is still published" where)
            (true loaded "~A: both libraries are still loaded" where)
            (is = 0 startups "~A: no startup since" where)
            (is eql :returned (first worker) "~A: the worker returned" where)
            (is equal expected (second worker) "~A: the worker's result" where))))))
  (true (open-counts-zero-p)))

(defparameter *reset-renders* 20
  "How many times the worker renders while the main thread closes.")

(defun reset-while-rendering ()
  "Render the GFM race document *RESET-RENDERS* times in a worker, while
the main thread calls RESET-NATIVE-STATE again and again until it is done.
Return a plist: :RENDERS and :WRONG, the worker's renders and how many
differed from the one made alone; :FAULTS, the type of each condition the
worker signalled; :HELD and :CLOSED, how many resets signalled
NATIVE-STATE-HELD and how many closed cmark; :OTHER, the type of any other
condition a reset signalled."
  (let* ((markdown (gfm-race-markdown))
         (expected (markdown->html markdown))
         (lock (bt2:make-lock :name "reset race"))
         (renders 0)
         (wrong 0)
         (faults '())
         (done nil)
         (held 0)
         (closed 0)
         (other '())
         (worker (bt2:make-thread
                  (lambda ()
                    (unwind-protect
                         (loop repeat *reset-renders*
                               do (handler-case
                                      (let ((html (markdown->html markdown)))
                                        (bt2:with-lock-held (lock)
                                          (incf renders)
                                          (unless (string= expected html)
                                            (incf wrong))))
                                    (serious-condition (condition)
                                      (bt2:with-lock-held (lock)
                                        (push (type-of condition) faults)))))
                      (bt2:with-lock-held (lock)
                        (setf done t))))
                  :name "reset race worker")))
    (unwind-protect
         (loop until (bt2:with-lock-held (lock) done)
               do (handler-case (progn (reset-native-state) (incf closed))
                    (native::native-state-held () (incf held))
                    (error (condition) (push (type-of condition) other)))
                  (sleep 0.001))
      (bt2:join-thread worker))
    (list :renders renders :wrong wrong :faults faults :held held :closed closed :other other)))

(define-test closing-while-a-worker-renders-never-harms-it
  (destructuring-bind (&key renders wrong faults held closed other) (reset-while-rendering)
    (is = *reset-renders* renders "renders")
    (is = 0 wrong "renders unlike the one made alone")
    (is equal '() faults "what the worker signalled")
    (is equal '() other "what the resets signalled, but NATIVE-STATE-HELD")
    (true (plusp held) "resets that signalled: ~D, resets that closed: ~D" held closed))
  (true (open-counts-zero-p)))
