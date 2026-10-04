;;;; The footnote pre-pass: resolving, numbering and placing footnotes (M1
;;;; design §5.4; M2 design §4.4).
;;;;
;;;; cmark's parser rewrites footnotes before its HTML renderer runs
;;;; (process_footnotes in src/blocks.c). This pure pre-pass does the same
;;;; work for any AST, without changing it: it decides which definitions
;;;; survive, numbers them, and gives each resolving reference its index
;;;; among its definition's references (ADR-0014's steps 1 to 4). The
;;;; converter (convert.lisp) then renders the survivors in one section after
;;;; everything else.
;;;;
;;;; Nodes are immutable, so one node object may sit at several places in a
;;;; tree, and each place is its own definition or reference. Places are
;;;; therefore told apart by where a walk meets them, never by node identity.

(in-package #:cl-commonmark-gfm.html-tree)

;;; Places: owners and ordinals (M2 design §4.4)
;;;
;;; Every reference place has an owner: the document body, or the innermost
;;; definition place around it. The body is owner 0, and definition places
;;; are owners 1, 2, ... in the order a walk enters them. A reference place
;;; is keyed by its owner and its ordinal: 1, 2, ... among that owner's
;;; references, in the order a walk enters them.
;;;
;;; The converter counts the same way. Its main walk is the body's owner,
;;; and skips definitions where they stand. The section then renders each
;;; surviving definition as its own owner, with a fresh count, skipping the
;;; definitions nested in it. The pre-pass and the converter meet each
;;; owner's references in the same order, so their keys agree. Each
;;; definition renders away from its place: after the body, and after any
;;; definition around it. So the converter meets references in a different
;;; order from the tree. A count kept per owner still comes out the same in
;;; the pre-pass and in the converter; one count over the whole tree would
;;; not. Both build keys with CITATION-KEY, and in no other way: were two to
;;; disagree, no lookup would match, and every resolving reference would
;;; render as the dangling text [^label].

(defconstant +body-owner+ 0
  "The owner of every reference place that no definition place contains.")

(defun citation-key (owner ordinal)
  "The key of the reference place that is OWNER's ORDINAL-th reference.
Keys compare with EQUAL."
  (cons owner ordinal))

(defun footnote-label (node)
  "The :LABEL of NODE, a :FOOTNOTE-DEFINITION or :FOOTNOTE-REFERENCE."
  (node-attribute node :label))

(defun unsupported-extension (node)
  "Signal UNSUPPORTED-EXTENSION-NODE for AST->HTML-TREE, naming NODE, an
:EXTENSION node (M1 design D10)."
  (error 'unsupported-extension-node
         :operation 'ast->html-tree
         :datum node
         :reason "extension nodes have no HTML tree"))

(defun find-places (root)
  "Walk ROOT's tree once, ROOT included (M2 design §4.4), and return three
lists:
- every definition place, as a (NODE . OWNER) cons, where OWNER is the
  place's number as an owner, in the order the walk enters the places,
  parents before children, which is tree order;
- the same conses in the order the walk leaves the places, children before
  parents;
- every reference place, as a (NODE . KEY) cons, where KEY is its
  CITATION-KEY, in the order the walk enters them.
The conses are fresh, so each place has its own. Signals
UNSUPPORTED-EXTENSION-NODE at the first :EXTENSION node the walk enters."
  (let ((owners (list (cons +body-owner+ 0)))
        (open-definitions '())
        (definition-count 0)
        (entered '())
        (left '())
        (references '()))
    ;; OWNERS holds an (OWNER . REFERENCES-SO-FAR) cons for the body and for
    ;; each definition place the walk is inside, innermost first;
    ;; OPEN-DEFINITIONS holds those definition places.
    (walk-ast (lambda (event node)
                (ecase event
                  (:enter
                   (case (node-kind node)
                     (:extension (unsupported-extension node))
                     (:footnote-definition
                      (let ((place (cons node (incf definition-count))))
                        (push place entered)
                        (push place open-definitions)
                        (push (cons (cdr place) 0) owners)))
                     (:footnote-reference
                      (let ((owner (first owners)))
                        (push (cons node (citation-key (car owner) (incf (cdr owner))))
                              references)))
                     (otherwise nil)))
                  (:exit
                   (when (eql (node-kind node) :footnote-definition)
                     (push (pop open-definitions) left)
                     (pop owners)))))
              root)
    (values (nreverse entered) (nreverse left) (nreverse references))))

;;; What the converter reads

(defstruct (footnote
            (:constructor make-footnote (definition owner number reference-count))
            (:copier nil))
  "A surviving footnote definition (M1 design §5.4 step 3): the DEFINITION
node, the OWNER number of the place it was kept from, its NUMBER, and
REFERENCE-COUNT, how many references resolve to it."
  (definition nil :read-only t)
  (owner nil :read-only t)
  (number nil :read-only t)
  (reference-count nil :read-only t))

(defstruct (footnote-plan
            (:constructor make-footnote-plan (footnotes citations))
            (:copier nil))
  "The pre-pass's result. FOOTNOTES lists the survivors in number order.
CITATIONS is an EQUAL hash table from the CITATION-KEY of each resolving
reference to (FOOTNOTE . K): the footnote it resolves to, and its index K
among that footnote's references."
  (footnotes '() :read-only t)
  (citations nil :read-only t))

(defun reference-citation (plan key)
  "(FOOTNOTE . K) for the reference place whose CITATION-KEY is KEY under
PLAN, or NIL when that reference is dangling."
  (values (gethash key (footnote-plan-citations plan))))

;;; The label table (M4 design §5.7)
;;;
;;; Labels match with STRING=, so an EQUAL hash table would do, but CCL
;;; hashes short strings into few, clustered values. An EQUAL table of
;;; 71,705 labels of one to four characters took 3.6 s on CCL, and 0.02 s
;;; on SBCL. So a label table hashes each label itself, with LABEL-HASH,
;;; into an EQL hash table, whose values are buckets: alists from label to
;;; value, searched with STRING=, for the labels that share a hash.

(defun label-hash (label)
  "The 32-bit FNV-1a hash of LABEL's character codes, a fixnum. It spreads
short labels that differ in one character, where SXHASH can cluster."
  (let ((hash 2166136261))
    (loop for char across label
          do (setf hash (logand (* (logxor hash (char-code char)) 16777619) #xFFFFFFFF)))
    hash))

(defun make-label-table ()
  "An empty label table."
  (make-hash-table :test 'eql))

(defun label-value (table label)
  "The value TABLE holds for LABEL, and true when it holds one; or NIL and
NIL. Labels compare with STRING=, so labels differing only in case are
different labels."
  (let ((entry (assoc label (gethash (label-hash label) table) :test #'string=)))
    (values (cdr entry) (and entry t))))

(defun add-label-value (table label value)
  "Make TABLE hold VALUE for LABEL, which it holds nothing for yet."
  (push (cons label value) (gethash (label-hash label) table)))

;;; The pre-pass (M1 design §5.4 steps 1 to 4)

(defun first-definitions (definitions)
  "Step 1: a label table from each label to the first place in DEFINITIONS
that has it; later places with the same label are dropped. DEFINITIONS
lists places in the order the walk leaves them, the order cmark's parser
registers definitions in, so the first is the one it keeps."
  (let ((table (make-label-table)))
    (dolist (place definitions table)
      (let ((label (footnote-label (car place))))
        (unless (nth-value 1 (label-value table label))
          (add-label-value table label place))))))

(defun resolve-references (references kept)
  "Step 2: resolve each place in REFERENCES, a list of reference places in
tree order, through KEPT, the label table from FIRST-DEFINITIONS. Returns
two values: the resolving references in order, each as (KEY DEFINITION K),
where DEFINITION is the kept definition's place and K counts its references
so far; and an EQL hash table from each such place to its reference count."
  (let ((counts (make-hash-table :test 'eql)))
    (values (loop for (reference . key) in references
                  for definition = (label-value kept (footnote-label reference))
                  when definition
                    collect (list key definition (incf (gethash definition counts 0))))
            counts)))

(defun number-footnotes (definitions counts)
  "Step 3: the survivors among DEFINITIONS, a list of definition places in
tree order, are the places COUNTS holds: the kept definitions that at least
one reference resolves to. Returns them as FOOTNOTEs numbered 1, 2, ... in
tree order, and an EQL hash table from each surviving place to its
FOOTNOTE."
  (let ((footnotes (make-hash-table :test 'eql))
        (number 0))
    (values (loop for place in definitions
                  for count = (gethash place counts)
                  when count
                    collect (setf (gethash place footnotes)
                                  (make-footnote (car place) (cdr place) (incf number) count)))
            footnotes)))

(defun citation-table (resolutions footnotes)
  "Step 4: an EQUAL hash table from the CITATION-KEY of each resolving
reference in RESOLUTIONS, from RESOLVE-REFERENCES, to (FOOTNOTE . K).
FOOTNOTES maps each surviving place to its FOOTNOTE, as NUMBER-FOOTNOTES
returns it."
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key definition k) in resolutions
          do (setf (gethash key table) (cons (gethash definition footnotes) k)))
    table))

(defun plan-footnotes (root)
  "Run the footnote pre-pass over ROOT (M1 design §5.4; M2 design §4.4) and
return its FOOTNOTE-PLAN. One WALK-AST finds the places; no step recurses.
Definitions and references are found everywhere in the tree, inside
definitions (even dropped ones) and images included. Labels match with
STRING=. Of the definitions sharing a label, the first the walk leaves is
kept, and survivors are numbered in the order they appear. Signals
UNSUPPORTED-EXTENSION-NODE, naming the first :EXTENSION node in ROOT's tree,
depth-first."
  (multiple-value-bind (tree-order exit-order references) (find-places root)
    (multiple-value-bind (resolutions counts)
        (resolve-references references (first-definitions exit-order))
      (multiple-value-bind (survivors footnotes) (number-footnotes tree-order counts)
        (make-footnote-plan survivors (citation-table resolutions footnotes))))))
