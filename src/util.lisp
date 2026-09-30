;;;; The cl-commonmark-gfm.util package: small helpers shared by the pure
;;;; systems, starting with a stack-safe PROPER-LIST-P (M2 design §3, §4.6).

(defpackage #:cl-commonmark-gfm.util
  (:use #:cl)
  (:export #:proper-list-p))

(in-package #:cl-commonmark-gfm.util)

;;; PROPER-LIST-P

(defun proper-list-p (value)
  "True when VALUE is a finite, NIL-terminated (proper) list. Uses Floyd's
cycle detection, so a circular list is rejected rather than looping forever."
  (and (listp value)
       (or (null value)
           (loop for slow = value then (cdr slow)
                 for fast = (cdr value) then (cddr fast)
                 do (cond
                      ((null fast) (return t))
                      ((atom fast) (return nil))
                      ((null (cdr fast)) (return t))
                      ((atom (cdr fast)) (return nil))
                      ((eql slow (cdr fast)) (return nil)))))))
