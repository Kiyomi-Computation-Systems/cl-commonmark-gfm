;;;; Starting the native layer, in nine steps, which the sections below
;;;; follow: (1) on an ECL without dynamic FFI, signal
;;;; DYNAMIC-FFI-UNAVAILABLE; (2) find the pinned pair; (3) load the core,
;;;; then the extensions, by absolute path, never by bare name, so the
;;;; loader opens those very files; (4) check cmark's version; (5) register
;;;; the core extensions; (6) find the five syntax extensions; (7) read the
;;;; default allocator's free; (8) smoke-test a parse; (9) publish the
;;;; state. Once per process, on first use, under the startup lock. A failed
;;;; attempt closes what it loaded and publishes nothing, so the next call
;;;; starts again.
;;;;
;;;; A linked ECL program has cmark-gfm linked in: ECL compiled cmark's
;;;; calls, all in src/ffi.lisp, with CFFI's :C/C++ method, so each is a
;;;; direct C call, bound when the program was linked. Its startup has
;;;; nothing to find or load: it skips steps 1 to 3, reading neither
;;;; override, and runs the rest on a state that names no files, its paths
;;;; :LINKED. Which method compiled the calls is recorded where they
;;;; compile, as they compile (FFI-METHOD, from src/ffi.lisp): at run time,
;;;; CFFI's variable holds ECL's default again. So even a program whose
;;;; files were compiled under different methods starts by what its calls
;;;; do.
;;;;
;;;; A call that parses holds the published state, from the moment it is
;;;; handed over until the call's document is released. While any call
;;;; holds it, closing cmark signals and closes nothing: no reset, not even
;;;; the save hook's, unloads cmark-gfm under a parse.
;;;;
;;;; Everything done under the startup lock runs with interrupts deferred,
;;;; from the wait for the lock until its release: startup and its cmark
;;;; calls, publishing, closing, and taking and ending a hold. So an
;;;; interrupt can't land between taking a hold and recording it, or leave
;;;; one recorded after its call has ended.
;;;;
;;;; A caller's handler of a failed startup doesn't run there. The
;;;; startup's error is caught under the lock, once the attempt has closed
;;;; what it loaded, and signalled after the lock is released, with
;;;; interrupts as the caller had them. Otherwise the handler, or the
;;;; debugger, would run holding the lock with interrupts deferred: no
;;;; timeout could land in it, and every other thread's call would wait for
;;;; it.
;;;;
;;;; A CCL process keeps the first pair it loads. CCL never unloads a
;;;; library it has called into, and CFFI's CCL backend calls a function by
;;;; its name alone, so a later pair could run an earlier pair's code.
;;;; Startup on CCL records the first pair's truenames, and refuses any
;;;; other pair before calling into it. SBCL and ECL unload both libraries
;;;; on close, and keep no record.

