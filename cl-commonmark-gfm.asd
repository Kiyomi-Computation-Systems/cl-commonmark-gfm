;;;; ASDF system definitions for cl-commonmark-gfm (M1 design §3; M2 design
;;;; §3).
;;;;
;;;; The primary system, cl-commonmark-gfm, holds the public API, and must
;;;; be defined even for a caller who never loads it: ASDF's
;;;; COMPONENT-DEPENDS-ON for any operation on a system S adds a dependency
;;;; on (DEFINE-OP (PRIMARY-SYSTEM-NAME S)), so a slash-named system can be
;;;; found and loaded only through its primary one. DEFINE-OP loads this
;;;; file, and loads no system. So loading the pure cl-commonmark-gfm/tests
;;;; defines the primary system but never loads its dependencies, CFFI
;;;; among them: `make check-purity` fails if a CFFI package exists after
;;;; the pure run.

(asdf:defsystem "cl-commonmark-gfm"
  :description "cmark-gfm bindings for Common Lisp"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/native" "cl-commonmark-gfm/html-tree")
  :serial t
  :pathname "src/"
  :components ((:file "api")))

(asdf:defsystem "cl-commonmark-gfm/util"
  :description "Helpers shared by the pure systems: proper-list-p, a UTF-8 encoder and decoder"
  :license "BSD-3-Clause"
  :serial t
  :pathname "src/"
  :components ((:file "util")))

(asdf:defsystem "cl-commonmark-gfm/conditions"
  :description "Conditions signalled by cl-commonmark-gfm"
  :license "BSD-3-Clause"
  :serial t
  :pathname "src/"
  :components ((:file "conditions")))

(asdf:defsystem "cl-commonmark-gfm/ast"
  :description "A validated AST node type, queries, equality and transforms"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/conditions" "cl-commonmark-gfm/util")
  :serial t
  :pathname "src/ast/"
  :components ((:file "package")
               (:file "schema")
               (:file "node")
               (:file "transform")))

(asdf:defsystem "cl-commonmark-gfm/html-tree"
  :description "AST to LHTML-shaped HTML tree conversion, and its serializer"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/ast" "cl-commonmark-gfm/util")
  :serial t
  :pathname "src/html-tree/"
  :components ((:file "package")
               (:file "url")
               (:file "serialize")
               (:file "footnotes")
               (:file "convert")))

(asdf:defsystem "cl-commonmark-gfm/native-core"
  :description "The native layer's pure decisions, from constants to the input guard"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/conditions" "cl-commonmark-gfm/util")
  :serial t
  :pathname "src/native-core/"
  :components ((:file "package")
               (:file "constants")
               (:file "version")
               (:file "classify")
               (:file "discovery")
               (:file "linking")
               (:file "options")
               (:file "limits")
               (:file "guard")
               (:file "output-bounds")))

(asdf:defsystem "cl-commonmark-gfm/tests"
  :description "Test suite for the pure conditions, AST, HTML-tree and native-core systems"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/util"
               "cl-commonmark-gfm/conditions"
               "cl-commonmark-gfm/ast"
               "cl-commonmark-gfm/html-tree"
               "cl-commonmark-gfm/native-core"
               "parachute")
  :serial t
  :pathname "tests/"
  :components ((:file "package")
               (:file "helpers")
               (:file "util")
               (:file "conditions")
               (:file "native-core")
               (:file "corpus")
               (:file "ast")
               (:file "url")
               (:file "serialize")
               (:file "html-tree")
               (:file "oracle")
               (:file "deep")
               (:file "property-harness")
               (:file "properties")))

(asdf:defsystem "cl-commonmark-gfm/ffi"
  :description "CFFI declarations of the cmark-gfm functions the native layer calls"
  :license "BSD-3-Clause"
  :depends-on ("cffi")
  :serial t
  :pathname "src/"
  :components ((:file "ffi")))

(asdf:defsystem "cl-commonmark-gfm/native"
  :description "Starting cmark-gfm, document lifetimes, walking, rendering, copying, saved images"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm/native-core"
               "cl-commonmark-gfm/ffi"
               "cl-commonmark-gfm/ast"
               "cl-commonmark-gfm/util"
               "cffi"
               "bordeaux-threads"
               "uiop")
  :serial t
  :pathname "src/native/"
  :components ((:file "package")
               (:file "interrupts")
               (:file "counters")
               (:file "document")
               (:file "walk")
               (:file "render")
               (:file "startup")
               (:file "image")
               (:file "copy")
               (:file "output-bounds")))

(asdf:defsystem "cl-commonmark-gfm/native-tests"
  :description "Test suite for the native layer, run against the pinned libcmark-gfm"
  :license "BSD-3-Clause"
  :depends-on ("cl-commonmark-gfm"
               "cl-commonmark-gfm/native"
               "cl-commonmark-gfm/tests"
               "parachute"
               "trivial-garbage"
               "cffi"
               "bordeaux-threads")
  :serial t
  :pathname "tests/native/"
  :components ((:file "package")
               (:file "helpers")
               (:file "startup")
               (:file "lifetimes")
               (:file "walk")
               (:file "render")
               (:file "copier")
               (:file "extensions")
               (:file "parse")
               (:file "limits")
               (:file "renderers")
               (:file "oracles")
               (:file "deep")
               (:file "xml")
               (:file "threads")
               (:file "stress")
               (:file "children")
               (:file "image")
               (:file "interrupts")
               (:file "guard")
               (:file "properties")
               (:file "divergences")))
