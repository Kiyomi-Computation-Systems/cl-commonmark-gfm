;;;; AST->HTML-TREE: converting a validated AST into an LHTML-shaped tree (design §5).
;;;;
;;;; A port of cmark-gfm's HTML renderer: S_render_node and
;;;; S_put_footnote_backref in src/html.c, and the html_render functions of
;;;; extensions/table.c, tasklist.c and strikethrough.c. It builds tree nodes
;;;; where cmark writes bytes, and a "\n" string wherever cmark writes a
;;;; newline (design §5.2, ADR-0014).

(in-package #:cl-commonmark-gfm.html-tree)

;;; Options (design §5.1)

(defparameter *render-option-choices*
  '((:raw-html :omit :text)
    (:softbreak :newline :space :br)
    (:link-policy :safe :unsafe))
  "Each option of AST->HTML-TREE but :DOCUMENT-WRAPPER, followed by the values
it accepts, default first (ADR-0012).")

(defun invalid-option (datum reason)
  "Signal INVALID-RENDER-OPTION for AST->HTML-TREE, naming DATUM and REASON."
  (error 'invalid-render-option :operation 'ast->html-tree :datum datum :reason reason))

(defun document-wrapper-p (value)
  "True when VALUE may be the :DOCUMENT-WRAPPER option: NIL, or a keyword that
names a non-void element under the serializer's name rule."
  (or (null value)
      (and (valid-html-name-p value) (not (void-element-p value)))))

(defun check-option (key value)
  "Signal INVALID-RENDER-OPTION unless KEY is an option of AST->HTML-TREE and
VALUE is one of its values."
  (let ((choices (rest (assoc key *render-option-choices*))))
    (cond ((eql key :document-wrapper)
           (unless (document-wrapper-p value)
             (invalid-option value ":document-wrapper must be nil or a non-void element keyword")))
          ((null choices)
           (invalid-option key "unknown option"))
          ((not (member value choices))
           (invalid-option value (format nil "~(~S~) must be one of ~{~(~S~)~^, ~}"
                                         key choices))))))

(defun check-options (options)
  "Signal INVALID-RENDER-OPTION unless OPTIONS is a plist of AST->HTML-TREE's
options with valid values. Every pair is checked, a repeated key's too."
  (unless (evenp (length options))
    (invalid-option options "options must be a plist of even length"))
  (loop for (key value) on options by #'cddr
        do (check-option key value)))

(defun option-value (options key)
  "KEY's value in the checked OPTIONS, or its default. A repeated key's
leftmost value wins, as with &KEY."
  (getf options key (second (assoc key *render-option-choices*))))

;;; What converting a node needs besides the node

(defstruct (settings
            (:constructor make-settings (raw-html softbreak link-policy footnotes))
            (:copier nil))
  "What stays the same for a whole conversion: the three render policies
(ADR-0012) and the FOOTNOTE-PLAN of the tree being converted."
  (raw-html nil :read-only t)
  (softbreak nil :read-only t)
  (link-policy nil :read-only t)
  (footnotes nil :read-only t))

(defstruct (context
            (:constructor make-context (settings parent grandparent path in-table-header))
            (:copier nil))
  "Where a node sits, as far as cmark's renderer asks: its PARENT and
GRANDPARENT nodes (NIL above the root), its PATH (see ROOT-PATH and
CHILD-PATH), and whether it is inside a table's header row. Plus the
conversion's SETTINGS."
  (settings nil :read-only t)
  (parent nil :read-only t)
  (grandparent nil :read-only t)
  (path '() :read-only t)
  (in-table-header nil :read-only t))

(defun child-context (context node index)
  "The context of the child at INDEX of NODE, whose own context is CONTEXT."
  (make-context (context-settings context)
                node
                (context-parent context)
                (child-path (context-path context) index)
                (or (context-in-table-header context)
                    (eql (node-kind node) :table-header))))

(defun raw-html-policy (context)
  "The :RAW-HTML policy CONTEXT's conversion runs under."
  (settings-raw-html (context-settings context)))

(defun softbreak-policy (context)
  "The :SOFTBREAK policy CONTEXT's conversion runs under."
  (settings-softbreak (context-settings context)))

(defun link-policy (context)
  "The :LINK-POLICY CONTEXT's conversion runs under."
  (settings-link-policy (context-settings context)))

(defun context-footnote-plan (context)
  "The FOOTNOTE-PLAN of the tree CONTEXT's conversion runs over."
  (settings-footnotes (context-settings context)))

;;; Pieces: output in order, with cmark's one bit of layout state (design §5.2)
;;;
;;; A piece is a function of BOL, which is true when the output so far is
;;; empty or ends in a newline. It returns the items it emits (strings and
;;; elements), in order, and BOL after them. Running pieces in output order
;;; carries BOL exactly as cmark's output buffer would, so EMIT-CR decides
;;; what cmark_html_render_cr decides.

(defun run-pieces (pieces bol)
  "Run PIECES in order, the first from BOL. Returns the items they emit, in
order, and BOL after the last."
  (let ((items '()))
    (dolist (piece pieces (values (reverse items) bol))
      (multiple-value-bind (emitted after) (funcall piece bol)
        (setf items (revappend emitted items)
              bol after)))))

(defun merge-strings (strings)
  "STRINGS concatenated into one fresh string."
  (with-output-to-string (out)
    (dolist (string strings)
      (write-string string out))))

(defun normalize-items (items)
  "ITEMS with each run of adjacent strings merged into one fresh string, and
empty strings dropped (design §5.2)."
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

(defun bol-after-string (string bol)
  "BOL after STRING: unchanged when STRING is empty, and otherwise whether
STRING ends in a newline."
  (if (zerop (length string))
      bol
      (char= (char string (1- (length string))) #\Newline)))

(defun emit-nothing ()
  "A piece that emits nothing."
  (lambda (bol) (values '() bol)))

(defun emit-string (string)
  "A piece that emits STRING as text."
  (lambda (bol) (values (list string) (bol-after-string string bol))))

(defun emit-newline ()
  "A piece that emits a newline, as cmark does when it writes one outright."
  (emit-string (string #\Newline)))

(defun emit-cr ()
  "A piece that emits a newline unless the output so far is empty or already
ends in one: cmark_html_render_cr (src/html.h)."
  (lambda (bol)
    (values (if bol '() (list (string #\Newline))) t)))

(defun emit-list (pieces)
  "A piece that runs the list PIECES in order."
  (lambda (bol) (run-pieces pieces bol)))

(defun emit-all (&rest pieces)
  "A piece that runs PIECES in order."
  (emit-list pieces))

(defun emit-element (tag attributes &rest pieces)
  "A piece that emits one element: TAG with ATTRIBUTES, whose children are
what PIECES emit after its start tag. A start tag and an end tag each leave
the output mid-line."
  (lambda (bol)
    (declare (ignore bol))
    (values (list (list* tag attributes (normalize-items (run-pieces pieces nil))))
            nil)))

(defun attribute (name value)
  "An attribute pair: NAME with a fresh copy of the string VALUE."
  (list name (copy-seq value)))

;;; Children

(defun child-pieces (node context)
  "The pieces that render NODE's children, each in its own context. CONTEXT
is NODE's."
  (loop for child in (node-children node)
        for index from 0
        collect (convert-node child (child-context context node index))))

(defun emit-children (node context)
  "A piece that renders NODE's children in order. CONTEXT is NODE's."
  (emit-list (child-pieces node context)))

;;; Blocks (html.c, and tasklist.c for task items)

(defun convert-block-quote (node context)
  "cr, <blockquote>, a newline, the children, cr, </blockquote>, a newline."
  (emit-all (emit-cr)
            (emit-element :blockquote '()
                          (emit-newline)
                          (emit-children node context)
                          (emit-cr))
            (emit-newline)))

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

(defun convert-list (node context)
  "cr, <ul> or <ol>, a newline, the items, the end tag, a newline."
  (emit-all (emit-cr)
            (emit-element (list-tag node) (list-attributes node)
                          (emit-newline)
                          (emit-children node context))
            (emit-newline)))

(defun convert-item (node context)
  "cr, <li>, the children, </li>, a newline."
  (emit-all (emit-cr)
            (emit-element :li '() (emit-children node context))
            (emit-newline)))

(defun checkbox-attributes (checked)
  "The attributes of a task item's checkbox, ticked when CHECKED."
  (list* (attribute :type "checkbox")
         (if checked
             (list (attribute :checked "") (attribute :disabled ""))
             (list (attribute :disabled "")))))

(defun convert-task-item (node context)
  "cr, <li>, the checkbox, a space, the children, </li>, a newline."
  (emit-all (emit-cr)
            (emit-element :li '()
                          (emit-element :input (checkbox-attributes (node-attribute node :checked)))
                          (emit-string " ")
                          (emit-children node context))
            (emit-newline)))

(defun tight-list-p (node)
  "True when NODE is a :LIST node with :TIGHT T."
  (and node
       (eql (node-kind node) :list)
       (node-attribute node :tight)))

(defun convert-paragraph (node context &optional (tail (emit-nothing)))
  "In a tight list, when the paragraph's grandparent is a :LIST with :TIGHT T,
only its children. Otherwise cr, <p>, the children, TAIL, </p>, a newline.
TAIL is where a footnote's backrefs go."
  (if (tight-list-p (context-grandparent context))
      (emit-children node context)
      (emit-all (emit-cr)
                (emit-element :p '() (emit-children node context) tail)
                (emit-newline))))

(defun heading-tag (level)
  "The tag of a heading of LEVEL, 1 to 6."
  (ecase level
    (1 :h1) (2 :h2) (3 :h3) (4 :h4) (5 :h5) (6 :h6)))

(defun convert-heading (node context)
  "cr, <hN>, the children, </hN>, a newline."
  (emit-all (emit-cr)
            (emit-element (heading-tag (node-attribute node :level)) '()
                          (emit-children node context))
            (emit-newline)))

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

(defun convert-code-block (node)
  "cr, <pre><code>, the literal, </code></pre>, a newline."
  (emit-all (emit-cr)
            (emit-element :pre '()
                          (emit-element :code (code-block-attributes (node-attribute node :info))
                                        (emit-string (node-attribute node :literal))))
            (emit-newline)))

(defun emit-raw-html (node context)
  "A piece for NODE's raw HTML: cmark's comment under :RAW-HTML :OMIT, and
NODE's literal as text under :TEXT."
  (ecase (raw-html-policy context)
    (:omit (emit-element :*comment* '() (emit-string " raw HTML omitted ")))
    (:text (emit-string (node-attribute node :literal)))))

(defun convert-html-block (node context)
  "cr, the raw HTML, cr."
  (emit-all (emit-cr) (emit-raw-html node context) (emit-cr)))

(defun convert-thematic-break ()
  "cr, <hr />, a newline."
  (emit-all (emit-cr) (emit-element :hr '()) (emit-newline)))

;;; Tables (table.c)

(defun convert-table (node context)
  "cr, <table>, the children, cr, </table>, cr. The first :TABLE-ROW child
opens a tbody that holds it and every child after it; a table without one
has no tbody."
  (let* ((pieces (child-pieces node context))
         (body-start (position :table-row (node-children node) :key #'node-kind)))
    (emit-all (emit-cr)
              (emit-element :table '()
                            (emit-list (subseq pieces 0 body-start))
                            (if body-start
                                (emit-table-body (nthcdr body-start pieces))
                                (emit-nothing))
                            (emit-cr))
              (emit-cr))))

(defun emit-table-body (pieces)
  "cr, <tbody>, cr, the rows PIECES render, cr, </tbody>, cr: what the first
body row opens, and the table's end closes."
  (emit-all (emit-cr)
            (emit-element :tbody '() (emit-cr) (emit-list pieces) (emit-cr))
            (emit-cr)))

(defun convert-table-header (node context)
  "cr, <thead>, cr, <tr>, the cells, cr, </tr>, cr, </thead>."
  (emit-all (emit-cr)
            (emit-element :thead '()
                          (emit-cr)
                          (emit-element :tr '() (emit-children node context) (emit-cr))
                          (emit-cr))))

(defun convert-table-row (node context)
  "cr, <tr>, the cells, cr, </tr>."
  (emit-all (emit-cr)
            (emit-element :tr '() (emit-children node context) (emit-cr))))

(defun cell-attributes (align)
  "The attributes of a table cell whose :ALIGN is ALIGN."
  (ecase align
    ((nil) '())
    (:left (list (attribute :align "left")))
    (:center (list (attribute :align "center")))
    (:right (list (attribute :align "right")))))

(defun convert-table-cell (node context)
  "cr, then <th> inside the header row or <td> elsewhere, holding the
children."
  (emit-all (emit-cr)
            (emit-element (if (context-in-table-header context) :th :td)
                          (cell-attributes (node-attribute node :align))
                          (emit-children node context))))

;;; Inlines (html.c, and strikethrough.c for :STRIKETHROUGH)

(defun emit-line-break ()
  "<br /> and a newline."
  (emit-all (emit-element :br '()) (emit-newline)))

(defun convert-softbreak (context)
  "A newline, a space, or a line break, by the :SOFTBREAK policy."
  (ecase (softbreak-policy context)
    (:newline (emit-newline))
    (:space (emit-string " "))
    (:br (emit-line-break))))

(defun strong-node-p (node)
  "True when NODE is a :STRONG node."
  (and node (eql (node-kind node) :strong)))

(defun convert-strong (node context)
  "<strong> holding the children, or only the children when the parent is
itself a :STRONG."
  (if (strong-node-p (context-parent context))
      (emit-children node context)
      (emit-element :strong '() (emit-children node context))))

(defun destination-url (node context)
  "The :DESTINATION of a :LINK or :IMAGE NODE, percent-encoded, or \"\" when
the link policy is :SAFE and it is dangerous. The check runs on the raw
destination (design §5.5)."
  (let ((destination (node-attribute node :destination)))
    (if (and (eql (link-policy context) :safe) (dangerous-url-p destination))
        ""
        (href-encode destination))))

(defun title-attributes (node)
  "A title attribute for a :LINK or :IMAGE NODE, or none when its title is
empty."
  (let ((title (node-attribute node :title)))
    (if (zerop (length title))
        '()
        (list (attribute :title title)))))

(defun convert-link (node context)
  "<a> with href and title, holding the children."
  (emit-element :a (list* (attribute :href (destination-url node context))
                          (title-attributes node))
                (emit-children node context)))

(defun convert-image (node context)
  "<img /> with src, alt and title."
  (emit-element :img (list* (attribute :src (destination-url node context))
                            (attribute :alt (alt-text node context))
                            (title-attributes node))))

;;; Alt text: cmark's plain mode (html.c, renderer->plain)

(defun write-plain-text (node path plan out)
  "Write NODE's plain text, as an image's alt, to OUT: a :TEXT, :CODE or
:HTML-INLINE literal, a space for a break, a dangling reference's text, and
otherwise its children's. PATH is NODE's place, and PLAN the tree's
FOOTNOTE-PLAN. A definition leaves its place, so it adds nothing."
  (ecase (node-kind node)
    ((:text :code :html-inline) (write-string (node-attribute node :literal) out))
    ((:softbreak :linebreak) (write-char #\Space out))
    (:footnote-reference
     (unless (reference-citation plan path)
       (write-string (dangling-reference-text node) out)))
    (:footnote-definition nil)
    ((:document :block-quote :list :item :task-item :paragraph :heading :code-block
      :html-block :thematic-break :table :table-header :table-row :table-cell
      :emph :strong :strikethrough :link :image)
     (write-plain-children node path plan out))))

(defun write-plain-children (node path plan out)
  "Write the plain text of NODE's children to OUT. PATH is NODE's place."
  (loop for child in (node-children node)
        for index from 0
        do (write-plain-text child (child-path path index) plan out)))

(defun alt-text (node context)
  "The alt text of an :IMAGE NODE: the plain text of its descendants."
  (with-output-to-string (out)
    (write-plain-children node (context-path context) (context-footnote-plan context) out)))

;;; Footnotes (html.c; the pre-pass is footnotes.lisp)

(defun dangling-reference-text (node)
  "The text a :FOOTNOTE-REFERENCE NODE becomes when nothing resolves it."
  (concatenate 'string "[^" (footnote-label node) "]"))

(defun footnote-anchor (footnote)
  "FOOTNOTE's label, percent-encoded, as its ids and hrefs carry it."
  (href-encode (footnote-label (footnote-definition footnote))))

(defun reference-id (footnote k)
  "The id of the K-th reference to FOOTNOTE: fnref-L, then fnref-L-K."
  (if (= k 1)
      (concatenate 'string "fnref-" (footnote-anchor footnote))
      (format nil "fnref-~A-~D" (footnote-anchor footnote) k)))

(defun emit-footnote-reference (footnote k)
  "The K-th reference to FOOTNOTE: a sup holding a link to it, which reads
as its number."
  (emit-element :sup (list (attribute :class "footnote-ref"))
                (emit-element :a (list (attribute :href (concatenate 'string "#fn-"
                                                                     (footnote-anchor footnote)))
                                       (attribute :id (reference-id footnote k))
                                       (attribute :data-footnote-ref ""))
                              (emit-string (format nil "~D" (footnote-number footnote))))))

(defun convert-footnote-reference (node context)
  "A resolving reference's sup, or the text of a dangling one."
  (let ((citation (reference-citation (context-footnote-plan context) (context-path context))))
    (if citation
        (emit-footnote-reference (car citation) (cdr citation))
        (emit-string (dangling-reference-text node)))))

(defun emit-backref (footnote k)
  "The backref anchor to the K-th reference to FOOTNOTE
(S_put_footnote_backref). From the second on, it names K in its index and
label, and shows K in a sup after the arrow."
  (let ((index (if (= k 1)
                   (format nil "~D" (footnote-number footnote))
                   (format nil "~D-~D" (footnote-number footnote) k))))
    (emit-element :a (list (attribute :href (concatenate 'string "#" (reference-id footnote k)))
                           (attribute :class "footnote-backref")
                           (attribute :data-footnote-backref "")
                           (attribute :data-footnote-backref-idx index)
                           (attribute :aria-label (concatenate 'string "Back to reference "
                                                               index)))
                  (emit-string (string (code-char #x21A9)))
                  (if (= k 1)
                      (emit-nothing)
                      (emit-element :sup (list (attribute :class "footnote-ref"))
                                    (emit-string (format nil "~D" k)))))))

(defun emit-backrefs (footnote)
  "One backref per reference to FOOTNOTE, separated by spaces."
  (emit-list (loop for k from 1 to (footnote-reference-count footnote)
                   append (if (= k 1)
                              (list (emit-backref footnote k))
                              (list (emit-string " ") (emit-backref footnote k))))))

(defun definition-node-p (node)
  "True when NODE is a :FOOTNOTE-DEFINITION node."
  (eql (node-kind node) :footnote-definition))

(defun backref-paragraph-index (definition)
  "The index of DEFINITION's last child, definitions aside, when that child
is a :PARAGRAPH: the backrefs go at its end. NIL otherwise. Definitions are
set aside because each one leaves its place."
  (let* ((children (node-children definition))
         (index (position-if-not #'definition-node-p children :from-end t)))
    (and index
         (eql (node-kind (nth index children)) :paragraph)
         index)))

(defun emit-footnote-body (footnote context)
  "The children of FOOTNOTE's definition, whose context is CONTEXT, with its
backrefs: inside its last paragraph after a space, or else after the
children and followed by a newline."
  (let* ((definition (footnote-definition footnote))
         (paragraph-index (backref-paragraph-index definition))
         (pieces (loop for child in (node-children definition)
                       for index from 0
                       for child-context = (child-context context definition index)
                       collect (if (eql index paragraph-index)
                                   (convert-paragraph child child-context
                                                      (emit-all (emit-string " ")
                                                                (emit-backrefs footnote)))
                                   (convert-node child child-context)))))
    (if paragraph-index
        (emit-list pieces)
        (emit-all (emit-list pieces) (emit-backrefs footnote) (emit-newline)))))

(defun emit-footnote-item (footnote document settings)
  "<li id=\"fn-L\">, a newline, the body, </li>, a newline. The definition
renders as a child of DOCUMENT, where cmark's parser moves it, but keeps the
path of the place it was kept from, so the references inside it are found
in the FOOTNOTE-PLAN."
  (emit-all (emit-element :li (list (attribute :id (concatenate 'string "fn-"
                                                                 (footnote-anchor footnote))))
                          (emit-newline)
                          (emit-footnote-body footnote
                                              (make-context settings document nil
                                                            (footnote-path footnote) nil)))
            (emit-newline)))

(defun emit-footnote-section (document settings)
  "The section of surviving footnotes, in number order, and a newline after
it; nothing when none survive. It comes straight after the rest, with no cr
before it, as in cmark."
  (let ((footnotes (footnote-plan-footnotes (settings-footnotes settings))))
    (if (null footnotes)
        (emit-nothing)
        (emit-all (emit-element :section (list (attribute :class "footnotes")
                                               (attribute :data-footnotes ""))
                                (emit-newline)
                                (emit-element :ol '()
                                              (emit-newline)
                                              (emit-list
                                               (loop for footnote in footnotes
                                                     collect (emit-footnote-item
                                                              footnote document settings))))
                                (emit-newline))
                  (emit-newline)))))

;;; Dispatch

(defun convert-node (node context)
  "The piece that renders NODE in CONTEXT, following cmark's S_render_node
(design §5.3). A definition renders nothing where it stands: the footnote
section renders it. CHECK-NO-EXTENSION-NODES has already ruled out
:EXTENSION."
  (ecase (node-kind node)
    (:document (emit-children node context))
    (:block-quote (convert-block-quote node context))
    (:list (convert-list node context))
    (:item (convert-item node context))
    (:task-item (convert-task-item node context))
    (:paragraph (convert-paragraph node context))
    (:heading (convert-heading node context))
    (:code-block (convert-code-block node))
    (:html-block (convert-html-block node context))
    (:thematic-break (convert-thematic-break))
    (:table (convert-table node context))
    (:table-header (convert-table-header node context))
    (:table-row (convert-table-row node context))
    (:table-cell (convert-table-cell node context))
    (:text (emit-string (node-attribute node :literal)))
    (:softbreak (convert-softbreak context))
    (:linebreak (emit-line-break))
    (:code (emit-element :code '() (emit-string (node-attribute node :literal))))
    (:html-inline (emit-raw-html node context))
    (:emph (emit-element :em '() (emit-children node context)))
    (:strong (convert-strong node context))
    (:strikethrough (emit-element :del '() (emit-children node context)))
    (:link (convert-link node context))
    (:image (convert-image node context))
    (:footnote-reference (convert-footnote-reference node context))
    (:footnote-definition (emit-nothing))))

;;; AST->HTML-TREE

(defun find-extension-node (node)
  "The first :EXTENSION node in NODE's tree, depth-first, or NIL."
  (if (eql (node-kind node) :extension)
      node
      (some #'find-extension-node (node-children node))))

(defun check-no-extension-nodes (root)
  "Signal UNSUPPORTED-EXTENSION-NODE, naming the node, when ROOT's tree holds
an :EXTENSION node anywhere (design D10)."
  (let ((extension (find-extension-node root)))
    (when extension
      (error 'unsupported-extension-node
             :operation 'ast->html-tree
             :datum extension
             :reason "extension nodes have no HTML tree"))))

(defun as-document (node)
  "NODE when it is a :DOCUMENT, and otherwise a new document holding only
NODE."
  (if (eql (node-kind node) :document)
      node
      (make-node :document :children (list node))))

(defun document-items (document settings)
  "The top-level items of DOCUMENT: its children, then the footnote section,
starting from an empty output."
  (let ((context (make-context settings nil nil (root-path) nil)))
    (normalize-items (run-pieces (list (convert-node document context)
                                       (emit-footnote-section document settings))
                                 t))))

(defun ast->html-tree (node &rest options)
  "Convert the AST NODE into an HTML tree, as cmark-gfm's HTML renderer
would render it (design §5). Returns a list of top-level items, strings and
elements, with cmark's newlines as \"\\n\" strings; or, with
:DOCUMENT-WRAPPER, one element of that tag holding them. A NODE that isn't a
:DOCUMENT converts as a document's only child.

OPTIONS (ADR-0012), each value's default first:
  :RAW-HTML :OMIT | :TEXT
  :SOFTBREAK :NEWLINE | :SPACE | :BR
  :LINK-POLICY :SAFE | :UNSAFE
  :DOCUMENT-WRAPPER NIL | a keyword naming a non-void element

Signals INVALID-RENDER-OPTION for a malformed option list, an unknown key or
a bad value, before converting anything; and UNSUPPORTED-EXTENSION-NODE when
the tree holds an :EXTENSION node. Returns a fresh tree, and leaves NODE as
it was."
  (check-options options)
  (check-no-extension-nodes node)
  (let* ((document (as-document node))
         (settings (make-settings (option-value options :raw-html)
                                  (option-value options :softbreak)
                                  (option-value options :link-policy)
                                  (plan-footnotes document)))
         (items (document-items document settings))
         (wrapper (option-value options :document-wrapper)))
    (if wrapper
        (list* wrapper '() items)
        items)))
