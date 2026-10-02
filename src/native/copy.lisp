;;;; COPY-NATIVE-TREE: a detached AST from a parsed tree (M2 design §6;
;;;; ADR-0018). One WALK-NATIVE builds the AST bottom-up through MAKE-NODE,
;;;; so a copied AST passes the schema. A stack of frames, one for each node
;;;; entered and not yet left, collects each node's finished children: no
;;;; recursion, so depth costs no Lisp stack (ADR-0015). The AST holds only
;;;; Lisp data, and outlives its document.

(in-package #:cl-commonmark-gfm.native)

;;; Frames

(defstruct (copy-frame
            (:constructor make-copy-frame (kind attributes sourcepos alignments))
            (:copier nil))
  "One node the copy has entered and not yet left: the KIND, ATTRIBUTES and
SOURCEPOS its AST node gets, read when the walk entered it; for a table,
its ALIGNMENTS, a vector with one entry per column; and its finished
CHILDREN, newest first, of which there are CHILD-COUNT."
  kind
  attributes
  sourcepos
  alignments
  (children '())
  (child-count 0))

;;; Attributes (M2 design §6.3). Each string accessor is called only on the
;;; kinds it serves, where cmark never returns null (M2 design §5.1).

(defun copied-list-attributes (document node)
  "A :LIST's attributes: its :TYPE and :TIGHT, and for an ordered list its
:START and :DELIMITER, which a bullet list has neither of."
  (let ((type (native-list-type document node))
        (tight (native-list-tight document node)))
    (if (eql type :ordered)
        (list :type type
              :start (native-list-start document node)
              :delimiter (native-list-delimiter document node)
              :tight tight)
        (list :type type :tight tight))))

(defun copied-reference-label (document node operation)
  "A footnote reference's :LABEL: the literal of its definition, which is
the label as written (M2 design finding 6). Its own literal is its number.
A reference without a definition signals NATIVE-PARSE-ERROR naming
OPERATION; cmark has already turned every dangling one into text
(process_footnotes, src/blocks.c)."
  (let ((definition (native-footnote-definition document node)))
    (unless definition
      (error 'native-parse-error
             :operation operation
             :datum (native-literal document node)
             :reason "a footnote reference has no definition"))
    (native-literal document definition)))

(defun copied-cell-alignment (stack operation)
  "The :ALIGN of the table cell about to be entered under STACK: its
table's alignment for the cell's column, which is its index in its row
(get_cell_alignment, extensions/table.c). The row's frame tops STACK, and
the table's is under it. A column past the table's alignments signals
NATIVE-PARSE-ERROR naming OPERATION, with the index as its datum; cmark
gives every row exactly its table's columns (try_opening_table_row,
extensions/table.c)."
  (let* ((row (first stack))
         (table (second stack))
         (column (copy-frame-child-count row))
         (alignments (and table (copy-frame-alignments table))))
    (unless (and alignments (< column (length alignments)))
      (error 'native-parse-error
             :operation operation
             :datum column
             :reason "a table cell lies past its table's columns"))
    (aref alignments column)))

(defun copied-attributes (document node kind checked-options stack operation)
  "The attributes NODE of KIND gets in the AST (M2 design §6.3). STACK holds
the frames of NODE's ancestors, its parent's on top."
  (ecase kind
    (:document (document-attributes checked-options))
    (:list (copied-list-attributes document node))
    (:heading (list :level (native-heading-level document node)))
    (:code-block (list :info (native-fence-info document node)
                       :literal (native-literal document node)))
    ((:text :code :html-block :html-inline) (list :literal (native-literal document node)))
    ((:link :image) (list :destination (native-url document node)
                          :title (native-title document node)))
    (:task-item (list :checked (native-task-checked document node)))
    (:table-cell (list :align (copied-cell-alignment stack operation)))
    (:footnote-definition (list :label (native-literal document node)))
    (:footnote-reference (list :label (copied-reference-label document node operation)))
    (:extension (list :type-name (native-type-string document node) :extension-name nil))
    ((:block-quote :item :paragraph :thematic-break :softbreak :linebreak :emph :strong
      :strikethrough :table :table-header :table-row)
     '())))

;;; Positions (M2 design §6.4)

(defun copied-sourcepos (document node)
  "NODE's position, ((START-LINE . START-COLUMN) . (END-LINE . END-COLUMN)),
copied as cmark reports it: inverted ranges and zero columns included,
never repaired (ADR-0005). NIL when its start line is 0, cmark's mark for
no position, as on a softbreak, a linebreak or an email autolink."
  (let ((start-line (native-start-line document node)))
    (if (zerop start-line)
        nil
        (cons (cons start-line (native-start-column document node))
              (cons (native-end-line document node) (native-end-column document node))))))

;;; Entering and leaving a node

(defun enter-copy-frame (document node checked-options stack operation)
  "A frame for NODE, which the walk has just entered under STACK: its kind,
attributes, position, and for a table its alignments."
  (let ((kind (native-kind document node)))
    (make-copy-frame kind
                     (copied-attributes document node kind checked-options stack operation)
                     (and (checked-sourcepos checked-options)
                          (copied-sourcepos document node))
                     (and (eql kind :table)
                          (coerce (native-table-alignments document node) 'vector)))))

(defun leave-copy-frame (frame)
  "FRAME's node, built with MAKE-NODE from what FRAME holds, its children
in order. FRAME is done with, and MAKE-NODE copies the children list, so
the list is reversed in place. A schema violation would be a copier bug,
and signals INVALID-AST-NODE (M2 design §6.1)."
  (make-node (copy-frame-kind frame)
             :attributes (copy-frame-attributes frame)
             :children (nreverse (copy-frame-children frame))
             :sourcepos (copy-frame-sourcepos frame)))

(defun add-copied-child (frame child)
  "Add CHILD, a finished node, to FRAME's children."
  (push child (copy-frame-children frame))
  (incf (copy-frame-child-count frame)))

;;; The copy

(defun copy-native-tree (document checked-options &optional (operation 'copy-native-tree))
  "A detached AST of DOCUMENT, a live native document parsed with
CHECKED-OPTIONS: a :DOCUMENT node, with every node of the parsed tree
below it (M2 design §6). It shares nothing with cmark, so it outlives
DOCUMENT.

- Attributes come from M2 design §6.3: the document's from CHECKED-OPTIONS
  (DOCUMENT-ATTRIBUTES); a footnote reference's :LABEL from its
  definition; a table cell's :ALIGN from its table, by the cell's index in
  its row.
- Positions are copied only when CHECKED-OPTIONS' :SOURCEPOS is true,
  which means the parse set CMARK_OPT_SOURCEPOS: without it, cmark's
  positions drift after a multi-line code span or raw HTML (M2 design
  finding 7).
- Text nodes stay split where cmark split them.

Counts nodes, the document included, as it goes, and signals
RESOURCE-LIMIT-EXCEEDED, through CHECK-LIMIT, at the first past
*MAX-NODES* (M2 design §5.5). Signals NATIVE-PARSE-ERROR for a footnote
reference without a definition, or a table cell past its table's columns,
neither of which cmark builds under the pin. Every condition it signals
itself names OPERATION, the entry point that called it."
  (let ((maximum (effective-maximum '*max-nodes*))
        (count 0)
        (stack '())
        (root nil))
    (walk-native (lambda (event node)
                   (ecase event
                     (:enter
                      (when (> (incf count) maximum)
                        (check-limit '*max-nodes* count operation))
                      (push (enter-copy-frame document node checked-options stack operation)
                            stack))
                     (:exit
                      (let ((copied (leave-copy-frame (pop stack))))
                        (if stack
                            (add-copied-child (first stack) copied)
                            (setf root copied)))))
                   nil)
                 document)
    root))
