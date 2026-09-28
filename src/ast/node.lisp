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

(defun node-attribute (node key)
  "Return the value of NODE's KEY attribute. Signals INVALID-AST-NODE when
NODE's kind has no such attribute."
  (let ((kind-spec (find-kind-spec (node-kind node))))
    (unless (and kind-spec (find-attribute-spec kind-spec key))
      (error 'invalid-ast-node
             :operation 'node-attribute
             :datum key
             :reason (format nil "~(~a~) node has no ~(~a~) attribute" (node-kind node) key)))
    (getf (%node-attributes node) key)))

;;; Sourcepos validation

(defun valid-position-p (value)
  "True when VALUE is a (LINE . COLUMN) cons of non-negative integers."
  (and (consp value)
       (typep (car value) '(integer 0))
       (typep (cdr value) '(integer 0))))

(defun valid-sourcepos-p (value)
  "True when VALUE is NIL or ((LINE . COLUMN) . (LINE . COLUMN)) of
non-negative integers. Inverted ranges are allowed."
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
                 :reason (format nil "~(~a~) has no ~(~a~) attribute" kind key)))
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

(defun children= (children-a children-b sourcepos)
  "Compare two children lists for NODE=, propagating SOURCEPOS down."
  (and (= (length children-a) (length children-b))
       (every (lambda (a b) (node= a b :sourcepos sourcepos)) children-a children-b)))

(defun node= (a b &key (sourcepos t))
  "True when nodes A and B have the same kind, attributes and children, and,
unless SOURCEPOS is NIL, the same source position at every depth."
  (and (eql (node-kind a) (node-kind b))
       (attributes= (%node-attributes a) (%node-attributes b))
       (or (not sourcepos) (equal (node-sourcepos a) (node-sourcepos b)))
       (children= (%node-children a) (%node-children b) sourcepos)))
