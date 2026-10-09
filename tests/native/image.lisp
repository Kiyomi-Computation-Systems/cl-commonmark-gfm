;;;; Saved images: a save hook closes cmark-gfm and clears the published
;;;; state, so an image saved after the native layer started up starts up
;;;; again on its first call; it refuses, and closes nothing, while a call
;;;; holds the state; and a restore hook clears whatever state an image
;;;; still carries when it starts. The hooks are the Lisps' own, which run
;;;; on every save, since UIOP's run only inside UIOP:DUMP-IMAGE and
;;;; UIOP:RESTORE-IMAGE. The saved-image tests run children of SBCL and
;;;; CCL, each with a time limit (children.lisp). ECL doesn't save images.

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

(defun startup-holds ()
  "How many calls hold the published state, read under the startup lock,
or NIL when the lock can't be had within 10 seconds. Polls, by CALL-WITH-
LOCK-WITHIN, since CCL's bordeaux-threads doesn't implement WITH-LOCK-
HELD's :TIMEOUT."
  (multiple-value-bind (holds got-it)
      (call-with-lock-within native::*startup-lock* 10
                             (lambda () (length native::*holds*)))
    (and got-it holds)))

(defun file-octets (path)
  "The length in octets of the file at PATH, or NIL when there is none."
  (with-open-file (stream path :element-type '(unsigned-byte 8) :if-does-not-exist nil)
    (and stream (file-length stream))))

;;; A saved image. The first child loads /native, renders, and saves an
;;; image while its state is published. The second starts from that image
;;; and renders again. On CCL the image's process must also start with no
;;; pair recorded: the record names the pair the saving process called
;;; into, and the image's own process has called into nothing yet.

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
  "The forms, as strings, with which a child reports whether a state is
published, on Linux whether cmark-gfm is mapped, and the pair CCL recorded
(NATIVE::LOADED-PAIR, always NIL on SBCL), then renders
*SAVED-IMAGE-MARKDOWN*, and reports the HTML and the startup count.
CHILD-RENDER and CHILD-REPORT are the saving child's."
  (append
   (list "(child-report :published-at-start (cl-commonmark-gfm.native:native-state-published-p))")
   #+linux (list (format nil "(child-report :mapped-at-start ~A)" *mapped-form*))
   (list "(child-report :pair-at-start (cl-commonmark-gfm.native::loaded-pair))"
         (format nil "(child-report :html (child-render ~S))" *saved-image-markdown*)
         "(child-report :startups (cl-commonmark-gfm.native:native-startup-count))")))

#+(or sbcl ccl)
(defun saving-child-forms (image skip-save-hook)
  "The first child's forms, as strings: load /native, define CHILD-REPORT
and CHILD-RENDER, render and report, then save an image at IMAGE, with
SB-EXT:SAVE-LISP-AND-DIE on SBCL and CCL:SAVE-APPLICATION on CCL. With
SKIP-SAVE-HOOK, the save hook is first taken off SB-EXT:*SAVE-HOOKS* or
CCL:*SAVE-EXIT-FUNCTIONS*, as a user might skip it from the debugger, so
the image carries the published state and its libraries. Just before the
save, the child reports whether a state is published and the pair CCL
recorded. The image keeps both functions, so the second child calls them
too. Their names are none that CL-USER inherits: SBCL's CL-USER uses
SB-PROFILE, whose REPORT is locked."
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
     (list #+sbcl (concatenate 'string "(setf sb-ext:*save-hooks* (remove "
                               "'cl-commonmark-gfm.native::reset-native-state-before-save "
                               "sb-ext:*save-hooks*))")
           #+ccl (concatenate 'string "(setf ccl:*save-exit-functions* (remove "
                              "'cl-commonmark-gfm.native::reset-native-state-before-save "
                              "ccl:*save-exit-functions*))")))
   (list "(child-report :published-before-save (cl-commonmark-gfm.native:native-state-published-p))"
         "(child-report :pair-before-save (cl-commonmark-gfm.native::loaded-pair))"
         #+sbcl (format nil "(sb-ext:save-lisp-and-die ~S)" (uiop:native-namestring image))
         #+ccl (format nil "(ccl:save-application ~S)" (uiop:native-namestring image)))))

#+(or sbcl ccl)
(defun saved-image-run (&key skip-save-hook)
  "Save an image from a child of this Lisp that started up and rendered,
then start a second child from the image. SKIP-SAVE-HOOK as for
SAVING-CHILD-FORMS. Return a plist: :SAVING and :RESTARTED, each child's
RUN-CHILD plist, and :IMAGE-SAVED, true when the first child left an
image. The image lives in a temporary directory, which is deleted."
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((image (merge-pathnames "saved.core" directory))
            (saving (run-child (saving-child-forms image skip-save-hook)))
            (image-saved (and (probe-file image) t)))
       (list :saving saving
             :image-saved image-saved
             :restarted (when image-saved
                          (run-child (render-and-report-forms) :image image)))))))

#+(or sbcl ccl)
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
      (is eql nil (getf saved :pair-at-start :unreported) "a fresh process has no pair recorded")
      (is equal *saved-image-html* (getf saved :html :unreported) "the saving child renders")
      (is eql 1 (getf saved :startups :unreported) "the saving child started up once")
      (is eql t (getf saved :published-before-save :unreported)
          "the image is saved while a state is published")
      ;; On CCL the image carries the saving process's pair record, which
      ;; the restore hook must forget; SBCL keeps none.
      #+ccl
      (true (getf saved :pair-before-save) "the image is saved with a pair recorded")
      #-ccl
      (is eql nil (getf saved :pair-before-save :unreported) "SBCL records no pair")
      (true image-saved "the saving child wrote the image")
      ;; The restarted image: nothing published and, since the save hook
      ;; closed both libraries and, on CCL, made CCL forget them, neither
      ;; reopened, so its first call starts up again, here, and renders
      ;; with fresh extensions.
      (is eql 0 (getf restarted :exit-code)
          "the restarted child exits 0; its error output starts:~%~A" (getf restarted :errors))
      (is eql nil (getf started :published-at-start :unreported)
          "the restarted image has nothing published")
      #+linux
      (is eql nil (getf started :mapped-at-start :unreported)
          "the restarted image has no cmark-gfm library mapped before its first call")
      (is eql nil (getf started :pair-at-start :unreported)
          "the restarted image has no pair recorded before its first call")
      (is equal *saved-image-html* (getf started :html :unreported) "the restarted image renders")
      (is eql 2 (getf started :startups :unreported) "the restarted image started up once more"))))

