;;;; Saved images (M2 design §5.3; ADR-0017; D12, findings 12 and 18). An
;;;; image keeps the libraries its process loaded, and the published
;;;; state's pointers into them. CFFI loads a library on SBCL with
;;;; SB-ALIEN:LOAD-SHARED-OBJECT, without :DONT-SAVE, so a saved image
;;;; would reopen cmark-gfm when it starts, at the path the saving machine
;;;; used, and its state would point into a process that is gone. So before
;;;; an image is saved, a hook resets the native state: both libraries
;;;; close, and nothing stays published. The image's first call starts up
;;;; again, on whatever machine it runs.
;;;;
;;;; Never under a parse (finding 18). SBCL runs its save hooks first in
;;;; DEINIT, and only then refuses a save while other threads run
;;;; (SAVE-WITH-MULTIPLE-THREADS-ERROR, src/code/save.lisp). A hook that
;;;; closed cmark there would close it under those threads' parses. So
;;;; while any call holds the state (WITH-NATIVE-STATE), the reset signals
;;;; NATIVE-STATE-HELD and closes nothing: SBCL's CALL-HOOKS reports that
;;;; as an error, and the save fails before anything is unloaded.
;;;;
;;;; A restore hook too. A save can still go ahead without the save hook,
;;;; as when a user skips it from the debugger. The image then carries the
;;;; published state, whose pointers lead into libraries that SBCL reopens,
;;;; likely at other addresses, or that are gone. So when an image starts, a
;;;; second hook clears the published state and the holds, and sets the open
;;;; counters to zero: no native object survives a restart. The image's
;;;; first call starts up again.
;;;;
;;;; UIOP's image hooks run only inside UIOP:DUMP-IMAGE and
;;;; UIOP:RESTORE-IMAGE. The Lisps' own run on every save, including one
;;;; UIOP:DUMP-IMAGE makes (finding 12). SBCL calls SB-EXT:*SAVE-HOOKS* in
;;;; DEINIT (src/code/save.lisp); CCL calls CCL:*SAVE-EXIT-FUNCTIONS* in
;;;; SAVE-APPLICATION (lib/dumplisp.lisp), and the native suite first runs
;;;; on CCL in M4. SBCL calls SB-EXT:*INIT-HOOKS* in REINIT, once the
;;;; libraries are reopened and before the command line is processed
;;;; (src/code/cold-init.lisp), and also after a save that fails once
;;;; DEINIT has run (src/code/save.lisp); CCL calls
;;;; CCL:*RESTORE-LISP-FUNCTIONS* when a saved image starts. ECL doesn't
;;;; save images.

(in-package #:cl-commonmark-gfm.native)

(defun reset-native-state-before-save ()
  "Close both libraries and clear the published state, by
RESET-NATIVE-STATE, before this Lisp saves an image (M2 design §5.3).
While any call holds the state, signal NATIVE-STATE-HELD instead and close
nothing, so the save fails with cmark-gfm still loaded under the parse.
Registered by name, so loading this file again registers it once."
  (reset-native-state))

(defun clear-native-state-on-restart ()
  "Forget the native state an image was saved with, as it starts, before
any call (M2 design §5.3): unpublish the state without closing anything,
drop every hold, and set the open counters to zero. Nothing it names
survived the restart. The startup count and the other monotonic counters
keep their counts.

SBCL also runs it in the process that tried to save, when the save fails
after the save hooks ran: SAVE-LISP-AND-DIE then calls REINIT, which runs
SB-EXT:*INIT-HOOKS* (src/code/save.lisp). The save hook has closed
everything and cleared the state by then, so clearing again is harmless.

Registered by name, so loading this file again registers it once."
  (with-startup-lock
    (setf *published-state* nil
          *holds* '()))
  (clear-open-counts))

#+sbcl
(pushnew 'reset-native-state-before-save sb-ext:*save-hooks*)

#+ccl
(pushnew 'reset-native-state-before-save ccl:*save-exit-functions*)

#+sbcl
(pushnew 'clear-native-state-on-restart sb-ext:*init-hooks*)

#+ccl
(pushnew 'clear-native-state-on-restart ccl:*restore-lisp-functions*)
