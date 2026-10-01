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

;;; M2: INVALID-OPTION, with INVALID-PARSE-OPTION and INVALID-RENDER-OPTION
;;; under it (M2 design §7.2, §7.4, D16).

(define-test invalid-option-hierarchy
  (true (subtypep 'invalid-option 'commonmark-gfm-error))
  (true (subtypep 'invalid-option 'error))
  (true (subtypep 'invalid-parse-option 'invalid-option))
  (true (subtypep 'invalid-parse-option 'commonmark-gfm-error))
  (true (subtypep 'invalid-parse-option 'error))
  ;; INVALID-RENDER-OPTION is M1's condition, now under INVALID-OPTION
  ;; instead of directly under COMMONMARK-GFM-ERROR.
  (true (subtypep 'invalid-render-option 'invalid-option))
  (true (subtypep 'invalid-render-option 'commonmark-gfm-error))
  (true (subtypep 'invalid-render-option 'error)))

;;; M2: RESOURCE-LIMIT-EXCEEDED, a direct subtype of COMMONMARK-GFM-ERROR,
;;; beside INVALID-OPTION and NATIVE-ERROR, not under either (M2 design
;;; §5.5, §7.4).

(define-test resource-limit-exceeded-hierarchy
  (true (subtypep 'resource-limit-exceeded 'commonmark-gfm-error))
  (true (subtypep 'resource-limit-exceeded 'error))
  (false (subtypep 'resource-limit-exceeded 'invalid-option))
  (false (subtypep 'resource-limit-exceeded 'native-error)))