;;; An image saved with the save hook skipped. It carries the published
;;; state, and reopens the libraries it had loaded: SBCL at the paths it
;;; loaded them from, CCL by their sonames, from wherever the loader finds
;;; them (REFRESH-EXTERNAL-ENTRYPOINTS, CCL 1.13's
;;; level-0/l0-cfm-support.lisp): the container's library path and Debian's
;;; multiarch directory both hold them. Likely at other addresses, so the
;;; state's pointers are stale. The restore hook clears that state as the
;;; image starts, so its first call starts up again. On CCL it records the
;;; pair CCL reopened instead of clearing the record.

#+(or sbcl ccl)
(define-test an-image-saved-without-the-save-hook-starts-with-nothing-published
  (destructuring-bind (&key saving image-saved restarted) (saved-image-run :skip-save-hook t)
    (let ((saved (getf saving :reports))
          (started (getf restarted :reports)))
      (is eql 0 (getf saving :exit-code)
          "the saving child exits 0; its error output starts:~%~A" (getf saving :errors))
      (is eql t (getf saved :published-before-save :unreported)
          "the image is saved while a state is published")
      #+ccl
      (true (getf saved :pair-before-save) "the image is saved with a pair recorded")
      (true image-saved "the saving child wrote the image")
      (is eql 0 (getf restarted :exit-code)
          "the restarted child exits 0; its error output starts:~%~A" (getf restarted :errors))
      #+linux
      (is eql t (getf started :mapped-at-start :unreported)
          "the image reopened the libraries it carried: the save hook didn't run")
      (is eql nil (getf started :published-at-start :unreported)
          "the restarted image has nothing published")
      ;; On CCL the image reopened the pair it carried, so the restore hook
      ;; recorded it (AN-IMAGE-SAVED-WITHOUT-THE-SAVE-HOOK-RECORDS-THE-PAIR-
      ;; CCL-REOPENED checks which files, and the refusal).
      #+ccl
      (true (getf started :pair-at-start) "the restarted image recorded the pair CCL reopened")
      #-ccl
      (is eql nil (getf started :pair-at-start :unreported)
          "the restarted image has no pair recorded before its first call")
      (is equal *saved-image-html* (getf started :html :unreported) "the restarted image renders")
      (is eql 2 (getf started :startups :unreported) "the restarted image started up once more"))))

;;; CCL's records of the libraries it has opened: the checks below find
;;; them by soname, which a copy of the pair shares: CCL reuses a listed
;;; record of the same soname (SHLIB-FROM-MAP-ENTRY, CCL 1.13's
;;; level-0/l0-cfm-support.lisp).

