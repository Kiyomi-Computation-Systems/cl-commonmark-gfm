;;;; The condition test of the container whose ECL has no dynamic FFI.
;;;; `make check-ecl-nodffi-inside` runs it there, after its guard and
;;;; before the smoke program, in a process of its own: ECL loads its
;;;; system, cl-commonmark-gfm-static-nodffi, as any session loads
;;;; cl-commonmark-gfm, and calls MAIN. ASDF has compiled both into that
;;;; container's own fasl cache with CFFI's method left at its default,
;;;; :DLOPEN on an ECL that has :DLOPEN but not :DFFI (src/cffi-ecl.lisp).
;;;; ECL code that probes the FFI must be compiled: interpreted code takes
;;;; other paths through it.
;;;;
;;;; There, the native layer isn't linked, and CFFI refuses to load a
;;;; library at run time: its ECL backend's %LOAD-FOREIGN-LIBRARY signals
;;;; without :DFFI, though ECL's own loader would load one. So
;;;; MARKDOWN->HTML's startup stops at step 1, with
;;;; DYNAMIC-FFI-UNAVAILABLE: its datum the missing feature, :DFFI, and its
;;;; report saying how to link cmark-gfm into a program instead.
;;;;
;;;; Step 1 must come before discovery, step 2. The target runs this with
;;;; CL_COMMONMARK_GFM_LIBS malformed, so discovery would signal
;;;; NATIVE-LIBRARY-NOT-FOUND: a startup that ran it first would signal
;;;; that, and the SIGNALLED check would fail. The DISCOVERY check makes
;;;; sure of that premise, so a run without the malformed value fails
;;;; rather than passing untested.
;;;;
;;;; Nothing here checks that the failed startup left nothing behind. Such
;;;; checks couldn't fail on this ECL: CFFI refuses every load there, and
;;;; step 1 comes before any state, parse or load exists.
;;;;
;;;; MAIN calls MARKDOWN->HTML once, prints one line per failed check,
;;;; "FAIL <check>: <detail>", then "check-ecl-nodffi: <n> checks, <m>
;;;; failed", and returns true only when nothing failed. Every check catches
;;;; its own errors, and MAIN any other serious condition: one that reaches
;;;; ECL's debugger ends the process with status 0 at the end of stdin (the
;;;; top level's :eof command, ECL 24.5.10's src/lsp/top.lsp),
;;;; so the target also requires the summary line, with 0 failed.
;;;;
;;;; It reaches the native layer's internals as package::symbol, as the
;;;; native suite does.

