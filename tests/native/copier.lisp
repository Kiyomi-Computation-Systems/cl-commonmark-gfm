;;;; The copier (M2 design §6, §8.3, §8.4; ADR-0018): COPY-NATIVE-TREE,
;;;; mostly through PARSE. The hand-built fixture ASTs are witness 4; the
;;;; direct tests cover what no corpus-wide witness sees in the AST itself.
;;;; Every expected value here was worked out from the Markdown by hand,
;;;; then confirmed with the pinned CLI: `--sourcepos -t xml` for kinds and
;;;; positions, and `-t html` for footnote labels, which cmark's XML
;;;; doesn't print (M2 design finding 13).

(in-package #:cl-commonmark-gfm.native-tests)

;;; Building Markdown, and reading ASTs. ASTs are walked with WALK-AST, so
;;; a deep one costs no stack (ADR-0015).

(defun markdown-lines (&rest lines)
  "LINES joined, each ended by a newline. Spares Markdown that holds ~ the
escaping a FORMAT control string would need."
  (with-output-to-string (out)
    (dolist (line lines)
      (write-string line out)
      (terpri out))))

(defun preorder-nodes (ast)
  "Every node of AST, each before its children, in document order."
  (let ((nodes '()))
    (walk-ast (lambda (event node)
                (when (eql event :enter)
                  (push node nodes)))
              ast)
    (nreverse nodes)))

(defun ast-nodes-of-kind (ast kind)
  "Every node of AST whose kind is KIND, in document order."
  (remove-if-not (lambda (node) (eql (node-kind node) kind)) (preorder-nodes ast)))

(defun text-of (ast)
  "The literals of AST's :TEXT nodes, in document order, joined."
  (with-output-to-string (out)
    (dolist (node (ast-nodes-of-kind ast :text))
      (write-string (node-attribute node :literal) out))))

;;; Witness 4: the fixture ASTs (M2 design §8.3; the M1 hand-off). Each
;;; case's Markdown, parsed with PARSE's defaults, equals its hand-built AST
;;; in tests/oracle.lisp. A case's own flags are render flags, so they don't
;;; change the parse. The hand-built ASTs leave out positions and the
;;; document's attributes, and cmark splits text nodes where it pleases
;;; (M2 design §6.1), so both sides are compared with positions aside, the
;;; document's attributes cleared, and adjacent text merged.

(defun merged-text-children (children)
  "CHILDREN with each run of adjacent :TEXT nodes replaced by one :TEXT
node, without a position, whose literal joins theirs in order."
  (let ((merged '()))
    (dolist (child children (nreverse merged))
      (if (and merged
               (eql (node-kind child) :text)
               (eql (node-kind (first merged)) :text))
          (setf (first merged)
                (make-node :text
                           :attributes (list :literal
                                             (concatenate 'string
                                                          (node-attribute (first merged) :literal)
                                                          (node-attribute child :literal)))))
          (push child merged)))))

(defun fixture-comparable (ast)
  "AST as witness 4 compares it: its document's attributes cleared, and
adjacent :TEXT nodes merged at every level."
  (transform-ast (lambda (node)
                   (let* ((children (node-children node))
                          (merged (merged-text-children children)))
                     (cond
                       ((eql (node-kind node) :document)
                        (copy-node node
                                   :attributes (list :profile nil :extensions nil :options nil)
                                   :children merged))
                       ((= (length merged) (length children)) node)
                       (t (copy-node node :children merged)))))
                 ast))

(defun fixture-ast (name)
  "Oracle case NAME's hand-built AST, from tests/oracle.lisp."
  (second (assoc name *oracle-cases* :test #'string=)))

(defun fixture-parse-matches-p (name file &optional (change #'identity))
  "True when tests/fixtures/html/FILE, parsed with PARSE's defaults and then
CHANGE, equals oracle case NAME's hand-built AST, both as FIXTURE-COMPARABLE
has them and with positions aside. CHANGE is applied to the parsed side
before the comparison runs: the guard below uses it to change one
attribute, as tests/native/xml.lisp's own guard does."
  (let ((expected (fixture-ast name)))
    (and expected
         (node= (fixture-comparable expected)
                (fixture-comparable
                 (funcall change (parse (fixture-string (format nil "html/~A" file)))))
                :sourcepos nil))))

(define-test every-fixture-ast-is-what-parse-builds
  (let ((compared 0))
    (dolist (case (oracle-fixture-cases))
      (destructuring-bind (name file options) case
        (declare (ignore options))
        (incf compared)
        (true (fixture-parse-matches-p name file) "oracle case ~A" name)))
    (is = (length *oracle-cases*) compared
        "every case of the manifest is compared")))

;;; The guard on witness 4 itself: FIXTURE-PARSE-MATCHES-P must run the same
;;; comparison the real test above makes, so a comparator that always said
;;; "equal" couldn't pass. "headings" (tests/oracle.lisp) holds four
;;; :HEADING nodes, so mirroring their levels on the side PARSE builds must
;;; make the same comparison fail.

(defun change-every-heading-level (ast)
  "AST with every :HEADING's level mirrored, 6 for 1, 5 for 2 and so on,
through COPY-NODE: never the level it had."
  (transform-ast (lambda (node)
                   (if (eql (node-kind node) :heading)
                       (copy-node node :attributes (list :level (- 7 (node-attribute node :level))))
                       node))
                 ast))

(define-test the-fixture-comparison-fails-when-the-parse-changes
  (true (fixture-parse-matches-p "headings" "headings.md") "unchanged, the case matches")
  (false (fixture-parse-matches-p "headings" "headings.md" #'change-every-heading-level)
         "with its headings' levels changed, it fails"))

(defun text-node (literal)
  "A :TEXT node whose literal is LITERAL."
  (make-node :text :attributes (list :literal literal)))

(defun one-block-document (kind attributes &rest children)
  "A :DOCUMENT holding one node of KIND, with ATTRIBUTES and CHILDREN."
  (make-node :document :children (list (make-node kind :attributes attributes
                                                       :children children))))

(define-test the-fixture-comparison-keeps-what-differs
  ;; The guard on witness 4's comparison: merging text must not hide what
  ;; the text says, or where it stops, and clearing the document's
  ;; attributes must clear no other node's.
  (flet ((comparable= (a b)
           (node= (fixture-comparable a) (fixture-comparable b) :sourcepos nil)))
    (let ((split (one-block-document :paragraph '() (text-node "a") (text-node "b"))))
      (true (comparable= split (one-block-document :paragraph '() (text-node "ab"))))
      (false (comparable= split (one-block-document :paragraph '() (text-node "ba"))))
      (false (comparable= split (one-block-document :paragraph '()
                                                    (text-node "a")
                                                    (make-node :emph)
                                                    (text-node "b")))))
    (true (comparable= (make-node :document :attributes '(:profile :gfm))
                       (make-node :document :attributes '(:profile :commonmark))))
    (false (comparable= (one-block-document :heading '(:level 1))
                        (one-block-document :heading '(:level 2))))))

;;; Footnote labels (M2 design §6.3, finding 6): after parsing, a
;;; reference's own literal is its number, and its label is its
;;; definition's literal, as written. cmark matches labels without regard
;;; to case, so the pinned CLI's HTML links [^note] and [^NOTE] to
;;; #fn-Note, and [^Foo] to #fn-foo.

(defun footnote-labels (ast kind)
  "The :LABEL of each node of KIND in AST, in document order."
  (mapcar (lambda (node) (node-attribute node :label)) (ast-nodes-of-kind ast kind)))

(define-test a-reference-is-labelled-as-its-definition-is-written
  (let ((ast (parse (markdown-lines "a[^note] b[^Foo] c[^NOTE]" "" "[^Note]: N." "" "[^foo]: F."))))
    (is equal '("Note" "foo" "Note") (footnote-labels ast :footnote-reference))
    (is equal '("Note" "foo") (footnote-labels ast :footnote-definition))))

;;; Alignment (M2 design §6.3, finding 13): cmark keeps it per column, on
;;; the table, and prints it in its XML on header cells only. Its HTML
;;; aligns every cell by the cell's index in its row (get_cell_alignment,
;;; extensions/table.c), and so does the copy, padded cells included.

(defun row-alignments (ast)
  "The :ALIGN of each cell of AST's first table, one list per row, header
row first."
  (mapcar (lambda (row)
            (mapcar (lambda (cell) (node-attribute cell :align)) (node-children row)))
          (node-children (first (ast-nodes-of-kind ast :table)))))

(define-test body-cells-take-their-columns-alignment
  ;; The second body row holds one cell; cmark pads it with three empty
  ;; ones (try_opening_table_row, extensions/table.c).
  (is equal '((:left :center :right nil)
              (:left :center :right nil)
              (:left :center :right nil))
      (row-alignments (parse (markdown-lines "| l | c | r | n |"
                                             "|:--|:-:|--:|---|"
                                             "| 1 | 2 | 3 | 4 |"
                                             "| 5 |")))))

;;; The document's attributes come from the parse's options, not from
;;; cmark (M2 design §6.3): the extensions attached, in canonical order,
;;; and :OPTIONS listing :FOOTNOTES, then :SMART, when each is on.

(define-test the-document-carries-the-parse-options
  (flet ((attributes (&rest options)
           (node-attributes (apply #'parse "x" options))))
    (is equal '(:profile :gfm
                :extensions (:table :strikethrough :autolink :tagfilter :tasklist)
                :options (:footnotes))
        (attributes))
    (is equal '(:profile :gfm
                :extensions (:table :strikethrough :autolink :tagfilter :tasklist)
                :options (:footnotes :smart))
        (attributes :smart t))
    (is equal '(:profile :commonmark :extensions () :options ())
        (attributes :profile :commonmark))
    (is equal '(:profile :commonmark :extensions () :options (:footnotes :smart))
        (attributes :profile :commonmark :smart t :footnotes t))
    (is equal '(:profile :gfm :extensions (:table :tasklist) :options ())
        (attributes :extensions '(:tasklist :table) :footnotes nil))
    (is equal '(:profile :commonmark :extensions (:strikethrough :autolink) :options ())
        (attributes :profile :commonmark :extensions '(:autolink :strikethrough)))
    (is equal '(:profile :gfm
                :extensions (:table :strikethrough :autolink :tagfilter :tasklist)
                :options (:footnotes))
        (attributes :sourcepos nil)
        ":sourcepos is no attribute")))

;;; Positions (M2 design §6.4). Each list below is every node of the parse,
;;; as (KIND SOURCEPOS), in document order. Columns count octets.

(defun kinds-and-positions (markdown)
  "Every node of MARKDOWN, parsed with PARSE's defaults, as (KIND
SOURCEPOS), in document order."
  (mapcar (lambda (node) (list (node-kind node) (node-sourcepos node)))
          (preorder-nodes (parse markdown))))

(define-test columns-count-octets
  ;; é is two octets, so the emphasis opens at octet 4, which is
  ;; character 3.
  (is equal '((:document ((1 . 1) . (1 . 6)))
              (:paragraph ((1 . 1) . (1 . 6)))
              (:text ((1 . 1) . (1 . 3)))
              (:emph ((1 . 4) . (1 . 6)))
              (:text ((1 . 5) . (1 . 5))))
      (kinds-and-positions (markdown-lines "é *x*"))))

(define-test a-multi-line-code-span-leaves-later-positions-right
  ;; Without CMARK_OPT_SOURCEPOS, cmark skips adjust_subj_node_newlines
  ;; (src/inlines.c), and what follows the span's newline drifts (M2 design
  ;; finding 7). A code span's position is its content's (handle_backticks):
  ;; from 1:2, after the opening backtick, to 2:1, before the closing one.
  (is equal '((:document ((1 . 1) . (2 . 6)))
              (:paragraph ((1 . 1) . (2 . 6)))
              (:code ((1 . 2) . (2 . 1)))
              (:text ((2 . 3) . (2 . 3)))
              (:emph ((2 . 4) . (2 . 6)))
              (:text ((2 . 5) . (2 . 5))))
      (kinds-and-positions (markdown-lines "`a" "b` *c*"))))

(define-test a-softbreak-has-no-position
  ;; cmark gives a softbreak start line 0: no position.
  (is equal '((:document ((1 . 1) . (2 . 1)))
              (:paragraph ((1 . 1) . (2 . 1)))
              (:text ((1 . 1) . (1 . 1)))
              (:softbreak nil)
              (:text ((2 . 1) . (2 . 1))))
      (kinds-and-positions (markdown-lines "a" "b"))))

;;; Positions are copied as cmark reports them, never repaired (ADR-0005
;;; finding 8). tests/fixtures/vocabulary.xml, the pinned CLI's
;;; --sourcepos XML for vocabulary.md, prints them for every node it
;;; holds, in the order PARSE's AST holds them.

(defun xml-sourcepos (line)
  "The position LINE, one of cmark's XML start tags, gives in its
sourcepos=\"L:C-L:C\" attribute, as ((L . C) . (L . C)); NIL when it has
none."
  (let ((start (search "sourcepos=\"" line)))
    (when start
      (let ((index (+ start (length "sourcepos=\"")))
            (numbers '()))
        (loop repeat 4
              do (multiple-value-bind (number end) (parse-integer line :start index :junk-allowed t)
                   (push number numbers)
                   (setf index (1+ end))))
        (destructuring-bind (end-column end-line start-column start-line) numbers
          (cons (cons start-line start-column) (cons end-line end-column)))))))

(defun xml-element-positions (xml)
  "The position of every element of XML, cmark's XML output, in document
order, NIL for an element without one. The elements are those
XML-ELEMENT-NAMES finds: each starts its own line."
  (with-input-from-string (stream xml)
    (loop for line = (read-line stream nil nil)
          while line
          for trimmed = (string-left-trim '(#\Space) line)
          when (and (> (length trimmed) 1)
                    (char= (char trimmed 0) #\<)
                    (not (member (char trimmed 1) '(#\/ #\? #\!))))
            collect (xml-sourcepos trimmed))))

(define-test positions-are-copied-as-cmark-reports-them
  (let ((expected (xml-element-positions (fixture-string "vocabulary.xml"))))
    (is = 76 (length expected) "one position, or none, per element")
    (true (member '((23 . 1) . (22 . 0)) expected :test #'equal)
          "the fixture holds an inverted range, on its second html_block")
    (true (member '((7 . 1) . (9 . 0)) expected :test #'equal)
          "the fixture holds an end column of 0, on its ordered list")
    (is = 5 (count nil expected)
        "none on the linebreak, the softbreak, the email autolink and its two texts")
    (is equal expected
        (mapcar #'node-sourcepos (preorder-nodes (parse (fixture-string "vocabulary.md")))))))

(defun positioned-node-count (markdown &rest options)
  "How many nodes of MARKDOWN's AST, parsed with OPTIONS, have a position."
  (count-if #'node-sourcepos (preorder-nodes (apply #'parse markdown options))))

(define-test sourcepos-nil-leaves-every-position-nil
  (is = 0 (positioned-node-count (fixture-string "vocabulary.md") :sourcepos nil))
  (is = 71 (positioned-node-count (fixture-string "vocabulary.md"))
      "by default, every position vocabulary.xml prints"))

;;; Text (M2 design §6.5): every string cmark returns is decoded as UTF-8,
;;; and NUL and a lone surrogate reach the AST as U+FFFD.

(define-test non-ascii-text-round-trips
  ;; One string attribute of each kind: heading text, a link's destination,
  ;; title and text, a code span, raw HTML, a code block's info and
  ;; literal, a footnote's label, and characters of two, three and four
  ;; octets.
  (let ((ast (parse (markdown-lines "# Café"
                                    ""
                                    "[naïve](/ü \"tïtle\") `cödé` <span title=\"é\">"
                                    ""
                                    "```lïsp"
                                    "(é)"
                                    "```"
                                    ""
                                    "日本 😀"
                                    ""
                                    "x[^ñ]"
                                    ""
                                    "[^ñ]: ü"))))
    (is string= "Café" (text-of (first (ast-nodes-of-kind ast :heading))))
    (let ((link (first (ast-nodes-of-kind ast :link))))
      (is string= "/ü" (node-attribute link :destination))
      (is string= "tïtle" (node-attribute link :title))
      (is string= "naïve" (text-of link)))
    (is string= "cödé" (node-attribute (first (ast-nodes-of-kind ast :code)) :literal))
    (is string= "<span title=\"é\">"
        (node-attribute (first (ast-nodes-of-kind ast :html-inline)) :literal))
    (let ((code-block (first (ast-nodes-of-kind ast :code-block))))
      (is string= "lïsp" (node-attribute code-block :info))
      (is string= (markdown-lines "(é)") (node-attribute code-block :literal)))
    (is string= "日本 😀" (text-of (second (ast-nodes-of-kind ast :paragraph))))
    (is equal '("ñ") (footnote-labels ast :footnote-reference))
    (is equal '("ñ") (footnote-labels ast :footnote-definition))
    (is string= "ü" (text-of (first (ast-nodes-of-kind ast :footnote-definition))))))

(define-test nul-and-a-lone-surrogate-become-the-replacement-character
  ;; cmark replaces a NUL byte with U+FFFD (S_parser_feed, src/blocks.c).
  ;; The encoder writes a lone surrogate as U+FFFD before cmark sees it (M2
  ;; design finding 11). CCL has no lone surrogate: (code-char #xD800) is
  ;; NIL there.
  (let ((expected (concatenate 'string "a" (string (code-char #xFFFD)) "b"))
        (surrogate (code-char #xD800)))
    (is string= expected (text-of (parse (format nil "a~Cb" (code-char 0)))) "NUL")
    (when surrogate
      (is string= expected (text-of (parse (format nil "a~Cb" surrogate))) "a lone surrogate"))))

;; CCL has no lone surrogate: (CODE-CHAR #xD800) is NIL there, so the real
;; assertion below would never run. CCL asserts that fact instead, as
;; tests/util.lisp does, so every Lisp still asserts something real.

#-ccl
(define-test cmark-is-fed-a-lone-surrogate-as-the-replacement-character
  ;; The parse above can't show which guard replaced the surrogate: under
  ;; CMARK_OPT_VALIDATE_UTF8, cmark turns the three octets an encoded
  ;; surrogate would take, ED A0 80, into one U+FFFD too (utf8proc_valid,
  ;; src/utf8.c). The octets fed to cmark show that cmark never sees one
  ;; (M2 design §6.5): U+FFFD is EF BF BD.
  (is equalp #(97 239 191 189 98) (native::encode-input (format nil "a~Cb" (code-char #xD800)))))

#+ccl
(define-test cmark-is-fed-a-lone-surrogate-as-the-replacement-character
  (false (code-char #xD800)))

;;; Failures that can't happen under the pin, made to happen by redefining
;;; an accessor (M2 design §8.4). Each signals NATIVE-PARSE-ERROR naming
;;; PARSE, and frees the document.

(define-test a-reference-without-a-definition-signals-native-parse-error
  ;; cmark turns a dangling reference into text (process_footnotes,
  ;; src/blocks.c), so a parsed reference always has its definition.
  (native-state)
  (with-redefined ((native-footnote-definition (constantly nil)))
    (let ((condition (raised native-parse-error (parse (markdown-lines "x[^a]" "" "[^a]: n")))))
      (when condition
        (is eql 'parse (condition-operation condition))
        (is equal "1" (condition-datum condition) "the reference's literal, its number"))))
  (true (open-counts-zero-p)))

(define-test a-cell-past-its-tables-columns-signals-native-parse-error
  ;; cmark gives every row exactly its table's column count of cells
  ;; (try_opening_table_row, extensions/table.c). Here the table's
  ;; alignments lose their last column, so the second cell of each row has
  ;; none.
  (native-state)
  (let ((alignments (fdefinition 'native-table-alignments)))
    (with-redefined ((native-table-alignments (lambda (document node)
                                                (butlast (funcall alignments document node)))))
      (let ((condition (raised native-parse-error
                               (parse (markdown-lines "| a | b |" "|---|---|")))))
        (when condition
          (is eql 'parse (condition-operation condition))
          (is = 1 (condition-datum condition) "the cell's index in its row")))))
  (true (open-counts-zero-p)))

(define-test copying-a-released-document-signals
  (raised native::native-document-released
          (copy-native-tree (released-document-and-root) (check-options :parse 'test '())))
  (true (open-counts-zero-p)))

;;; ASTs outlive their document (the plan's M2 exit): an AST is Lisp data,
;;; holding nothing of cmark's.

(defun ast-outlives-its-document-p ()
  "True when vocabulary.md's AST still equals a fresh parse's, positions
included, after its document was freed, a full collection ran, and every
oracle fixture's Markdown was parsed and its document freed in turn."
  (let* ((markdown (fixture-string "vocabulary.md"))
         (ast (parse markdown)))
    (trivial-garbage:gc :full t)
    (dolist (case (oracle-fixture-cases))
      (parse (fixture-string (format nil "html/~A" (second case)))))
    (trivial-garbage:gc :full t)
    (node= ast (parse markdown))))

(define-test an-ast-outlives-its-native-document
  (true (ast-outlives-its-document-p))
  (true (open-counts-zero-p)))

;;; Deep inputs (M2 design §8.4): cmark's own stress inputs
;;; (test/pathological_tests.py), each within the default limits. The
;;; copy follows each to its full depth, which no recursive walk would
;;; reach (ADR-0015). Built and parsed inside helpers that return numbers,
;;; so no assertion holds a megabyte of Markdown or its AST.

(defun nested-block-quotes ()
  "cmark's \"nested block quotes\": 50,000 block quote markers, then a.
100,001 octets."
  (concatenate 'string (cl-commonmark-gfm.tests::repeat-string "> " 50000) "a"))

(defun nested-emphasis ()
  "cmark's \"nested strong emph\": 65,000 copies of `*a **a `, then b, then
65,000 of ` a** a*`. 910,001 octets."
  (concatenate 'string
               (cl-commonmark-gfm.tests::repeat-string "*a **a " 65000)
               "b"
               (cl-commonmark-gfm.tests::repeat-string " a** a*" 65000)))

(defun nested-lists ()
  "cmark's \"deeply nested lists\": for X from 0 below 1,000, a line of 2X
spaces, then `* a`. 1,003,000 octets."
  (with-output-to-string (out)
    (dotimes (x 1000)
      (write-string (cl-commonmark-gfm.tests::repeat-string "  " x) out)
      (write-line "* a" out))))

(defun ast-shape (ast)
  "AST's node count, its depth in nodes, and how many nodes of each kind it
holds, as (COUNT DEPTH ((KIND . N) ...)), the kinds sorted by name."
  (let ((count 0)
        (depth 0)
        (deepest 0)
        (kinds '()))
    (walk-ast (lambda (event node)
                (ecase event
                  (:enter
                   (incf count)
                   (setf deepest (max deepest (incf depth)))
                   (let ((entry (assoc (node-kind node) kinds)))
                     (if entry
                         (incf (cdr entry))
                         (push (cons (node-kind node) 1) kinds))))
                  (:exit (decf depth))))
              ast)
    (list count deepest (sort kinds #'string< :key #'car))))

(defun parsed-shape (markdown)
  "AST-SHAPE of MARKDOWN, parsed with PARSE's defaults."
  (ast-shape (parse markdown)))

(define-test cmarks-stress-inputs-copy-to-their-full-depth
  ;; The document, 50,000 block quotes, one inside the next, then a
  ;; paragraph and its text.
  (is equal '(50003 50003
              ((:block-quote . 50000) (:document . 1) (:paragraph . 1) (:text . 1)))
      (parsed-shape (nested-block-quotes))
      "nested block quotes")
  ;; The document and its paragraph, then 130,000 levels: emphasis, strong,
  ;; emphasis, and so on. Each holds the text "a ", the next level, and the
  ;; text " a", but the innermost strong holds one text, "a b a": so
  ;; 2 x 130,000 - 1 texts.
  (is equal '(390001 130003
              ((:document . 1) (:emph . 65000) (:paragraph . 1) (:strong . 65000)
               (:text . 259999)))
      (parsed-shape (nested-emphasis))
      "nested strong and emphasis")
  ;; Each line's indent is its parent item's content column, so each item
  ;; holds its paragraph, then the next list: the document, then 1,000
  ;; lists, items, paragraphs and texts; 2 x 1,000 + 3 levels.
  (is equal '(4001 2003
              ((:document . 1) (:item . 1000) (:list . 1000) (:paragraph . 1000)
               (:text . 1000)))
      (parsed-shape (nested-lists))
      "deeply nested lists")
  (true (open-counts-zero-p)))
