;;;; ASDF systems for the documentation site's generator, which renders
;;;; docs/ into HTML through cl-commonmark-gfm's public API, and for its
;;;; tests. They live here, outside cl-commonmark-gfm.asd, so they never
;;;; ship with the library: the Makefile's site targets add site/ to
;;;; CL_SOURCE_REGISTRY to find this file. On SBCL, the generator also
;;;; loads the sb-introspect contrib, which reads each function's lambda
;;;; list for the API reference (reference.lisp).

(asdf:defsystem "cl-commonmark-gfm-site"
  :description "Renders docs/ into an HTML site through cl-commonmark-gfm's public API"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm" (:feature :sbcl (:require "sb-introspect")))
  :serial t
  :components ((:file "package")
               (:file "pages")
               (:file "ids")
               (:file "links")
               (:file "checks")
               (:file "template")
               (:file "render")
               (:file "reference")
               (:file "examples")))

(asdf:defsystem "cl-commonmark-gfm-site/tests"
  :description "Tests for the documentation site's generator"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm-site" "parachute")
  :serial t
  :pathname "tests/"
  :components ((:file "package")
               (:file "core")
               (:file "checks")
               (:file "reference")
               (:file "examples")))
