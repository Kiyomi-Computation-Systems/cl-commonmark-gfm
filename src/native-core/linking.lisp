;;;; LINKED-METHOD-P: whether an ECL program has cmark-gfm linked in. That
;;;; is so when ECL compiled cmark's calls, all in src/ffi.lisp, with CFFI's
;;;; :C/C++ method. Each call is then a direct C call, bound at link time,
;;;; so startup has no library to find or load. src/ffi.lisp records the
;;;; method as the calls compile (FFI-METHOD), because CFFI's own variable
;;;; is back at its default by the time the program runs. Pure: the method
;;;; is an argument.

(in-package #:cl-commonmark-gfm.native-core)

(defun linked-method-p (method)
  "True when METHOD, the method CFFI compiled cmark's calls with (FFI-METHOD,
src/ffi.lisp), makes the program linked: :C/C++ alone. On ECL, METHOD is
the value CFFI-SYS:*CFFI-ECL-METHOD* had then: :DFFI and :DLOPEN look
cmark-gfm's functions up in a library loaded at run time, and :C/C++ calls
them directly, bound at link time. On SBCL and CCL, it is NIL. Startup
skips the dynamic-FFI check, discovery and loading for a linked program
alone, and runs every step otherwise."
  (eql method :c/c++))
