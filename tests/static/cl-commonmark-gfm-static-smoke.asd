;;;; The smoke program of a linked ECL build (M4 design §6.3), outside the
;;;; project's .asd. tests/static/build.lisp compiles it with
;;;; cl-commonmark-gfm under CFFI's :c/c++ method and links cmark-gfm's two
;;;; static archives into it; `make check-ecl-static` runs it. It depends on
;;;; cl-commonmark-gfm alone, CFFI coming with it: no Parachute, no test
;;;; system.

(asdf:defsystem "cl-commonmark-gfm-static-smoke"
  :description "Checks that an ECL program with cmark-gfm linked in starts and renders"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm")
  :serial t
  :components ((:file "smoke")))
