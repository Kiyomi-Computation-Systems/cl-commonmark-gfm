;;;; The cl-commonmark-gfm.native-core package: the native layer's pure
;;;; decisions. It holds the pin and cmark's constants; the version
;;;; cross-check's pure half; CLASSIFY-NODE; RESOLVE-CMARK-LIBRARIES and
;;;; LINKED-METHOD-P; CHECK-OPTIONS, the option bits and
;;;; DOCUMENT-ATTRIBUTES; the three resource limits; FOOTNOTE-ENTITY-INDEX,
;;;; the input guard's scan; and the per-node terms of the output bounds.
;;;;
;;;; Pure: no CFFI and no UIOP anywhere in this system. The operating
;;;; system, an environment variable's value and a file-existence check all
;;;; arrive as ordinary arguments, never read directly, so this system loads
;;;; and its tests pass with no C library present. make check-purity fails
;;;; if the pure suite loads CFFI.

(defpackage #:cl-commonmark-gfm.native-core
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm.conditions
                #:unsupported-extension-node
                #:native-library-not-found
                #:invalid-parse-option
                #:invalid-render-option
                #:resource-limit-exceeded)
  (:import-from #:cl-commonmark-gfm.util
                #:proper-list-p
                #:utf8-length)
  (:export ;; The pin, and the extensions this library can attach
           #:*cmark-gfm-version*
           #:*extension-keywords*
           ;; The version cross-check's pure half
           #:version-number
           #:number-version
           ;; cmark's constants, transcribed from
           ;; vendor/cmark-gfm/src/cmark-gfm.h, and the table mapping each
           ;; one back to its C name
           #:*cmark-header-constants*
           #:+cmark-node-document+
           #:+cmark-node-block-quote+
           #:+cmark-node-list+
           #:+cmark-node-item+
           #:+cmark-node-code-block+
           #:+cmark-node-html-block+
           #:+cmark-node-custom-block+
           #:+cmark-node-paragraph+
           #:+cmark-node-heading+
           #:+cmark-node-thematic-break+
           #:+cmark-node-footnote-definition+
           #:+cmark-node-text+
           #:+cmark-node-softbreak+
           #:+cmark-node-linebreak+
           #:+cmark-node-code+
           #:+cmark-node-html-inline+
           #:+cmark-node-custom-inline+
           #:+cmark-node-emph+
           #:+cmark-node-strong+
           #:+cmark-node-link+
           #:+cmark-node-image+
           #:+cmark-node-footnote-reference+
           #:+cmark-opt-sourcepos+
           #:+cmark-opt-hardbreaks+
           #:+cmark-opt-nobreaks+
           #:+cmark-opt-validate-utf8+
           #:+cmark-opt-smart+
           #:+cmark-opt-footnotes+
           #:+cmark-opt-unsafe+
           #:+cmark-bullet-list+
           #:+cmark-ordered-list+
           #:+cmark-period-delim+
           #:+cmark-paren-delim+
           ;; Node classification
           #:classify-node
           ;; Library discovery
           #:resolve-cmark-libraries
           #:*cmark-gfm-libraries*
           ;; Linked ECL programs
           #:linked-method-p
           ;; Options
           #:check-options
           #:checked-options
           #:checked-profile
           #:checked-extensions
           #:checked-footnotes
           #:checked-smart
           #:checked-sourcepos
           #:checked-softbreak
           #:checked-unsafe-html
           #:checked-width
           #:checked-tree-options
           #:parse-option-bits
           #:html-option-bits
           #:plaintext-option-bits
           #:document-attributes
           ;; Limits
           #:*max-input-octets*
           #:*max-nodes*
           #:*max-output-octets*
           #:effective-maximum
           #:check-limit
           #:table-cell-bound
           ;; The input guard
           #:footnote-entity-index
           ;; The output bounds' per-node terms: HTML, from
           ;; vendor/cmark-gfm/src/html.c and the extensions' html_render
           #:decimal-width
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
           #:html-footnote-backref-bound
           #:html-footnote-section-bound
           #:html-footnote-suffix-bound
           #:html-footnote-backrefs-bound
           #:footnote-reference-bound
           ;; plaintext, from vendor/cmark-gfm/src/plaintext.c,
           ;; vendor/cmark-gfm/src/render.c and the extensions' plaintext
           ;; renderers
           #:plaintext-item-marker-width
           #:plaintext-prefix-width
           #:plaintext-out-bound
           #:plaintext-event-steps
           #:plaintext-steps-bound))
