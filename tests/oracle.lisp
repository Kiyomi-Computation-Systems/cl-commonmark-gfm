;;;; Oracle tests: AST->HTML-TREE output against the pinned cmark-gfm CLI's HTML.

(in-package #:cl-commonmark-gfm.tests)

;;; Fixture location

(defparameter *fixtures-html-directory*
  (asdf:system-relative-pathname "cl-commonmark-gfm/tests" "tests/fixtures/html/")
  "The directory holding the oracle manifest, the Markdown inputs and the
expected HTML files (design §7.3).")

;;; The manifest

(defun manifest-whitespace-char-p (char)
  "True when CHAR is a space or a tab, the field separators in
tests/fixtures/html/cases (design §7.3)."
  (or (char= char #\Space) (char= char #\Tab)))

(defun manifest-first-field (line)
  "LINE's first field: up to (but not including) its first run of spaces or
tabs, once LINE's own leading spaces and tabs are trimmed -- as the shell's
READ splits a manifest line (design §7.3)."
  (let ((trimmed (string-left-trim '(#\Space #\Tab) line)))
    (subseq trimmed 0 (position-if #'manifest-whitespace-char-p trimmed))))

(defun oracle-manifest-case-names ()
  "Return the case names listed in tests/fixtures/html/cases, in file order:
the first field of every line that is not blank and does not start with #,
once leading whitespace is trimmed."
  (with-open-file (stream (merge-pathnames "cases" *fixtures-html-directory*)
                           :external-format :utf-8)
    (loop for line = (read-line stream nil nil)
          while line
          for trimmed = (string-left-trim '(#\Space #\Tab) line)
          unless (or (zerop (length trimmed)) (char= (char trimmed 0) #\#))
            collect (manifest-first-field trimmed))))

;;; Case ASTs, transcribed by hand from `cmark-gfm <flags> -t xml
;;; tests/fixtures/html/<file>` for every case in tests/fixtures/html/cases
;;; (design §7.3). Footnote nodes print as <unknown> in that XML; their
;;; labels are taken from the Markdown instead (design §5.4), and footnote
;;; definitions are placed where the XML shows them: at the end, in cmark's
;;; order (first-reference order in the source, not declaration order).
;;;
;;; A table cell's :align is carried by its column, not by the individual
;;; XML node: cmark's XML only prints align= on header cells, but the
;;; rendered HTML applies the same alignment to body cells too (the plan's
;;; AST vocabulary, ADR-0005), so body cells get their column's :align here
;;; as well.

(defparameter *oracle-cases*
  (let* ((links-dangerous-ast
           (n :document nil
              (n :paragraph nil
                 (n :link (list :destination "javascript:alert(1)" :title "") (txt "js"))
                 (n :softbreak nil)
                 (n :link (list :destination "vbscript:msgbox" :title "") (txt "vb"))
                 (n :softbreak nil)
                 (n :link (list :destination "file:///etc/passwd" :title "") (txt "file"))
                 (n :softbreak nil)
                 (n :link (list :destination "data:text/html,hi" :title "") (txt "data-html"))
                 (n :softbreak nil)
                 (n :link (list :destination "data:image/png;base64,aaaa" :title "")
                    (txt "data-png")))))
         (softbreak-ast
           (n :document nil
              (n :paragraph nil (txt "Line one") (n :softbreak nil) (txt "Line two")))))
    (list
     (list "paragraphs"
           (n :document nil
              (n :paragraph nil (txt "First paragraph."))
              (n :paragraph nil (txt "Second paragraph.")))
           '())
     (list "headings"
           (n :document nil
              (n :heading (list :level 1) (txt "ATX One"))
              (n :heading (list :level 3) (txt "ATX Three"))
              (n :heading (list :level 1) (txt "Setext One"))
              (n :heading (list :level 2) (txt "Setext Two")))
           '())
     (list "blockquotes"
           (n :document nil
              (n :block-quote nil
                 (n :paragraph nil (txt "Outer text."))
                 (n :block-quote nil
                    (n :paragraph nil (txt "Inner text."))))
              (n :block-quote nil))
           '())
     (list "code-blocks"
           (n :document nil
              (n :code-block (list :info "lisp" :literal (format nil "(+ 1 2)~%")))
              (n :code-block (list :info "lisp extra words" :literal (format nil "(+ 3 4)~%")))
              (n :code-block (list :info (concatenate 'string "lisp" (string (code-char 9)) "more")
                                   :literal (format nil "(+ 5 6)~%")))
              (n :code-block (list :info "" :literal (format nil "bare~%")))
              (n :code-block (list :info "" :literal (format nil "indented code~%")))
              (n :code-block (list :info "text" :literal "")))
           '())
     (list "thematic-break"
           (n :document nil
              (n :paragraph nil (txt "Some text."))
              (n :thematic-break nil))
           '())
     (list "emphasis"
           ;; cmark parses **** as nested STRONGs (below), collapsed to one
           ;; <strong> only by the HTML renderer (design finding 5).
           (n :document nil
              (n :paragraph nil
                 (n :emph nil (txt "em"))
                 (txt " and ")
                 (n :strong nil (txt "strong"))
                 (txt " and ")
                 (n :strong nil (n :strong nil (txt "s")))
                 (txt " and ")
                 (n :strikethrough nil (txt "strike"))
                 (txt " and ")
                 (n :code (list :literal "code"))
                 (txt ".")))
           '())
     (list "breaks-hard"
           (n :document nil
              (n :paragraph nil (txt "Line one") (n :linebreak nil) (txt "Line two")))
           '())
     (list "lists-tight"
           (n :document nil
              (n :list (list :tight t)
                 (n :item nil (n :paragraph nil (txt "one")))
                 (n :item nil
                    (n :paragraph nil (txt "two"))
                    (n :list (list :tight t)
                       (n :item nil (n :paragraph nil (txt "nested a")))
                       (n :item nil (n :paragraph nil (txt "nested b")))))
                 (n :item nil (n :paragraph nil (txt "three")))))
           '())
     (list "lists-loose"
           (n :document nil
              (n :list (list :tight nil)
                 (n :item nil (n :paragraph nil (txt "one")))
                 (n :item nil (n :paragraph nil (txt "two")))
                 (n :item nil (n :paragraph nil (txt "three")))))
           '())
     (list "lists-ordered"
           (n :document nil
              (n :list (list :type :ordered :start 1 :delimiter :period :tight t)
                 (n :item nil (n :paragraph nil (txt "one"))))
              (n :paragraph nil (txt "Sep."))
              (n :list (list :type :ordered :start 3 :delimiter :period :tight t)
                 (n :item nil (n :paragraph nil (txt "three"))))
              (n :paragraph nil (txt "Sep."))
              (n :list (list :type :ordered :start 0 :delimiter :period :tight t)
                 (n :item nil (n :paragraph nil (txt "zero"))))
              (n :paragraph nil (txt "Sep."))
              (n :list (list :type :ordered :start 1 :delimiter :paren :tight t)
                 (n :item nil (n :paragraph nil (txt "one")))))
           '())
     (list "tasks-tight"
           (n :document nil
              (n :list (list :tight t)
                 (n :task-item (list :checked nil) (n :paragraph nil (txt "todo")))
                 (n :task-item (list :checked t) (n :paragraph nil (txt "done")))))
           '())
     (list "tasks-loose"
           (n :document nil
              (n :list (list :tight nil)
                 (n :task-item (list :checked nil) (n :paragraph nil (txt "todo")))
                 (n :task-item (list :checked t) (n :paragraph nil (txt "done")))))
           '())
     (list "raw-html"
           (n :document nil
              (n :html-block (list :literal (format nil "<div>block html</div>~%")))
              (n :paragraph nil
                 (txt "Some ")
                 (n :html-inline (list :literal "<span>"))
                 (txt "inline")
                 (n :html-inline (list :literal "</span>"))
                 (txt " html."))
              (n :list (list :tight t)
                 (n :item nil (n :html-block (list :literal (format nil "<div>~%"))))
                 (n :item nil
                    (n :paragraph nil
                       (txt "a ")
                       (n :html-inline (list :literal "<b>"))))))
           '())
     (list "links"
           (n :document nil
              (n :paragraph nil
                 (n :link (list :destination "http://example.com/a" :title "A Title")
                    (txt "title link"))
                 (n :softbreak nil)
                 (n :link (list :destination "http://example.com/b" :title "") (txt "no title"))
                 (n :softbreak nil)
                 (n :link (list :destination "http://example.org/c" :title "")
                    (txt "http://example.org/c"))
                 (n :softbreak nil)
                 (n :link (list :destination "http://www.example.com" :title "")
                    (txt "www.example.com"))
                 (n :softbreak nil)
                 (n :link (list :destination "http://example.com/x?y=1&z=2" :title "") (txt "amp"))
                 (n :softbreak nil)
                 (n :link (list :destination "http://example.com/o'brien" :title "") (txt "apos"))
                 (n :softbreak nil)
                 (n :link (list :destination "http://example.com/has space" :title "")
                    (txt "spaced"))
                 (n :softbreak nil)
                 (n :link (list :destination "http://example.com/café" :title "") (txt "unicode"))
                 (n :softbreak nil)
                 (n :link (list :destination "http://example.com/already%20encoded" :title "")
                    (txt "percent"))))
           '())
     (list "images"
           (n :document nil
              (n :paragraph nil
                 (n :image (list :destination "http://example.com/img.png" :title "Image title")
                    (n :emph nil (txt "em"))
                    (txt " ")
                    (n :code (list :literal "code"))
                    (txt " a")
                    (n :linebreak nil)
                    (txt "b ")
                    (n :html-inline (list :literal "<b>"))
                    (txt "html")
                    (n :html-inline (list :literal "</b>"))
                    (txt " ")
                    (n :link (list :destination "http://x.com" :title "") (txt "link")))))
           '())
     (list "links-dangerous" links-dangerous-ast '())
     (list "links-unsafe" links-dangerous-ast (list :link-policy :unsafe))
     (list "tables"
           (n :document nil
              (n :table nil
                 (n :table-header nil
                    (n :table-cell (list :align :left) (txt "Left"))
                    (n :table-cell (list :align :center) (txt "Center"))
                    (n :table-cell (list :align :right) (txt "Right"))
                    (n :table-cell nil (txt "None")))
                 (n :table-row nil
                    (n :table-cell (list :align :left) (n :emph nil (txt "em")))
                    (n :table-cell (list :align :center) (n :code (list :literal "code")))
                    (n :table-cell (list :align :right) (txt "a|b"))
                    (n :table-cell nil (txt "text")))))
           '())
     (list "table-header-only"
           (n :document nil
              (n :table nil
                 (n :table-header nil
                    (n :table-cell nil (txt "a"))
                    (n :table-cell nil (txt "b")))))
           '())
     (list "softbreak-space" softbreak-ast (list :softbreak :space))
     (list "softbreak-br" softbreak-ast (list :softbreak :br))
     (list "footnotes-basic"
           (n :document nil
              (n :paragraph nil
                 (txt "Basic note")
                 (n :footnote-reference (list :label "a"))
                 (txt "."))
              (n :footnote-definition (list :label "a")
                 (n :paragraph nil (txt "The note."))))
           '())
     (list "footnotes-repeat"
           (n :document nil
              (n :paragraph nil
                 (txt "First")
                 (n :footnote-reference (list :label "a"))
                 (txt " and second")
                 (n :footnote-reference (list :label "a"))
                 (txt " and third")
                 (n :footnote-reference (list :label "a"))
                 (txt "."))
              (n :footnote-definition (list :label "a")
                 (n :paragraph nil (txt "The note."))))
           '())
     (list "footnotes-order"
           ;; x[^a] / [^a]: see [^c] / y[^b] / [^b]: B / [^c]: C -- cmark
           ;; numbers definitions by first reference in source order (a, c,
           ;; b), so the parsed tree holds the definitions in that order and
           ;; c is numbered 2 (design finding 4, ADR-0014).
           (n :document nil
              (n :paragraph nil (txt "x") (n :footnote-reference (list :label "a")))
              (n :paragraph nil (txt "y") (n :footnote-reference (list :label "b")))
              (n :footnote-definition (list :label "a")
                 (n :paragraph nil (txt "see ") (n :footnote-reference (list :label "c"))))
              (n :footnote-definition (list :label "c")
                 (n :paragraph nil (txt "C")))
              (n :footnote-definition (list :label "b")
                 (n :paragraph nil (txt "B"))))
           '())
     (list "footnotes-nested"
           (n :document nil
              (n :paragraph nil
                 (txt "This is some text. It has a citation.")
                 (n :footnote-reference (list :label "citation")))
              (n :footnote-definition (list :label "citation")
                 (n :paragraph nil
                    (txt "This is a long winded parapgraph that also has another citation.")
                    (n :footnote-reference (list :label "another-citation"))))
              (n :footnote-definition (list :label "another-citation")
                 (n :paragraph nil (txt "My second citation."))))
           '())
     (list "footnotes-nonparagraph"
           (n :document nil
              (n :paragraph nil (txt "x") (n :footnote-reference (list :label "b")))
              (n :footnote-definition (list :label "b")
                 (n :paragraph nil (txt "A paragraph."))
                 (n :code-block (list :info "" :literal (format nil "code~%")))))
           '())
     (list "footnotes-empty"
           (n :document nil
              (n :paragraph nil (txt "x") (n :footnote-reference (list :label "b")))
              (n :footnote-definition (list :label "b")))
           '())
     (list "footnotes-labels"
           (n :document nil
              (n :paragraph nil
                 (txt "Ref one")
                 (n :footnote-reference (list :label "it's"))
                 (txt " and ref two")
                 (n :footnote-reference (list :label "café"))
                 (txt "."))
              (n :footnote-definition (list :label "it's")
                 (n :paragraph nil (txt "Apostrophe note.")))
              (n :footnote-definition (list :label "café")
                 (n :paragraph nil (txt "Accented note."))))
           '())))
  "One (NAME AST OPTIONS) entry per tests/fixtures/html/cases line. OPTIONS is
the &rest plist ast->html-tree takes.")

;;; Test A: the manifest and the Lisp cases name the same set, with no
;;; duplicates on either side.

(define-test oracle-manifest-and-lisp-cases-agree
  (let ((manifest-names (oracle-manifest-case-names))
        (lisp-names (mapcar #'first *oracle-cases*)))
    (is = (length manifest-names) (length (remove-duplicates manifest-names :test #'string=))
        "the manifest must not repeat a case name")
    (is = (length lisp-names) (length (remove-duplicates lisp-names :test #'string=))
        "the Lisp oracle table must not repeat a case name")
    (false (set-difference manifest-names lisp-names :test #'string=)
           "every manifest case needs a matching Lisp oracle entry")
    (false (set-difference lisp-names manifest-names :test #'string=)
           "every Lisp oracle entry needs a matching manifest case")))

;;; Test B: every case's hand-built AST converts to its committed HTML, byte
;;; for byte. The .html files are the pinned cmark-gfm CLI's output, and
;;; `make check-fixtures' keeps them honest.

(define-test oracle-cases-match-cmark-gfm-html
  (dolist (entry *oracle-cases*)
    (destructuring-bind (name ast options) entry
      (is string=
          (uiop:read-file-string
           (merge-pathnames (format nil "~a.html" name) *fixtures-html-directory*)
           :external-format :utf-8)
          (html-tree->string (apply #'ast->html-tree ast options))
          "oracle case ~a" name))))
