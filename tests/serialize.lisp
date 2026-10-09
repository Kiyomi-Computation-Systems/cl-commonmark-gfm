;;;; Tests for HTML-TREE->STRING, VALID-HTML-NAME-P and VOID-ELEMENT-P.

(in-package #:cl-commonmark-gfm.tests)

;;; Escaping in text: & < > " are escaped, ' is not

(define-test html-tree->string-escapes-ampersand-lt-gt-quote-in-text
  (is string= "&amp;" (html-tree->string "&"))
  (is string= "&lt;" (html-tree->string "<"))
  (is string= "&gt;" (html-tree->string ">"))
  (is string= "&quot;" (html-tree->string "\""))
  (is string= "a &amp; b &lt;c&gt; &quot;d&quot;" (html-tree->string "a & b <c> \"d\"")))

(define-test html-tree->string-leaves-apostrophe-raw-in-text
  (is string= "it's" (html-tree->string "it's")))

;;; Escaping in attribute values: title keeps ' raw; href/src/id escape it

(define-test html-tree->string-leaves-apostrophe-raw-in-title
  (is string= "<a title=\"it's\">x</a>"
      (html-tree->string (list :a (list (list :title "it's")) "x"))))

(define-test html-tree->string-escapes-apostrophe-in-href-src-and-id
  (is string= "<a href=\"u&#x27;v\">x</a>"
      (html-tree->string (list :a (list (list :href "u'v")) "x")))
  (is string= "<img src=\"u&#x27;v\" />"
      (html-tree->string (list :img (list (list :src "u'v")))))
  (is string= "<a id=\"u&#x27;v\">x</a>"
      (html-tree->string (list :a (list (list :id "u'v")) "x"))))

(define-test html-tree->string-escapes-ampersand-lt-gt-quote-in-attribute-values
  (is string= "<a href=\"a&amp;b&lt;c&gt;d&quot;e\">x</a>"
      (html-tree->string (list :a (list (list :href "a&b<c>d\"e")) "x"))))

;;; Void elements: br, hr, img, input print with no end tag

(define-test html-tree->string-void-elements
  (is string= "<br />" (html-tree->string (list :br nil)))
  (is string= "<hr />" (html-tree->string (list :hr nil)))
  (is string= "<img src=\"u\" alt=\"a\" />"
      (html-tree->string (list :img (list (list :src "u") (list :alt "a")))))
  (is string= "<input type=\"checkbox\" checked=\"\" disabled=\"\" />"
      (html-tree->string (list :input (list (list :type "checkbox")
                                             (list :checked "")
                                             (list :disabled ""))))))

;;; All 13 of HTML's void elements print void with one attribute, and
;;; reject a child with INVALID-HTML-TREE.

(define-test html-tree->string-all-void-elements-print-void-and-reject-children
  (dolist (tag '(:area :base :br :col :embed :hr :img :input :link :meta :source :track :wbr))
    (let ((name (string-downcase (symbol-name tag))))
      (is string= (format nil "<~A attr=\"v\" />" name)
          (html-tree->string (list tag (list (list :attr "v"))))
          "~A should serialize as a void element" name)
      (fail (html-tree->string (list tag nil "x")) 'invalid-html-tree
            "~A should signal INVALID-HTML-TREE given a child" name))))

;;; Void elements, and repeated/bare/escaped attribute names, are classified
;;; by lowercased name, not by keyword identity: :|br| and
;;; (INTERN "br" :KEYWORD) are not EQL to :BR, but must still be void.

(define-test html-tree->string-void-element-classified-by-lowercased-name
  (fail (html-tree->string (list (intern "br" :keyword) nil "x")) 'invalid-html-tree)
  (is string= "<img src=\"u\" />"
      (html-tree->string (list (intern "img" :keyword) (list (list :src "u"))))))

(define-test html-tree->string-rejects-repeated-attribute-name-classified-by-lowercased-name
  (fail (html-tree->string
         (list :a (list (list (intern "href" :keyword) "javascript:alert(1)")
                        (list :href "https://safe"))
               "x"))
        'invalid-html-tree))

(define-test html-tree->string-escapes-apostrophe-for-a-lowercase-keyword-href
  (is string= "<a href=\"u&#x27;v\">x</a>"
      (html-tree->string (list :a (list (list (intern "href" :keyword) "u'v")) "x"))))

(define-test html-tree->string-bare-attribute-classified-by-lowercased-name
  (is string= "<a data-footnote-ref>x</a>"
      (html-tree->string (list :a (list (list (intern "data-footnote-ref" :keyword) "")) "x"))))

;;; Bare attributes: the three footnote data-* names print bare when empty;
;;; every other attribute, including disabled/checked, keeps ="".

(define-test html-tree->string-bare-footnote-attributes-when-empty
  (is string= "<a data-footnote-ref>x</a>"
      (html-tree->string (list :a (list (list :data-footnote-ref "")) "x")))
  (is string= "<section data-footnotes>x</section>"
      (html-tree->string (list :section (list (list :data-footnotes "")) "x")))
  (is string= "<a data-footnote-backref>x</a>"
      (html-tree->string (list :a (list (list :data-footnote-backref "")) "x"))))

(define-test html-tree->string-non-bare-attributes-print-with-empty-value
  (is string= "<input disabled=\"\" />"
      (html-tree->string (list :input (list (list :disabled "")))))
  (is string= "<input checked=\"\" />"
      (html-tree->string (list :input (list (list :checked ""))))))

(define-test html-tree->string-bare-attribute-name-with-non-empty-value-prints-normally
  (is string= "<a data-footnote-ref=\"1\">x</a>"
      (html-tree->string (list :a (list (list :data-footnote-ref "1")) "x"))))

;;; Comments

(define-test html-tree->string-comment
  (is string= "<!-- raw HTML omitted -->"
      (html-tree->string (list :*comment* nil " raw HTML omitted "))))

;;; Comment text is escaped exactly as text content: browsers do not
;;; parse comments inside TEXTAREA/TITLE/SCRIPT/STYLE, so raw comment text
;;; could let markup escape the comment.

(define-test html-tree->string-comment-text-is-escaped
  (is string= "<!--a&lt;b&amp;c-->"
      (html-tree->string (list :*comment* nil "a<b&c"))))

(define-test html-tree->string-comment-escaping-defeats-textarea-script-injection
  (is string=
      "<textarea><!--&lt;/textarea&gt;&lt;script&gt;alert(1)&lt;/script&gt;--></textarea>"
      (html-tree->string
       (list :textarea nil
             (list :*comment* nil "</textarea><script>alert(1)</script>")))))

;;; Top-level shapes: a string, a list of nodes, and NIL

(define-test html-tree->string-top-level-string
  (is string= "hi" (html-tree->string "hi")))

(define-test html-tree->string-top-level-list-of-nodes
  (is string= "ab" (html-tree->string (list "a" "b")))
  (is string= "a<br />b" (html-tree->string (list "a" (list :br nil) "b")))
  (is string= "<p>a</p><p>b</p>"
      (html-tree->string (list (list :p nil "a") (list :p nil "b")))))

(define-test html-tree->string-nil-is-the-empty-string
  (is string= "" (html-tree->string nil)))

;;; Nesting: no newlines or indentation are ever added

(define-test html-tree->string-adds-no-layout
  (is string= "<p>a</p>" (html-tree->string (list :p nil "a")))
  (is string= "<p></p>" (html-tree->string (list :p nil)))
  (is string= "<div><p>a</p><p>b</p></div>"
      (html-tree->string (list :div nil (list :p nil "a") (list :p nil "b")))))

;;; A tag with no ATTRS/CHILDREN cell at all -- (:p), not (:p nil) -- is a
;;; valid element too: SECOND and CDDR of a one-element list are both NIL.

(define-test html-tree->string-tag-only-element-with-no-attrs-or-children-cell
  (is string= "<p></p>" (html-tree->string (list :p))))

;;; Names print lowercase, regardless of the keyword's own case

(define-test html-tree->string-lowercases-names
  (is string= "<data-thing data-x=\"1\">y</data-thing>"
      (html-tree->string (list :data-thing (list (list :data-x "1")) "y")))
  ;; A keyword whose name isn't upcased by the reader (built via INTERN) is
  ;; still printed lowercase: the rule lowercases the name, it doesn't just
  ;; rely on default reader case.
  (is string= "<foo>x</foo>" (html-tree->string (list (intern "Foo" :keyword) nil "x"))))

;;; Non-ASCII text passes through unchanged: not escaped, not re-encoded

(define-test html-tree->string-passes-through-non-ascii-text
  (let ((text (concatenate 'string "caf" (string (code-char #xE9)))))
    (is string= text (html-tree->string text))))

;;; VALID-HTML-NAME-P

(define-test valid-html-name-p-accepts-any-case-once-lowercased
  (true (cl-commonmark-gfm.html-tree::valid-html-name-p :p))
  (true (cl-commonmark-gfm.html-tree::valid-html-name-p :h1))
  (true (cl-commonmark-gfm.html-tree::valid-html-name-p :data-footnote-ref))
  (true (cl-commonmark-gfm.html-tree::valid-html-name-p :a1-2-3))
  ;; Built with INTERN so its name is mixed-case, independent of reader case:
  ;; the rule matches the LOWERCASED name, so case alone never disqualifies it.
  (true (cl-commonmark-gfm.html-tree::valid-html-name-p (intern "Foo" :keyword))))

(define-test valid-html-name-p-rejects-bad-character-sets-and-shapes
  (false (cl-commonmark-gfm.html-tree::valid-html-name-p :*comment*))
  (false (cl-commonmark-gfm.html-tree::valid-html-name-p :-p))
  (false (cl-commonmark-gfm.html-tree::valid-html-name-p :1p))
  (false (cl-commonmark-gfm.html-tree::valid-html-name-p :p_q))
  (false (cl-commonmark-gfm.html-tree::valid-html-name-p (intern "" :keyword)))
  (false (cl-commonmark-gfm.html-tree::valid-html-name-p "p"))
  (false (cl-commonmark-gfm.html-tree::valid-html-name-p 42))
  (false (cl-commonmark-gfm.html-tree::valid-html-name-p nil)))

;;; VOID-ELEMENT-P

(define-test void-element-p-true-for-br-hr-img-input
  (true (cl-commonmark-gfm.html-tree::void-element-p :br))
  (true (cl-commonmark-gfm.html-tree::void-element-p :hr))
  (true (cl-commonmark-gfm.html-tree::void-element-p :img))
  (true (cl-commonmark-gfm.html-tree::void-element-p :input)))

(define-test void-element-p-false-for-others
  (false (cl-commonmark-gfm.html-tree::void-element-p :p))
  (false (cl-commonmark-gfm.html-tree::void-element-p :a))
  (false (cl-commonmark-gfm.html-tree::void-element-p "br")))

;;; Validation: a malformed element

(define-test html-tree->string-rejects-non-proper-list-element
  ;; Dotted: the children tail ends in a string instead of NIL.
  (fail (html-tree->string (list* :p nil "a" "b")) 'invalid-html-tree)
  ;; Circular: guarded by the shared CL-COMMONMARK-GFM.UTIL:PROPER-LIST-P, not by looping forever.
  (let* ((tail (list "b"))
         (circular (list* :p nil "a" tail)))
    (setf (cdr tail) circular)
    (fail (html-tree->string circular) 'invalid-html-tree)))

;;; Validation: an element that reaches itself through its own children.
;;; None of these loop forever or exhaust the stack: each is caught by the
;;; ancestor-path check, not by recursing until it fails some other way.

(define-test html-tree->string-rejects-an-element-that-contains-itself
  ;; E's own third slot (its one child) is E itself. E is a proper list --
  ;; the cdr chain terminates fine -- so only ancestor tracking, not the
  ;; cycle check above (which only follows cdrs), can catch this.
  (let ((e (list :p nil)))
    (setf (cddr e) (list e))
    (fail (html-tree->string e) 'invalid-html-tree)))

(define-test html-tree->string-rejects-a-deeper-element-cycle
  ;; DIV's child is P, and P's child is DIV: the cycle is two conses long,
  ;; not a direct self-reference.
  (let* ((div (list :div nil))
         (p (list :p nil div)))
    (setf (cddr div) (list p))
    (fail (html-tree->string div) 'invalid-html-tree)))

;;; A DAG -- the same element object reachable more than once, but never
;;; through itself -- is not a cycle, and must still serialize normally.

(define-test html-tree->string-serializes-a-shared-acyclic-element-as-siblings
  (let ((shared (list :span nil "x")))
    (is string= "<div><span>x</span><span>x</span></div>"
        (html-tree->string (list :div nil shared shared)))))

(define-test html-tree->string-serializes-a-shared-acyclic-element-as-cousins
  (let ((shared (list :span nil "x")))
    (is string= "<div><section>1<span>x</span></section><section>2<span>x</span></section></div>"
        (html-tree->string (list :div nil
                                  (list :section nil "1" shared)
                                  (list :section nil "2" shared))))))

(define-test html-tree->string-rejects-tag-that-is-not-a-keyword
  (fail (html-tree->string (list :div nil (list "span" nil "x"))) 'invalid-html-tree))

(define-test html-tree->string-rejects-malformed-attrs-shape
  (fail (html-tree->string (list :p 42 "a")) 'invalid-html-tree)
  ;; A bare keyword where a (name value) pair belongs.
  (fail (html-tree->string (list :p (list :href) "a")) 'invalid-html-tree)
  ;; A three-element "pair".
  (fail (html-tree->string (list :p (list (list :href "u" "extra")) "a")) 'invalid-html-tree))

(define-test html-tree->string-rejects-repeated-attribute-name
  (fail (html-tree->string (list :a (list (list :href "u") (list :href "v")) "x"))
        'invalid-html-tree))

;;; CHECK-NO-REPEATED-ATTRIBUTE-NAMES compares malformed names safely: two
;;; distinct cons names, circular or merely deep, must not reach EQUAL's
;;; unbounded walk, which can hang or crash the process.

(define-test html-tree->string-rejects-two-distinct-circular-cons-attribute-names
  (let ((name1 (list 'x))
        (name2 (list 'x)))
    (setf (cdr name1) name1)
    (setf (cdr name2) name2)
    (fail (html-tree->string (list :a (list (list name1 "v1") (list name2 "v2")) "x"))
          'invalid-html-tree)))

;;; The reason is checked, not just the condition type: two distinct but
;;; EQUAL 100,000-deep cons names must not be reported as a repeat. Some
;;; Lisps' EQUAL survives this depth without overflowing, so names compared
;;; with EQUAL would still signal INVALID-HTML-TREE, as a repeat, and a
;;; type-only check would pass.
(define-test html-tree->string-rejects-two-distinct-100000-deep-cons-attribute-names
  (flet ((deep-name ()
           (let ((c nil))
             (dotimes (i 100000) (setf c (list c)))
             c)))
    (handler-case
        (progn (html-tree->string
                (list :a (list (list (deep-name) "v1") (list (deep-name) "v2")) "x"))
               (true nil "expected invalid-html-tree"))
      (invalid-html-tree (e)
        (is string= "invalid attribute name" (condition-reason e))))))

(define-test html-tree->string-rejects-bad-child
  (fail (html-tree->string (list :p nil 42)) 'invalid-html-tree)
  (fail (html-tree->string (list :p nil nil)) 'invalid-html-tree)
  (fail (html-tree->string (list :p nil 'a-symbol)) 'invalid-html-tree))

;;; Validation: a bad name

(define-test html-tree->string-rejects-bad-tag-name
  (fail (html-tree->string (list :1p nil "x")) 'invalid-html-tree))

(define-test html-tree->string-rejects-bad-attribute-name
  ;; The rule this protects: a keyword can never smuggle markup into an
  ;; attribute name.
  (fail (html-tree->string (list :a (list (list (intern "onclick=\"x\"" :keyword) "y")) "z"))
        'invalid-html-tree))

;;; Validation: an attribute value that isn't a string

(define-test html-tree->string-rejects-non-string-attribute-value
  (fail (html-tree->string (list :a (list (list :href 42)) "x")) 'invalid-html-tree))

;;; Validation: a void element with children

(define-test html-tree->string-rejects-void-element-with-children
  (fail (html-tree->string (list :br nil "x")) 'invalid-html-tree)
  (fail (html-tree->string (list :img (list (list :src "u")) "x")) 'invalid-html-tree))

;;; Validation: a bad comment

(define-test html-tree->string-rejects-malformed-comment-shape
  (fail (html-tree->string (list :*comment* (list (list :class "x")) "text")) 'invalid-html-tree)
  (fail (html-tree->string (list :*comment* nil "a" "b")) 'invalid-html-tree)
  (fail (html-tree->string (list :*comment* nil 42)) 'invalid-html-tree))

(define-test html-tree->string-rejects-unsafe-comment-text
  (fail (html-tree->string (list :*comment* nil "a--b")) 'invalid-html-tree)
  (fail (html-tree->string (list :*comment* nil ">text")) 'invalid-html-tree)
  (fail (html-tree->string (list :*comment* nil "->text")) 'invalid-html-tree)
  (fail (html-tree->string (list :*comment* nil "text-")) 'invalid-html-tree))

;;; Validation: a bad top level

(define-test html-tree->string-rejects-bad-top-level
  (fail (html-tree->string 42) 'invalid-html-tree)
  (fail (html-tree->string :foo) 'invalid-html-tree)
  (fail (html-tree->string (cons "a" "b")) 'invalid-html-tree))

;;; Condition details

(define-test html-tree->string-signals-invalid-html-tree-with-operation-html-tree->string
  (handler-case (progn (html-tree->string 42) (true nil "expected invalid-html-tree"))
    (invalid-html-tree (e) (is eql 'html-tree->string (condition-operation e)))))

;;; Order: the loop over a stack of open elements must meet each element's
;;; problem in document order, as a recursive walk would -- a parent's own
;;; checks (reached first) before its children's, and an earlier sibling's
;;; problem (reached first) before a later one's, each sibling fully
;;; written, errors included, before the next is even looked at.

(define-test html-tree->string-reports-the-first-malformed-sibling-in-document-order
  (handler-case
      (progn (html-tree->string (list :div nil (list :1bad nil "a") (list :2bad nil "a")))
             (true nil "expected invalid-html-tree"))
    (invalid-html-tree (e)
      (is eql :1bad (condition-datum e))
      (is string= "invalid tag name" (condition-reason e)))))

(define-test html-tree->string-reports-a-parents-problem-before-descending-into-a-malformed-child
  (handler-case
      (progn (html-tree->string (list :1bad nil (list :2bad nil "a")))
             (true nil "expected invalid-html-tree"))
    (invalid-html-tree (e)
      (is eql :1bad (condition-datum e))
      (is string= "invalid tag name" (condition-reason e)))))

;;; The self-containment check's datum is EQ to the element that contains
;;; itself, not a copy -- what the deep cycle test in deep.lisp relies on.

(define-test html-tree->string-self-containment-datum-is-eq-to-the-element
  (let ((e (list :p nil)))
    (setf (cddr e) (list e))
    (handler-case
        (progn (html-tree->string e) (true nil "expected invalid-html-tree"))
      (invalid-html-tree (condition)
        (is string= "element contains itself" (condition-reason condition))
        (true (eq e (condition-datum condition)))))))
