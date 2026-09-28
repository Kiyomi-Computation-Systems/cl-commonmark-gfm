;;;; The footnote pre-pass: resolving, numbering and placing footnotes (design §5.4).
;;;;
;;;; cmark's parser rewrites footnotes before its HTML renderer runs
;;;; (process_footnotes in src/blocks.c). This pure pre-pass does the same
;;;; work for any AST, without changing it: it decides which definitions
;;;; survive, numbers them, and gives each resolving reference its index
;;;; among its definition's references. The converter (convert.lisp) then
;;;; renders the survivors in one section after everything else.
;;;;
;;;; Nodes are immutable, so one node object may sit at several places in a
;;;; tree, and each place is its own reference. Places are therefore told
;;;; apart by their path from the root, never by node identity.

(in-package #:cl-commonmark-gfm.html-tree)

;;; Places
;;;
;;; The plan names each place by its path: the child indices, each counted
;;; from 0, that lead from the root to the place, innermost first. The
;;; pre-pass records paths (OCCURRENCES), and the converter looks them up in
;;; walks of its own (CHILD-CONTEXT, and WRITE-PLAIN-CHILDREN for alt text).
;;; All of them build paths with ROOT-PATH and CHILD-PATH, and in no other
;;; way: were two to disagree, no lookup would match, and every resolving
;;; reference would render as the dangling text [^label].

(defun root-path ()
  "The path of the root's place."
  '())

(defun child-path (path index)
  "The path of the child at INDEX, counted from 0, of the node whose place is
PATH."
  (cons index path))

;;; Occurrences

(defun footnote-label (node)
  "The :LABEL of NODE, a :FOOTNOTE-DEFINITION or :FOOTNOTE-REFERENCE."
  (node-attribute node :label))

(defun occurrences (kind root)
  "Every place in ROOT's tree, ROOT included, that holds a node of KIND, as a
(NODE . PATH) cons, where PATH is the place's path. The conses are fresh, so
each place has its own. Returns two lists of the same conses: in the order a
depth-first walk enters the places, parents before children, which is tree
order; and in the order it leaves them, children before parents."
  (let ((entered '())
        (left '()))
    (labels ((walk (node path)
               (let ((occurrence (and (eql (node-kind node) kind) (cons node path))))
                 (when occurrence
                   (push occurrence entered))
                 (loop for child in (node-children node)
                       for index from 0
                       do (walk child (child-path path index)))
                 (when occurrence
                   (push occurrence left)))))
      (walk root (root-path)))
    (values (reverse entered) (reverse left))))

;;; What the converter reads

(defstruct (footnote
            (:constructor make-footnote (definition path number reference-count))
            (:copier nil))
  "A surviving footnote definition (design §5.4 step 3): the DEFINITION node,
the PATH of the place it was kept from, its NUMBER, and REFERENCE-COUNT, how
many references resolve to it."
  (definition nil :read-only t)
  (path '() :read-only t)
  (number nil :read-only t)
  (reference-count nil :read-only t))

(defstruct (footnote-plan
            (:constructor make-footnote-plan (footnotes citations))
            (:copier nil))
  "The pre-pass's result. FOOTNOTES lists the survivors in number order.
CITATIONS is an EQUAL hash table from the path of each resolving reference
to (FOOTNOTE . K): the footnote it resolves to, and its index K among that
footnote's references."
  (footnotes '() :read-only t)
  (citations nil :read-only t))

(defun reference-citation (plan path)
  "(FOOTNOTE . K) for the footnote reference at PATH under PLAN, or NIL when
that reference is dangling."
  (values (gethash path (footnote-plan-citations plan))))

;;; The pre-pass (design §5.4 steps 1 to 4)

(defun first-definitions (definitions)
  "Step 1: an EQUAL hash table from each label to the first place in
DEFINITIONS that has it; later places with the same label are dropped.
DEFINITIONS lists occurrences in the order the walk leaves them, the order
cmark's parser registers definitions in, so the first is the one it keeps.
EQUAL compares strings as STRING= does, so labels differing only in case
are different labels."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (occurrence definitions table)
      (let ((label (footnote-label (car occurrence))))
        (unless (nth-value 1 (gethash label table))
          (setf (gethash label table) occurrence))))))

(defun resolve-references (references kept)
  "Step 2: resolve each place in REFERENCES, a list of occurrences in tree
order, through KEPT, from FIRST-DEFINITIONS. Returns two values: the
resolving references in order, each as (PATH DEFINITION K), where DEFINITION
is the kept definition's occurrence and K counts its references so far; and
an EQ hash table from each such occurrence to its reference count."
  (let ((counts (make-hash-table :test 'eql)))
    (values (loop for (reference . path) in references
                  for definition = (gethash (footnote-label reference) kept)
                  when definition
                    collect (list path definition (incf (gethash definition counts 0))))
            counts)))

(defun number-footnotes (definitions counts)
  "Step 3: the survivors among DEFINITIONS, a list of occurrences in tree
order, are the places COUNTS holds: the kept definitions that at least one
reference resolves to. Returns them as FOOTNOTEs numbered 1, 2, ... in tree
order, and an EQ hash table from each surviving occurrence to its FOOTNOTE."
  (let ((footnotes (make-hash-table :test 'eql))
        (number 0))
    (values (loop for occurrence in definitions
                  for count = (gethash occurrence counts)
                  when count
                    collect (setf (gethash occurrence footnotes)
                                  (make-footnote (car occurrence) (cdr occurrence)
                                                 (incf number) count)))
            footnotes)))

(defun citation-table (resolutions footnotes)
  "Step 4: an EQUAL hash table from the path of each resolving reference in
RESOLUTIONS, from RESOLVE-REFERENCES, to (FOOTNOTE . K). FOOTNOTES maps each
surviving occurrence to its FOOTNOTE, as NUMBER-FOOTNOTES returns it."
  (let ((table (make-hash-table :test 'equal)))
    (loop for (path definition k) in resolutions
          do (setf (gethash path table) (cons (gethash definition footnotes) k)))
    table))

(defun plan-footnotes (root)
  "Run the footnote pre-pass over ROOT (design §5.4) and return its
FOOTNOTE-PLAN. Definitions and references are found everywhere in the tree,
inside definitions (even dropped ones) and images included. Labels match
with STRING=. Of the definitions sharing a label, the first the walk leaves
is kept, and survivors are numbered in the order they appear."
  (multiple-value-bind (tree-order exit-order) (occurrences :footnote-definition root)
    (multiple-value-bind (resolutions counts)
        (resolve-references (occurrences :footnote-reference root)
                            (first-definitions exit-order))
      (multiple-value-bind (survivors footnotes) (number-footnotes tree-order counts)
        (make-footnote-plan survivors (citation-table resolutions footnotes))))))
