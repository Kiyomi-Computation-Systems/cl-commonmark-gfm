;;;; PARSE and the primary package (M2 design §3, §7.1, §7.2; ADR-0017):
;;;; what PARSE rejects, and in what order, before any native call; each
;;;; option reaching cmark; and the package's re-exports.

(in-package #:cl-commonmark-gfm.native-tests)

;;; What PARSE rejects before any native call (M2 design §7.1). The
;;; monotonic parser count shows that no parser was made.

(define-test parse-given-a-non-string-signals-a-type-error
  ;; Most of these would reach UTF8-LENGTH and signal a TYPE-ERROR there,
  ;; expecting a vector; the check names STRING for every one.
  (native-state)
  (let ((parsers (created-parsers)))
    (dolist (markdown (list 42 nil #\a :markdown (list "x") (vector #\x)))
      (let ((condition (fail (parse markdown) 'type-error "~S" markdown)))
        (when (typep condition 'type-error)
          (is eql markdown (type-error-datum condition) "the datum of ~S" markdown)
          (is eql 'string (type-error-expected-type condition) "the type expected of ~S"
              markdown))))
    (is = parsers (created-parsers) "no parser"))
  (true (open-counts-zero-p)))

(define-test option-errors-signal-invalid-parse-option-before-any-parser
  ;; PARSE signals INVALID-PARSE-OPTION for every option problem (M2 design
  ;; §7.2), including a render option it doesn't take.
  (native-state)
  (let ((parsers (created-parsers)))
    (dolist (options '((:bogus t)
                       (:smart)
                       (:profile :github)
                       (:extensions (:table :table))
                       (:extensions (:emoji))
                       (:extensions :table)
                       (:footnotes 1)
                       (:smart "yes")
                       (:sourcepos :yes)
                       (:softbreak :br)
                       (:unsafe-html t)
                       (:width 20)
                       (:smart t :smart 3)))
      (let ((condition (raised invalid-parse-option (apply #'parse "x" options)
                               "options ~S" options)))
        (when condition
          (is eql 'parse (condition-operation condition) "the operation for ~S" options))))
    (is = parsers (created-parsers) "no parser"))
  (true (open-counts-zero-p)))

(define-test parse-checks-its-argument-its-options-then-the-limits-before-starting-up
  ;; M2 design §7.1: the type, then the options, then the limits, then
  ;; startup. After a reset, none of these rejections starts cmark up.
  (with-startup-reset
    (let ((startups (native-startup-count)))
      (fail (parse 42 :bogus t) 'type-error "a non-string, with a bad option")
      (let ((*max-input-octets* 0))
        (raised invalid-parse-option (parse "x" :bogus t) "a bad option, past the limit")
        (raised resource-limit-exceeded (parse "x") "past the limit"))
      (false (native-state-published-p) "nothing started up")
      (is = startups (native-startup-count))
      (is eql :document (node-kind (parse "x")) "the next parse starts up")
      (is = (1+ startups) (native-startup-count))))
  (true (open-counts-zero-p)))

;;; Each option reaches cmark (M2 design §7.2): *OPTIONS-MARKDOWN* holds one
;;; of each thing an option turns on. Expected kinds from the pinned CLI's
;;; XML under the matching flags. Under :COMMONMARK, or without footnotes,
;;; [^n]: n is a link reference definition, and x[^n] a link to n.

(defparameter *options-markdown*
  (markdown-lines "~~s~~ x[^n] www.example.com"
                  ""
                  "[^n]: n"
                  ""
                  "| t |"
                  "|---|"
                  ""
                  "- [x] t")
  "A strikethrough, a footnote reference, an autolink, a table and a task
item.")

(defun option-kinds (&rest options)
  "Which of :STRIKETHROUGH, :FOOTNOTE-REFERENCE, :TABLE and :TASK-ITEM
*OPTIONS-MARKDOWN*'s AST holds under OPTIONS, in that order, then :AUTOLINK
when www.example.com became a link."
  (let* ((ast (apply #'parse *options-markdown* options))
         (kinds (mapcar #'node-kind (preorder-nodes ast))))
    (append (remove-if-not (lambda (kind) (member kind kinds))
                           '(:strikethrough :footnote-reference :table :task-item))
            (when (member "http://www.example.com" (ast-nodes-of-kind ast :link)
                          :key (lambda (link) (node-attribute link :destination))
                          :test #'string=)
              (list :autolink)))))

(define-test each-parse-option-reaches-cmark
  (is equal '(:strikethrough :footnote-reference :table :task-item :autolink) (option-kinds))
  (is equal '() (option-kinds :profile :commonmark))
  (is equal '(:footnote-reference) (option-kinds :profile :commonmark :footnotes t))
  (is equal '(:strikethrough :autolink)
      (option-kinds :profile :commonmark :extensions '(:autolink :strikethrough)))
  (is equal '(:footnote-reference :table :task-item) (option-kinds :extensions '(:tasklist :table)))
  (is equal '(:strikethrough :table :task-item :autolink) (option-kinds :footnotes nil))
  (is string= "“q” it’s" (text-of (parse "\"q\" it's" :smart t)) ":smart t")
  (is string= "\"q\" it's" (text-of (parse "\"q\" it's")) ":smart nil, the default"))

;;; The primary package (M2 design §3): one package for a caller, holding
;;; the public symbols of the conditions, the AST and the HTML tree, the
;;; four variables, and the entry points.

(defparameter *re-exported-packages*
  '("CL-COMMONMARK-GFM.CONDITIONS" "CL-COMMONMARK-GFM.AST" "CL-COMMONMARK-GFM.HTML-TREE")
  "The packages every exported symbol of which cl-commonmark-gfm exports.")

(defun re-exported-variables ()
  "The four variables of native-core that cl-commonmark-gfm exports."
  (mapcar (lambda (name) (find-symbol name "CL-COMMONMARK-GFM.NATIVE-CORE"))
          '("*MAX-INPUT-OCTETS*" "*MAX-NODES*" "*MAX-OUTPUT-OCTETS*" "*CMARK-GFM-LIBRARIES*")))

(defun re-exported-symbols ()
  "Every symbol cl-commonmark-gfm must export from elsewhere."
  (let ((symbols (copy-list (re-exported-variables))))
    (dolist (package *re-exported-packages* symbols)
      (do-external-symbols (symbol package)
        (push symbol symbols)))))

(defun external-p (symbol package)
  "True when SYMBOL itself, not merely one of its name, is external in
PACKAGE."
  (multiple-value-bind (found status) (find-symbol (symbol-name symbol) package)
    (and (eql found symbol) (eql status :external))))

(defun missing-re-exports ()
  "Each symbol of RE-EXPORTED-SYMBOLS that isn't external in
cl-commonmark-gfm."
  (remove-if (lambda (symbol) (external-p symbol "CL-COMMONMARK-GFM")) (re-exported-symbols)))

(defparameter *entry-point-names*
  '("PARSE" "MARKDOWN->HTML" "MARKDOWN->PLAINTEXT" "MARKDOWN->HTML-TREE")
  "The names of the four entry points (M2 design §7.1), the only symbols of
its own cl-commonmark-gfm may export.")

(defun stray-exports ()
  "Each symbol cl-commonmark-gfm exports that is neither one of
RE-EXPORTED-SYMBOLS nor one of its own entry points: an internal of
native-core, /native or /util, say, or one of its own helpers."
  (let ((own (find-package "CL-COMMONMARK-GFM"))
        (re-exported (re-exported-symbols))
        (strays '()))
    (do-external-symbols (symbol own strays)
      (unless (or (member symbol re-exported)
                  (and (eql (symbol-package symbol) own)
                       (member (symbol-name symbol) *entry-point-names* :test #'string=)))
        (push symbol strays)))))

(define-test the-primary-package-re-exports-the-public-symbols
  (false (member nil (re-exported-variables)) "native-core has the four variables")
  (true (member 'node= (re-exported-symbols)) "the AST's symbols are among them")
  (true (member 'resource-limit-exceeded (re-exported-symbols)) "and the conditions'")
  (true (member 'cl-commonmark-gfm.html-tree:html-tree->string (re-exported-symbols))
        "and the HTML tree's")
  (is equal '() (missing-re-exports))
  (is equal '() (stray-exports))
  (true (external-p 'parse "CL-COMMONMARK-GFM"))
  (is eql (find-package "CL-COMMONMARK-GFM") (symbol-package 'parse)))
