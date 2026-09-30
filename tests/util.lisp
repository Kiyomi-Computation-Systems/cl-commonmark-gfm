;;;; Tests for PROPER-LIST-P: proper, dotted, circular, non-list and huge
;;;; inputs (M2 design §4.6).

(in-package #:cl-commonmark-gfm.tests)

;;; Proper lists

(define-test proper-list-p-true-for-nil
  (true (proper-list-p nil)))

(define-test proper-list-p-true-for-one-element
  (true (proper-list-p (list 1))))

(define-test proper-list-p-true-for-several-elements
  (true (proper-list-p (list 1 2 3 4 5))))

;;; Dotted lists

(define-test proper-list-p-false-for-a-dotted-pair
  (false (proper-list-p (cons 1 2))))

(define-test proper-list-p-false-for-a-dotted-list
  (false (proper-list-p (list* 1 2 3))))

;;; Circular lists, built at run time -- never with #1= read syntax, so the
;;; reader is never asked to parse a circular datum.

(define-test proper-list-p-false-for-a-cycle-of-length-1
  (let ((list (list 1)))
    (setf (cdr list) list)
    (false (proper-list-p list))))

(define-test proper-list-p-false-for-a-cycle-of-length-2
  (let ((list (list 1 2)))
    (setf (cdr (last list)) list)
    (false (proper-list-p list))))

(define-test proper-list-p-false-for-a-cycle-of-length-3
  (let ((list (list 1 2 3)))
    (setf (cdr (last list)) list)
    (false (proper-list-p list))))

(define-test proper-list-p-false-for-a-cycle-entered-after-a-prefix
  ;; 1 -> 2 -> 3 -> 4 -> 5 -> back to the cons holding 3: a two-element
  ;; acyclic prefix (1 2), then a cycle of length 3 (3 4 5).
  (let* ((list (list 1 2 3 4 5))
         (cycle-start (cddr list)))
    (setf (cdr (last list)) cycle-start)
    (false (proper-list-p list))))

;;; Non-lists

(define-test proper-list-p-false-for-a-string
  (false (proper-list-p "abc")))

(define-test proper-list-p-false-for-a-vector
  (false (proper-list-p (vector 1 2 3))))

(define-test proper-list-p-false-for-a-number
  (false (proper-list-p 42)))

;;; A huge proper list: PROPER-LIST-P must walk it in a loop, not recurse

(define-test proper-list-p-true-for-a-3-000-000-element-list
  (true (proper-list-p (make-list 3000000))))
