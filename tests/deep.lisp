;;;; Deep and wide tests for every walk (M2 design §4.7): the shared
;;;; BUILD-CHAIN, REPEAT-STRING and +DEEP+; seven deep AST shapes, §4.7's six
;;;; plus nested tables, each through WALK-AST, FOLD-AST, MAP-AST,
;;;; TRANSFORM-AST and NODE= at +DEEP+ levels; wide trees; the serializer on
;;;; its own; and the converter over every shape.

(in-package #:cl-commonmark-gfm.tests)

;;; Shared constants and builders (M2a implementation plan, "Interfaces the
;;; tasks share"). BUILD-CHAIN and REPEAT-STRING loop; neither recurses over
;;; DEPTH or COUNT.

(defconstant +deep+ 100000
  "The depth every deep AST test uses (M2 design §4.7).")

(defconstant +wide+ 300000
  "The width the wide-tree AST tests use (M2 design §4.7).")

(defun build-chain (depth leaf wrap)
  "Starting from LEAF, a node, apply WRAP -- a function of one node -- DEPTH
times in a loop, each time wrapping the previous result, and return the
topmost node."
  (let ((node leaf))
    (dotimes (i depth node)
      (setf node (funcall wrap node)))))

(defun repeat-string (string count)
  "Return STRING repeated COUNT times, built with a loop, not recursion."
  (with-output-to-string (out)
    (dotimes (i count)
      (write-string string out))))

;;; The seven deep AST shapes: M2 design §4.7's six, plus nested tables.
;;; TEXT is always the literal of the single deepest leaf; every other
;;; literal these build is fixed, so two trees built with different TEXT
;;; differ at exactly one node.

(defun deep-block-quotes (depth &optional (text "x"))
  "A :DOCUMENT holding DEPTH nested :BLOCK-QUOTEs, the innermost holding a
:PARAGRAPH with one :TEXT node whose literal is TEXT."
  (let ((chain (build-chain depth (n :paragraph nil (txt text))
                             (lambda (child) (n :block-quote nil child)))))
    (n :document nil chain)))

(defun deep-emphasis (depth &optional (text "x"))
  "A :DOCUMENT holding one :PARAGRAPH with DEPTH nested nodes alternating
:EMPH and :STRONG, outermost :EMPH, wrapping one :TEXT node whose literal is
TEXT. WRAP counts its own calls to alternate: the call that produces the
outermost node (call number DEPTH) always lands on :EMPH, whichever parity
DEPTH has."
  (let ((call-number 0))
    (flet ((wrap (child)
             (incf call-number)
             (if (evenp (- depth call-number))
                 (n :emph nil child)
                 (n :strong nil child))))
      (let ((chain (build-chain depth (txt text) #'wrap)))
        (n :document nil (n :paragraph nil chain))))))

(defun deep-lists (depth &optional (text "x"))
  "A :DOCUMENT holding DEPTH levels of a :LIST (bullet, :TIGHT T) holding one
:ITEM, each item holding the next level's :LIST, the innermost item holding
a :PARAGRAPH with one :TEXT node whose literal is TEXT."
  (let ((chain (build-chain depth (n :paragraph nil (txt text))
                             (lambda (child)
                               (n :list (list :type :bullet :tight t)
                                  (n :item nil child))))))
    (n :document nil chain)))

(defun deep-links (depth &optional (text "x"))
  "A :DOCUMENT holding one :PARAGRAPH with DEPTH nested :LINKs
(:DESTINATION \"u\"), the innermost holding a :TEXT node whose literal is
TEXT."
  (let ((chain (build-chain depth (txt text)
                             (lambda (child) (n :link (list :destination "u") child)))))
    (n :document nil (n :paragraph nil chain))))

(defun deep-image (depth &optional (text "x"))
  "A :DOCUMENT holding one :PARAGRAPH with one :IMAGE (:DESTINATION \"i\"),
holding DEPTH nested :EMPH nodes wrapping a :TEXT node whose literal is
TEXT, DEPTH levels below the image."
  (let* ((chain (build-chain depth (txt text) (lambda (child) (n :emph nil child))))
         (image (n :image (list :destination "i") chain)))
    (n :document nil (n :paragraph nil image))))

(defun deep-footnotes (depth &optional (text "x"))
  "A :DOCUMENT whose first child is a :PARAGRAPH holding DEPTH
:FOOTNOTE-REFERENCEs labelled \"1\" through DEPTH in order, followed by
footnote definition \"1\". Definition I (labelled I, as a decimal string)
holds a :PARAGRAPH (:TEXT \"x\") followed by definition I+1, nested inside
it; the last definition, DEPTH, holds only its paragraph, whose :TEXT is
TEXT."
  (let* ((last-definition (n :footnote-definition (list :label (princ-to-string depth))
                              (n :paragraph nil (txt text))))
         (call-number 0)
         (definitions
           (build-chain (1- depth) last-definition
                        (lambda (child)
                          (incf call-number)
                          (n :footnote-definition
                             (list :label (princ-to-string (- depth call-number)))
                             (n :paragraph nil (txt "x"))
                             child))))
         (references (loop for i from 1 to depth
                            collect (n :footnote-reference (list :label (princ-to-string i))))))
    (n :document nil (make-node :paragraph :children references) definitions)))

(defun deep-tables (depth &optional (text "x"))
  "A :DOCUMENT holding DEPTH nested :TABLEs: each :TABLE holds one
:TABLE-ROW holding one :TABLE-CELL, which holds the next level's :TABLE; the
innermost cell holds a :TEXT node whose literal is TEXT."
  (let ((chain (build-chain depth (txt text)
                             (lambda (child)
                               (n :table nil (n :table-row nil (n :table-cell nil child)))))))
    (n :document nil chain)))

;;; The wide shape: one node, WIDTH children.

(defun wide-paragraph (width &optional (text "x"))
  "A :PARAGRAPH with WIDTH :TEXT children, in order; every child's :LITERAL
is \"x\" except the last, whose :LITERAL is TEXT."
  (let ((children (loop for i from 1 to width
                         collect (txt (if (= i width) text "x")))))
    (make-node :paragraph :children children)))

;;; Shared walk helpers. Each counts independently of the other walks, so a
;;; bug shared between two of WALK-AST, FOLD-AST and MAP-AST cannot make
;;; mismatched counts agree with each other.

(defun count-walk-ast-events (node)
  "Return the total number of :ENTER and :EXIT calls WALK-AST makes while
visiting NODE and its descendants."
  (let ((count 0))
    (walk-ast (lambda (event n) (declare (ignore event n)) (incf count)) node)
    count))

(defun count-fold-ast-nodes (node)
  "Return the number of nodes FOLD-AST visits under NODE, counted by
FOLD-AST itself."
  (fold-ast (lambda (n acc) (declare (ignore n)) (1+ acc)) 0 node))

;;; Parachute keeps every assertion's closure until the run ends, and with
;;; it whatever the closure captured. So no assertion in this file captures
;;; a tree or a large string: helpers build them, check them and return
;;; numbers and booleans, or the asserted form builds them itself. Captured
;;; trees and strings once kept 515 MB alive through the run, and SBCL ran
;;; out of heap at Debian's default of 1 GB.

(defun walk-facts (build size)
  "What the walk tests check, for three trees BUILD makes at SIZE: two alike,
and one whose deepest text is \"y\". Returns a plist of numbers and
booleans, so no test holds a tree:
- :EVENTS, WALK-AST's event count; :NODES, FOLD-AST's node count; :MAPPED,
  MAP-AST's length;
- :IDENTITY, whether TRANSFORM-AST with IDENTITY returns the same root;
  :REBUILT, whether TRANSFORM-AST rebuilding every node with COPY-NODE
  returns a tree NODE= to the original;
- :SAME and :DIFFERENT, NODE= of the first tree with the second, and with
  the third."
  (let ((a (funcall build size))
        (b (funcall build size))
        (c (funcall build size "y")))
    (list :events (count-walk-ast-events a)
          :nodes (count-fold-ast-nodes a)
          :mapped (length (map-ast #'node-kind a))
          :identity (eql a (transform-ast #'identity a))
          :rebuilt (node= a (transform-ast (lambda (n) (copy-node n)) a))
          :same (node= a b)
          :different (node= a c))))

;;; Deep tests. Each shape at +DEEP+ levels: WALK-AST's event count,
;;; FOLD-AST's node count and MAP-AST's length, each checked against a count
;;; derived from the shape's own structure, not from the code under test;
;;; TRANSFORM-AST with IDENTITY returns the same root; TRANSFORM-AST
;;; rebuilding every node with COPY-NODE returns a tree NODE= to the
;;; original; NODE= of two separately built trees is true, and false when
;;; only the deepest leaf's text differs.

(define-test deep-block-quotes-walks
  (let ((facts (walk-facts #'deep-block-quotes +deep+))
        (nodes (+ +deep+ 3)))
    (is = (* 2 nodes) (getf facts :events))
    (is = nodes (getf facts :nodes))
    (is = nodes (getf facts :mapped))
    (true (getf facts :identity))
    (true (getf facts :rebuilt))
    (true (getf facts :same))
    (false (getf facts :different))))

(define-test deep-emphasis-walks
  (let ((facts (walk-facts #'deep-emphasis +deep+))
        (nodes (+ +deep+ 3)))
    (is = (* 2 nodes) (getf facts :events))
    (is = nodes (getf facts :nodes))
    (is = nodes (getf facts :mapped))
    (true (getf facts :identity))
    (true (getf facts :rebuilt))
    (true (getf facts :same))
    (false (getf facts :different))))

(define-test deep-lists-walks
  (let ((facts (walk-facts #'deep-lists +deep+))
        (nodes (+ (* 2 +deep+) 3)))
    (is = (* 2 nodes) (getf facts :events))
    (is = nodes (getf facts :nodes))
    (is = nodes (getf facts :mapped))
    (true (getf facts :identity))
    (true (getf facts :rebuilt))
    (true (getf facts :same))
    (false (getf facts :different))))

(define-test deep-links-walks
  (let ((facts (walk-facts #'deep-links +deep+))
        (nodes (+ +deep+ 3)))
    (is = (* 2 nodes) (getf facts :events))
    (is = nodes (getf facts :nodes))
    (is = nodes (getf facts :mapped))
    (true (getf facts :identity))
    (true (getf facts :rebuilt))
    (true (getf facts :same))
    (false (getf facts :different))))

(define-test deep-image-walks
  (let ((facts (walk-facts #'deep-image +deep+))
        (nodes (+ +deep+ 4)))
    (is = (* 2 nodes) (getf facts :events))
    (is = nodes (getf facts :nodes))
    (is = nodes (getf facts :mapped))
    (true (getf facts :identity))
    (true (getf facts :rebuilt))
    (true (getf facts :same))
    (false (getf facts :different))))

(define-test deep-footnotes-walks
  (let ((facts (walk-facts #'deep-footnotes +deep+))
        (nodes (+ (* 4 +deep+) 2)))
    (is = (* 2 nodes) (getf facts :events))
    (is = nodes (getf facts :nodes))
    (is = nodes (getf facts :mapped))
    (true (getf facts :identity))
    (true (getf facts :rebuilt))
    (true (getf facts :same))
    (false (getf facts :different))))

(define-test deep-tables-walks
  (let ((facts (walk-facts #'deep-tables +deep+))
        (nodes (+ (* 3 +deep+) 2)))
    (is = (* 2 nodes) (getf facts :events))
    (is = nodes (getf facts :nodes))
    (is = nodes (getf facts :mapped))
    (true (getf facts :identity))
    (true (getf facts :rebuilt))
    (true (getf facts :same))
    (false (getf facts :different))))

;;; Wide test: one node, +WIDE+ children.

(define-test wide-paragraph-walks
  (let ((facts (walk-facts #'wide-paragraph +wide+))
        (nodes (1+ +wide+)))
    (is = (* 2 nodes) (getf facts :events))
    (is = nodes (getf facts :nodes))
    (is = nodes (getf facts :mapped))
    (true (getf facts :identity))
    (true (getf facts :rebuilt))
    (true (getf facts :same))
    (false (getf facts :different))))

;;; The serializer (M2 design §4.7, Task 3). A deep HTML tree and a deep
;;; element cycle, both built with a loop -- not BUILD-CHAIN, which builds
;;; AST nodes, not HTML-tree conses. Deep values never reach a failure
;;; message: the assertions see strings compared inside the asserted form,
;;; and DEEP-CYCLE-FACTS's plist.

(defconstant +cycle-depth+ 50000
  "The depth HTML-TREE->STRING's deep-cycle test uses: an element that
contains itself this many levels down (M2 design §4.7; M2a implementation
plan, Task 3). Distinct from +DEEP+, which this test does not use.")

(defun deep-html-tree (depth &optional (text "x"))
  "An HTML-tree element, (:DIV NIL (:DIV NIL ... TEXT)): DEPTH levels of
(:DIV NIL ...) nested around one child TEXT string, built with a loop, not
BUILD-CHAIN, which builds AST nodes (M2 design §4.7)."
  (let ((tree text))
    (dotimes (i depth tree)
      (setf tree (list :div nil tree)))))

(defun deep-cycle-html-tree (depth)
  "DEPTH (:DIV NIL) elements chained with a loop, each one's only child the
next, and the innermost element's only child the first (outermost) element,
closing a cycle DEPTH conses long: HTML-TREE->STRING's self-containment
check must still find it, without recursing DEPTH deep to do so (M2 design
§4.7). Returns the outermost element."
  (let* ((outermost (list :div nil))
         (innermost outermost))
    (dotimes (i (1- depth))
      (let ((next (list :div nil)))
        (setf (cddr innermost) (list next))
        (setf innermost next)))
    (setf (cddr innermost) (list outermost))
    outermost))

(define-test deep-html-tree-serializes
  (true (string= (concatenate 'string
                              (repeat-string "<div>" +deep+)
                              "x"
                              (repeat-string "</div>" +deep+))
                 (html-tree->string (deep-html-tree +deep+)))))

(defun deep-cycle-facts (depth)
  "Serialize the cycle DEEP-CYCLE-HTML-TREE builds at DEPTH. Returns NIL
when nothing is signalled, and otherwise a plist: :REASON, the reason of the
INVALID-HTML-TREE signalled, and :DATUM-IS-ROOT, whether its datum is the
outermost element."
  (let ((tree (deep-cycle-html-tree depth)))
    (handler-case (progn (html-tree->string tree) nil)
      (invalid-html-tree (condition)
        (list :reason (condition-reason condition)
              :datum-is-root (eql tree (condition-datum condition)))))))

(define-test deep-cycle-html-tree-signals-element-contains-itself
  (let ((facts (deep-cycle-facts +cycle-depth+)))
    (true facts "expected invalid-html-tree")
    (is string= "element contains itself" (getf facts :reason))
    (true (getf facts :datum-is-root))))

;;; The converter (M2 design §4.7). Each of the seven AST shapes at
;;; +DEEP+ levels goes through AST->HTML-TREE, then HTML-TREE->STRING, and
;;; the result is compared with STRING= to a string built by REPEAT-STRING
;;; and plain loops, never by the code under test. At depths 1, 2 and 3,
;;; each builder below reproduces M1's HTML for its shape. Deep values never
;;; reach a failure message: every assertion is TRUE around STRING=.

(defun deep-html (ast)
  "AST converted by AST->HTML-TREE, then serialized by HTML-TREE->STRING."
  (html-tree->string (ast->html-tree ast)))

(defun expected-deep-block-quotes (depth)
  "The HTML of (DEEP-BLOCK-QUOTES DEPTH): DEPTH start tags, each on its own
line, the paragraph, then DEPTH end tags."
  (concatenate 'string
               (repeat-string (format nil "<blockquote>~%") depth)
               (format nil "<p>x</p>~%")
               (repeat-string (format nil "</blockquote>~%") depth)))

(defun expected-deep-emphasis (depth)
  "The HTML of (DEEP-EMPHASIS DEPTH): levels counted from 1 at the top, em at
odd levels and strong at even ones. A strong's parent is an em, so every
level adds an element."
  (with-output-to-string (out)
    (write-string "<p>" out)
    (loop for level from 1 to depth
          do (write-string (if (oddp level) "<em>" "<strong>") out))
    (write-string "x" out)
    (loop for level from depth downto 1
          do (write-string (if (oddp level) "</em>" "</strong>") out))
    (format out "</p>~%")))

(defun expected-deep-lists (depth)
  "The HTML of (DEEP-LISTS DEPTH): every list is tight, so the innermost
item holds the bare text, and each outer item holds the next list after a
newline."
  (concatenate 'string
               (format nil "<ul>~%<li>")
               (repeat-string (format nil "~%<ul>~%<li>") (1- depth))
               "x"
               (repeat-string (format nil "</li>~%</ul>~%") depth)))

(defun expected-deep-links (depth)
  "The HTML of (DEEP-LINKS DEPTH): DEPTH links, one inside the other."
  (concatenate 'string
               "<p>"
               (repeat-string "<a href=\"u\">" depth)
               "x"
               (repeat-string "</a>" depth)
               (format nil "</p>~%")))

(defun expected-deep-image (depth)
  "The HTML of (DEEP-IMAGE DEPTH), the same at every DEPTH: the alt text is
the deepest text's literal."
  (declare (ignore depth))
  (format nil "<p><img src=\"i\" alt=\"x\" /></p>~%"))

(defun expected-deep-footnotes (depth)
  "The HTML of (DEEP-FOOTNOTES DEPTH): the body cites 1 to DEPTH, each once.
Every definition survives, numbered by its label, and its item holds its
paragraph and its backref; the definition nested in it renders as its own
item."
  (with-output-to-string (out)
    (write-string "<p>" out)
    (loop for i from 1 to depth
          do (format out "<sup class=\"footnote-ref\"><a href=\"#fn-~D\" id=\"fnref-~D\" ~
                          data-footnote-ref>~D</a></sup>"
                     i i i))
    (format out "</p>~%<section class=\"footnotes\" data-footnotes>~%<ol>~%")
    (loop for i from 1 to depth
          do (format out "<li id=\"fn-~D\">~%<p>x <a href=\"#fnref-~D\" class=\"footnote-backref\" ~
                          data-footnote-backref data-footnote-backref-idx=\"~D\" ~
                          aria-label=\"Back to reference ~D\">~A</a></p>~%</li>~%"
                     i i i i (arrow)))
    (format out "</ol>~%</section>~%")))

(defun expected-deep-tables (depth)
  "The HTML of (DEEP-TABLES DEPTH): DEPTH nested tables, each cell holding
the next level's table on its own line, the innermost cell holding the bare
text; every table's row opens its own tbody, since each is a distinct
:TABLE node (M1's output at depths 1-3, confirmed by hand before this was
written)."
  (concatenate 'string
               (repeat-string (format nil "<table>~%<tbody>~%<tr>~%<td>~%") (1- depth))
               (format nil "<table>~%<tbody>~%<tr>~%<td>x</td>~%</tr>~%</tbody>~%</table>~%")
               (repeat-string (format nil "</td>~%</tr>~%</tbody>~%</table>~%") (1- depth))))

(define-test deep-block-quotes-converts
  (true (string= (expected-deep-block-quotes +deep+) (deep-html (deep-block-quotes +deep+)))))

(define-test deep-emphasis-converts
  (true (string= (expected-deep-emphasis +deep+) (deep-html (deep-emphasis +deep+)))))

(define-test deep-lists-converts
  (true (string= (expected-deep-lists +deep+) (deep-html (deep-lists +deep+)))))

(define-test deep-links-converts
  (true (string= (expected-deep-links +deep+) (deep-html (deep-links +deep+)))))

(define-test deep-image-converts
  (true (string= (expected-deep-image +deep+) (deep-html (deep-image +deep+)))))

(define-test deep-footnotes-converts
  (true (string= (expected-deep-footnotes +deep+) (deep-html (deep-footnotes +deep+)))))

(define-test deep-tables-converts
  (true (string= (expected-deep-tables +deep+) (deep-html (deep-tables +deep+)))))

;;; The wide shape through the converter: Task 2's WIDE-PARAGRAPH at +WIDE+,
;;; wrapped in a document, through AST->HTML-TREE then HTML-TREE->STRING.
;;; The expected string is built by REPEAT-STRING, not by the code under
;;; test; confirmed against M1's output at width 3 (<p>xxx</p> and a
;;; newline) before this was written.

(define-test wide-paragraph-converts
  (true (string= (concatenate 'string "<p>" (repeat-string "x" +wide+) "</p>" (string #\Newline))
                 (deep-html (n :document nil (wide-paragraph +wide+))))))

(defun wide-emphasis (width)
  "A :DOCUMENT holding one :PARAGRAPH with WIDTH :EMPH children, each holding
:TEXT \"x\"."
  (n :document nil (make-node :paragraph
                              :children (loop repeat width
                                              collect (n :emph nil (txt "x"))))))

(define-test wide-emphasis-converts
  ;; +WIDE+ :EMPH children don't merge the way text does, so the converter's
  ;; open element and the serializer each meet +WIDE+ siblings.
  (true (string= (concatenate 'string "<p>" (repeat-string "<em>x</em>" +wide+) "</p>"
                              (string #\Newline))
                 (deep-html (wide-emphasis +wide+)))))