(defpackage #:cl-commonmark-gfm.static-nodffi
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm
                #:markdown->html
                #:*cmark-gfm-libraries*
                #:commonmark-gfm-error
                #:condition-datum
                #:dynamic-ffi-unavailable
                #:native-library-not-found)
  (:export #:main))

(in-package #:cl-commonmark-gfm.static-nodffi)

;;; What the checks expect

(defparameter *default-method* :dlopen
  "The method CFFI compiles foreign calls with, by default, on an ECL that
has :DLOPEN but not :DFFI (*CFFI-ECL-METHOD*, src/cffi-ecl.lisp), and so
the method cmark's calls were compiled with here: a session that leaves it
alone isn't linked.")

(defparameter *report-needles*
  '("cffi-sys:*cffi-ecl-method*" ":c/c++" "libcmark-gfm-extensions.a" "libcmark-gfm.a")
  "What DYNAMIC-FFI-UNAVAILABLE's report must name, to say how to build a
linked program: the variable to set, its value, and the two archives to
link, extensions first.")

(defparameter *markdown* "Hello, *world*."
  "What MAIN asks MARKDOWN->HTML to render. Startup fails before it is
parsed.")

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

(defun report-string (condition)
  "CONDITION's report, without the pretty printer's line breaks. A report
that itself signals is replaced by a note saying so."
  (handler-case (let ((*print-pretty* nil))
                  (princ-to-string condition))
    (error () "its report signalled an error")))

(defun condition-detail (condition)
  "CONDITION's type and report."
  (detail "~S: ~A" (type-of condition) (report-string condition)))

(defun run-check (tally name function)
  "Run FUNCTION, one check of no arguments, which returns NIL when it passed
or a string saying what failed, and count it in TALLY. A failure, a
serious condition the check signals included, prints FAIL, NAME and its
detail on one line."
  (let ((failure (handler-case (funcall function)
                   (serious-condition (condition) (condition-detail condition)))))
    (incf (tally-checks tally))
    (when failure
      (incf (tally-failures tally))
      (format t "FAIL ~A: ~A~%" name (substitute #\Space #\Newline failure))
      (finish-output))))

;;; The one call

(defun startup-failure ()
  "Call MARKDOWN->HTML once, and return the serious condition it signals,
or NIL when it returns."
  (handler-case (progn (markdown->html *markdown*) nil)
    (serious-condition (condition) condition)))

;;; The checks: each returns NIL when it passed, or what failed

(defun method-problem ()
  "cmark's calls must have been compiled with this ECL's default method,
*DEFAULT-METHOD*: the session isn't linked, so its startup runs step 1."
  (let ((method (cl-commonmark-gfm.native::ffi-method)))
    (unless (eql method *default-method*)
      (detail "cmark's calls were compiled with ~S, not ~S" method *default-method*))))

(defun discovery-problem ()
  "Discovery, run with the arguments startup's step 2 gives it, must signal
NATIVE-LIBRARY-NOT-FOUND here, so that a startup that ran it before step 1
would fail with that, not DYNAMIC-FFI-UNAVAILABLE. It loads nothing: the
override, CL_COMMONMARK_GFM_LIBS and a file check are all it reads."
  (handler-case
      (let ((paths (cl-commonmark-gfm.native-core:resolve-cmark-libraries
                    :libraries (cl-commonmark-gfm.native::native-override
                                *cmark-gfm-libraries*)
                    :environment (uiop:getenv "CL_COMMONMARK_GFM_LIBS")
                    :os (cl-commonmark-gfm.native::current-os)
                    :multiarch (cl-commonmark-gfm.native::current-multiarch)
                    :regular-file-p #'cl-commonmark-gfm.native::regular-file-p)))
        (detail "discovery found ~S, so the order of steps 1 and 2 goes untested: run this ~
                 with CL_COMMONMARK_GFM_LIBS malformed, as make check-ecl-nodffi-inside does"
                paths))
    (native-library-not-found ()
      nil)))

(defun signalled-problem (condition)
  "CONDITION, what MARKDOWN->HTML signalled, must be of exactly the type
DYNAMIC-FFI-UNAVAILABLE: step 1 came first."
  (cond
    ((null condition)
     "markdown->html returned, signalling nothing")
    ((not (eql (type-of condition) 'dynamic-ffi-unavailable))
     (detail "markdown->html signalled ~A, not ~S"
             (condition-detail condition) 'dynamic-ffi-unavailable))))

(defun datum-problem (condition)
  "CONDITION's datum must be the missing feature, :DFFI."
  (cond
    ((null condition)
     "markdown->html signalled nothing, so there is no datum")
    ((not (typep condition 'commonmark-gfm-error))
     (detail "~S has no datum" (type-of condition)))
    ((not (eql (condition-datum condition) :dffi))
     (detail "the datum is ~S, not :DFFI" (condition-datum condition)))))

(defun report-problem (condition)
  "CONDITION's report must name each of *REPORT-NEEDLES*, so it says how to
build a linked program instead."
  (if (null condition)
      "markdown->html signalled nothing, so there is no report"
      (let* ((report (report-string condition))
             (missing (remove-if (lambda (needle) (search needle report :test #'char=))
                                 *report-needles*)))
        (when missing
          (detail "the report doesn't name ~{~A~^, ~}: ~A" missing report)))))

;;; The program

(defun run-checks (tally)
  "Run every check, in order: the method and discovery's premise, then
MARKDOWN->HTML's one call and what it signalled."
  (run-check tally "method" #'method-problem)
  (run-check tally "discovery" #'discovery-problem)
  (let ((condition (startup-failure)))
    (run-check tally "signalled" (lambda () (signalled-problem condition)))
    (run-check tally "datum" (lambda () (datum-problem condition)))
    (run-check tally "report" (lambda () (report-problem condition)))))

(defun main ()
  "Run every check, printing one line per failure, then the summary, and
return true only when nothing failed. Every serious condition is handled
here: one outside any check counts as a failed check of its own, main."
  (let ((tally (make-tally)))
    (handler-case (run-checks tally)
      (serious-condition (condition)
        (run-check tally "main" (lambda () (condition-detail condition)))))
    (format t "check-ecl-nodffi: ~D checks, ~D failed~%"
            (tally-checks tally) (tally-failures tally))
    (finish-output)
    (zerop (tally-failures tally))))
