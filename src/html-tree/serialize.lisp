;;;; HTML-TREE->STRING: serializing an LHTML-shaped tree to a string,
;;;; looping over an explicit stack of open elements instead of recursing, so
;;;; the Lisp call stack doesn't bound a tree's depth.

(in-package #:cl-commonmark-gfm.html-tree)

;;; Data: void elements, bare attributes, and the URL-escaped attributes
;;;
;;; Each table holds lowercased name strings, and every lookup below goes
;;; through LOWERCASE-NAME-STRING first: a tag or attribute is classified on
;;; its lowercased name, never on keyword identity. Otherwise :|br| (built
;;; with INTERN, or read with a case-preserving readtable) would not be
;;; treated as void, :|href| would get no ' escape, and :HREF next to
;;; :|href| would not be caught as a repeat.

(defun lowercase-name-string (keyword)
  "KEYWORD's SYMBOL-NAME, lowercased, as a fresh string. Used both to
classify a tag or attribute name (compared with STRING= against the tables
below) and to print it, so classification and printing can never disagree."
  (string-downcase (symbol-name keyword)))

(defparameter *void-element-names* '("br" "hr" "img" "input")
  "Lowercased element names that print with no children and no end tag, as
\"<tag />\": the void elements cmark-gfm writes.")

(defparameter *bare-attribute-names* '("data-footnotes" "data-footnote-ref" "data-footnote-backref")
  "Lowercased attribute names that print with no value, as just \" name\",
when their value is \"\", as cmark-gfm writes them. Every other attribute,
including DISABLED and CHECKED, prints \" name=\\\"\\\"\" for an empty value.")

(defparameter *url-attribute-names* '("href" "src" "id")
  "Lowercased attribute names whose values get the extra ' -> &#x27; escape,
mirroring cmark-gfm's houdini_escape_href. Every other attribute (TITLE,
ALT, ...) leaves ' raw, as houdini_escape_html0 does.")

;;; VOID-ELEMENT-P

(defun void-element-name-p (name-string)
  "True when NAME-STRING, an already-lowercased element name, is one of
*VOID-ELEMENT-NAMES*."
  (and (member name-string *void-element-names* :test #'string=) t))

(defun void-element-p (keyword)
  "True when KEYWORD is a void element tag: :BR, :HR, :IMG or :INPUT, in any
keyword case or interning, classified by its LOWERCASE-NAME-STRING rather
than by keyword identity. A void element with children signals
INVALID-HTML-TREE."
  (and (keywordp keyword) (void-element-name-p (lowercase-name-string keyword))))

;;; VALID-HTML-NAME-P

(defun ascii-lowercase-letter-p (char)
  "True when CHAR is an ASCII lowercase letter, a-z."
  (char<= #\a char #\z))

(defun ascii-digit-p (char)
  "True when CHAR is an ASCII digit, 0-9."
  (char<= #\0 char #\9))

(defun html-name-string-p (string)
  "True when STRING matches [a-z][a-z0-9-]*, ASCII only. STRING is assumed
already lowercased; this only checks the character set and shape."
  (and (plusp (length string))
       (ascii-lowercase-letter-p (char string 0))
       (loop for char across string
             always (or (ascii-lowercase-letter-p char)
                        (ascii-digit-p char)
                        (char= char #\-)))))

(defun valid-html-name-p (keyword)
  "True when KEYWORD is a keyword whose LOWERCASE-NAME-STRING matches
[a-z][a-z0-9-]*, ASCII only, so no name can carry markup into the output.
False for :*COMMENT* (the one tag the serializer exempts from this rule)
and for anything that isn't a keyword."
  (and (keywordp keyword)
       (html-name-string-p (lowercase-name-string keyword))))

;;; Escaping

(defun write-escaped-char (char out escape-apostrophe)
  "Write CHAR to OUT, entity-escaping &, <, > and \". Escapes ' as &#x27;
when ESCAPE-APOSTROPHE, otherwise writes it raw."
  (case char
    (#\& (write-string "&amp;" out))
    (#\< (write-string "&lt;" out))
    (#\> (write-string "&gt;" out))
    (#\" (write-string "&quot;" out))
    (#\' (write-string (if escape-apostrophe "&#x27;" "'") out))
    (t (write-char char out))))

(defun write-escaped-string (string out &optional escape-apostrophe)
  "Write STRING to OUT, applying WRITE-ESCAPED-CHAR to every character."
  (loop for char across string
        do (write-escaped-char char out escape-apostrophe)))

;;; Errors

(defun invalid-tree (datum reason)
  "Signal INVALID-HTML-TREE for HTML-TREE->STRING, naming the offending
DATUM and a short REASON."
  (error 'invalid-html-tree :operation 'html-tree->string :datum datum :reason reason))

;;; Attributes

(defun attrs-shape-p (attrs)
  "True when ATTRS is NIL or a proper list of two-element (NAME VALUE)
lists: the shape alone, before each NAME and VALUE is validated."
  (or (null attrs)
      (and (proper-list-p attrs)
           (every (lambda (pair) (and (proper-list-p pair) (= (length pair) 2))) attrs))))

(defun attribute-name-key (name)
  "A value that identifies NAME for CHECK-NO-REPEATED-ATTRIBUTE-NAMES: its
LOWERCASE-NAME-STRING when NAME is a keyword, so :HREF and :|href| collide;
NAME itself otherwise, so a malformed non-keyword name still
compares consistently, and CHECK-ATTRIBUTE-NAME-AND-VALUE rejects it right
after."
  (if (keywordp name) (lowercase-name-string name) name))

(defun attribute-name-key= (a b)
  "True when A and B, two values from ATTRIBUTE-NAME-KEY, name the same
attribute: STRING= when both are strings, so keyword and string names
collide by their lowercased spelling, and EQL otherwise. A malformed name
that is neither a string nor a keyword is compared by identity, never by
structure, so a circular or deeply nested name can't hang or overflow the
check."
  (if (and (stringp a) (stringp b))
      (string= a b)
      (eql a b)))

(defun check-no-repeated-attribute-names (attrs)
  "Signal INVALID-HTML-TREE when ATTRS (already ATTRS-SHAPE-P) repeats a
name, once every keyword name is lowercased; names compare with
ATTRIBUTE-NAME-KEY=. So two distinct but EQUAL names that are neither
strings nor keywords, such as conses, bit vectors or pathnames, aren't a
repeat, and CHECK-ATTRIBUTE-NAME-AND-VALUE rejects them right after, as
\"invalid attribute name\"."
  (let ((seen '()))
    (dolist (pair attrs)
      (let* ((name (first pair))
             (key (attribute-name-key name)))
        (when (member key seen :test #'attribute-name-key=)
          (invalid-tree name "repeated attribute name"))
        (push key seen)))))

(defun check-attribute-name-and-value (pair)
  "Signal INVALID-HTML-TREE when PAIR's name fails VALID-HTML-NAME-P or its
value isn't a string."
  (let ((name (first pair))
        (value (second pair)))
    (unless (valid-html-name-p name)
      (invalid-tree name "invalid attribute name"))
    (unless (stringp value)
      (invalid-tree (list name value) "attribute value is not a string"))))

(defun bare-attribute-p (name-string value)
  "True when NAME-STRING (already lowercased) is one of the footnote
attributes that print bare, as just \" name\", and VALUE is \"\"."
  (and (string= value "") (member name-string *bare-attribute-names* :test #'string=) t))

(defun write-attribute (pair out)
  "Write one already-validated (NAME VALUE) PAIR to OUT: a leading space,
NAME's LOWERCASE-NAME-STRING, and, unless it prints bare, =\"value\" with
VALUE escaped (the extra ' escape applies to *URL-ATTRIBUTE-NAMES*)."
  (let* ((name (first pair))
         (value (second pair))
         (name-string (lowercase-name-string name)))
    (write-char #\Space out)
    (write-string name-string out)
    (unless (bare-attribute-p name-string value)
      (write-string "=\"" out)
      (write-escaped-string value out (member name-string *url-attribute-names* :test #'string=))
      (write-char #\" out))))

;;; Comments

(defun check-comment-shape (element)
  "Signal INVALID-HTML-TREE unless ELEMENT is exactly (:*COMMENT* NIL
\"text\"). Returns the text."
  (unless (and (= (length element) 3)
               (null (second element))
               (stringp (third element)))
    (invalid-tree element "malformed comment"))
  (third element))

(defun string-starts-with-p (prefix string)
  "True when STRING starts with PREFIX, compared with STRING= (case-sensitive)."
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun unsafe-comment-text-p (text)
  "True when TEXT could end the comment early: it contains --, starts with >
or ->, or ends with -."
  (or (search "--" text)
      (string-starts-with-p ">" text)
      (string-starts-with-p "->" text)
      (and (plusp (length text)) (char= (char text (1- (length text))) #\-))))

(defun write-comment (element out)
  "Validate ELEMENT as an exact (:*COMMENT* NIL \"text\") comment and write
it to OUT as <!--text-->, with TEXT escaped exactly as text content -- &,
<, >, \" but not ' -- since browsers do not parse comments inside TEXTAREA,
TITLE, SCRIPT or STYLE: raw comment text there could let markup escape the
comment. Signals INVALID-HTML-TREE for any other shape, or for text that
could end the comment early."
  (let ((text (check-comment-shape element)))
    (when (unsafe-comment-text-p text)
      (invalid-tree element "unsafe comment text"))
    (write-string "<!--" out)
    (write-escaped-string text out)
    (write-string "-->" out)))

;;; The stack of open elements
;;;
;;; HTML-TREE->STRING loops over an explicit stack of WRITE-FRAMEs -- one
;;; per element currently open, holding the element and the children (or,
;;; for the one synthetic top-level frame, top-level nodes) still to write
;;; -- instead of recursing through WRITE-NODE, OPEN-ELEMENT and
;;; OPEN-REGULAR-ELEMENT, so depth is bounded by memory rather than by the
;;; Lisp call stack. OPEN-ELEMENTS, an EQ hash set threaded alongside OUT,
;;; holds the open elements: CHECK-NOT-SELF-REFERENTIAL consults it in
;;; O(1), where scanning a list of them at every element would be quadratic
;;; in depth.

(defun check-proper-element-list (element)
  "Signal INVALID-HTML-TREE unless ELEMENT is a proper list, guarding
against circular and dotted lists."
  (unless (proper-list-p element)
    (invalid-tree element "not a proper list")))

(defstruct (write-frame
             (:constructor make-write-frame (element tag-string remaining))
             (:conc-name %frame-)
             (:copier nil))
  "One HTML-TREE->STRING stack frame: ELEMENT, the open regular element
cons being written, or NIL for the one synthetic frame that holds the
top-level nodes; TAG-STRING, ELEMENT's already-lowercased tag string, for
writing its end tag later (unused when ELEMENT is NIL); and REMAINING,
ELEMENT's children -- or, for the synthetic frame, the top-level nodes --
not yet written."
  element
  tag-string
  remaining)

(defun check-not-self-referential (element open-elements)
  "Signal INVALID-HTML-TREE when ELEMENT is already a key of OPEN-ELEMENTS,
the EQ hash set of open elements -- ones whose start tag is written and
whose end tag isn't: OPEN-REGULAR-ELEMENT adds ELEMENT to it when its start
tag is written, and CLOSE-WRITE-FRAME removes it when its end tag is
written, so it only ever holds elements on the path from the root down to
whatever is being written right now. Being an EQ, object-identity check,
only actually re-entering the same cons trips it: a tree that is a DAG
rather than a tree -- the same element cons reachable more than once, but
never through itself -- serializes normally, since each occurrence's own
write finishes, and comes back off OPEN-ELEMENTS, before the next begins; a
later, unrelated sibling or cousin reference to it does not look like an
ancestor."
  (when (gethash element open-elements)
    (invalid-tree element "element contains itself")))

(defun open-regular-element (element out open-elements)
  "Validate ELEMENT, a non-comment (TAG ATTRS . CHILDREN) list, and write
its start tag to OUT. The checks run in this order, which decides what an
element with several problems reports: self-containment, the tag is a
keyword, the tag is a valid name, the attrs' shape, repeated attribute
names, then each pair's name and value. Signals INVALID-HTML-TREE for a
void element with children.

A void element is written whole, start tag and all, here, and this returns
NIL: it has no children to recurse into, so nothing is pushed onto the
stack or added to OPEN-ELEMENTS. A non-void element is added to
OPEN-ELEMENTS and this returns a new WRITE-FRAME holding its CHILDREN, for
WRITE-NODES to push, so CLOSE-WRITE-FRAME can write its end tag and remove
it from OPEN-ELEMENTS once they are all written."
  (let ((tag (first element))
        (attrs (second element))
        (children (cddr element)))
    (check-not-self-referential element open-elements)
    (unless (keywordp tag)
      (invalid-tree tag "tag is not a keyword"))
    (unless (valid-html-name-p tag)
      (invalid-tree tag "invalid tag name"))
    (unless (attrs-shape-p attrs)
      (invalid-tree attrs "attrs must be nil or a list of two-element (name value) lists"))
    (check-no-repeated-attribute-names attrs)
    (dolist (pair attrs) (check-attribute-name-and-value pair))
    (let* ((tag-string (lowercase-name-string tag))
           (voidp (void-element-name-p tag-string)))
      (when (and voidp children)
        (invalid-tree element "void element with children"))
      (write-char #\< out)
      (write-string tag-string out)
      (dolist (pair attrs) (write-attribute pair out))
      (cond
        (voidp (write-string " />" out) nil)
        (t
         (write-char #\> out)
         (setf (gethash element open-elements) t)
         (make-write-frame element tag-string children))))))

(defun open-element (element out open-elements)
  "Validate ELEMENT -- (:*COMMENT* NIL \"text\") or a regular
(TAG ATTRS . CHILDREN) list -- and write it, checking in this order:
ELEMENT must be a proper list; then, for a comment, its shape and its
text's safety; for a regular element, OPEN-REGULAR-ELEMENT's checks. A
comment is always fully written here, and this returns NIL; see
OPEN-REGULAR-ELEMENT for the regular-element case."
  (check-proper-element-list element)
  (cond
    ((eql (first element) :*comment*) (write-comment element out) nil)
    (t (open-regular-element element out open-elements))))

(defun write-node (node out open-elements)
  "Write NODE -- a child or top-level string or element -- to OUT, and
return a new WRITE-FRAME for WRITE-NODES to push when NODE opens a non-void
regular element with children still to write, or NIL when NODE is already
fully written. Signals INVALID-HTML-TREE, naming NODE, when NODE is neither
a string nor a cons; a cons that isn't a well-formed element is rejected
inside OPEN-ELEMENT instead, naming the particular problem."
  (cond
    ((stringp node) (write-escaped-string node out) nil)
    ((consp node) (open-element node out open-elements))
    (t (invalid-tree node "not a string or an element"))))

(defun close-write-frame (frame out open-elements)
  "Finish FRAME once its REMAINING is empty: write its end tag and remove
its ELEMENT from OPEN-ELEMENTS. The one synthetic frame with a NIL ELEMENT
-- the top-level nodes -- needs neither."
  (let ((element (%frame-element frame)))
    (when element
      (write-string "</" out)
      (write-string (%frame-tag-string frame) out)
      (write-char #\> out)
      (remhash element open-elements))))

(defun write-nodes (nodes out open-elements)
  "Write NODES -- a proper list of top-level strings and elements -- to OUT,
each fully written, descendants included, before the next.

Loops over an explicit stack of WRITE-FRAMEs, seeded with one synthetic
frame holding NODES, instead of recursing through WRITE-NODE, OPEN-ELEMENT
and OPEN-REGULAR-ELEMENT, so depth is bounded by memory rather than by the
Lisp call stack. At each step, the top frame's next not-yet-written child or
top-level node is written; when that opens a non-void element, the new
frame WRITE-NODE returns is pushed on top, so its own children are written,
in full, before the frame beneath it is resumed. Once a frame's REMAINING
is empty, CLOSE-WRITE-FRAME finishes it and it is popped, resuming its
parent frame -- which is how a later sibling or cousin reference to an
already-fully-written, merely shared element is never mistaken for a
self-reference: by the time it is reached, the earlier occurrence's frame
has already been popped, and its element removed from OPEN-ELEMENTS."
  (let ((stack (list (make-write-frame nil nil nodes))))
    (loop while stack
          do (let ((frame (first stack)))
               (cond
                 ((%frame-remaining frame)
                  (let ((new-frame (write-node (pop (%frame-remaining frame)) out open-elements)))
                    (when new-frame (push new-frame stack))))
                 (t
                  (close-write-frame frame out open-elements)
                  (pop stack)))))))

;;; HTML-TREE->STRING

(defun html-tree->string (tree)
  "Serialize TREE to an HTML string. TREE is a string; an element, meaning a
list whose first item is a keyword; or a list of strings and elements (NIL
is the empty list, so it serializes as \"\"). Adds no newlines or
indentation of its own: the output is TREE's plain concatenation. Signals
INVALID-HTML-TREE for a malformed TREE, naming the offending node or value.

Text and attribute values are entity-escaped, but URLs aren't checked: the
link policy applies only in AST->HTML-TREE. Memory, not the Lisp call
stack, bounds TREE's depth."
  (let ((open-elements (make-hash-table :test 'eq)))
    (with-output-to-string (out)
      (cond
        ((stringp tree) (write-escaped-string tree out))
        ((and (consp tree) (keywordp (first tree))) (write-nodes (list tree) out open-elements))
        ((proper-list-p tree) (write-nodes tree out open-elements))
        (t (invalid-tree tree "not a string, an element, or a list of nodes"))))))
