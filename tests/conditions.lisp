;;;; Tests for the condition hierarchy: subtypes, readers and report text.

(in-package #:cl-commonmark-gfm.tests)

(define-test commonmark-gfm-error-is-an-error
  (true (subtypep 'commonmark-gfm-error 'error)))

(define-test subtypes-of-commonmark-gfm-error
  (true (subtypep 'invalid-ast-node 'commonmark-gfm-error))
  (true (subtypep 'invalid-render-option 'commonmark-gfm-error))
  (true (subtypep 'invalid-html-tree 'commonmark-gfm-error))
  (true (subtypep 'unsupported-extension-node 'commonmark-gfm-error))
  ;; The chain reaches ERROR too, not just the immediate base.
  (true (subtypep 'invalid-ast-node 'error))
  (true (subtypep 'invalid-render-option 'error))
  (true (subtypep 'invalid-html-tree 'error))
  (true (subtypep 'unsupported-extension-node 'error)))

(define-test condition-readers
  (let ((ast-condition (make-condition 'invalid-ast-node
                                        :operation 'make-node
                                        :datum :foo
                                        :reason "unknown kind")))
    (is eql 'make-node (condition-operation ast-condition))
    (is eql :foo (condition-datum ast-condition))
    (is string= "unknown kind" (condition-reason ast-condition)))
  ;; The readers are defined once on the base condition, so they must work
  ;; the same way on every subtype, not just the one above.
  (let ((tree-condition (make-condition 'unsupported-extension-node
                                         :operation 'ast->html-tree
                                         :datum :extension
                                         :reason "extension node")))
    (is eql 'ast->html-tree (condition-operation tree-condition))
    (is eql :extension (condition-datum tree-condition))
    (is string= "extension node" (condition-reason tree-condition))))

(define-test signalling-a-condition
  (fail (error 'invalid-ast-node :operation 'make-node :datum :foo :reason "unknown kind")
        'invalid-ast-node))

(define-test condition-report-names-operation-reason-and-datum
  (is string= "make-node: unknown kind: :FOO"
      (princ-to-string (make-condition 'invalid-ast-node
                                        :operation 'make-node
                                        :datum :foo
                                        :reason "unknown kind"))))

;;; OPERATION, DATUM and REASON each default to NIL, so a report never hits
;;; an unbound slot when a condition is signalled (or made) with some
;;; initargs omitted.

(define-test condition-report-with-no-initargs-is-a-string
  (is string= "nil: NIL: NIL" (princ-to-string (make-condition 'commonmark-gfm-error))))

(define-test condition-report-with-only-datum-supplied-mentions-it
  (true (search "1" (princ-to-string (make-condition 'invalid-ast-node :datum 1)))))

;;; A pathological :DATUM prints safely instead of hanging or exhausting
;;; memory: the report binds *PRINT-LENGTH*, *PRINT-LEVEL* and
;;; *PRINT-CIRCLE*.

(define-test condition-report-truncates-a-long-datum-list
  (let ((condition (make-condition 'invalid-ast-node :operation 'make-node
                                    :datum (loop for i below 100 collect i)
                                    :reason "too long")))
    (true (search "..." (princ-to-string condition))
          "a 100-element list datum must print truncated")))

(define-test condition-report-handles-a-circular-datum
  ;; Without *PRINT-CIRCLE* bound, PRINC-TO-STRING on this condition would
  ;; hang or exhaust memory rather than return.
  (let* ((circular (list 1 2 3)))
    (setf (cdr (last circular)) circular)
    (let ((condition (make-condition 'invalid-ast-node :operation 'make-node
                                      :datum circular
                                      :reason "circular")))
      (true (stringp (princ-to-string condition))))))

(define-test condition-report-across-every-subtype
  (is string= "ast->html-tree: unknown option: :BOGUS"
      (princ-to-string (make-condition 'invalid-render-option
                                        :operation 'ast->html-tree
                                        :datum :bogus
                                        :reason "unknown option")))
  (is string= "html-tree->string: not an element: 42"
      (princ-to-string (make-condition 'invalid-html-tree
                                        :operation 'html-tree->string
                                        :datum 42
                                        :reason "not an element")))
  (is string= "ast->html-tree: extension node: :EXTENSION"
      (princ-to-string (make-condition 'unsupported-extension-node
                                        :operation 'ast->html-tree
                                        :datum :extension
                                        :reason "extension node"))))
