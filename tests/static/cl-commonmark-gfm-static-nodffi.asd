;;;; The condition test of the container whose ECL has no dynamic FFI (M4
;;;; design §6.2 and §6.4), outside the project's .asd. `make
;;;; check-ecl-nodffi-inside` loads it there, so ASDF compiles it, and
;;;; cl-commonmark-gfm with CFFI's method left at that ECL's default, into
;;;; that container's own fasl cache, then runs its MAIN in a process of its
;;;; own. It depends on cl-commonmark-gfm alone, CFFI coming with it: no
;;;; Parachute, no test system.

(asdf:defsystem "cl-commonmark-gfm-static-nodffi"
  :description "Checks dynamic-ffi-unavailable on an ECL built without dynamic FFI"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm")
  :serial t
  :components ((:file "nodffi")))
