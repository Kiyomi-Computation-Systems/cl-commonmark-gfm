;;;; The output bounds: HTML-OUTPUT-BOUND and PLAINTEXT-OUTPUT-BOUND, upper
;;;; bounds on the UTF-8 octets RENDER-HTML and RENDER-PLAINTEXT would write
;;;; for a live document. Each is one WALK-NATIVE that reads every node's
;;;; facts and sums /native-core's per-node terms
;;;; (src/native-core/output-bounds.lisp). MARKDOWN->HTML and
;;;; MARKDOWN->PLAINTEXT check them against *MAX-OUTPUT-OCTETS* between the
;;;; parse and the render: cmark_strbuf_grow aborts the process inside the
;;;; render (vendor/cmark-gfm/src/buffer.c), where nothing can stop it. Like
;;;; every walk, these keep their state on explicit stacks, so depth costs
;;;; no Lisp stack.

(in-package #:cl-commonmark-gfm.native)

;;; HTML

(defstruct (html-bound-walk
            (:constructor make-html-bound-walk (document sourcepos unsafe tagfilter softbreak))
            (:copier nil))
  "What HTML-OUTPUT-BOUND keeps while it walks DOCUMENT: the options that
change cmark's markup; the octets counted so far, TOTAL; the kind of every
node entered and not yet left, innermost first, each as (KIND . TIGHT),
TIGHT true for a tight list; how many IMAGES enclose the node, whose alt
text cmark writes in plain mode; the current table's ALIGNMENTS and the
next cell's COLUMN in its row; and the footnote DEFINITIONS and REFERENCES
counted, with the LONGEST-LABEL of the definitions, in octets."
  document
  sourcepos
  unsafe
  tagfilter
  softbreak
  (total 0)
  (ancestors '())
  (images 0)
  (alignments #())
  (column 0)
  (definitions 0)
  (references 0)
  (longest-label 0))

(defun walk-sourcepos-octets (walk node)
  "The data-sourcepos NODE gets under WALK's options: its positions'
HTML-SOURCEPOS-OCTETS under :SOURCEPOS T, as cmark_html_render_sourcepos
reads them; 0 without."
  (let ((document (html-bound-walk-document walk)))
    (if (html-bound-walk-sourcepos walk)
        (html-sourcepos-octets (native-start-line document node)
                               (native-start-column document node)
                               (native-end-line document node)
                               (native-end-column document node))
        0)))

(defun literal-octets-of (document node)
  "The UTF-8 octets of NODE's literal."
  (utf8-length (native-literal document node)))

(defun tight-paragraph-p (walk)
  "True when the paragraph about to be entered under WALK's ancestors is in
a tight list: S_render_node (vendor/cmark-gfm/src/html.c) writes no tags
for a paragraph whose grandparent is a CMARK_NODE_LIST that is tight."
  (let ((grandparent (second (html-bound-walk-ancestors walk))))
    (and grandparent (eql (car grandparent) :list) (cdr grandparent))))

(defun nested-strong-p (walk)
  "True when the strong emphasis about to be entered under WALK's ancestors
is a direct child of another: S_render_node (vendor/cmark-gfm/src/html.c)
writes no tags for it."
  (eql (car (first (html-bound-walk-ancestors walk))) :strong))

(defun next-cell-alignment (walk operation)
  "The alignment of the next table cell under WALK: its table's, for the
cell's column, its index in its row (get_cell_alignment,
vendor/cmark-gfm/extensions/table.c). A column past the table's alignments
signals NATIVE-PARSE-ERROR naming OPERATION: cmark gives every row exactly
its table's columns (try_opening_table_row), and reading past them would
read past the C array."
  (let ((alignments (html-bound-walk-alignments walk))
        (column (html-bound-walk-column walk)))
    (unless (< column (length alignments))
      (error 'native-parse-error
             :operation operation
             :datum column
             :reason "a table cell lies past its table's columns"))
    (incf (html-bound-walk-column walk))
    (aref alignments column)))

(defun footnote-reference-label-octets (document node operation)
  "The octets of the label of the footnote definition NODE, a footnote
reference, resolves to: cmark_render_html writes that definition's literal
(S_render_node, vendor/cmark-gfm/src/html.c). A reference without one
signals NATIVE-PARSE-ERROR naming OPERATION: cmark turns every dangling
reference into text (process_footnotes, vendor/cmark-gfm/src/blocks.c),
and the renderer would follow the null pointer."
  (let ((definition (native-footnote-definition document node)))
    (unless definition
      (error 'native-parse-error
             :operation operation
             :datum (native-literal document node)
             :reason "a footnote reference has no definition"))
    (literal-octets-of document definition)))

(defun html-footnote-definition-entered (walk node)
  "Count NODE, a footnote definition, under WALK, and return its term:
cmark_render_html numbers the definitions in the order it renders them."
  (let* ((document (html-bound-walk-document walk))
         (label (literal-octets-of document node))
         (number (incf (html-bound-walk-definitions walk))))
    (setf (html-bound-walk-longest-label walk) (max label (html-bound-walk-longest-label walk)))
    (html-footnote-definition-bound label number)))

(defun html-footnote-reference-entered (walk node operation)
  "Count NODE, a footnote reference, under WALK, and return its term
without its index suffix, which HTML-FOOTNOTES-BOUND adds once the
definitions are counted."
  (let ((document (html-bound-walk-document walk)))
    (incf (html-bound-walk-references walk))
    (html-footnote-reference-bound (footnote-reference-label-octets document node operation)
                                   (literal-octets-of document node)
                                   0)))

(defun html-node-bound (walk node kind operation)
  "NODE's HTML term, NODE being of KIND and about to be entered under WALK's
ancestors; updates WALK's tables and footnotes as cmark_render_html would
reach them. Signals UNSUPPORTED-EXTENSION-NODE, naming OPERATION, for an
:EXTENSION node, whose markup no term knows."
  (let ((document (html-bound-walk-document walk)))
    (flet ((sourcepos () (walk-sourcepos-octets walk node))
           (literal () (literal-octets-of document node)))
      (ecase kind
        (:document 0)
        (:block-quote (html-block-quote-bound (sourcepos)))
        (:list (html-list-bound (native-list-type document node) (native-list-start document node)
                                (sourcepos)))
        (:item (html-item-bound (sourcepos)))
        (:task-item (html-task-item-bound (native-task-checked document node) (sourcepos)))
        (:heading (html-heading-bound (sourcepos)))
        (:code-block (let ((info (native-fence-info document node)))
                       (html-code-block-bound (utf8-length info)
                                              (code-block-language-octets info)
                                              (literal) (sourcepos))))
        (:html-block (let ((literal (native-literal document node)))
                       (html-html-block-bound (utf8-length literal)
                                              (count #\< literal :test #'char=)
                                              (html-bound-walk-unsafe walk)
                                              (html-bound-walk-tagfilter walk))))
        (:thematic-break (html-thematic-break-bound (sourcepos)))
        (:paragraph (if (tight-paragraph-p walk)
                        (html-paragraph-bound t 0)
                        (html-paragraph-bound nil (sourcepos))))
        (:text (html-text-bound (literal)))
        (:softbreak (html-softbreak-bound (html-bound-walk-softbreak walk)))
        (:linebreak (html-linebreak-bound))
        (:code (html-code-bound (literal)))
        (:html-inline (html-html-inline-bound (literal)
                                              (html-bound-walk-unsafe walk)
                                              (html-bound-walk-tagfilter walk)
                                              (plusp (html-bound-walk-images walk))))
        (:emph (html-emph-bound))
        (:strong (html-strong-bound (nested-strong-p walk)))
        (:strikethrough (html-strikethrough-bound))
        (:link (html-link-bound (utf8-length (native-url document node))
                                (utf8-length (native-title document node))))
        (:image (html-image-bound (utf8-length (native-url document node))
                                  (utf8-length (native-title document node))))
        (:table (setf (html-bound-walk-alignments walk)
                      (coerce (native-table-alignments document node) 'vector))
                (html-table-bound (sourcepos)))
        (:table-header (setf (html-bound-walk-column walk) 0)
                       (html-table-header-bound (sourcepos)))
        (:table-row (setf (html-bound-walk-column walk) 0)
                    (html-table-row-bound (sourcepos)))
        (:table-cell (html-table-cell-bound (next-cell-alignment walk operation) (sourcepos)))
        (:footnote-definition (html-footnote-definition-entered walk node))
        (:footnote-reference (html-footnote-reference-entered walk node operation))
        (:extension (error 'unsupported-extension-node
                           :operation operation
                           :datum (native-type-string document node)
                           :reason "no output bound for an extension's own node"))))))

(defun html-footnotes-bound (walk markdown operation)
  "What WALK's footnotes add once every node is counted: the section around
the definitions, each reference's index suffix, and every repeat backref,
bounded from the input: the tree no longer holds the references in
definitions cmark dropped, which still count (process_footnotes,
vendor/cmark-gfm/src/blocks.c). Of MARKDOWN's FOOTNOTE-REFERENCE-BOUND
openers, each definition kept takes one, its own [^label]:, so the
references, dropped ones included, number at most the rest: those are the
openers the suffix and backref terms are given. A tree with more
references and definitions together than MARKDOWN has openers would mean
that bound is wrong, and signals NATIVE-PARSE-ERROR naming OPERATION
rather than trust it."
  (let ((definitions (html-bound-walk-definitions walk))
        (references (html-bound-walk-references walk)))
    (if (and (zerop definitions) (zerop references))
        0
        (let* ((candidates (footnote-reference-bound markdown))
               (openers (- candidates definitions)))
          (when (> references openers)
            (error 'native-parse-error
                   :operation operation
                   :datum (list :definitions definitions :references references
                                :candidates candidates)
                   :reason "more footnotes than the input can open"))
          (+ (if (plusp definitions) (html-footnote-section-bound) 0)
             (* references (html-footnote-suffix-bound openers definitions))
             (html-footnote-backrefs-bound openers definitions
                                           (html-bound-walk-longest-label walk)))))))

(defun html-output-bound (document checked-options markdown
                          &optional (operation 'html-output-bound))
  "An upper bound on the UTF-8 octets RENDER-HTML would write for DOCUMENT,
a live native document parsed from MARKDOWN with CHECKED-OPTIONS: one
WALK-NATIVE summing /native-core's HTML terms, then the footnotes'
suffixes and repeat backrefs, bounded from MARKDOWN.

It reads what changes cmark_render_html's markup: :SOURCEPOS's
data-sourcepos, :UNSAFE-HTML's raw HTML, :SOFTBREAK's breaks, and whether
the tagfilter extension is attached, since the renderer filters raw HTML
through every attached extension with an html_filter_func (RENDER-HTML
passes it the parser's extensions).

Signals UNSUPPORTED-EXTENSION-NODE, naming OPERATION, for a node no term
bounds, and NATIVE-PARSE-ERROR for a footnote reference without a
definition, a table cell past its columns, or more footnotes than MARKDOWN
can open: cmark builds none of them under the pin."
  (let ((walk (make-html-bound-walk document
                                    (checked-sourcepos checked-options)
                                    (checked-unsafe-html checked-options)
                                    (and (member :tagfilter (checked-extensions checked-options))
                                         t)
                                    (checked-softbreak checked-options))))
    (walk-native (lambda (event node)
                   (ecase event
                     (:enter
                      (let ((kind (native-kind document node)))
                        (incf (html-bound-walk-total walk)
                              (html-node-bound walk node kind operation))
                        (push (cons kind (and (eql kind :list) (native-list-tight document node)))
                              (html-bound-walk-ancestors walk))
                        (when (eql kind :image)
                          (incf (html-bound-walk-images walk)))))
                     (:exit
                      (when (eql (car (pop (html-bound-walk-ancestors walk))) :image)
                        (decf (html-bound-walk-images walk)))))
                   nil)
                 document)
    (+ (html-bound-walk-total walk) (html-footnotes-bound walk markdown operation))))

;;; Plaintext

(defstruct (plaintext-frame
            (:constructor make-plaintext-frame (kind prefix &optional list-type next-index))
            (:copier nil))
  "A node PLAINTEXT-OUTPUT-BOUND has entered and not yet left: its KIND, the
PREFIX width its children are written under, and for a list its
LIST-TYPE and the NEXT-INDEX its next item takes."
  kind
  prefix
  list-type
  next-index)

(defun next-item-marker-width (frames operation)
  "The marker width of the list item about to be entered under FRAMES, its
parent's on top, and advance its list's count: cmark_render numbers every
item, task items too, from its list's start. An item outside a list
signals NATIVE-PARSE-ERROR naming OPERATION."
  (let ((list (first frames)))
    (unless (and list (eql (plaintext-frame-kind list) :list))
      (error 'native-parse-error
             :operation operation
             :reason "a list item lies outside a list"))
    (prog1 (plaintext-item-marker-width (plaintext-frame-list-type list)
                                        (plaintext-frame-next-index list))
      (incf (plaintext-frame-next-index list)))))

(defun plaintext-output-bound (document checked-options
                               &optional (operation 'plaintext-output-bound))
  "An upper bound on the UTF-8 octets RENDER-PLAINTEXT would write for
DOCUMENT, a live native document parsed with CHECKED-OPTIONS: one
WALK-NATIVE that turns every node's events into PLAINTEXT-EVENT-STEPS and
sums their PLAINTEXT-STEPS-BOUND, under the prefix in effect, with a frame
per entered node on an explicit stack.

It reads what changes cmark_render_plaintext's output: :SOFTBREAK, whose
:BR turns wrapping off (CMARK_OPT_HARDBREAKS) and whose :SPACE leaves the
width but no wrapping (CMARK_OPT_NOBREAKS), and :WIDTH.

Signals UNSUPPORTED-EXTENSION-NODE, naming OPERATION, for a node no term
bounds, and NATIVE-PARSE-ERROR for a list item outside a list, which cmark
never builds."
  (let* ((softbreak (checked-softbreak checked-options))
         (width (if (eql softbreak :br) 0 (checked-width checked-options)))
         (wrap (and (plusp width) (eql softbreak :newline)))
         ;; cmark_render ends the text with a newline when it lacks one.
         (total 1)
         (pending nil)
         (frames '())
         (tables 0)
         (columns 0)
         (definitions 0))
    (labels ((prefix ()
               (if frames (plaintext-frame-prefix (first frames)) 0))
             (add (steps prefix)
               (multiple-value-bind (octets now-pending)
                   (plaintext-steps-bound steps prefix pending)
                 (incf total octets)
                 (setf pending now-pending)))
             (literal-steps (kind node)
               (let ((literal (native-literal document node)))
                 (plaintext-event-steps :enter kind
                                        :octets (utf8-length literal)
                                        :spaces (count #\Space literal :test #'char=)
                                        :newlines (count #\Newline literal :test #'char=)
                                        :escapes (if (plusp tables)
                                                     (count #\| literal :test #'char=)
                                                     0)
                                        :wrap wrap)))
             (enter (node)
               (let* ((kind (native-kind document node))
                      (prefix (prefix))
                      (marker-width (if (member kind '(:item :task-item))
                                        (next-item-marker-width frames operation)
                                        0)))
                 (add (ecase kind
                        ((:document :block-quote :list :html-block :paragraph :heading
                          :thematic-break :linebreak :html-inline :emph :strong :link :image
                          :strikethrough :table-header :table-row :table-cell :task-item)
                         (plaintext-event-steps :enter kind :wrap wrap))
                        (:item (plaintext-event-steps :enter kind :marker-width marker-width))
                        ((:text :code :code-block) (literal-steps kind node))
                        (:softbreak (plaintext-event-steps :enter kind :wrap wrap))
                        (:footnote-reference
                         (plaintext-event-steps :enter kind
                                                :octets (literal-octets-of document node)))
                        (:footnote-definition
                         (plaintext-event-steps :enter kind :number (incf definitions)))
                        (:table
                         (incf tables)
                         (setf columns (native-table-columns document node))
                         (plaintext-event-steps :enter kind))
                        (:extension
                         (error 'unsupported-extension-node
                                :operation operation
                                :datum (native-type-string document node)
                                :reason "no output bound for an extension's own node")))
                      prefix)
                 (push (if (eql kind :list)
                           (make-plaintext-frame kind prefix (native-list-type document node)
                                                 (native-list-start document node))
                           (make-plaintext-frame kind (+ prefix (plaintext-prefix-width
                                                                 kind marker-width))))
                       frames)))
             (leave ()
               (let ((kind (plaintext-frame-kind (pop frames))))
                 (add (plaintext-event-steps :exit kind :columns columns) (prefix))
                 (when (eql kind :table)
                   (decf tables)))))
      (walk-native (lambda (event node)
                     (ecase event
                       (:enter (enter node))
                       (:exit (leave)))
                     nil)
                   document))
    total))
