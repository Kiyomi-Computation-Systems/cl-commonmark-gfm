;;;; Two of the four oracles over the pinned corpus (M2 design §8.2, §8.3;
;;;; ADR-0018): witness 1, cmark's own expectations, and witness 2, the HTML
;;;; oracle (tree path against MARKDOWN->HTML). Witness 3 (the XML oracle)
;;;; and witness 4 (the fixture ASTs, already in tests/native/copier.lisp)
;;;; are Task 8's and Task 6's.
;;;;
;;;; Every helper here returns a small summary -- a comparison count and a
;;;; list of small (FILE NUMBER) or (FILE NUMBER SOFTBREAK) identifiers --
;;;; never the corpus examples themselves, so no assertion's closure keeps
;;;; megabytes of Markdown or HTML alive once the run ends (M2b plan, "Large
;;;; values"; .plans/progress.md's global constraint "Tests keep large
;;;; values out of assertions").

(in-package #:cl-commonmark-gfm.native-tests)

;;; Witness 1: cmark's own expectations (M2 design §8.3). MARKDOWN->HTML,
;;; with the example's own options plus :UNSAFE-HTML T -- the flags cmark's
;;; own test harness runs with (finding 8; vendor/cmark-gfm/test/cmark.py) --
;;; must reproduce the expected HTML byte for byte. This guards ADR-0011's
;;; weak spot: a broken corpus reader or a wrong option bit could otherwise
;;; let the tree oracle (witness 2) agree with MARKDOWN->HTML while both are
;;; wrong.

(defparameter *witness-1-files* '("spec.txt" "regression.txt" "smart_punct.txt" "extensions.txt")
  "The first four corpus files, the only ones witness 1 runs over (M2 design
§8.3): extensions-full-info-string.txt and
extensions-table-prefer-style-attributes.txt test CLI flags with no
version-1 option.")

(defun witness-1-examples ()
  "The 741 examples witness 1 compares: *WITNESS-1-FILES*' enabled examples,
but extensions.txt's one <IGNORE> (M2 design §8.3, finding 8), which
vendor/cmark-gfm/test/spec_tests.py itself never compares."
  (remove-if (lambda (example)
              (and (string= (corpus-example-file example) "extensions.txt")
                   (= (corpus-example-number example) 20)))
            (remove-if-not (lambda (example)
                            (member (corpus-example-file example) *witness-1-files*
                                    :test #'string=))
                          (corpus-examples))))

(defun cmark-expectation-mismatch-p (example)
  "True when MARKDOWN->HTML, given EXAMPLE's own options plus :UNSAFE-HTML T,
doesn't reproduce EXAMPLE's expected HTML byte for byte."
  (not (string= (corpus-example-html example)
               (apply #'markdown->html (corpus-example-markdown example) :unsafe-html t
                      (corpus-example-options example)))))

(defun witness-1-failures ()
  "How many of WITNESS-1-EXAMPLES were compared, and each that
CMARK-EXPECTATION-MISMATCH-P, as (FILE NUMBER)."
  (let ((examples (witness-1-examples)))
    (list :compared (length examples)
         :failures (loop for example in examples
                         when (cmark-expectation-mismatch-p example)
                           collect (list (corpus-example-file example)
                                        (corpus-example-number example))))))

(define-test cmarks-own-expectations-match-byte-for-byte
  (destructuring-bind (&key compared failures) (witness-1-failures)
    (is = 741 compared)
    (is equal '() failures)))

;;; Witness 2: the HTML oracle (M2 design §8.3; ADR-0011). For all 747
;;; enabled examples, under each :SOFTBREAK value, the tree path
;;; (MARKDOWN->HTML-TREE then HTML-TREE->STRING) must equal MARKDOWN->HTML.

(defparameter *softbreak-values* '(:newline :space :br)
  "Every :SOFTBREAK value the HTML oracle sweeps (M2 design §7.2, §8.3).")

(defun html-oracle-mismatch-p (example softbreak)
  "True when the tree path disagrees with MARKDOWN->HTML for EXAMPLE, both
under EXAMPLE's own options plus :SOFTBREAK SOFTBREAK."
  (let ((options (list* :softbreak softbreak (corpus-example-options example)))
        (markdown (corpus-example-markdown example)))
    (not (string= (apply #'markdown->html markdown options)
                 (html-tree->string (apply #'markdown->html-tree markdown options))))))

(defun html-oracle-failures ()
  "How many (example, softbreak) pairs were compared, and each that
HTML-ORACLE-MISMATCH-P, as (FILE NUMBER SOFTBREAK)."
  (let ((examples (corpus-examples)))
    (list :compared (* (length examples) (length *softbreak-values*))
         :failures (loop for example in examples
                         append (loop for softbreak in *softbreak-values*
                                     when (html-oracle-mismatch-p example softbreak)
                                       collect (list (corpus-example-file example)
                                                    (corpus-example-number example)
                                                    softbreak))))))

;;; The known footnote divergences (ADR-0014, "Known divergences"; M2 design
;;; §8.3). Both come from information a parsed tree no longer has: cmark
;;; counts repeat references in source order, the copier in tree order; and
;;; a definition referenced only from a dropped definition survives in
;;; cmark, with a dangling backref, but has no reference left in a parsed
;;; tree. Neither depends on :SOFTBREAK, so a real divergence fails at every
;;; value of it.

(defparameter *known-divergences* '()
  "Corpus examples HTML-ORACLE-FAILURES is allowed to differ on, each (FILE
NUMBER REASON). Empty: a scan of the corpus found neither of ADR-0014's two
divergences there. A fix that makes one of these reproduce again must add it
back; this test requires the opposite too, so a listed divergence that stops
reproducing must be removed.")

(defun known-divergence-triples ()
  "*KNOWN-DIVERGENCES*, expanded over *SOFTBREAK-VALUES*."
  (loop for (file number reason) in *known-divergences*
        append (loop for softbreak in *softbreak-values*
                    collect (list file number softbreak))
        do (assert (stringp reason))))

(define-test the-html-oracle-matches-every-example-but-the-known-divergences
  (destructuring-bind (&key compared failures) (html-oracle-failures)
    (is = 2241 compared)
    (is equal '() (set-difference failures (known-divergence-triples) :test #'equal)
        "a failure the known divergences don't name")
    (is equal '() (set-difference (known-divergence-triples) failures :test #'equal)
        "a known divergence that no longer reproduces")))

;;; Direct pins for the known divergences (ADR-0014, "Known divergences").
;;; The corpus hits neither -- *KNOWN-DIVERGENCES* is empty -- so these two
;;; minimized inputs pin each one directly against the tree path, confirmed
;;; against the pinned CLI (`cmark-gfm -e footnotes -e table -e
;;; strikethrough -e autolink -e tagfilter -e tasklist`). Both trace to
;;; process_footnotes (vendor/cmark-gfm/src/blocks.c): its first loop
;;; resolves every :FOOTNOTE-REFERENCE against the tree cmark originally
;;; parsed, assigning each definition's index and each reference's backref
;;; index in that walk's order; only its second loop unlinks an unreferenced
;;; definition (dropping its whole subtree) or appends a referenced one as
;;; the document's last child (so a kept definition always ends up after the
;;; content, wherever it first sat). The pre-pass sees only the tree that
;;; second loop leaves, so it can't recover what the first loop saw.

(defun tree-path (markdown &rest options)
  "The tree path's HTML for MARKDOWN and OPTIONS: (HTML-TREE->STRING
(MARKDOWN->HTML-TREE MARKDOWN . OPTIONS))."
  (html-tree->string (apply #'markdown->html-tree markdown options)))

(define-test repeat-references-counted-in-tree-order-still-diverges
  ;; "[^b]:[^b]" is the definition of b, whose own content is a reference to
  ;; b; "[^b]" on its own afterwards is a second, body reference to b. In
  ;; the source, the embedded reference comes first, so process_footnotes's
  ;; first loop (which runs before any definition moves) numbers it 1 and
  ;; the body reference 2. But its second loop then moves the kept
  ;; definition to the end of the document, so the pre-pass -- walking the
  ;; tree that leaves, body paragraph first -- numbers the body reference 1
  ;; and the embedded one 2: swapped. If a fix ever makes these agree, this
  ;; test must fail, so whoever removes the divergence also updates it.
  (let ((markdown (markdown-lines "[^b]:[^b]" "" "[^b]")))
    (isnt string= (markdown->html markdown) (tree-path markdown)
          "the tree path must keep disagreeing with cmark's repeat-reference order")
    ;; ISNT alone passes on any wrong output that merely differs from
    ;; cmark's, the -K suffix included: a reviewer dropped it from every
    ;; repeat reference's id and this pin still passed. So the tree path's
    ;; exact HTML is pinned too, rendered once here: per the comment above,
    ;; the embedded reference (numbered 2 by the pre-pass) gets the -K
    ;; suffix on its id, and the body reference (numbered 1) doesn't.
    (is string=
        (concatenate 'string
          "<p><sup class=\"footnote-ref\"><a href=\"#fn-b\" id=\"fnref-b\""
          " data-footnote-ref>1</a></sup></p>
<section class=\"footnotes\" data-footnotes>
<ol>
<li id=\"fn-b\">
"
          "<p><sup class=\"footnote-ref\"><a href=\"#fn-b\" id=\"fnref-b-2\""
          " data-footnote-ref>1</a></sup> <a href=\"#fnref-b\" class=\"footnote-backref\""
          " data-footnote-backref data-footnote-backref-idx=\"1\" aria-label=\"Back to reference"
          " 1\">↩</a> <a href=\"#fnref-b-2\" class=\"footnote-backref\" data-footnote-backref"
          " data-footnote-backref-idx=\"1-2\" aria-label=\"Back to reference 1-2\">↩<sup"
          " class=\"footnote-ref\">2</sup></a></p>
</li>
</ol>
</section>
"
         )
        (tree-path markdown)
        "the tree path's exact HTML for this input")))

(define-test a-definition-referenced-only-from-a-dropped-definition-still-diverges
  ;; "[^a]:[^b]:[^a]" defines a, nesting a definition of b inside it, whose
  ;; own content is a reference to a. Nothing ever references b, so
  ;; process_footnotes's first loop still resolves b's nested reference
  ;; against a -- giving a a backref -- before its second loop unlinks b,
  ;; dropping that reference along with it, and keeps a with no reference
  ;; left anywhere in the tree: a dangling backref. The pre-pass, seeing a
  ;; parsed tree with no reference to a at all, drops a too, rendering
  ;; nothing. If a fix ever makes these agree, this test must fail.
  (let ((markdown (markdown-lines "[^a]:[^b]:[^a]")))
    (isnt string= (markdown->html markdown) (tree-path markdown)
          "the tree path must keep disagreeing with cmark's dangling backref")
    ;; Pinned exactly, not just "differs", for the same reason as the
    ;; repeat-reference test above: the pre-pass drops every reference to a,
    ;; so the tree path renders nothing at all for this input.
    (is string= "" (tree-path markdown)
        "the pre-pass sees no reference to a left anywhere in the tree")))

;;; :LINK-POLICY :UNSAFE against :UNSAFE-HTML T (M2 design §8.3; ADR-0011),
;;; only on examples whose AST has no :HTML-BLOCK or :HTML-INLINE node:
;;; :UNSAFE-HTML also emits raw HTML verbatim, which :LINK-POLICY leaves
;;; alone.

(defun example-has-raw-html-p (example)
  "True when EXAMPLE's AST, parsed with its own options, holds an
:HTML-BLOCK or :HTML-INLINE node."
  (let ((ast (apply #'parse (corpus-example-markdown example) (corpus-example-options example))))
    (and (or (ast-nodes-of-kind ast :html-block) (ast-nodes-of-kind ast :html-inline)) t)))

(defun link-policy-oracle-mismatch-p (example)
  "True when MARKDOWN->HTML-TREE with :LINK-POLICY :UNSAFE doesn't equal
MARKDOWN->HTML with :UNSAFE-HTML T, both at the default :SOFTBREAK, under
EXAMPLE's own options."
  (let ((markdown (corpus-example-markdown example))
        (options (corpus-example-options example)))
    (not (string= (apply #'markdown->html markdown :unsafe-html t options)
                 (html-tree->string (apply #'markdown->html-tree markdown :link-policy :unsafe
                                           options))))))

(defun link-policy-oracle-failures ()
  "How many examples with no raw HTML were compared, and each whose
:LINK-POLICY :UNSAFE tree disagrees with :UNSAFE-HTML T, as (FILE NUMBER)."
  (let ((examples (remove-if #'example-has-raw-html-p (corpus-examples))))
    (list :compared (length examples)
         :failures (loop for example in examples
                         when (link-policy-oracle-mismatch-p example)
                           collect (list (corpus-example-file example)
                                        (corpus-example-number example))))))

(define-test link-policy-unsafe-matches-unsafe-html-where-there-is-no-raw-html
  (destructuring-bind (&key compared failures) (link-policy-oracle-failures)
    (is = 668 compared)
    (is equal '() failures)))

;;; The table-cell bound is sound on every corpus example (M2 design §5.5,
;;; §8.4): never below the cells the example's own parse actually builds.

(defun corpus-table-cell-bound-undercounts ()
  "How many examples were checked, and each whose TABLE-CELL-BOUND falls
below the :TABLE-CELL nodes its own parse builds, as (FILE NUMBER CELLS
BOUND)."
  (let ((examples (corpus-examples)))
    (list :compared (length examples)
         :undercounts
         (loop for example in examples
               for markdown = (corpus-example-markdown example)
               for cells = (table-cell-count
                           (apply #'parse markdown (corpus-example-options example)))
               for bound = (table-cell-bound markdown)
               when (< bound cells)
                 collect (list (corpus-example-file example) (corpus-example-number example)
                              cells bound)))))

(define-test the-table-cell-bound-never-undercounts-the-corpus
  (destructuring-bind (&key compared undercounts) (corpus-table-cell-bound-undercounts)
    (is = 747 compared)
    (is equal '() undercounts)))
