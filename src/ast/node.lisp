;;;; The NODE struct and its schema-checked constructors, MAKE-NODE and COPY-NODE.

(in-package #:cl-commonmark-gfm.ast)

;;; The struct

(defstruct (node
             (:constructor %make-node)
             (:copier nil)
             (:conc-name %node-))
  "An immutable CommonMark/GFM AST node. Built and validated only through
MAKE-NODE and COPY-NODE: never call %MAKE-NODE directly."
  (kind nil :read-only t)
  (attributes nil :read-only t)
  (children nil :read-only t)
  (sourcepos nil :read-only t))

(setf (documentation 'node-p 'function)
      "True when OBJECT is a NODE.")

;;; Public queries

(defun node-kind (node)
  "Return NODE's kind keyword."
  (%node-kind node))

(defun node-attributes (node)
  "Return a fresh copy of NODE's canonical attribute plist."
  (copy-list (%node-attributes node)))

(defun node-children (node)
  "Return a fresh copy of NODE's list of child nodes, like NODE-ATTRIBUTES,
so a destructive operation on the result (e.g. SORT) cannot corrupt NODE."
  (copy-list (%node-children node)))

(defun node-sourcepos (node)
  "Return NODE's source position, or NIL when it has none."
  (%node-sourcepos node))

(defun bounded-key-string (key)
  "KEY as a reason string names it: printed with ~(~A~), under the bounds
src/conditions.lisp's report uses (*PRINT-CIRCLE* T, *PRINT-LENGTH* 10,
*PRINT-LEVEL* 4, *PRINT-READABLY* NIL). The report's own bindings come too
late, since the reason is formatted when the condition is signalled. A
keyword prints in full. A caller's circular or deeply nested KEY prints cut
short instead of hanging or exhausting memory; so does a long or shared
one."
  (let ((*print-circle* t)
        (*print-length* 10)
        (*print-level* 4)
        (*print-readably* nil))
    (format nil "~(~a~)" key)))

(defun node-attribute (node key)
  "Return the value of NODE's KEY attribute. Signals INVALID-AST-NODE when
NODE's kind has no such attribute."
  (let ((kind-spec (find-kind-spec (node-kind node))))
    (unless (and kind-spec (find-attribute-spec kind-spec key))
      (error 'invalid-ast-node
             :operation 'node-attribute
             :datum key
             :reason (format nil "~(~a~) node has no ~a attribute"
                             (node-kind node) (bounded-key-string key))))
    (getf (%node-attributes node) key)))

;;; Sourcepos validation

(defun valid-position-p (value)
  "True when VALUE is a (LINE . COLUMN) cons of integers. cmark has been
seen to report a negative start column: a table's rebuilt paragraph has no
position of its own (try_inserting_table_header_paragraph,
vendor/cmark-gfm/extensions/table.c), so an inline inside it gets a
position computed from a missing origin, and an autolink at the start of
a line gets column -1. No negative line or end position has been seen.
The AST keeps positions as cmark reports them, never repaired, so it
accepts any integer in either slot: rejecting a negative one would make
PARSE fail on valid Markdown."
  (and (consp value)
       (integerp (car value))
       (integerp (cdr value))))

(defun valid-sourcepos-p (value)
  "True when VALUE is NIL or ((LINE . COLUMN) . (LINE . COLUMN)) of
integers: the AST accepts any integer in all four slots, as cmark reports
them (see VALID-POSITION-P). Inverted ranges are allowed: cmark reports
some, such as 23:1-22:0 for an HTML block."
  (or (null value)
      (and (consp value)
           (valid-position-p (car value))
           (valid-position-p (cdr value)))))

(defun check-sourcepos (sourcepos operation)
  "Signal INVALID-AST-NODE for OPERATION unless SOURCEPOS is well-formed."
  (unless (valid-sourcepos-p sourcepos)
    (error 'invalid-ast-node :operation operation :datum sourcepos
           :reason "malformed sourcepos")))

;;; Attribute plist handling shared by MAKE-NODE and COPY-NODE

