;;;; The native counters (M2 design §5.4; ADR-0008): how many parsers, roots
;;;; and render buffers are open now, how many parsers and buffers were ever
;;;; created, and how many startups were published. Every native suite ends
;;;; with the open counters at zero; that is its leak check. The monotonic
;;;; counters show a test whether a failure came before cmark created
;;;; anything.
;;;;
;;;; Each count changes in the same function as the cmark call it counts, so
;;;; skipping a free skips its count too, and the open counters catch it.
;;;; Every read and change runs with interrupts deferred (M2 design §5.4,
;;;; finding 21), so an interrupt can't cut a change short.

(in-package #:cl-commonmark-gfm.native)

(defvar *counters-lock* (bt2:make-lock :name "cl-commonmark-gfm native counters")
  "Held around every read and change of the counters below, and nothing
else: no other lock is ever taken while it is held.")

(defvar *open-parsers* 0 "Parsers created and not yet freed.")
(defvar *open-roots* 0 "Finished roots not yet freed.")
(defvar *open-buffers* 0 "Render buffers not yet freed.")
(defvar *created-parsers* 0 "Parsers ever created: never decreases.")
(defvar *created-buffers* 0 "Render buffers ever created: never decreases.")
(defvar *published-startups* 0 "Startups ever published: never decreases.")

(defmacro with-counters-lock (&body body)
  "Run BODY holding *COUNTERS-LOCK*, with interrupts deferred from the wait
for the lock until its release (M2 design §5.4)."
  `(with-interrupts-deferred
     (bt2:with-lock-held (*counters-lock*)
       ,@body)))

(defun note-parser-created ()
  "Count a parser cmark has just created."
  (with-counters-lock
    (incf *open-parsers*)
    (incf *created-parsers*)))

(defun note-parser-freed ()
  "Count a parser just freed."
  (with-counters-lock
    (decf *open-parsers*)))

(defun note-root-created ()
  "Count a root cmark_parser_finish has just returned."
  (with-counters-lock
    (incf *open-roots*)))

(defun note-root-freed ()
  "Count a root just freed."
  (with-counters-lock
    (decf *open-roots*)))

(defun note-buffer-created ()
  "Count a render buffer cmark has just returned."
  (with-counters-lock
    (incf *open-buffers*)
    (incf *created-buffers*)))

(defun note-buffer-freed ()
  "Count a render buffer just freed."
  (with-counters-lock
    (decf *open-buffers*)))

(defun note-startup-published ()
  "Count a startup whose state was just published."
  (with-counters-lock
    (incf *published-startups*)))

(defun clear-open-counts ()
  "Set the open counters to zero, for an image that has just started: no
parser, root or buffer survives a restart (M2 design §5.3). SBCL also runs
the restore hook that calls this in the process that tried to save, when
the save fails after the save hooks ran (REINIT, src/code/save.lisp). The
save hook has closed everything by then, so clearing again is harmless.
The monotonic counters keep their counts."
  (with-counters-lock
    (setf *open-parsers* 0
          *open-roots* 0
          *open-buffers* 0)))

(defun native-open-counts ()
  "The open native handles, as the plist (:PARSERS n :ROOTS n :BUFFERS n).
All three are zero whenever no native document is live and no render is
under way."
  (with-counters-lock
    (list :parsers *open-parsers* :roots *open-roots* :buffers *open-buffers*)))

(defun native-created-counts ()
  "The parsers and render buffers ever created, as the plist (:PARSERS n
:BUFFERS n). Both only ever grow."
  (with-counters-lock
    (list :parsers *created-parsers* :buffers *created-buffers*)))

(defun native-startup-count ()
  "The number of startups ever published. It only ever grows."
  (with-counters-lock
    *published-startups*))
