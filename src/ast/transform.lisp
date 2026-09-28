;;;; AST traversal and transformation: FOLD-AST, MAP-AST and TRANSFORM-AST.

(in-package #:cl-commonmark-gfm.ast)

;;; FOLD-AST and MAP-AST

(defun fold-ast (function initial-value node)
  "Fold FUNCTION over NODE and its descendants, depth-first and parent
before children. Calls (FUNCALL FUNCTION NODE ACCUMULATOR), starting
ACCUMULATOR at INITIAL-VALUE, and returns the final accumulator."
  (let ((accumulator (funcall function node initial-value)))
    (dolist (child (node-children node) accumulator)
      (setf accumulator (fold-ast function accumulator child)))))

(defun map-ast (function node)
  "Return the list of (FUNCALL FUNCTION N) for NODE and each descendant,
visited depth-first, parent before children, in that order."
  ;; One accumulator, pushed in preorder and reversed once at the end, so
  ;; each descendant's cons is made exactly once: linear in the number of
  ;; nodes rather than nodes times depth. Consing the result of each
  ;; recursive call onto the next (as MAP-AST used to) instead re-walks
  ;; every descendant's result list once per ancestor.
  (let ((results '()))
    (labels ((visit (n)
               (push (funcall function n) results)
               (dolist (child (node-children n))
                 (visit child))))
      (visit node))
    (nreverse results)))

;;; TRANSFORM-AST

(defun transform-subtree (function node)
  "Transform NODE and its descendants bottom-up. Returns the list of zero or
more nodes that NODE became, per TRANSFORM-AST's contract."
  (let* ((old-children (node-children node))
         (new-children (loop for child in old-children
                              append (transform-subtree function child)))
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
children have already been transformed, and returns a node, a list of nodes
to splice into the parent, or NIL to delete the node. Returns the single
resulting root node; signals INVALID-AST-NODE when the root does not come
back as exactly one node."
  (let ((results (transform-subtree function node)))
    (if (and results (null (rest results)))
        (first results)
        (error 'invalid-ast-node
               :operation 'transform-ast
               :datum results
               :reason "root did not transform to exactly one node"))))
