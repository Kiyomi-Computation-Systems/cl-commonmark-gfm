;;;; The cl-commonmark-gfm.native-tests package: the native suite.
;;;; tests/run-native.lisp runs it on each Lisp in NATIVE_LISPS. The native
;;;; layer's internals are reached through the NATIVE nickname, as
;;;; native::name. The public API comes from the primary package,
;;;; cl-commonmark-gfm, as a caller would reach it.

(defpackage #:cl-commonmark-gfm.native-tests
  (:use #:cl)
  (:local-nicknames (#:native #:cl-commonmark-gfm.native)
                     (#:native-core #:cl-commonmark-gfm.native-core)
                     (#:html-tree #:cl-commonmark-gfm.html-tree))
  (:import-from #:cl-commonmark-gfm
                #:parse
                #:markdown->html
                #:markdown->plaintext
                #:markdown->html-tree
                #:ast->html-tree
                #:html-tree->string
                #:make-node
                #:copy-node
                #:node-kind
                #:node-attributes
                #:node-attribute
                #:node-children
                #:node-sourcepos
                #:node=
                #:walk-ast
                #:transform-ast
                #:commonmark-gfm-error
                #:invalid-parse-option
                #:invalid-render-option
                #:resource-limit-exceeded
                #:condition-limit
                #:condition-maximum
                #:unsupported-input
                #:*max-input-octets*
                #:*max-nodes*)
  (:import-from #:cl-commonmark-gfm.tests
                #:corpus-examples
                #:corpus-example-file
                #:corpus-example-number
                #:corpus-example-markdown
                #:corpus-example-html
                #:corpus-example-options
                #:*oracle-cases*
                ;; The property-testing harness (tests/property-harness.lisp):
                ;; shared by tests/native/properties.lisp and divergences.lisp.
                #:register-property
                #:run-case
                #:run-property
                #:property-generators
                #:oracle-option-sets
                #:*property-seed*
                #:property-cases
                #:summary-problems
                #:summary-report)
  (:import-from #:cl-commonmark-gfm.conditions
                #:condition-operation
                #:condition-datum
                #:condition-reason
                #:native-library-not-found
                #:condition-override
                #:condition-paths
                #:native-abi-mismatch
                #:condition-expected-version
                #:condition-found-version
                #:native-initialization-error
                #:native-parse-error
                #:native-render-error
                #:unsupported-extension-node)
  (:import-from #:cl-commonmark-gfm.native-core
                #:*cmark-gfm-version*
                #:*cmark-gfm-libraries*
                #:*extension-keywords*
                #:check-options
                #:checked-footnotes
                #:table-cell-bound
                #:classify-node
                #:+cmark-node-custom-block+
                #:+cmark-node-custom-inline+)
  (:import-from #:cl-commonmark-gfm.ffi
                #:cmark-get-default-mem-allocator)
  (:import-from #:cl-commonmark-gfm.native
                #:native-state
                #:with-native-document
                #:walk-native
                #:native-root
                #:native-first-child
                #:native-next
                #:native-parent
                #:native-type
                #:native-type-string
                #:native-extension
                #:native-kind
                #:native-literal
                #:native-url
                #:native-title
                #:native-fence-info
                #:native-heading-level
                #:native-list-type
                #:native-list-delimiter
                #:native-list-start
                #:native-list-tight
                #:native-start-line
                #:native-start-column
                #:native-end-line
                #:native-end-column
                #:native-footnote-definition
                #:native-table-columns
                #:native-table-alignments
                #:native-task-checked
                #:render-html
                #:render-plaintext
                #:render-xml
                #:copy-native-tree
                #:html-output-bound
                #:plaintext-output-bound
                #:reset-native-state
                #:native-state-published-p
                #:native-open-counts
                #:native-created-counts
                #:native-startup-count)
  (:import-from #:parachute
                #:define-test
                #:is
                #:isnt
                #:true
                #:false
                #:fail
                #:of-type))
