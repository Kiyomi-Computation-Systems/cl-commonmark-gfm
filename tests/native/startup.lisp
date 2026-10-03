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
;;; and the next ordinary call starts up.

;;; Whether the loader really unloaded cmark-gfm (finding 15): CFFI's own
;;; books say only what CFFI closed. On Linux, /proc/self/maps lists every
;;; file the process has mapped, so it shows what the loader still holds.

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

(defun check-nothing-left-behind (paths)
  "Assert that a failed startup left nothing behind: no published state,
neither of PATHS loaded, on Linux no libcmark-gfm mapped, no native handle
open; and that the next ordinary call starts up."
  (false (native-state-published-p) "a failed startup publishes nothing")
  (dolist (path paths)
    (false (loaded-p path) "~A is closed again" path))
  #+linux
  (is equal '() (mapped-cmark-libraries) "the loader holds no libcmark-gfm")
  (true (open-counts-zero-p))
  (true (native::native-state-p (native-state)) "the next call starts up")
  (true (native-state-published-p)))

#+linux
(define-test a-reset-unmaps-both-libraries
  ;; The control first: while a state is published, both are mapped.
  (native-state)
  (is = 2 (length (mapped-cmark-libraries)) "libcmark-gfm mappings while published")
  (with-startup-reset
    (is equal '() (mapped-cmark-libraries) "libcmark-gfm mappings after a reset")))

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
              "the reason carries the loader's message"))
      (check-nothing-left-behind (list core not-a-library)))))

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
:LOCK-HELD rather than a recursive lock error."
  (bt2:join-thread
   (bt2:make-thread (lambda ()
                      (or (bt2:with-lock-held (native::*startup-lock* :timeout 2)
                            (length native::*holds*))
                          :lock-held))
                    :name "holds reader")))

(defun what-a-failure-handler-sees (call)
  "Call CALL, a function of no arguments, with MISSING-PAIR as the override.
Return what a HANDLER-BIND handler of the NATIVE-LIBRARY-NOT-FOUND it
signals saw, as a plist, or NIL when no handler ran:
- :INTERRUPTS-ENABLED, SB-SYS:*INTERRUPTS-ENABLED* on SBCL, and :UNKNOWN
  elsewhere;
- :HOLDS, HOLDS-READ-ELSEWHERE."
  (let ((seen nil))
    (handler-case
        (handler-bind ((native-library-not-found
                         (lambda (condition)
                           (declare (ignore condition))
                           (setf seen (list :interrupts-enabled
                                            #+sbcl sb-sys:*interrupts-enabled*
                                            #-sbcl :unknown
                                            :holds (holds-read-elsewhere))))))
          (let ((*cmark-gfm-libraries* (missing-pair)))
            (funcall call)))
      (native-library-not-found () nil))
    seen))

(define-test a-startup-failure-is-handled-with-interrupts-enabled-and-no-hold
  ;; The handler runs with interrupts enabled, as the test itself has them,
  ;; and with the startup lock free: a failed call has taken no hold.
  #+sbcl (true sb-sys:*interrupts-enabled* "the control: interrupts are enabled in the test")
  (loop for (name call) in *failing-calls*
        do (with-startup-reset
             (destructuring-bind (&key (interrupts-enabled :not-handled) (holds :not-handled))
                 (what-a-failure-handler-sees call)
               (declare (ignorable interrupts-enabled))
               #+sbcl
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
                 (bt2:make-thread
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
                 (bt2:make-thread
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
  "Copy the published pair to LIBRARY-COPY-NAMESTRINGS, and call FUNCTION
with the copies' native namestrings, CORE and EXTENSIONS. Both copies are
deleted however FUNCTION exits."
  (let ((originals (state-paths))
        (copies (library-copy-namestrings)))
    (unwind-protect
         (progn
           (loop for original in originals
                 for copy in copies
                 do (uiop:copy-file (uiop:parse-native-namestring original)
                                    (uiop:parse-native-namestring copy)))
           (apply function copies))
      (dolist (copy copies)
        (uiop:delete-file-if-exists (uiop:parse-native-namestring copy))))))

(define-test a-pathname-override-holding-a-star-loads-its-native-namestring
  (call-with-library-copies
   (lambda (core extensions)
     (with-startup-reset
       (let ((*cmark-gfm-libraries* (list (uiop:parse-native-namestring core)
                                          (uiop:parse-native-namestring extensions))))
         (is equal (list core extensions) (native::state-paths (native-state))
             "the paths loaded"))))))
