;;;; Tests for the AST: schema validation, queries, equality and transforms.

(in-package #:cl-commonmark-gfm.tests)

;;; NODE-P

(define-test node-p-predicate
  (true (node-p (make-node :paragraph)))
  (false (node-p "not-a-node"))
  (false (node-p nil)))

;;; MAKE-NODE: every kind, defaults filled, canonical schema order

(define-test make-node-document-defaults
  (let ((node (make-node :document)))
    (is eql :document (node-kind node))
    (is equal (list :profile nil :extensions nil :options nil) (node-attributes node))))

(define-test make-node-document-with-values-in-schema-order
  ;; Attributes are given out of schema order, to prove the canonical plist
  ;; is reordered, not just accepted as-is.
  (let ((node (make-node :document
                          :attributes (list :options (list :sourcepos)
                                             :profile :gfm
                                             :extensions (list :table :strikethrough)))))
    (is equal (list :profile :gfm
                     :extensions (list :table :strikethrough)
                     :options (list :sourcepos))
        (node-attributes node))))

(define-test make-node-no-attribute-kinds-are-empty-and-childless
  (dolist (kind '(:block-quote :item :paragraph :table :table-header :table-row
                  :emph :strong :strikethrough))
    (let ((node (make-node kind)))
      (is eql kind (node-kind node))
      (is equal nil (node-attributes node))
      (is equal nil (node-children node))
      (false (node-sourcepos node)))))

(define-test make-node-list-bullet-defaults
  (is equal (list :type :bullet :start nil :delimiter nil :tight nil)
      (node-attributes (make-node :list))))

(define-test make-node-list-ordered-canonical-order-independent-of-caller-order
  ;; Caller order is scrambled and does not match the schema; the canonical
  ;; plist must come back in schema order regardless (:type :start :delimiter
  ;; :tight).
  (let ((node (make-node :list
                          :attributes (list :delimiter :period :tight t
                                             :type :ordered :start 3))))
    (is equal (list :type :ordered :start 3 :delimiter :period :tight t)
        (node-attributes node))))

(define-test make-node-task-item-defaults
  (is equal (list :checked nil) (node-attributes (make-node :task-item))))

(define-test make-node-code-block-defaults
  (is equal (list :info "" :literal "") (node-attributes (make-node :code-block))))

