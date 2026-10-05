;;;; AST traversal and transformation: WALK-AST, and FOLD-AST, MAP-AST and
;;;; TRANSFORM-AST, built on it. WALK-AST loops over an explicit stack
;;;; instead of recursing, so depth is bounded by memory rather than by the
;;;; Lisp call stack. cmark-gfm parses trees deeper than the Lisps' stacks
;;;; allow a recursive walk: its own stress tests nest 130,000 levels
;;;; (vendor/cmark-gfm/test/pathological_tests.py).

(in-package #:cl-commonmark-gfm.ast)

;;; WALK-AST

(defun walk-ast (function node)
  "Visit NODE and its descendants depth-first, children in order, calling
FUNCTION with :ENTER and each node before its children, and with :EXIT and
the node after them; a leaf gets both calls. When an :ENTER call returns
:SKIP, that node's children and its :EXIT call are skipped; every other
returned value is ignored. Returns NIL.

Memory, not the Lisp call stack, bounds NODE's depth, and, unlike
NODE-CHILDREN, it reads each node's children without copying them. Signals
a TYPE-ERROR when NODE is not a NODE, before FUNCTION is ever called.
Whatever FUNCTION signals propagates out of WALK-AST, abandoning the walk."
  (check-type node node)
  ;; FOLD-AST, MAP-AST, TRANSFORM-AST and AST->HTML-TREE's walks are all
  ;; built on WALK-AST.
  ;; Each frame is (NODE . CHILDREN), CHILDREN the tail of NODE's own child
  ;; list still to visit. Popping it moves only the frame's CDR, so the
  ;; list, from %NODE-CHILDREN, is never copied or changed.
  (let ((stack '()))
    (flet ((enter (n)
             (unless (eql (funcall function :enter n) :skip)
               (push (cons n (%node-children n)) stack))))
      (enter node)
      (loop while stack
            do (let ((frame (first stack)))
                 (cond ((cdr frame) (enter (pop (cdr frame))))
                       (t (funcall function :exit (car frame))
                          (pop stack))))))
    nil))

;;; FOLD-AST and MAP-AST

(defun fold-ast (function initial-value node)
  "Fold FUNCTION over NODE and its descendants, depth-first and parent
before children: FUNCTION is called with each node and the accumulator,
which starts as INITIAL-VALUE, and returns the next accumulator. Returns
the final accumulator.

Memory, not the Lisp call stack, bounds NODE's depth. Signals a TYPE-ERROR
when NODE is not a NODE."
  (let ((accumulator initial-value))
    (walk-ast (lambda (event n)
                (when (eql event :enter)
                  (setf accumulator (funcall function n accumulator))))
              node)
    accumulator))

(defun map-ast (function node)
  "Return a list of FUNCTION's results on NODE and each descendant,
depth-first, parent before children, in that order.

Memory, not the Lisp call stack, bounds NODE's depth. Signals a TYPE-ERROR
when NODE is not a NODE. Linear in the number of nodes."
  (let ((results '()))
    (walk-ast (lambda (event n)
                (when (eql event :enter)
                  (push (funcall function n) results)))
              node)
    (nreverse results)))

;;; TRANSFORM-AST

(defstruct (transform-frame
             (:constructor make-transform-frame (node))
             (:conc-name %frame-)
             (:copier nil))
  "One TRANSFORM-AST frame: NODE, entered and not yet left, and COLLECTED,
its already-transformed children, consed on in reverse order as each one
finishes, and reversed once when NODE itself finishes."
  node
  (collected nil))

(defun finish-transform-frame (function frame)
  "Rebuild FRAME's node with COPY-NODE, only when its transformed children
differ from its old ones -- EQUAL on the two lists, so the same length and
EQ elements -- call FUNCTION on it, and return the list of zero or more
nodes FUNCTION's result represents, per TRANSFORM-AST's contract. Signals
INVALID-AST-NODE, with that result as its datum, when FUNCTION's result is
neither a node nor a proper list of nodes."
  (let* ((node (%frame-node frame))
         (old-children (%node-children node))
         (new-children (nreverse (%frame-collected frame)))
         (rebuilt (if (equal new-children old-children)
                      node
                      (copy-node node :children new-children)))
         (result (funcall function rebuilt)))
    (cond
      ((node-p result) (list result))
      ;; A proper list of nodes is spliced in; NIL is the empty case of this
      ;; same check, and means "delete this node".
      ((and (proper-list-p result) (every #'node-p result)) result)
      (t (error 'invalid-ast-node
                :operation 'transform-ast
                :datum result
                :reason "transform function must return a node, a list of nodes, or nil")))))

(defun transform-ast (function node)
  "Transform NODE bottom-up: FUNCTION is called on each node after its
children have already been transformed, and returns a node, a list of
nodes to splice into the parent, or NIL to delete the node. Returns the
single resulting root node. Signals INVALID-AST-NODE when FUNCTION returns
anything else, or when the root doesn't come back as exactly one node, bare
or alone in a list; its datum is then what FUNCTION returned. When no child
of a node changed, FUNCTION is called on that same node object, not a copy.

Memory, not the Lisp call stack, bounds NODE's depth. Signals a TYPE-ERROR
when NODE is not a NODE."
  ;; A node's frame is pushed when WALK-AST enters it, and finished when
  ;; WALK-AST leaves it: the result goes into the parent's frame, now on
  ;; top, or, for the root, becomes ROOT-RESULT.
  (let ((frames '())
        (root-result '()))
    (walk-ast (lambda (event n)
                (ecase event
                  (:enter (push (make-transform-frame n) frames))
                  (:exit (let ((result (finish-transform-frame function (pop frames))))
                           (if frames
                               (dolist (r result)
                                 (push r (%frame-collected (first frames))))
                               (setf root-result result)))))
                ;; Never :SKIP: every node is transformed.
                nil)
              node)
    (if (and root-result (null (rest root-result)))
        (first root-result)
        (error 'invalid-ast-node
               :operation 'transform-ast
               :datum root-result
               :reason "root did not transform to exactly one node"))))
