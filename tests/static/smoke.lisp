;;;; The smoke program of a linked ECL build: an ECL program with
;;;; cmark-gfm linked in, whose startup loads nothing.
;;;; tests/static/build.lisp builds it, and its epilogue calls MAIN. `make
;;;; check-ecl-static` runs it with one argument, the fixtures directory,
;;;; and with CL_COMMONMARK_GFM_LIBS naming two files that don't exist, so a
;;;; startup that looks for files fails.
;;;;
;;;; MAIN prints one line per failed check, "FAIL <check>: <detail>", then
;;;; "check-ecl-static: <n> checks, <m> failed", and returns true only when
;;;; nothing failed. Every check catches its own errors, and MAIN any other:
;;;; an error that reaches an ECL program's debugger doesn't end it with a
;;;; failure. The debugger waits for input, and quits with status 0 at the
;;;; end of stdin (the top level's :eof command, ECL's src/lsp/top.lsp).
;;;;
;;;; It reaches the native layer's internals as package::symbol, as the
;;;; native suite does. It runs on ECL alone, so it calls ECL's
;;;; EXT:COMMAND-ARGS.

(defpackage #:cl-commonmark-gfm.static-smoke
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm
                #:*cmark-gfm-libraries*
                #:markdown->html
                #:markdown->html-tree
                #:html-tree->string)
  (:export #:main))

(in-package #:cl-commonmark-gfm.static-smoke)

;;; What the checks expect

(defparameter *pinned-version* "0.29.0.gfm.13"
  "The cmark-gfm release a linked program's state must report.")

(defconstant +case-count+ 28
  "How many cases tests/fixtures/html/cases lists: the 28 oracle fixtures.
The pure suite keeps the manifest and its own table of cases in step
(tests/oracle.lisp). Counting them here catches a manifest read short,
which would otherwise check less and still pass.")

(defparameter *restart-case* "paragraphs"
  "The case rendered again after the restart.")

(defparameter *missing-libraries*
  '("missing-libcmark-gfm.so" "missing-libcmark-gfm-extensions.so")
  "The files, core then extensions, in the fixtures directory, that the
restart binds *CMARK-GFM-LIBRARIES* to. Neither exists, and a linked
startup ignores the override.")

;;; Counting and reporting the checks

(defstruct (tally (:constructor make-tally ()))
  "How many checks ran, and how many of them failed."
  (checks 0)
  (failures 0))

(defun detail (control &rest arguments)
  "A failure's detail: FORMAT's string for CONTROL and ARGUMENTS, without
the pretty printer's line breaks."
  (let ((*print-pretty* nil))
    (apply #'format nil control arguments)))

(defun condition-detail (condition)
  "CONDITION's type and report. A report that itself signals is replaced by
a note saying so."
  (detail "~S: ~A" (type-of condition)
          (handler-case (let ((*print-pretty* nil))
                          (princ-to-string condition))
            (error () "its report signalled an error"))))

(defun one-line (string)
  "STRING with each newline replaced by a space, so a failure prints on one
line."
  (substitute #\Space #\Newline string))

(defun run-check (tally name function)
  "Run FUNCTION, one check of no arguments, which returns NIL when it passed
or a string saying what failed, and count it in TALLY. A failure, an ERROR
the check signals included, prints FAIL, NAME and its detail."
  (let ((failure (handler-case (funcall function)
                   (error (condition) (condition-detail condition)))))
    (incf (tally-checks tally))
    (when failure
      (incf (tally-failures tally))
      (format t "FAIL ~A: ~A~%" name (one-line failure))
      (finish-output))))

;;; Files, read with plain streams

(defun file-string (path)
  "PATH's contents, read as UTF-8."
  (with-open-file (stream path :external-format :utf-8)
    (with-output-to-string (out)
      (let ((buffer (make-string 4096)))
        (loop for end = (read-sequence buffer stream)
              while (plusp end)
              do (write-string buffer out :end end))))))

;;; The manifest, tests/fixtures/html/cases, read as the native suite reads
;;; it (tests/native/render.lisp)

(defun manifest-fields (line)
  "LINE split at runs of spaces and tabs."
  (let ((fields '())
        (start nil))
    (loop for index from 0 to (length line)
          for char = (and (< index (length line)) (char line index))
          do (cond
               ((and char (not (member char '(#\Space #\Tab) :test #'char=)))
                (unless start (setf start index)))
               (start
                (push (subseq line start index) fields)
                (setf start nil))))
    (nreverse fields)))

(defun read-cases (directory)
  "Every case of the cases file in DIRECTORY, as (NAME FILE FLAGS): one for
each line that isn't blank and doesn't start with #, whose fields are the
case's name, its Markdown file and the CLI flags it renders with."
  (with-open-file (stream (merge-pathnames "cases" directory) :external-format :utf-8)
    (loop for line = (read-line stream nil nil)
          for fields = (and line (manifest-fields line))
          while line
          when (and fields (char/= (char (first fields) 0) #\#))
            collect (list (first fields) (second fields) (cddr fields)))))

(defun flag-options (flag path)
  "The options for what the CLI's FLAG does, as PATH takes them: :HTML,
MARKDOWN->HTML, or :TREE, MARKDOWN->HTML-TREE. MARKDOWN->HTML's are the
native suite's (CLI-FLAG-OPTIONS, tests/native/render.lisp). The tree has
no :UNSAFE-HTML: --unsafe's links are its :LINK-POLICY :UNSAFE, as the
pure suite renders links-unsafe (tests/oracle.lisp) and as the native
suite's tree oracle compares the two (tests/native/oracles.lisp). An
unknown flag signals an error, which fails its case."
  (cond
    ((string= flag "--unsafe") (ecase path
                                 (:html '(:unsafe-html t))
                                 (:tree '(:link-policy :unsafe))))
    ((string= flag "--nobreaks") '(:softbreak :space))
    ((string= flag "--hardbreaks") '(:softbreak :br))
    (t (error "the manifest names an unknown flag: ~A" flag))))

(defun case-options (flags path)
  "The options PATH renders a case with, for its FLAGS, on top of the :GFM
profile's defaults, as the CLI's flags are on top of its GFM flags."
  (loop for flag in flags
        append (flag-options flag path)))

;;; The two paths each case renders through

(defparameter *paths* '(:html :tree)
  "The paths every case renders through, each compared with its committed
HTML.")

(defun path-name (path)
  "PATH's name in a failure's line."
  (ecase path
    (:html "markdown->html")
    (:tree "markdown->html-tree")))

(defun render (path markdown options)
  "MARKDOWN rendered with OPTIONS through PATH: :HTML, MARKDOWN->HTML; or
:TREE, (HTML-TREE->STRING (MARKDOWN->HTML-TREE ...))."
  (ecase path
    (:html (apply #'markdown->html markdown options))
    (:tree (html-tree->string (apply #'markdown->html-tree markdown options)))))

(defun visible (string)
  "STRING with each newline written as \\n."
  (with-output-to-string (out)
    (loop for char across string
          do (if (char= char #\Newline)
                 (write-string "\\n" out)
                 (write-char char out)))))

(defun difference (expected actual file)
  "NIL when ACTUAL equals EXPECTED, FILE's contents, character for
character; otherwise where they first differ, and up to 24 characters of
each from there."
  (let ((index (mismatch expected actual :test #'char=)))
    (when index
      (flet ((excerpt (string)
               (visible (subseq string index (min (length string) (+ index 24))))))
        (detail "differs from ~A at character ~D: expected \"~A\", got \"~A\""
                file index (excerpt expected) (excerpt actual))))))

(defun case-difference (entry directory path)
  "NIL when ENTRY, a case (NAME FILE FLAGS), rendered through PATH, equals
its committed HTML, NAME.html in DIRECTORY; otherwise what differs. They
are compared as characters, the file read as UTF-8, which is octet for
octet: ECL signals EXT:STREAM-DECODING-ERROR on an octet sequence that
isn't UTF-8, which fails the check."
  (destructuring-bind (name file flags) entry
    (if (null file)
        "its line in the manifest names no Markdown file"
        (let ((html (merge-pathnames (format nil "~A.html" name) directory)))
          (difference (file-string html)
                      (render path
                              (file-string (merge-pathnames file directory))
                              (case-options flags path))
                      (namestring html))))))

;;; The checks: each returns NIL when it passed, or what failed

(defun ffi-method-problem ()
  "cmark's calls, in src/ffi.lisp, must have been compiled with CFFI's
:C/C++ method, which makes them direct C calls and the program linked.
FFI-METHOD records the method as that file compiles, since CFFI's own
variable is back at ECL's default by the time the program runs."
  (let ((method (cl-commonmark-gfm.native::ffi-method)))
    (unless (eql method :c/c++)
      (detail "cmark's calls, in src/ffi.lisp, were compiled with ~S, not :C/C++" method))))

(defun linked-state-problem ()
  "The published state must be linked: its paths :LINKED, as it loaded no
file, and its version the pinned one."
  (let* ((state (cl-commonmark-gfm.native::native-state))
         (paths (cl-commonmark-gfm.native::state-paths state))
         (version (cl-commonmark-gfm.native::state-version state))
         (problems (append (unless (eql paths :linked)
                             (list (detail "its paths are ~S, not :LINKED" paths)))
                           (unless (equal version *pinned-version*)
                             (list (detail "its version is ~S, not ~S"
                                           version *pinned-version*))))))
    (and problems (detail "~{~A~^; ~}" problems))))

(defun case-count-problem (cases)
  "CASES, the manifest's, must be +CASE-COUNT+ of them."
  (unless (= (length cases) +case-count+)
    (detail "the manifest lists ~D cases, not ~D" (length cases) +case-count+)))

(defun missing-library-paths (directory)
  "*MISSING-LIBRARIES*, as absolute paths in DIRECTORY."
  (let ((base (truename directory)))
    (mapcar (lambda (name) (namestring (merge-pathnames name base)))
            *missing-libraries*)))

(defun restart-problem (cases directory)
  "After RESET-NATIVE-STATE, with *CMARK-GFM-LIBRARIES* naming two files
that don't exist, *RESTART-CASE* of CASES must render through
MARKDOWN->HTML as its committed HTML has it, and the startup count must
rise by one: a linked state closes nothing, starts again, and ignores the
override."
  (let ((entry (find *restart-case* cases :key #'first :test #'string=))
        (libraries (missing-library-paths directory))
        (before (cl-commonmark-gfm.native::native-startup-count))
        (problems '()))
    (cond
      ((null entry)
       (detail "the manifest has no case ~A" *restart-case*))
      (t
       (dolist (library libraries)
         (when (probe-file library)
           (push (detail "~A exists" library) problems)))
       (cl-commonmark-gfm.native::reset-native-state)
       (let ((failure (handler-case (let ((*cmark-gfm-libraries* libraries))
                                      (case-difference entry directory :html))
                        (error (condition) (condition-detail condition)))))
         (when failure
           (push (detail "~A: ~A" *restart-case* failure) problems)))
       (let ((risen (- (cl-commonmark-gfm.native::native-startup-count) before)))
         (unless (= risen 1)
           (push (detail "the startup count rose by ~D, not 1" risen) problems)))
       (and problems (detail "~{~A~^; ~}" (reverse problems)))))))

(defun open-counts-problem ()
  "The open counters must be at zero: no parser, root or render buffer left
open."
  (let ((counts (cl-commonmark-gfm.native::native-open-counts)))
    (unless (loop for (nil count) on counts by #'cddr always (zerop count))
      (detail "handles left open:~{ ~(~A~) ~D~}" counts))))

(defun foreign-libraries-problem ()
  "CFFI must list no loaded library: a linked program loads none. Replacing
ECL's own FFI functions to catch a load would catch nothing, since ECL
compiles a call to them as a direct C call, so what was loaded is checked
instead."
  (let ((libraries (cffi:list-foreign-libraries)))
    (when libraries
      (detail "CFFI lists ~D loaded: ~{~A~^, ~}" (length libraries)
              (mapcar #'cffi:foreign-library-pathname libraries)))))

#+linux
(defun mapped-cmark-problem ()
  "No line of /proc/self/maps may name libcmark-gfm: no shared cmark-gfm is
mapped into the program. Read as Latin-1, so any octet decodes."
  (let ((lines (with-open-file (stream "/proc/self/maps" :external-format :latin-1)
                 (loop for line = (read-line stream nil nil)
                       while line
                       when (search "libcmark-gfm" line :test #'char=)
                         collect line))))
    (when lines
      (detail "/proc/self/maps names libcmark-gfm on ~D line~:P, the first: ~A"
              (length lines) (first lines)))))

;;; The program

(defun fixtures-directory ()
  "The fixtures directory, the program's one argument, as a directory
pathname. ECL's EXT:COMMAND-ARGS lists the program itself first."
  (let ((arguments (rest (ext:command-args))))
    (unless (= (length arguments) 1)
      (error "expected one argument, the fixtures directory, but got ~D: ~S"
             (length arguments) arguments))
    (let ((argument (first arguments)))
      (pathname (if (and (plusp (length argument))
                         (char= (char argument (1- (length argument))) #\/))
                    argument
                    (concatenate 'string argument "/"))))))

(defun run-checks (tally directory)
  "Run every check, in order, against the fixtures in DIRECTORY. What is
loaded is checked twice: right after the first startup, and at the end. A
pair that the first startup loaded would be gone by the end: the restart's
reset closes it, and its own startup loads nothing."
  (let ((cases '()))
    (run-check tally "ffi-method" #'ffi-method-problem)
    (run-check tally "linked-state" #'linked-state-problem)
    (run-check tally "foreign-libraries after startup" #'foreign-libraries-problem)
    #+linux
    (run-check tally "proc-self-maps after startup" #'mapped-cmark-problem)
    (run-check tally "cases" (lambda ()
                               (setf cases (read-cases directory))
                               (case-count-problem cases)))
    (dolist (entry cases)
      (dolist (path *paths*)
        (run-check tally (format nil "~A ~A" (path-name path) (first entry))
                   (lambda () (case-difference entry directory path)))))
    (run-check tally "restart" (lambda () (restart-problem cases directory)))
    (run-check tally "open-counts" #'open-counts-problem)
    (run-check tally "foreign-libraries at the end" #'foreign-libraries-problem)
    #+linux
    (run-check tally "proc-self-maps at the end" #'mapped-cmark-problem)))

(defun main ()
  "Run every check, printing one line per failure, then the summary, and
return true only when nothing failed. The fixtures directory is the
program's one argument. Every error is handled here: one outside any check
counts as a failed check of its own, main."
  (let ((tally (make-tally)))
    (handler-case (run-checks tally (fixtures-directory))
      (error (condition)
        (run-check tally "main" (lambda () (condition-detail condition)))))
    (format t "check-ecl-static: ~D checks, ~D failed~%"
            (tally-checks tally) (tally-failures tally))
    (finish-output)
    (zerop (tally-failures tally))))
