;;;; Builds the smoke program, tests/static/, as an ECL program with
;;;; cmark-gfm linked in: build/ecl-static/cl-commonmark-gfm-static-smoke.
;;;; `make check-ecl-static` runs it from the repository root, as
;;;;
;;;;   ecl -norc -load tests/static/build.lisp </dev/null
;;;;
;;;; with CL_SOURCE_REGISTRY naming the root, tests/static/ and ocicl//, and
;;;; CMARK_GFM_ARCHIVE_DIR naming the directory that holds cmark-gfm's two
;;;; static archives. It sets ASDF's output translations itself, ignoring
;;;; any it would inherit, so every fasl goes under build/ecl-static/cache/:
;;;; fasls compiled under CFFI's :c/c++ method must be shared with no other
;;;; ECL, since ASDF keys an ECL's fasls by version and platform alone,
;;;; though their compiled calls differ by method.
;;;;
;;;; It uses ECL's own ASDF and no other: a newer ASDF, loaded over Debian's
;;;; ECL, fails to link the program, since it links in ECL's libcmp.a, which
;;;; Debian doesn't ship. Any serious condition prints itself and exits 1.
;;;; ECL's own handler of the command line quits 1 on an ERROR
;;;; (src/lsp/cmdline.lsp), but any other serious condition reaches its
;;;; debugger, which waits for input, and quits with status 0 at the end of
;;;; stdin (the top level's :eof command, src/lsp/top.lsp).
;;;;
;;;; It stays in CL-USER: ECL's builder writes the program's prologue and
;;;; epilogue forms out as text, which the program reads back in CL-USER as
;;;; it starts (BUILDER, ECL 24.5.10's src/cmp/cmpbackend-cxx/
;;;; cmpbackend-cxx.lsp), so their symbols must be ones CL-USER can read.

(require :asdf)
(require :cmp)

(defparameter *smoke-system* "cl-commonmark-gfm-static-smoke"
  "The system the program is built from, in tests/static/.")

(defparameter *repository*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-parent-directory-pathname
    (uiop:pathname-directory-pathname *load-truename*)))
  "The repository's root, two directories above this file.")

(defparameter *build-directory* (merge-pathnames "build/ecl-static/" *repository*)
  "Where the program goes, beside the fasls it is built from.")

