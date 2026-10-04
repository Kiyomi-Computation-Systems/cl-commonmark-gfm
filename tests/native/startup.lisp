;;;; Startup (M2 design §5.2, §8.4; ADR-0009): where the libraries come
;;;; from, what the published state holds, and every startup condition.

(in-package #:cl-commonmark-gfm.native-tests)

;;; A test that resets the native state resets it again however it exits,
;;; so nothing it published, or failed to publish, outlives it. The next
;;; call to NATIVE-STATE starts up afresh.

(defmacro with-startup-reset (&body body)
  "Run BODY after RESET-NATIVE-STATE, and reset again in UNWIND-PROTECT."
  `(unwind-protect
        (progn (reset-native-state) ,@body)
     (reset-native-state)))

;;; Discovery, both ways (M2 design §8.4). In the Guix container,
;;; CL_COMMONMARK_GFM_LIBS names the profile's pair; in CI it is unset and
;;; the directory search finds Debian's. The test asserts whichever applies.

(defun environment-override-paths (value)
  "CL_COMMONMARK_GFM_LIBS's VALUE, \"core:extensions\", as (CORE EXTENSIONS)."
  (let ((colon (position #\: value)))
    (list (subseq value 0 colon) (subseq value (1+ colon)))))

(defun multiarch-directories ()
  "The Linux multiarch directory for this machine's architecture, as a list
of none or one (ADR-0009)."
  (case (uiop:architecture)
    (:x64 (list "/usr/lib/x86_64-linux-gnu"))
    (:arm64 (list "/usr/lib/aarch64-linux-gnu"))
    (t '())))

(defun searched-pair ()
  "The pair ADR-0009's directory search must find on this machine: in the
first of its directories that holds both pinned files, by its table of
directories and filenames, written out here independently of
RESOLVE-CMARK-LIBRARIES. NIL when no directory holds both."
  (multiple-value-bind (directories core extensions)
      (if (eql (uiop:operating-system) :macosx)
          (values (list "/opt/homebrew/lib" "/usr/local/lib")
                  (format nil "libcmark-gfm.~A.dylib" *cmark-gfm-version*)
                  (format nil "libcmark-gfm-extensions.~A.dylib" *cmark-gfm-version*))
          (values (append (multiarch-directories) (list "/usr/lib64" "/usr/lib" "/usr/local/lib"))
                  (format nil "libcmark-gfm.so.~A" *cmark-gfm-version*)
                  (format nil "libcmark-gfm-extensions.so.~A" *cmark-gfm-version*)))
    (loop for directory in directories
          for pair = (list (format nil "~A/~A" directory core)
                           (format nil "~A/~A" directory extensions))
          when (every #'probe-file pair)
            return pair)))

(define-test discovery-loads-the-override-or-the-searched-pair
  (false *cmark-gfm-libraries* "the suite runs with *cmark-gfm-libraries* unset")
  (let ((environment (uiop:getenv "CL_COMMONMARK_GFM_LIBS")))
    (if environment
        (is equal (environment-override-paths environment) (state-paths)
            "CL_COMMONMARK_GFM_LIBS is set, so its paths are loaded")
        (is equal (searched-pair) (state-paths)
            "CL_COMMONMARK_GFM_LIBS is unset, so the directory search's pair is loaded"))))

(define-test startup-loads-both-libraries-through-cffi
  ;; The positive control for the startup-condition tests below, which
  ;; assert that CFFI lists neither library after a failed attempt.
  (destructuring-bind (core extensions) (state-paths)
    (true (loaded-p core))
    (true (loaded-p extensions))))

;;; The published state

(define-test startup-finds-the-pinned-version
  (is string= *cmark-gfm-version* (native::state-version (native-state))))

(define-test startup-caches-five-distinct-extensions
  (let ((extensions (native::state-extensions (native-state))))
    (is equal *extension-keywords* (mapcar #'car extensions))
    (false (some #'cffi:null-pointer-p (mapcar #'cdr extensions)))
    (is = 5 (length (remove-duplicates (mapcar (lambda (entry) (cffi:pointer-address (cdr entry)))
                                               extensions))))))

(define-test startup-runs-once-until-a-reset
  (native-state)
  (with-startup-reset
    (false (native-state-published-p))
    (let ((before (native-startup-count)))
      (native-state)
      (native-state)
      (is = (1+ before) (native-startup-count)))
    (true (native-state-published-p))))

;;; Every startup condition (M2 design §8.4). After each: nothing is
;;; published, CFFI lists neither library as loaded, nothing is left open,
;;; and the next ordinary call starts up. On Linux, the loader holds no
;;; libcmark-gfm, but on CCL exactly the recorded pair (M4 design §5.3).

;;; Whether the loader really unloaded cmark-gfm (finding 15): CFFI's own
;;; books say only what CFFI closed. On Linux, /proc/self/maps lists every
;;; file the process has mapped, by its real path, so it shows what the
;;; loader still holds.
;;;
;;; CCL never unloads a library it has called into (M4 finding 2): once
;;; any startup has called into the pair, both stay mapped for good. So a
;;; CCL process keeps the first pair it loads, and records its truenames
;;; (NATIVE::LOADED-PAIR); on CCL, the mapping checks expect exactly that
;;; pair, and SBCL's and ECL's still expect nothing.

#+linux
(defun mapped-cmark-libraries ()
  "The distinct paths of the files /proc/self/maps lists whose names hold
libcmark-gfm: both pinned libraries while they are loaded, and nothing
once the loader has unloaded them."
  (with-open-file (stream "/proc/self/maps")
    (let ((paths '()))
      (loop for line = (read-line stream nil nil)
            while line
            do (let ((start (position #\/ line)))
                 (when (and start (search "libcmark-gfm" line :start2 start))
                   (pushnew (subseq line start) paths :test #'string=))))
      paths)))

(defun sorted-paths (paths)
  "A fresh list of PATHS, native namestrings, without duplicates, in
STRING< order: the set of files PATHS name, to compare with
MAPPED-CMARK-LIBRARIES. PATHS itself is left as it was."
  (sort (remove-duplicates (copy-list paths) :test #'string=) #'string<))

#+ccl
(defun native-truename (path)
  "The truename of the file at PATH, an absolute native namestring, as a
native namestring: what CCL's pair record holds for a library loaded from
PATH. Parsed as a native namestring, so a * in PATH is no wildcard. For a
symbolic link, such as CL_COMMONMARK_GFM_LIBS's profile paths in the
container, it is the file /proc/self/maps shows: CHECK-NOTHING-LEFT-BEHIND
and A-RESET-LEAVES-EXACTLY-THE-RECORDED-PAIR-MAPPED compare the record with
that. For a copy whose name holds a *, it is the copy's own path, the *
unescaped: A-PATHNAME-OVERRIDE-HOLDING-A-STAR-LOADS-ITS-NATIVE-NAMESTRING-
IN-A-CHILD checks the record against the path built without parsing it."
  (uiop:native-namestring (truename (uiop:parse-native-namestring path))))

(defun check-nothing-left-behind (paths)
  "Assert that a failed startup left nothing behind: no published state,
neither of PATHS loaded, no native handle open; on Linux, no libcmark-gfm
mapped, but on CCL exactly the recorded pair, or none before any record;
and that the next ordinary call starts up."
  (false (native-state-published-p) "a failed startup publishes nothing")
  (dolist (path paths)
    (false (loaded-p path) "~A is closed again" path))
  #+(and linux (not ccl))
  (is equal '() (mapped-cmark-libraries) "the loader holds no libcmark-gfm")
  #+(and linux ccl)
  (is equal (sorted-paths (native::loaded-pair)) (sorted-paths (mapped-cmark-libraries))
      "the loader holds exactly the recorded pair")
  (true (open-counts-zero-p))
  (true (native::native-state-p (native-state)) "the next call starts up")
  (true (native-state-published-p)))

#+(and linux (not ccl))
(define-test a-reset-unmaps-both-libraries
  ;; The control first: while a state is published, both are mapped.
  (native-state)
  (is = 2 (length (mapped-cmark-libraries)) "libcmark-gfm mappings while published")
  (with-startup-reset
    (is equal '() (mapped-cmark-libraries) "libcmark-gfm mappings after a reset")))

#+(and linux ccl)
(define-test a-reset-leaves-exactly-the-recorded-pair-mapped
  ;; M4 finding 2: the reset closes both, but CCL keeps them mapped. The
  ;; control first: while a state is published, the recorded pair is two
  ;; files, and they are what is mapped.
  (native-state)
  (let ((recorded (sorted-paths (native::loaded-pair))))
    (is = 2 (length recorded) "the recorded pair's files")
    (is equal recorded (sorted-paths (mapped-cmark-libraries))
        "libcmark-gfm mappings while published")
    (with-startup-reset
      (false (native-state-published-p) "the reset unpublished the state")
      (is equal recorded (sorted-paths (mapped-cmark-libraries))
          "libcmark-gfm mappings after a reset"))))

(define-test a-missing-override-file-signals-native-library-not-found
  ;; Step 2: the override names a file that doesn't exist, so nothing loads.
  (let* ((core (first (state-paths)))
         (missing (uiop:native-namestring (fixture-path "no-such-libcmark-gfm-extensions.so")))
         (override (list core missing)))
    (with-startup-reset
      (let ((condition (let ((*cmark-gfm-libraries* override))
                         (raised native-library-not-found (native-state)))))
        (is equal missing (condition-datum condition))
        (is equal (list missing) (condition-paths condition))
        (is equal override (condition-override condition)))
      (check-nothing-left-behind (list core missing)))))

(define-test a-file-that-is-no-library-signals-native-library-not-found
  ;; Step 3: the core loads, then the extensions don't, so the core must be
  ;; closed again. The reason carries the loader's message, which names the
  ;; file it couldn't load.
  (let* ((core (first (state-paths)))
         (not-a-library (uiop:native-namestring (fixture-path "vocabulary.md")))
         (override (list core not-a-library)))
    (with-startup-reset
      (let ((condition (let ((*cmark-gfm-libraries* override))
                         (raised native-library-not-found (native-state)))))
        (is equal not-a-library (condition-datum condition))
        (is equal (list not-a-library) (condition-paths condition))
        (is equal override (condition-override condition))
        (true (search not-a-library (condition-reason condition))
              "the reason carries the loader's message")
        (true (search "*CMARK-GFM-LIBRARIES*" (condition-reason condition))
              "the reason names the override that named the file"))
      (check-nothing-left-behind (list core not-a-library)))))

(define-test a-library-that-fails-to-load-is-reported-with-its-source
  ;; LOAD-LIBRARY alone, with each source startup can pass it: the name of
  ;; either override, or NIL for the directory search.
  (let ((core (first (state-paths)))
        (not-a-library (uiop:native-namestring (fixture-path "vocabulary.md"))))
    (loop for (override override-name opening)
            in (list (list (list core not-a-library) "*CMARK-GFM-LIBRARIES*"
                           "*CMARK-GFM-LIBRARIES* names a library")
                     (list (format nil "~A:~A" core not-a-library) "CL_COMMONMARK_GFM_LIBS"
                           "CL_COMMONMARK_GFM_LIBS names a library")
                     (list nil nil "the directory search found a library"))
          do (let ((condition (raised native-library-not-found
                                      (native::load-library not-a-library override override-name))))
               (when condition
                 (true (search opening (condition-reason condition))
                       "~S should say ~S" (condition-reason condition) opening))))))

(define-test another-version-signals-native-abi-mismatch
  ;; Step 4, through the version wrapper.
  (let ((paths (state-paths)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::%version-string (constantly "0.29.0.gfm.12")))
                         (raised native-abi-mismatch (native-state)))))
        (is string= *cmark-gfm-version* (condition-expected-version condition))
        (is string= "0.29.0.gfm.12" (condition-found-version condition))
        (is equal paths (condition-paths condition)))
      (check-nothing-left-behind paths))))

;;; Step 4, the number cross-check (M3 design §5): once the string check
;;; passes, cmark_version()'s number must also match
;;; (VERSION-NUMBER *CMARK-GFM-VERSION*).

(define-test another-version-number-signals-native-abi-mismatch
  ;; Through the version-number wrapper, once the string check passes.
  (let ((paths (state-paths)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::%version-number (constantly #x001D000E)))
                         (raised native-abi-mismatch (native-state)))))
        (is string= *cmark-gfm-version* (condition-expected-version condition))
        (is string= "0.29.0.gfm.14" (condition-found-version condition))
        (is equal paths (condition-paths condition))
        (true (search "001D000D" (condition-reason condition)) "the expected number, in hex")
        (true (search "001D000E" (condition-reason condition)) "the found number, in hex"))
      (check-nothing-left-behind paths))))

(define-test an-error-reading-the-version-number-signals-native-abi-mismatch
  ;; Through the version-number wrapper: an error that isn't the project's.
  (let ((paths (state-paths)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::%version-number
                                         (lambda () (error "no version number here"))))
                         (raised native-abi-mismatch (native-state)))))
        (when condition
          (is eql 'simple-error (type-of (condition-datum condition)) "the datum")
          (is string= *cmark-gfm-version* (condition-expected-version condition))
          (is equal paths (condition-paths condition))))
      (check-nothing-left-behind paths))))

(define-test a-negative-version-number-is-reported-as-its-unsigned-version
  ;; cmark_version() is a C int: a packed value with bit 31 set (a major
  ;; version of 128 or more) reads back as negative. CHECK-VERSION-NUMBER
  ;; reinterprets FOUND as an unsigned 32-bit value before comparing and
  ;; decoding it, so a negative wrapper result is reported as
  ;; NATIVE-ABI-MISMATCH with a proper FOUND-VERSION -- not, as without the
  ;; LDB, one left NIL once NUMBER-VERSION's own range check fails instead.
  (let ((paths (state-paths)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::%version-number (constantly -1)))
                         (raised native-abi-mismatch (native-state)))))
        (is string= *cmark-gfm-version* (condition-expected-version condition))
        (is string= "255.255.255.gfm.255" (condition-found-version condition)
            "-1's bit pattern, read unsigned, is 0xFFFFFFFF"))
      (check-nothing-left-behind paths))))

(define-test a-missing-extension-signals-native-initialization-error
  ;; Step 6, through the find-extension wrapper.
  (let ((paths (state-paths)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::%find-extension
                                         (lambda (name)
                                           (declare (ignore name))
                                           (cffi:null-pointer))))
                         (raised native-initialization-error (native-state)))))
        (is string= "table" (condition-datum condition)))
      (check-nothing-left-behind paths))))

(define-test a-null-allocator-free-signals-native-initialization-error
  ;; Step 7, through the allocator wrapper.
  (let ((paths (state-paths)))
    (with-startup-reset
      (with-redefined ((native::%allocator-free (lambda () (cffi:null-pointer))))
        (raised native-initialization-error (native-state)))
      (check-nothing-left-behind paths))))

(define-test a-failed-smoke-parse-signals-native-initialization-error
  ;; Step 8. Every extension found is strikethrough, so the smoke document
  ;; parses without its table or its task item. The footnote reference
  ;; needs no extension, only CMARK_OPT_FOOTNOTES, so it is still there.
  (let ((paths (state-paths))
        (find-extension (fdefinition 'native::%find-extension)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::%find-extension
                                         (lambda (name)
                                           (declare (ignore name))
                                           (funcall find-extension "strikethrough"))))
                         (raised native-initialization-error (native-state)))))
        (is equal '(:table :task-item) (condition-datum condition)
            "the datum lists the kinds the smoke parse didn't find"))
      (check-nothing-left-behind paths))))

;;; An error from the loaded libraries is a NATIVE-ERROR too (M2 design
;;; §5.2): one that isn't the project's own, in steps 4 to 8, becomes
;;; NATIVE-ABI-MISMATCH in step 4 and NATIVE-INITIALIZATION-ERROR in steps
;;; 5 to 8, its datum the original condition. So does any failure of the
;;; smoke parse.

(define-test an-error-reading-the-version-signals-native-abi-mismatch
  ;; Step 4, through the version wrapper: an error that isn't the
  ;; project's, as a library without cmark_version_string would signal.
  (let ((paths (state-paths)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::%version-string
                                         (lambda () (error "no version here"))))
                         (raised native-abi-mismatch (native-state)))))
        (when condition
          (is eql 'simple-error (type-of (condition-datum condition)) "the datum")
          (is string= *cmark-gfm-version* (condition-expected-version condition))
          (is equal paths (condition-paths condition))))
      (check-nothing-left-behind paths))))

;;; Not in the suite's process on CCL (M4 design §5.3): there the core
;;; named twice is another pair than the suite's, which is recorded, so
;;; startup refuses it before step 4. A fresh child CCL runs it below.
#-ccl
(define-test an-override-naming-the-core-twice-signals-native-initialization-error
  ;; The core loads twice and reports the pinned version, so steps 3 and 4
  ;; pass. Step 5 calls cmark_gfm_core_extensions_ensure_registered, which
  ;; lives in the extensions library (extensions/core-extensions.c), never
  ;; loaded: the Lisp's own undefined-function error, which startup turns
  ;; into a NATIVE-INITIALIZATION-ERROR.
  (let* ((core (first (state-paths)))
         (override (list core core)))
    (with-startup-reset
      (let ((condition (let ((*cmark-gfm-libraries* override))
                         (raised native-initialization-error (native-state)))))
        (when condition
          (true (typep (condition-datum condition) 'error) "the datum is the original error")
          (false (typep (condition-datum condition) 'commonmark-gfm-error)
                 "the original error isn't the project's")))
      (check-nothing-left-behind (list core)))))

(defun readable-paths (datum)
  "DATUM when it is a list of strings, such as a refused pair's truenames,
and :OTHER otherwise, so a child can report it as text its parent reads
back."
  (if (and (listp datum) (ignore-errors (every #'stringp datum))) datum :other))

#+ccl
(defun core-twice-in-a-fresh-process (core)
  "In a child CCL that has started nothing up: the scenario of
AN-OVERRIDE-NAMING-THE-CORE-TWICE-SIGNALS-NATIVE-INITIALIZATION-ERROR,
with CORE, a native namestring, named twice as the override; then the next
call, with no override. Return a plist, readable by the parent:
- :SIGNALLED, the type of what the startup signalled, or :STARTED-UP;
- :DATUM-ERROR and :DATUM-OURS, whether its datum is an ERROR, and one of
  the project's;
- after it: :PUBLISHED, whether a state is published; :LOADED, whether
  CFFI lists CORE as loaded; :OPEN-ZERO, whether no native handle is open;
  :RECORDED, the pair record; :MAPPED, on Linux, the libcmark-gfm files
  mapped;
- :NEXT-SIGNALLED, :NEXT-DATUM and :NEXT-REASON: the type of what the
  next call signalled, or :STARTED-UP, and its datum (READABLE-PATHS) and
  reason."
  (let* ((failure (let ((*cmark-gfm-libraries* (list core core)))
                    (startup-failure)))
         (datum (and (typep failure 'commonmark-gfm-error) (condition-datum failure)))
         (after (list :published (native-state-published-p)
                      :loaded (loaded-p core)
                      :open-zero (open-counts-zero-p)
                      :recorded (native::loaded-pair)
                      :mapped #+linux (mapped-cmark-libraries) #-linux :unknown))
         (next (startup-failure))
         (ours (typep next 'commonmark-gfm-error)))
    (list* :signalled (if failure (type-of failure) :started-up)
           :datum-error (typep datum 'error)
           :datum-ours (typep datum 'commonmark-gfm-error)
           :next-signalled (if next (type-of next) :started-up)
           :next-datum (and ours (readable-paths (condition-datum next)))
           :next-reason (and ours (condition-reason next))
           after)))

#+ccl
(define-test an-override-naming-the-core-twice-signals-native-initialization-error-in-a-child
  ;; As on SBCL and ECL, but in a child CCL, which has loaded no pair, so
  ;; nothing it holds can answer step 5's call (M4 finding 3). The core
  ;; named twice is then the child's first pair, so it is recorded, and
  ;; the next ordinary call names another pair: CCL refuses it.
  (let* ((core (first (state-paths)))
         (core-truename (native-truename core))
         (ordinary (mapcar #'native-truename (state-paths))))
    (destructuring-bind (&key killed exit-code reports errors &allow-other-keys)
        (run-child (suite-child-forms
                    :core-twice
                    (format nil "(cl-commonmark-gfm.native-tests::core-twice-in-a-fresh-process ~S)"
                            core)))
      (false killed "the child reported within RUN-CHILD's time limit")
      (is eql 0 exit-code "the child exits 0; its error output starts:~%~A" errors)
      (destructuring-bind (&key (signalled :unreported) datum-error datum-ours published loaded
                             open-zero recorded mapped next-signalled next-datum next-reason)
          (getf reports :core-twice)
        (declare (ignorable mapped))
        (is eql 'native-initialization-error signalled "what the startup signalled")
        (true datum-error "the datum is the original error")
        (false datum-ours "the original error isn't the project's")
        (false published "a failed startup publishes nothing")
        (false loaded "~A is closed again" core)
        (true open-zero "nothing is left open")
        (is equal (list core-truename core-truename) recorded "the child's record: the core, twice")
        #+linux
        (is equal (sorted-paths recorded) (sorted-paths mapped)
            "the loader holds exactly the recorded pair: the core")
        (is eql 'native-initialization-error next-signalled
            "the next ordinary call names another pair than the recorded one")
        (is equal ordinary next-datum "the refused pair: the ordinary pair's truenames")
        (true (and (stringp next-reason) (search core-truename next-reason))
              "the reason names the recorded core: ~S" next-reason)))))

(define-test a-null-root-in-the-smoke-parse-signals-native-initialization-error
  ;; Step 8's parse runs through WITH-NATIVE-DOCUMENT, whose null root
  ;; signals NATIVE-PARSE-ERROR (M2 design §5.4 step 4).
  (let ((paths (state-paths)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::%parser-finish (lambda (parser)
                                                                  (declare (ignore parser))
                                                                  (cffi:null-pointer))))
                         (raised native-initialization-error (native-state)))))
        (when condition
          (is eql 'native-parse-error (type-of (condition-datum condition))
              "the datum is the smoke parse's error")))
      (check-nothing-left-behind paths))))

;;; Where a failed startup's condition reaches its caller (M2 design §11):
;;; after the startup lock is released, with interrupts as the caller had
;;; them. Signalled under the lock, with interrupts deferred, a caller's
;;; handler or the debugger would run there: no timeout could land in it,
;;; and every other thread's call would wait until it was done. Startup is
;;; reached two ways: by NATIVE-STATE, and by an entry point, which holds
;;; the state by WITH-NATIVE-STATE.

(defparameter *failing-calls*
  (list (list 'native-state (lambda () (native-state)))
        (list 'markdown->html (lambda () (markdown->html "*a*"))))
  "Each way into startup, as (NAME FUNCTION), FUNCTION taking no
arguments.")

(defun missing-pair ()
  "An override naming two files that don't exist: startup fails at step 2
with NATIVE-LIBRARY-NOT-FOUND, having loaded nothing."
  (list (uiop:native-namestring (fixture-path "no-such-libcmark-gfm.so"))
        (uiop:native-namestring (fixture-path "no-such-libcmark-gfm-extensions.so"))))

(defun holds-read-elsewhere ()
  "How many calls hold the native state, read by another thread under the
startup lock, or :LOCK-HELD when that thread can't have the lock within 2
seconds. Another thread, so that a caller holding the lock gets
:LOCK-HELD rather than a recursive lock error. Polls, by CALL-WITH-LOCK-
WITHIN, since CCL's bordeaux-threads doesn't implement WITH-LOCK-HELD's
:TIMEOUT (M4 finding 1)."
  (thread-outcome
   (make-test-thread
    (lambda ()
      (multiple-value-bind (holds got-it)
          (call-with-lock-within native::*startup-lock* 2
                                 (lambda () (length native::*holds*)))
        (if got-it holds :lock-held)))
    :name "holds reader")))

(defun what-a-failure-handler-sees (call)
  "Call CALL, a function of no arguments, with MISSING-PAIR as the override.
Return what a HANDLER-BIND handler of the NATIVE-LIBRARY-NOT-FOUND it
signals saw, as a plist, or NIL when no handler ran:
- :INTERRUPTS-ENABLED, INTERRUPTS-ENABLED-P, read on every Lisp (M4
  finding 1);
- :HOLDS, HOLDS-READ-ELSEWHERE."
  (let ((seen nil))
    (handler-case
        (handler-bind ((native-library-not-found
                         (lambda (condition)
                           (declare (ignore condition))
                           (setf seen (list :interrupts-enabled (interrupts-enabled-p)
                                            :holds (holds-read-elsewhere))))))
          (let ((*cmark-gfm-libraries* (missing-pair)))
            (funcall call)))
      (native-library-not-found () nil))
    seen))

(define-test a-startup-failure-is-handled-with-interrupts-enabled-and-no-hold
  ;; The handler runs with interrupts enabled, as the test itself has them,
  ;; and with the startup lock free: a failed call has taken no hold.
  (true (interrupts-enabled-p) "the control: interrupts are enabled in the test")
  (loop for (name call) in *failing-calls*
        do (with-startup-reset
             (destructuring-bind (&key (interrupts-enabled :not-handled) (holds :not-handled))
                 (what-a-failure-handler-sees call)
               (is eql t interrupts-enabled "~(~A~): interrupts enabled in the handler" name)
               (is eql 0 holds "~(~A~): holds seen from the handler" name))
             (false (native-state-published-p) "~(~A~): nothing published" name)
             (true (open-counts-zero-p) "~(~A~): nothing open" name))))

(defparameter *slow-handler-seconds* 10
  "The longest a slow handler waits for another thread's call to return.")

(defun call-while-a-handler-waits (call)
  "In a thread of its own, call CALL, a function of no arguments, with
MISSING-PAIR as the override. A HANDLER-BIND handler of the
NATIVE-LIBRARY-NOT-FOUND it signals waits, up to *SLOW-HANDLER-SECONDS*,
for another thread's call to return. Once that handler runs, start the
other thread, which renders *b* with no override. Both threads are joined,
however this exits. Return a plist:
- :HANDLED, whether the handler ran;
- :MEANWHILE, whether the other call returned while the handler waited;
- :OTHER, the other call's outcome: (:RETURNED HTML) or (:SIGNALLED
  CONDITION);
- :CALLER, what CALL's caller got in the end: the type of the condition,
  or :RETURNED."
  (let ((handling (bt2:make-semaphore :name "a handler runs"))
        (returned (bt2:make-semaphore :name "the other call returned"))
        (meanwhile nil)
        (handled nil)
        (failing nil)
        (other nil)
        (outcomes '()))
    (unwind-protect
         (progn
           (setf failing
                 (make-test-thread
                  (lambda ()
                    (handler-case
                        (handler-bind ((native-library-not-found
                                         (lambda (condition)
                                           (declare (ignore condition))
                                           (bt2:signal-semaphore handling)
                                           (setf meanwhile
                                                 (and (bt2:wait-on-semaphore
                                                       returned :timeout *slow-handler-seconds*)
                                                      t)))))
                          (let ((*cmark-gfm-libraries* (missing-pair)))
                            (funcall call)
                            :returned))
                      (error (condition) (type-of condition))))
                  :name "failing startup"))
           (setf handled (and (bt2:wait-on-semaphore handling :timeout *slow-handler-seconds*) t))
           (setf other
                 (make-test-thread
                  (lambda ()
                    (unwind-protect
                         (handler-case (list :returned (markdown->html "*b*"))
                           (serious-condition (condition) (list :signalled condition)))
                      (bt2:signal-semaphore returned)))
                  :name "another caller")))
      (setf outcomes (list :other (and other (bt2:join-thread other))
                           :caller (and failing (bt2:join-thread failing)))))
    (list* :handled handled :meanwhile meanwhile outcomes)))

(define-test another-thread-starts-up-while-a-startup-failure-is-handled
  (loop for (name call) in *failing-calls*
        do (with-startup-reset
             (let ((startups (native-startup-count)))
               (destructuring-bind (&key handled meanwhile other caller)
                   (call-while-a-handler-waits call)
                 (true handled "~(~A~): the handler ran" name)
                 (true meanwhile "~(~A~): the other call returned while the handler waited" name)
                 (is equal (list :returned (format nil "<p><em>b</em></p>~%")) other
                     "~(~A~): the other call's outcome" name)
                 (is eql 'native-library-not-found caller "~(~A~): what the caller got" name))
               (is = (1+ startups) (native-startup-count)
                   "~(~A~): the other call's own startup was published" name)
               (true (open-counts-zero-p) "~(~A~): nothing open" name)))))

;;; A pathname override (ADR-0009). SBCL's NAMESTRING escapes a * in a
;;; pathname as \*, so the override must be read as a native namestring:
;;; the file at that path is the one to load.

(defun library-copy-namestrings ()
  "Two native namestrings in the temporary directory, for copies of the
core and extensions libraries, each name holding a *."
  (let ((tag (format nil "~36R" (random (expt 36 8) (make-random-state t))))
        (directory (uiop:native-namestring (uiop:temporary-directory))))
    (list (format nil "~Alibcmark-gfm*copy-~A.so" directory tag)
          (format nil "~Alibcmark-gfm-extensions*copy-~A.so" directory tag))))

(defun call-with-library-copies (function)
  "Copy the published pair to LIBRARY-COPY-NAMESTRINGS, with the system's
cp, through UIOP:RUN-PROGRAM, on native namestrings throughout, so no
pathname is ever parsed from a name holding a * (M4 finding 4: on ECL, a *
in a pathname is a wildcard, and UIOP:COPY-FILE on such a path signals
FILE-ERROR before anything is loaded). Call FUNCTION with the copies'
native namestrings, CORE and EXTENSIONS. Both copies are deleted however
FUNCTION exits, again by an external command (rm), so cleanup never parses
one of these paths as a pathname either."
  (let ((originals (state-paths))
        (copies (library-copy-namestrings)))
    (unwind-protect
         (progn
           (loop for original in originals
                 for copy in copies
                 do (uiop:run-program (list "cp" original copy)))
           (apply function copies))
      (dolist (copy copies)
        (uiop:run-program (list "rm" "-f" copy) :ignore-error-status t)))))

;;; Not on ECL (M4 finding 12): ECL parses a * in a pathname as a
;;; wildcard, so PROBE-FILE finds no file at the copy's pathname though cp
;;; made it, and discovery signals NATIVE-LIBRARY-NOT-FOUND before anything
;;; loads. On ECL, an override path holding a * is reported as not found,
;;; as A-PATHNAME-OVERRIDE-HOLDING-A-STAR-IS-NOT-FOUND-ON-ECL checks.
;;; Not in the suite's process on CCL (M4 design §5.3): the copies are
;;; another pair than the suite's, which is recorded, so startup refuses
;;; them. A fresh child CCL runs it below.
#-(or ecl ccl)
(define-test a-pathname-override-holding-a-star-loads-its-native-namestring
  (call-with-library-copies
   (lambda (core extensions)
     (with-startup-reset
       (let ((*cmark-gfm-libraries* (list (uiop:parse-native-namestring core)
                                          (uiop:parse-native-namestring extensions))))
         (is equal (list core extensions) (native::state-paths (native-state))
             "the paths loaded"))))))

#+ccl
(defun star-override-in-a-fresh-process (core extensions)
  "In a child CCL that has started nothing up: the scenario of
A-PATHNAME-OVERRIDE-HOLDING-A-STAR-LOADS-ITS-NATIVE-NAMESTRING. Start up
with the pathnames parsed from CORE and EXTENSIONS, native namestrings
holding a *, as the override, and return (:PATHS P :RECORDED R): the paths
the state loaded, and the truenames CCL's pair record holds; or
(:SIGNALLED (TYPE REPORT)) when startup signals."
  (let ((*cmark-gfm-libraries* (list (uiop:parse-native-namestring core)
                                     (uiop:parse-native-namestring extensions))))
    (handler-case (list :paths (native::state-paths (native-state))
                        :recorded (native::loaded-pair))
      (error (condition)
        (list :signalled (list (type-of condition) (princ-to-string condition)))))))

#+ccl
(defun copy-truename (copy)
  "The truename that COPY, the native namestring of a file cp made in the
temporary directory, must have, found without parsing COPY at all: the
directory's truename, as a native namestring, then COPY's own file name,
which holds a * and is no symbolic link."
  (concatenate 'string
               (uiop:native-namestring (truename (uiop:temporary-directory)))
               (subseq copy (1+ (position #\/ copy :from-end t)))))

#+ccl
(define-test a-pathname-override-holding-a-star-loads-its-native-namestring-in-a-child
  (call-with-library-copies
   (lambda (core extensions)
     (destructuring-bind (&key killed exit-code reports errors &allow-other-keys)
         (run-child (suite-child-forms
                     :star
                     (format nil "(cl-commonmark-gfm.native-tests::~
                                  star-override-in-a-fresh-process ~S ~S)"
                             core extensions)))
       (false killed "the child reported within RUN-CHILD's time limit")
       (is eql 0 exit-code "the child exits 0; its error output starts:~%~A" errors)
       (let ((star (getf reports :star)))
         (is equal (list core extensions) (getf star :paths :unreported)
             "the paths loaded: ~S" star)
         ;; NATIVE::LIBRARY-TRUENAME keeps the * a plain character: no
         ;; wildcard, and not escaped, as NAMESTRING would write it (\*).
         (is equal (mapcar #'copy-truename (list core extensions))
             (getf star :recorded :unreported)
             "the pair record holds the copies' truenames, each * as it is"))))))

#+ecl
(define-test a-pathname-override-holding-a-star-is-not-found-on-ecl
  ;; M4 finding 12: the copies exist, but ECL parses each path as wild, so
  ;; discovery finds no file at the first, the core's, and nothing loads.
  (call-with-library-copies
   (lambda (core extensions)
     (with-startup-reset
       (let ((condition (let ((*cmark-gfm-libraries* (list (uiop:parse-native-namestring core)
                                                           (uiop:parse-native-namestring
                                                            extensions))))
                          (raised native-library-not-found (native-state)))))
         (when condition
           (is equal core (condition-datum condition) "the path not found: the core's copy")))
       (check-nothing-left-behind (list core extensions))))))

;;; CCL: one pair per process (M4 design §5.3; M4 findings 2 and 3). CCL
;;; never unloads a library it has called into, and CFFI's CCL backend
;;; looks a foreign name up in whichever library holds it
;;; (src/cffi-openmcl.lisp), so a later pair could run an earlier pair's
;;; code. So once both libraries of a pair have loaded, and before any call
;;; into them, a CCL process records the pair's truenames, the first time,
;;; and refuses a later pair whose truenames differ. SBCL and ECL unload
;;; both libraries on close, and keep no record.

(define-test ccl-alone-records-the-truenames-of-the-pair-it-loaded
  ;; After a startup: STATE-PATHS starts up when nothing is published.
  (let ((paths (state-paths)))
    (declare (ignorable paths))
    #-ccl
    (false (native::loaded-pair) "SBCL and ECL keep no record")
    #+ccl
    (is equal (mapcar #'native-truename paths) (native::loaded-pair)
        "CCL records the truenames of the state's paths")))

#+ccl
(define-test a-copy-of-the-pair-at-another-path-is-refused
  ;; The copies are the same files' bytes at other paths: another pair,
  ;; which this process would run the recorded pair's code for (M4 finding
  ;; 3). Refused once both have loaded, before any call into them, and
  ;; closed again, so the loader drops both (M4 finding 2).
  (let ((recorded (progn (state-paths) (native::loaded-pair))))
    (true (and (= 2 (length recorded)) (every #'stringp recorded))
          "the control: the suite's pair is recorded: ~S" recorded)
    (call-with-library-copies
     (lambda (core extensions)
       (with-startup-reset
         (let ((condition (let ((*cmark-gfm-libraries* (list core extensions)))
                            (raised native-initialization-error (native-state)))))
           (when condition
             (is equal (list (native-truename core) (native-truename extensions))
                 (condition-datum condition) "the datum: the refused pair's truenames")
             (let ((reason (condition-reason condition)))
               (true (search (first recorded) reason) "the reason names the recorded core")
               (true (search (second recorded) reason) "the reason names the recorded extensions")
               (true (search "can't unload" reason) "the reason says CCL can't unload it")
               (true (search "new process" reason)
                     "the reason says another pair needs a new process"))))
         (false (native-state-published-p) "the refusal publishes nothing")
         (false (loaded-p core) "~A is closed again" core)
         (false (loaded-p extensions) "~A is closed again" extensions)
         #+linux
         (let ((mapped (mapped-cmark-libraries)))
           (false (find core mapped :test #'string=) "~A isn't mapped" core)
           (false (find extensions mapped :test #'string=) "~A isn't mapped" extensions)
           (is equal (sorted-paths recorded) (sorted-paths mapped)
               "the loader holds exactly the recorded pair"))
         (is equal recorded (native::loaded-pair) "the record is unchanged")
         (true (open-counts-zero-p))
         (true (native::native-state-p (native-state)) "the next ordinary call starts up")
         (true (native-state-published-p)))))))

#+ccl
(define-test an-error-reading-the-pairs-truenames-signals-native-initialization-error
  ;; Once both libraries have loaded, an error reading a truename, as from
  ;; a file deleted meanwhile, is a startup failure like any other.
  (let ((paths (state-paths)))
    (with-startup-reset
      (let ((condition (with-redefined ((native::library-truename
                                         (lambda (path)
                                           (declare (ignore path))
                                           (error "no truename here"))))
                         (raised native-initialization-error (native-state)))))
        (when condition
          (is eql 'simple-error (type-of (condition-datum condition)) "the datum")))
      (check-nothing-left-behind paths))))

#+ccl
(defun pair-record ()
  "CCL's whole pair record, NATIVE::*LOADED-PAIR*, its truenames and
sonames, read under the startup lock, as the library reads it."
  (native::with-startup-lock
    native::*loaded-pair*))

#+ccl
(defun restore-pair-record (record)
  "Make RECORD, as PAIR-RECORD gave it, CCL's pair record again, under the
startup lock, as the library writes it."
  (native::with-startup-lock
    (setf native::*loaded-pair* record)))

#+ccl
(define-test the-restore-hook-forgets-the-recorded-pair
  ;; A saved image whose pair CCL didn't reopen forgets the record as it
  ;; starts: the restore hook clears it with the published state (M4 design
  ;; §5.3). Called here in the suite's own process, after a reset, which
  ;; made CCL forget both records, and the record put back.
  (let ((record (progn (state-paths) (pair-record))))
    (true (native::loaded-pair) "the control: a pair is recorded")
    (with-startup-reset
      (unwind-protect
           (progn
             (native::clear-native-state-on-restart)
             (false (native::loaded-pair) "the restore hook forgot the pair")
             (false (pair-record) "and its sonames with it"))
        (restore-pair-record record)))
    (is equal record (pair-record) "the record is back")))

#+ccl
(defun record-after-the-restore-hook (record)
  "Make RECORD CCL's pair record, run the restore hook, and return the
record it left."
  (restore-pair-record record)
  (native::clear-native-state-on-restart)
  (pair-record))

#+ccl
(define-test the-restore-hook-records-the-pair-ccl-lists-and-maps
  ;; As a saved image starts, CCL reopens by soname every record it lists,
  ;; before the restore hook runs; when it has reopened the pair, the hook
  ;; records the files it maps (M4 design §5.3; M4 finding 22). Here, in the
  ;; suite's own process after a reset, a CFFI load of the pair's files
  ;; lists and maps both records as that reopening does. The record the
  ;; hook is given names other files, as one saved elsewhere would.
  (let* ((paths (state-paths))
         (record (pair-record))
         (elsewhere (list :truenames (list "/saved/elsewhere/libcmark-gfm.so"
                                           "/saved/elsewhere/libcmark-gfm-extensions.so")
                          :sonames (getf record :sonames))))
    (is = 2 (length (getf record :sonames)) "the control: the record's sonames: ~S" record)
    (with-startup-reset
      (unwind-protect
           (let ((libraries (mapcar (lambda (path)
                                      (cffi:load-foreign-library (native::library-designator path)))
                                    paths)))
             (unwind-protect
                  (progn
                    (is equal record (record-after-the-restore-hook elsewhere)
                        "both listed and mapped: the hook recorded the files CCL maps")
                    ;; The hook runs as an image starts: it mustn't signal.
                    (with-redefined ((native::library-truename
                                      (lambda (path)
                                        (declare (ignore path))
                                        (error "no truename here"))))
                      (false (record-after-the-restore-hook elsewhere)
                             "a truename that can't be read: the hook cleared the record")))
               (mapc #'cffi:close-foreign-library libraries))
             ;; CFFI's close empties both records but leaves them listed.
             (false (record-after-the-restore-hook elsewhere)
                    "listed, but mapped for CCL no more: the hook cleared the record"))
        (restore-pair-record record)))
    (is equal record (pair-record) "the record is back")
    (true (native::native-state-p (native-state)) "the next call starts up")
    (true (open-counts-zero-p))))
