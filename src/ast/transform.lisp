;;;; AST traversal and transformation: WALK-AST, the one AST traversal (M2
;;;; design §4.1, D8), and FOLD-AST, MAP-AST and TRANSFORM-AST, built on it
;;;; (M1 design §4.5; M2 design §4.2). Every walk here loops over an
;;;; explicit stack instead of recursing, so depth is bounded by memory
;;;; rather than by the Lisp call stack (M2 design D2).

(in-package #:cl-commonmark-gfm.ast)

;;; WALK-AST

(defun walk-ast (function node)
  "Visit NODE and its descendants depth-first, children in order, calling
FUNCTION with :ENTER before a node's children and with :EXIT after them (M2
design §4.1); a leaf gets both calls. When an :ENTER call returns :SKIP,
that node's children and its :EXIT call are skipped; every other returned
value is ignored. Returns NIL.

Loops over an explicit stack of frames -- each holding a node and the
children it has not yet visited -- instead of recursing, so depth is
bounded by memory rather than by the Lisp call stack, and reads children
through the internal %NODE-CHILDREN, which (unlike NODE-CHILDREN) does not
copy. Signals a TYPE-ERROR, via CHECK-TYPE, when NODE is not a NODE, before
FUNCTION is ever called. Whatever FUNCTION signals propagates out of
WALK-AST, abandoning the walk.

This is the one AST traversal (M2 design D8): FOLD-AST, MAP-AST,
TRANSFORM-AST and every HTML-tree walk are built on it."
  (check-type node node)
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
before children: ACCUMULATOR starts at INITIAL-VALUE, and each call is
(FUNCALL FUNCTION NODE ACCUMULATOR). Returns the final accumulator.

Acts on WALK-AST's :ENTER events, so it keeps M1's call order and results
(M1 design §4.5) without recursing over NODE's depth (M2 design §4.2)."
  (let ((accumulator initial-value))
    (walk-ast (lambda (event n)
                (when (eql event :enter)
                  (setf accumulator (funcall function n accumulator))))
              node)
    accumulator))

(defun map-ast (function node)
  "Return the list of (FUNCALL FUNCTION N) for NODE and each descendant,
visited depth-first, parent before children, in that order.

Acts on WALK-AST's :ENTER events, so it keeps M1's call order and results
(M1 design §4.5) without recursing over NODE's depth (M2 design §4.2).
Results are pushed in preorder and reversed once at the end, so each
descendant's cons is made exactly once: linear in the number of nodes
rather than nodes times depth."
  (let ((results '()))
    (walk-ast (lambda (event n)
                (when (eql event :enter)
                  (push (funcall function n) results)))
              node)
    (nreverse results)))

;;; TRANSFORM-AST

(defstruct (transform-frame
             (:constructor make-transform-frame (node remaining))
             (:conc-name %frame-)
             (:copier nil))
  "One TRANSFORM-AST stack frame: NODE, and its REMAINING not-yet-transformed
children (a tail of NODE's own child list, read through %NODE-CHILDREN).
COLLECTED gathers NODE's already-transformed children, consed on in reverse
order as each one finishes, and reversed once when NODE itself finishes."
  node
  remaining
  (collected nil))

(defun finish-transform-frame (function frame)
  "Rebuild FRAME's node with COPY-NODE, only when its transformed children
differ from its old ones -- M1's comparison: EQUAL on the two lists, so the
same length and EQ elements -- call FUNCTION on it, and return the list of
zero or more nodes FUNCTION's result represents, per TRANSFORM-AST's
contract (M1 design §4.5). Signals INVALID-AST-NODE, with M1's reason and
datum, when FUNCTION's result is neither a node nor a proper list of
nodes."
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
single resulting root node; signals INVALID-AST-NODE, with M1's reason and
datum, when the root does not come back as exactly one node. When no child
of a node changed, FUNCTION is called on that same node object, not a copy
(M1 design §4.5).

Loops over an explicit stack of frames, each collecting its node's
transformed children in order, instead of recursing, so depth is bounded by
memory rather than by the Lisp call stack (M2 design §4.2)."
  (let ((stack (list (make-transform-frame node (%node-children node)))))
    (loop
      (let ((frame (first stack)))
        (cond
          ;; FRAME's node still has children to transform: descend into the
          ;; next one, pushing a frame for it.
          ((%frame-remaining frame)
           (let ((child (pop (%frame-remaining frame))))
             (push (make-transform-frame child (%node-children child)) stack)))
          ;; FRAME's node is done: pop it, finish it, and hand the result to
          ;; its parent's frame, now on top -- or, when the stack is now
          ;; empty, FRAME was the root, so return.
          (t
           (pop stack)
           (let ((result (finish-transform-frame function frame)))
             (if stack
                 (dolist (r result)
                   (push r (%frame-collected (first stack))))
                 (return (if (and result (null (rest result)))
                             (first result)
                             (error 'invalid-ast-node
                                    :operation 'transform-ast
                                    :datum result
                                    :reason "root did not transform to exactly one node")))))))))))
