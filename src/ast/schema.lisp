;;;; Per-kind AST node schema: attribute types, defaults and leaf status.

(in-package #:cl-commonmark-gfm.ast)

;;; General-purpose predicates shared by the schema and by node construction

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

(defun strict-boolean-p (value)
  "True when VALUE is exactly T or NIL: the schema's \"boolean\" type."
  (or (eql value t) (null value)))

(defun keyword-list-p (value)
  "True when VALUE is a proper list of keywords: the schema's \"list of
keywords\" type."
  (and (proper-list-p value) (every #'keywordp value)))

(defun non-empty-string-p (value)
  "True when VALUE is a string with at least one character: the schema's
label type."
  (and (stringp value) (plusp (length value))))

(defun levelp (value)
  "True when VALUE is a heading level, an integer from 1 to 6."
  (typep value '(integer 1 6)))

(defun start-value-p (value)
  "True when VALUE is a valid list :START: NIL or a non-negative integer."
  (or (null value) (typep value '(integer 0))))

(defun optional-string-p (value)
  "True when VALUE is a string or NIL: the :EXTENSION-NAME type."
  (or (null value) (stringp value)))

;;; Attribute and kind specifications

(defstruct (attribute-spec
             (:constructor make-attribute-spec (key type-predicate default requiredp))
             (:copier nil))
  "The schema row for one attribute: its KEY, the TYPE-PREDICATE its value
must satisfy, and either a DEFAULT or REQUIREDP."
  key
  type-predicate
  default
  requiredp)

(defstruct (kind-spec
             (:constructor make-kind-spec (leafp attributes))
             (:copier nil))
  "The schema row for one node kind: whether it is a LEAFP kind, and its
ATTRIBUTES, an ATTRIBUTE-SPEC list in canonical order."
  leafp
  attributes)

(defun find-attribute-spec (kind-spec key)
  "Return KEY's ATTRIBUTE-SPEC in KIND-SPEC, or NIL when KIND-SPEC has no
such attribute."
  (find key (kind-spec-attributes kind-spec) :key #'attribute-spec-key :test #'eql))

;;; The schema table (design spec Sec 4.2)

(defparameter *schema*
  (let ((table (make-hash-table :test 'eql)))
    (flet ((kind (name leafp &rest attributes)
             (setf (gethash name table) (make-kind-spec leafp attributes))))
      (kind :document nil
            (make-attribute-spec :profile
                                  (lambda (v) (member v '(nil :gfm :commonmark)))
                                  nil nil)
            (make-attribute-spec :extensions #'keyword-list-p nil nil)
            (make-attribute-spec :options #'keyword-list-p nil nil))
      (dolist (name '(:block-quote :item :paragraph :table :table-header
                      :table-row :emph :strong :strikethrough))
        (kind name nil))
      (kind :list nil
            (make-attribute-spec :type
                                  (lambda (v) (member v '(:bullet :ordered)))
                                  :bullet nil)
            (make-attribute-spec :start #'start-value-p nil nil)
            (make-attribute-spec :delimiter
                                  (lambda (v) (member v '(nil :period :paren)))
                                  nil nil)
            (make-attribute-spec :tight #'strict-boolean-p nil nil))
      (kind :task-item nil
            (make-attribute-spec :checked #'strict-boolean-p nil nil))
      (kind :code-block t
            (make-attribute-spec :info #'stringp "" nil)
            (make-attribute-spec :literal #'stringp "" nil))
      (dolist (name '(:html-block :html-inline :text :code))
        (kind name t (make-attribute-spec :literal #'stringp "" nil)))
      (kind :heading nil
            (make-attribute-spec :level #'levelp nil t))
      (dolist (name '(:thematic-break :softbreak :linebreak))
        (kind name t))
      (kind :footnote-definition nil
            (make-attribute-spec :label #'non-empty-string-p nil t))
      (kind :footnote-reference t
            (make-attribute-spec :label #'non-empty-string-p nil t))
      (kind :table-cell nil
            (make-attribute-spec :align
                                  (lambda (v) (member v '(nil :left :center :right)))
                                  nil nil))
      (dolist (name '(:link :image))
        (kind name nil
              (make-attribute-spec :destination #'stringp "" nil)
              (make-attribute-spec :title #'stringp "" nil)))
      (kind :extension nil
            (make-attribute-spec :extension-name #'optional-string-p nil nil)
            (make-attribute-spec :type-name #'stringp nil t)))
    table)
  "One row per vocabulary kind (design Sec 4.2), keyed by kind keyword.")

(defun find-kind-spec (kind)
  "Return KIND's KIND-SPEC, or NIL when KIND is not in the schema."
  (gethash kind *schema*))
