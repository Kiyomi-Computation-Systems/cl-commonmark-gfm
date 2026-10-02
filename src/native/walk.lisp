;;;; WALK-NATIVE: the one walk over a parsed tree (M2 design §5.1). The
;;;; copier, the output-bound walk and startup's smoke parse all use it. It
;;;; follows cmark's own first-child, next and parent pointers, so it keeps
;;;; no stack and has no cmark_iter to free, and depth costs it nothing
;;;; (ADR-0015).

(in-package #:cl-commonmark-gfm.native)

(defun enter-native-node (function document node)
  "Call FUNCTION with :ENTER and NODE. Return NODE's first child when the
walk descends into it. Otherwise return NIL: after calling FUNCTION with
:EXIT when NODE is a leaf, or without when the :ENTER call returned :SKIP."
  (cond
    ((eql (funcall function :enter node) :skip) nil)
    ((native-first-child document node))
    (t (funcall function :exit node)
       nil)))

(defun next-native-node (function document root node)
  "NODE, under ROOT, is done. Return the node the walk enters next: NODE's
next sibling, or else the next sibling of its nearest ancestor that has
one, calling FUNCTION with :EXIT for each ancestor it climbs out of. Return
NIL once it climbs out of ROOT."
  (loop
    (when (cffi:pointer-eq node root)
      (return nil))
    (let ((next (native-next document node)))
      (when next
        (return next)))
    (setf node (native-parent document node))
    (funcall function :exit node)))

(defun walk-native (function document)
  "Visit DOCUMENT's root and every node under it, depth-first, children in
order, with WALK-AST's protocol (M2 design §4.1): (FUNCALL FUNCTION :ENTER
NODE) before a node's children and (FUNCALL FUNCTION :EXIT NODE) after
them, so a leaf gets both. When an :ENTER call returns :SKIP, the node's
children and its :EXIT are skipped; any other value is ignored. Returns
NIL.

NODE is a cmark node pointer, valid only inside DOCUMENT's
WITH-NATIVE-DOCUMENT scope. Each step goes through the alive-checked
accessors, so a released DOCUMENT signals NATIVE-DOCUMENT-RELEASED.
Whatever FUNCTION signals passes through, abandoning the walk."
  (let ((root (native-root document)))
    (loop with node = root
          for child = (enter-native-node function document node)
          do (setf node (or child (next-native-node function document root node)))
          while node)
    nil))