#+ccl
(defun state-records (state)
  "CCL's records of STATE's two libraries, core then extensions: the
CCL:SHLIB objects CFFI keeps as their handles (CFFI's src/cffi-openmcl.lisp)."
  (list (cffi::foreign-library-handle (native::state-core-library state))
        (cffi::foreign-library-handle (native::state-extensions-library state))))

#+ccl
(defun record-soname (record)
  "The soname of RECORD, a CCL:SHLIB. CCL's accessor is a macro."
  (ccl::shlib.soname record))

#+ccl
(defun record-open-count (record)
  "How many opens of RECORD, a CCL:SHLIB, CCL counts: one for each
CCL:OPEN-SHARED-LIBRARY of its library not yet closed. CCL's accessor is a
macro."
  (ccl::shlib.opencount record))

#+ccl
(defun listed-records-named (sonames)
  "The records on CCL's list of the shared libraries it has opened whose
sonames are among SONAMES."
  (remove-if-not (lambda (record) (member (record-soname record) sonames :test #'equal))
                 ccl::*shared-libraries*))

;;; An image saved after a failed startup. Step 4 read cmark's version
;;; string, a call into the core, then failed: so on CCL, which never
;;; unloads a library it has called into, the core stays mapped, and the
;;; pair stays recorded, while nothing is published, and the save hook has
;;; nothing to close. The image still mustn't reopen the pair: on CCL, the
;;; failed startup's own close made CCL forget both libraries
;;; (CLOSE-LIBRARIES). SBCL unloads both on close.

#+(or sbcl ccl)
(defun save-after-a-failed-startup (image)
  "In a child that loaded this suite: start up with NATIVE::%VERSION-NUMBER
reporting another version, so step 4 fails after reading cmark's version
string, a call into the core; report what the failure left; then save an
image at IMAGE, which doesn't return. Reports (REPORT-TO-PARENT): :FAILED,
the type of what startup signalled; :PUBLISHED; :LOADED, whether CFFI
lists either library; :PAIR, CCL's pair record; and on Linux :MAPPED,
whether cmark-gfm is mapped."
  (let ((failure (with-redefined ((native::%version-number (constantly #x001D000E)))
                   (startup-failure))))
    (report-to-parent :failed (type-of failure))
    (report-to-parent :published (native-state-published-p))
    (report-to-parent :loaded (and (typep failure 'native-abi-mismatch)
                                   (some #'loaded-p (condition-paths failure))
                                   t))
    (report-to-parent :pair (native::loaded-pair))
    #+linux
    (report-to-parent :mapped (and (mapped-cmark-libraries) t))
    #+sbcl (sb-ext:save-lisp-and-die image)
    #+ccl (ccl:save-application image)))

#+(or sbcl ccl)
(define-test an-image-saved-after-a-failed-startup-starts-with-nothing-mapped
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((image (uiop:native-namestring (merge-pathnames "failed.image" directory)))
            (saving (run-child (suite-child-forms
                                :save-returned
                                (format nil "(cl-commonmark-gfm.native-tests::~
                                             save-after-a-failed-startup ~S)"
                                        image))))
            (octets (file-octets image))
            (restarted (when (and octets (plusp octets))
                         (run-child (restarted-image-forms) :image image))))
       (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) saving
         (false killed "the saving child ended within ~D seconds" *child-seconds*)
         (is eql 0 exit-code "the saving child exits 0; its error output starts:~%~A" errors)
         (is eql 'native-abi-mismatch (getf reports :failed :unreported) "step 4 failed")
         (is eql nil (getf reports :published :unreported) "nothing was published")
         (is eql nil (getf reports :loaded :unreported) "CFFI lists neither library")
         #+ccl
         (true (getf reports :pair) "CCL kept the pair recorded")
         #+(and ccl linux)
         (is eql t (getf reports :mapped :unreported) "CCL still maps the core it called into")
         #+(and sbcl linux)
         (is eql nil (getf reports :mapped :unreported) "SBCL unloaded both"))
       (true (and octets (plusp octets)) "the image was written: ~S octets" octets)
       (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) restarted
         (false killed "the restarted child ended within ~D seconds" *child-seconds*)
         (is eql 0 exit-code "the restarted child exits 0; its error output starts:~%~A" errors)
         (destructuring-bind (&key published mapped pair holds open html startups-added)
             (getf reports :restarted)
           (false published "the image has nothing published")
           #+linux
           (false mapped "the image has no cmark-gfm library mapped before its first call")
           (false pair "the image has no pair recorded before its first call")
           (is eql 0 holds "the image has no hold")
           (is equal '(:parsers 0 :roots 0 :buffers 0) open "the image's open counts")
           (is equal *saved-image-html* html "the image's first ordinary call renders")
           (is eql 1 startups-added "the image's first call started up")))))))

;;; An image saved after the core is loaded again outside a startup. On CCL,
;;; the reset made CCL forget both libraries (CLOSE-LIBRARIES), but opening
;;; any library makes CCL record again every library it maps and doesn't
;;; list (OPEN-SHARED-LIBRARY-INTERNAL, CCL 1.13's
;;; level-0/l0-cfm-support.lisp), and it still maps the pair it called into.
;;; Here a CFFI load and close of the core brings both records back: the
;;; core's, emptied by the close but listed, and the extensions'. Nothing is
;;; published, so the save hook's reset closes nothing; the hook must still
;;; make CCL forget the recorded pair's libraries. On SBCL, the same steps
;;; leave nothing behind.

#+(or sbcl ccl)
(defun save-after-the-core-is-loaded-again (image)
  "In a child that loaded this suite: start up, reset, then load the
core's library through CFFI and close it again, as other code in the
process might; report what that left; then save an image at IMAGE, which
doesn't return. Reports (REPORT-TO-PARENT): :PUBLISHED; :PAIR, CCL's pair
record; on CCL :RELISTED, (:CORE C :EXTENSIONS E), whether CCL lists a
record of each library's soname again; and on Linux :MAPPED, whether
cmark-gfm is mapped."
  (let* ((paths (state-paths))
         #+ccl (sonames (mapcar #'record-soname (state-records (native-state)))))
    (reset-native-state)
    (cffi:close-foreign-library
     (cffi:load-foreign-library (native::library-designator (first paths))))
    (report-to-parent :published (native-state-published-p))
    (report-to-parent :pair (native::loaded-pair))
    #+ccl
    (report-to-parent :relisted
                      (list :core (and (listed-records-named (list (first sonames))) t)
                            :extensions (and (listed-records-named (list (second sonames))) t)))
    #+linux
    (report-to-parent :mapped (and (mapped-cmark-libraries) t))
    #+sbcl (sb-ext:save-lisp-and-die image)
    #+ccl (ccl:save-application image)))

#+(or sbcl ccl)
(define-test an-image-saved-after-the-core-is-loaded-again-starts-with-nothing-mapped
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((image (uiop:native-namestring (merge-pathnames "again.image" directory)))
            (saving (run-child (suite-child-forms
                                :save-returned
                                (format nil "(cl-commonmark-gfm.native-tests::~
                                             save-after-the-core-is-loaded-again ~S)"
                                        image))))
            (octets (file-octets image))
            (restarted (when (and octets (plusp octets))
                         (run-child (restarted-image-forms) :image image))))
       (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) saving
         (false killed "the saving child ended within ~D seconds" *child-seconds*)
         (is eql 0 exit-code "the saving child exits 0; its error output starts:~%~A" errors)
         (is eql nil (getf reports :published :unreported) "nothing was published")
         #+ccl
         (true (getf reports :pair) "CCL kept the pair recorded")
         #+ccl
         (is equal '(:core t :extensions t) (getf reports :relisted :unreported)
             "the control: CCL lists both libraries again")
         #+(and ccl linux)
         (is eql t (getf reports :mapped :unreported) "CCL still maps the pair it called into")
         #+sbcl
         (is eql nil (getf reports :pair :unreported) "SBCL records no pair")
         #+(and sbcl linux)
         (is eql nil (getf reports :mapped :unreported) "SBCL unloaded both"))
       (true (and octets (plusp octets)) "the image was written: ~S octets" octets)
       (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) restarted
         (false killed "the restarted child ended within ~D seconds" *child-seconds*)
         (is eql 0 exit-code "the restarted child exits 0; its error output starts:~%~A" errors)
         (destructuring-bind (&key published mapped pair holds open html startups-added)
             (getf reports :restarted)
           (false published "the image has nothing published")
           #+linux
           (false mapped "the image has no cmark-gfm library mapped before its first call")
           (false pair "the image has no pair recorded before its first call")
           (is eql 0 holds "the image has no hold")
           (is equal '(:parsers 0 :roots 0 :buffers 0) open "the image's open counts")
           (is equal *saved-image-html* html "the image's first ordinary call renders")
           (is eql 1 startups-added "the image's first call started up")))))))

;;; An image saved while other code holds the pair open. CCL keeps one
;;; record of a library, however many times it is opened, and counts the
;;; opens not yet closed: a user's own CFFI load of the pair and startup's
;;; load of the same files share both records (CCL 1.13's
;;; OPEN-SHARED-LIBRARY-INTERNAL, level-0/l0-cfm-support.lisp). Startup's
;;; close leaves the user's opens counted, so CCL must forget neither
;;; record, at the close or in the save hook: the user's code still holds
;;; the pair, and the image must reopen it as CCL does any library still
;;; open. CCL forgets only a record nothing holds open, its open count 0.
;;;
;;; Such an image starts with the pair mapped, and CFFI's lookups by name
;;; land in it, so it must refuse another pair, as any CCL process does: the
;;; restore hook records the files CCL reopened. The image's child names a
;;; copy of the pair at another path first.

#+ccl
(defun check-the-image-kept-the-reopened-pair (restarted copies)
  "Assert what RESTARTED, the RUN-CHILD plist of a child started from an
image whose pair CCL reopened as it started, reported by
RESTARTED-IMAGE-FACTS given COPIES, a copy of the pair at another path:
before any call, nothing published, and the files CCL reopened mapped and
recorded as the pair; naming COPIES first refused, leaving nothing loaded
or published and the record as it was; then the first ordinary call
starting up and rendering."
  (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) restarted
    (false killed "the restarted child ended within ~D seconds" *child-seconds*)
    (is eql 0 exit-code "the restarted child exits 0; its error output starts:~%~A" errors)
    (destructuring-bind (&key published mapped pair holds open ((:copies refusal)) html
                           startups-added)
        (getf reports :restarted)
      (false published "the image has nothing published")
      #+linux
      (true mapped "CCL reopened the pair as the image started: ~S" mapped)
      #+linux
      (is equal mapped (sorted-paths pair) "the image recorded the files CCL reopened")
      #-linux
      (true pair "the image recorded the pair CCL reopened")
      (is eql 0 holds "the image has no hold")
      (is equal '(:parsers 0 :roots 0 :buffers 0) open "the image's open counts")
      (destructuring-bind (&key signalled datum reason ((:pair after)) loaded
                             ((:published published-after)))
          refusal
        (is eql 'native-initialization-error signalled "naming another pair first: ~S" refusal)
        (is equal (mapcar #'native-truename copies) datum "the datum: the copies' truenames")
        (true (and (stringp reason) pair (search (first pair) reason))
              "the reason names the recorded core: ~S" reason)
        (is equal pair after "the record is as it was")
        (false loaded "neither copy is left loaded")
        (false published-after "the refusal publishes nothing"))
      (is equal *saved-image-html* html "the image's first ordinary call renders")
      (is eql 1 startups-added "the image's first ordinary call started up"))))

#+ccl
(defun save-while-other-code-holds-the-pair (image core extensions)
  "In a child CCL that loaded this suite: load CORE and EXTENSIONS, the
pair's paths, through CFFI, as a user's own code might, and keep both open;
start up, which loads the same files, then reset; report what that left;
then save an image at IMAGE, which doesn't return. Reports
(REPORT-TO-PARENT): :STARTED, whether startup gave a state; :PUBLISHED,
whether one is published after the reset; :LISTED, (:CORE C :EXTENSIONS E),
whether CCL still lists the record of each library the user holds; and
:OPEN-COUNTS, those records' open counts."
  (let* ((libraries (list (cffi:load-foreign-library (native::library-designator core))
                          (cffi:load-foreign-library (native::library-designator extensions))))
         (records (mapcar #'cffi::foreign-library-handle libraries)))
    (report-to-parent :started (native::native-state-p (native-state)))
    (reset-native-state)
    (report-to-parent :published (native-state-published-p))
    (report-to-parent :listed
                      (list :core (and (member (first records) ccl::*shared-libraries*) t)
                            :extensions (and (member (second records) ccl::*shared-libraries*) t)))
    (report-to-parent :open-counts (mapcar #'record-open-count records))
    (ccl:save-application image)))

#+ccl
(define-test an-image-saved-while-other-code-holds-the-pair-reopens-it-and-starts-up
  (call-with-library-copies
   (lambda (core-copy extensions-copy)
     (destructuring-bind (&key saving image-octets restarted)
         (let ((paths (state-paths)))
           (saving-and-restarted-children
            (lambda (image)
              (format nil "(cl-commonmark-gfm.native-tests::~
                           save-while-other-code-holds-the-pair ~S ~S ~S)"
                      image (first paths) (second paths)))
            :copies (list core-copy extensions-copy)))
       (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) saving
         (false killed "the saving child ended within ~D seconds" *child-seconds*)
         (is eql 0 exit-code "the saving child exits 0; its error output starts:~%~A" errors)
         (is eql t (getf reports :started :unreported)
             "startup loaded the pair the user's code holds open")
         (is eql nil (getf reports :published :unreported) "the reset unpublished the state")
         (is equal '(:core t :extensions t) (getf reports :listed :unreported)
             "after the reset, CCL still lists both records the user's code holds open")
         (is equal '(1 1) (getf reports :open-counts :unreported)
             "the records' open counts: the user's opens alone"))
       (true (and image-octets (plusp image-octets)) "the image was written: ~S octets"
             image-octets)
       (check-the-image-kept-the-reopened-pair restarted (list core-copy extensions-copy))))))

;;; An image saved with the save hook skipped: on CCL it reopens, by
;;; soname, the pair it carried, as it starts, so the restore hook records
;;; the files CCL reopened, and the image refuses another pair.

#+ccl
(defun save-without-the-save-hook (image)
  "In a child CCL that loaded this suite: start up, take the library's save
hook off CCL:*SAVE-EXIT-FUNCTIONS*, as a user might skip it from the
debugger, and save an image at IMAGE, which doesn't return. Reports
(REPORT-TO-PARENT) :PUBLISHED, whether a state is published as the save is
asked for."
  (native-state)
  (setf ccl:*save-exit-functions*
        (remove 'native::reset-native-state-before-save ccl:*save-exit-functions*))
  (report-to-parent :published (native-state-published-p))
  (ccl:save-application image))

#+ccl
(define-test an-image-saved-without-the-save-hook-records-the-pair-ccl-reopened
  (call-with-library-copies
   (lambda (core-copy extensions-copy)
     (destructuring-bind (&key saving image-octets restarted)
         (saving-and-restarted-children
          (lambda (image)
            (format nil "(cl-commonmark-gfm.native-tests::save-without-the-save-hook ~S)" image))
          :copies (list core-copy extensions-copy))
       (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) saving
         (false killed "the saving child ended within ~D seconds" *child-seconds*)
         (is eql 0 exit-code "the saving child exits 0; its error output starts:~%~A" errors)
         (is eql t (getf reports :published :unreported)
             "the image is saved while a state is published"))
       (true (and image-octets (plusp image-octets)) "the image was written: ~S octets"
             image-octets)
       (check-the-image-kept-the-reopened-pair restarted (list core-copy extensions-copy))))))

;;; Never under a parse. SBCL runs its save hooks before it refuses a save
;;; while other threads run (SAVE-LISP-AND-DIE, then DEINIT,
;;; src/code/save.lisp), so the hook must not close cmark-gfm while any call
;;; holds its state: it signals instead, and the save fails with everything
;;; still loaded.

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

(defun held-state-report ()
  "What NATIVE-STATE-HELD prints when one call holds the state: the text a
save the save hook refused carries."
  (princ-to-string (make-condition 'native::native-state-held :holds 1)))

;;; SBCL: one save, attempted while a worker provably holds the state: it
;;; waits at a gate inside a live document, which it entered before the
;;; save is tried. SBCL calls the save hook first, so the hook refuses,
;;; every time, before SBCL looks at the other threads. One attempt, since
;;; SBCL 2.5.2, Debian's, can fail an internal AVER when saves are refused
;;; again and again while a worker parses.

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
  (:SIGNALLED TEXT), or (:TIMED-OUT) when it hasn't ended within 60
  seconds (JOIN-WITHIN);
- :EXPECTED, the HTML the same render gives alone;
- :HOLDS and :OPEN, the holds and the open counters left;
- :IMAGE-WRITTEN, whether an image was written."
  (let* ((paths (state-paths))
         (expected (render-html-of *held-markdown* '()))
         (arrival (bt2:make-semaphore :name "arrival"))
         (gate (bt2:make-semaphore :name "gate"))
         (worker (make-test-thread
                  (lambda ()
                    (handler-case
                        (list :returned
                              (call-with-native-document
                               *held-markdown* '()
                               (lambda (document checked-options)
                                 (bt2:signal-semaphore arrival)
                                 (bt2:wait-on-semaphore gate :timeout 60)
                                 (render-html document checked-options))
                               :entry-point :html))
                      (serious-condition (condition)
                        (list :signalled (princ-to-string condition)))))
                  :name "holding worker"))
         (arrived (and (bt2:wait-on-semaphore arrival :timeout 60) t))
         (save (if arrived
                   (handler-case (progn (sb-ext:save-lisp-and-die (uiop:native-namestring image))
                                        :saved)
                     (error (condition) (princ-to-string condition)))
                   :not-tried))
         (published (native-state-published-p))
         (loaded (every #'loaded-p paths)))
    (bt2:signal-semaphore gate)
    (list :arrived arrived
          :save (if (stringp save) (string-head save 600) save)
          :names-hook (and (stringp save) (search "RESET-NATIVE-STATE-BEFORE-SAVE" save) t)
          :held (and (stringp save) (search (held-state-report) save) t)
          :published published
          :loaded loaded
          :worker (let ((outcome (join-within worker 60)))
                    (if (eql outcome :timed-out) '(:timed-out) outcome))
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
       (run-child (suite-child-forms
                   :save-under-a-hold
                   (format nil "(cl-commonmark-gfm.native-tests::save-under-a-hold ~S)" image)))))))

#+sbcl
(define-test saving-while-a-worker-holds-the-state-fails-and-never-harms-it
  (destructuring-bind (&key killed exit-code reports errors &allow-other-keys)
      (save-under-a-hold-run)
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

;;; CCL saves differently. CCL:SAVE-APPLICATION, called from any thread but
;;; the initial one, as a child's forms are, kills the thread that called
;;; it, and asks the initial thread to save (CCL 1.13's lib/dumplisp.lisp).
;;; That thread first kills every other thread, each by an interrupt that
;;; unwinds it, running its cleanup forms, and waits up to 50 ms for each to
;;; signal its end (PREPARE-TO-QUIT, level-1/l1-readloop.lisp), which a
;;; thread does before it counts as ended (PROCESS-INITIAL-FORM-EXITED,
;;; level-1/l1-processes.lisp). Only then does it call
;;; CCL:*SAVE-EXIT-FUNCTIONS*. So:
;;; - a worker that holds the state where an interrupt lands at once, at a
;;;   gate or between cmark calls, is unwound first: its document is
;;;   released and its hold ends, though the thread may still be finishing.
;;;   The save hook then closes cmark-gfm, and the image is saved clean;
;;; - a worker inside a cmark call defers the interrupt (interrupts.lisp),
;;;   and one that stays there past those 50 ms still holds the state when
;;;   the save hook runs. The hook refuses, as on SBCL, and closes nothing.
;;;   CCL's batch mode reports the error and exits with status 255
;;;   (ABNORMAL-APPLICATION-EXIT, level-1/l1-readloop-lds.lisp). No image is
;;;   written: the file SAVE-APPLICATION opened before the hooks ran stays
;;;   empty.
;;; That refusal is what keeps the second case safe: without it, CCL saves
;;; past the worker and dies of SIGSEGV, leaving an image it can't load,
;;; with or without cmark-gfm loaded. The save can't return to the
;;; child's forms, so the child reports each fact as it happens: before the
;;; save, from functions CCL calls before and after the library's save hook,
;;; and from a cleanup function CCL calls as it quits when the save fails.

#+ccl
(defun save-while-a-worker-holds (image &key in-call)
  "In a child CCL that loaded this suite: hold the published state in a
worker, inside a live document, and save an image at IMAGE with
CCL:SAVE-APPLICATION from this thread. The worker waits at a gate, where an
interrupt lands at once, or, with IN-CALL, stays up to 20 seconds with
interrupts deferred, as inside a cmark call that outlasts CCL's 50 ms wait.
The save doesn't return: CCL kills this thread, and the process ends once
the image is saved or the save fails. So each fact is reported to the
parent as it happens (REPORT-TO-PARENT):
- :ARRIVED, whether the worker held the state before the save was asked
  for;
- :BEFORE-SAVE, (:HOLDS N :PUBLISHED P) as it is asked for;
- :BEFORE-HOOK, from a function CCL calls just before the library's save
  hook, once the worker has ended or a second has passed:
  (:HOLDS N :PUBLISHED P :OPEN COUNTS :WORKER-ALIVE A :UNWOUND U), where
  U is whether the worker's own cleanup has run, once its document was
  released;
- :AFTER-HOOK, from a function CCL calls after the library's save hook,
  when it returns: (:PUBLISHED P :LOADED L), L whether either library is
  still loaded;
- :AFTER-REFUSAL, from a cleanup function CCL calls as it quits once the
  save hooks have begun, which a successful save never does: (:HOLDS N
  :PUBLISHED P :LOADED L :WORKER-ALIVE A), L whether both libraries are
  loaded;
- :SAVE-ERROR, should SAVE-APPLICATION signal before it asks for the save.
Returns :SAVE-RETURNED should the save return. The functions it adds to
CCL's lists stay there, in this process, which ends; once the library's
hook has returned, they take themselves off, so the image carries none."
  (let* ((paths (state-paths))
         (arrival (bt2:make-semaphore :name "arrival"))
         (gate (bt2:make-semaphore :name "gate"))
         (unwound nil)
         (hooks-began nil)
         (worker (make-test-thread
                  (lambda ()
                    (unwind-protect
                         (call-with-native-document
                          *held-markdown* '()
                          (lambda (document checked-options)
                            (cond (in-call
                                   (native::with-interrupts-deferred
                                     (bt2:signal-semaphore arrival)
                                     (loop with end = (+ (get-internal-real-time)
                                                         (* 20 internal-time-units-per-second))
                                           until (>= (get-internal-real-time) end))))
                                  (t
                                   (bt2:signal-semaphore arrival)
                                   (bt2:wait-on-semaphore gate :timeout 60)))
                            (render-html document checked-options))
                          :entry-point :html)
                      ;; Only a flag: CCL waits just 50 ms for the worker to
                      ;; end, and the hook reads the holds and counters.
                      (setf unwound t)))
                  :name "holding worker"))
         (before-hook (lambda ()
                        (setf hooks-began t)
                        ;; CCL signals a thread's termination semaphore, which
                        ;; PREPARE-TO-QUIT waits on, before the thread counts
                        ;; as ended (PROCESS-INITIAL-FORM-EXITED, CCL 1.13's
                        ;; level-1/l1-processes.lisp). So wait up to a second
                        ;; for the worker to end. Never join it here: a join
                        ;; waits on that semaphore, which PREPARE-TO-QUIT took.
                        (let ((ended (ended-within-p worker 1)))
                          (report-to-parent :before-hook
                                            (list :holds (startup-holds)
                                                  :published (native-state-published-p)
                                                  :open (native-open-counts)
                                                  :worker-alive (not ended)
                                                  :unwound unwound)))))
         (after-refusal (lambda ()
                          (when hooks-began
                            (report-to-parent :after-refusal
                                              (list :holds (startup-holds)
                                                    :published (native-state-published-p)
                                                    :loaded (every #'loaded-p paths)
                                                    :worker-alive (bt2:thread-alive-p worker))))))
         (after-hook nil))
    (setf after-hook (lambda ()
                       (report-to-parent :after-hook
                                         (list :published (native-state-published-p)
                                               :loaded (some #'loaded-p paths)))
                       (setf ccl:*save-exit-functions*
                             (remove-if (lambda (function)
                                          (member function (list before-hook after-hook)))
                                        ccl:*save-exit-functions*)
                             ccl:*lisp-cleanup-functions*
                             (remove after-refusal ccl:*lisp-cleanup-functions*))))
    (setf ccl:*save-exit-functions*
          (append (list before-hook) ccl:*save-exit-functions* (list after-hook)))
    (push after-refusal ccl:*lisp-cleanup-functions*)
    (report-to-parent :arrived (and (bt2:wait-on-semaphore arrival :timeout 60) t))
    (report-to-parent :before-save (list :holds (startup-holds)
                                         :published (native-state-published-p)))
    (handler-case (progn (ccl:save-application image) :save-returned)
      (error (condition)
        (report-to-parent :save-error (princ-to-string condition))
        :save-error))))

(defun copies-startup-facts (copies)
  "Start up with COPIES, the native namestrings of a copy of the pair at
another path, as the override, and return what that left, as a plist:
:SIGNALLED, the type of what startup signalled, or :STARTED-UP; :DATUM
(READABLE-PATHS) and :REASON, its datum and reason; then :PAIR, the pair
record; :LOADED, whether CFFI lists either copy as loaded; and
:PUBLISHED, whether a state is published."
  (let* ((failure (let ((*cmark-gfm-libraries* copies))
                    (startup-failure)))
         (ours (typep failure 'commonmark-gfm-error)))
    (list :signalled (if failure (type-of failure) :started-up)
          :datum (and ours (readable-paths (condition-datum failure)))
          :reason (and ours (condition-reason failure))
          :pair (native::loaded-pair)
          :loaded (and (some #'loaded-p copies) t)
          :published (native-state-published-p))))

(defun restarted-image-facts (&optional copies)
  "In a child started from a saved image that holds this suite: what the
image carried, before any call -- :PUBLISHED, :MAPPED, the libcmark-gfm
files it maps (Linux; SORTED-PATHS), :PAIR, :HOLDS and :OPEN -- then, with
COPIES, the native namestrings of a copy of the pair at another path,
:COPIES, what naming that pair first gave (COPIES-STARTUP-FACTS); then,
after its first ordinary call, :HTML, the render of *SAVED-IMAGE-MARKDOWN*,
and :STARTUPS-ADDED, how many startups that call ran."
  (let* ((startups (native-startup-count))
         (carried (list :published (native-state-published-p)
                        :mapped #+linux (sorted-paths (mapped-cmark-libraries)) #-linux :unknown
                        :pair (native::loaded-pair)
                        :holds (startup-holds)
                        :open (native-open-counts)))
         (copied (and copies (list :copies (copies-startup-facts copies)))))
    (append carried
            copied
            (list :html (render-html-of *saved-image-markdown* '())
                  :startups-added (- (native-startup-count) startups)))))

(defun restarted-image-forms (&optional copies)
  "The forms, as strings, of a child started from a saved image that holds
this suite: report RESTARTED-IMAGE-FACTS, given COPIES, under :RESTARTED,
then exit at once (CHILD-EXIT-FORM)."
  (list (format nil "(cl-commonmark-gfm.native-tests::report-to-parent :restarted ~
                     (cl-commonmark-gfm.native-tests::restarted-image-facts '~S))"
                copies)
        (child-exit-form)))

(defun saving-and-restarted-children (save-form &key copies)
  "Run a child that loads this suite and saves an image, by the form, as a
string, that SAVE-FORM, a function, makes from the image's native
namestring; then, when it wrote an image, start a second child from that
image, which reports RESTARTED-IMAGE-FACTS, given COPIES, under
:RESTARTED. The image lives in a temporary directory, which is deleted.
Return a plist: :SAVING and :RESTARTED, each child's RUN-CHILD plist, or
NIL for a child not run, and :IMAGE-OCTETS, the image file's length, or NIL
when there is none."
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((image (uiop:native-namestring (merge-pathnames "saved.image" directory)))
            (saving (run-child (suite-child-forms :save-returned (funcall save-form image))))
            (octets (file-octets image)))
       (list :saving saving
             :image-octets octets
             :restarted (when (and octets (plusp octets))
                          (run-child (restarted-image-forms copies) :image image)))))))

#+ccl
(defun busy-save-run (&key in-call)
  "Run SAVE-WHILE-A-WORKER-HOLDS, with IN-CALL, in a child CCL that loads
this suite, its image in a temporary directory, and, when that child wrote
an image, start a second child from it, which reports RESTARTED-IMAGE-
FACTS under :RESTARTED. Return a plist: :SAVING and :RESTARTED, each
child's RUN-CHILD plist, or NIL for a child not run, and :IMAGE-OCTETS, the
image file's length, or NIL when there is no file."
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((image (uiop:native-namestring (merge-pathnames "busy.image" directory)))
            (saving (run-child (suite-child-forms
                                :save-returned
                                (format nil "(cl-commonmark-gfm.native-tests::save-while-a-~
                                             worker-holds ~S :in-call ~S)"
                                        image in-call))))
            (octets (file-octets image)))
       (list :saving saving
             :image-octets octets
             :restarted (when (and octets (plusp octets))
                          (run-child (restarted-image-forms) :image image)))))))

#+ccl
(define-test saving-while-a-worker-holds-the-state-fails-and-never-harms-it
  ;; On CCL, a worker still holds the state when the save hook runs only if
  ;; it is in a call CCL's kill can't land in within 50 ms: here, held with
  ;; interrupts deferred, as inside a long cmark call.
  (destructuring-bind (&key saving image-octets restarted) (busy-save-run :in-call t)
    (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) saving
      (false killed "the child ended within ~D seconds" *child-seconds*)
      (is eql 255 exit-code
          "CCL's batch mode exits 255 when the save hook signals; its error output starts:~%~A"
          errors)
      (true (search "NATIVE-STATE-HELD" errors) "the save hook signalled NATIVE-STATE-HELD: ~A"
            errors)
      (true (search (held-state-report) errors) "with its report: ~A" errors)
      (true (getf reports :arrived) "the worker held the state, in its call, before the save")
      (is equal '(:holds 1 :published t) (getf reports :before-save :unreported)
          "the state was held and published as the save was asked for")
      (destructuring-bind (&key holds published worker-alive unwound &allow-other-keys)
          (getf reports :before-hook)
        (is eql 1 holds "the worker still held the state when the save hook ran")
        (true published "the state was published when the save hook ran")
        (true worker-alive "the worker was still in its call")
        (false unwound "the worker hadn't unwound"))
      (is eql :unreported (getf reports :after-hook :unreported)
          "the save hook signalled, so nothing after it ran")
      (is equal '(:holds 1 :published t :loaded t :worker-alive t)
          (getf reports :after-refusal :unreported)
          "after the refused save, CCL quit with nothing closed under the worker"))
    (is eql 0 image-octets "no image was written: the file CCL opened for it is empty")
    (false restarted "no image to start")))

#+ccl
(define-test saving-unwinds-a-worker-that-holds-the-state-and-the-image-starts-clean
  ;; The worker waits at a gate inside a live document, where CCL's kill
  ;; lands at once, so CCL unwinds it before the save hook runs.
  (destructuring-bind (&key saving image-octets restarted) (busy-save-run)
    (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) saving
      (false killed "the saving child ended within ~D seconds" *child-seconds*)
      (is eql 0 exit-code "the saving child exits 0 once its image is saved; its error output ~
                           starts:~%~A" errors)
      (true (getf reports :arrived) "the worker held the state, inside a live document, before ~
                                     the save")
      (is equal '(:holds 1 :published t) (getf reports :before-save :unreported)
          "the state was held and published as the save was asked for")
      (destructuring-bind (&key holds published open worker-alive unwound)
          (getf reports :before-hook)
        (is eql 0 holds "CCL had unwound the worker, and its hold, before the save hook ran")
        (true published "the state was still published when the save hook ran")
        (is equal '(:parsers 0 :roots 0 :buffers 0) open "the worker's document was released")
        (false worker-alive "the worker had ended")
        (is eql t unwound "the worker's own cleanup ran, once its document was released"))
      (is equal '(:published nil :loaded nil) (getf reports :after-hook :unreported)
          "the save hook closed both libraries and unpublished the state")
      (is eql :unreported (getf reports :after-refusal :unreported) "the save didn't fail"))
    (true (and image-octets (plusp image-octets)) "the image was written: ~S octets" image-octets)
    (destructuring-bind (&key killed exit-code reports errors &allow-other-keys) restarted
      (false killed "the restarted child ended within ~D seconds" *child-seconds*)
      (is eql 0 exit-code "the restarted child exits 0; its error output starts:~%~A" errors)
      (destructuring-bind (&key published mapped pair holds open html startups-added)
          (getf reports :restarted)
        (false published "the image has nothing published")
        #+linux
        (false mapped "the image has no cmark-gfm library mapped before its first call")
        (false pair "the image has no pair recorded before its first call")
        (is eql 0 holds "the image has no hold")
        (is equal '(:parsers 0 :roots 0 :buffers 0) open "the image's open counts")
        (is equal *saved-image-html* html "the image renders")
        (is eql 1 startups-added "the image's first call started up")))))

;;; On CCL, every close forgets. CCL keeps a record of each shared library
;;; it has opened, and a closed one stays on its list, for a saved image to
;;; reopen by soname. So closing the pair, by a reset or a failed startup,
;;; also takes both records off that list (NATIVE::CLOSE-LIBRARIES). The
;;; checks find the records by the sonames of the published state's two
;;; libraries (LISTED-RECORDS-NAMED).

#+ccl
(define-test a-reset-makes-ccl-forget-both-libraries
  (let* ((records (state-records (native-state)))
         (sonames (mapcar #'record-soname records)))
    (true (every (lambda (record) (member record ccl::*shared-libraries*)) records)
          "the control: CCL lists both while the state is published")
    (is = 2 (length (listed-records-named sonames))
        "the control: two records by those sonames: ~S" sonames)
    (is equal sonames (getf (pair-record) :sonames)
        "the pair record holds those sonames, for the save hook's forgetting")
    (with-startup-reset
      (is equal '() (listed-records-named sonames) "after a reset, CCL lists neither library")
      (true (native::native-state-p (native-state)) "the next call starts up")
      (is = 2 (length (listed-records-named sonames)) "and CCL lists both again"))))

#+ccl
(define-test a-failed-startup-makes-ccl-forget-the-libraries-it-loaded
  (let* ((paths (state-paths))
         (sonames (mapcar #'record-soname (state-records (native-state)))))
    ;; Step 3: the core loads, then the extensions don't, so only the core
    ;; closes. Opening the core, CCL also records every library it maps but
    ;; doesn't list (OPEN-SHARED-LIBRARY-INTERNAL): here the extensions,
    ;; which this process called into and still maps, though the reset
    ;; made CCL forget them. So only the core's record is checked.
    (with-startup-reset
      (let ((*cmark-gfm-libraries*
              (list (first paths) (uiop:native-namestring (fixture-path "vocabulary.md")))))
        (raised native-library-not-found (native-state)))
      (is equal '() (listed-records-named (list (first sonames)))
          "after step 3 failed, CCL doesn't list the core it loaded"))
    ;; Step 4: both load, the core is called, then the version number differs.
    (with-startup-reset
      (with-redefined ((native::%version-number (constantly #x001D000E)))
        (raised native-abi-mismatch (native-state)))
      (is equal '() (listed-records-named sonames) "after step 4 failed, CCL lists neither"))
    ;; The refusal: a copy of the pair loads, and is refused before any call.
    (call-with-library-copies
     (lambda (core extensions)
       (with-startup-reset
         (let ((*cmark-gfm-libraries* (list core extensions)))
           (raised native-initialization-error (native-state)))
         (is equal '() (listed-records-named sonames) "after the refusal, CCL lists neither"))))
    (true (native::native-state-p (native-state)) "the next ordinary call starts up")
    (true (open-counts-zero-p))))

#+ccl
(define-test a-close-that-signals-still-makes-ccl-forget-both-libraries
  ;; The extensions' close closes them, then signals. The core still
  ;; closes, and both records, nothing holding them open, are forgotten:
  ;; NATIVE::CLOSE-LIBRARIES forgets in its outermost cleanup.
  (let* ((state (native-state))
         (extensions (native::state-extensions-library state))
         (sonames (mapcar #'record-soname (state-records state)))
         (close (fdefinition 'cffi:close-foreign-library)))
    (unwind-protect
         (progn
           (with-redefined ((cffi:close-foreign-library
                             (lambda (library)
                               (prog1 (funcall close library)
                                 (when (eql library extensions)
                                   (error "the extensions' close signals"))))))
             (raised simple-error (reset-native-state)))
           (false (native-state-published-p) "the reset unpublished the state")
           (false (some #'loaded-p (native::state-paths state)) "both libraries closed")
           (is equal '() (listed-records-named sonames) "CCL lists neither library"))
      (reset-native-state))
    (true (native::native-state-p (native-state)) "the next call starts up")
    (true (open-counts-zero-p))))