(define-test make-node-leaf-literal-kinds-default-to-empty-literal
  (dolist (kind '(:html-block :html-inline :text :code))
    (let ((node (make-node kind)))
      (true (node-p node))
      (is equal (list :literal "") (node-attributes node))
      (is equal nil (node-children node)))))

(define-test make-node-heading-with-supplied-level
  (is equal (list :level 3) (node-attributes (make-node :heading :attributes (list :level 3)))))

(define-test make-node-leaf-no-attribute-kinds
  (dolist (kind '(:thematic-break :softbreak :linebreak))
    (let ((node (make-node kind)))
      (is eql kind (node-kind node))
      (is equal nil (node-attributes node))
      (is equal nil (node-children node)))))

(define-test make-node-footnote-definition-with-label
  (is equal (list :label "note")
      (node-attributes (make-node :footnote-definition :attributes (list :label "note")))))

(define-test make-node-footnote-reference-with-label
  (is equal (list :label "note")
      (node-attributes (make-node :footnote-reference :attributes (list :label "note")))))

(define-test make-node-table-cell-defaults
  (is equal (list :align nil) (node-attributes (make-node :table-cell))))

(define-test make-node-link-and-image-defaults
  (is equal (list :destination "" :title "") (node-attributes (make-node :link)))
  (is equal (list :destination "" :title "") (node-attributes (make-node :image))))

(define-test make-node-extension-defaults-extension-name-to-nil
  (is equal (list :extension-name nil :type-name "table")
      (node-attributes (make-node :extension :attributes (list :type-name "table")))))

(define-test make-node-accepts-valid-children-for-a-non-leaf-kind
  (let ((node (n :paragraph nil (txt "a") (txt "b"))))
    (is = 2 (length (node-children node)))))

(define-test make-node-copies-the-children-list
  ;; MAKE-NODE must store a copy: mutating the list passed to it afterwards
  ;; must not change the node.
  (let* ((children (list (txt "a")))
         (node (make-node :paragraph :children children)))
    (setf (car children) (txt "mutated"))
    (setf (cdr children) (list (txt "extra")))
    (is = 1 (length (node-children node)))
    (is string= "a" (node-attribute (first (node-children node)) :literal))))

;;; MAKE-NODE: rejections

(define-test make-node-rejects-unknown-kind
  (fail (make-node :not-a-real-kind) 'invalid-ast-node))

(define-test make-node-rejects-unknown-key
  (fail (make-node :paragraph :attributes (list :bogus 1)) 'invalid-ast-node))

(define-test make-node-rejects-repeated-key
  (fail (make-node :heading :attributes (list :level 1 :level 2)) 'invalid-ast-node))

(define-test make-node-rejects-odd-length-plist
  (fail (make-node :heading :attributes (list :level)) 'invalid-ast-node))

(define-test make-node-rejects-improper-plist
  (fail (make-node :heading :attributes (list* :level 1 :extra)) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-document-attributes
  (fail (make-node :document :attributes (list :profile "gfm")) 'invalid-ast-node)
  (fail (make-node :document :attributes (list :profile :bogus)) 'invalid-ast-node)
  (fail (make-node :document :attributes (list :extensions :table)) 'invalid-ast-node)
  (fail (make-node :document :attributes (list :extensions (list "table"))) 'invalid-ast-node)
  (fail (make-node :document :attributes (list :extensions (list* :table :strikethrough)))
        'invalid-ast-node)
  (fail (make-node :document :attributes (list :options 42)) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-list-attributes
  (fail (make-node :list :attributes (list :type :roman)) 'invalid-ast-node)
  (fail (make-node :list :attributes (list :type :ordered :start "1" :delimiter :period))
        'invalid-ast-node)
  (fail (make-node :list :attributes (list :type :ordered :start -1 :delimiter :period))
        'invalid-ast-node)
  (fail (make-node :list :attributes (list :type :ordered :start 1 :delimiter :dash))
        'invalid-ast-node)
  (fail (make-node :list :attributes (list :tight :yes)) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-task-item-checked
  (fail (make-node :task-item :attributes (list :checked 1)) 'invalid-ast-node)
  (fail (make-node :task-item :attributes (list :checked :yes)) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-string-attributes
  (fail (make-node :code-block :attributes (list :info 42)) 'invalid-ast-node)
  (fail (make-node :code-block :attributes (list :literal 42)) 'invalid-ast-node)
  (fail (make-node :link :attributes (list :destination 42)) 'invalid-ast-node)
  (fail (make-node :image :attributes (list :title 42)) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-literal-on-leaf-text-kinds
  (fail (make-node :text :attributes (list :literal 42)) 'invalid-ast-node)
  (fail (make-node :code :attributes (list :literal 42)) 'invalid-ast-node)
  (fail (make-node :html-inline :attributes (list :literal 42)) 'invalid-ast-node)
  (fail (make-node :html-block :attributes (list :literal 42)) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-link-title-and-image-destination
  (fail (make-node :link :attributes (list :title 42)) 'invalid-ast-node)
  (fail (make-node :image :attributes (list :destination 42)) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-heading-level
  (fail (make-node :heading :attributes (list :level 0)) 'invalid-ast-node)
  (fail (make-node :heading :attributes (list :level 7)) 'invalid-ast-node)
  (fail (make-node :heading :attributes (list :level "2")) 'invalid-ast-node)
  (fail (make-node :heading :attributes (list :level 2.0)) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-footnote-label
  (fail (make-node :footnote-definition :attributes (list :label 42)) 'invalid-ast-node)
  (fail (make-node :footnote-reference :attributes (list :label :note)) 'invalid-ast-node))

(define-test make-node-rejects-empty-label
  (fail (make-node :footnote-definition :attributes (list :label "")) 'invalid-ast-node)
  (fail (make-node :footnote-reference :attributes (list :label "")) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-table-cell-align
  (fail (make-node :table-cell :attributes (list :align :top)) 'invalid-ast-node)
  (fail (make-node :table-cell :attributes (list :align "left")) 'invalid-ast-node))

(define-test make-node-rejects-wrong-type-extension-attributes
  (fail (make-node :extension :attributes (list :extension-name 42 :type-name "table"))
        'invalid-ast-node)
  (fail (make-node :extension :attributes (list :type-name 42)) 'invalid-ast-node))

(define-test make-node-rejects-missing-required-key
  (fail (make-node :heading) 'invalid-ast-node)
  (fail (make-node :footnote-definition) 'invalid-ast-node)
  (fail (make-node :footnote-reference) 'invalid-ast-node)
  (fail (make-node :extension) 'invalid-ast-node))

(define-test make-node-rejects-children-on-leaf-kind
  (fail (make-node :thematic-break :children (list (n :paragraph nil))) 'invalid-ast-node)
  (fail (make-node :text :attributes (list :literal "x") :children (list (txt "y")))
        'invalid-ast-node))

(define-test make-node-rejects-non-node-child
  (fail (make-node :paragraph :children (list "not-a-node")) 'invalid-ast-node)
  (fail (make-node :paragraph :children (list 42)) 'invalid-ast-node))

(define-test make-node-rejects-improper-children-list
  (fail (make-node :paragraph :children (list* (txt "a") (txt "b"))) 'invalid-ast-node))

(define-test make-node-rejects-ordered-list-without-start-and-delimiter
  (fail (make-node :list :attributes (list :type :ordered)) 'invalid-ast-node)
  (fail (make-node :list :attributes (list :type :ordered :start 1)) 'invalid-ast-node)
  (fail (make-node :list :attributes (list :type :ordered :delimiter :period))
        'invalid-ast-node))

(define-test make-node-rejects-bullet-list-with-start-or-delimiter
  (fail (make-node :list :attributes (list :type :bullet :start 1)) 'invalid-ast-node)
  (fail (make-node :list :attributes (list :type :bullet :delimiter :period)) 'invalid-ast-node)
  (fail (make-node :list :attributes (list :type :bullet :start 0 :delimiter :paren))
        'invalid-ast-node))

(define-test make-node-rejects-malformed-sourcepos
  (fail (make-node :paragraph :sourcepos 42) 'invalid-ast-node)
  (fail (make-node :paragraph :sourcepos (cons 1 5)) 'invalid-ast-node)
  (fail (make-node :paragraph :sourcepos (cons 1 (cons 1 5))) 'invalid-ast-node)
  (fail (make-node :paragraph :sourcepos (cons (cons -1 1) (cons 1 5))) 'invalid-ast-node)
  (fail (make-node :paragraph :sourcepos (cons (cons 1 1.5) (cons 1 5))) 'invalid-ast-node)
  (fail (make-node :paragraph :sourcepos (cons (cons 1 1) (cons 1 -5))) 'invalid-ast-node))

(define-test make-node-accepts-inverted-sourcepos
  (let ((sourcepos (cons (cons 5 1) (cons 1 1))))
    (is equal sourcepos (node-sourcepos (make-node :paragraph :sourcepos sourcepos)))))

(define-test make-node-signals-invalid-ast-node-with-operation-make-node
  (handler-case (progn (make-node :not-a-real-kind) (true nil "expected invalid-ast-node"))
    (invalid-ast-node (e) (is eql 'make-node (condition-operation e)))))

;;; COPY-NODE

(define-test copy-node-merges-attributes-over-original
  (let* ((original (make-node :link :attributes (list :destination "a" :title "t")))
         (copy (copy-node original :attributes (list :title "new"))))
    (is equal (list :destination "a" :title "new") (node-attributes copy))))

(define-test copy-node-replaces-children
  (let* ((original (n :paragraph nil (txt "a")))
         (copy (copy-node original :children (list (txt "x") (txt "y")))))
    (is = 2 (length (node-children copy)))
    (true (node= (txt "x") (first (node-children copy))))
    (true (node= (txt "y") (second (node-children copy))))))

(define-test copy-node-clears-sourcepos-with-explicit-nil
  (let* ((original (make-node :paragraph :sourcepos (cons (cons 1 1) (cons 1 5))))
         (copy (copy-node original :sourcepos nil)))
    (false (node-sourcepos copy))))

(define-test copy-node-keeps-fields-that-are-not-supplied
  (let* ((original (make-node :link
                               :attributes (list :destination "a" :title "t")
                               :children (list (txt "label"))
                               :sourcepos (cons (cons 1 1) (cons 1 5))))
         (copy (copy-node original :attributes (list :title "new"))))
    (is equal (node-children original) (node-children copy))
    (is equal (node-sourcepos original) (node-sourcepos copy))
    (true (node= original (copy-node original)))))

(define-test copy-node-cannot-change-kind
  ;; COPY-NODE's lambda list has no &ALLOW-OTHER-KEYS and takes no :KIND
  ;; argument, so passing one is an unrecognized keyword argument: a
  ;; PROGRAM-ERROR on SBCL, CCL and ECL alike at default safety (verified
  ;; directly on all three; none of them accept it silently). Routed through
  ;; CALL-WITH-ARGS so this stays a runtime check: some Lisps would otherwise
  ;; flag it at compile time instead, from a literal (APPLY #'COPY-NODE ...).
  (fail (call-with-args #'copy-node (list (make-node :paragraph) :kind :heading))
        'program-error))

(define-test copy-node-revalidates-the-merged-result
  (fail (copy-node (make-node :list) :attributes (list :type :ordered)) 'invalid-ast-node))

;;; COPY-NODE re-validates every rule itself: it does not merely delegate to
;;; MAKE-NODE. Each check below is skipped in turn as a mutation.

(define-test copy-node-rejects-unknown-attribute-key
  (fail (copy-node (txt "a") :attributes '(:bogus 1)) 'invalid-ast-node))

(define-test copy-node-rejects-wrong-type-attribute-value
  (fail (copy-node (txt "a") :attributes '(:literal 42)) 'invalid-ast-node))

(define-test copy-node-rejects-children-on-a-leaf-node
  (fail (copy-node (txt "a") :children (list (txt "b"))) 'invalid-ast-node))

(define-test copy-node-rejects-malformed-sourcepos
  (fail (copy-node (make-node :paragraph) :sourcepos 42) 'invalid-ast-node))

(define-test copy-node-signals-invalid-ast-node-with-operation-copy-node
  (handler-case (progn (copy-node (make-node :list) :attributes (list :type :ordered))
                        (true nil "expected invalid-ast-node"))
    (invalid-ast-node (e) (is eql 'copy-node (condition-operation e)))))

;;; COPY-NODE validates CHILDREN before copying it, exactly as MAKE-NODE
;;; does: a bad CHILDREN argument must be rejected before COPY-LIST ever
;;; runs on it.

(define-test copy-node-rejects-non-list-children-before-copying
  (fail (copy-node (make-node :paragraph) :children "abc") 'invalid-ast-node))

;; Only reachable once CHECK-CHILDREN runs before COPY-LIST: PROPER-LIST-P's
;; Floyd cycle detection catches this without ever looping, so a circular
;; CHILDREN argument is rejected rather than exhausting the heap.
(define-test copy-node-rejects-a-circular-children-list
  (let ((l (list (make-node :thematic-break))))
    (setf (cdr l) l)
    (fail (copy-node (make-node :paragraph) :children l) 'invalid-ast-node)))

;;; NODE-ATTRIBUTES and NODE-ATTRIBUTE

(define-test node-attributes-returns-a-fresh-copy
  (let* ((node (make-node :code-block :attributes (list :info "lisp" :literal "(+ 1 2)")))
         (first-copy (node-attributes node)))
    (setf (getf first-copy :info) "mutated")
    (is string= "lisp" (getf (node-attributes node) :info))))

(define-test node-children-returns-a-fresh-copy
  ;; A destructive SORT on the returned list must not corrupt the node: a
  ;; later NODE-CHILDREN call must still see the original order. SORT's
  ;; result is bound (and declared ignorable, since the test only cares
  ;; about the destructive effect on the fresh copy) rather than discarded
  ;; outright, which some Lisps warn about.
  (let* ((node (make-node :paragraph :children (list (txt "b") (txt "a"))))
         (sorted (sort (node-children node) #'string<
                       :key (lambda (child) (node-attribute child :literal)))))
    (declare (ignorable sorted))
    (is equal (list "b" "a")
        (mapcar (lambda (child) (node-attribute child :literal)) (node-children node)))))

(define-test node-attribute-returns-the-value
  (is string= "" (node-attribute (make-node :code-block) :info))
  (is eql :bullet (node-attribute (make-node :list) :type)))

(define-test node-attribute-signals-for-a-key-the-kind-lacks
  (fail (node-attribute (make-node :paragraph) :bogus) 'invalid-ast-node)
  (fail (node-attribute (make-node :code-block) :destination) 'invalid-ast-node))

(define-test node-attribute-signals-invalid-ast-node-with-operation-node-attribute
  (handler-case (progn (node-attribute (make-node :paragraph) :bogus)
                        (true nil "expected invalid-ast-node"))
    (invalid-ast-node (e) (is eql 'node-attribute (condition-operation e)))))

;;; NODE=

(define-test node=-true-for-identical-trees
  (true (node= (n :paragraph nil (txt "a")) (n :paragraph nil (txt "a")))))

(define-test node=-false-for-different-kind
  (false (node= (n :paragraph nil) (n :block-quote nil))))

(define-test node=-false-for-different-attributes
  (false (node= (make-node :heading :attributes (list :level 1))
                (make-node :heading :attributes (list :level 2)))))

(define-test node=-false-for-different-children
  (false (node= (n :paragraph nil (txt "a")) (n :paragraph nil (txt "b")))))

(define-test node=-false-for-different-number-of-children
  (false (node= (n :paragraph nil (txt "a")) (n :paragraph nil (txt "a") (txt "b")))))

(define-test node=-considers-sourcepos-by-default
  (let ((a (make-node :paragraph :sourcepos (cons (cons 1 1) (cons 1 5))))
        (b (make-node :paragraph :sourcepos (cons (cons 2 1) (cons 2 5)))))
    (false (node= a b))
    (true (node= a b :sourcepos nil))))

(define-test node=-ignores-sourcepos-at-depth-when-disabled
  (let ((a (n :paragraph nil (make-node :text :attributes (list :literal "x")
                                          :sourcepos (cons (cons 1 1) (cons 1 2)))))
        (b (n :paragraph nil (make-node :text :attributes (list :literal "x")
                                          :sourcepos (cons (cons 9 9) (cons 9 9))))))
    (false (node= a b))
    (true (node= a b :sourcepos nil))))

(define-test node=-is-case-sensitive-for-string-attributes
  (false (node= (txt "Hello") (txt "hello"))))

(define-test node=-compares-list-attributes-by-contents
  ;; Two separately built, equal lists: identity must not matter.
  (true (node= (n :document (list :extensions (list :table :autolink)
                                  :options (list :footnotes)))
               (n :document (list :extensions (list :table :autolink)
                                  :options (list :footnotes)))))
  (false (node= (n :document (list :extensions (list :table)))
                (n :document (list :extensions (list :autolink))))))

;;; FOLD-AST and MAP-AST: traversal order

(define-test fold-ast-visits-parent-before-children-depth-first
  (let ((tree (n :document nil
                 (n :paragraph nil (txt "a") (txt "b"))
                 (n :paragraph nil (txt "c")))))
    (is equal '(:document :paragraph :text :text :paragraph :text)
        (reverse (fold-ast (lambda (node acc) (cons (node-kind node) acc)) nil tree)))))

(define-test map-ast-visits-in-the-same-preorder-as-fold-ast
  (let ((tree (n :document nil
                 (n :paragraph nil (txt "a") (txt "b"))
                 (n :paragraph nil (txt "c")))))
    (is equal '(:document :paragraph :text :text :paragraph :text)
        (map-ast #'node-kind tree))))

(define-test map-ast-is-correct-over-a-2000-deep-chain-of-block-quotes
  ;; A 2,000-deep chain, one block-quote nested in the next, terminated by
  ;; one leaf: 2,001 nodes in total. This depth is small enough that the
  ;; recursion itself does not overflow the call stack on SBCL, CCL or ECL
  ;; (checked by hand); it is here to catch MAP-AST corrupting order or
  ;; count at depth, not to probe the stack limit.
  (let ((tree (make-node :thematic-break)))
    (dotimes (i 2000)
      (setf tree (make-node :block-quote :children (list tree))))
    (let ((kinds (map-ast #'node-kind tree)))
      (is = 2001 (length kinds))
      (is eql :block-quote (first kinds))
      (is eql :thematic-break (first (last kinds)))
      (true (every (lambda (k) (eql k :block-quote)) (butlast kinds))))))

;;; TRANSFORM-AST

(define-test transform-ast-identity-returns-an-equal-tree
  (let ((tree (n :document nil (n :paragraph nil (txt "a")))))
    (true (node= tree (transform-ast (lambda (node) node) tree)))))

(define-test transform-ast-replaces-a-node
  (let* ((tree (n :document nil (txt "a")))
         (result (transform-ast (lambda (node)
                                   (if (eql (node-kind node) :text)
                                       (make-node :text :attributes (list :literal "b"))
                                       node))
                                 tree)))
    (is string= "b" (node-attribute (first (node-children result)) :literal))))

(define-test transform-ast-splices-a-list-of-nodes-into-the-parent
  (let* ((tree (n :paragraph nil (txt "a")))
         (result (transform-ast (lambda (node)
                                   (if (eql (node-kind node) :text)
                                       (list (txt "x") (txt "y"))
                                       node))
                                 tree)))
    (is = 2 (length (node-children result)))
    (is string= "x" (node-attribute (first (node-children result)) :literal))
    (is string= "y" (node-attribute (second (node-children result)) :literal))))

(define-test transform-ast-deletes-a-node-that-becomes-nil
  (let* ((tree (n :paragraph nil (txt "a") (txt "b")))
         (result (transform-ast (lambda (node)
                                   (if (and (eql (node-kind node) :text)
                                            (string= (node-attribute node :literal) "a"))
                                       nil
                                       node))
                                 tree)))
    (is = 1 (length (node-children result)))
    (is string= "b" (node-attribute (first (node-children result)) :literal))))

(define-test transform-ast-accepts-root-spliced-into-exactly-one-node
  (let ((result (transform-ast (lambda (node) (list node)) (n :paragraph nil))))
    (true (node-p result))))

(define-test transform-ast-function-sees-children-already-transformed
  ;; If TRANSFORM-AST were top-down, the paragraph would still see all three
  ;; text children (the "b" deletion below would not have happened yet).
  (let ((seen-count nil))
    (transform-ast (lambda (node)
                      (cond
                        ((and (eql (node-kind node) :text)
                              (string= (node-attribute node :literal) "b"))
                         nil)
                        ((eql (node-kind node) :paragraph)
                         (setf seen-count (length (node-children node)))
                         node)
                        (t node)))
                    (n :paragraph nil (txt "a") (txt "b") (txt "c")))
    (is = 2 seen-count)))

(define-test transform-ast-rejects-root-deleted-to-nil
  (fail (transform-ast (lambda (node) (declare (ignore node)) nil) (n :paragraph nil))
        'invalid-ast-node))

(define-test transform-ast-rejects-root-spliced-into-many-nodes
  (fail (transform-ast (lambda (node) (list node node)) (n :paragraph nil))
        'invalid-ast-node))

(define-test transform-ast-rejects-a-non-node-non-list-result
  (fail (transform-ast (lambda (node) (declare (ignore node)) 42) (n :paragraph nil))
        'invalid-ast-node))

(define-test transform-ast-rejects-a-list-containing-a-non-node
  (fail (transform-ast (lambda (node)
                          (if (eql (node-kind node) :text)
                              (list (txt "ok") "not-a-node")
                              node))
                        (n :paragraph nil (txt "a")))
        'invalid-ast-node))

(define-test transform-ast-signals-invalid-ast-node-with-operation-transform-ast
  (handler-case (progn (transform-ast (lambda (node) (declare (ignore node)) nil)
                                       (n :paragraph nil))
                        (true nil "expected invalid-ast-node"))
    (invalid-ast-node (e) (is eql 'transform-ast (condition-operation e)))))