(defparameter *fasl-directory* (merge-pathnames "cache/" *build-directory*)
  "Where every fasl of this build goes, in a directory named for the Lisp
implementation.")

(defparameter *archive-names* '("libcmark-gfm-extensions.a" "libcmark-gfm.a")
  "cmark-gfm's two static archives, in the order the linker must see them:
the extensions call into the core, so they come first.")

(defparameter *linkable-asdf* (probe-file (translate-logical-pathname "SYS:libasdf.a"))
  "ECL's ASDF as an archive that ASDF links into a program, or NIL when this
ECL ships none, as Debian's doesn't.")

;;; ECL runs a program's prologue and epilogue under EXT:SAFE-EVAL
;;; (src/lsp/top.lsp). It hands any serious condition to the debugger, and
;;; the cleanup of its UNWIND-PROTECT returns from it, which stops any
;;; unwind passing through. So EXT:QUIT, which unwinds, doesn't end the
;;; program from there: on Debian's ECL, after the prologue's EXT:QUIT, the
;;; program goes on to start its compiled files. Both forms handle every
;;; serious condition themselves, and end the program with EXT:EXIT, which
;;; runs the exit hooks and calls exit() without unwinding (src/c/main.d).

(defparameter *prologue*
  '(handler-case (let ((*load-verbose* nil))
                   (require :asdf))
     (serious-condition (condition)
       (ignore-errors
        (format *error-output* "~&check-ecl-static: the program can't load ECL's ASDF: ~A~%"
                condition)
        (finish-output *error-output*))
       (ext:exit 3)))
  "What the program runs as it starts, before any compiled file, when ECL
ships no ASDF to link in: CFFI's compiled code refers to ASDF's packages,
so ECL's own ASDF must be loaded first. A failure exits 3.")

(defparameter *epilogue*
  '(handler-case
       (let ((passed (funcall (find-symbol "MAIN" "CL-COMMONMARK-GFM.STATIC-SMOKE"))))
         (finish-output)
         (ext:exit (if passed 0 1)))
     (serious-condition (condition)
       (ignore-errors
        (finish-output *standard-output*)
        (format *error-output* "~%check-ecl-static: the smoke program signalled ~A~%"
                condition)
        (finish-output *error-output*))
       (ext:exit 2)))
  "What the program runs once every compiled file has started: the smoke
program's MAIN, exiting 0 when it returns true and 1 when it returns false.
Anything it signals exits 2, its message on a line of its own.")

;;; The archives

(defun archive-path (directory name)
  "The archive NAME in DIRECTORY, as the linker is to get it: the native
namestring of the very file found, absolute, its symbolic links resolved.
So a relative DIRECTORY, or one holding // or /./, names that file wherever
the linker runs: ECL runs it in its own default directory (SAVE-DIRECTORY,
src/cmp/cmpos-run.lsp), not necessarily the build's. Signals an error when
the path holds a *, a ? or a backslash, which ECL's pathnames read as a
wildcard, when ECL can't look the path up, or when no file is there. A
directory's name may hold blanks, quotes and colons."
  (let ((path (concatenate 'string (string-right-trim "/" directory) "/" name)))
    (when (find-if (lambda (char) (member char '(#\* #\? #\\) :test #'char=)) path)
      (error "ECL's pathnames read a *, a ? or a \\ as a wildcard, and ~A holds one. Put ~
              the archives in a directory whose path has none of them ~
              (CMARK_GFM_ARCHIVE_DIR)"
             path))
    (let ((found (handler-case (let ((parsed (uiop:parse-native-namestring path)))
                                 (and (not (wild-pathname-p parsed))
                                      (probe-file parsed)))
                   (error (condition)
                     (error "ECL can't look up ~A: ~A (CMARK_GFM_ARCHIVE_DIR)"
                            path condition)))))
      (unless found
        (error "~A has no ~A (CMARK_GFM_ARCHIVE_DIR)" directory name))
      (uiop:native-namestring found))))

(defun archive-paths ()
  "*ARCHIVE-NAMES* in the directory CMARK_GFM_ARCHIVE_DIR names, as native
namestrings. Signals an error when the variable is unset or empty, or when
ARCHIVE-PATH does."
  (let ((directory (uiop:getenv "CMARK_GFM_ARCHIVE_DIR")))
    (when (or (null directory) (zerop (length directory)))
      (error "CMARK_GFM_ARCHIVE_DIR is unset; it names the directory holding ~{~A~^ and ~}"
             *archive-names*))
    (mapcar (lambda (name) (archive-path directory name)) *archive-names*)))

(defun linker-option (path)
  "PATH as one option of C::*LD-LIBS*. ECL splits that string at blanks
outside quotes, and takes the character after a backslash as it is
(SPLIT-PROGRAM-OPTIONS, src/cmp/cmpos-run.lsp), so each blank, quote and
backslash in PATH gets a backslash before it."
  (with-output-to-string (out)
    (loop for char across path
          do (when (member char '(#\\ #\' #\" #\Space #\Tab #\Return #\Newline) :test #'char=)
               (write-char #\\ out))
             (write-char char out))))

;;; The fasls

(defun use-own-fasl-directory ()
  "Make ASDF compile every file under *FASL-DIRECTORY*, ignoring the output
translations it would inherit, ASDF_OUTPUT_TRANSLATIONS and the
configuration files among them: an inherited translation could send some
fasls where another ECL shares them. ASDF keeps two entries of its own
around this one: before it, ECL's own directory, left untranslated; after
it, the user cache under XDG_CACHE_HOME, which no file reaches, since this
entry matches every file first."
  (asdf:initialize-output-translations
   `(:output-translations
     (t (,*fasl-directory* :implementation))
     :ignore-inherited-configuration)))

(defun compiled-outputs (system component)
  "The files ASDF's COMPILE-OP writes for COMPONENT of SYSTEM."
  (asdf:output-files (asdf:make-operation 'asdf:compile-op)
                     (asdf:find-component system component)))

(defun check-what-compiles ()
  "Signal an error, before anything compiles, unless this build compiles this
repository's cl-commonmark-gfm, and ASDF puts its fasls, the smoke
program's and CFFI's under *FASL-DIRECTORY*. CFFI's system is only located,
never found: cffi.asd needs trivial-features compiled before it can be
read (:DEFSYSTEM-DEPENDS-ON), so finding it would compile. So for CFFI, the
translation checked is that of cffi.asd, a file in its tree."
  (let ((library (asdf:system-source-directory "cl-commonmark-gfm"))
        (cffi (nth-value 2 (asdf:locate-system "cffi"))))
    (unless (equal (namestring library) (namestring *repository*))
      (error "ASDF finds cl-commonmark-gfm in ~A, not in this repository, ~A ~
              (CL_SOURCE_REGISTRY)"
             library *repository*))
    (unless cffi
      (error "ASDF finds no CFFI (CL_SOURCE_REGISTRY)"))
    (dolist (output (append (compiled-outputs "cl-commonmark-gfm" "api")
                            (compiled-outputs *smoke-system* "smoke")))
      (unless (uiop:subpathp output *fasl-directory*)
        (error "ASDF would compile into ~A, outside ~A, where this build's fasls must go"
               output *fasl-directory*)))
    (let ((translated (asdf:apply-output-translations cffi)))
      (unless (uiop:subpathp translated *fasl-directory*)
        (error "ASDF would put CFFI's fasls outside ~A, where this build's fasls must go: ~
                it translates ~A, in CFFI's tree, to ~A"
               *fasl-directory* cffi translated)))))

;;; The build

(defun print-header ()
  "One line saying how this build goes: which ECL, whether it has dynamic
FFI, its ASDF, whether the program links ASDF in or loads it as it starts,
and where the archives come from."
  (format t "~&check-ecl-static: building with ~A ~A (~:[no~;with~] dynamic FFI) and its ~
             ASDF ~A, ~A; archives from ~A~%"
          (lisp-implementation-type) (lisp-implementation-version)
          (member :dffi *features*) (asdf:asdf-version)
          (if *linkable-asdf*
              (format nil "linked in from ~A" (uiop:native-namestring *linkable-asdf*))
              "loaded by the program's prologue, as this ECL has no SYS:libasdf.a")
          (uiop:getenv "CMARK_GFM_ARCHIVE_DIR"))
  (finish-output))

(defun build-program ()
  "Build the program:
- compile everything, CFFI included, under CFFI's :c/c++ method, with
  LOAD-SYSTEM :FORCE :ALL, into *FASL-DIRECTORY*. ASDF 3.1.8.8's
  MAKE-BUILD can't compile it itself;
- with the archives first in C::*LD-LIBS*: ECL's builder puts its
  :LD-FLAGS before the objects, and C::*LD-LIBS* after them.
  They go in before anything compiles: ECL links each compiled file with
  C::*LD-LIBS* too (BUNDLE-CC, src/cmp/cmpbackend-cxx/cmpbackend-cxx.lsp),
  and without them the first file that calls cmark-gfm, src/ffi.fas,
  doesn't load (\"undefined symbol\");
- link it with MAKE-BUILD, as one monolithic program, moved into
  *BUILD-DIRECTORY*.
ASDF 3.3 warns that MAKE-BUILD is deprecated: expected."
  (print-header)
  (let ((started (get-internal-real-time))
        (archives (archive-paths)))
    (use-own-fasl-directory)
    (check-what-compiles)
    (asdf:load-system "cffi")
    (setf (symbol-value (uiop:find-symbol* "*CFFI-ECL-METHOD*" "CFFI-SYS")) :c/c++)
    (setf c::*ld-libs* (format nil "~{~A ~}~A" (mapcar #'linker-option archives) c::*ld-libs*))
    (asdf:load-system *smoke-system* :force :all)
    (apply #'asdf:make-build *smoke-system*
           :type :program
           :monolithic t
           :move-here *build-directory*
           :epilogue-code *epilogue*
           (unless *linkable-asdf*
             (list :prologue-code *prologue*)))
    (let ((program (merge-pathnames *smoke-system* *build-directory*)))
      (unless (probe-file program)
        (error "MAKE-BUILD left no program at ~A" (uiop:native-namestring program)))
      (format t "~&check-ecl-static: built ~A in ~D s~%"
              (uiop:native-namestring program)
              (round (- (get-internal-real-time) started) internal-time-units-per-second))
      (finish-output))))

;;; The failure message starts on a line of its own: the compiler's last
;;; line on standard output may lack its newline, and ~& sees only the
;;; stream it writes to.

(handler-case
    (progn
      (build-program)
      (ext:quit 0))
  (serious-condition (condition)
    (finish-output *standard-output*)
    (format *error-output* "~%check-ecl-static: the build failed: ~A~%" condition)
    (finish-output *error-output*)
    (ext:quit 1)))
