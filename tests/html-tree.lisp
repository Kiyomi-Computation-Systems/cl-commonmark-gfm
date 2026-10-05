;;;; Tests for AST->HTML-TREE and the footnote pre-pass (M1 design §5).
;;;;
;;;; Expected trees are written out whole and compared with EQUAL. Their
;;;; strings go through FORMAT first (see TREE), so "~%" is a newline.

(in-package #:cl-commonmark-gfm.tests)

;;; Builders for ASTs

(defun doc (&rest children)
  "A :DOCUMENT node holding CHILDREN."
  (make-node :document :children children))

(defun para (&rest children)
  "A :PARAGRAPH node holding CHILDREN."
  (make-node :paragraph :children children))

(defun fn-ref (label)
  "A :FOOTNOTE-REFERENCE node labelled LABEL."
  (make-node :footnote-reference :attributes (list :label label)))

(defun fn-def (label &rest children)
  "A :FOOTNOTE-DEFINITION node labelled LABEL, holding CHILDREN."
  (make-node :footnote-definition :attributes (list :label label) :children children))

;;; Builders for expected trees

(defun tree (template)
  "Return a copy of TEMPLATE, an expected HTML tree, with every string passed
through FORMAT, so that \"~%\" stands for a newline."
  (cond ((stringp template) (format nil template))
        ((consp template) (cons (tree (car template)) (tree (cdr template))))
        (t template)))

(defun newline ()
  "A string holding one newline."
  (string #\Newline))

(defun arrow ()
  "The backref arrow, U+21A9, built from its code point."
  (string (code-char #x21A9)))

(defun expected-ref (label number &optional (k 1))
  "The expected tree for the K-th reference to the footnote labelled LABEL,
numbered NUMBER (M1 design §5.4)."
  (list :sup (list (list :class "footnote-ref"))
        (list :a (list (list :href (format nil "#fn-~A" label))
                       (list :id (if (= k 1)
                                     (format nil "fnref-~A" label)
                                     (format nil "fnref-~A-~D" label k)))
                       (list :data-footnote-ref ""))
              (format nil "~D" number))))

(defun expected-backref (label number &optional (k 1))
  "The expected backref anchor to the K-th reference to the footnote labelled
LABEL, numbered NUMBER (M1 design §5.4)."
  (let ((index (if (= k 1) (format nil "~D" number) (format nil "~D-~D" number k))))
    (list* :a (list (list :href (if (= k 1)
                                    (format nil "#fnref-~A" label)
                                    (format nil "#fnref-~A-~D" label k)))
                    (list :class "footnote-backref")
                    (list :data-footnote-backref "")
                    (list :data-footnote-backref-idx index)
                    (list :aria-label (format nil "Back to reference ~A" index)))
           (arrow)
           (if (= k 1)
               '()
               (list (list :sup (list (list :class "footnote-ref")) (format nil "~D" k)))))))

(defun expected-note (label text number)
  "The expected item of a footnote labelled LABEL and numbered NUMBER, with
one reference, whose only child is a paragraph holding TEXT."
  (list :li (list (list :id (format nil "fn-~A" label)))
        (newline)
        (list :p nil (format nil "~A " text) (expected-backref label number))
        (newline)))

(defun expected-section (&rest items)
  "The expected footnote section holding ITEMS, and the newline after it, as
a list of the two top-level items."
  (list (list :section (list (list :class "footnotes") (list :data-footnotes ""))
              (newline)
              (list* :ol nil (newline)
                     (loop for item in items append (list item (newline))))
              (newline))
        (newline)))

;;; Condition helpers

(defun render-option-error (ast options)
  "The INVALID-RENDER-OPTION that (APPLY #'AST->HTML-TREE AST OPTIONS)
signals, or NIL."
  (signalled 'invalid-render-option (lambda () (apply #'ast->html-tree ast options))))

;;; Tree walkers for the determinism tests

(defun html-tree-data-p (value)
  "True when VALUE is built only from conses, strings, keywords and NIL."
  (cond ((null value) t)
        ((consp value) (and (html-tree-data-p (car value)) (html-tree-data-p (cdr value))))
        (t (or (stringp value) (keywordp value)))))

(defun tree-objects (value)
  "An EQL hash table holding every cons and string reachable from VALUE."
  (let ((table (make-hash-table :test 'eql)))
    (labels ((walk (object)
               (when (or (consp object) (stringp object))
                 (setf (gethash object table) t))
               (when (consp object)
                 (walk (car object))
                 (walk (cdr object)))))
      (walk value))
    table))

(defun shares-object-p (table value)
  "True when a cons or string reachable from VALUE is in TABLE."
  (loop for object being the hash-keys of (tree-objects value)
        thereis (gethash object table)))

(defun ast-strings (ast)
  "An EQL hash table holding every string attribute value in AST."
  (let ((table (make-hash-table :test 'eql)))
    (fold-ast (lambda (node accumulator)
                (loop for (nil value) on (node-attributes node) by #'cddr
                      when (stringp value) do (setf (gethash value table) t))
                accumulator)
              nil ast)
    table))

(defun every-kind-ast ()
  "A fresh AST using every node kind but :EXTENSION, footnotes included."
  (doc (make-node :heading :attributes (list :level 2) :children (list (txt "Title")))
       (para (txt "a")
             (n :emph nil (txt "b"))
             (n :strong nil (n :strong nil (txt "c")))
             (n :strikethrough nil (txt "d"))
             (n :softbreak nil)
             (n :linebreak nil)
             (n :code (list :literal "e"))
             (n :html-inline (list :literal "<f>"))
             (n :link (list :destination "http://x.com/g h" :title "T") (txt "g"))
             (n :image (list :destination "i.png" :title "I") (txt "i"))
             (fn-ref "note")
             (fn-ref "missing"))
       (n :block-quote nil (para (txt "q")))
       (n :list (list :type :ordered :start 3 :delimiter :period :tight t)
          (n :item nil (para (txt "one")))
          (n :task-item (list :checked t) (para (txt "two"))))
       (n :code-block (list :info "lisp" :literal (format nil "(x)~%")))
       (n :html-block (list :literal (format nil "<div>~%")))
       (n :thematic-break nil)
       (n :table nil
          (n :table-header nil (n :table-cell (list :align :left) (txt "h")))
          (n :table-row nil (n :table-cell (list :align :left) (txt "r"))))
       (fn-def "note" (para (txt "Note.")))))

;;; The document and its layout (M1 design §5.2)

(define-test ast->html-tree-empty-document-is-an-empty-list
  (is equal '() (ast->html-tree (doc))))

(define-test ast->html-tree-paragraph
  ;; The document starts empty, so the first block gets no leading newline.
  (is equal (tree '((:p nil "a") "~%"))
      (ast->html-tree (doc (para (txt "a"))))))

(define-test ast->html-tree-blocks-follow-each-other
  (is equal (tree '((:p nil "a") "~%" (:p nil "b") "~%"))
      (ast->html-tree (doc (para (txt "a")) (para (txt "b"))))))

(define-test ast->html-tree-merges-adjacent-strings-and-drops-empty-ones
  (is equal (tree '((:p nil "ab") "~%"))
      (ast->html-tree (doc (para (txt "") (txt "a") (txt "b") (txt ""))))
      "inside an element")
  (is equal (tree '((:p nil) "~%"))
      (ast->html-tree (doc (para (txt ""))))
      "an element left with no children")
  (is equal '("ab")
      (ast->html-tree (doc (txt "a") (txt "") (txt "b")))
      "at the top level"))

;;; Block rows of the §5.3 table

(define-test ast->html-tree-block-quote
  (is equal (tree '((:blockquote nil "~%" (:p nil "a") "~%") "~%"))
      (ast->html-tree (doc (n :block-quote nil (para (txt "a"))))))
  (is equal (tree '((:blockquote nil "~%") "~%"))
      (ast->html-tree (doc (n :block-quote nil)))
      "an empty block quote"))

(define-test ast->html-tree-block-quote-after-inline-content-gets-a-newline-first
  ;; A tight paragraph leaves the output mid-line, so cr writes a newline.
  (is equal (tree '((:ul nil "~%"
                     (:li nil "a~%" (:blockquote nil "~%" (:p nil "b") "~%") "~%")
                     "~%")
                    "~%"))
      (ast->html-tree (doc (n :list (list :tight t)
                              (n :item nil
                                 (para (txt "a"))
                                 (n :block-quote nil (para (txt "b")))))))))

(define-test ast->html-tree-tight-bullet-list
  (is equal (tree '((:ul nil "~%" (:li nil "a") "~%" (:li nil "b") "~%") "~%"))
      (ast->html-tree (doc (n :list (list :tight t)
                              (n :item nil (para (txt "a")))
                              (n :item nil (para (txt "b"))))))))

(define-test ast->html-tree-loose-bullet-list
  (is equal (tree '((:ul nil "~%"
                     (:li nil "~%" (:p nil "a") "~%") "~%"
                     (:li nil "~%" (:p nil "b") "~%") "~%")
                    "~%"))
      (ast->html-tree (doc (n :list (list :tight nil)
                              (n :item nil (para (txt "a")))
                              (n :item nil (para (txt "b"))))))))

(define-test ast->html-tree-tight-paragraph-next-to-a-nested-list
  (is equal (tree '((:ul nil "~%"
                     (:li nil "two~%"
                          (:ul nil "~%" (:li nil "nested") "~%")
                          "~%")
                     "~%")
                    "~%"))
      (ast->html-tree (doc (n :list (list :tight t)
                              (n :item nil
                                 (para (txt "two"))
                                 (n :list (list :tight t)
                                    (n :item nil (para (txt "nested"))))))))))

(define-test ast->html-tree-paragraph-unwrapped-only-when-its-grandparent-is-a-tight-list
  ;; Here the grandparent is the item, not the list: the paragraph is wrapped.
  (is equal (tree '((:ul nil "~%"
                     (:li nil "~%" (:blockquote nil "~%" (:p nil "a") "~%") "~%")
                     "~%")
                    "~%"))
      (ast->html-tree (doc (n :list (list :tight t)
                              (n :item nil (n :block-quote nil (para (txt "a")))))))))

(define-test ast->html-tree-empty-item
  (is equal (tree '((:ul nil "~%" (:li nil) "~%") "~%"))
      (ast->html-tree (doc (n :list (list :tight t) (n :item nil))))))

(define-test ast->html-tree-ordered-list-start
  (flet ((ordered (start)
           (doc (n :list (list :type :ordered :start start :delimiter :period :tight t)
                   (n :item nil (para (txt "x")))))))
    (is equal (tree '((:ol nil "~%" (:li nil "x") "~%") "~%"))
        (ast->html-tree (ordered 1)))
    (is equal (tree '((:ol ((:start "3")) "~%" (:li nil "x") "~%") "~%"))
        (ast->html-tree (ordered 3)))
    (is equal (tree '((:ol ((:start "0")) "~%" (:li nil "x") "~%") "~%"))
        (ast->html-tree (ordered 0)))))

(define-test ast->html-tree-tight-task-items
  (is equal (tree '((:ul nil "~%"
                     (:li nil (:input ((:type "checkbox") (:disabled ""))) " todo") "~%"
                     (:li nil (:input ((:type "checkbox") (:checked "") (:disabled ""))) " done")
                     "~%")
                    "~%"))
      (ast->html-tree (doc (n :list (list :tight t)
                              (n :task-item (list :checked nil) (para (txt "todo")))
                              (n :task-item (list :checked t) (para (txt "done"))))))))

(define-test ast->html-tree-loose-task-item
  ;; The space after the checkbox leaves the output mid-line, so the
  ;; paragraph's cr writes a newline straight after it.
  (is equal (tree '((:ul nil "~%"
                     (:li nil (:input ((:type "checkbox") (:disabled "")))
                          " ~%" (:p nil "todo") "~%")
                     "~%")
                    "~%"))
      (ast->html-tree (doc (n :list (list :tight nil)
                              (n :task-item (list :checked nil) (para (txt "todo"))))))))

(define-test ast->html-tree-headings
  (loop for level from 1 to 6
        for tag in '(:h1 :h2 :h3 :h4 :h5 :h6)
        do (is equal (list (list tag nil "h") (newline))
               (ast->html-tree (doc (n :heading (list :level level) (txt "h"))))
               "level ~D" level)))

(define-test ast->html-tree-code-block
  (is equal (tree '((:pre nil (:code nil "x~%")) "~%"))
      (ast->html-tree (doc (n :code-block (list :literal (format nil "x~%"))))))
  (is equal (tree '((:pre nil (:code ((:class "language-lisp")) "x")) "~%"))
      (ast->html-tree (doc (n :code-block (list :info "lisp extra words" :literal "x"))))))

(define-test ast->html-tree-code-block-language-ends-at-space-tab-lf-or-cr
  (flet ((code-class (info)
           (let ((items (ast->html-tree (doc (n :code-block (list :info info :literal "x"))))))
             (second (assoc :class (second (third (first items))))))))
    (dolist (code '(32 9 10 13))
      (is string= "language-a" (code-class (format nil "a~Cb" (code-char code)))
          "character code ~D ends the language word" code))
    (dolist (code '(11 12))
      (is string= (format nil "language-a~Cb" (code-char code))
          (code-class (format nil "a~Cb" (code-char code)))
          "character code ~D does not end the language word" code))
    (is string= "language-" (code-class " a")
        "a non-empty info string gets a class even when its word is empty")))

(define-test ast->html-tree-code-block-with-an-empty-literal
  (is equal (tree '((:pre nil (:code nil)) "~%"))
      (ast->html-tree (doc (n :code-block nil))))
  (is equal (tree '((:pre nil (:code ((:class "language-text")))) "~%"))
      (ast->html-tree (doc (n :code-block (list :info "text"))))))

(define-test ast->html-tree-html-block
  (let ((ast (doc (n :html-block (list :literal (format nil "<div>~%"))))))
    (is equal (tree '((:*comment* nil " raw HTML omitted ") "~%")) (ast->html-tree ast))
    (is equal (tree '((:*comment* nil " raw HTML omitted ") "~%"))
        (ast->html-tree ast :raw-html :omit))
    (is equal (tree '("<div>~%")) (ast->html-tree ast :raw-html :text))))

(define-test ast->html-tree-html-block-gets-cr-before-and-after
  ;; After a tight paragraph the output is mid-line, so a newline comes
  ;; before the block; its literal has no trailing newline, so one follows.
  (let ((ast (doc (n :list (list :tight t)
                     (n :item nil (para (txt "a")) (n :html-block (list :literal "<div>")))))))
    (is equal (tree '((:ul nil "~%" (:li nil "a~%" (:*comment* nil " raw HTML omitted ") "~%") "~%")
                      "~%"))
        (ast->html-tree ast))
    (is equal (tree '((:ul nil "~%" (:li nil "a~%<div>~%") "~%") "~%"))
        (ast->html-tree ast :raw-html :text))))

(define-test ast->html-tree-thematic-break
  (is equal (tree '((:p nil "a") "~%" (:hr nil) "~%"))
      (ast->html-tree (doc (para (txt "a")) (n :thematic-break nil)))))

(define-test ast->html-tree-table-with-a-body
  (is equal (tree '((:table nil "~%"
                     (:thead nil "~%"
                      (:tr nil "~%" (:th ((:align "left")) "a") "~%" (:th nil "b") "~%")
                      "~%")
                     "~%"
                     (:tbody nil "~%"
                      (:tr nil "~%" (:td ((:align "left")) "1") "~%" (:td nil "2") "~%")
                      "~%"
                      (:tr nil "~%" (:td ((:align "left")) "3") "~%" (:td nil "4") "~%")
                      "~%")
                     "~%")
                    "~%"))
      (ast->html-tree
       (doc (n :table nil
               (n :table-header nil
                  (n :table-cell (list :align :left) (txt "a"))
                  (n :table-cell nil (txt "b")))
               (n :table-row nil
                  (n :table-cell (list :align :left) (txt "1"))
                  (n :table-cell nil (txt "2")))
               (n :table-row nil
                  (n :table-cell (list :align :left) (txt "3"))
                  (n :table-cell nil (txt "4"))))))))

(define-test ast->html-tree-table-with-only-a-header-has-no-tbody
  (is equal (tree '((:table nil "~%"
                     (:thead nil "~%" (:tr nil "~%" (:th nil "a") "~%") "~%")
                     "~%")
                    "~%"))
      (ast->html-tree (doc (n :table nil (n :table-header nil (n :table-cell nil (txt "a"))))))))

(define-test ast->html-tree-table-cell-alignments
  (is equal (tree '((:table nil "~%"
                     (:thead nil "~%"
                      (:tr nil "~%"
                       (:th ((:align "left")) "l") "~%" (:th ((:align "center")) "c") "~%"
                       (:th ((:align "right")) "r") "~%" (:th nil "n") "~%")
                      "~%")
                     "~%"
                     (:tbody nil "~%"
                      (:tr nil "~%"
                       (:td ((:align "left")) "l") "~%" (:td ((:align "center")) "c") "~%"
                       (:td ((:align "right")) "r") "~%" (:td nil "n") "~%")
                      "~%")
                     "~%")
                    "~%"))
      (flet ((cells ()
               (list (n :table-cell (list :align :left) (txt "l"))
                     (n :table-cell (list :align :center) (txt "c"))
                     (n :table-cell (list :align :right) (txt "r"))
                     (n :table-cell nil (txt "n")))))
        (ast->html-tree (doc (n :table nil
                                (apply #'n :table-header nil (cells))
                                (apply #'n :table-row nil (cells))))))))

;;; Inline rows of the §5.3 table

(define-test ast->html-tree-text-stays-unescaped-in-the-tree
  (is equal (tree '((:p nil "a & <b> \"c\"") "~%"))
      (ast->html-tree (doc (para (txt "a & <b> \"c\""))))))

(define-test ast->html-tree-softbreak-policies
  (let ((ast (doc (para (txt "a") (n :softbreak nil) (txt "b")))))
    (is equal (tree '((:p nil "a~%b") "~%")) (ast->html-tree ast))
    (is equal (tree '((:p nil "a~%b") "~%")) (ast->html-tree ast :softbreak :newline))
    (is equal (tree '((:p nil "a b") "~%")) (ast->html-tree ast :softbreak :space))
    (is equal (tree '((:p nil "a" (:br nil) "~%b") "~%")) (ast->html-tree ast :softbreak :br))))

(define-test ast->html-tree-linebreak-whatever-the-softbreak-policy
  (let ((ast (doc (para (txt "a") (n :linebreak nil) (txt "b")))))
    (dolist (policy '(:newline :space :br))
      (is equal (tree '((:p nil "a" (:br nil) "~%b") "~%"))
          (ast->html-tree ast :softbreak policy)
          "softbreak ~S" policy))))

(define-test ast->html-tree-code-span
  (is equal (tree '((:p nil "a " (:code nil "x < y")) "~%"))
      (ast->html-tree (doc (para (txt "a ") (n :code (list :literal "x < y")))))))

(define-test ast->html-tree-html-inline
  (let ((ast (doc (para (txt "a ") (n :html-inline (list :literal "<b>")) (txt " c")))))
    (is equal (tree '((:p nil "a " (:*comment* nil " raw HTML omitted ") " c") "~%"))
        (ast->html-tree ast))
    (is equal (tree '((:p nil "a <b> c") "~%"))
        (ast->html-tree ast :raw-html :text)
        "inline raw HTML as text gets no newlines")))

(define-test ast->html-tree-emph-strong-and-strikethrough
  (is equal (tree '((:p nil (:em nil "a") (:strong nil "b") (:del nil "c")) "~%"))
      (ast->html-tree (doc (para (n :emph nil (txt "a"))
                                 (n :strong nil (txt "b"))
                                 (n :strikethrough nil (txt "c")))))))

(define-test ast->html-tree-strong-directly-inside-strong-is-not-wrapped-again
  (is equal (tree '((:p nil (:strong nil "s")) "~%"))
      (ast->html-tree (doc (para (n :strong nil (n :strong nil (txt "s")))))))
  (is equal (tree '((:p nil (:strong nil "abc")) "~%"))
      (ast->html-tree (doc (para (n :strong nil (txt "a") (n :strong nil (txt "b")) (txt "c"))))))
  (is equal (tree '((:p nil (:strong nil "s")) "~%"))
      (ast->html-tree (doc (para (n :strong nil (n :strong nil (n :strong nil (txt "s"))))))))
  (is equal (tree '((:p nil (:strong nil (:em nil (:strong nil "s")))) "~%"))
      (ast->html-tree (doc (para (n :strong nil (n :emph nil (n :strong nil (txt "s")))))))
      "only a strong's direct parent counts"))

(define-test ast->html-tree-link
  (is equal (tree '((:p nil (:a ((:href "http://x.com/a%20b") (:title "T")) "l")) "~%"))
      (ast->html-tree (doc (para (n :link (list :destination "http://x.com/a b" :title "T")
                                    (txt "l"))))))
  (is equal (tree '((:p nil (:a ((:href "u")) "l")) "~%"))
      (ast->html-tree (doc (para (n :link (list :destination "u") (txt "l")))))
      "no title pair for an empty title"))

(define-test ast->html-tree-link-policy-safe-blanks-dangerous-urls
  (let ((ast (doc (para (n :link (list :destination "javascript:alert(1)") (txt "l"))
                        (n :image (list :destination "data:text/html,x"))))))
    (is equal (tree '((:p nil (:a ((:href "")) "l") (:img ((:src "") (:alt "")))) "~%"))
        (ast->html-tree ast))
    (is equal (tree '((:p nil (:a ((:href "")) "l") (:img ((:src "") (:alt "")))) "~%"))
        (ast->html-tree ast :link-policy :safe))
    (is equal (tree '((:p nil
                       (:a ((:href "javascript:alert(1)")) "l")
                       (:img ((:src "data:text/html,x") (:alt ""))))
                      "~%"))
        (ast->html-tree ast :link-policy :unsafe))))

(define-test ast->html-tree-link-policy-safe-keeps-data-image-urls
  (is equal (tree '((:p nil
                     (:a ((:href "data:image/png;base64,AAAA")) "l")
                     (:img ((:src "data:image/webp;base64,BBBB") (:alt ""))))
                    "~%"))
      (ast->html-tree (doc (para (n :link (list :destination "data:image/png;base64,AAAA")
                                    (txt "l"))
                                 (n :image (list :destination "data:image/webp;base64,BBBB")))))))

(define-test ast->html-tree-image
  (is equal (tree '((:p nil (:img ((:src "a%20b.png") (:alt "alt") (:title "T")))) "~%"))
      (ast->html-tree (doc (para (n :image (list :destination "a b.png" :title "T") (txt "alt"))))))
  (is equal (tree '((:p nil (:img ((:src "u") (:alt "")))) "~%"))
      (ast->html-tree (doc (para (n :image (list :destination "u")))))
      "an image with no children has an empty alt and no title"))

(define-test ast->html-tree-image-alt-is-the-plain-text-of-its-descendants
  (let ((ast (doc (para (n :image (list :destination "u")
                           (txt "a")
                           (n :emph nil (txt "b"))
                           (n :softbreak nil)
                           (n :code (list :literal "c"))
                           (n :linebreak nil)
                           (n :html-inline (list :literal "<i>"))
                           (n :link (list :destination "v") (txt "d"))
                           (n :image (list :destination "w") (txt "e"))
                           (n :strikethrough nil (txt "f")))))))
    (dolist (options '(() (:softbreak :br) (:softbreak :space) (:raw-html :text)))
      (is equal (tree '((:p nil (:img ((:src "u") (:alt "ab c <i>def")))) "~%"))
          (apply #'ast->html-tree ast options)
          "options ~S" options))))

;;; Options (M1 design §5.1)

(define-test ast->html-tree-rejects-an-odd-length-option-list
  (dolist (options '((:softbreak) (:softbreak :space :raw-html)))
    (let ((condition (render-option-error (doc) options)))
      (true condition "~S should be rejected" options)
      (is eql 'ast->html-tree (and condition (condition-operation condition))))))

(define-test ast->html-tree-rejects-an-unknown-option-key
  (dolist (options '((:bogus 1) (:raw-html :omit :softbreaks :space)
                     (nil nil) ("softbreak" :space)))
    (let ((condition (render-option-error (doc) options)))
      (true condition "~S should be rejected" options)
      (is eql 'ast->html-tree (and condition (condition-operation condition))))))

(define-test ast->html-tree-rejects-a-bad-option-value
  (dolist (options '((:raw-html :drop) (:raw-html :preserve) (:raw-html nil)
                     (:softbreak :tab) (:softbreak nil)
                     (:link-policy :none) (:link-policy nil) (:link-policy t)))
    (let ((condition (render-option-error (doc) options)))
      (true condition "~S should be rejected" options)
      (is eql 'ast->html-tree (and condition (condition-operation condition))))))

(define-test ast->html-tree-rejects-a-bad-document-wrapper
  (dolist (wrapper (list "div" 'div 42 t :br :hr :img :input :meta :*comment* :|a b| :|1div|))
    (let ((condition (render-option-error (doc) (list :document-wrapper wrapper))))
      (true condition "wrapper ~S should be rejected" wrapper)
      (is eql 'ast->html-tree (and condition (condition-operation condition))))))

(define-test ast->html-tree-rejects-a-document-wrapper-classified-by-lowercased-name
  ;; (INTERN "br" :KEYWORD) is not EQL to :BR, but it must still be rejected
  ;; as a void element once its name is lowercased.
  (let ((condition (render-option-error (doc) (list :document-wrapper (intern "br" :keyword)))))
    (true condition)
    (is eql 'ast->html-tree (and condition (condition-operation condition)))))

(define-test ast->html-tree-validates-options-before-converting
  (let ((ast (doc (n :extension (list :type-name "x")))))
    (true (render-option-error ast '(:softbreak :bogus))
          "a bad option wins over a node that cannot be converted")))

(define-test ast->html-tree-repeated-option-leftmost-wins
  (let ((ast (doc (para (txt "a") (n :softbreak nil) (txt "b")))))
    (is equal (tree '((:p nil "a b") "~%"))
        (ast->html-tree ast :softbreak :space :softbreak :br))
    (is equal (tree '((:p nil "a" (:br nil) "~%b") "~%"))
        (ast->html-tree ast :softbreak :br :softbreak :space))))

(define-test ast->html-tree-validates-every-value-of-a-repeated-option
  (true (render-option-error (doc) '(:softbreak :space :softbreak :bogus))))

(define-test ast->html-tree-document-wrapper
  (let ((ast (doc (para (txt "a")))))
    (is equal (tree '(:div nil (:p nil "a") "~%"))
        (ast->html-tree ast :document-wrapper :div)
        "the wrapper adds no newline of its own")
    (is equal (tree '(:my-doc nil (:p nil "a") "~%"))
        (ast->html-tree ast :document-wrapper :my-doc)
        "any valid element name")
    (is equal (tree '((:p nil "a") "~%"))
        (ast->html-tree ast :document-wrapper nil))
    (is equal '(:article nil)
        (ast->html-tree (doc) :document-wrapper :article))
    (is equal (list* :section nil (ast->html-tree (doc (para (txt "x") (fn-ref "a"))
                                                        (fn-def "a" (para (txt "A"))))))
        (ast->html-tree (doc (para (txt "x") (fn-ref "a")) (fn-def "a" (para (txt "A"))))
                        :document-wrapper :section)
        "the footnote section goes inside the wrapper")))

;;; Roots that aren't documents (M1 design §5.1)

(define-test ast->html-tree-converts-a-root-as-a-documents-only-child
  (is equal (tree '((:p nil "a") "~%")) (ast->html-tree (para (txt "a"))))
  (is equal (tree '((:em nil "a"))) (ast->html-tree (n :emph nil (txt "a"))))
  (is equal '("a") (ast->html-tree (txt "a")))
  (is equal (tree '((:strong nil "s"))) (ast->html-tree (n :strong nil (n :strong nil (txt "s")))))
  (is equal (tree '((:li nil "~%" (:p nil "a") "~%") "~%"))
      (ast->html-tree (n :item nil (para (txt "a"))))
      "an item's paragraph is wrapped: its grandparent is the document")
  (is equal (tree '((:ul nil "~%" (:li nil "a") "~%") "~%"))
      (ast->html-tree (n :list (list :tight t) (n :item nil (para (txt "a")))))))

(define-test ast->html-tree-converts-a-self-referencing-definition-root
  ;; The definition moves to the section; its own reference keeps it alive.
  (is equal (tree `((:section ((:class "footnotes") (:data-footnotes "")) "~%"
                     (:ol nil "~%"
                      (:li ((:id "fn-a")) "~%"
                       (:p nil "see " ,(expected-ref "a" 1) " " ,(expected-backref "a" 1))
                       "~%")
                      "~%")
                     "~%")
                    "~%"))
      (ast->html-tree (fn-def "a" (para (txt "see ") (fn-ref "a"))))))

;;; Footnotes (M1 design §5.4)

(define-test ast->html-tree-footnote-reference-and-section
  (is equal
      (tree `((:p nil "x"
                  (:sup ((:class "footnote-ref"))
                        (:a ((:href "#fn-note") (:id "fnref-note") (:data-footnote-ref "")) "1")))
              "~%"
              (:section ((:class "footnotes") (:data-footnotes "")) "~%"
                        (:ol nil "~%"
                             (:li ((:id "fn-note")) "~%"
                                  (:p nil "Text. "
                                      (:a ((:href "#fnref-note") (:class "footnote-backref")
                                           (:data-footnote-backref "")
                                           (:data-footnote-backref-idx "1")
                                           (:aria-label "Back to reference 1"))
                                          ,(arrow)))
                                  "~%")
                             "~%")
                        "~%")
              "~%"))
      (ast->html-tree (doc (para (txt "x") (fn-ref "note"))
                           (fn-def "note" (para (txt "Text.")))))))

(define-test ast->html-tree-footnote-repeat-references
  (is equal
      (tree `((:p nil "x"
                  (:sup ((:class "footnote-ref"))
                        (:a ((:href "#fn-a") (:id "fnref-a") (:data-footnote-ref "")) "1"))
                  (:sup ((:class "footnote-ref"))
                        (:a ((:href "#fn-a") (:id "fnref-a-2") (:data-footnote-ref "")) "1")))
              "~%"
              (:section ((:class "footnotes") (:data-footnotes "")) "~%"
                        (:ol nil "~%"
                             (:li ((:id "fn-a")) "~%"
                                  (:p nil "A "
                                      (:a ((:href "#fnref-a") (:class "footnote-backref")
                                           (:data-footnote-backref "")
                                           (:data-footnote-backref-idx "1")
                                           (:aria-label "Back to reference 1"))
                                          ,(arrow))
                                      " "
                                      (:a ((:href "#fnref-a-2") (:class "footnote-backref")
                                           (:data-footnote-backref "")
                                           (:data-footnote-backref-idx "1-2")
                                           (:aria-label "Back to reference 1-2"))
                                          ,(arrow)
                                          (:sup ((:class "footnote-ref")) "2")))
                                  "~%")
                             "~%")
                        "~%")
              "~%"))
      (ast->html-tree (doc (para (txt "x") (fn-ref "a") (fn-ref "a"))
                           (fn-def "a" (para (txt "A")))))))

(define-test ast->html-tree-footnote-shared-reference-node-counts-each-place
  ;; Nodes are immutable, so one reference node may sit in two places. Each
  ;; place is its own reference, exactly as two distinct nodes would be.
  (let ((shared (fn-ref "a")))
    (is equal
        (ast->html-tree (doc (para (txt "x") (fn-ref "a") (fn-ref "a"))
                             (fn-def "a" (para (txt "A")))))
        (ast->html-tree (doc (para (txt "x") shared shared)
                             (fn-def "a" (para (txt "A"))))))))

(define-test ast->html-tree-footnotes-numbered-by-definition-order
  ;; The references reach b first, but a is defined first: a is 1, b is 2.
  (is equal
      (tree `((:p nil "x" ,(expected-ref "b" 2) " y" ,(expected-ref "a" 1))
              "~%"
              ,@(expected-section (expected-note "a" "A" 1) (expected-note "b" "B" 2))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "b") (txt " y") (fn-ref "a"))
                           (fn-def "a" (para (txt "A")))
                           (fn-def "b" (para (txt "B")))))))

(define-test ast->html-tree-footnote-unreferenced-definition-is-dropped
  ;; z comes first, but nothing references it: it is dropped, and a is 1.
  (is equal
      (tree `((:p nil "x" ,(expected-ref "a" 1)) "~%"
              ,@(expected-section (expected-note "a" "A" 1))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "a"))
                           (fn-def "z" (para (txt "Z")))
                           (fn-def "a" (para (txt "A")))))))

(define-test ast->html-tree-footnote-reference-without-a-definition-is-text
  (is equal (tree '((:p nil "see[^x] and [^y z]") "~%"))
      (ast->html-tree (doc (para (txt "see") (fn-ref "x") (txt " and ") (fn-ref "y z"))))))

(define-test ast->html-tree-footnote-duplicate-label-keeps-the-first-definition
  (is equal
      (tree `((:p nil "x" ,(expected-ref "a" 1)) "~%"
              ,@(expected-section (expected-note "a" "First" 1))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "a"))
                           (fn-def "a" (para (txt "First")))
                           (fn-def "a" (para (txt "Second")))))))

(define-test ast->html-tree-footnote-nested-duplicate-label-keeps-the-inner-definition
  ;; cmark's parser registers a definition as its walk leaves it, and keeps
  ;; the first one registered: the inner a is left before the outer one.
  (is equal
      (tree `((:p nil "x" ,(expected-ref "a" 1)) "~%"
              ,@(expected-section (expected-note "a" "Inner" 1))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "a"))
                           (fn-def "a" (para (txt "Outer")) (fn-def "a" (para (txt "Inner")))))))
  ;; The inner a is numbered at its own place, which comes after c's.
  (is equal
      (tree `((:p nil "x" ,(expected-ref "a" 2) ,(expected-ref "c" 1)) "~%"
              ,@(expected-section (expected-note "c" "C" 1) (expected-note "a" "Inner" 2))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "a") (fn-ref "c"))
                           (fn-def "a"
                                   (para (txt "Outer"))
                                   (fn-def "c" (para (txt "C")))
                                   (fn-def "a" (para (txt "Inner"))))))))

(define-test ast->html-tree-footnote-labels-match-case-sensitively
  ;; A matches nothing, so it stays text; a is unreferenced, so it goes.
  (is equal (tree '((:p nil "x[^A]") "~%"))
      (ast->html-tree (doc (para (txt "x") (fn-ref "A"))
                           (fn-def "a" (para (txt "lower")))))))

;;; The label table (M4 design §5.7): labels are found by LABEL-HASH, and
;;; the labels that share a hash are told apart with STRING=.

(define-test ast->html-tree-footnote-labels-sharing-a-hash-stay-apart
  ;; costarring and liquid share a LABEL-HASH, and so do altarage and zinke.
  ;; Each reference gets its own copy of its label, as a parsed document's
  ;; references do: equal literals in one file can be one object.
  (is = (cl-commonmark-gfm.html-tree::label-hash "costarring")
      (cl-commonmark-gfm.html-tree::label-hash "liquid"))
  (is = (cl-commonmark-gfm.html-tree::label-hash "altarage")
      (cl-commonmark-gfm.html-tree::label-hash "zinke"))
  ;; Both defined: each reference reaches its own definition.
  (is equal
      (tree `((:p nil "x" ,(expected-ref "liquid" 2) ,(expected-ref "costarring" 1)) "~%"
              ,@(expected-section (expected-note "costarring" "C" 1)
                                  (expected-note "liquid" "L" 2))))
      (ast->html-tree (doc (para (txt "x")
                                 (fn-ref (copy-seq "liquid"))
                                 (fn-ref (copy-seq "costarring")))
                           (fn-def "costarring" (para (txt "C")))
                           (fn-def "liquid" (para (txt "L"))))))
  ;; Only zinke defined: altarage, with zinke's hash, still dangles.
  (is equal
      (tree `((:p nil "x[^altarage]" ,(expected-ref "zinke" 1)) "~%"
              ,@(expected-section (expected-note "zinke" "Z" 1))))
      (ast->html-tree (doc (para (txt "x")
                                 (fn-ref (copy-seq "altarage"))
                                 (fn-ref (copy-seq "zinke")))
                           (fn-def "zinke" (para (txt "Z")))))))

(defun short-labels ()
  "Every label of one to three characters from 0 to 9 and a to z: 47,988."
  (let* ((alphabet "0123456789abcdefghijklmnopqrstuvwxyz")
         (ones (map 'list #'string alphabet))
         (twos (loop for one in ones
                     append (loop for char across alphabet
                                  collect (format nil "~A~C" one char))))
         (threes (loop for two in twos
                       append (loop for char across alphabet
                                    collect (format nil "~A~C" two char)))))
    (append ones twos threes)))

(defun short-label-spread ()
  "How many SHORT-LABELS there are, and how many LABEL-HASH values they
take, as (COUNT DISTINCT)."
  (let ((labels (short-labels))
        (hashes (make-hash-table :test 'eql)))
    (dolist (label labels)
      (setf (gethash (cl-commonmark-gfm.html-tree::label-hash label) hashes) t))
    (list (length labels) (hash-table-count hashes))))

(define-test label-hash-spreads-short-labels
  ;; Short labels are where CCL's SXHASH clusters: 71,705 labels of one to
  ;; four such characters take 41,145 of its values, and an EQUAL table of
  ;; them takes seconds. LABEL-HASH must keep them apart: at most one
  ;; label in a thousand shares a value.
  (destructuring-bind (count distinct) (short-label-spread)
    (is = 47988 count)
    (true (>= distinct (- count (floor count 1000))) "~D values for ~D labels" distinct count)))

(define-test ast->html-tree-footnote-reference-in-a-dropped-definition-keeps-its-target
  ;; u is never referenced, so it is dropped. Its reference to c still
  ;; counts, as in cmark's parser, so c survives as 1.
  (is equal
      (tree `((:p nil "x") "~%" ,@(expected-section (expected-note "c" "C" 1))))
      (ast->html-tree (doc (para (txt "x"))
                           (fn-def "u" (para (txt "see ") (fn-ref "c")))
                           (fn-def "c" (para (txt "C"))))))
  ;; The second a is a duplicate, dropped; its reference to c still counts.
  (is equal
      (tree `((:p nil "x" ,(expected-ref "a" 1)) "~%"
              ,@(expected-section (expected-note "a" "A" 1) (expected-note "c" "C" 2))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "a"))
                           (fn-def "a" (para (txt "A")))
                           (fn-def "a" (para (txt "dup ") (fn-ref "c")))
                           (fn-def "c" (para (txt "C")))))))

(define-test ast->html-tree-footnote-backrefs-follow-a-last-child-that-isnt-a-paragraph
  (is equal
      (tree `((:p nil "x" ,(expected-ref "b" 1)) "~%"
              ,@(expected-section
                 `(:li ((:id "fn-b")) "~%"
                       (:p nil "P") "~%"
                       (:pre nil (:code nil "code~%")) "~%"
                       ,(expected-backref "b" 1) "~%"))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "b"))
                           (fn-def "b"
                                   (para (txt "P"))
                                   (n :code-block (list :literal (format nil "code~%"))))))))

(define-test ast->html-tree-footnote-backrefs-go-only-in-the-last-paragraph-place
  ;; One paragraph object sits at three places in a's definition: in a block
  ;; quote, then twice as a child. Only the last child's place is the
  ;; backref paragraph.
  (let ((shared (para (txt "P"))))
    (is equal
        (tree `((:p nil "x" ,(expected-ref "a" 1)) "~%"
                ,@(expected-section
                   `(:li ((:id "fn-a")) "~%"
                         (:blockquote nil "~%" (:p nil "P") "~%") "~%"
                         (:p nil "P") "~%"
                         (:p nil "P " ,(expected-backref "a" 1)) "~%"))))
        (ast->html-tree (doc (para (txt "x") (fn-ref "a"))
                             (fn-def "a" (n :block-quote nil shared) shared shared))))))

(define-test ast->html-tree-footnote-empty-definition
  (is equal
      (tree `((:p nil "x" ,(expected-ref "b" 1)) "~%"
              ,@(expected-section `(:li ((:id "fn-b")) "~%" ,(expected-backref "b" 1) "~%"))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "b")) (fn-def "b")))))

(define-test ast->html-tree-footnote-definitions-leave-their-place
  ;; A definition inside a block quote renders in the section, not there.
  (is equal
      (tree `((:blockquote nil "~%" (:p nil "q" ,(expected-ref "a" 1)) "~%") "~%"
              ,@(expected-section (expected-note "a" "A" 1))))
      (ast->html-tree (doc (n :block-quote nil
                              (para (txt "q") (fn-ref "a"))
                              (fn-def "a" (para (txt "A"))))))))

(define-test ast->html-tree-footnote-nested-definition-leaves-its-parent
  ;; b moves out of a, so a's last child is its paragraph, which takes a's
  ;; backref. a comes first in the tree, so a is 1.
  (is equal
      (tree `((:p nil "x" ,(expected-ref "b" 2) ,(expected-ref "a" 1)) "~%"
              ,@(expected-section (expected-note "a" "A" 1) (expected-note "b" "B" 2))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "b") (fn-ref "a"))
                           (fn-def "a" (para (txt "A")) (fn-def "b" (para (txt "B"))))))))

(define-test ast->html-tree-footnote-section-has-no-cr-before-it
  ;; Inline content at the top level leaves the output mid-line, and cmark
  ;; writes the section straight after it.
  (is equal
      (tree `("x" ,(expected-ref "a" 1) ,@(expected-section (expected-note "a" "A" 1))))
      (ast->html-tree (doc (txt "x") (fn-ref "a") (fn-def "a" (para (txt "A")))))))

(define-test ast->html-tree-footnote-references-inside-an-image
  ;; In alt text a resolved reference adds nothing but still counts, so the
  ;; body's reference is the second; a dangling one is text, as cmark's
  ;; parser makes it.
  (is equal
      (tree `((:p nil (:img ((:src "u") (:alt "a [^zz]"))) ,(expected-ref "n" 1 2)) "~%"
              (:section ((:class "footnotes") (:data-footnotes "")) "~%"
                        (:ol nil "~%"
                             (:li ((:id "fn-n")) "~%"
                                  (:p nil "N "
                                      ,(expected-backref "n" 1)
                                      " "
                                      (:a ((:href "#fnref-n-2") (:class "footnote-backref")
                                           (:data-footnote-backref "")
                                           (:data-footnote-backref-idx "1-2")
                                           (:aria-label "Back to reference 1-2"))
                                          ,(arrow)
                                          (:sup ((:class "footnote-ref")) "2")))
                                  "~%")
                             "~%")
                        "~%")
              "~%"))
      (ast->html-tree (doc (para (n :image (list :destination "u")
                                    (txt "a") (fn-ref "n") (txt " ") (fn-ref "zz"))
                                 (fn-ref "n"))
                           (fn-def "n" (para (txt "N")))))))

(define-test ast->html-tree-footnote-references-resolve-in-nested-definitions-and-their-images
  ;; The pre-pass and the converter walk the tree separately, so they must
  ;; name each place alike. The converter reaches a definition's references,
  ;; a nested one's too, from the section, and an image's through its alt
  ;; text. All four references resolve, each with its K in tree order.
  (is equal
      (tree `((:p nil "x" ,(expected-ref "a" 1)) "~%"
              ,@(expected-section
                 `(:li ((:id "fn-a")) "~%"
                       (:p nil "A" ,(expected-ref "b" 2) " "
                           ,(expected-backref "a" 1) " "
                           ,(expected-backref "a" 1 2) " "
                           ,(expected-backref "a" 1 3))
                       "~%")
                 `(:li ((:id "fn-b")) "~%"
                       (:p nil (:img ((:src "u") (:alt "i"))) ,(expected-ref "a" 1 3) " "
                           ,(expected-backref "b" 2))
                       "~%"))))
      (ast->html-tree
       (doc (para (txt "x") (fn-ref "a"))
            (fn-def "a"
                    (para (txt "A") (fn-ref "b"))
                    (fn-def "b"
                            (para (n :image (list :destination "u") (txt "i") (fn-ref "a"))
                                  (fn-ref "a"))))))))

(define-test ast->html-tree-footnote-reference-ids-follow-tree-order-not-render-order
  ;; a's definition comes first in the tree, so its reference to b is b's
  ;; first (fnref-b), though the body renders before the section; the body's
  ;; b is the second (fnref-b-2). Keys counted per owner, the body or a
  ;; definition place, agree between the pre-pass and the converter, which
  ;; meet the references in different orders (M2 design §4.4).
  (is equal
      (tree `((:p nil ,(expected-ref "b" 2 2) ,(expected-ref "a" 1)) "~%"
              ,@(expected-section
                 `(:li ((:id "fn-a")) "~%"
                       (:p nil "A" ,(expected-ref "b" 2) " " ,(expected-backref "a" 1))
                       "~%")
                 `(:li ((:id "fn-b")) "~%"
                       (:p nil "B " ,(expected-backref "b" 2) " " ,(expected-backref "b" 2 2))
                       "~%"))))
      (ast->html-tree (doc (fn-def "a" (para (txt "A") (fn-ref "b")))
                           (para (fn-ref "b") (fn-ref "a"))
                           (fn-def "b" (para (txt "B")))))))

(define-test ast->html-tree-footnote-labels-are-percent-encoded
  (is equal
      (tree `((:p nil "x" ,(expected-ref "caf%C3%A9" 1)) "~%"
              ,@(expected-section (expected-note "caf%C3%A9" "C" 1))))
      (ast->html-tree (doc (para (txt "x") (fn-ref "café"))
                           (fn-def "café" (para (txt "C")))))))

;;; Extension nodes (M1 design D10)

(define-test ast->html-tree-signals-unsupported-extension-node-anywhere
  (let ((extension (n :extension (list :type-name "x"))))
    (dolist (ast (list extension
                       (doc extension)
                       (doc (para (n :image (list :destination "u") extension)))
                       (doc (para (txt "x")) (fn-def "unused" extension))))
      (let ((condition (signalled 'unsupported-extension-node (lambda () (ast->html-tree ast)))))
        (true condition)
        (is eql extension (and condition (condition-datum condition)))
        (is eql 'ast->html-tree (and condition (condition-operation condition)))))))

;;; Determinism and purity

(define-test ast->html-tree-is-deterministic
  (let ((ast (every-kind-ast)))
    (is equal (ast->html-tree ast) (ast->html-tree ast))
    (is equal (ast->html-tree ast :raw-html :text :softbreak :br :link-policy :unsafe
                                  :document-wrapper :div)
        (ast->html-tree ast :raw-html :text :softbreak :br :link-policy :unsafe
                            :document-wrapper :div))))

(define-test ast->html-tree-holds-only-conses-strings-and-keywords
  (let ((ast (every-kind-ast)))
    (true (html-tree-data-p (ast->html-tree ast)))
    (true (html-tree-data-p (ast->html-tree ast :raw-html :text :softbreak :br
                                                :document-wrapper :div)))))

(define-test ast->html-tree-returns-fresh-structure-and-leaves-the-ast-alone
  (let* ((ast (every-kind-ast))
         (first-tree (ast->html-tree ast))
         (second-tree (ast->html-tree ast)))
    (false (shares-object-p (tree-objects first-tree) second-tree)
           "two conversions share no cons or string")
    (false (shares-object-p (ast-strings ast) first-tree)
           "the tree shares no string with the AST")
    (true (node= (every-kind-ast) ast)
          "converting leaves the AST as it was")))