(defun plist-pairs (plist operation)
  "Return PLIST's (KEY . VALUE) pairs, in PLIST's order. Signals
INVALID-AST-NODE for OPERATION when PLIST is not a proper list of even
length."
  (unless (and (proper-list-p plist) (evenp (length plist)))
    (error 'invalid-ast-node :operation operation :datum plist
           :reason "attributes must be a proper plist of even length"))
  (loop for (key value) on plist by #'cddr collect (cons key value)))

(defun check-known-attributes (pairs kind-spec kind operation)
  "Signal INVALID-AST-NODE for OPERATION when PAIRS (as PLIST-PAIRS returns)
names a key that KIND-SPEC lacks, or repeats a key."
  (let ((seen '()))
    (dolist (pair pairs)
      (let ((key (car pair)))
        (unless (find-attribute-spec kind-spec key)
          (error 'invalid-ast-node :operation operation :datum key
                 :reason (format nil "~(~a~) has no ~a attribute" kind (bounded-key-string key))))
        (when (member key seen :test #'eql)
          (error 'invalid-ast-node :operation operation :datum key
                 :reason "repeated attribute key"))
        (push key seen)))))

(defun check-attribute-types (pairs kind-spec operation)
  "Signal INVALID-AST-NODE for OPERATION when a value in PAIRS fails its
key's type predicate in KIND-SPEC."
  (dolist (pair pairs)
    (let* ((key (car pair))
           (value (cdr pair))
           (spec (find-attribute-spec kind-spec key)))
      (unless (funcall (attribute-spec-type-predicate spec) value)
        (error 'invalid-ast-node :operation operation :datum (cons key value)
               :reason (format nil "~(~a~) has the wrong type" key))))))

(defun canonicalize-attributes (pairs kind-spec operation)
  "Build the canonical attribute plist for KIND-SPEC from PAIRS: every key,
in schema order, using PAIRS's value or the key's default. Signals
INVALID-AST-NODE for OPERATION when a required key is absent from PAIRS."
  (loop for spec in (kind-spec-attributes kind-spec)
        for key = (attribute-spec-key spec)
        for pair = (assoc key pairs :test #'eql)
        append (list key
                     (cond
                       (pair (cdr pair))
                       ((attribute-spec-requiredp spec)
                        (error 'invalid-ast-node :operation operation :datum key
                               :reason (format nil "missing required ~(~a~) attribute" key)))
                       (t (attribute-spec-default spec))))))

(defun merge-attributes (node pairs kind-spec)
  "Return NODE's canonical attributes with PAIRS's (KEY . VALUE) overrides
applied, still in schema order."
  (loop for spec in (kind-spec-attributes kind-spec)
        for key = (attribute-spec-key spec)
        for pair = (assoc key pairs :test #'eql)
        append (list key (if pair (cdr pair) (getf (%node-attributes node) key)))))

(defun check-list-cross-field-rule (attributes operation)
  "Enforce the one cross-field rule: an :ORDERED :LIST needs an integer
:START and a non-NIL :DELIMITER; a :BULLET :LIST has neither."
  (let ((type (getf attributes :type))
        (start (getf attributes :start))
        (delimiter (getf attributes :delimiter)))
    (ecase type
      (:ordered
       (unless (and (integerp start) delimiter)
         (error 'invalid-ast-node :operation operation :datum attributes
                :reason ":ordered list needs an integer :start and a non-nil :delimiter")))
      (:bullet
       (when (or start delimiter)
         (error 'invalid-ast-node :operation operation :datum attributes
                :reason ":bullet list must have neither :start nor :delimiter"))))))

(defun check-children (children kind-spec operation)
  "Signal INVALID-AST-NODE for OPERATION when CHILDREN is not a proper list
of nodes, or is non-empty for a leaf kind."
  (unless (proper-list-p children)
    (error 'invalid-ast-node :operation operation :datum children
           :reason "children must be a proper list"))
  (when (and (kind-spec-leafp kind-spec) children)
    (error 'invalid-ast-node :operation operation :datum children
           :reason "a leaf node cannot have children"))
  (dolist (child children)
    (unless (node-p child)
      (error 'invalid-ast-node :operation operation :datum child
             :reason "a child must be a node"))))

(defun require-kind-spec (kind operation)
  "Return KIND's KIND-SPEC. Signals INVALID-AST-NODE for OPERATION when KIND
is not in the schema."
  (or (find-kind-spec kind)
      (error 'invalid-ast-node :operation operation :datum kind :reason "unknown kind")))

;;; MAKE-NODE

(defun make-node (kind &key attributes children sourcepos)
  "Build and validate a NODE of KIND. ATTRIBUTES is a plist; any key KIND's
schema does not require takes its default when ATTRIBUTES omits it. CHILDREN
is a list of nodes, and must be empty when KIND is a leaf kind; MAKE-NODE
stores a copy of it, so mutating the list you passed afterwards does not
change the node. SOURCEPOS is NIL or a source range. Signals INVALID-AST-NODE
for any schema violation."
  (let* ((kind-spec (require-kind-spec kind 'make-node))
         (pairs (plist-pairs attributes 'make-node)))
    (check-known-attributes pairs kind-spec kind 'make-node)
    (check-attribute-types pairs kind-spec 'make-node)
    (let ((canonical (canonicalize-attributes pairs kind-spec 'make-node)))
      (when (eql kind :list)
        (check-list-cross-field-rule canonical 'make-node))
      (check-children children kind-spec 'make-node)
      (check-sourcepos sourcepos 'make-node)
      (%make-node :kind kind :attributes canonical :children (copy-list children)
                  :sourcepos sourcepos))))

;;; COPY-NODE

(defun copy-node (node &key attributes
                          (children nil children-supplied-p)
                          (sourcepos nil sourcepos-supplied-p))
  "Return a new node like NODE, with ATTRIBUTES merged over its own, and
CHILDREN or SOURCEPOS replaced only when supplied (so :SOURCEPOS NIL clears
it). A supplied CHILDREN is copied, as MAKE-NODE copies it, so mutating the
list you passed afterwards does not change the node. There is no way to
change NODE's kind. Validates the result exactly as MAKE-NODE would."
  (let* ((kind (node-kind node))
         (kind-spec (require-kind-spec kind 'copy-node))
         (pairs (plist-pairs attributes 'copy-node)))
    (check-known-attributes pairs kind-spec kind 'copy-node)
    (check-attribute-types pairs kind-spec 'copy-node)
    (let ((canonical (merge-attributes node pairs kind-spec))
          ;; The children to validate, still uncopied: CHILDREN as supplied,
          ;; or NODE's own (already-valid) children otherwise.
          (old-children (if children-supplied-p children (%node-children node)))
          (new-sourcepos (if sourcepos-supplied-p sourcepos (%node-sourcepos node))))
      (when (eql kind :list)
        (check-list-cross-field-rule canonical 'copy-node))
      ;; Validate before copying, as MAKE-NODE does: COPY-LIST on a bad
      ;; CHILDREN argument (a non-list, or one with a cycle) must never run
      ;; before CHECK-CHILDREN has had a chance to reject it.
      (check-children old-children kind-spec 'copy-node)
      (check-sourcepos new-sourcepos 'copy-node)
      (%make-node :kind kind :attributes canonical
                  :children (if children-supplied-p (copy-list children) old-children)
                  :sourcepos new-sourcepos))))

;;; Structural equality

(defun attribute-value= (a b)
  "Compare two attribute values for NODE=. EQUAL compares strings
case-sensitively (never EQUALP) and keyword lists by contents."
  (equal a b))

(defun attributes= (plist-a plist-b)
  "Compare two canonical attribute plists for NODE=, key by key."
  (and (= (length plist-a) (length plist-b))
       (loop for (key value) on plist-a by #'cddr
             always (attribute-value= value (getf plist-b key)))))

(defun shallow-node= (x y sourcepos)
  "True when nodes X and Y have the same kind and attributes, and, unless
SOURCEPOS is NIL, the same source position: every part of NODE='s comparison
except children, which NODE= walks separately."
  (and (eql (node-kind x) (node-kind y))
       (attributes= (%node-attributes x) (%node-attributes y))
       (or (not sourcepos) (equal (node-sourcepos x) (node-sourcepos y)))))

(defun node= (a b &key (sourcepos t))
  "True when nodes A and B have the same kind, attributes and children, and,
unless SOURCEPOS is NIL, the same source position at every depth. Signals a
TYPE-ERROR, via CHECK-TYPE, when A or B is not a NODE -- A is checked first,
so its datum is the one named when both are bad.

Loops over an explicit stack of (A . B) node pairs instead of recursing into
children, so depth is bounded by memory rather than by the Lisp call stack.
A pair of EQL nodes is equal without being descended into."
  (check-type a node)
  (check-type b node)
  (let ((stack (list (cons a b))))
    (loop while stack
          do (let* ((pair (pop stack))
                    (x (car pair))
                    (y (cdr pair)))
               (unless (eql x y)
                 (unless (shallow-node= x y sourcepos)
                   (return-from node= nil))
                 (let ((children-x (%node-children x))
                       (children-y (%node-children y)))
                   (unless (= (length children-x) (length children-y))
                     (return-from node= nil))
                   (loop for cx in children-x
                         for cy in children-y
                         do (push (cons cx cy) stack)))))
          finally (return t))))
