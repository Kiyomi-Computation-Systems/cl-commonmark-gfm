;;;; AST->HTML-TREE: converting a validated AST into an LHTML-shaped tree.
;;;;
;;;; A port of cmark-gfm's HTML renderer loop: S_render_node and
;;;; S_put_footnote_backref in vendor/cmark-gfm/src/html.c, and the
;;;; html_render functions of vendor/cmark-gfm/extensions/table.c,
;;;; tasklist.c and strikethrough.c. cmark hands each enter and exit event
;;;; of its iterator to S_render_node; here WALK-AST hands each event to
;;;; RENDER-EVENT. The renderer builds tree nodes where cmark writes bytes,
;;;; and a "\n" string wherever cmark writes a newline: cmark lays out the
;;;; same element differently in different places, so the tree carries the
;;;; layout, and HTML-TREE->STRING adds none. Nothing here recurses over a
;;;; tree's depth or a list's length, so memory, not the Lisp call stack,
;;;; bounds the trees it converts.

(in-package #:cl-commonmark-gfm.html-tree)

;;; Options

(defparameter *render-option-choices*
  '((:raw-html :omit :text)
    (:softbreak :newline :space :br)
    (:link-policy :safe :unsafe))
  "Each option of AST->HTML-TREE but :DOCUMENT-WRAPPER, followed by the values
it accepts, default first.")

(defun signal-invalid-render-option (operation datum reason)
  "Signal INVALID-RENDER-OPTION for OPERATION, naming DATUM and REASON. OPERATION
is ordinarily AST->HTML-TREE, its own name; MARKDOWN->HTML-TREE passes its own
name instead, when it checks its tree options before any native call."
  (error 'invalid-render-option :operation operation :datum datum :reason reason))

(defun document-wrapper-p (value)
  "True when VALUE may be the :DOCUMENT-WRAPPER option: NIL, or a keyword that
names a non-void element under the serializer's name rule."
  (or (null value)
      (and (valid-html-name-p value) (not (void-element-p value)))))

(defun check-option (operation key value)
  "Signal INVALID-RENDER-OPTION for OPERATION unless KEY is an option of
AST->HTML-TREE and VALUE is one of its values."
  (let ((choices (rest (assoc key *render-option-choices*))))
    (cond ((eql key :document-wrapper)
           (unless (document-wrapper-p value)
             (signal-invalid-render-option
              operation value ":document-wrapper must be nil or a non-void element keyword")))
          ((null choices)
           (signal-invalid-render-option operation key "unknown option"))
          ((not (member value choices))
           (signal-invalid-render-option
            operation value (format nil "~(~S~) must be one of ~{~(~S~)~^, ~}" key choices))))))

(defun check-tree-options (options operation)
  "Signal INVALID-RENDER-OPTION for OPERATION unless OPTIONS is a plist of
AST->HTML-TREE's options with valid values. Every pair is checked, a repeated
key's too.

This checker is internal to .HTML-TREE, not exported: MARKDOWN->HTML-TREE
imports it by name to validate its own tree options before any native call,
so the rules for :RAW-HTML, :SOFTBREAK, :LINK-POLICY and :DOCUMENT-WRAPPER
stay in one place. AST->HTML-TREE calls it on its own OPTIONS, passing its
own name."
  (unless (evenp (length options))
    (signal-invalid-render-option operation options "options must be a plist of even length"))
  (loop for (key value) on options by #'cddr
        do (check-option operation key value)))

(defun option-value (options key)
  "KEY's value in the checked OPTIONS, or its default. A repeated key's
leftmost value wins, as with &KEY."
  (getf options key (second (assoc key *render-option-choices*))))

;;; The renderer's state

(defstruct (pending-element
            (:constructor make-pending-element (tag attributes))
            (:copier nil))
  "An element whose start tag is written and whose end tag isn't yet: its
TAG, its ATTRIBUTES, and ITEMS, its children so far, latest first. The
bottom of the renderer's stack of open elements has no TAG, and collects the
top-level items."
  (tag nil :read-only t)
  (attributes nil :read-only t)
  (items '()))

(defstruct (renderer
            (:copier nil))
  "Everything one conversion keeps from one event to the next.

What stays the same: the three render policies, the PLAN from PLAN-FOOTNOTES,
and the DOCUMENT being converted.

The output: ELEMENTS, the stack of PENDING-ELEMENTs, innermost first; and BOL,
true when the output so far is empty or ends in a newline, the one bit of
layout cmark_html_render_cr reads.

Plain mode, cmark's renderer->plain: PLAIN is the image whose :ENTER started
it, or NIL, and ALT a string output stream holding its alt text so far.

Context: ANCESTORS, the nodes the current walk has entered and not yet left,
innermost first, above WALK-BASE, the parent and grandparent the walk's root
is rendered under; OPEN-HEADERS, how many :TABLE-HEADERs are open; TABLES,
one flag per open :TABLE, innermost first, true once its tbody is open.

Footnotes: OWNER, the owner whose references are being rendered, and
ORDINAL, how many of them have been met so far; BACKREFS, the footnote whose
backrefs end the current walk's root paragraph, or NIL."
  (raw-html nil :read-only t)
  (softbreak nil :read-only t)
  (link-policy nil :read-only t)
  (plan nil :read-only t)
  (document nil :read-only t)
  (elements (list (make-pending-element nil '())))
  (bol t)
  (plain nil)
  (alt nil)
  (ancestors '())
  (walk-base '())
  (open-headers 0)
  (tables '())
  (owner +body-owner+)
  (ordinal 0)
  (backrefs nil))

(defun parent (renderer)
  "The parent of the node whose event is being rendered: at its :ENTER, and
again at its :EXIT, the node itself isn't among the ANCESTORS."
  (first (renderer-ancestors renderer)))

(defun grandparent (renderer)
  "The grandparent of the node whose event is being rendered."
  (second (renderer-ancestors renderer)))

(defun walk-root-p (renderer)
  "True when the node whose event is being rendered is the current walk's
root: no ancestor has been entered above the WALK-BASE."
  (eql (renderer-ancestors renderer) (renderer-walk-base renderer)))

;;; Output: the stack of open elements, and BOL

(defun merge-strings (strings)
  "STRINGS concatenated into one fresh string."
  (let ((result (make-string (loop for string in strings sum (length string))))
        (start 0))
    (dolist (string strings result)
      (replace result string :start1 start)
      (incf start (length string)))))

(defun normalize-items (items)
  "ITEMS with each run of adjacent strings merged into one fresh string, and
empty strings dropped."
  (let ((result '())
        (run '()))
    (flet ((end-run ()
             (let ((merged (merge-strings (reverse run))))
               (setf run '())
               (when (plusp (length merged))
                 (push merged result)))))
      (dolist (item items)
        (cond ((stringp item) (push item run))
              (t (end-run)
                 (push item result))))
      (end-run))
    (reverse result)))

(defun emit-text (renderer string)
  "Write STRING as text: add it to the innermost open element. A non-empty
STRING sets BOL from its last character."
  (push string (pending-element-items (first (renderer-elements renderer))))
  (when (plusp (length string))
    (setf (renderer-bol renderer) (char= (char string (1- (length string))) #\Newline))))

(defun emit-newline (renderer)
  "Write a newline, as cmark does when it writes one outright."
  (emit-text renderer (string #\Newline)))

(defun emit-cr (renderer)
  "Write a newline unless the output so far is empty or already ends in one,
as cmark_html_render_cr (vendor/cmark-gfm/src/html.h) does. The docstrings
below call this cr."
  (unless (renderer-bol renderer)
    (emit-newline renderer)))

(defun emit-start-tag (renderer tag attributes)
  "Write a start tag: push an element of TAG with ATTRIBUTES, whose children
are what is written until it closes. A start tag leaves the output
mid-line."
  (push (make-pending-element tag attributes) (renderer-elements renderer))
  (setf (renderer-bol renderer) nil))

(defun emit-end-tag (renderer)
  "Write the innermost open element's end tag: pop it, normalize its
children, and add it to the element it sits in. An end tag leaves the
output mid-line."
  (let ((element (pop (renderer-elements renderer))))
    (push (list* (pending-element-tag element)
                 (pending-element-attributes element)
                 (normalize-items (reverse (pending-element-items element))))
          (pending-element-items (first (renderer-elements renderer))))
    (setf (renderer-bol renderer) nil)))

(defun emit-void-element (renderer tag attributes)
  "Write a void element: TAG with ATTRIBUTES, and no children."
  (emit-start-tag renderer tag attributes)
  (emit-end-tag renderer))

(defun top-level-items (renderer)
  "The top-level items written so far, normalized: what the bottom of the
stack of open elements collected."
  (normalize-items (reverse (pending-element-items (first (renderer-elements renderer))))))

(defun attribute (name value)
  "An attribute pair: NAME with a fresh copy of the string VALUE."
  (list name (copy-seq value)))

;;; Blocks (html.c, and tasklist.c for task items)

(defun render-block-quote (renderer entering)
  "Enter: cr, <blockquote>, a newline. Exit: cr, </blockquote>, a newline."
  (cond (entering
         (emit-cr renderer)
         (emit-start-tag renderer :blockquote '())
         (emit-newline renderer))
        (t
         (emit-cr renderer)
         (emit-end-tag renderer)
         (emit-newline renderer))))

(defun list-tag (node)
  "The tag of a :LIST node: :UL for a bullet list, :OL for an ordered one."
  (ecase (node-attribute node :type)
    (:bullet :ul)
    (:ordered :ol)))

(defun list-attributes (node)
  "The attributes of a :LIST node's start tag: a start attribute for an
ordered list that doesn't start at 1, and none otherwise."
  (if (and (eql (node-attribute node :type) :ordered)
           (/= (node-attribute node :start) 1))
      (list (attribute :start (format nil "~D" (node-attribute node :start))))
      '()))

(defun render-list (renderer node entering)
  "Enter: cr, <ul> or <ol>, a newline. Exit: the end tag, a newline."
  (cond (entering
         (emit-cr renderer)
         (emit-start-tag renderer (list-tag node) (list-attributes node))
         (emit-newline renderer))
        (t
         (emit-end-tag renderer)
         (emit-newline renderer))))

(defun render-item (renderer entering)
  "Enter: cr, <li>. Exit: </li>, a newline."
  (cond (entering
         (emit-cr renderer)
         (emit-start-tag renderer :li '()))
        (t
         (emit-end-tag renderer)
         (emit-newline renderer))))

(defun checkbox-attributes (checked)
  "The attributes of a task item's checkbox, ticked when CHECKED."
  (list* (attribute :type "checkbox")
         (if checked
             (list (attribute :checked "") (attribute :disabled ""))
             (list (attribute :disabled "")))))

(defun render-task-item (renderer node entering)
  "Enter: cr, <li>, the checkbox, a space. Exit: </li>, a newline."
  (cond (entering
         (emit-cr renderer)
         (emit-start-tag renderer :li '())
         (emit-void-element renderer :input (checkbox-attributes (node-attribute node :checked)))
         (emit-text renderer " "))
        (t
         (emit-end-tag renderer)
         (emit-newline renderer))))

(defun tight-list-p (node)
  "True when NODE is a :LIST node with :TIGHT T."
  (and node
       (eql (node-kind node) :list)
       (node-attribute node :tight)))

(defun backref-paragraph-exit-p (renderer)
  "True at the :EXIT of a definition's backref paragraph: the walk carries
BACKREFS, and the paragraph is the walk's root."
  (and (renderer-backrefs renderer) (walk-root-p renderer)))

(defun render-paragraph (renderer entering)
  "Nothing when the paragraph is tight, that is when its grandparent is a
:LIST with :TIGHT T. Otherwise, enter: cr, <p>. Exit: a space and the
backrefs, in a definition's backref paragraph; then </p>, a newline."
  (unless (tight-list-p (grandparent renderer))
    (cond (entering
           (emit-cr renderer)
           (emit-start-tag renderer :p '()))
          (t
           (when (backref-paragraph-exit-p renderer)
             (emit-text renderer " ")
             (emit-backrefs renderer (renderer-backrefs renderer)))
           (emit-end-tag renderer)
           (emit-newline renderer)))))

(defun heading-tag (level)
  "The tag of a heading of LEVEL, 1 to 6."
  (ecase level
    (1 :h1) (2 :h2) (3 :h3) (4 :h4) (5 :h5) (6 :h6)))

(defun render-heading (renderer node entering)
  "Enter: cr, <hN>. Exit: </hN>, a newline."
  (cond (entering
         (emit-cr renderer)
         (emit-start-tag renderer (heading-tag (node-attribute node :level)) '()))
        (t
         (emit-end-tag renderer)
         (emit-newline renderer))))

(defun info-space-p (char)
  "True when CHAR ends a code block's language word: space, tab, LF or CR,
the characters cmark_isspace accepts. VT and FF do not."
  (member (char-code char) '(9 10 13 32)))

(defun code-block-attributes (info)
  "The attributes of a code block's code element: none for an empty INFO,
otherwise a class naming the language, INFO's first word."
  (if (zerop (length info))
      '()
      (list (attribute :class (concatenate 'string "language-"
                                           (subseq info 0 (position-if #'info-space-p info)))))))

(defun render-code-block (renderer node)
  "cr, <pre><code>, the literal, </code></pre>, a newline."
  (emit-cr renderer)
  (emit-start-tag renderer :pre '())
  (emit-start-tag renderer :code (code-block-attributes (node-attribute node :info)))
  (emit-text renderer (node-attribute node :literal))
  (emit-end-tag renderer)
  (emit-end-tag renderer)
  (emit-newline renderer))

(defun render-raw-html (renderer node)
  "NODE's raw HTML: cmark's comment under :RAW-HTML :OMIT, and NODE's
literal as text under :TEXT."
  (ecase (renderer-raw-html renderer)
    (:omit
     (emit-start-tag renderer :*comment* '())
     (emit-text renderer " raw HTML omitted ")
     (emit-end-tag renderer))
    (:text
     (emit-text renderer (node-attribute node :literal)))))

(defun render-html-block (renderer node)
  "cr, the raw HTML, cr."
  (emit-cr renderer)
  (render-raw-html renderer node)
  (emit-cr renderer))

(defun render-thematic-break (renderer)
  "cr, <hr />, a newline."
  (emit-cr renderer)
  (emit-void-element renderer :hr '())
  (emit-newline renderer))

;;; Tables (table.c)

(defun render-table (renderer entering)
  "Enter: cr, <table>, with its tbody not yet open. Exit: when its tbody is
open, cr, </tbody>, cr; then cr, </table>, cr."
  (cond (entering
         (emit-cr renderer)
         (emit-start-tag renderer :table '())
         (push nil (renderer-tables renderer)))
        (t
         (when (pop (renderer-tables renderer))
           (emit-cr renderer)
           (emit-end-tag renderer)
           (emit-cr renderer))
         (emit-cr renderer)
         (emit-end-tag renderer)
         (emit-cr renderer))))

(defun render-table-header (renderer entering)
  "Enter: cr, <thead>, cr, <tr>. Exit: cr, </tr>, cr, </thead>. Its cells,
and every cell below it, are th cells."
  (cond (entering
         (emit-cr renderer)
         (emit-start-tag renderer :thead '())
         (emit-cr renderer)
         (emit-start-tag renderer :tr '())
         (incf (renderer-open-headers renderer)))
        (t
         (decf (renderer-open-headers renderer))
         (emit-cr renderer)
         (emit-end-tag renderer)
         (emit-cr renderer)
         (emit-end-tag renderer))))

(defun opens-table-body-p (renderer)
  "True when the :TABLE-ROW being entered opens a tbody: its parent is a
:TABLE, the innermost open one, whose tbody isn't open yet. The tbody then
holds the row and everything after it in the table."
  (let ((parent (parent renderer)))
    (and parent
         (eql (node-kind parent) :table)
         (not (first (renderer-tables renderer))))))

(defun render-table-row (renderer entering)
  "Enter: when the row opens its table's tbody, cr, <tbody>, cr; then cr,
<tr>. Exit: cr, </tr>."
  (cond (entering
         (when (opens-table-body-p renderer)
           (emit-cr renderer)
           (emit-start-tag renderer :tbody '())
           (emit-cr renderer)
           (setf (first (renderer-tables renderer)) t))
         (emit-cr renderer)
         (emit-start-tag renderer :tr '()))
        (t
         (emit-cr renderer)
         (emit-end-tag renderer))))

(defun cell-attributes (align)
  "The attributes of a table cell whose :ALIGN is ALIGN."
  (ecase align
    ((nil) '())
    (:left (list (attribute :align "left")))
    (:center (list (attribute :align "center")))
    (:right (list (attribute :align "right")))))

(defun render-table-cell (renderer node entering)
  "Enter: cr, then <th> while a :TABLE-HEADER is open, or <td>. Exit: the
end tag."
  (cond (entering
         (emit-cr renderer)
         (emit-start-tag renderer
                         (if (plusp (renderer-open-headers renderer)) :th :td)
                         (cell-attributes (node-attribute node :align))))
        (t
         (emit-end-tag renderer))))

;;; Inlines (html.c, and strikethrough.c for :STRIKETHROUGH)

(defun render-line-break (renderer)
  "<br /> and a newline."
  (emit-void-element renderer :br '())
  (emit-newline renderer))

(defun render-softbreak (renderer)
  "A newline, a space, or a line break, by the :SOFTBREAK policy."
  (ecase (renderer-softbreak renderer)
    (:newline (emit-newline renderer))
    (:space (emit-text renderer " "))
    (:br (render-line-break renderer))))

(defun render-code (renderer node)
  "<code>, the literal, </code>."
  (emit-start-tag renderer :code '())
  (emit-text renderer (node-attribute node :literal))
  (emit-end-tag renderer))

(defun render-inline-element (renderer tag entering)
  "Enter: TAG's start tag. Exit: its end tag."
  (if entering
      (emit-start-tag renderer tag '())
      (emit-end-tag renderer)))

(defun strong-node-p (node)
  "True when NODE is a :STRONG node."
  (and node (eql (node-kind node) :strong)))

(defun render-strong (renderer entering)
  "<strong> and </strong>, unless the parent is itself a :STRONG. The same
parent decides at the :ENTER and at the :EXIT."
  (unless (strong-node-p (parent renderer))
    (render-inline-element renderer :strong entering)))

(defun destination-url (renderer node)
  "The :DESTINATION of a :LINK or :IMAGE NODE, percent-encoded, or \"\" when
the link policy is :SAFE and it is dangerous. The check runs on the raw
destination, before encoding, as in cmark-gfm's renderer."
  (let ((destination (node-attribute node :destination)))
    (if (and (eql (renderer-link-policy renderer) :safe) (dangerous-url-p destination))
        ""
        (href-encode destination))))

(defun title-attributes (node)
  "A title attribute for a :LINK or :IMAGE NODE, or none when its title is
empty."
  (let ((title (node-attribute node :title)))
    (if (zerop (length title))
        '()
        (list (attribute :title title)))))

(defun render-link (renderer node entering)
  "Enter: <a> with href and title. Exit: </a>."
  (if entering
      (emit-start-tag renderer :a (list* (attribute :href (destination-url renderer node))
                                         (title-attributes node)))
      (emit-end-tag renderer)))

(defun render-image (renderer node entering)
  "Enter: start plain mode, so the descendants write only alt text. Exit,
once plain mode has ended: <img /> with src, alt and title."
  (cond (entering
         (setf (renderer-plain renderer) node
               (renderer-alt renderer) (make-string-output-stream)))
        (t
         (let ((alt (get-output-stream-string (renderer-alt renderer))))
           (setf (renderer-alt renderer) nil)
           (emit-void-element renderer :img
                              (list* (attribute :src (destination-url renderer node))
                                     (attribute :alt alt)
                                     (title-attributes node)))))))

;;; Footnotes (html.c; the pre-pass is footnotes.lisp)

(defun next-citation (renderer)
  "Count one more reference of the current owner, and return its citation
under the plan, (FOOTNOTE . K), or NIL when it dangles. Every reference
place the renderer meets counts exactly once, resolving or not, as the
pre-pass counts it."
  (reference-citation (renderer-plan renderer)
                      (citation-key (renderer-owner renderer)
                                    (incf (renderer-ordinal renderer)))))

(defun dangling-reference-text (node)
  "The text a :FOOTNOTE-REFERENCE NODE becomes when nothing resolves it."
  (concatenate 'string "[^" (footnote-label node) "]"))

(defun footnote-anchor (footnote)
  "FOOTNOTE's label, percent-encoded, as its ids and hrefs carry it."
  (href-encode (footnote-label (footnote-definition footnote))))

;;; A test redefines REFERENCE-ID. Its calls are all in this file, and
;;; CLHS 3.2.2.3 lets a compiler bind such calls to this definition unless
;;; it is declared NOTINLINE.
(declaim (notinline reference-id))

(defun reference-id (footnote k)
  "The id of the K-th reference to FOOTNOTE: fnref-L, then fnref-L-K."
  (if (= k 1)
      (concatenate 'string "fnref-" (footnote-anchor footnote))
      (format nil "fnref-~A-~D" (footnote-anchor footnote) k)))

(defun emit-footnote-reference (renderer footnote k)
  "The K-th reference to FOOTNOTE: a sup holding a link to it, which reads
as its number."
  (emit-start-tag renderer :sup (list (attribute :class "footnote-ref")))
  (emit-start-tag renderer :a
                  (list (attribute :href (concatenate 'string "#fn-" (footnote-anchor footnote)))
                        (attribute :id (reference-id footnote k))
                        (attribute :data-footnote-ref "")))
  (emit-text renderer (format nil "~D" (footnote-number footnote)))
  (emit-end-tag renderer)
  (emit-end-tag renderer))

(defun render-footnote-reference (renderer node)
  "A resolving reference's sup, or the text of a dangling one."
  (let ((citation (next-citation renderer)))
    (if citation
        (emit-footnote-reference renderer (car citation) (cdr citation))
        (emit-text renderer (dangling-reference-text node)))))

(defun emit-backref (renderer footnote k)
  "The backref anchor to the K-th reference to FOOTNOTE
(S_put_footnote_backref). From the second on, it names K in its index and
label, and shows K in a sup after the arrow."
  (let ((index (if (= k 1)
                   (format nil "~D" (footnote-number footnote))
                   (format nil "~D-~D" (footnote-number footnote) k))))
    (emit-start-tag renderer :a
                    (list (attribute :href (concatenate 'string "#" (reference-id footnote k)))
                          (attribute :class "footnote-backref")
                          (attribute :data-footnote-backref "")
                          (attribute :data-footnote-backref-idx index)
                          (attribute :aria-label (concatenate 'string "Back to reference "
                                                              index))))
    (emit-text renderer (string (code-char #x21A9)))
    (unless (= k 1)
      (emit-start-tag renderer :sup (list (attribute :class "footnote-ref")))
      (emit-text renderer (format nil "~D" k))
      (emit-end-tag renderer))
    (emit-end-tag renderer)))

(defun emit-backrefs (renderer footnote)
  "One backref per reference to FOOTNOTE, separated by spaces."
  (loop for k from 1 to (footnote-reference-count footnote)
        do (unless (= k 1)
             (emit-text renderer " "))
           (emit-backref renderer footnote k)))

;;; Dispatch: one handler for WALK-AST's events

(defun render-node (renderer node entering)
  "Render the :ENTER of NODE, when ENTERING, or its :EXIT, outside plain
mode, following cmark's S_render_node case by case. A leaf does all its
work on :ENTER. Returns :SKIP at a definition's :ENTER, and NIL otherwise:
a definition leaves its place, and the footnote section renders it. The
pre-pass has already ruled out :EXTENSION."
  (ecase (node-kind node)
    (:document nil)
    (:block-quote (render-block-quote renderer entering))
    (:list (render-list renderer node entering))
    (:item (render-item renderer entering))
    (:task-item (render-task-item renderer node entering))
    (:paragraph (render-paragraph renderer entering))
    (:heading (render-heading renderer node entering))
    (:code-block (when entering (render-code-block renderer node)))
    (:html-block (when entering (render-html-block renderer node)))
    (:thematic-break (when entering (render-thematic-break renderer)))
    (:table (render-table renderer entering))
    (:table-header (render-table-header renderer entering))
    (:table-row (render-table-row renderer entering))
    (:table-cell (render-table-cell renderer node entering))
    (:text (when entering (emit-text renderer (node-attribute node :literal))))
    (:softbreak (when entering (render-softbreak renderer)))
    (:linebreak (when entering (render-line-break renderer)))
    (:code (when entering (render-code renderer node)))
    (:html-inline (when entering (render-raw-html renderer node)))
    (:emph (render-inline-element renderer :em entering))
    (:strikethrough (render-inline-element renderer :del entering))
    (:strong (render-strong renderer entering))
    (:link (render-link renderer node entering))
    (:image (render-image renderer node entering))
    (:footnote-reference (when entering (render-footnote-reference renderer node)))
    (:footnote-definition (return-from render-node :skip)))
  nil)

(defun render-plain (renderer node)
  "Render the :ENTER of NODE in plain mode, cmark's renderer->plain: NODE
adds only to the alt text. :TEXT, :CODE and :HTML-INLINE add their literal,
whatever the :RAW-HTML policy; breaks add a space; a reference counts, and
adds its [^label] text when it dangles. Returns :SKIP at a definition, which
leaves its place, and NIL otherwise: every other node's children are
visited, nested images' included."
  (let ((alt (renderer-alt renderer)))
    (ecase (node-kind node)
      ((:text :code :html-inline) (write-string (node-attribute node :literal) alt))
      ((:softbreak :linebreak) (write-char #\Space alt))
      (:footnote-reference
       (unless (next-citation renderer)
         (write-string (dangling-reference-text node) alt)))
      (:footnote-definition (return-from render-plain :skip))
      ((:document :block-quote :list :item :task-item :paragraph :heading :code-block
        :html-block :thematic-break :table :table-header :table-row :table-cell
        :emph :strong :strikethrough :link :image)
       nil)))
  nil)

(defun render-event (renderer event node)
  "WALK-AST's handler: render EVENT, :ENTER or :EXIT, of NODE. An entered
node joins the ANCESTORS unless it is skipped, and leaves them at its :EXIT,
before that renders, so a node sees the same parent at both events. Plain
mode ends at the :EXIT of the image that started it, before that image's
exit renders: cmark's renderer->plain == node check. A node can't sit below
itself, so no other event meets that image. Every other event in plain mode
renders through RENDER-PLAIN, whose exits write nothing."
  (ecase event
    (:enter
     (let ((result (if (renderer-plain renderer)
                       (render-plain renderer node)
                       (render-node renderer node t))))
       (unless (eql result :skip)
         (push node (renderer-ancestors renderer)))
       result))
    (:exit
     (pop (renderer-ancestors renderer))
     (when (eql node (renderer-plain renderer))
       (setf (renderer-plain renderer) nil))
     (unless (renderer-plain renderer)
       (render-node renderer node nil))
     nil)))

(defun render-walk (renderer root ancestors &optional backrefs)
  "Render ROOT's tree with one WALK-AST, starting under ANCESTORS: ROOT's
parent and grandparent as cmark's renderer would see them, innermost first.
BACKREFS, when given, is a footnote whose backrefs go at the end of ROOT,
its definition's backref paragraph."
  (setf (renderer-ancestors renderer) ancestors
        (renderer-walk-base renderer) ancestors
        (renderer-backrefs renderer) backrefs)
  (walk-ast (lambda (event node) (render-event renderer event node)) root))

;;; The footnote section

(defun definition-node-p (node)
  "True when NODE is a :FOOTNOTE-DEFINITION node."
  (eql (node-kind node) :footnote-definition))

(defun backref-paragraph-index (children)
  "The index in CHILDREN, a definition's children, of its last child that
isn't a definition, when that child is a :PARAGRAPH: the backrefs go at its
end. NIL otherwise. Definitions are set aside because each one leaves its
place."
  (let ((index (position-if-not #'definition-node-p children :from-end t)))
    (and index
         (eql (node-kind (nth index children)) :paragraph)
         index)))

(defun render-footnote-body (renderer footnote)
  "The children of FOOTNOTE's definition, rendered as its owner with a fresh
count. Each child is walked on its own, under the definition as parent and
the document as grandparent, where cmark's parser moves the definition;
nested definitions are skipped. The backrefs end the backref paragraph,
after a space, or else follow the children, then a newline. The backref
paragraph is known by its index, not by its identity: the same paragraph
object may also sit elsewhere in the definition."
  (let* ((definition (footnote-definition footnote))
         (children (node-children definition))
         (paragraph-index (backref-paragraph-index children))
         (ancestors (list definition (renderer-document renderer))))
    (setf (renderer-owner renderer) (footnote-owner footnote)
          (renderer-ordinal renderer) 0)
    (loop for child in children
          for index from 0
          do (render-walk renderer child ancestors (and (eql index paragraph-index) footnote)))
    (unless paragraph-index
      (emit-backrefs renderer footnote)
      (emit-newline renderer))))

(defun render-footnote-item (renderer footnote)
  "<li id=\"fn-L\">, a newline, the definition's body, </li>, a newline."
  (emit-start-tag renderer :li
                  (list (attribute :id (concatenate 'string "fn-" (footnote-anchor footnote)))))
  (emit-newline renderer)
  (render-footnote-body renderer footnote)
  (emit-end-tag renderer)
  (emit-newline renderer))

(defun render-footnote-section (renderer)
  "The section of surviving footnotes, in number order, and a newline after
it; nothing when none survive. It comes straight after the rest, with no cr
before it, as in cmark. The main walk has closed every table, header and
image, so the section starts with none open."
  (let ((footnotes (footnote-plan-footnotes (renderer-plan renderer))))
    (when footnotes
      (emit-start-tag renderer :section (list (attribute :class "footnotes")
                                              (attribute :data-footnotes "")))
      (emit-newline renderer)
      (emit-start-tag renderer :ol '())
      (emit-newline renderer)
      (dolist (footnote footnotes)
        (render-footnote-item renderer footnote))
      (emit-end-tag renderer)
      (emit-newline renderer)
      (emit-end-tag renderer)
      (emit-newline renderer))))

;;; AST->HTML-TREE

(defun as-document (node)
  "NODE when it is a :DOCUMENT, and otherwise a new document holding only
NODE."
  (if (eql (node-kind node) :document)
      node
      (make-node :document :children (list node))))

(defun document-items (renderer)
  "The top-level items of the RENDERER's document: the document's own walk,
as the body's owner, then the footnote section, starting from an empty
output."
  (render-walk renderer (renderer-document renderer) '())
  (render-footnote-section renderer)
  (top-level-items renderer))

(defun ast->html-tree (node &rest options)
  "Convert the AST NODE into an HTML tree, as cmark-gfm's HTML renderer
would render it. Returns a list of top-level items, strings and elements,
whose strings carry the newlines cmark writes; or, with :DOCUMENT-WRAPPER,
one element of that tag holding them. A NODE that isn't a :DOCUMENT
converts as a document's only child.

OPTIONS is a plist. When a key repeats, the leftmost value wins, but every
value must be valid.
- :RAW-HTML: :OMIT, the default, turns raw HTML into cmark's comment,
  (:*COMMENT* NIL \" raw HTML omitted \"); :TEXT keeps its markup as text.
- :SOFTBREAK: :NEWLINE, the default, turns a soft break into a newline;
  :SPACE, into a space; :BR, into (:BR NIL) and a newline.
- :LINK-POLICY: :SAFE, the default, blanks a link or image URL that starts,
  in any case, with javascript:, vbscript:, file: or data:, but not
  data:image/png, gif, jpeg or webp, as cmark-gfm does; :UNSAFE keeps every
  URL.
- :DOCUMENT-WRAPPER: NIL, the default, or a keyword naming a non-void
  element, which wraps the result in one element of that tag.

Signals INVALID-RENDER-OPTION for a malformed option list, an unknown key or
a bad value, before converting anything; and UNSUPPORTED-EXTENSION-NODE,
naming the first :EXTENSION node depth-first, when the tree holds one.
It loops over WALK-AST's events, so the Lisp stack doesn't bound a tree's
depth. Returns a fresh tree, and leaves NODE as it was."
  (check-tree-options options 'ast->html-tree)
  (let* ((document (as-document node))
         (renderer (make-renderer :raw-html (option-value options :raw-html)
                                  :softbreak (option-value options :softbreak)
                                  :link-policy (option-value options :link-policy)
                                  :plan (plan-footnotes document)
                                  :document document))
         (items (document-items renderer))
         (wrapper (option-value options :document-wrapper)))
    (if wrapper
        (list* wrapper '() items)
        items)))
