;;;; Starting the native layer (M2 design §5.2; ADR-0009): find the pinned
;;;; pair, load it by absolute path, check it, cache what every parse
;;;; needs, smoke-test it, and publish it. Once per process, on first use,
;;;; under the startup lock (D11). A failed attempt closes what it loaded
;;;; and publishes nothing, so the next call starts again.
;;;;
;;;; A call that parses holds the published state, from the moment it is
;;;; handed over until the call's document is released (M2 design §5.3;
;;;; finding 18). While any call holds it, closing cmark signals and closes
;;;; nothing.
;;;;
;;;; Everything done under the startup lock runs with interrupts deferred,
;;;; from the wait for the lock until its release (M2 design §5.4, finding
;;;; 21): startup and its cmark calls, publishing, closing, and taking and
;;;; ending a hold. So an interrupt can't land between taking a hold and
;;;; recording it, or leave one recorded after its call has ended.
;;;;
;;;; A caller's handler of a failed startup doesn't run there. The
;;;; startup's error is caught under the lock, once the attempt has closed
;;;; what it loaded, and signalled after the lock is released, with
;;;; interrupts as the caller had them (M2 design §11). Otherwise the
;;;; handler, or the debugger, would run holding the lock with interrupts
;;;; deferred: no timeout could land in it, and every other thread's call
;;;; would wait for it.

