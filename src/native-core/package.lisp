;;;; The cl-commonmark-gfm.native-core package: the native layer's pure
;;;; decisions (M2 design §3, §5.5, §6.2, §7, §8.1; ADR-0008, ADR-0009,
;;;; ADR-0016). It holds cmark's constants, CLASSIFY-NODE and
;;;; RESOLVE-CMARK-LIBRARIES (M2b plan Task 2); CHECK-OPTIONS, the option
;;;; bits, DOCUMENT-ATTRIBUTES and the three resource limits (Task 3); the
;;;; per-node terms of the output bounds (Task 9); and FOOTNOTE-ENTITY-INDEX,
;;;; the input guard's scan (Task 9b).
;;;;
;;;; Pure: no CFFI and no UIOP anywhere in this system. The operating
;;;; system, an environment variable's value and a file-existence check all
;;;; arrive as ordinary arguments, never read directly, so this system loads
;;;; and its tests pass with no C library present (the pure-systems global
;;;; constraint in .plans/progress.md).

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
           ;; The version cross-check's pure half (M3 design §5)
           #:version-number
           #:number-version
           ;; cmark's constants, transcribed from cmark-gfm.h, and the table
           ;; mapping each one back to its C name (M2 design §8.1)
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
           ;; Node classification (M2 design §6.2; ADR-0008)
           #:classify-node
           ;; Library discovery (ADR-0009)
           #:resolve-cmark-libraries
           #:*cmark-gfm-libraries*
           ;; Options (M2 design §6.3, §7.2, §7.3)
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
           ;; Limits (M2 design §5.5; ADR-0016)
           #:*max-input-octets*
           #:*max-nodes*
           #:*max-output-octets*
           #:effective-maximum
           #:check-limit
           #:table-cell-bound
           ;; The input guard (M2 design §5.6; finding 16; M2b plan Task 9b)
           #:footnote-entity-index
           ;; The output bounds' per-node terms (M2 design §5.5; ADR-0016):
           ;; HTML, from src/html.c and the extensions' html_render
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
           ;; plaintext, from src/plaintext.c, src/render.c and the
           ;; extensions' plaintext_render
           #:plaintext-item-marker-width
           #:plaintext-prefix-width
           #:plaintext-out-bound
           #:plaintext-event-steps
           #:plaintext-steps-bound))
