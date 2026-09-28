;;;; HTML-TREE->STRING: serializing an LHTML-shaped tree to a string (design §6).

(in-package #:cl-commonmark-gfm.html-tree)

;;; A local, circular-safe proper-list check (no other package's internals)

(defun proper-list-p (value)
  "True when VALUE is a finite, NIL-terminated (proper) list. Uses Floyd's
cycle detection, so a circular list is rejected rather than looping forever."
  (labels ((traverse (slow fast)
             (cond
               ((null fast) t)
               ((atom fast) nil)
               ((null (cdr fast)) t)
               ((atom (cdr fast)) nil)
               ((eql slow (cdr fast)) nil)
               (t (traverse (cdr slow) (cddr fast))))))
    (and (listp value)
         (or (null value)
             (traverse value (cdr value))))))

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
\"<tag />\" (design §6).")

(defparameter *bare-attribute-names* '("data-footnotes" "data-footnote-ref" "data-footnote-backref")
  "Lowercased attribute names that print with no value, as just \" name\",
when their value is \"\" (design §6). Every other attribute, including
DISABLED and CHECKED, prints \" name=\\\"\\\"\" for an empty value.")

(defparameter *url-attribute-names* '("href" "src" "id")
  "Lowercased attribute names whose values get the extra ' -> &#x27; escape
(design §6), mirroring cmark-gfm's houdini_escape_href. Every other attribute
(TITLE, ALT, ...) leaves ' raw, as houdini_escape_html0 does.")

;;; VOID-ELEMENT-P

(defun void-element-name-p (name-string)
  "True when NAME-STRING, an already-lowercased element name, is one of
*VOID-ELEMENT-NAMES* (design §6)."
  (and (member name-string *void-element-names* :test #'string=) t))

(defun void-element-p (keyword)
  "True when KEYWORD is a void element tag: :BR, :HR, :IMG or :INPUT, in any
keyword case or interning (design §6), classified by its LOWERCASE-NAME-STRING
rather than by keyword identity. A void element with children signals
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
[a-z][a-z0-9-]*, ASCII only (design §6). False for :*COMMENT* (the one tag
the serializer exempts from this rule) and for anything that isn't a
keyword."
  (and (keywordp keyword)
       (html-name-string-p (lowercase-name-string keyword))))

;;; Escaping (design §6, §2 finding 2)

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
lists (design §6's attrs shape, before NAME and VALUE are validated
individually)."
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

(defun check-no-repeated-attribute-names (attrs)
  "Signal INVALID-HTML-TREE when ATTRS (already ATTRS-SHAPE-P) repeats a
name, once every keyword name is lowercased."
  (let ((seen '()))
    (dolist (pair attrs)
      (let* ((name (first pair))
             (key (attribute-name-key name)))
        (when (member key seen :test #'equal)
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
attributes that print bare, as just \" name\", and VALUE is \"\" (design
§6)."
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
or ->, or ends with - (design §6)."
  (or (search "--" text)
      (string-starts-with-p ">" text)
      (string-starts-with-p "->" text)
      (and (plusp (length text)) (char= (char text (1- (length text))) #\-))))

(defun write-comment (element out)
  "Validate ELEMENT as an exact (:*COMMENT* NIL \"text\") comment (design
§6) and write it to OUT as <!--text-->, with TEXT escaped exactly as text
content -- &, <, >, \" but not ' -- since browsers do not parse comments
inside TEXTAREA, TITLE, SCRIPT or STYLE: raw comment text there could let
markup escape the comment. Signals INVALID-HTML-TREE for any other
shape, or for text that could end the comment early."
  (let ((text (check-comment-shape element)))
    (when (unsafe-comment-text-p text)
      (invalid-tree element "unsafe comment text"))
    (write-string "<!--" out)
    (write-escaped-string text out)
    (write-string "-->" out)))

;;; Elements

(defvar *element-ancestors* nil
  "The element conses currently being written, innermost first: the ancestor
path for the element HTML-TREE->STRING is writing right now. HTML-TREE->STRING
binds this fresh to NIL for each call; WRITE-ELEMENT pushes onto it around a
regular element's children and pops back off once they are written, so it
only ever holds elements whose own write call is still open. A tree that is a
DAG rather than a tree -- the same element cons reachable more than once, but
never through itself -- serializes normally: once an element's own write
finishes, it comes back off this list, so a later, unrelated sibling or
cousin reference to it does not look like an ancestor.")

(defun check-proper-element-list (element)
  "Signal INVALID-HTML-TREE unless ELEMENT is a proper list, guarding
against circular and dotted lists."
  (unless (proper-list-p element)
    (invalid-tree element "not a proper list")))

(defun check-not-self-referential (element)
  "Signal INVALID-HTML-TREE when ELEMENT is already on *ELEMENT-ANCESTORS*,
meaning ELEMENT's own write call is still open higher up the stack: ELEMENT
reaches itself through its children. Compared by EQ, an object-identity
check, so writing the same element object twice over -- never through
itself -- is unaffected; only actually re-entering the same cons trips it,
which is what makes a merely-shared acyclic subtree safe (design §6)."
  (when (member element *element-ancestors* :test #'eql)
    (invalid-tree element "element contains itself")))

(defun write-regular-element (element out)
  "Validate and write ELEMENT, a non-comment (TAG ATTRS . CHILDREN) list, to
OUT (design §6)."
  (let ((tag (first element))
        (attrs (second element))
        (children (cddr element)))
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
        (voidp (write-string " />" out))
        (t
         (write-char #\> out)
         (dolist (child children) (write-node child out))
         (write-string "</" out)
         (write-string tag-string out)
         (write-char #\> out))))))

(defun write-element (element out)
  "Validate and write ELEMENT — (:*COMMENT* NIL \"text\") or a regular
(TAG ATTRS . CHILDREN) list — to OUT (design §6). Signals INVALID-HTML-TREE
when a regular ELEMENT reaches itself through its own children, rather than
recursing until the stack is exhausted; a comment can never do this, since
its one permitted child is a string."
  (check-proper-element-list element)
  (cond
    ((eql (first element) :*comment*) (write-comment element out))
    (t
     (check-not-self-referential element)
     (let ((*element-ancestors* (cons element *element-ancestors*)))
       (write-regular-element element out)))))

;;; Nodes: a string or an element, used for children and top-level list items

(defun write-node (node out)
  "Write NODE, a string or an element, to OUT (design §6). Signals
INVALID-HTML-TREE when NODE is neither: a cons is tried as an element (so a
list whose first item isn't a keyword fails there), anything else -- a
number, NIL, a symbol -- fails directly."
  (cond
    ((stringp node) (write-escaped-string node out))
    ((consp node) (write-element node out))
    (t (invalid-tree node "not a string or an element"))))

;;; HTML-TREE->STRING

(defun html-tree->string (tree)
  "Serialize TREE to an HTML string (design §6). TREE is a string; an
element, meaning a list whose first item is a keyword; or a list of strings
and elements (NIL is the empty list, so it serializes as \"\"). Adds no
newlines or indentation of its own: the output is TREE's plain
concatenation. Signals INVALID-HTML-TREE for a malformed TREE, naming the
offending node or value."
  (let ((*element-ancestors* nil))
    (with-output-to-string (out)
      (cond
        ((stringp tree) (write-escaped-string tree out))
        ((and (consp tree) (keywordp (first tree))) (write-element tree out))
        ((proper-list-p tree) (dolist (node tree) (write-node node out)))
        (t (invalid-tree tree "not a string, an element, or a list of nodes"))))))