(define-test resource-limit-exceeded-readers-without-initargs
  (let ((condition (make-condition 'resource-limit-exceeded)))
    (false (condition-limit condition))
    (false (condition-maximum condition))))

(define-test resource-limit-exceeded-readers-with-initargs
  (let ((condition (make-condition 'resource-limit-exceeded
                                    :limit '*max-nodes*
                                    :maximum 1000000)))
    (is eql '*max-nodes* (condition-limit condition))
    (is = 1000000 (condition-maximum condition))))

(define-test resource-limit-exceeded-report-omits-its-extra-slots
  ;; The report stays "operation: reason: datum"; LIMIT and MAXIMUM don't
  ;; appear in it even though they are set here.
  (is string= "parse: too many nodes: 2000000"
      (princ-to-string (make-condition 'resource-limit-exceeded
                                        :operation 'parse
                                        :datum 2000000
                                        :reason "too many nodes"
                                        :limit '*max-nodes*
                                        :maximum 1000000))))

;;; M2b: UNSUPPORTED-INPUT, a direct subtype of COMMONMARK-GFM-ERROR, beside
;;; INVALID-OPTION, RESOURCE-LIMIT-EXCEEDED and NATIVE-ERROR, not under any
;;; of them (M2 design §5.6, §7.4; finding 16).

(define-test unsupported-input-hierarchy
  (true (subtypep 'unsupported-input 'commonmark-gfm-error))
  (true (subtypep 'unsupported-input 'error))
  (false (subtypep 'unsupported-input 'invalid-option))
  (false (subtypep 'unsupported-input 'resource-limit-exceeded))
  (false (subtypep 'unsupported-input 'native-error)))

(define-test unsupported-input-readers-without-initargs
  ;; UNSUPPORTED-INPUT adds no slots of its own: only the base condition's
  ;; three, already covered by CONDITION-READERS.
  (let ((condition (make-condition 'unsupported-input)))
    (false (condition-operation condition))
    (false (condition-datum condition))
    (false (condition-reason condition))))

(define-test unsupported-input-report
  (is string= "parse: entity decodes to ^: 7"
      (princ-to-string (make-condition 'unsupported-input
                                        :operation 'parse
                                        :datum 7
                                        :reason "entity decodes to ^"))))

;;; M2: NATIVE-ERROR, with its six subtypes (M2 design §5.2, §5.4, §6.3,
;;; §7.4, D16).

(define-test native-error-hierarchy
  (true (subtypep 'native-error 'commonmark-gfm-error))
  (true (subtypep 'native-error 'error))
  (dolist (subtype '(native-library-not-found
                      native-abi-mismatch
                      dynamic-ffi-unavailable
                      native-initialization-error
                      native-parse-error
                      native-render-error))
    (true (subtypep subtype 'native-error) "~S must be a subtype of NATIVE-ERROR" subtype)
    (true (subtypep subtype 'commonmark-gfm-error)
          "~S must be a subtype of COMMONMARK-GFM-ERROR" subtype)
    (true (subtypep subtype 'error) "~S must be a subtype of ERROR" subtype)))

(define-test native-library-not-found-readers-without-initargs
  (let ((condition (make-condition 'native-library-not-found)))
    (false (condition-override condition))
    (false (condition-paths condition))))

(define-test native-library-not-found-readers-with-initargs
  (let ((condition (make-condition 'native-library-not-found
                                    :override "/opt/lib"
                                    :paths '("/opt/lib/libcmark-gfm.so"))))
    (is string= "/opt/lib" (condition-override condition))
    (is equal '("/opt/lib/libcmark-gfm.so") (condition-paths condition))))

(define-test native-abi-mismatch-readers-without-initargs
  (let ((condition (make-condition 'native-abi-mismatch)))
    (false (condition-expected-version condition))
    (false (condition-found-version condition))
    (false (condition-paths condition))))

(define-test native-abi-mismatch-readers-with-initargs
  (let ((condition (make-condition 'native-abi-mismatch
                                    :expected-version "0.29.0.gfm.13"
                                    :found-version "0.28.0"
                                    :paths '("/usr/lib/libcmark-gfm.so"))))
    (is string= "0.29.0.gfm.13" (condition-expected-version condition))
    (is string= "0.28.0" (condition-found-version condition))
    (is equal '("/usr/lib/libcmark-gfm.so") (condition-paths condition))))

(define-test condition-report-across-every-m2-subtype
  (is string= "parse: unknown key: :BOGUS"
      (princ-to-string (make-condition 'invalid-parse-option
                                        :operation 'parse
                                        :datum :bogus
                                        :reason "unknown key")))
  (is string= "ast->html-tree: unknown option: :WEIRD"
      (princ-to-string (make-condition 'invalid-option
                                        :operation 'ast->html-tree
                                        :datum :weird
                                        :reason "unknown option")))
  (is string= "native-state: missing library: \"/no/such/file\""
      (princ-to-string (make-condition 'native-error
                                        :operation 'native-state
                                        :datum "/no/such/file"
                                        :reason "missing library")))
  (is string= "native-state: missing library: \"/no/such/file\""
      (princ-to-string (make-condition 'native-library-not-found
                                        :operation 'native-state
                                        :datum "/no/such/file"
                                        :reason "missing library"
                                        :paths '("/no/such/file"))))
  (is string= "native-state: version mismatch: \"1.2.3\""
      (princ-to-string (make-condition 'native-abi-mismatch
                                        :operation 'native-state
                                        :datum "1.2.3"
                                        :reason "version mismatch"
                                        :expected-version "0.29.0.gfm.13"
                                        :found-version "1.2.3")))
  (is string= "native-state: dynamic ffi unavailable: :ECL"
      (princ-to-string (make-condition 'dynamic-ffi-unavailable
                                        :operation 'native-state
                                        :datum :ecl
                                        :reason "dynamic ffi unavailable")))
  (is string= "native-state: null extension pointer: :TABLE"
      (princ-to-string (make-condition 'native-initialization-error
                                        :operation 'native-state
                                        :datum :table
                                        :reason "null extension pointer")))
  (is string= "parse: dangling footnote reference: \"a\""
      (princ-to-string (make-condition 'native-parse-error
                                        :operation 'parse
                                        :datum "a"
                                        :reason "dangling footnote reference")))
  (is string= "markdown->html: null render buffer: NIL"
      (princ-to-string (make-condition 'native-render-error
                                        :operation 'markdown->html
                                        :datum nil
                                        :reason "null render buffer"))))
