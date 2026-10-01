;;;; Deep documents through the entry points (M2 design §8.4): the tree path
;;;; (MARKDOWN->HTML-TREE then HTML-TREE->STRING) gives the same bytes as
;;;; MARKDOWN->HTML, on cmark's own stress inputs -- NESTED-BLOCK-QUOTES,
;;;; NESTED-EMPHASIS and NESTED-LISTS, built in tests/native/copier.lisp --
;;;; each well within the default limits (confirmed there:
;;;; CMARKS-STRESS-INPUTS-COPY-TO-THEIR-FULL-DEPTH).
;;;;
;;;; Each comparison is built inside its own TRUE, never bound in a LET
;;;; around it, so no megabyte-sized string outlives the assertion (M2b
;;;; plan, "Large values"; .plans/progress.md's global constraint "Tests
;;;; keep large values out of assertions").

(in-package #:cl-commonmark-gfm.native-tests)

(define-test nested-block-quotes-tree-path-equals-markdown-html
  (true (string= (markdown->html (nested-block-quotes))
                 (html-tree->string (markdown->html-tree (nested-block-quotes)))))
  (true (open-counts-zero-p)))

(define-test nested-emphasis-tree-path-equals-markdown-html
  (true (string= (markdown->html (nested-emphasis))
                 (html-tree->string (markdown->html-tree (nested-emphasis)))))
  (true (open-counts-zero-p)))

(define-test nested-lists-tree-path-equals-markdown-html
  (true (string= (markdown->html (nested-lists))
                 (html-tree->string (markdown->html-tree (nested-lists)))))
  (true (open-counts-zero-p)))
