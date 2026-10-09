;;;; Witness 3, the XML oracle. A test-only writer prints a copied AST in
;;;; cmark's XML, as cmark_render_xml prints the tree the AST was copied
;;;; from. On every enabled corpus example, its output must equal
;;;; cmark_render_xml's for the same native document, byte for byte. The
;;;; expectation comes from cmark, so the writer can't be tuned to hide a
;;;; copier bug.
;;;;
;;;; The writer follows vendor/cmark-gfm's C, not its output: src/xml.c
;;;; (cmark_render_xml_with_mem, S_render_node, indent, escape_xml and
;;;; MAX_INDENT), src/node.c (cmark_node_get_type_string) and the
;;;; extensions' get_type_string and xml_attr functions. cmark's XML hides
;;;; or adds three things: footnote nodes print as <<unknown>, without their
;;;; label; align appears on header-row cells only; task items carry
;;;; completed.

(in-package #:cl-commonmark-gfm.native-tests)

;;; The writer

(defconstant +xml-max-indent+ 40
  "MAX_INDENT (src/xml.c): indent writes no more spaces than this, so every
node below the 20th level is indented as one at the 20th is.")

(defun kind-type-string (kind)
  "The element name S_render_node (src/xml.c) gives a node of KIND:
cmark_node_get_type_string (src/node.c), which asks the node's extension
first. Each extension's get_type_string gives its own: \"tasklist\"
(extensions/tasklist.c); \"table\", \"table_header\" for the row whose
is_header is set, \"table_row\" and \"table_cell\" (extensions/table.c);
\"strikethrough\" (extensions/strikethrough.c). Footnote nodes have no
extension and no case in cmark_node_get_type_string, which ends in
\"<unknown>\". :EXTENSION, which can't occur under the pin (CLASSIFY-NODE
says why), has no entry: its extension's xml_attr is out of this writer's
reach."
  (ecase kind
    (:document "document")
    (:block-quote "block_quote")
    (:list "list")
    (:item "item")
    (:task-item "tasklist")
    (:code-block "code_block")
    (:html-block "html_block")
    (:paragraph "paragraph")
    (:heading "heading")
    (:thematic-break "thematic_break")
    (:table "table")
    (:table-header "table_header")
    (:table-row "table_row")
    (:table-cell "table_cell")
    (:footnote-definition "<unknown>")
    (:text "text")
    (:softbreak "softbreak")
    (:linebreak "linebreak")
    (:code "code")
    (:html-inline "html_inline")
    (:emph "emph")
    (:strong "strong")
    (:strikethrough "strikethrough")
    (:link "link")
    (:image "image")
    (:footnote-reference "<unknown>")))

(defun literal-kind-p (kind)
  "True for the kinds S_render_node (src/xml.c) prints with their text
inside the start tag's element, closed as soon as it opens: text, code,
raw HTML and code blocks."
  (member kind '(:text :code :html-block :html-inline :code-block)))

(defun write-xml-escaped (string stream)
  "Write STRING to STREAM as escape_xml (src/xml.c) does, through
houdini_escape_html0 with secure 0 (src/houdini_html_e.c): \", &, < and >
escaped, and nothing else. ' and / are in its table, but only secure mode
escapes them. A UTF-8 character of more than one octet holds no octet
below 128, so escaping characters escapes the same octets."
  (loop for char across string
        do (case char
             (#\" (write-string "&quot;" stream))
             (#\& (write-string "&amp;" stream))
             (#\< (write-string "&lt;" stream))
             (#\> (write-string "&gt;" stream))
             (otherwise (write-char char stream)))))

(defun write-xml-indent (depth stream)
  "Write indent's spaces (src/xml.c) for a node DEPTH levels below the
document: two a level, and never more than +XML-MAX-INDENT+."
  (loop repeat (min (* 2 depth) +xml-max-indent+)
        do (write-char #\Space stream)))

(defun write-xml-sourcepos (node stream)
  "Write NODE's sourcepos attribute, or nothing when NODE has none.
S_render_node (src/xml.c) writes it only under CMARK_OPT_SOURCEPOS, without
which the copy holds no positions, and only for a start line other than
0, which the copy holds as NIL."
  (let ((sourcepos (node-sourcepos node)))
    (when sourcepos
      (destructuring-bind ((start-line . start-column) . (end-line . end-column)) sourcepos
        (format stream " sourcepos=\"~D:~D-~D:~D\""
                start-line start-column end-line end-column)))))

(defun write-xml-extension-attributes (node parent stream)
  "Write what NODE's extension's xml_attr returns, which S_render_node
(src/xml.c) writes before the type's own attributes. PARENT is NODE's
parent, or NIL for the document.
- A task item: completed, true or false (xml_attr,
  extensions/tasklist.c).
- A table cell: align, only when PARENT is the header row and the cell's
  column is aligned (xml_attr, extensions/table.c). A body cell's :ALIGN
  never shows.
The table's other nodes get NULL from the same xml_attr, strikethrough.c
sets none, and the other kinds have no extension."
  (ecase (node-kind node)
    (:task-item
     (write-string (if (node-attribute node :checked) " completed=\"true\"" " completed=\"false\"")
                   stream))
    (:table-cell
     (let ((align (node-attribute node :align)))
       (when (and align (eql (node-kind parent) :table-header))
         (format stream " align=\"~A\"" (ecase align
                                          (:left "left")
                                          (:center "center")
                                          (:right "right"))))))
    ((:table :table-header :table-row :strikethrough
      :document :block-quote :list :item :code-block :html-block :paragraph :heading
      :thematic-break :footnote-definition :text :softbreak :linebreak :code :html-inline
      :emph :strong :link :image :footnote-reference)
     nil)))

(defun write-xml-list-attributes (node stream)
  "Write a :LIST's attributes as S_render_node's CMARK_NODE_LIST case
(src/xml.c) does: type; for an ordered list, start and delim; then tight.
cmark writes no delim for CMARK_NO_DELIM, which an ordered list's
:DELIMITER can't be (the schema's list rule)."
  (ecase (node-attribute node :type)
    (:ordered
     (format stream " type=\"ordered\" start=\"~D\"" (node-attribute node :start))
     (ecase (node-attribute node :delimiter)
       (:paren (write-string " delim=\"paren\"" stream))
       (:period (write-string " delim=\"period\"" stream))))
    (:bullet
     (write-string " type=\"bullet\"" stream)))
  (format stream " tight=\"~:[false~;true~]\"" (node-attribute node :tight)))

(defun write-xml-attribute (name value stream)
  "Write ` NAME=\"VALUE\"`, VALUE escaped, as S_render_node (src/xml.c)
writes info, destination and title."
  (format stream " ~A=\"" name)
  (write-xml-escaped value stream)
  (write-char #\" stream))

(defun write-xml-literal (node name stream)
  "Write the rest of a literal NODE's element, named NAME, after its
attributes, as S_render_node (src/xml.c) does: its text, escaped, and its
end tag up to the >."
  (write-string " xml:space=\"preserve\">" stream)
  (write-xml-escaped (node-attribute node :literal) stream)
  (write-string "</" stream)
  (write-string name stream))

(defun write-xml-type-attributes (node name stream)
  "Write what S_render_node's switch on the node type (src/xml.c) writes
for NODE, named NAME: the document's namespace, a list's, heading's, link's
or image's attributes, or a literal's text and end tag. Every other kind
falls to the switch's default, and writes nothing."
  (ecase (node-kind node)
    (:document (write-string " xmlns=\"http://commonmark.org/xml/1.0\"" stream))
    ((:text :code :html-block :html-inline) (write-xml-literal node name stream))
    (:list (write-xml-list-attributes node stream))
    (:heading (format stream " level=\"~D\"" (node-attribute node :level)))
    (:code-block
     (let ((info (node-attribute node :info)))
       (when (plusp (length info))
         (write-xml-attribute "info" info stream)))
     (write-xml-literal node name stream))
    ((:link :image)
     (write-xml-attribute "destination" (node-attribute node :destination) stream)
     (write-xml-attribute "title" (node-attribute node :title) stream))
    ((:block-quote :item :task-item :paragraph :thematic-break :table :table-header :table-row
      :table-cell :footnote-definition :softbreak :linebreak :emph :strong :strikethrough
      :footnote-reference)
     nil)))

(defun write-xml-start (node parent depth stream)
  "Write what S_render_node (src/xml.c) writes on entering NODE, DEPTH
levels below the document, under PARENT: its start tag, which closes
itself when NODE has no children, unless NODE is a literal, whose whole
element it is."
  (let ((name (kind-type-string (node-kind node))))
    (write-xml-indent depth stream)
    (write-char #\< stream)
    (write-string name stream)
    (write-xml-sourcepos node stream)
    (write-xml-extension-attributes node parent stream)
    (write-xml-type-attributes node name stream)
    (unless (or (node-children node) (literal-kind-p (node-kind node)))
      (write-string " /" stream))
    (write-char #\> stream)
    (terpri stream)))

(defun write-xml-end (node depth stream)
  "Write what S_render_node (src/xml.c) writes on leaving NODE, DEPTH levels
below the document: its end tag, on a line of its own, when NODE has
children. Any other element closed when it opened."
  (when (node-children node)
    (write-xml-indent depth stream)
    (write-string "</" stream)
    (write-string (kind-type-string (node-kind node)) stream)
    (write-char #\> stream)
    (terpri stream)))

(defun ast->cmark-xml (ast)
  "AST in cmark's XML, as cmark_render_xml_with_mem (src/xml.c) prints the
tree AST was copied from: the XML declaration and doctype, then each node
as S_render_node writes it. One WALK-AST, so depth costs no stack."
  (with-output-to-string (stream)
    (write-line "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" stream)
    (write-line "<!DOCTYPE document SYSTEM \"CommonMark.dtd\">" stream)
    (let ((ancestors '())
          (depth 0))
      (walk-ast (lambda (event node)
                  (ecase event
                    (:enter
                     (write-xml-start node (first ancestors) depth stream)
                     (push node ancestors)
                     (incf depth))
                    (:exit
                     (pop ancestors)
                     (decf depth)
                     (write-xml-end node depth stream)))
                  nil)
                ast))))

;;; The comparison: one native document, printed twice

(defun xml-oracle-match-p (markdown options change)
  "True when the writer's XML for MARKDOWN's copied AST equals cmark's own
XML of the same native document, both from one parse with OPTIONS plus
:SOURCEPOS T. CHANGE is applied to the copied AST before it is written:
the guard uses it to change one attribute."
  (call-with-native-document
   markdown (list* :sourcepos t options)
   (lambda (document checked-options)
     (string= (ast->cmark-xml (funcall change (copy-native-tree document checked-options)))
              (render-xml document)))))

(defun xml-oracle-failures (&key (examples (corpus-examples)) (change #'identity))
  "How many of EXAMPLES, every enabled corpus example by default, were
compared, and each that XML-ORACLE-MATCH-P rejects under its own options
and CHANGE, as (FILE NUMBER)."
  (list :compared (length examples)
        :failures (loop for example in examples
                        unless (xml-oracle-match-p (corpus-example-markdown example)
                                                   (corpus-example-options example)
                                                   change)
                          collect (list (corpus-example-file example)
                                        (corpus-example-number example)))))

(define-test the-xml-oracle-matches-every-corpus-example
  (destructuring-bind (&key compared failures) (xml-oracle-failures)
    (is = 747 compared)
    (is equal '() failures))
  (true (open-counts-zero-p)))

;;; The guard: a comparison that always said "equal" would pass the corpus
;;; test whatever the copier did. Changing one attribute of a copied AST
;;; must make the same comparison fail.

(defun mirrored-heading-levels (ast)
  "AST with each heading's level mirrored, 6 for 1, 5 for 2 and so on,
through COPY-NODE: never the level it had."
  (transform-ast (lambda (node)
                   (if (eql (node-kind node) :heading)
                       (copy-node node :attributes (list :level (- 7 (node-attribute node :level))))
                       node))
                 ast))

(defun guard-example-failures (change)
  "XML-ORACLE-FAILURES over spec.txt example 36 alone, `# foo *bar*
\\*baz\\*`, whose AST holds one heading, of level 1, under CHANGE."
  (xml-oracle-failures :examples (list (cl-commonmark-gfm.tests::find-corpus-example "spec.txt" 36))
                       :change change))

(define-test the-xml-oracle-reports-a-changed-heading-level
  (is equal '(:compared 1 :failures ()) (guard-example-failures #'identity)
      "unchanged, the example matches")
  (is equal '(:compared 1 :failures (("spec.txt" 36)))
      (guard-example-failures #'mirrored-heading-levels)
      "with its heading's level changed, it fails"))

;;; A second check on the writer: tests/fixtures/vocabulary.xml is the
;;; pinned CLI's `--sourcepos` XML for vocabulary.md under the GFM flags
;;; (make check-vocabulary), so it doesn't come through this process's
;;; RENDER-XML. vocabulary.md holds every kind but :EXTENSION.

(define-test the-xml-writer-reproduces-the-vocabulary-fixture
  (is string= (fixture-string "vocabulary.xml")
      (ast->cmark-xml (parse (fixture-string "vocabulary.md") :sourcepos t))))

;;; The indentation cap. MAX_INDENT (src/xml.c) stops indentation at 40
;;; spaces, the 20th level's, so a writer without the cap agrees on every
;;; shallower tree. 25 nested block quotes put the quotes from the 21st
;;; on, their paragraph and its text past it.

(defun nested-quotes (depth)
  "DEPTH block quote markers, then ` deep`: DEPTH nested block quotes
around one paragraph."
  (concatenate 'string (make-string depth :initial-element #\>) " deep" (string #\Newline)))

(define-test the-xml-writer-caps-indentation-at-40-spaces
  (true (xml-oracle-match-p (nested-quotes 25) '() #'identity)))

;;; The table extension can rebuild a paragraph with no position, giving
;;; an inline inside it a negative column. The AST keeps the column as
;;; cmark reports it, and the writer must still match cmark's XML.

(define-test the-xml-writer-matches-cmark-for-an-autolink-with-a-negative-column
  (true (xml-oracle-match-p (format nil "a~%www.g~%b~%|-") '() #'identity))
  (true (open-counts-zero-p)))
