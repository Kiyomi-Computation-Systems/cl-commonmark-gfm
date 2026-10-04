;;;; The cl-commonmark-gfm.native package: the native layer's imperative
;;;; shell (M2 design §3, §5, §6; ADR-0008, ADR-0009). It starts cmark-gfm,
;;;; owns every native parser, root and render buffer, walks a parsed tree,
;;;; renders it, and copies it into an AST. Its decisions live in the pure
;;;; /native-core.
;;;;
;;;; Internal: the primary system builds on it, and the native suite tests
;;;; it, but nothing here is part of the public API. The library's only
;;;; reader conditionals live in this system (M2 design §3).

(defpackage #:cl-commonmark-gfm.native
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm.conditions
                #:native-library-not-found
                #:native-abi-mismatch
                #:dynamic-ffi-unavailable
                #:native-initialization-error
                #:native-parse-error
                #:native-render-error
                #:unsupported-extension-node)
  (:import-from #:cl-commonmark-gfm.native-core
                #:*cmark-gfm-version*
                #:*extension-keywords*
                #:*cmark-gfm-libraries*
                #:version-number
                #:number-version
                #:+cmark-bullet-list+
                #:+cmark-ordered-list+
                #:+cmark-period-delim+
                #:+cmark-paren-delim+
                #:classify-node
                #:resolve-cmark-libraries
                #:linked-method-p
                #:check-options
                #:checked-extensions
                #:checked-sourcepos
                #:checked-softbreak
                #:checked-unsafe-html
                #:checked-width
                #:parse-option-bits
                #:html-option-bits
                #:plaintext-option-bits
                #:document-attributes
                #:*max-nodes*
                #:effective-maximum
                #:check-limit
                ;; The output bounds' per-node terms (M2 design §5.5)
                #:html-sourcepos-octets
                #:html-block-quote-bound
                #:html-list-bound
                #:html-item-bound
                #:html-task-item-bound
                #:html-heading-bound
                #:code-block-language-octets
                #:html-code-block-bound
                #:html-html-block-bound
                #:html-thematic-break-bound
                #:html-paragraph-bound
                #:html-text-bound
                #:html-softbreak-bound
                #:html-linebreak-bound
                #:html-code-bound
                #:html-html-inline-bound
                #:html-emph-bound
                #:html-strong-bound
                #:html-strikethrough-bound
                #:html-link-bound
                #:html-image-bound
                #:html-table-bound
                #:html-table-header-bound
                #:html-table-row-bound
                #:html-table-cell-bound
                #:html-footnote-definition-bound
                #:html-footnote-reference-bound
                #:html-footnote-section-bound
                #:html-footnote-suffix-bound
                #:html-footnote-backrefs-bound
                #:footnote-reference-bound
                #:plaintext-item-marker-width
                #:plaintext-prefix-width
                #:plaintext-event-steps
                #:plaintext-steps-bound)
  (:import-from #:cl-commonmark-gfm.ast
                #:make-node)
  (:import-from #:cl-commonmark-gfm.util
                #:proper-list-p
                #:utf8-length
                #:encode-utf8
                #:decode-utf8)
  (:import-from #:cl-commonmark-gfm.ffi
                #:ffi-method
                #:cmark-parser-new
                #:cmark-parser-attach-syntax-extension
                #:cmark-parser-feed
                #:cmark-parser-finish
                #:cmark-parser-get-syntax-extensions
                #:cmark-parser-free
                #:cmark-node-free
                #:cmark-node-first-child
                #:cmark-node-next
                #:cmark-node-parent
                #:cmark-node-get-type
                #:cmark-node-get-type-string
                #:cmark-node-get-syntax-extension
                #:cmark-node-get-literal
                #:cmark-node-get-url
                #:cmark-node-get-title
                #:cmark-node-get-fence-info
                #:cmark-node-get-heading-level
                #:cmark-node-get-list-type
                #:cmark-node-get-list-delim
                #:cmark-node-get-list-start
                #:cmark-node-get-list-tight
                #:cmark-node-get-start-line
                #:cmark-node-get-start-column
                #:cmark-node-get-end-line
                #:cmark-node-get-end-column
                #:cmark-node-parent-footnote-def
                #:cmark-gfm-core-extensions-ensure-registered
                #:cmark-find-syntax-extension
                #:cmark-gfm-extensions-get-table-columns
                #:cmark-gfm-extensions-get-table-alignments
                #:cmark-gfm-extensions-get-tasklist-item-checked
                #:cmark-render-html
                #:cmark-render-plaintext
                #:cmark-render-xml
                #:cmark-version
                #:cmark-version-string
                #:cmark-get-default-mem-allocator)
  (:export ;; Startup (M2 design §5.2), and holding the state (§5.3)
           #:native-state
           #:with-native-state
           ;; Lifetimes (M2 design §5.4)
           #:with-native-document
           ;; Walking (M2 design §5.1)
           #:walk-native
           ;; The node accessors, each (accessor document node), but
           ;; NATIVE-ROOT, which takes the document alone
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
           ;; Rendering (M2 design §5.4)
           #:render-html
           #:render-plaintext
           #:render-xml
           ;; Copying a parsed tree into an AST (M2 design §6)
           #:copy-native-tree
           ;; The output bounds (M2 design §5.5)
           #:html-output-bound
           #:plaintext-output-bound
           ;; For tests, and for saved images (M2 design §5.3)
           #:reset-native-state
           #:native-state-published-p
           #:native-open-counts
           #:native-created-counts
           #:native-startup-count))
