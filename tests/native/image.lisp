;;;; Saved images (M2 design §5.3, §8.4; ADR-0017; D12, findings 12 and
;;;; 18): a save hook closes cmark-gfm and clears the published state, so
;;;; an image saved after the native layer started up starts up again on
;;;; its first call; it refuses, and closes nothing, while a call holds the
;;;; state; and a restore hook clears whatever state an image still
;;;; carries when it starts. The saved-image tests run child SBCLs, each
;;;; with a time limit. CCL's arrive in M4 (spec §11), and ECL doesn't save
;;;; images.

(in-package #:cl-commonmark-gfm.native-tests)

;;; The hooks' registration: one function each, by name, on this Lisp's
;;; lists

#+(or sbcl ccl)
(defun save-hooks ()
  "The functions this Lisp calls before it saves an image."
  #+sbcl sb-ext:*save-hooks*
  #+ccl ccl:*save-exit-functions*)

#+(or sbcl ccl)
(defun restore-hooks ()
  "The functions this Lisp calls when a saved image starts."
  #+sbcl sb-ext:*init-hooks*
  #+ccl ccl:*restore-lisp-functions*)

#+(or sbcl ccl)
(define-test the-save-hook-is-registered-once
  (is = 1 (count 'native::reset-native-state-before-save (save-hooks))))

#+(or sbcl ccl)
(define-test the-restore-hook-is-registered-once
  (is = 1 (count 'native::clear-native-state-on-restart (restore-hooks))))

#+(or sbcl ccl)
(define-test loading-the-hooks-again-registers-them-once
  (handler-bind ((warning #'muffle-warning))
    (load (asdf:system-relative-pathname "cl-commonmark-gfm" "src/native/image.lisp")))
  (is = 1 (count 'native::reset-native-state-before-save (save-hooks)))
  (is = 1 (count 'native::clear-native-state-on-restart (restore-hooks))))

;;; Children. A child reports a fact by printing a line: *REPORT-PREFIX*, a
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

(defparameter *child-seconds* 120
  "How long a child may run before it is killed, and its test fails.")

#+sbcl
(defun run-child (core forms &key (seconds *child-seconds*))
  "Run a child SBCL from CORE, which evaluates FORMS, strings, in turn with
--eval: its input the null device, its output and its error output files,
and its environment this process's, CL_SOURCE_REGISTRY, the fasl cache
and, in the container, CL_COMMONMARK_GFM_LIBS among it. A child still
running after SECONDS is killed with SIGKILL, so one that deadlocks fails
its test instead of hanging the suite. Return a plist: :KILLED, whether it
was; :EXIT-CODE, NIL when it was; :REPORTS, CHILD-REPORTS of its output;
:ERRORS, the start of its error output, where SBCL names a condition that
ended it."
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((output (merge-pathnames "output.txt" directory))
            (errors (merge-pathnames "errors.txt" directory))
            (process (uiop:launch-program
                      (list* sb-ext:*runtime-pathname*
                             "--core" (uiop:native-namestring core)
                             "--noinform" "--non-interactive" "--no-sysinit" "--no-userinit"
                             (loop for form in forms
                                   append (list "--eval" form)))
                      :input nil
                      :output output :if-output-exists :supersede
                      :error-output errors :if-error-output-exists :supersede))
            (deadline (+ (get-internal-real-time) (* seconds internal-time-units-per-second))))
       (loop while (and (uiop:process-alive-p process)
                        (< (get-internal-real-time) deadline))
             do (sleep 0.05))
       (let ((killed (uiop:process-alive-p process)))
         (when killed
           (uiop:terminate-process process :urgent t))
         (let ((exit-code (uiop:wait-process process)))
           (list :killed killed
                 :exit-code (if killed nil exit-code)
                 :reports (child-reports (uiop:read-file-string output))
                 :errors (string-head (uiop:read-file-string errors) 2000))))))))

#+sbcl
(defun suite-child-forms (key form)
  "The --eval strings of a child that loads this suite, reports FORM's
value under KEY, and exits at once, abandoning any thread still running.
FORM is a string, read in CL-USER."
  (list "(require :asdf)"
        "(asdf:load-system \"cl-commonmark-gfm/native-tests\")"
        (format nil "(cl-commonmark-gfm.native-tests::report-to-parent ~S ~A)" key form)
        "(sb-ext:exit :code 0 :abort t)"))

(defun startup-holds ()
  "How many calls hold the published state, read under the startup lock,
or NIL when the lock can't be had within 10 seconds."
  (bt2:with-lock-held (native::*startup-lock* :timeout 10)
    (length native::*holds*)))

;;; A saved image (M2 design §8.4). The first child loads /native, renders,
;;; and saves an image while its state is published. The second starts
;;; from that image and renders again.

(defparameter *saved-image-markdown* "~~gone~~ and www.example.com"
  "What each child renders: a strikethrough and an autolink, which only
the extensions the state found can parse.")

(defparameter *saved-image-html*
  (format nil "<p><del>gone</del> and <a href=\"http://www.example.com\">www.example.com</a></p>~%")
  "*SAVED-IMAGE-MARKDOWN* as the pinned CLI renders it, with the GFM flags.")

(defparameter *mapped-form*
  "(with-open-file (maps \"/proc/self/maps\")
     (loop for line = (read-line maps nil)
           while line
           thereis (and (search \"libcmark-gfm\" line) t)))"
  "A form, as a string, that is true when this process maps a file whose
name holds libcmark-gfm: the core library, the extensions or both. Linux
only.")

(defun render-and-report-forms ()
  "The forms, as --eval strings, with which a child reports whether a
state is published and, on Linux, whether cmark-gfm is mapped, then renders
*SAVED-IMAGE-MARKDOWN*, and reports the HTML and the startup count.
CHILD-RENDER and CHILD-REPORT are the saving child's."
  (append
   (list "(child-report :published-at-start (cl-commonmark-gfm.native:native-state-published-p))")
   #+linux (list (format nil "(child-report :mapped-at-start ~A)" *mapped-form*))
   (list (format nil "(child-report :html (child-render ~S))" *saved-image-markdown*)
         "(child-report :startups (cl-commonmark-gfm.native:native-startup-count))")))

#+sbcl
(defun saving-child-forms (image skip-save-hook)
  "The first child's --eval strings: load /native, define CHILD-REPORT and
CHILD-RENDER, render and report, then save an image at IMAGE. With
SKIP-SAVE-HOOK, the save hook is first taken off SB-EXT:*SAVE-HOOKS*, as a
user might skip it from the debugger, so the image carries the published
state and its libraries. The image keeps both functions, so the second
child calls them too. Their names are none that CL-USER inherits: SBCL's
CL-USER uses SB-PROFILE, whose REPORT is locked."
  (append
   (list "(require :asdf)"
         "(asdf:load-system \"cl-commonmark-gfm/native\")"
         (concatenate 'string "(defun child-report (key value) (format t \"~&" *report-prefix*
                      " ~S ~S~%\" key value) (finish-output))")
         (concatenate 'string "(defun child-render (markdown) "
                      "(let ((options (cl-commonmark-gfm.native-core:check-options"
                      " :html 'child-render '()))) "
                      "(cl-commonmark-gfm.native:with-native-document (document markdown options) "
                      "(cl-commonmark-gfm.native:render-html document options))))"))
   (render-and-report-forms)
   (when skip-save-hook
     (list (concatenate 'string "(setf sb-ext:*save-hooks* (remove "
                        "'cl-commonmark-gfm.native::reset-native-state-before-save "
                        "sb-ext:*save-hooks*))")))
   (list "(child-report :published-before-save (cl-commonmark-gfm.native:native-state-published-p))"
         (format nil "(sb-ext:save-lisp-and-die ~S)" (uiop:native-namestring image)))))

#+sbcl
(defun saved-image-run (&key skip-save-hook)
  "Save an image from a child SBCL that started up and rendered, then
start a second child from the image. SKIP-SAVE-HOOK as for
SAVING-CHILD-FORMS. Return a plist: :SAVING and :RESTARTED, each child's
RUN-CHILD plist, and :IMAGE-SAVED, true when the first child left an
image. The image lives in a temporary directory, which is deleted."
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((image (merge-pathnames "saved.core" directory))
            (saving (run-child sb-ext:*core-pathname* (saving-child-forms image skip-save-hook)))
            (image-saved (and (probe-file image) t)))
       (list :saving saving
             :image-saved image-saved
             :restarted (when image-saved
                          (run-child image (render-and-report-forms))))))))

#+sbcl
(define-test a-saved-image-starts-up-again-on-its-first-call
  (destructuring-bind (&key saving image-saved restarted) (saved-image-run)
    (let ((saved (getf saving :reports))
          (started (getf restarted :reports)))
      ;; The saving child: a fresh process starts up, renders, and saves
      ;; while its state is published.
      (is eql 0 (getf saving :exit-code)
          "the saving child exits 0; its error output starts:~%~A" (getf saving :errors))
      (is eql nil (getf saved :published-at-start :unreported)
          "a fresh process has nothing published")
      #+linux
      (is eql nil (getf saved :mapped-at-start :unreported)
          "a fresh process has no cmark-gfm library mapped")
      (is equal *saved-image-html* (getf saved :html :unreported) "the saving child renders")
      (is eql 1 (getf saved :startups :unreported) "the saving child started up once")
      (is eql t (getf saved :published-before-save :unreported)
          "the image is saved while a state is published")
      (true image-saved "the saving child wrote the image")
      ;; The restarted image: nothing published and, since the save hook
      ;; closed both libraries, neither reopened, so its first call starts
      ;; up again, here, and renders with fresh extensions.
      (is eql 0 (getf restarted :exit-code)
          "the restarted child exits 0; its error output starts:~%~A" (getf restarted :errors))
      (is eql nil (getf started :published-at-start :unreported)
          "the restarted image has nothing published")
      #+linux
      (is eql nil (getf started :mapped-at-start :unreported)
          "the restarted image has no cmark-gfm library mapped before its first call")
      (is equal *saved-image-html* (getf started :html :unreported) "the restarted image renders")
      (is eql 2 (getf started :startups :unreported) "the restarted image started up once more"))))

;;; An image saved with the save hook skipped (M2 design §5.3, §8.4). It
;;; carries the published state, and SBCL reopens the libraries it had
;;; loaded, likely at other addresses, so the state's pointers are stale.
;;; The restore hook clears that state as the image starts, so its first
;;; call starts up again.

#+sbcl
(define-test an-image-saved-without-the-save-hook-starts-with-nothing-published
  (destructuring-bind (&key saving image-saved restarted) (saved-image-run :skip-save-hook t)
    (let ((saved (getf saving :reports))
          (started (getf restarted :reports)))
      (is eql 0 (getf saving :exit-code)
          "the saving child exits 0; its error output starts:~%~A" (getf saving :errors))
      (is eql t (getf saved :published-before-save :unreported)
          "the image is saved while a state is published")
      (true image-saved "the saving child wrote the image")
      (is eql 0 (getf restarted :exit-code)
          "the restarted child exits 0; its error output starts:~%~A" (getf restarted :errors))
      #+linux
      (is eql t (getf started :mapped-at-start :unreported)
          "the image reopened the libraries it carried: the save hook didn't run")
      (is eql nil (getf started :published-at-start :unreported)
          "the restarted image has nothing published")
      (is equal *saved-image-html* (getf started :html :unreported) "the restarted image renders")
      (is eql 2 (getf started :startups :unreported) "the restarted image started up once more"))))

;;; Never under a parse (M2 design §5.3; finding 18). SBCL runs its save
;;; hooks before it refuses a save while other threads run
;;; (SAVE-LISP-AND-DIE, then DEINIT, src/code/save.lisp), so the hook must
;;; not close cmark-gfm while any call holds its state: it signals instead,
;;; and the save fails with everything still loaded.

(defun hook-under-a-live-document ()
  "Call the save hook's function inside a live document's scope, and render
the document after. Return a plist: :HOOK, the type of what the hook
signalled, or :RETURNED; :PUBLISHED and :LOADED, whether the state was
still published and both libraries loaded after it; :HTML, the render."
  (let ((paths (state-paths)))
    (call-with-native-document
     "*hi*" '()
     (lambda (document checked-options)
       (list :hook (handler-case (progn (native::reset-native-state-before-save) :returned)
                     (error (condition) (type-of condition)))
             :published (native-state-published-p)
             :loaded (every #'loaded-p paths)
             :html (render-html document checked-options)))
     :entry-point :html)))

(define-test the-save-hook-signals-while-a-document-is-live
  (destructuring-bind (&key hook published loaded html) (hook-under-a-live-document)
    (is eql 'native::native-state-held hook "the hook signalled")
    (true published "the state is still published")
    (true loaded "both libraries are still loaded")
    (is string= (format nil "<p><em>hi</em></p>~%") html "the document still renders"))
  (true (native-state-published-p) "the state is published after the document")
  (true (open-counts-zero-p)))

;;; One save, attempted while a worker provably holds the state: it waits
;;; at a gate inside a live document, which it entered before the save is
;;; tried. SBCL calls the save hook first, so the hook refuses, every time,
;;; before SBCL looks at the other threads. One attempt, since SBCL 2.5.2,
;;; Debian's, failed an internal AVER when saves were refused again and
;;; again while a worker parsed.

(defun held-state-report ()
  "What NATIVE-STATE-HELD prints when one call holds the state: the text
SBCL's refusal carries when the save hook refused."
  (princ-to-string (make-condition 'native::native-state-held :holds 1)))

#+sbcl
(defun save-under-a-hold (image)
  "In a child SBCL: hold the published state in a worker, which waits at a
gate inside a live document, and try once to save an image at IMAGE. Then
open the gate. Return a plist:
- :ARRIVED, whether the worker reached the gate;
- :SAVE, the start of the error the save signalled, :SAVED should it
  return, or :NOT-TRIED when the worker never arrived;
- :NAMES-HOOK and :HELD, whether that error names the save hook and
  carries NATIVE-STATE-HELD's report;
- :PUBLISHED and :LOADED, whether after the save the state was still
  published and both libraries loaded;
- :WORKER, the worker's outcome after the gate opened: (:RETURNED HTML),
  (:SIGNALLED TEXT) or (:TIMED-OUT);
- :EXPECTED, the HTML the same render gives alone;
- :HOLDS and :OPEN, the holds and the open counters left;
- :IMAGE-WRITTEN, whether an image was written."
  (let* ((paths (state-paths))
         (expected (render-html-of *held-markdown* '()))
         (arrival (sb-thread:make-semaphore :name "arrival"))
         (gate (sb-thread:make-semaphore :name "gate"))
         (worker (sb-thread:make-thread
                  (lambda ()
                    (handler-case
                        (list :returned
                              (call-with-native-document
                               *held-markdown* '()
                               (lambda (document checked-options)
                                 (sb-thread:signal-semaphore arrival)
                                 (sb-thread:wait-on-semaphore gate :timeout 60)
                                 (render-html document checked-options))
                               :entry-point :html))
                      (serious-condition (condition)
                        (list :signalled (princ-to-string condition)))))
                  :name "holding worker"))
         (arrived (and (sb-thread:wait-on-semaphore arrival :timeout 60) t))
         (save (if arrived
                   (handler-case (progn (sb-ext:save-lisp-and-die (uiop:native-namestring image))
                                        :saved)
                     (error (condition) (princ-to-string condition)))
                   :not-tried))
         (published (native-state-published-p))
         (loaded (every #'loaded-p paths)))
    (sb-thread:signal-semaphore gate)
    (list :arrived arrived
          :save (if (stringp save) (string-head save 600) save)
          :names-hook (and (stringp save) (search "RESET-NATIVE-STATE-BEFORE-SAVE" save) t)
          :held (and (stringp save) (search (held-state-report) save) t)
          :published published
          :loaded loaded
          :worker (sb-thread:join-thread worker :default '(:timed-out) :timeout 60)
          :expected expected
          :holds (startup-holds)
          :open (native-open-counts)
          :image-written (and (probe-file image) t))))

#+sbcl
(defun save-under-a-hold-run ()
  "Run SAVE-UNDER-A-HOLD in a child that loads this suite, its image path
in a temporary directory, and return the child's RUN-CHILD plist."
  (call-with-temporary-directory
   (lambda (directory)
     (let ((image (uiop:native-namestring (merge-pathnames "held.core" directory))))
       (run-child sb-ext:*core-pathname*
                  (suite-child-forms
                   :save-under-a-hold
                   (format nil "(cl-commonmark-gfm.native-tests::save-under-a-hold ~S)" image)))))))

#+sbcl
(define-test saving-while-a-worker-holds-the-state-fails-and-never-harms-it
  (destructuring-bind (&key killed exit-code reports errors) (save-under-a-hold-run)
    (false killed "the child reported within ~D seconds" *child-seconds*)
    (is eql 0 exit-code "the child exits 0; its error output starts:~%~A" errors)
    (destructuring-bind (&key arrived save names-hook held published loaded worker expected
                           holds open image-written)
        (getf reports :save-under-a-hold)
      (true arrived "the worker held the state, inside a live document, before the save")
      (true names-hook "the save failed in the save hook: ~S" save)
      (true held "the hook signalled NATIVE-STATE-HELD: ~S" save)
      (true published "the state is still published")
      (true loaded "both libraries are still loaded")
      (is eql :returned (first worker) "the worker returned: ~S" worker)
      (true (and (stringp expected) (equal expected (second worker)))
            "the worker rendered as it does alone: ~S" worker)
      (is eql 0 holds "holds left")
      (is equal '(:parsers 0 :roots 0 :buffers 0) open "the child's open counts")
      (false image-written "no image was written"))))
