;;;; Saved images. An image keeps the libraries its process loaded, and the
;;;; published state's pointers into them. CFFI loads a library on SBCL with
;;;; SB-ALIEN:LOAD-SHARED-OBJECT, without :DONT-SAVE, so a saved image
;;;; would reopen cmark-gfm when it starts, at the path the saving machine
;;;; used, and its state would point into a process that is gone. So before
;;;; an image is saved, a hook resets the native state: both libraries
;;;; close, and nothing stays published. The image's first call starts up
;;;; again, on whatever machine it runs.
;;;;
;;;; Never under a parse. SBCL runs its save hooks first in DEINIT, and only
;;;; then refuses a save while other threads run
;;;; (SAVE-WITH-MULTIPLE-THREADS-ERROR, SBCL's src/code/save.lisp). A hook
;;;; that closed cmark there would close it under those threads' parses. So
;;;; while any call holds the state (WITH-NATIVE-STATE), the reset signals
;;;; NATIVE-STATE-HELD and closes nothing: SBCL's CALL-HOOKS reports that
;;;; as an error, and the save fails before anything is unloaded.
;;;;
;;;; CCL saves differently: before it calls its save hooks, it kills every
;;;; other thread, by an interrupt that unwinds it, and waits up to 50 ms for
;;;; each to signal its end (PREPARE-TO-QUIT, CCL 1.13's
;;;; level-1/l1-readloop.lisp). A thread that holds the state where an
;;;; interrupt lands ends its hold as it unwinds, before CCL signals the
;;;; thread's end, but the thread may still be finishing when the hook runs
;;;; (PROCESS-INITIAL-FORM-EXITED, level-1/l1-processes.lisp). One inside a
;;;; cmark call defers the interrupt (interrupts.lisp): if it is still there,
;;;; the hook refuses as on SBCL, and the save fails. Without that refusal,
;;;; CCL itself would crash there: it saves past a thread it couldn't stop,
;;;; and dies of SIGSEGV with the image cut short.
;;;;
;;;; On CCL, closing isn't enough: CCL keeps a record of each library it
;;;; opened, and a saved image reopens every library it still lists, by
;;;; soname, as it starts. So on CCL every close also makes CCL forget the
;;;; libraries it closed, unless other code in the process still holds them
;;;; open (CLOSE-LIBRARIES, startup.lisp). But CCL records a library it maps
;;;; again whenever it opens another, and it still maps the pair it called
;;;; into, so after its reset the save hook also makes CCL forget whatever
;;;; it lists again of the recorded pair that nothing holds open
;;;; (FORGET-RECORDED-PAIR), whether or not anything was published.
;;;;
;;;; A restore hook too. A save can still go ahead without the save hook,
;;;; as when a user skips it from the debugger. The image then carries the
;;;; published state, whose pointers lead into libraries that SBCL reopens,
;;;; likely at other addresses, or that are gone. So when an image starts, a
;;;; second hook clears the published state and the holds, and sets the open
;;;; counters to zero: no native object survives a restart. The image's
;;;; first call starts up again. On CCL, it also forgets the pair record:
;;;; the record names the pair the saving process had called into, and the
;;;; image's own process has called into nothing yet. Unless CCL has
;;;; already reopened that pair, by soname, as the image started, as it
;;;; does a record other code held open across the save, or any record when
;;;; the save hook was skipped: the image then maps the pair, and CFFI's
;;;; lookups by name land in it, so the hook records the files CCL reopened,
;;;; and the image refuses another pair. When CCL reopened only one of the
;;;; two, the hook can't record the pair, and clears the record: that image
;;;; could still accept another pair, whose calls could then land in the
;;;; libraries that image maps.
;;;;
;;;; UIOP's image hooks run only inside UIOP:DUMP-IMAGE and
;;;; UIOP:RESTORE-IMAGE. The Lisps' own run on every save, including one
;;;; UIOP:DUMP-IMAGE makes, so the hooks below are the Lisps' own. SBCL
;;;; calls SB-EXT:*SAVE-HOOKS* in DEINIT (SBCL's src/code/save.lisp); CCL
;;;; calls CCL:*SAVE-EXIT-FUNCTIONS* in SAVE-IMAGE, in its initial thread,
;;;; once SAVE-APPLICATION has asked that thread to save (lib/dumplisp.lisp).
;;;; SBCL calls SB-EXT:*INIT-HOOKS* in REINIT, once the libraries are
;;;; reopened and before the command line is processed (SBCL's
;;;; src/code/cold-init.lisp), and also after a save that fails once DEINIT
;;;; has run (SBCL's src/code/save.lisp); CCL calls
;;;; CCL:*RESTORE-LISP-FUNCTIONS* when a saved image starts, once it has
;;;; reopened the libraries on its list (RESTORE-LISP-POINTERS,
;;;; lib/dumplisp.lisp). ECL doesn't save images.

(in-package #:cl-commonmark-gfm.native)

(defun reset-native-state-before-save ()
  "Close both libraries and clear the published state, by
RESET-NATIVE-STATE, before this Lisp saves an image. On CCL, closing also
makes CCL forget both (CLOSE-LIBRARIES), and the hook then makes CCL
forget any record it lists again of the recorded pair's libraries
(FORGET-RECORDED-PAIR), so the image reopens neither, unless other code in
the process still holds it open: CCL forgets only a record nothing holds
open. While any call holds the state, signal NATIVE-STATE-HELD instead,
and close and forget nothing, so the save fails with cmark-gfm still
loaded under the parse. Registered by name, so loading this file again
registers it once."
  (reset-native-state)
  #+ccl
  (forget-recorded-pair))

(defun clear-native-state-on-restart ()
  "Forget the native state an image was saved with, as it starts, before
any call: unpublish the state without closing anything, drop every hold,
and set the open counters to zero. Nothing it names survived the restart.
The startup count and the other monotonic counters keep their counts.

On CCL, also forget the pair record, unless CCL has already reopened the
pair as the image started: then record the files it reopened instead
(REOPENED-PAIR-RECORD), so the image refuses another pair.

SBCL also runs it in the process that tried to save, when the save fails
after the save hooks ran: SAVE-LISP-AND-DIE then calls REINIT, which runs
SB-EXT:*INIT-HOOKS* (SBCL's src/code/save.lisp). The save hook has closed
everything and cleared the state by then, so clearing again is harmless.

Registered by name, so loading this file again registers it once."
  (with-startup-lock
    (setf *published-state* nil
          *holds* '()
          *loaded-pair* #+ccl (reopened-pair-record *loaded-pair*) #-ccl nil))
  (clear-open-counts))

#+sbcl
(pushnew 'reset-native-state-before-save sb-ext:*save-hooks*)

#+ccl
(pushnew 'reset-native-state-before-save ccl:*save-exit-functions*)

#+sbcl
(pushnew 'clear-native-state-on-restart sb-ext:*init-hooks*)

#+ccl
(pushnew 'clear-native-state-on-restart ccl:*restore-lisp-functions*)