(in-package #:cl-commonmark-gfm.native)

(defvar *startup-lock* (bt2:make-lock :name "cl-commonmark-gfm startup")
  "Held while starting up, publishing, resetting, reading the published
state, or taking or ending a hold on it, never while a caller parses or
handles a failed startup, and always by WITH-STARTUP-LOCK. Lock order:
startup's smoke parse takes the finish lock while holding this one; nothing
takes this one while holding the finish lock.")

(defvar *published-state* nil
  "The NATIVE-STATE every parse uses, or NIL before startup. Read and
written only under *STARTUP-LOCK*.")

(defvar *holds* '()
  "One token for each call that holds the published state: pushed in the
critical section that hands the state over, and removed once the call's
document is released. Read and written only under *STARTUP-LOCK*. While
it isn't empty, RESET-NATIVE-STATE closes nothing.")

(defmacro with-startup-lock (&body body)
  "Run BODY holding *STARTUP-LOCK*, with interrupts deferred from the wait
for the lock until its release. A thread waiting for the lock can't be
interrupted until it has had it, and a startup holding it may take tens
of milliseconds. A handler of a condition BODY signals runs there,
holding the lock with interrupts deferred, so a condition meant for a
caller is signalled after the release: a failed startup's by
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
  "cmark_version's result: a C int, so a packed value with bit 31 set (a
major version of 128 or more) can come back negative. The call runs with
interrupts deferred, as every cmark call does."
  (with-interrupts-deferred (cmark-version)))

(defun %find-extension (name)
  "cmark_find_syntax_extension's pointer for the extension called NAME, or
null when none is registered under it (vendor/cmark-gfm/src/registry.c).
The call runs with interrupts deferred, as every cmark call does, and so
does the foreign copy of NAME that CFFI allocates and frees around it."
  (with-interrupts-deferred
    (cmark-find-syntax-extension name)))

(defun %allocator-free ()
  "The default allocator's free: the third function pointer of its
cmark_mem, after calloc and realloc (vendor/cmark-gfm/src/cmark-gfm.h).
No C compiler checks that layout here; a native test checks that the
three slots are non-null and distinct. The call runs with interrupts
deferred."
  (cffi:mem-aref (with-interrupts-deferred (cmark-get-default-mem-allocator)) :pointer 2))

;;; Step 1: ECL without dynamic FFI

(defun check-dynamic-ffi ()
  "Signal DYNAMIC-FFI-UNAVAILABLE on an ECL built without :DFFI, where CFFI
refuses to load a library at run time, so startup can't load the pair:
its datum the missing feature, :DFFI, and its reason saying how to link
cmark-gfm into a program instead, whose startup skips this step. It comes
first so that the failure says what to do: otherwise discovery finds the
pair, and the load fails as NATIVE-LIBRARY-NOT-FOUND, with CFFI's message
pointing at ECL's FFI:LOAD-FOREIGN-LIBRARY. On SBCL, CCL and an ECL with
:DFFI, it does nothing."
  #+(and ecl (not dffi))
  (error 'dynamic-ffi-unavailable
         :operation 'start-native-layer
         :datum :dffi
         :reason (format nil "this ECL was built without dynamic FFI, so it can't load ~
                              cmark-gfm at run time; to link cmark-gfm into a program ~
                              instead, compile with cffi-sys:*cffi-ecl-method* set to ~
                              :c/c++, and link libcmark-gfm-extensions.a and ~
                              libcmark-gfm.a"))
  nil)

;;; Step 2: where the pinned pair is

(defun current-os ()
  "This machine's system, as RESOLVE-CMARK-LIBRARIES names it: :MACOS on
macOS, and :LINUX everywhere else. The project supports Linux and macOS;
any other system is searched as Linux is."
  (if (eql (uiop:operating-system) :macosx) :macos :linux))

(defun current-multiarch ()
  "Debian's multiarch name for this machine on Linux, or NIL: on macOS, or
on an architecture other than the two the project supports, x64 and
arm64."
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
parses it as a Lisp namestring (SBCL's src/code/foreign-load.lisp), where
* and ? are wildcards, so SBCL gets a pathname parsed from the native
namestring, which CFFI writes back escaped and SBCL reads back exactly.
CCL's OPEN-SHARED-LIBRARY opens the string itself."
  #+sbcl (uiop:parse-native-namestring path)
  #-sbcl path)

(defun load-library (path override override-name)
  "Load the shared library at PATH, an absolute native namestring, and
return CFFI's object for it. Any load error signals
NATIVE-LIBRARY-NOT-FOUND, naming PATH and carrying the loader's message,
with OVERRIDE, the override in effect, kept. Its reason says where PATH
came from: OVERRIDE-NAME, the name of the override that gave it, or the
directory search when OVERRIDE-NAME is NIL."
  (handler-case (cffi:load-foreign-library (library-designator path))
    (error (condition)
      (error 'native-library-not-found
             :operation 'start-native-layer
             :override override
             :datum path
             :paths (list path)
             :reason (format nil "~A a library the loader could not load: ~A"
                             (if override-name
                                 (format nil "~A names" override-name)
                                 "the directory search found")
                             condition)))))

;;; Step 3, on CCL: one pair per process. CCL never unloads a library it
;;; has called into: closing it leaves it mapped. And CFFI's CCL backend
;;; calls a foreign function by its name alone, ignoring the library (CFFI's
;;; src/cffi-openmcl.lisp), so a later pair could run an earlier pair's
;;; code. So the first pair a CCL process loads is its pair for good, and
;;; another is refused before any call into it. Closed with nothing called,
;;; a refused pair leaves nothing mapped.

(defvar *loaded-pair* nil
  "On CCL, this process's pair, or NIL before any: a plist of :TRUENAMES,
the two libraries' truenames as native namestrings, core then extensions,
and :SONAMES, the sonames CCL recorded them under, which the save hook's
forgetting matches (FORGET-RECORDED-PAIR). Recorded once both libraries
of the first pair had loaded, before any call into them, and kept however
that startup ended, since a call may already have pinned the pair. As a
saved image starts, forgotten, or replaced by the pair CCL reopened then
(CLEAR-NATIVE-STATE-ON-RESTART). Always NIL on SBCL and ECL. Read and
written only under *STARTUP-LOCK*.")

(defun loaded-pair ()
  "The truenames, as native namestrings, core then extensions, of this CCL
process's pair: the first it loaded, or the one CCL reopened as its saved
image started. A fresh list, or NIL before any. Always NIL on SBCL and
ECL, which keep no record."
  (with-startup-lock
    (copy-list (getf *loaded-pair* :truenames))))

#+ccl
(declaim (notinline library-truename))

#+ccl
(defun library-truename (path)
  "The truename of the file at PATH, an absolute native namestring, as a
native namestring: its real path, symbolic links resolved, as Linux's
/proc/self/maps names it. PATH is parsed as a native namestring, and the
truename written back as one, so a * in PATH stays a plain character:
neither a wildcard nor escaped, as NAMESTRING would write it (\\*). The
star-path test checks it on CCL. A missing file signals FILE-ERROR.
NOTINLINE: a test redefines it."
  (uiop:native-namestring (truename (uiop:parse-native-namestring path))))

#+ccl
(defun keep-one-pair (paths libraries)
  "Record the pair at PATHS, whose LIBRARIES, CFFI's objects for them, core
then extensions, have just loaded, as this process's pair when none is
recorded: their truenames, and the sonames CCL recorded them under, read
from the CCL:SHLIB objects CFFI keeps as their handles
(SHARED-LIBRARY-RECORDS). When one is, and these truenames differ, signal
NATIVE-INITIALIZATION-ERROR: its datum the refused pair's truenames, its
reason naming the recorded pair. An error reading a truename or a soname
leaves the record as it was. Called by START-LOADED-NATIVE-LAYER on CCL
alone, under *STARTUP-LOCK*, before any call into the pair, so a refused
pair closes with nothing called."
  (let ((truenames (mapcar #'library-truename paths))
        (recorded (getf *loaded-pair* :truenames)))
    (cond ((null recorded)
           (setf *loaded-pair*
                 (list :truenames truenames
                       :sonames (mapcar (lambda (record) (ccl::shlib.soname record))
                                        (shared-library-records libraries)))))
          ((not (equal truenames recorded))
           (error 'native-initialization-error
                  :operation 'start-native-layer
                  :datum truenames
                  :reason (format nil "CCL can't unload the cmark-gfm pair this process loaded ~
                                       first, ~A and ~A, so another pair needs a new process"
                                  (first recorded) (second recorded)))))))

;;; As a saved image starts, CCL reopens by soname every record it still
;;; lists, before the restore hook runs (REFRESH-EXTERNAL-ENTRYPOINTS, CCL
;;; 1.13's level-0/l0-cfm-support.lisp): a record other code held open
;;; across the save, or any record when the save hook was skipped. Such an
;;; image maps the pair from its start, and CFFI's lookups by name land in
;;; it, so it keeps that pair as its own.

#+ccl
(defun reopened-path (record)
  "The path of the file CCL maps for RECORD, a CCL:SHLIB, or NIL when it
maps none. On Linux, a record CCL reopened as the image started, or found
mapped already, has a link map again, and the path the loader opened
(REVIVE-SHARED-LIBRARIES, %REOPEN-USER-LIBRARIES); one it couldn't reopen,
or that a close emptied, has neither. On macOS, CCL opens a library by the
path it is given and keeps that path as the record's soname, and a record
it reopened has a handle again (REOPEN-USER-LIBRARIES)."
  #+darwin (and (ccl::shlib.handle record) (ccl::shlib.soname record))
  #-darwin (and (ccl::shlib.map record) (ccl::shlib.pathname record)))

#+ccl
(defun reopened-pair-record (record)
  "The pair record a saved image starts with, given RECORD, the one it was
saved with: when CCL lists both of RECORD's sonames again and maps both,
having reopened them as the image started, a record of the files it
reopened, their truenames with the same sonames, so the image refuses
another pair; otherwise NIL, as when the save hook made CCL forget both
records, or CCL reopened only one. A truename that can't be read gives NIL
too: the restore hook, which calls this as the image starts, mustn't
signal."
  (let* ((sonames (getf record :sonames))
         (paths (loop for soname in sonames
                      for listed = (find soname ccl::*shared-libraries*
                                         :key (lambda (shlib) (ccl::shlib.soname shlib))
                                         :test #'equal)
                      collect (and listed (reopened-path listed)))))
    (when (and sonames (notany #'null paths))
      (let ((truenames (ignore-errors (mapcar #'library-truename paths))))
        (when truenames
          (list :truenames truenames :sonames sonames))))))

;;; Closing, and on CCL forgetting. CCL keeps a record of each shared
;;; library it has opened, on CCL::*SHARED-LIBRARIES*: one record a soname,
;;; however many times the library is opened, with a count of the opens not
;;; yet closed (OPEN-SHARED-LIBRARY-INTERNAL, CCL 1.13's
;;; level-0/l0-cfm-support.lisp). CCL:CLOSE-SHARED-LIBRARY, which CFFI's
;;; close calls, leaves a closed library there. A saved image reopens every
;;; library on that list by its soname as it starts
;;; (REFRESH-EXTERNAL-ENTRYPOINTS): by bare name, from wherever the loader
;;; finds it, where startup loads only by absolute path, and an image saved
;;; after a startup would start with both libraries mapped. So on CCL every
;;; close also makes CCL forget the libraries it closed: a reset, and so the
;;; save hook, and every failed startup, the refusal of another pair
;;; included.
;;;
;;; Only a record that nothing holds open is forgotten, its open count 0.
;;; Other code in the process, such as a user's own CFFI load of the same
;;; files, shares the record, and its open is still counted once startup's
;;; is closed: CCL keeps that record, and a saved image reopens it, as the
;;; other code expects.
;;;
;;; The forgetting lasts until CCL next opens a library, any library: it
;;; then records again every library it maps but doesn't list
;;; (OPEN-SHARED-LIBRARY-INTERNAL), and it still maps one it has called
;;; into. So the save hook, after its reset, also makes CCL forget whatever
;;; it lists again of the recorded pair's libraries (FORGET-RECORDED-PAIR).
;;; It finds those records by the sonames recorded with the pair
;;; (KEEP-ONE-PAIR): CCL keeps one record a soname, and a record CCL emptied
;;; on close still has its soname, though it names no file.

#+ccl
(defun shared-library-records (libraries)
  "CCL's records of LIBRARIES, CFFI library objects or NIL: the CCL:SHLIB
objects CCL:OPEN-SHARED-LIBRARY returned, which CFFI keeps as their handles
(CFFI's src/cffi-openmcl.lisp). Read them before the libraries close:
closing clears CFFI's handles. CFFI exports no reader of a handle."
  (loop for library in libraries
        for record = (and library (cffi::foreign-library-handle library))
        when record
          collect record))

#+ccl
(defun forget-shared-libraries (records)
  "Make CCL forget each of RECORDS, CCL:SHLIB objects, that nothing holds
open, its open count 0, so a saved image neither reopens it as it starts
nor looks for a function in it. RECORDS are libraries just closed, or
records CCL listed again when it last opened a library
(FORGET-RECORDED-PAIR). One that other code still holds open stays, and a
saved image reopens it, as that code expects. Takes each forgotten record
off CCL's list of the shared libraries it has opened, and detaches every
entry point CCL resolved in it: an entry point keeps the library it was
found in, and calling it once that record has no handle signals
\"Shared library not open\" (RESOLVE-EEP). Detached, it is looked up again
by name when next called. CCL exports no function for either, so this
edits CCL 1.13's own records (level-0/l0-cfm-support.lisp). CCL guards its
list with no lock: a CFFI load in another thread at the same moment can
race with this edit, as two of CCL's own opens can race with each other.
Called only under *STARTUP-LOCK*."
  (let ((unheld (remove-if-not (lambda (record) (zerop (ccl::shlib.opencount record))) records)))
    (setf ccl::*shared-libraries*
          (remove-if (lambda (record) (member record unheld)) ccl::*shared-libraries*))
    (maphash (lambda (name entry-point)
               (declare (ignore name))
               (when (member (ccl::eep.container entry-point) unheld)
                 (setf (ccl::eep.container entry-point) nil
                       (ccl::eep.address entry-point) nil)))
             (ccl::eeps))))

#+ccl
(defun forget-recorded-pair ()
  "Make CCL forget every record it lists of the recorded pair's libraries
that nothing holds open (FORGET-SHARED-LIBRARIES): the records under the
sonames recorded with the pair (KEEP-ONE-PAIR). The save hook calls it
after its reset, which closed and forgot the published pair, if any: CCL
may have listed the pair's libraries again since, when it last opened a
library. With no pair recorded, it forgets nothing. Reads the pair record
and edits CCL's records in one hold of *STARTUP-LOCK*."
  (with-startup-lock
    (let ((sonames (getf *loaded-pair* :sonames)))
      (forget-shared-libraries
       (remove-if-not (lambda (record)
                        (member (ccl::shlib.soname record) sonames :test #'equal))
                      ccl::*shared-libraries*)))))

(defun close-libraries (core extensions)
  "Close EXTENSIONS, then CORE, CFFI library objects or NIL: the extensions
library first, since it depends on the core. A failure closing one still
closes the other. On CCL, then make CCL forget each of the two that nothing
holds open any more (FORGET-SHARED-LIBRARIES), so no saved image reopens
it: their records are read before the closes clear CFFI's handles, and
forgotten in the outermost cleanup, so a close that signals still forgets.
Called only under *STARTUP-LOCK*."
  (let (#+ccl (records (shared-library-records (list extensions core))))
    (unwind-protect
         (unwind-protect
              (when extensions
                (cffi:close-foreign-library extensions))
           (when core
             (cffi:close-foreign-library core)))
      #+ccl
      (forget-shared-libraries records))))

;;; Steps 4 to 7: what every parse needs

(defun check-version (state)
  "Signal NATIVE-ABI-MISMATCH unless cmark reports the pinned version, first
by string and then by number; otherwise record the string in STATE."
  (let ((found (%version-string)))
    (unless (and (stringp found) (string= found *cmark-gfm-version*))
      (error 'native-abi-mismatch
             :operation 'start-native-layer
             :datum found
             :reason "the cmark-gfm in use isn't the pinned version"
             :expected-version *cmark-gfm-version*
             :found-version found
             :paths (state-paths state)))
    (check-version-number state)
    (setf (state-version state) found)))

(defun check-version-number (state)
  "Signal NATIVE-ABI-MISMATCH unless cmark_version()'s number matches
(VERSION-NUMBER *CMARK-GFM-VERSION*), once CHECK-VERSION's string check has
passed. cmark_version() is a C int: FOUND is read through
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
syntax extension (step 6). A null signals NATIVE-INITIALIZATION-ERROR
naming the extension."
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
  "The default allocator's free (step 7). A null signals
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
  "The smoke parse's input: a table, a checked task item and a footnote.")

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

;;; Errors from the loaded libraries. An override can name a library that
;;; loads but isn't cmark-gfm, or isn't all of it: a call into it then
;;; signals whatever the Lisp signals for a missing function. Each step from
;;; 4 on, and on CCL the pair record, turns any error that isn't already
;;; its own condition into that condition, naming the original, so no raw
;;; FFI error escapes those steps.

(defun call-startup-step (function condition-type initargs what)
  "Call FUNCTION, one of startup's steps 4 to 8 or, on CCL, the pair
record, and return its values. An ERROR it signals that isn't of
CONDITION-TYPE signals CONDITION-TYPE instead, with INITARGS, the original
condition as its datum, and a reason naming WHAT the step does and the
original condition."
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
unless the smoke parse under STATE finds each of *SMOKE-KINDS*."
  (let* ((kinds (smoke-parse-kinds state))
         (missing (remove-if (lambda (kind) (member kind kinds)) *smoke-kinds*)))
    (when missing
      (error 'native-initialization-error
             :operation 'start-native-layer
             :datum missing
             :reason "the smoke parse didn't find every kind it needs"))))

;;; Steps 4 to 8, the same for a linked program as for one that loads the
;;; pair

(defun prepare-native-state (state)
  "Run startup's steps 4 to 8 on STATE, not yet published, and return it:
check cmark's version, register the core extensions, find the five
extensions and the allocator's free, which STATE then holds, and run the
smoke parse. Any error that isn't the step's own condition becomes it:
NATIVE-ABI-MISMATCH in step 4, naming STATE's paths, and
NATIVE-INITIALIZATION-ERROR in steps 5 to 8, every failure of the smoke
parse included. STATE names the two libraries startup loaded, or, in a
linked program, none."
  (startup-step (native-abi-mismatch "reading cmark's version"
                                     :expected-version *cmark-gfm-version*
                                     :paths (state-paths state))
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
  state)

;;; Steps 1 to 8

(defun start-loaded-native-layer ()
  "Run startup's steps 1 to 8, loading the pinned pair, and return the new
state, not yet published. A failure in steps 3 to 8 closes whatever this
attempt loaded, the extensions library first. On CCL, once step 3 has
loaded both libraries, and before step 4's first call into them,
KEEP-ONE-PAIR records the pair, or refuses one other than this process's.
From then on, any error that isn't the step's own condition becomes it:
NATIVE-INITIALIZATION-ERROR in that record, then as PREPARE-NATIVE-STATE
says."
  (check-dynamic-ffi)
  (let* ((libraries (native-override *cmark-gfm-libraries*))
         (environment (uiop:getenv "CL_COMMONMARK_GFM_LIBS"))
         (override (or libraries environment))
         (core nil)
         (extensions nil)
         (started-state nil))
    (multiple-value-bind (paths override-name)
        (resolve-cmark-libraries :libraries libraries
                                 :environment environment
                                 :os (current-os)
                                 :multiarch (current-multiarch)
                                 :regular-file-p #'regular-file-p)
      (unwind-protect
           (progn
             (setf core (load-library (first paths) override override-name))
             (setf extensions (load-library (second paths) override override-name))
             #+ccl
             (startup-step (native-initialization-error "recording the loaded pair")
               (keep-one-pair paths (list core extensions)))
             (setf started-state
                   (prepare-native-state (make-native-state core extensions paths))))
        (unless started-state
          (close-libraries core extensions))))
    started-state))

(defun start-linked-native-layer ()
  "Run startup's steps 4 to 8 alone, in a linked program, and return the
new state, not yet published. cmark-gfm is linked in, so there is no
dynamic FFI to check for, no pair to find and nothing to load: neither
*CMARK-GFM-LIBRARIES* nor CL_COMMONMARK_GFM_LIBS is read. The state's two
libraries are NIL, and its paths :LINKED. A failure closes nothing, since
nothing was loaded."
  (prepare-native-state (make-native-state nil nil :linked)))

(defun start-native-layer ()
  "Start cmark-gfm and return the new state, not yet published. In a
linked program, steps 4 to 8 alone (START-LINKED-NATIVE-LAYER): its state
names no libraries, its paths :LINKED. Otherwise steps 1 to 8, loading
the pinned pair (START-LOADED-NATIVE-LAYER). LINKED-METHOD-P tells which
from FFI-METHOD, the method cmark's calls compiled with, recorded in
src/ffi.lisp where they compile: so a program whose files were compiled
under different methods starts by what its calls do. Called only under
*STARTUP-LOCK*: cmark_gfm_core_extensions_ensure_registered keeps an
unlocked static flag (vendor/cmark-gfm/extensions/core-extensions.c)."
  (if (linked-method-p (ffi-method))
      (start-linked-native-layer)
      (start-loaded-native-layer)))

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
after the lock is released, with interrupts as the caller had them. So a
caller's handler, or the debugger, never runs holding the lock with
interrupts deferred, where no timeout could land and every other thread's
call would wait for it. A SERIOUS-CONDITION that isn't an ERROR, such as
heap exhaustion, isn't caught."
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
  "The published native state, after starting up when none is published.
Startup runs at most once at a time, under *STARTUP-LOCK*; the state is
then used after the lock is released. Takes no hold: a call that parses
uses WITH-NATIVE-STATE.

A linked ECL program, one whose cmark calls (src/ffi.lisp) ECL compiled
with CFFI's :C/C++ method, has cmark-gfm linked in. Its startup finds and
loads nothing, and reads neither *CMARK-GFM-LIBRARIES* nor
CL_COMMONMARK_GFM_LIBS: it runs steps 4 to 9 alone, and its state's paths
are :LINKED.

A failed startup publishes nothing and signals a NATIVE-ERROR, after the
lock is released, with interrupts as the caller had them:
- DYNAMIC-FFI-UNAVAILABLE, on an ECL built without :DFFI whose native
  layer isn't linked (step 1): its datum :DFFI, and its reason saying how
  to build a linked program instead;
- NATIVE-LIBRARY-NOT-FOUND, when no pair is found, an override is
  malformed or names a missing file, or the loader can't load a file
  (steps 2 and 3), never in a linked program;
- NATIVE-ABI-MISMATCH, when cmark reports another version, or any other
  error comes from reading it (step 4);
- NATIVE-INITIALIZATION-ERROR, for any failure in steps 5 to 8: an
  extension or the allocator's free missing, an error from the loaded
  libraries, or a smoke parse that fails or finds too little; and on CCL,
  for an error while recording the pair, or for a pair other than the one
  this process loaded first, which CCL can't unload.
On CCL, once the first pair whose libraries both load has been recorded,
before any call into it, it is this process's pair from then on, whether
or not that startup succeeds (KEEP-ONE-PAIR). An error while recording
leaves the record as it was, so the pair is not recorded. A saved image
starts with no record, unless CCL reopened the pair as it started
(CLEAR-NATIVE-STATE-ON-RESTART)."
  (call-with-published-state #'identity))

(defun native-state-published-p ()
  "True when a native state is published."
  (with-startup-lock
    (and *published-state* t)))

;;; Holding the published state

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
first when none is published, and hold the state for BODY's extent. The
hold begins under *STARTUP-LOCK*, as the state is handed over, and ends
however BODY exits, with interrupts deferred from the moment BODY is
left, so it can't leak.
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
call holds the published state: closing cmark-gfm then would unload it
under a live parse. Internal and unexported, like
NATIVE-DOCUMENT-RELEASED."))

(defun reset-native-state ()
  "Unpublish the native state and close both its libraries, extensions
first, under *STARTUP-LOCK*, so the next call starts up again. The tests
use it, and so does the save hook.

Never under a parse: while any call holds the state, from the moment it
is handed over until the call's document is released, this signals
NATIVE-STATE-HELD, after releasing the lock, and closes nothing; the
state stays published. Holds are taken under the same lock, so no call
can start holding a state this is closing.

A restart in the same process relies on the loader unloading both: cmark
keeps its registry of syntax extensions in the core library
(vendor/cmark-gfm/src/registry.c), and a core left loaded would still
list the extensions of the library unloaded under it. CCL unloads neither
once a startup has called into them, so there only the same pair starts
again (KEEP-ONE-PAIR), its extensions still mapped beside its core.

A linked program's state names no libraries, so its reset closes nothing:
cmark-gfm stays linked in, and the next call starts again, running steps
4 to 9 on the same code. Its registry still lists the extensions, and
registering them again does nothing:
cmark_gfm_core_extensions_ensure_registered keeps a static flag
(vendor/cmark-gfm/extensions/core-extensions.c)."
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
