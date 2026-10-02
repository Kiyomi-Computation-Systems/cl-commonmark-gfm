;;;; Helpers for the native suite (M2b plan, "Test helpers"): redefining an
;;;; internal wrapper for one test, reading the counters, finding fixtures,
;;;; and running a function on a live native document.

(in-package #:cl-commonmark-gfm.native-tests)

;;; Redefining a function for one test

(defmacro with-redefined ((&rest bindings) &body body)
  "Run BODY with each (NAME FUNCTION) of BINDINGS installed as NAME's global
function, and restore every original in UNWIND-PROTECT, however BODY exits.
FUNCTION is evaluated before any NAME changes. This is how a test makes an
internal wrapper around a cmark call fail or return null (M2 design §8.4):
the library itself has no test hooks."
  (let ((originals (loop repeat (length bindings) collect (gensym "ORIGINAL")))
        (replacements (loop repeat (length bindings) collect (gensym "REPLACEMENT"))))
    `(let (,@(loop for (name) in bindings
                   for original in originals
                   collect `(,original (fdefinition ',name)))
           ,@(loop for (nil function) in bindings
                   for replacement in replacements
                   collect `(,replacement ,function)))
       (unwind-protect
            (progn
              ,@(loop for (name) in bindings
                      for replacement in replacements
                      collect `(setf (fdefinition ',name) ,replacement))
              ,@body)
         ,@(loop for (name) in bindings
                 for original in originals
                 collect `(setf (fdefinition ',name) ,original))))))

(defun call-with-redefined (name function thunk)
  "Call THUNK with FUNCTION installed as NAME's global function, and restore
the original in UNWIND-PROTECT: WITH-REDEFINED for a NAME known only at
run time."
  (let ((original (fdefinition name)))
    (unwind-protect
         (progn
           (setf (fdefinition name) function)
           (funcall thunk))
      (setf (fdefinition name) original))))

;;; Asserting on what was signalled

(defmacro raised (type form &optional description &rest format-arguments)
  "Assert that FORM signals a condition of exactly TYPE, with Parachute's
FAIL, and return the condition, or NIL when FORM signalled nothing of TYPE.
A subtype of TYPE fails the second assertion: the test asserts on what was
signalled, not on something that merely satisfies TYPEP. DESCRIPTION and
FORMAT-ARGUMENTS describe both assertions, as in FAIL."
  (let ((condition (gensym "CONDITION")))
    `(let ((,condition (fail ,form ',type ,description ,@format-arguments)))
       (is eql ',type (type-of ,condition) ,description ,@format-arguments)
       (and (typep ,condition ',type) ,condition))))

;;; The counters (M2 design §5.4)

(defun open-counts-zero-p ()
  "True when no parser, root or buffer is open."
  (loop for (nil count) on (native-open-counts) by #'cddr always (zerop count)))

(defun created-parsers ()
  "The number of parsers ever created: a monotonic counter."
  (getf (native-created-counts) :parsers))

(defun created-buffers ()
  "The number of render buffers ever created: a monotonic counter."
  (getf (native-created-counts) :buffers))

;;; Fixtures

(defun fixture-path (name)
  "The absolute pathname of tests/fixtures/NAME."
  (asdf:system-relative-pathname "cl-commonmark-gfm" (concatenate 'string "tests/fixtures/" name)))

(defun fixture-string (name)
  "tests/fixtures/NAME's contents, read as UTF-8."
  (uiop:read-file-string (fixture-path name) :external-format :utf-8))

;;; A live document

(defun call-with-native-document (string options function &key (entry-point :parse))
  "Check OPTIONS, a plist, as ENTRY-POINT's options (:PARSE, :HTML,
:PLAINTEXT or :HTML-TREE), parse STRING with them, and call FUNCTION with
the live document and the CHECKED-OPTIONS. Returns what FUNCTION returns.
The native tests use this until the entry points exist."
  (let ((checked-options (check-options entry-point 'call-with-native-document options)))
    (with-native-document (document string checked-options)
      (funcall function document checked-options))))

(defun type-strings-entered (document)
  "The type string of every node of DOCUMENT, in the order WALK-NATIVE
enters them."
  (let ((type-strings '()))
    (walk-native (lambda (event node)
                   (when (eql event :enter)
                     (push (native-type-string document node) type-strings)))
                 document)
    (nreverse type-strings)))

(defun nodes-of-kind (document kind)
  "Every node of DOCUMENT whose classified kind is KIND, in walk order."
  (let ((nodes '()))
    (walk-native (lambda (event node)
                   (when (and (eql event :enter) (eql (native-kind document node) kind))
                     (push node nodes)))
                 document)
    (nreverse nodes)))

;;; The native state

(defun state-paths ()
  "The two library paths of the published native state, starting up first
when nothing is published."
  (native::state-paths (native-state)))

(defun loaded-library-namestrings ()
  "The native namestring of every foreign library CFFI lists as loaded."
  (loop for library in (cffi:list-foreign-libraries)
        for pathname = (cffi:foreign-library-pathname library)
        when pathname
          collect (uiop:native-namestring pathname)))

(defun loaded-p (path)
  "True when CFFI lists a loaded foreign library at PATH."
  (and (member path (loaded-library-namestrings) :test #'string=) t))

(defun startup-failure ()
  "Call NATIVE-STATE and return the ERROR it signals, or NIL when startup
succeeds."
  (handler-case (progn (native-state) nil)
    (error (condition) condition)))