(in-package #:cl-commonmark-gfm.native)

(defvar *startup-lock* (bt2:make-lock :name "cl-commonmark-gfm startup")
  "Held while starting up, publishing, resetting, reading the published
state, or taking or ending a hold on it, never while a caller parses or
handles a failed startup, and always by WITH-STARTUP-LOCK. Lock order:
startup's smoke parse takes the finish lock while holding this one; nothing
takes this one while holding the finish lock (M2 design §5.2).")

(defvar *published-state* nil
  "The NATIVE-STATE every parse uses, or NIL before startup. Read and
written only under *STARTUP-LOCK*.")

(defvar *holds* '()
  "One token for each call that holds the published state (M2 design
§5.3): pushed in the critical section that hands the state over, and
removed once the call's document is released. Read and written only under
*STARTUP-LOCK*. While it isn't empty, RESET-NATIVE-STATE closes nothing.")

(defmacro with-startup-lock (&body body)
  "Run BODY holding *STARTUP-LOCK*, with interrupts deferred from the wait
for the lock until its release (M2 design §5.4). A thread waiting for the
lock can't be interrupted until it has had it, as a startup may take tens
of milliseconds (M2 design §11). A handler of a condition BODY signals
runs there, holding the lock with interrupts deferred, so a condition meant
for a caller is signalled after the release: a failed startup's by
CALL-WITH-PUBLISHED-STATE, a refused reset's by RESET-NATIVE-STATE."
  `(with-interrupts-deferred
     (bt2:with-lock-held (*startup-lock*)
       ,@body)))

;;; Wrappers a test can redefine, NOTINLINE as in document.lisp

(declaim (notinline %version-string %version-number %find-extension %allocator-free))

(defun %version-string ()
  "cmark_version_string's result, as a Lisp string. The call runs with
interrupts deferred, as every cmark call does."
  (cffi:foreign-string-to-lisp (with-interrupts-deferred (cmark-version-string))
                               :encoding :utf-8))

(defun %version-number ()
  "cmark_version's result (M3 design §5): a C int, so a packed value with
bit 31 set (a major version of 128 or more) can come back negative. The call
runs with interrupts deferred, as every cmark call does."
  (with-interrupts-deferred (cmark-version)))

(defun %find-extension (name)
  "cmark_find_syntax_extension's pointer for the extension called NAME, or
null when none is registered under it. The call runs with interrupts
deferred: it allocates a copy of the registry's list and frees it
(src/syntax_extension.c)."
  (with-interrupts-deferred
    (cmark-find-syntax-extension name)))

(defun %allocator-free ()
  "The default allocator's free: the third function pointer of its
cmark_mem, after calloc and realloc (cmark-gfm.h; ADR-0008's first ABI
belief). The call runs with interrupts deferred."
  (cffi:mem-aref (with-interrupts-deferred (cmark-get-default-mem-allocator)) :pointer 2))

;;; Step 1: ECL without dynamic FFI

(defun check-dynamic-ffi ()
  "Signal DYNAMIC-FFI-UNAVAILABLE on an ECL built without :DFFI, which can't
call a library loaded at run time (M2 design §5.2 step 1). Exercised in
M4."
  #+(and ecl (not dffi))
  (error 'dynamic-ffi-unavailable
         :operation 'start-native-layer
         :reason "this ECL was built without dynamic FFI (:dffi)")
  nil)

;;; Step 2: where the pinned pair is (ADR-0009)

(defun current-os ()
  "This machine's system, as RESOLVE-CMARK-LIBRARIES names it: :MACOS on
macOS, and :LINUX everywhere else. The project supports Linux and macOS
(ADR-0001); any other system is searched as Linux is."
  (if (eql (uiop:operating-system) :macosx) :macos :linux))

(defun current-multiarch ()
  "Debian's multiarch name for this machine on Linux, or NIL: on macOS, or
on an architecture ADR-0009 doesn't list."
  (when (eql (current-os) :linux)
    (case (uiop:architecture)
      (:x64 "x86_64-linux-gnu")
      (:arm64 "aarch64-linux-gnu")
      (t nil))))

(defun native-override (libraries)
  "*CMARK-GFM-LIBRARIES*' value LIBRARIES, with each pathname in it
replaced by its native namestring, the path the loader opens. NAMESTRING
would escape it: SBCL writes a * in a pathname as \\*. Anything but a
proper list passes unchanged, for RESOLVE-CMARK-LIBRARIES to reject."
  (if (proper-list-p libraries)
      (mapcar (lambda (library)
                (if (pathnamep library) (uiop:native-namestring library) library))
              libraries)
      libraries))

(defun regular-file-p (path)
  "True when PATH, an absolute native namestring, names a file that exists
and isn't a directory. A probe that fails counts as no file."
  (let ((truename (ignore-errors (probe-file (uiop:parse-native-namestring path)))))
    (and truename (not (uiop:directory-pathname-p truename)))))

;;; Step 3: loading by absolute path

(defun library-designator (path)
  "PATH, an absolute native namestring, in the form
CFFI:LOAD-FOREIGN-LIBRARY must be given to open that very file. CFFI hands
a string to the Lisp's own loader as it is. SBCL's LOAD-SHARED-OBJECT
parses it as a Lisp namestring (src/code/foreign-load.lisp), where * and ?
are wildcards, so SBCL gets a pathname parsed from the native namestring,
which CFFI writes back escaped and SBCL reads back exactly. CCL's
OPEN-SHARED-LIBRARY opens the string itself."
  #+sbcl (uiop:parse-native-namestring path)
  #-sbcl path)

(defun load-library (path override)
  "Load the shared library at PATH, an absolute native namestring, and
return CFFI's object for it. Any load error signals
NATIVE-LIBRARY-NOT-FOUND, naming PATH and carrying the loader's message,
with OVERRIDE, the override in effect, kept (M2 design §5.2 step 3)."
  (handler-case (cffi:load-foreign-library (library-designator path))
    (error (condition)
      (error 'native-library-not-found
             :operation 'start-native-layer
             :override override
             :datum path
             :paths (list path)
             :reason (format nil "the loader could not load it: ~A" condition)))))

(defun close-libraries (core extensions)
  "Close EXTENSIONS, then CORE, CFFI library objects or NIL: the extensions
library first, since it depends on the core. A failure closing one still
closes the other."
  (unwind-protect
       (when extensions
         (cffi:close-foreign-library extensions))
    (when core
      (cffi:close-foreign-library core))))

;;; Steps 4 to 7: what every parse needs

(defun check-version (state)
  "Signal NATIVE-ABI-MISMATCH unless cmark reports the pinned version, first
by string and then by number (M2 design §5.2 step 4; M3 design §5);
otherwise record the string in STATE."
  (let ((found (%version-string)))
    (unless (and (stringp found) (string= found *cmark-gfm-version*))
      (error 'native-abi-mismatch
             :operation 'start-native-layer
             :datum found
             :reason "the loaded cmark-gfm isn't the pinned version"
             :expected-version *cmark-gfm-version*
             :found-version found
             :paths (state-paths state)))
    (check-version-number state)
    (setf (state-version state) found)))

(defun check-version-number (state)
  "Signal NATIVE-ABI-MISMATCH unless cmark_version()'s number matches
(VERSION-NUMBER *CMARK-GFM-VERSION*), once CHECK-VERSION's string check has
passed (M3 design §5). cmark_version() is a C int: FOUND is read through
(LDB (BYTE 32 0) ...) first, so a packed value with bit 31 set (a major
version of 128 or more), which a C int reads back as negative, is compared
and reported as the unsigned 32-bit value it actually is. Without the LDB, a
negative FOUND would still make CALL-STARTUP-STEP signal NATIVE-ABI-MISMATCH
-- NUMBER-VERSION's own range check signals an ERROR like any other step 4
failure -- but with a NIL FOUND-VERSION, naming no version at all. The
reason names both version strings and both numbers, in hex."
  (let* ((found (ldb (byte 32 0) (%version-number)))
         (expected (version-number *cmark-gfm-version*)))
    (unless (= found expected)
      (error 'native-abi-mismatch
             :operation 'start-native-layer
             :datum found
             :reason (format nil "cmark_version() returned #x~8,'0X (~A), not the pinned ~
                                  cmark-gfm's #x~8,'0X (~A)"
                             found (number-version found) expected *cmark-gfm-version*)
             :expected-version *cmark-gfm-version*
             :found-version (number-version found)
             :paths (state-paths state)))))

(defun find-extensions ()
  "An alist from each of *EXTENSION-KEYWORDS* to cmark's pointer for that
syntax extension (M2 design §5.2 step 6). A null signals
NATIVE-INITIALIZATION-ERROR naming the extension."
  (loop for keyword in *extension-keywords*
        for name = (string-downcase (symbol-name keyword))
        for extension = (%find-extension name)
        when (cffi:null-pointer-p extension)
          do (error 'native-initialization-error
                    :operation 'start-native-layer
                    :datum name
                    :reason "cmark has no syntax extension of this name")
        collect (cons keyword extension)))

(defun find-allocator-free ()
  "The default allocator's free (M2 design §5.2 step 7). A null signals
NATIVE-INITIALIZATION-ERROR."
  (let ((free (%allocator-free)))
    (when (cffi:null-pointer-p free)
      (error 'native-initialization-error
             :operation 'start-native-layer
             :reason "cmark's default allocator has no free"))
    free))

;;; Step 8: the smoke parse

(defparameter *smoke-markdown*
  (format nil "| a |~%|---|~%| b |~%~%- [x] done~%~%Note[^1].~%~%[^1]: The note.~%")
  "The smoke parse's input (M2 design §5.2 step 8): a table, a checked task
item and a footnote.")

(defparameter *smoke-kinds* '(:table :task-item :footnote-reference)
  "The kinds the smoke parse must find: proof that the table and tasklist
extensions attach, and that CMARK_OPT_FOOTNOTES parses footnotes.")

(defun smoke-parse-kinds (state)
  "Every kind in *SMOKE-MARKDOWN*, parsed under :GFM with STATE, which
isn't published yet."
  (let ((kinds '()))
    (with-native-document (document *smoke-markdown*
                                    (check-options :parse 'start-native-layer '())
                                    :state state)
      (walk-native (lambda (event node)
                     (when (eql event :enter)
                       (pushnew (native-kind document node) kinds)))
                   document))
    kinds))

;;; Errors from the loaded libraries (M2 design §5.2). An override can name
;;; a library that loads but isn't cmark-gfm, or isn't all of it: a call
;;; into it then signals whatever the Lisp signals for a missing function.
;;; Each step from 4 on turns any error that isn't already its own
;;; condition into that condition, naming the original.

(defun call-startup-step (function condition-type initargs what)
  "Call FUNCTION, one of startup's steps 4 to 8, and return its values. An
ERROR it signals that isn't of CONDITION-TYPE signals CONDITION-TYPE
instead, with INITARGS, the original condition as its datum, and a reason
naming WHAT the step does and the original condition."
  (handler-bind ((error (lambda (condition)
                          (unless (typep condition condition-type)
                            (apply #'error condition-type
                                   :operation 'start-native-layer
                                   :datum condition
                                   :reason (format nil "~A failed: ~A" what condition)
                                   initargs)))))
    (funcall function)))

(defmacro startup-step ((condition-type what &rest initargs) &body body)
  "Run BODY as a startup step that signals only CONDITION-TYPE, a
NATIVE-ERROR, by CALL-STARTUP-STEP. WHAT names the step in a converted
condition's reason; INITARGS are evaluated."
  `(call-startup-step (lambda () ,@body) ',condition-type (list ,@initargs) ,what))

(defun smoke-test (state)
  "Signal NATIVE-INITIALIZATION-ERROR, naming the kinds it didn't find,
unless the smoke parse under STATE finds each of *SMOKE-KINDS* (M2 design
§5.2 step 8)."
  (let* ((kinds (smoke-parse-kinds state))
         (missing (remove-if (lambda (kind) (member kind kinds)) *smoke-kinds*)))
    (when missing
      (error 'native-initialization-error
             :operation 'start-native-layer
             :datum missing
             :reason "the smoke parse didn't find every kind it needs"))))

;;; Steps 1 to 8

(defun start-native-layer ()
  "Run M2 design §5.2's steps 1 to 8, and return the new state, not yet
published. A failure in steps 3 to 8 closes whatever this attempt loaded,
the extensions library first. From step 4 on, any error that isn't the
step's own condition becomes it: NATIVE-ABI-MISMATCH in step 4,
NATIVE-INITIALIZATION-ERROR in steps 5 to 8, every failure of the smoke
parse included. Called only under *STARTUP-LOCK*:
cmark_gfm_core_extensions_ensure_registered keeps an unlocked static flag
(extensions/core-extensions.c)."
  (check-dynamic-ffi)
  (let* ((libraries (native-override *cmark-gfm-libraries*))
         (environment (uiop:getenv "CL_COMMONMARK_GFM_LIBS"))
         (paths (resolve-cmark-libraries :libraries libraries
                                         :environment environment
                                         :os (current-os)
                                         :multiarch (current-multiarch)
                                         :regular-file-p #'regular-file-p))
         (override (or libraries environment))
         (core nil)
         (extensions nil)
         (started-state nil))
    (unwind-protect
         (progn
           (setf core (load-library (first paths) override))
           (setf extensions (load-library (second paths) override))
           (let ((state (make-native-state core extensions paths)))
             (startup-step (native-abi-mismatch "reading cmark's version"
                                                :expected-version *cmark-gfm-version*
                                                :paths paths)
               (check-version state))
             (startup-step (native-initialization-error "registering the extensions")
               (with-interrupts-deferred
                 (cmark-gfm-core-extensions-ensure-registered)))
             (startup-step (native-initialization-error "finding the extensions")
               (setf (state-extensions state) (find-extensions)))
             (startup-step (native-initialization-error "reading the allocator")
               (setf (state-free state) (find-allocator-free)))
             (startup-step (native-initialization-error "the smoke parse")
               (smoke-test state))
             (setf started-state state)))
      (unless started-state
        (close-libraries core extensions)))
    started-state))

;;; Step 9: the published state

(defun published-state ()
  "The published native state, after starting up and publishing when none
is. Called only by CALL-WITH-PUBLISHED-STATE, under *STARTUP-LOCK*, so
with interrupts deferred."
  (or *published-state*
      (let ((state (start-native-layer)))
        (setf *published-state* state)
        (note-startup-published)
        state)))

(defun call-with-published-state (function)
  "Call FUNCTION with the published native state, under *STARTUP-LOCK*,
after starting up and publishing when none is, and return FUNCTION's value.

A failed startup doesn't call FUNCTION. Its ERROR is caught under the lock,
once START-NATIVE-LAYER has closed what it loaded, and signalled again
after the lock is released, with interrupts as the caller had them (M2
design §11). So a caller's handler, or the debugger, never runs holding the
lock with interrupts deferred, where no timeout could land and every other
thread's call would wait for it. A SERIOUS-CONDITION that isn't an ERROR,
such as heap exhaustion, isn't caught."
  (let* ((failure nil)
         (value (with-startup-lock
                  (let ((state (handler-case (published-state)
                                 (error (condition)
                                   (setf failure condition)
                                   nil))))
                    (when state
                      (funcall function state))))))
    (when failure
      (error failure))
    value))

(defun native-state ()
  "The published native state, after starting up when none is published
(M2 design §5.2). Startup runs at most once at a time, under
*STARTUP-LOCK*; the state is then used after the lock is released. Takes
no hold: a call that parses uses WITH-NATIVE-STATE.

A failed startup publishes nothing and signals a NATIVE-ERROR, after the
lock is released, with interrupts as the caller had them (M2 design §11):
- DYNAMIC-FFI-UNAVAILABLE, on an ECL built without :DFFI (step 1);
- NATIVE-LIBRARY-NOT-FOUND, when no pair is found, an override is
  malformed or names a missing file, or the loader can't load a file
  (steps 2 and 3);
- NATIVE-ABI-MISMATCH, when cmark reports another version, or any other
  error comes from reading it (step 4);
- NATIVE-INITIALIZATION-ERROR, for any failure in steps 5 to 8: an
  extension or the allocator's free missing, an error from the loaded
  libraries, or a smoke parse that fails or finds too little."
  (call-with-published-state #'identity))

(defun native-state-published-p ()
  "True when a native state is published."
  (with-startup-lock
    (and *published-state* t)))

;;; Holding the published state (M2 design §5.3; finding 18)

(defun hold-native-state (token)
  "NATIVE-STATE's state, held for TOKEN, a fresh cons: TOKEN joins *HOLDS*
in the same critical section that hands the state over, with interrupts
deferred throughout. When startup fails, TOKEN joins nothing, and the
failure is signalled as NATIVE-STATE signals it."
  (call-with-published-state (lambda (state)
                               (push token *holds*)
                               state)))

(defun release-native-state (token)
  "End TOKEN's hold, if it has one, with interrupts deferred, so no
interrupt can land between dropping TOKEN from the list and storing the
list."
  (with-startup-lock
    (setf *holds* (delete token *holds*))))

(defun call-with-native-state (function)
  "Call FUNCTION with the published native state, held until FUNCTION
returns or exits: WITH-NATIVE-STATE's function. The hold ends with
interrupts deferred from the moment FUNCTION is left, by
UNWIND-PROTECT-DEFERRED, so no interrupt can skip its end."
  (let ((token (list :hold)))
    (unwind-protect-deferred
        (funcall function (hold-native-state token))
      (release-native-state token))))

(defmacro with-native-state ((state) &body body)
  "Run BODY with STATE bound to the published native state, starting up
first when none is published, and hold the state for BODY's extent (M2
design §5.3). The hold begins under *STARTUP-LOCK*, as the state is handed
over, and ends however BODY exits, with interrupts deferred from the moment
BODY is left, so it can't leak.
While any call holds the state, RESET-NATIVE-STATE, and so the save hooks,
signal NATIVE-STATE-HELD and close nothing. Every call that parses runs
its WITH-NATIVE-DOCUMENT inside one: the entry points directly, and
WITH-NATIVE-DOCUMENT itself when given no state. Signals what NATIVE-STATE
signals."
  `(call-with-native-state (lambda (,state) ,@body)))

(define-condition native-state-held (error)
  ((holds :reader native-state-holds
          :initarg :holds
          :initform 0
          :documentation "How many calls held the state."))
  (:report (lambda (condition stream)
             (format stream "reset-native-state: ~D call~:P hold~:[s~;~] cmark-gfm's ~
                             native state, so nothing was closed"
                     (native-state-holds condition) (/= 1 (native-state-holds condition)))))
  (:documentation
   "Signalled by RESET-NATIVE-STATE, and so by the save hooks, while any
call holds the published state (M2 design §5.3; finding 18): closing
cmark-gfm then would unload it under a live parse. Internal and
unexported, like NATIVE-DOCUMENT-RELEASED."))

(defun reset-native-state ()
  "Unpublish the native state and close both its libraries, extensions
first, under *STARTUP-LOCK*, so the next call starts up again. The tests
use it, and so does the save hook (M2 design §5.3).

Never under a parse (finding 18): while any call holds the state, from
the moment it is handed over until the call's document is released, this
signals NATIVE-STATE-HELD, after releasing the lock, and closes nothing;
the state stays published. Holds are taken under the same lock, so no
call can start holding a state this is closing.

A restart in the same process relies on the loader unloading both: cmark
keeps its registry of syntax extensions in the core library
(src/registry.c), and a core left loaded would still list the extensions
of the library unloaded under it."
  (let ((holds (with-startup-lock
                 (cond
                   (*holds* (length *holds*))
                   (t (let ((state *published-state*))
                        (setf *published-state* nil)
                        (when state
                          (close-libraries (state-core-library state)
                                           (state-extensions-library state))))
                      0)))))
    (when (plusp holds)
      (error 'native-state-held :holds holds))))
