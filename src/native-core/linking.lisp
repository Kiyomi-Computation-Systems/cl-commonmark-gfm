;;;; LINKED-METHOD-P: whether an ECL program has cmark-gfm linked in (M4
;;;; design §6.1; ADR-0021). A program is linked when ECL compiled cmark's
;;;; calls, all in src/ffi.lisp, with CFFI's :C/C++ method: each is then a
;;;; direct C call, bound when the program is linked, so startup has no
;;;; library to find or load, and skips its steps 1 to 3 (M4 finding 6).
;;;; src/ffi.lisp records the method as its calls compile (FFI-METHOD; M4
;;;; finding 25). Pure: the method arrives as an argument.

(in-package #:cl-commonmark-gfm.native-core)

(defun linked-method-p (method)
  "True when METHOD, the method CFFI compiled cmark's calls with (FFI-METHOD,
src/ffi.lisp), makes the program linked: :C/C++ alone (M4 design §6.1;
ADR-0021). On ECL, METHOD is the value CFFI-SYS:*CFFI-ECL-METHOD* had
then: :DFFI and :DLOPEN look cmark-gfm's functions up in a library loaded
at run time, and :C/C++ calls them directly, bound at link time. On SBCL
and CCL, it is NIL. Startup skips the dynamic-FFI check, discovery and
loading for a linked program alone, and runs every step otherwise."
  (eql method :c/c++))
