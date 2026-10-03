;;;; Tests for cl-commonmark-gfm.native-core: the header constants (M2
;;;; design §8.1), CLASSIFY-NODE (§6.2; ADR-0008 "Node classification") and
;;;; RESOLVE-CMARK-LIBRARIES (ADR-0009).

(in-package #:cl-commonmark-gfm.tests)

;;; A tiny, test-only evaluator for vendor/cmark-gfm/src/cmark-gfm.h's
;;; #defines and enums: hex and decimal literals, | and <<, parentheses,
;;; names defined earlier, and a plain enum's implicit values (M2b plan,
;;; Task 2). It is independent of src/native-core/constants.lisp -- it
;;; shares no code with the file it checks -- so a transcription slip there
;;; cannot also slip in here.

(defun identifier-char-p (char)
  "True when CHAR may appear in a C identifier: alphanumeric or underscore."
  (or (alphanumericp char) (char= char #\_)))

(defun split-on-char (string char)
  "STRING split at every occurrence of CHAR, CHAR itself dropped."
  (let ((parts '()) (start 0) (length (length string)))
    (loop
      (let ((next (position char string :start start)))
        (push (subseq string start (or next length)) parts)
        (if next (setf start (1+ next)) (return))))
    (nreverse parts)))

(defun blank-string-p (string)
  "True when STRING holds only spaces, tabs and carriage returns."
  (every (lambda (char) (member char '(#\Space #\Tab #\Return))) string))

;;; Tokenizing and parsing a C integer-constant expression

(defun read-c-integer (string position)
  "Read a C integer literal (0x hex, or decimal) from STRING starting at
POSITION. Returns (VALUES VALUE NEXT-POSITION)."
  (let ((length (length string)))
    (if (and (char= (char string position) #\0)
             (< (1+ position) length)
             (member (char string (1+ position)) '(#\x #\X)))
        (let ((end (or (position-if-not (lambda (c) (digit-char-p c 16)) string
                                         :start (+ position 2))
                       length)))
          (values (parse-integer string :start (+ position 2) :end end :radix 16) end))
        (let ((end (or (position-if-not #'digit-char-p string :start position) length)))
          (values (parse-integer string :start position :end end) end)))))

(defun tokenize-c-expression (string)
  "Tokenize STRING into a list of tokens: (:NUMBER N), (:IDENT \"NAME\"),
:PIPE, :SHIFT, :LPAREN or :RPAREN. STRING is a C integer-constant expression
using only hex and decimal literals, identifiers, | and <<, and
parentheses: everything cmark-gfm.h's constants ever need."
  (let ((tokens '())
        (position 0)
        (length (length string)))
    (loop while (< position length)
          do (let ((char (char string position)))
               (cond
                 ((member char '(#\Space #\Tab #\Newline #\Return))
                  (incf position))
                 ((char= char #\() (push :lparen tokens) (incf position))
                 ((char= char #\)) (push :rparen tokens) (incf position))
                 ((char= char #\|) (push :pipe tokens) (incf position))
                 ((and (char= char #\<) (< (1+ position) length)
                       (char= (char string (1+ position)) #\<))
                  (push :shift tokens)
                  (incf position 2))
                 ((digit-char-p char)
                  (multiple-value-bind (value next) (read-c-integer string position)
                    (push (list :number value) tokens)
                    (setf position next)))
                 ((identifier-char-p char)
                  (let ((end (or (position-if-not #'identifier-char-p string :start position)
                                 length)))
                    (push (list :ident (subseq string position end)) tokens)
                    (setf position end)))
                 (t (error "unexpected character ~S in C expression ~S" char string)))))
    (nreverse tokens)))

(defun parse-c-atom (tokens environment)
  "Parse one atom -- a number, an identifier looked up in ENVIRONMENT (an
alist of (\"NAME\" . VALUE)), or a parenthesized expression -- from the
front of TOKENS. Returns (VALUES VALUE REMAINING-TOKENS)."
  (let ((token (first tokens)))
    (cond
      ((eql token :lparen)
       (multiple-value-bind (value remaining) (parse-c-expression (rest tokens) environment)
         (unless (eql (first remaining) :rparen)
           (error "expected ) in C expression"))
         (values value (rest remaining))))
      ((and (consp token) (eql (first token) :number))
       (values (second token) (rest tokens)))
      ((and (consp token) (eql (first token) :ident))
       (let ((binding (assoc (second token) environment :test #'string=)))
         (unless binding
           (error "undefined identifier ~S in a C expression" (second token)))
         (values (cdr binding) (rest tokens))))
      (t (error "unexpected token ~S in a C expression" token)))))

(defun parse-c-term (tokens environment)
  "Parse ATOM (<< ATOM)*: C's precedence puts << tighter than |."
  (multiple-value-bind (value tokens) (parse-c-atom tokens environment)
    (loop while (eql (first tokens) :shift)
          do (multiple-value-bind (next-value remaining) (parse-c-atom (rest tokens) environment)
               (setf value (ash value next-value)
                     tokens remaining)))
    (values value tokens)))

(defun parse-c-expression (tokens environment)
  "Parse TERM (| TERM)*. Returns (VALUES VALUE REMAINING-TOKENS)."
  (multiple-value-bind (value tokens) (parse-c-term tokens environment)
    (loop while (eql (first tokens) :pipe)
          do (multiple-value-bind (next-value remaining) (parse-c-term (rest tokens) environment)
               (setf value (logior value next-value)
                     tokens remaining)))
    (values value tokens)))

(defun evaluate-c-expression (string environment)
  "Evaluate STRING, a C integer-constant expression, with identifiers looked
up in ENVIRONMENT."
  (multiple-value-bind (value remaining)
      (parse-c-expression (tokenize-c-expression string) environment)
    (when remaining
      (error "trailing tokens ~S after a C expression ~S" remaining string))
    value))

;;; Reading #defines and enums out of the header text

(defun header-define-name-and-value (line)
  "LINE, if it is an object-like #define with a value, as (VALUES NAME
VALUE-STRING); two NILs otherwise. Skips a header guard (#define FOO alone)
and a function-like macro (#define FOO(...), ( right after the name):
cmark-gfm.h never defines a constant this library needs either way."
  (let ((trimmed (string-left-trim '(#\Space #\Tab) line)))
    (if (and (>= (length trimmed) 7) (string= trimmed "#define" :end1 7)
             (or (= (length trimmed) 7) (member (char trimmed 7) '(#\Space #\Tab))))
        (let* ((rest (string-left-trim '(#\Space #\Tab) (subseq trimmed 7)))
               (name-end (or (position-if-not #'identifier-char-p rest) (length rest))))
          (if (and (plusp name-end)
                   (not (and (< name-end (length rest)) (char= (char rest name-end) #\())))
              (let* ((name (subseq rest 0 name-end))
                     (value (string-trim '(#\Space #\Tab) (subseq rest name-end))))
                (if (blank-string-p value) (values nil nil) (values name value)))
              (values nil nil)))
        (values nil nil))))

(defun header-defines (text)
  "An alist of (NAME . VALUE-STRING) for every object-like #define in TEXT
that has a value, in the order they appear."
  (let ((result '()))
    (dolist (line (split-on-char text #\Newline) (nreverse result))
      (multiple-value-bind (name value) (header-define-name-and-value line)
        (when name
          (push (cons name value) result))))))

(defun lookup-define (name defines)
  "VALUE-STRING bound to NAME in DEFINES, or an error naming NAME."
  (let ((binding (assoc name defines :test #'string=)))
    (unless binding
      (error "no #define ~A found in cmark-gfm.h" name))
    (cdr binding)))

(defun strip-c-comments (string)
  "STRING with every /* ... */ comment removed."
  (with-output-to-string (out)
    (let ((position 0) (length (length string)))
      (loop while (< position length)
            do (let ((comment-start (search "/*" string :start2 position)))
                 (cond
                   ((null comment-start)
                    (write-string string out :start position)
                    (setf position length))
                   (t
                    (write-string string out :start position :end comment-start)
                    (let ((comment-end (search "*/" string :start2 (+ comment-start 2))))
                      (unless comment-end
                        (error "unterminated comment in a C enum body"))
                      (setf position (+ comment-end 2))))))))))

(defun enum-entries (body)
  "BODY, an enum's text between { and }, as a list of trimmed, comment-free,
non-blank entries, split at each comma."
  (remove-if (lambda (entry) (zerop (length entry)))
             (mapcar (lambda (entry) (string-trim '(#\Space #\Tab #\Newline #\Return) entry))
                     (split-on-char (strip-c-comments body) #\,))))

(defun parse-enum-entry (entry)
  "ENTRY, one trimmed enum entry, as (VALUES NAME VALUE-STRING) --
VALUE-STRING NIL when ENTRY has no =, an implicit value."
  (let ((equals (position #\= entry)))
    (if equals
        (values (string-trim '(#\Space #\Tab) (subseq entry 0 equals))
                (string-trim '(#\Space #\Tab) (subseq entry (1+ equals))))
        (values (string-trim '(#\Space #\Tab) entry) nil))))

(defun evaluate-enum (body environment)
  "BODY, an enum's text between { and }, evaluated under ENVIRONMENT: an
alist of every enumerator's name and value, in order. An entry with no =
gets one more than the previous entry's value, or 0 for the first (C's rule
for a plain enum)."
  (let ((previous -1)
        (result '()))
    (dolist (entry (enum-entries body) (nreverse result))
      (multiple-value-bind (name value-string) (parse-enum-entry entry)
        (let ((value (if value-string
                         (evaluate-c-expression value-string (append result environment))
                         (1+ previous))))
          (setf previous value)
          (push (cons name value) result))))))

(defun find-enum-body (text type-name)
  "The text between { and } of TEXT's `typedef enum { ... } TYPE-NAME;`."
  (let* ((marker (format nil "} ~A;" type-name))
         (end (search marker text)))
    (unless end
      (error "no enum ~A found in cmark-gfm.h" type-name))
    (let ((open (position #\{ text :from-end t :end end)))
      (unless open
        (error "no { found before ~A in cmark-gfm.h" marker))
      (subseq text (1+ open) end))))

;;; The pinned header, evaluated independently of constants.lisp

(defparameter *header-path*
  (asdf:system-relative-pathname "cl-commonmark-gfm/tests" "vendor/cmark-gfm/src/cmark-gfm.h")
  "The pinned header CLASSIFY-NODE's and the option bits' constants are
transcribed from (ADR-0008, ADR-0009, M2 design §8.1).")

(defparameter *header-text* (uiop:read-file-string *header-path* :external-format :utf-8)
  "The pinned cmark-gfm.h, as text.")

(defparameter *header-defines* (header-defines *header-text*)
  "Every object-like #define of *HEADER-TEXT* that has a value, as
(NAME . VALUE-STRING).")

(defparameter *header-node-type-tags*
  (let ((environment '()))
    (dolist (name '("CMARK_NODE_TYPE_PRESENT" "CMARK_NODE_TYPE_BLOCK" "CMARK_NODE_TYPE_INLINE")
             environment)
      (push (cons name (evaluate-c-expression (lookup-define name *header-defines*) environment))
            environment)))
  "CMARK_NODE_TYPE_PRESENT, CMARK_NODE_TYPE_BLOCK and CMARK_NODE_TYPE_INLINE
(cmark-gfm.h lines 34-36), the three names cmark_node_type's enumerators are
built from.")

(defparameter *header-node-type-enum*
  (evaluate-enum (find-enum-body *header-text* "cmark_node_type") *header-node-type-tags*)
  "Every cmark_node_type enumerator, name and value, read off the pinned
header independently of src/native-core/constants.lisp.")

(defparameter *header-list-type-enum*
  (evaluate-enum (find-enum-body *header-text* "cmark_list_type") '())
  "CMARK_NO_LIST, CMARK_BULLET_LIST and CMARK_ORDERED_LIST, by their
implicit values 0, 1 and 2.")

(defparameter *header-delim-type-enum*
  (evaluate-enum (find-enum-body *header-text* "cmark_delim_type") '())
  "CMARK_NO_DELIM, CMARK_PERIOD_DELIM and CMARK_PAREN_DELIM, by their
implicit values 0, 1 and 2.")

(defparameter *header-option-names*
  '("CMARK_OPT_SOURCEPOS" "CMARK_OPT_HARDBREAKS" "CMARK_OPT_NOBREAKS"
    "CMARK_OPT_VALIDATE_UTF8" "CMARK_OPT_SMART" "CMARK_OPT_FOOTNOTES" "CMARK_OPT_UNSAFE")
  "The seven CMARK_OPT_ names this library transcribes (M2 design §7.3).")

(defparameter *header-options*
  (mapcar (lambda (name)
            (cons name (evaluate-c-expression (lookup-define name *header-defines*) '())))
          *header-option-names*)
  "The seven option bits, read off the pinned header.")

(defparameter *header-environment*
  (append *header-node-type-enum* *header-list-type-enum* *header-delim-type-enum*
          *header-options*)
  "Every header value this test suite knows how to derive, by C name:
CMARK-HEADER-CONSTANTS-MATCH-THE-PINNED-HEADER checks *CMARK-HEADER-CONSTANTS*
against this.")

;;; Header constant tests (M2 design §8.1)

(define-test cmark-header-constants-match-the-pinned-header
  (dolist (pair *cmark-header-constants*)
    (destructuring-bind (name . value) pair
      (let ((binding (assoc name *header-environment* :test #'string=)))
        (true binding "no header value was found for ~A" name)
        (when binding
          (is = (cdr binding) value "~A: header ~A, library ~A" name (cdr binding) value))))))

(define-test every-node-type-enumerator-but-none-has-a-header-constant
  (dolist (pair *header-node-type-enum*)
    (let ((name (car pair)))
      (unless (string= name "CMARK_NODE_NONE")
        (true (assoc name *cmark-header-constants* :test #'string=)
              "~A has no entry in *CMARK-HEADER-CONSTANTS*" name))))
  ;; MATCH, above, only checks that every entry already in
  ;; *CMARK-HEADER-CONSTANTS* has the right value: it never notices a whole
  ;; entry missing. This completeness check does, for the seven CMARK_OPT_
  ;; names this library transcribes and every cmark_list_type and
  ;; cmark_delim_type enumerator but the two "no value" sentinels.
  (dolist (name *header-option-names*)
    (true (assoc name *cmark-header-constants* :test #'string=)
          "~A has no entry in *CMARK-HEADER-CONSTANTS*" name))
  (dolist (pair (append *header-list-type-enum* *header-delim-type-enum*))
    (let ((name (car pair)))
      (unless (member name '("CMARK_NO_LIST" "CMARK_NO_DELIM") :test #'string=)
        (true (assoc name *cmark-header-constants* :test #'string=)
              "~A has no entry in *CMARK-HEADER-CONSTANTS*" name)))))

;;; CLASSIFY-NODE (M2 design §6.2; ADR-0008 "Node classification")

(defparameter *core-type-code-kinds*
  (list (cons +cmark-node-document+ :document)
        (cons +cmark-node-block-quote+ :block-quote)
        (cons +cmark-node-list+ :list)
        (cons +cmark-node-item+ :item)
        (cons +cmark-node-code-block+ :code-block)
        (cons +cmark-node-html-block+ :html-block)
        (cons +cmark-node-paragraph+ :paragraph)
        (cons +cmark-node-heading+ :heading)
        (cons +cmark-node-thematic-break+ :thematic-break)
        (cons +cmark-node-footnote-definition+ :footnote-definition)
        (cons +cmark-node-text+ :text)
        (cons +cmark-node-softbreak+ :softbreak)
        (cons +cmark-node-linebreak+ :linebreak)
        (cons +cmark-node-code+ :code)
        (cons +cmark-node-html-inline+ :html-inline)
        (cons +cmark-node-emph+ :emph)
        (cons +cmark-node-strong+ :strong)
        (cons +cmark-node-link+ :link)
        (cons +cmark-node-image+ :image)
        (cons +cmark-node-footnote-reference+ :footnote-reference))
  "Every core cmark_node_type but CUSTOM_BLOCK and CUSTOM_INLINE, paired with
the AST vocabulary kind CLASSIFY-NODE must give it when a node carries no
extension.")

(define-test classify-node-every-core-type-code
  (dolist (pair *core-type-code-kinds*)
    (destructuring-bind (type-code . kind) pair
      (is eql kind (classify-node type-code nil "<unknown>") "type code ~A" type-code))))

(define-test classify-node-table-type-strings
  (is eql :table (classify-node 0 :table "table"))
  (is eql :table-header (classify-node 0 :table "table_header"))
  (is eql :table-row (classify-node 0 :table "table_row"))
  (is eql :table-cell (classify-node 0 :table "table_cell")))

(define-test classify-node-strikethrough
  (is eql :strikethrough (classify-node 0 :strikethrough "strikethrough")))

(define-test classify-node-tasklist-item
  (is eql :task-item (classify-node +cmark-node-item+ :tasklist "tasklist")))

(define-test classify-node-tasklist-non-item-is-extension
  (is eql :extension (classify-node +cmark-node-paragraph+ :tasklist "tasklist")))

(define-test classify-node-unrecognized-table-type-string-is-extension
  (is eql :extension (classify-node 0 :table "something_else")))

(define-test classify-node-autolink-is-extension
  (is eql :extension (classify-node 0 :autolink "<unknown>")))

(define-test classify-node-tagfilter-is-extension
  (is eql :extension (classify-node 0 :tagfilter "<unknown>")))

(define-test classify-node-other-extension-is-extension
  (is eql :extension (classify-node 0 :other "something")))

(define-test classify-node-unknown-core-type-code-is-extension
  ;; No extension, and a type code outside the pin's vocabulary: the
  ;; defensive fallback, not an error. CLASSIFY-NODE only ever refuses
  ;; CMARK_NODE_CUSTOM_BLOCK and CMARK_NODE_CUSTOM_INLINE outright.
  (is eql :extension (classify-node 999999 nil "<unknown>")))

(define-test classify-node-custom-block-signals
  (fail (classify-node +cmark-node-custom-block+ nil "<unknown>") 'unsupported-extension-node)
  (let ((condition (signalled
                     'unsupported-extension-node
                     (lambda () (classify-node +cmark-node-custom-block+ nil "<unknown>")))))
    (true condition)
    (is eql 'classify-node (condition-operation condition))
    (is = +cmark-node-custom-block+ (condition-datum condition))))

(define-test classify-node-custom-inline-signals
  (fail (classify-node +cmark-node-custom-inline+ nil "<unknown>") 'unsupported-extension-node)
  (let ((condition (signalled
                     'unsupported-extension-node
                     (lambda () (classify-node +cmark-node-custom-inline+ nil "<unknown>")))))
    (true condition)
    (is eql 'classify-node (condition-operation condition))
    (is = +cmark-node-custom-inline+ (condition-datum condition))))

(define-test classify-node-custom-block-signals-whatever-extension-is
  ;; "whatever EXTENSION is" (M2b plan, Task 2): the custom-node check runs
  ;; first, before EXTENSION is even consulted.
  (fail (classify-node +cmark-node-custom-block+ :table "table") 'unsupported-extension-node)
  (fail (classify-node +cmark-node-custom-inline+ :other "x") 'unsupported-extension-node)
  (fail (classify-node +cmark-node-custom-block+ :tasklist "tasklist")
        'unsupported-extension-node))

;;; RESOLVE-CMARK-LIBRARIES (ADR-0009)

(defun regular-file-p-for (paths)
  "A REGULAR-FILE-P function for RESOLVE-CMARK-LIBRARIES: true exactly for
the path strings in PATHS, a closure over that list, never touching a real
filesystem."
  (lambda (path) (and (member path paths :test #'string=) t)))

(defun native-library-not-found-error (thunk)
  "Call THUNK. Return the NATIVE-LIBRARY-NOT-FOUND it signals, or NIL."
  (signalled 'native-library-not-found thunk))

(defun linux-core-path (directory)
  (format nil "~A/libcmark-gfm.so.~A" directory *cmark-gfm-version*))

(defun linux-extensions-path (directory)
  (format nil "~A/libcmark-gfm-extensions.so.~A" directory *cmark-gfm-version*))

(defun macos-core-path (directory)
  (format nil "~A/libcmark-gfm.~A.dylib" directory *cmark-gfm-version*))

(defun macos-extensions-path (directory)
  (format nil "~A/libcmark-gfm-extensions.~A.dylib" directory *cmark-gfm-version*))

;;; 1. Override: the special variable, verbatim

(define-test resolve-cmark-libraries-uses-the-special-variable-verbatim
  (let ((core "/opt/lib/libcmark-gfm.so")
        (extensions "/opt/lib/libcmark-gfm-extensions.so"))
    (is equal (list core extensions)
        (resolve-cmark-libraries :libraries (list core extensions)
                                  :regular-file-p (regular-file-p-for (list core extensions))))))

(define-test resolve-cmark-libraries-accepts-pathnames-in-the-special-variable
  (let ((core #P"/opt/lib/libcmark-gfm.so")
        (extensions #P"/opt/lib/libcmark-gfm-extensions.so"))
    (is equal (list (namestring core) (namestring extensions))
        (resolve-cmark-libraries
         :libraries (list core extensions)
         :regular-file-p (regular-file-p-for (list (namestring core) (namestring extensions)))))))

(define-test resolve-cmark-libraries-rejects-one-path-in-the-special-variable
  (let ((condition (native-library-not-found-error
                     (lambda ()
                       (resolve-cmark-libraries :libraries (list "/opt/lib/libcmark-gfm.so")
                                                 :regular-file-p (constantly t))))))
    (true condition)
    (is equal (list "/opt/lib/libcmark-gfm.so") (condition-override condition))))

(define-test resolve-cmark-libraries-rejects-three-paths-in-the-special-variable
  (true (native-library-not-found-error
         (lambda ()
           (resolve-cmark-libraries
            :libraries (list "/a/libcmark-gfm.so" "/a/libcmark-gfm-extensions.so" "/a/extra.so")
            :regular-file-p (constantly t))))))

(define-test resolve-cmark-libraries-rejects-a-relative-path-in-the-special-variable
  (true (native-library-not-found-error
         (lambda ()
           (resolve-cmark-libraries
            :libraries (list "lib/libcmark-gfm.so" "/opt/lib/libcmark-gfm-extensions.so")
            :regular-file-p (constantly t))))))

(define-test resolve-cmark-libraries-rejects-an-empty-path-in-the-special-variable
  (true (native-library-not-found-error
         (lambda ()
           (resolve-cmark-libraries
            :libraries (list "" "/opt/lib/libcmark-gfm-extensions.so")
            :regular-file-p (constantly t))))))

(define-test resolve-cmark-libraries-rejects-a-dotted-pair-special-variable
  ;; A dotted LIBRARIES isn't a proper list at all: (LENGTH LIBRARIES), on
  ;; the old LISTP-only check, signalled a raw TYPE-ERROR here instead.
  (true (native-library-not-found-error
         (lambda ()
           (resolve-cmark-libraries :libraries (cons "/a/core.so" "/a/ext.so")
                                     :regular-file-p (constantly t))))))

(define-test resolve-cmark-libraries-rejects-a-circular-special-variable
  ;; A circular LIBRARIES hung (LENGTH LIBRARIES) on the old LISTP-only
  ;; check, under the startup lock. PROPER-LIST-P's Floyd cycle detection
  ;; rejects it in bounded time instead.
  (let ((circular (list "/a/core.so" "/a/ext.so")))
    (setf (cdr (last circular)) circular)
    (true (native-library-not-found-error
           (lambda ()
             (resolve-cmark-libraries :libraries circular :regular-file-p (constantly t)))))))

(define-test resolve-cmark-libraries-bad-special-variable-never-falls-back
  ;; ADR-0009 §1, "No fallback": a malformed *CMARK-GFM-LIBRARIES* must
  ;; signal, never silently trying CL_COMMONMARK_GFM_LIBS or the directory
  ;; search instead, even when either would otherwise resolve cleanly.
  (let ((environment-core "/opt/b/libcmark-gfm.so")
        (environment-extensions "/opt/b/libcmark-gfm-extensions.so")
        (search-core (linux-core-path "/usr/lib"))
        (search-extensions (linux-extensions-path "/usr/lib")))
    (true (native-library-not-found-error
           (lambda ()
             (resolve-cmark-libraries
              :libraries (list "rel/a.so" "/opt/a/libcmark-gfm-extensions.so")
              :environment (format nil "~A:~A" environment-core environment-extensions)
              :regular-file-p (regular-file-p-for
                               (list "/opt/a/libcmark-gfm-extensions.so"
                                     environment-core environment-extensions)))))
          "a bad special variable must not fall back to a good environment variable")
    (true (native-library-not-found-error
           (lambda ()
             (resolve-cmark-libraries
              :libraries (list "rel/a.so" "/opt/a/libcmark-gfm-extensions.so")
              :os :linux :multiarch nil
              :regular-file-p (regular-file-p-for (list search-core search-extensions)))))
          "a bad special variable must not fall back to the directory search")))

(define-test resolve-cmark-libraries-names-a-missing-override-file
  (let* ((core "/opt/lib/libcmark-gfm.so")
         (extensions "/opt/lib/libcmark-gfm-extensions.so")
         (condition (native-library-not-found-error
                     (lambda ()
                       (resolve-cmark-libraries :libraries (list core extensions)
                                                 :regular-file-p (regular-file-p-for
                                                                   (list core)))))))
    (true condition)
    (is string= extensions (condition-datum condition))
    (is equal (list extensions) (condition-paths condition))))

(define-test resolve-cmark-libraries-checks-the-core-before-the-extensions
  (let* ((core "/opt/lib/libcmark-gfm.so")
         (extensions "/opt/lib/libcmark-gfm-extensions.so")
         (condition (native-library-not-found-error
                     (lambda ()
                       (resolve-cmark-libraries :libraries (list core extensions)
                                                 :regular-file-p (constantly nil))))))
    (true condition)
    (is string= core (condition-datum condition))
    (is equal (list core) (condition-paths condition))))

;;; 1. Override: the environment variable, when the special variable is NIL

(define-test resolve-cmark-libraries-uses-the-environment-when-unset
  (let ((core "/opt/lib/libcmark-gfm.so")
        (extensions "/opt/lib/libcmark-gfm-extensions.so"))
    (is equal (list core extensions)
        (resolve-cmark-libraries :environment (format nil "~A:~A" core extensions)
                                  :regular-file-p (regular-file-p-for (list core extensions))))))

(define-test resolve-cmark-libraries-prefers-the-special-variable-over-the-environment
  (let ((libraries-core "/opt/a/libcmark-gfm.so")
        (libraries-extensions "/opt/a/libcmark-gfm-extensions.so")
        (environment-core "/opt/b/libcmark-gfm.so")
        (environment-extensions "/opt/b/libcmark-gfm-extensions.so"))
    (is equal (list libraries-core libraries-extensions)
        (resolve-cmark-libraries
         :libraries (list libraries-core libraries-extensions)
         :environment (format nil "~A:~A" environment-core environment-extensions)
         :regular-file-p (regular-file-p-for (list libraries-core libraries-extensions
                                                    environment-core environment-extensions))))))

(define-test resolve-cmark-libraries-treats-an-empty-environment-variable-as-set
  ;; "" is set, not unset, so this must signal even though a directory
  ;; search with this REGULAR-FILE-P would otherwise succeed.
  (let ((core (linux-core-path "/usr/lib"))
        (extensions (linux-extensions-path "/usr/lib")))
    (true (native-library-not-found-error
           (lambda ()
             (resolve-cmark-libraries :environment "" :os :linux :multiarch nil
                                       :regular-file-p (regular-file-p-for
                                                         (list core extensions))))))))

(define-test resolve-cmark-libraries-empty-environment-is-named-as-the-override
  (let ((condition (native-library-not-found-error
                     (lambda ()
                       (resolve-cmark-libraries :environment "" :os :linux
                                                 :regular-file-p (constantly nil))))))
    (true condition)
    (is string= "" (condition-override condition))))

(define-test resolve-cmark-libraries-rejects-an-environment-with-no-colon
  (true (native-library-not-found-error
         (lambda ()
           (resolve-cmark-libraries :environment "/opt/lib/libcmark-gfm.so"
                                     :regular-file-p (constantly t))))))

(define-test resolve-cmark-libraries-rejects-an-environment-with-two-colons
  (true (native-library-not-found-error
         (lambda ()
           (resolve-cmark-libraries :environment "/a/x.so:/a/y.so:/a/z.so"
                                     :regular-file-p (constantly t))))))

(define-test resolve-cmark-libraries-rejects-a-relative-path-in-the-environment
  (true (native-library-not-found-error
         (lambda ()
           (resolve-cmark-libraries
            :environment "lib/libcmark-gfm.so:/opt/lib/libcmark-gfm-extensions.so"
            :regular-file-p (constantly t))))))

;;; 2. Directory search

(define-test resolve-cmark-libraries-searches-linux-directories-in-order
  (let* ((directories '("/usr/lib64" "/usr/lib" "/usr/local/lib"))
         (regular-file-p (regular-file-p-for
                           (mapcan (lambda (d) (list (linux-core-path d) (linux-extensions-path d)))
                                   directories))))
    (is equal (list (linux-core-path "/usr/lib64") (linux-extensions-path "/usr/lib64"))
        (resolve-cmark-libraries :os :linux :multiarch nil :regular-file-p regular-file-p))))

(define-test resolve-cmark-libraries-finds-a-later-linux-directory
  (let ((regular-file-p (regular-file-p-for (list (linux-core-path "/usr/local/lib")
                                                   (linux-extensions-path "/usr/local/lib")))))
    (is equal (list (linux-core-path "/usr/local/lib") (linux-extensions-path "/usr/local/lib"))
        (resolve-cmark-libraries :os :linux :multiarch nil :regular-file-p regular-file-p))))

(define-test resolve-cmark-libraries-prefers-the-multiarch-directory
  (let* ((multiarch "x86_64-linux-gnu")
         (multiarch-directory (format nil "/usr/lib/~A" multiarch))
         (regular-file-p (regular-file-p-for
                           (list (linux-core-path multiarch-directory)
                                 (linux-extensions-path multiarch-directory)
                                 (linux-core-path "/usr/lib64")
                                 (linux-extensions-path "/usr/lib64")))))
    (is equal (list (linux-core-path multiarch-directory)
                    (linux-extensions-path multiarch-directory))
        (resolve-cmark-libraries :os :linux :multiarch multiarch :regular-file-p regular-file-p))))

(define-test resolve-cmark-libraries-skips-the-multiarch-directory-when-nil
  (let* ((multiarch-directory "/usr/lib/x86_64-linux-gnu")
         (regular-file-p (regular-file-p-for (list (linux-core-path multiarch-directory)
                                                    (linux-extensions-path multiarch-directory)))))
    (true (native-library-not-found-error
           (lambda ()
             (resolve-cmark-libraries :os :linux :multiarch nil :regular-file-p regular-file-p))))))

(define-test resolve-cmark-libraries-skips-a-directory-holding-only-one-file
  ;; /usr/lib64 holds only the core; it must not be paired with /usr/lib's
  ;; extensions. The correct result comes entirely from /usr/lib.
  (let* ((partial-directory "/usr/lib64")
         (full-directory "/usr/lib")
         (regular-file-p (regular-file-p-for
                           (list (linux-core-path partial-directory)
                                 (linux-core-path full-directory)
                                 (linux-extensions-path full-directory)))))
    (is equal (list (linux-core-path full-directory) (linux-extensions-path full-directory))
        (resolve-cmark-libraries :os :linux :multiarch nil :regular-file-p regular-file-p))))

(define-test resolve-cmark-libraries-macos-filenames
  (let ((regular-file-p (regular-file-p-for (list (macos-core-path "/opt/homebrew/lib")
                                                   (macos-extensions-path "/opt/homebrew/lib")))))
    (is equal (list (macos-core-path "/opt/homebrew/lib")
                    (macos-extensions-path "/opt/homebrew/lib"))
        (resolve-cmark-libraries :os :macos :regular-file-p regular-file-p))))

(define-test resolve-cmark-libraries-macos-falls-back-to-usr-local-lib
  (let ((regular-file-p (regular-file-p-for (list (macos-core-path "/usr/local/lib")
                                                   (macos-extensions-path "/usr/local/lib")))))
    (is equal (list (macos-core-path "/usr/local/lib") (macos-extensions-path "/usr/local/lib"))
        (resolve-cmark-libraries :os :macos :regular-file-p regular-file-p))))

(define-test resolve-cmark-libraries-signals-when-nothing-is-found
  (true (native-library-not-found-error
         (lambda ()
           (resolve-cmark-libraries :os :linux :multiarch nil :regular-file-p (constantly nil))))))

(define-test resolve-cmark-libraries-nothing-found-lists-every-linux-directory
  (let* ((multiarch "aarch64-linux-gnu")
         (condition (native-library-not-found-error
                     (lambda ()
                       (resolve-cmark-libraries :os :linux :multiarch multiarch
                                                 :regular-file-p (constantly nil))))))
    (true condition)
    (is equal (list (format nil "/usr/lib/~A" multiarch) "/usr/lib64" "/usr/lib" "/usr/local/lib")
        (condition-paths condition))
    (false (condition-override condition))))

(define-test resolve-cmark-libraries-nothing-found-lists-every-macos-directory
  (let ((condition (native-library-not-found-error
                     (lambda ()
                       (resolve-cmark-libraries :os :macos :regular-file-p (constantly nil))))))
    (true condition)
    (is equal (list "/opt/homebrew/lib" "/usr/local/lib") (condition-paths condition))
    (false (condition-override condition))))

(define-test resolve-cmark-libraries-nothing-found-report-is-useful
  ;; The report used to read "neither *CMARK-GFM-LIBRARIES* nor
  ;; CL_COMMONMARK_GFM_LIBS is set: NIL" -- a NIL datum, and no mention of
  ;; how to fix it. It must now say no searched directory holds both pinned
  ;; libraries, name both override variables, and carry the directories
  ;; searched as its datum, not NIL.
  (let* ((multiarch "x86_64-linux-gnu")
         (condition (native-library-not-found-error
                     (lambda ()
                       (resolve-cmark-libraries :os :linux :multiarch multiarch
                                                 :regular-file-p (constantly nil))))))
    (true condition)
    (is equal (condition-paths condition) (condition-datum condition))
    (let ((report (princ-to-string condition)))
      (true (search "no searched directory holds both pinned libraries" report))
      (true (search "*CMARK-GFM-LIBRARIES*" report))
      (true (search "CL_COMMONMARK_GFM_LIBS" report)))))

(define-test resolve-cmark-libraries-condition-names-its-operation
  (let ((condition (native-library-not-found-error
                     (lambda ()
                       (resolve-cmark-libraries :os :linux :multiarch nil
                                                 :regular-file-p (constantly nil))))))
    (true condition)
    (is eql 'resolve-cmark-libraries (condition-operation condition))))

;;;; CHECK-OPTIONS, the option bits, DOCUMENT-ATTRIBUTES, the limits and
;;;; TABLE-CELL-BOUND (M2b plan Task 3; M2 design §5.5, §6.3, §7.2, §7.3).

;;; Helpers

(defun checked (entry-point &rest options)
  "(CHECK-OPTIONS ENTRY-POINT 'OP OPTIONS). The OPERATION symbol is never
interpreted by CHECK-OPTIONS, so any symbol will do here."
  (check-options entry-point 'op options))

(defun entry-option-error (type entry-point options)
  "The condition of TYPE that (CHECK-OPTIONS ENTRY-POINT 'OP OPTIONS)
signals, or NIL."
  (signalled type (lambda () (check-options entry-point 'op options))))

(defun entry-parse-option-error (entry-point options)
  "The INVALID-PARSE-OPTION that CHECK-OPTIONS signals for ENTRY-POINT and
OPTIONS, or NIL."
  (entry-option-error 'invalid-parse-option entry-point options))

(defun entry-render-option-error (entry-point options)
  "The INVALID-RENDER-OPTION that CHECK-OPTIONS signals for ENTRY-POINT and
OPTIONS, or NIL."
  (entry-option-error 'invalid-render-option entry-point options))

(defun type-error-signalled (thunk)
  "Call THUNK. Return the TYPE-ERROR it signals, or NIL."
  (handler-case (progn (funcall thunk) nil)
    (type-error (condition) condition)))

(defparameter *vt* (string (code-char 11))
  "A vertical tab, one of TABLE-CELL-BOUND's candidate characters.")

(defparameter *ff* (string (code-char 12))
  "A form feed, one of TABLE-CELL-BOUND's candidate characters.")

;;; CHECK-OPTIONS: bad values, per entry point (M2 design §7.2)

(define-test check-options-parse-rejects-bad-profile
  (dolist (value '(:bogus "gfm" 1 nil))
    (true (entry-parse-option-error :parse (list :profile value))
          "profile ~S should be rejected" value)))

(define-test check-options-parse-rejects-bad-extensions
  (dolist (value (list :table '(:table . :strikethrough) '(:bogus) '(:table :table) 5 "table"))
    (true (entry-parse-option-error :parse (list :extensions value))
          "extensions ~S should be rejected" value)))

(define-test check-options-parse-rejects-bad-footnotes
  (dolist (value '(1 "yes" :yes 0))
    (true (entry-parse-option-error :parse (list :footnotes value))
          "footnotes ~S should be rejected" value)))

(define-test check-options-parse-rejects-bad-smart
  (dolist (value '(1 "yes" :yes 0))
    (true (entry-parse-option-error :parse (list :smart value))
          "smart ~S should be rejected" value)))

(define-test check-options-parse-rejects-bad-sourcepos
  (dolist (value '(1 "yes" :yes 0))
    (true (entry-parse-option-error :parse (list :sourcepos value))
          "sourcepos ~S should be rejected" value)))

(define-test check-options-html-rejects-bad-softbreak
  (dolist (value '(:tab nil "newline" :space-bar))
    (true (entry-render-option-error :html (list :softbreak value))
          "softbreak ~S should be rejected" value)))

(define-test check-options-html-rejects-bad-unsafe-html
  (dolist (value '(1 "yes" :yes))
    (true (entry-render-option-error :html (list :unsafe-html value))
          "unsafe-html ~S should be rejected" value)))

(define-test check-options-html-rejects-bad-profile-as-a-parse-option
  ;; :HTML recognizes :PROFILE too, and a bad value is still
  ;; INVALID-PARSE-OPTION, not INVALID-RENDER-OPTION.
  (true (entry-parse-option-error :html '(:profile :bogus)))
  (false (entry-render-option-error :html '(:profile :bogus))))

(define-test check-options-html-rejects-bad-sourcepos-as-a-parse-option
  (true (entry-parse-option-error :html '(:sourcepos :maybe)))
  (false (entry-render-option-error :html '(:sourcepos :maybe))))

;;; CHECK-OPTIONS: which condition, across all four entry points (M2 design
;;; §7.2, §8.1). The four tests above cover :HTML on its own; this one is
;;; table-driven over every entry point and every parse-option key it takes.
;;; The keys come from spec §7.2's table, written out here by hand rather
;;; than read from PARSE-KEYS: a mutation that drops a key from PARSE-KEYS
;;; (dropping :SMART from :PLAINTEXT and :HTML-TREE, say) would otherwise
;;; narrow this test's own coverage along with the code under test, and
;;; still pass. :PLAINTEXT and :HTML-TREE take no :SOURCEPOS at all, so
;;; BAD-PARSE-VALUE-FOR has no entry for it.

(defparameter *entry-point-parse-keys*
  '((:parse . (:profile :extensions :footnotes :smart :sourcepos))
    (:html . (:profile :extensions :footnotes :smart :sourcepos))
    (:plaintext . (:profile :extensions :footnotes :smart))
    (:html-tree . (:profile :extensions :footnotes :smart)))
  "Each entry point's parse-option keys (M2 design §7.2's table), written
out by hand so CHECK-OPTIONS-SIGNALS-INVALID-PARSE-OPTION-FOR-EVERY-PARSE-KEY
doesn't take them from PARSE-KEYS, the code under test.")

(defun bad-parse-value-for (key)
  "A value CHECK-OPTIONS must reject for KEY, one of
*ENTRY-POINT-PARSE-KEYS*' five."
  (ecase key
    (:profile :bogus)
    (:extensions '(:bogus))
    (:footnotes 1)
    (:smart 1)
    (:sourcepos 1)))

(define-test check-options-signals-invalid-parse-option-for-every-parse-key
  (dolist (entry *entry-point-parse-keys*)
    (destructuring-bind (entry-point . keys) entry
      (dolist (key keys)
        (let ((options (list key (bad-parse-value-for key))))
          (true (entry-parse-option-error entry-point options)
                "~S ~S should signal INVALID-PARSE-OPTION" entry-point options)
          (false (entry-render-option-error entry-point options)
                 "~S ~S should not signal INVALID-RENDER-OPTION" entry-point options))))))

(define-test check-options-plaintext-rejects-bad-softbreak
  (dolist (value '(:tab nil "space"))
    (true (entry-render-option-error :plaintext (list :softbreak value))
          "softbreak ~S should be rejected" value)))

(define-test check-options-plaintext-rejects-bad-width
  (dolist (value '(-1 1.5 "80" t))
    (true (entry-render-option-error :plaintext (list :width value))
          "width ~S should be rejected" value)))

(define-test check-options-plaintext-width-boundaries
  (false (entry-render-option-error :plaintext '(:width 0)))
  (is = 0 (checked-width (checked :plaintext :width 0)))
  (false (entry-render-option-error :plaintext '(:width 2147483647)))
  (is = 2147483647 (checked-width (checked :plaintext :width 2147483647)))
  (true (entry-render-option-error :plaintext '(:width 2147483648))))

(define-test check-options-plaintext-rejects-sourcepos-as-an-unknown-key
  ;; :PLAINTEXT doesn't take :SOURCEPOS at all: it always parses without
  ;; positions, so giving it the key is an unknown-key problem, not a bad
  ;; value of a recognized one.
  (true (entry-render-option-error :plaintext '(:sourcepos t))))

(define-test check-options-plaintext-rejects-unsafe-html-as-an-unknown-key
  (true (entry-render-option-error :plaintext '(:unsafe-html t))))

(define-test check-options-html-tree-accepts-any-tree-option-value
  ;; Tree-option values aren't checked here; CHECK-TREE-OPTIONS (ADR-0012)
  ;; validates them. CHECKED-TREE-OPTIONS must still return each pair
  ;; verbatim, bogus value included.
  (false (entry-render-option-error :html-tree '(:softbreak :bogus)))
  (is equal '(:softbreak :bogus) (checked-tree-options (checked :html-tree :softbreak :bogus)))
  (false (entry-render-option-error :html-tree '(:raw-html :nonsense)))
  (is equal '(:raw-html :nonsense) (checked-tree-options (checked :html-tree :raw-html :nonsense)))
  (false (entry-render-option-error :html-tree '(:link-policy 42)))
  (is equal '(:link-policy 42) (checked-tree-options (checked :html-tree :link-policy 42)))
  (false (entry-render-option-error :html-tree '(:document-wrapper "not-a-keyword")))
  (is equal '(:document-wrapper "not-a-keyword")
      (checked-tree-options (checked :html-tree :document-wrapper "not-a-keyword"))))

(define-test check-options-html-tree-rejects-sourcepos-as-an-unknown-key
  (true (entry-render-option-error :html-tree '(:sourcepos t))))

(define-test check-options-html-tree-rejects-width-as-an-unknown-key
  (true (entry-render-option-error :html-tree '(:width 10))))

(define-test check-options-html-tree-rejects-unsafe-html-as-an-unknown-key
  (true (entry-render-option-error :html-tree '(:unsafe-html t))))

;;; CHECK-OPTIONS: structural problems

(define-test check-options-rejects-an-odd-length-option-list
  (true (entry-parse-option-error :parse '(:profile)))
  (true (entry-render-option-error :html '(:profile :gfm :softbreak))))

(define-test check-options-parse-signals-invalid-parse-option-for-an-odd-length-list
  ;; :PARSE signals INVALID-PARSE-OPTION for every problem, this one
  ;; included; it never signals INVALID-RENDER-OPTION at all.
  (true (entry-parse-option-error :parse '(:profile)))
  (false (entry-render-option-error :parse '(:profile))))

(define-test check-options-rejects-an-unknown-key
  (true (entry-parse-option-error :parse '(:bogus 1)))
  (true (entry-render-option-error :html '(:bogus 1)))
  (true (entry-render-option-error :plaintext '(:bogus 1)))
  (true (entry-render-option-error :html-tree '(:bogus 1))))

(define-test check-options-rejects-a-key-only-another-entry-point-takes
  ;; :WIDTH belongs to :PLAINTEXT alone.
  (true (entry-parse-option-error :parse '(:width 10)))
  (true (entry-render-option-error :html '(:width 10)))
  (true (entry-render-option-error :html-tree '(:width 10))))

(define-test check-options-parse-never-signals-invalid-render-option
  (false (entry-render-option-error :parse '(:profile)))
  (false (entry-render-option-error :parse '(:bogus 1)))
  (false (entry-render-option-error :parse '(:profile :bogus))))

;;; CHECK-OPTIONS: repeated keys

(define-test check-options-repeated-key-leftmost-wins
  (is eql :space (checked-softbreak (checked :html :softbreak :space :softbreak :br)))
  (is eql :gfm (checked-profile (checked :parse :profile :gfm :profile :commonmark))))

(define-test check-options-repeated-key-validates-every-value
  ;; The leftmost value (:space) is fine, but the second (:bogus) must still
  ;; be checked and rejected.
  (true (entry-render-option-error :html '(:softbreak :space :softbreak :bogus))))

;;; CHECK-OPTIONS: extensions

(define-test check-options-rejects-a-repeated-extension
  (true (entry-parse-option-error :parse '(:extensions (:table :table)))))

(define-test check-options-rejects-an-unknown-extension
  (true (entry-parse-option-error :parse '(:extensions (:bogus)))))

(define-test check-options-repeated-extensions-key-leftmost-wins
  (is equal '(:table)
      (checked-extensions (checked :parse :extensions '(:table) :extensions '(:strikethrough)))))

(define-test check-options-extensions-canonical-order
  (is equal '(:table :strikethrough :tasklist)
      (checked-extensions (checked :parse :extensions '(:tasklist :table :strikethrough)))))

(defun no-shared-cons-p (list other)
  "True when no cons cell of LIST is EQ to any cons cell of OTHER: the two
share no tail at all, not even a trailing one."
  (loop for tail on list never (loop for other-tail on other thereis (eq tail other-tail))))

(define-test check-options-extensions-default-shares-no-cons-with-the-global
  (true (no-shared-cons-p (checked-extensions (checked :parse)) *extension-keywords*)))

(define-test check-options-extensions-explicit-lists-share-no-cons-with-the-global
  ;; A caller who sorts a parsed document's :EXTENSIONS attribute in place --
  ;; or SETFs one of its cells -- must not corrupt every later default parse.
  ;; CANONICAL-EXTENSIONS must return a fresh list every time, never
  ;; *EXTENSION-KEYWORDS* itself and never a tail of it, whether every
  ;; extension is named, a trailing subset is, or just one is.
  (dolist (extensions (list (copy-list *extension-keywords*)
                             '(:strikethrough :autolink :tagfilter :tasklist)
                             '(:tasklist :strikethrough)
                             '(:autolink)))
    (true (no-shared-cons-p (checked-extensions (checked :parse :extensions extensions))
                            *extension-keywords*)
          "~S should share no cons with *EXTENSION-KEYWORDS*" extensions)))

;;; CHECK-OPTIONS: profile defaults

(define-test check-options-gfm-profile-defaults
  (let ((result (checked :parse)))
    (is eql :gfm (checked-profile result))
    (is equal *extension-keywords* (checked-extensions result))
    (true (checked-footnotes result))
    (false (checked-smart result))
    (true (checked-sourcepos result))))

(define-test check-options-commonmark-profile-defaults
  (let ((result (checked :parse :profile :commonmark)))
    (is eql :commonmark (checked-profile result))
    (is equal '() (checked-extensions result))
    (false (checked-footnotes result))
    (false (checked-smart result))))

(define-test check-options-commonmark-with-explicit-footnotes
  ;; :profile :commonmark :footnotes t parses footnotes with no extensions
  ;; attached (M2 design §7.2): the profile only supplies defaults.
  (let ((result (checked :parse :profile :commonmark :footnotes t)))
    (is eql :commonmark (checked-profile result))
    (is equal '() (checked-extensions result))
    (true (checked-footnotes result))))

(define-test check-options-explicit-empty-extensions
  ;; An explicit :EXTENSIONS NIL overrides even the :GFM profile's default.
  (let ((result (checked :parse :extensions nil)))
    (is eql :gfm (checked-profile result))
    (is equal '() (checked-extensions result))
    (true (checked-footnotes result))))

;;; CHECK-OPTIONS: tree options

(define-test check-options-tree-options-keep-order-and-repeats
  (is equal '(:softbreak :space :raw-html :omit :softbreak :br :document-wrapper :article)
      (checked-tree-options
       (checked :html-tree :softbreak :space :raw-html :omit :softbreak :br
                :document-wrapper :article))))

(define-test check-options-tree-options-nil-for-other-entry-points
  (false (checked-tree-options (checked :parse)))
  (false (checked-tree-options (checked :html)))
  (false (checked-tree-options (checked :plaintext))))

(define-test check-options-tree-options-nil-when-none-given
  (false (checked-tree-options (checked :html-tree))))

;;; CHECK-OPTIONS: :SOURCEPOS, and defaults for options an entry point
;;; doesn't take (M2 design §7.2)

(define-test check-options-sourcepos-defaults
  (true (checked-sourcepos (checked :parse)))
  (false (checked-sourcepos (checked :html)))
  (false (checked-sourcepos (checked :plaintext)))
  (false (checked-sourcepos (checked :html-tree))))

(define-test check-options-html-accepts-explicit-sourcepos
  (true (checked-sourcepos (checked :html :sourcepos t)))
  (false (checked-sourcepos (checked :html :sourcepos nil))))

(define-test check-options-parse-accepts-explicit-sourcepos-off
  (false (checked-sourcepos (checked :parse :sourcepos nil))))

(define-test check-options-softbreak-default-when-not-a-core-option
  ;; :HTML-TREE's :SOFTBREAK is a tree option, not CHECK-OPTIONS' core one:
  ;; CHECKED-SOFTBREAK must stay the hardcoded default, unaffected by it.
  (is eql :newline (checked-softbreak (checked :parse)))
  (is eql :newline (checked-softbreak (checked :html-tree :softbreak :br))))

(define-test check-options-unsafe-html-default-when-not-taken
  (false (checked-unsafe-html (checked :parse)))
  (false (checked-unsafe-html (checked :plaintext)))
  (false (checked-unsafe-html (checked :html-tree))))

(define-test check-options-width-default-when-not-taken
  (is = 0 (checked-width (checked :parse)))
  (is = 0 (checked-width (checked :html)))
  (is = 0 (checked-width (checked :html-tree))))

;;; CHECK-OPTIONS: miscellaneous

(define-test check-options-condition-names-its-operation
  (let ((condition (signalled
                    'invalid-parse-option
                    (lambda () (check-options :parse 'some-caller '(:profile :bogus))))))
    (true condition)
    (is eql 'some-caller (condition-operation condition))))

(define-test check-options-render-condition-names-its-operation
  (let ((condition (signalled
                    'invalid-render-option
                    (lambda () (check-options :html 'another-caller '(:bogus 1))))))
    (true condition)
    (is eql 'another-caller (condition-operation condition))))

(define-test check-options-returns-a-checked-options
  (true (typep (checked :parse) 'checked-options)))

;;; Option bits (M2 design §7.3)

(define-test parse-option-bits-gfm-defaults
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-sourcepos+)
      (parse-option-bits (checked :parse))))

(define-test parse-option-bits-commonmark-defaults
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-sourcepos+)
      (parse-option-bits (checked :parse :profile :commonmark))))

(define-test parse-option-bits-smart
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-sourcepos+
               +cmark-opt-smart+)
      (parse-option-bits (checked :parse :smart t))))

(define-test parse-option-bits-sourcepos-off
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+)
      (parse-option-bits (checked :parse :sourcepos nil))))

(define-test parse-option-bits-footnotes-off
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-sourcepos+)
      (parse-option-bits (checked :parse :footnotes nil))))

(define-test parse-option-bits-always-includes-validate-utf8
  (is = +cmark-opt-validate-utf8+
      (parse-option-bits (checked :parse :profile :commonmark :sourcepos nil))))

(define-test html-option-bits-defaults
  ;; :HTML's default :SOURCEPOS is NIL, so only VALIDATE-UTF8 and FOOTNOTES
  ;; (the :GFM default) appear.
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+)
      (html-option-bits (checked :html))))

(define-test html-option-bits-softbreak-br-sets-hardbreaks
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-hardbreaks+)
      (html-option-bits (checked :html :softbreak :br))))

(define-test html-option-bits-softbreak-space-sets-nobreaks
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-nobreaks+)
      (html-option-bits (checked :html :softbreak :space))))

(define-test html-option-bits-softbreak-newline-sets-neither
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+)
      (html-option-bits (checked :html :softbreak :newline))))

(define-test html-option-bits-unsafe-html-sets-unsafe
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-unsafe+)
      (html-option-bits (checked :html :unsafe-html t))))

(define-test html-option-bits-sourcepos-sets-sourcepos
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-sourcepos+)
      (html-option-bits (checked :html :sourcepos t))))

(define-test html-option-bits-combines-every-bit
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-smart+
               +cmark-opt-sourcepos+ +cmark-opt-hardbreaks+ +cmark-opt-unsafe+)
      (html-option-bits (checked :html :smart t :sourcepos t :softbreak :br :unsafe-html t))))

(define-test plaintext-option-bits-defaults
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+)
      (plaintext-option-bits (checked :plaintext))))

(define-test plaintext-option-bits-softbreak-br-sets-hardbreaks
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-hardbreaks+)
      (plaintext-option-bits (checked :plaintext :softbreak :br))))

(define-test plaintext-option-bits-softbreak-space-sets-nobreaks
  (is = (logior +cmark-opt-validate-utf8+ +cmark-opt-footnotes+ +cmark-opt-nobreaks+)
      (plaintext-option-bits (checked :plaintext :softbreak :space))))

(define-test plaintext-option-bits-never-sets-sourcepos
  ;; :PLAINTEXT always parses with :SOURCEPOS NIL internally.
  (false (plusp (logand +cmark-opt-sourcepos+ (plaintext-option-bits (checked :plaintext))))))

;;; DOCUMENT-ATTRIBUTES (M2 design §6.3)

(define-test document-attributes-gfm-profile
  (is equal (list :profile :gfm :extensions *extension-keywords* :options '(:footnotes))
      (document-attributes (checked :parse))))

(define-test document-attributes-commonmark-profile
  (is equal (list :profile :commonmark :extensions '() :options '())
      (document-attributes (checked :parse :profile :commonmark))))

(define-test document-attributes-explicit-extensions-come-back-canonical
  (is equal '(:table :autolink :tasklist)
      (getf (document-attributes (checked :parse :extensions '(:tasklist :table :autolink)))
            :extensions)))

(define-test document-attributes-options-with-neither-footnotes-nor-smart
  (is equal '() (getf (document-attributes (checked :parse :profile :commonmark)) :options)))

(define-test document-attributes-options-with-only-footnotes
  (is equal '(:footnotes)
      (getf (document-attributes (checked :parse :profile :commonmark :footnotes t)) :options)))

(define-test document-attributes-options-with-only-smart
  (is equal '(:smart)
      (getf (document-attributes (checked :parse :profile :commonmark :smart t)) :options)))

(define-test document-attributes-options-with-both-footnotes-and-smart
  ;; :FOOTNOTES before :SMART, whichever order the caller gave them.
  (is equal '(:footnotes :smart)
      (getf (document-attributes (checked :parse :profile :commonmark :smart t :footnotes t))
            :options)))

(define-test document-attributes-pass-the-ast-schema
  (dolist (options (list '() '(:profile :commonmark) '(:smart t)
                         '(:profile :commonmark :smart t :footnotes t)))
    (true (node-p (make-node :document
                              :attributes (document-attributes (apply #'checked :parse options))))
          "~S should pass the :document schema" options)))

;;; Limits: the three variables (M2 design §5.5)

(define-test max-input-octets-default
  (is = 1048576 *max-input-octets*))

(define-test max-nodes-default
  (is = 1000000 *max-nodes*))

(define-test max-output-octets-default
  (is = 67108864 *max-output-octets*))

;;; EFFECTIVE-MAXIMUM

(define-test effective-maximum-max-input-octets-below-the-hard-cap
  (let ((*max-input-octets* 1000))
    (is = 1000 (effective-maximum '*max-input-octets*))
    (false (nth-value 1 (effective-maximum '*max-input-octets*)))))

(define-test effective-maximum-max-input-octets-at-the-hard-cap
  (let ((*max-input-octets* 268435456))
    (is = 268435456 (effective-maximum '*max-input-octets*))
    (false (nth-value 1 (effective-maximum '*max-input-octets*)))))

(define-test effective-maximum-max-input-octets-above-the-hard-cap
  (let ((*max-input-octets* 268435457))
    (is = 268435456 (effective-maximum '*max-input-octets*))
    (true (nth-value 1 (effective-maximum '*max-input-octets*)))))

(define-test effective-maximum-max-output-octets-below-the-hard-cap
  (let ((*max-output-octets* 1000))
    (is = 1000 (effective-maximum '*max-output-octets*))
    (false (nth-value 1 (effective-maximum '*max-output-octets*)))))

(define-test effective-maximum-max-output-octets-at-the-hard-cap
  (let ((*max-output-octets* 536870912))
    (is = 536870912 (effective-maximum '*max-output-octets*))
    (false (nth-value 1 (effective-maximum '*max-output-octets*)))))

(define-test effective-maximum-max-output-octets-above-the-hard-cap
  (let ((*max-output-octets* 536870913))
    (is = 536870912 (effective-maximum '*max-output-octets*))
    (true (nth-value 1 (effective-maximum '*max-output-octets*)))))

(define-test effective-maximum-max-nodes-has-no-hard-cap
  (let ((*max-nodes* 999999999999))
    (is = 999999999999 (effective-maximum '*max-nodes*))
    (false (nth-value 1 (effective-maximum '*max-nodes*)))))

(define-test effective-maximum-rejects-a-negative-binding
  (let ((*max-nodes* -1))
    (true (type-error-signalled (lambda () (effective-maximum '*max-nodes*))))))

(define-test effective-maximum-rejects-a-non-integer-binding
  (let ((*max-nodes* 1.5))
    (true (type-error-signalled (lambda () (effective-maximum '*max-nodes*))))))

(define-test effective-maximum-rejects-a-nil-binding
  (let ((*max-nodes* nil))
    (true (type-error-signalled (lambda () (effective-maximum '*max-nodes*))))))

(define-test effective-maximum-rejects-a-negative-max-input-octets
  (let ((*max-input-octets* -1))
    (true (type-error-signalled (lambda () (effective-maximum '*max-input-octets*))))))

(define-test effective-maximum-rejects-a-non-integer-max-output-octets
  (let ((*max-output-octets* "64mb"))
    (true (type-error-signalled (lambda () (effective-maximum '*max-output-octets*))))))

(define-test effective-maximum-type-error-names-the-datum
  (let* ((*max-nodes* -5)
         (condition (type-error-signalled (lambda () (effective-maximum '*max-nodes*)))))
    (true condition)
    (is eql -5 (type-error-datum condition))))

;;; CHECK-LIMIT

(define-test check-limit-at-the-maximum-passes
  (false (signalled 'resource-limit-exceeded
                                (lambda () (check-limit '*max-nodes* 1000000 'op)))))

(define-test check-limit-below-the-maximum-passes
  (false (signalled 'resource-limit-exceeded
                                (lambda () (check-limit '*max-input-octets* 10 'op)))))

(define-test check-limit-one-past-the-maximum-signals-every-slot
  (let* ((*max-nodes* 1000000)
         (condition (signalled
                     'resource-limit-exceeded
                     (lambda () (check-limit '*max-nodes* 1000001 'some-op)))))
    (true condition)
    (is eql 'some-op (condition-operation condition))
    (is = 1000001 (condition-datum condition))
    (is eql '*max-nodes* (condition-limit condition))
    (is = 1000000 (condition-maximum condition))
    (true (condition-reason condition))))

(define-test check-limit-reason-when-the-variable-itself-is-exceeded
  (let* ((*max-nodes* 100)
         (condition (signalled
                     'resource-limit-exceeded
                     (lambda () (check-limit '*max-nodes* 101 'op)))))
    (true condition)
    (false (search "hard cap" (condition-reason condition)))))

(define-test check-limit-reason-when-the-hard-cap-applied
  (let* ((*max-input-octets* 300000000) ; above the 256 MiB hard cap
         (condition (signalled
                     'resource-limit-exceeded
                     (lambda () (check-limit '*max-input-octets* 268435457 'op)))))
    (true condition)
    (is = 268435456 (condition-maximum condition))
    (true (search "hard cap" (condition-reason condition)))))

;;; TABLE-CELL-BOUND (M2 design §5.5)

(define-test table-cell-bound-empty-string
  (is = 0 (table-cell-bound "")))

(define-test table-cell-bound-lf-line-ends
  ;; Two lines, "|-|-|" each: 2 single-character dash runs per line, one run
  ;; of 2 lines. Bound = 2 (the widest candidate line's run count) * 2
  ;; (lines in the run) = 4.
  (is = 4 (table-cell-bound (format nil "|-|-|~%|-|-|~%"))))

(define-test table-cell-bound-cr-line-ends
  ;; Two lines, "|-|" (1 dash run) and "|-|-|" (2 dash runs), separated by a
  ;; bare CR. One run of 2 lines, widest is 2: bound = 2 * 2 = 4.
  (is = 4 (table-cell-bound (format nil "|-|~C|-|-|~C" #\Return #\Return))))

(define-test table-cell-bound-crlf-is-one-line-end
  ;; Two lines, "|-|" (1 dash run) and "|-|-|-|" (3 dash runs), joined by
  ;; CRLF. Treated as ONE line end, this is one run of 2 lines: bound =
  ;; 3 * 2 = 6. (Were CRLF split into two line ends, an empty line would
  ;; fall between them, breaking the run in two: 1*1 + 3*1 = 4 instead; and
  ;; if CR were not recognized as part of a line end at all, both lines
  ;; would carry a trailing CR, which isn't a candidate character, giving
  ;; 0*2 = 0. Either bug gives a different number from the correct 6.)
  (is = 6 (table-cell-bound
           (format nil "|-|~C~C|-|-|-|~C~C" #\Return #\Linefeed #\Return #\Linefeed))))

(define-test table-cell-bound-without-a-trailing-newline
  ;; One line, "|-|-|", with no line end at all: still closed at the end of
  ;; the string. Bound = 2 * 1 = 2.
  (is = 2 (table-cell-bound "|-|-|")))

(define-test table-cell-bound-blank-line-of-spaces-separates-runs
  ;; "|-|-|" (2 dash runs), then a blank line of spaces, then "|-|-|-|" (3
  ;; dash runs): two runs of one line each. Bound = 2*1 + 3*1 = 5.
  (is = 5 (table-cell-bound (format nil "|-|-|~%   ~%|-|-|-|~%"))))

(define-test table-cell-bound-blank-line-of-tabs-separates-runs
  ;; Same shape, with a tab-only blank line.
  (is = 5 (table-cell-bound (format nil "|-|-|~%~C~%|-|-|-|~%" #\Tab))))

(define-test table-cell-bound-empty-blank-line-separates-runs
  ;; "|-|" (1 dash run), an empty line, "|-|" (1 dash run): two runs of one
  ;; line each. Bound = 1*1 + 1*1 = 2.
  (is = 2 (table-cell-bound (format nil "|-|~%~%|-|~%"))))

(define-test table-cell-bound-container-prefixes
  ;; "> |-|-|" (a block-quote prefix; 2 dash runs) then "    |-|-|-|" (a
  ;; 4-space list-item indent; 3 dash runs): one run of 2 lines. Bound =
  ;; 3 (the widest) * 2 = 6.
  (is = 6 (table-cell-bound (format nil "> |-|-|~%    |-|-|-|~%"))))

(define-test table-cell-bound-vt-and-ff
  ;; Line 1, "|<VT>-<VT>|<FF>-<FF>|", has 2 dash runs and is a candidate.
  ;; Line 2, "<VT><FF><VT>", has no dash and is a candidate, but it is NOT
  ;; blank (IS-BLANK only treats space and tab as blank, not VT or FF), so
  ;; it stays in the same run instead of starting a new one. One run of 2
  ;; lines, widest is 2: bound = 2*2 = 4.
  (is = 4 (table-cell-bound
           (format nil "|~A-~A|~A-~A|~%~A~A~A~%" *vt* *vt* *ff* *ff* *vt* *ff* *vt*))))

(define-test table-cell-bound-several-rows-widest-not-first
  ;; Three lines in one run: "|-|-|" (2), "|-|-|-|-|" (4), "|-|" (1). The
  ;; widest is the middle line, neither first nor last. Bound = 4*3 = 12.
  (is = 12 (table-cell-bound (format nil "|-|-|~%|-|-|-|-|~%|-|~%"))))

(define-test table-cell-bound-counts-runs-not-individual-dashes
  ;; One line, "|-----|": a run of five dashes is ONE run, not five. Bound =
  ;; 1 (run) * 1 (line) = 1, not 5.
  (is = 1 (table-cell-bound (format nil "|-----|~%"))))

(define-test table-cell-bound-text-line-is-not-a-candidate
  ;; "|-|" (1 dash run, a candidate), then "a-b-c-d" (3 dash runs if merely
  ;; counted, but it holds letters, so it is NOT a candidate and must not
  ;; affect the widest-line count). One run of 2 lines; widest is 1 (line 1
  ;; alone). Bound = 1*2 = 2, not 3*2 = 6.
  (is = 2 (table-cell-bound (format nil "|-|~%a-b-c-d~%"))))

(define-test table-cell-bound-a-run-with-no-candidate-line-contributes-nothing
  (is = 0 (table-cell-bound (format nil "hello~%world~%"))))

;;; The output bounds' per-node terms (M2 design §5.5; M2b plan, Task 9)
;;;
;;; Every expected value is counted by hand from the C source the term
;;; reads (vendor/cmark-gfm), byte by byte, in the comment beside it. Each
;;; cmark_html_render_cr counts as the one newline it can write; "cr" below
;;; is that newline. These counts are made apart from the terms, which
;;; measure their own transcriptions of the C literals.

(define-test decimal-width-counts-what-printf-d-writes
  (is = 1 (decimal-width 0))
  (is = 1 (decimal-width 9))
  (is = 2 (decimal-width 10))
  (is = 3 (decimal-width 100))
  (is = 10 (decimal-width 2147483647))
  (is = 2 (decimal-width -1) "a minus sign")
  (is = 11 (decimal-width -2147483648)))

(define-test html-sourcepos-octets-counts-the-attribute
  ;; ` data-sourcepos="1:1-1:3"`: ` data-sourcepos="` is 17, then
  ;; `1:1-1:3` 7, then `"` 1 (cmark_html_render_sourcepos, src/html.h).
  (is = 25 (html-sourcepos-octets 1 1 1 3))
  ;; ` data-sourcepos="12:3--1:10"`: 17, `12:3--1:10` 10, `"` 1.
  (is = 28 (html-sourcepos-octets 12 3 -1 10)))

;;; HTML: the blocks (S_render_node, src/html.c)

(define-test html-block-quote-bound-counts-both-tags
  ;; cr, `<blockquote` 11, `>` LF 2; then cr, `</blockquote>` LF 14.
  (is = 29 (html-block-quote-bound 0))
  (is = 54 (html-block-quote-bound 25) "plus data-sourcepos"))

(define-test html-list-bound-counts-the-start-attribute
  ;; A bullet list, or an ordered list starting at 1: cr, `<ul` or `<ol`
  ;; 3, `>` LF 2; then `</ul>` LF or `</ol>` LF, 6.
  (is = 12 (html-list-bound :bullet 7 0) "a bullet list has no start")
  (is = 12 (html-list-bound :ordered 1 0))
  ;; Another start: cr, `<ol start="3"` 13, `>` LF 2, `</ol>` LF 6.
  (is = 22 (html-list-bound :ordered 3 0))
  (is = 22 (html-list-bound :ordered 0 0))
  ;; `<ol start="123456789"` is 21.
  (is = 30 (html-list-bound :ordered 123456789 0))
  (is = 37 (html-list-bound :ordered 1 25) "plus data-sourcepos"))

(define-test html-item-bound-counts-both-tags
  ;; cr, `<li` 3, `>` 1; then `</li>` LF 6.
  (is = 11 (html-item-bound 0))
  (is = 36 (html-item-bound 25)))

(define-test html-task-item-bound-counts-the-checkbox
  ;; tasklist.c's html_render: cr, `<li` 3, `>` 1, the checkbox, then
  ;; `</li>` LF 6. `<input type="checkbox" checked="" disabled="" /> ` is
  ;; 49; without ` checked=""`, 38.
  (is = 60 (html-task-item-bound t 0))
  (is = 49 (html-task-item-bound nil 0))
  (is = 85 (html-task-item-bound t 25)))

(define-test html-heading-bound-counts-both-tags
  ;; cr, `<h1` 3, `>` 1; then `</h1` 4, `>` LF 2.
  (is = 11 (html-heading-bound 0))
  (is = 36 (html-heading-bound 25)))

(define-test code-block-language-octets-stops-at-cmark-isspace
  ;; S_render_node writes the info string up to its first byte
  ;; cmark_isspace accepts: tab, LF, CR or space (src/cmark_ctype.c).
  (is = 0 (code-block-language-octets ""))
  (is = 4 (code-block-language-octets "ruby"))
  (is = 4 (code-block-language-octets "ruby startline=3"))
  (is = 4 (code-block-language-octets (format nil "ruby~Cx" #\Tab)))
  (is = 2 (code-block-language-octets (format nil "~C x" (code-char #xE9)))
      "U+00E9 is two octets")
  ;; A vertical tab or a form feed is not a space to cmark: `a`, VT, `b`.
  (is = 3 (code-block-language-octets (format nil "a~Cb c" (code-char 11))))
  (is = 3 (code-block-language-octets (format nil "a~Cb c" (code-char 12)))))

(define-test html-code-block-bound-escapes-language-and-literal
  ;; No info: cr, `<pre` 4, `><code>` 7, the literal escaped (5 octets, 6
  ;; each: 30), `</code></pre>` LF 14.
  (is = 56 (html-code-block-bound 0 0 5 0))
  ;; Info whose first word is 3 octets: cr, `<pre` 4,
  ;; `><code class="language-` 23, the word escaped (18), `">` 2, the
  ;; literal (30), 14. The rest of the info string isn't written.
  (is = 92 (html-code-block-bound 3 3 5 0))
  (is = 92 (html-code-block-bound 10 3 5 0))
  (is = 117 (html-code-block-bound 3 3 5 25)))

(define-test html-html-block-bound-follows-unsafe-and-tagfilter
  ;; cr, the content, cr. Without UNSAFE the content is
  ;; `<!-- raw HTML omitted -->`, 25.
  (is = 27 (html-html-block-bound 10 2 nil t))
  ;; UNSAFE, no filter: the literal, 10.
  (is = 12 (html-html-block-bound 10 2 t nil))
  ;; UNSAFE with tagfilter: filter_html_block writes each < as either < or
  ;; `&lt;`, 3 more, and every other byte once: 10 + 3 x 2.
  (is = 18 (html-html-block-bound 10 2 t t)))

(define-test html-thematic-break-bound-counts-the-tag
  ;; cr, `<hr` 3, ` />` LF 4.
  (is = 8 (html-thematic-break-bound 0))
  (is = 33 (html-thematic-break-bound 25)))

(define-test html-paragraph-bound-writes-nothing-when-tight
  ;; cr, `<p` 2, `>` 1; then `</p>` LF 5.
  (is = 9 (html-paragraph-bound nil 0))
  (is = 34 (html-paragraph-bound nil 25))
  (is = 0 (html-paragraph-bound t 25) "a tight list's paragraph writes no tags"))

;;; HTML: the inlines

(define-test html-text-bound-escapes-every-octet-as-quot
  ;; escape_html: `"` becomes `&quot;`, 6, the longest of its escapes.
  (is = 30 (html-text-bound 5))
  (is = 0 (html-text-bound 0)))

(define-test html-softbreak-bound-follows-the-softbreak-option
  ;; HARDBREAKS: `<br />` LF, 7. NOBREAKS: a space. Otherwise LF.
  (is = 1 (html-softbreak-bound :newline))
  (is = 1 (html-softbreak-bound :space))
  (is = 7 (html-softbreak-bound :br)))

(define-test html-linebreak-bound-counts-the-br
  (is = 7 (html-linebreak-bound)))

(define-test html-code-bound-counts-tags-and-escapes
  ;; `<code>` 6, the literal (5 x 6), `</code>` 7.
  (is = 43 (html-code-bound 5)))

(define-test html-html-inline-bound-follows-unsafe-tagfilter-and-alt-text
  ;; Without UNSAFE: `<!-- raw HTML omitted -->`, 25.
  (is = 25 (html-html-inline-bound 10 nil nil nil))
  ;; UNSAFE: the literal; filtered, `&lt;` then all but its first byte.
  (is = 10 (html-html-inline-bound 10 t nil nil))
  (is = 13 (html-html-inline-bound 10 t t nil))
  ;; Inside an image's alt text, escape_html of the literal, whatever the
  ;; options: 10 x 6.
  (is = 60 (html-html-inline-bound 10 t t t))
  (is = 60 (html-html-inline-bound 10 nil nil t)))

(define-test html-emphasis-bounds-count-their-tags
  ;; `<em>` 4 and `</em>` 5; `<strong>` 8 and `</strong>` 9, but nothing
  ;; for a strong directly inside a strong; `<del>` 5 and `</del>` 6
  ;; (strikethrough.c's html_render).
  (is = 9 (html-emph-bound))
  (is = 17 (html-strong-bound nil))
  (is = 0 (html-strong-bound t))
  (is = 11 (html-strikethrough-bound)))

(define-test html-link-bound-escapes-destination-and-title
  ;; `<a href="` 9, the destination (4 octets; houdini_escape_href's longest
  ;; escape, ' to `&#x27;`, is 6: 24), `">` 2, `</a>` 4.
  (is = 39 (html-link-bound 4 0))
  ;; A title adds `" title="` 9 and its escape (2 x 6).
  (is = 60 (html-link-bound 4 2)))

(define-test html-image-bound-escapes-source-and-title
  ;; `<img src="` 10, the source (24), `" alt="` 7, then `" />` 4.
  (is = 45 (html-image-bound 4 0))
  (is = 66 (html-image-bound 4 2)))

;;; HTML: tables (extensions/table.c's html_render)

(define-test html-table-bounds-count-every-tag
  ;; The table: cr, `<table` 6, `>` 1; the `<tbody>` and cr its first body
  ;; row writes, 8; then cr, `</tbody>` 8, cr, cr, `</table>` 8, cr.
  (is = 36 (html-table-bound 0))
  ;; The header row: cr, `<thead>` 7, cr, `<tr` 3, `>` 1; then cr, `</tr>`
  ;; 5, cr, `</thead>` 8.
  (is = 28 (html-table-header-bound 0))
  ;; A body row: cr, `<tr` 3, `>` 1; then cr, `</tr>` 5.
  (is = 11 (html-table-row-bound 0))
  ;; A cell: cr, `<td` 3, its alignment, `>` 1, then `</td>` 5. The
  ;; alignment is ` align="` 8, the word, `"` 1.
  (is = 10 (html-table-cell-bound nil 0))
  (is = 23 (html-table-cell-bound :left 0))
  (is = 25 (html-table-cell-bound :center 0))
  (is = 24 (html-table-cell-bound :right 0))
  (is = 50 (html-table-cell-bound :center 25)))

;;; HTML: footnotes (S_render_node, S_put_footnote_backref and
;;; cmark_render_html, src/html.c)

(define-test html-footnote-definition-bound-counts-its-label-and-first-backref
  ;; A definition labelled "a", the first rendered:
  ;; `<li id="fn-` 11, the label (6), `">` LF 3;
  ;; the backref: `<a href="#fnref-` 16, the label (6),
  ;; `" class="footnote-backref" data-footnote-backref data-footnote-backref-idx="`
  ;; 76, `1`, `" aria-label="Back to reference ` 32, `1`, `">` 2, U+21A9
  ;; in 3, `</a>` 4;
  ;; the space before the backref or the newline after it, counted both: 2;
  ;; `</li>` LF 6.
  ;; 20 + 141 + 2 + 6.
  (is = 169 (html-footnote-definition-bound 1 1))
  ;; A 3-octet label and number 12: two more label octets in each of the
  ;; label's two places (24), and a second digit in each of the number's
  ;; two (2).
  (is = 195 (html-footnote-definition-bound 3 12)))

(define-test html-footnote-reference-bound-counts-its-label-twice
  ;; `<sup class="footnote-ref"><a href="#fn-` 39, the label (6),
  ;; `" id="fnref-` 12, the label (6), the suffix, `" data-footnote-ref>`
  ;; 20, the number (1, digits are href-safe), `</a></sup>` 10.
  (is = 94 (html-footnote-reference-bound 1 1 0))
  (is = 97 (html-footnote-reference-bound 1 1 3) "with a 3-octet suffix, -12"))

(define-test html-footnote-backref-bound-counts-a-repeat-backref
  ;; The second backref of definition 1, labelled "a":
  ;; ` <a href="#fnref-` 17, the label (6), `-2` 2, the idx
  ;; attribute's 76, `1-2` 3, the aria-label's 32, `1-2` 3, `">` 2, U+21A9
  ;; in 3, `<sup class="footnote-ref">` 26, `2` 1, `</sup></a>` 10.
  (is = 181 (html-footnote-backref-bound 1 2 1))
  ;; Label 3 octets, backref 4 of definition 2: 18 for the label.
  (is = 193 (html-footnote-backref-bound 3 4 2)))

(define-test html-footnote-section-bound-counts-both-ends
  ;; `<section class="footnotes" data-footnotes>` 42, LF, `<ol>` 4, LF;
  ;; then `</ol>` LF `</section>` LF, 17.
  (is = 65 (html-footnote-section-bound)))

(define-test html-footnote-suffix-bound-allows-for-unseen-references
  ;; As many candidates as definitions: every definition has its one
  ;; reference, and no reference is the second of its definition.
  (is = 0 (html-footnote-suffix-bound 3 3))
  ;; One candidate more: a definition can have 2, so a suffix `-2`.
  (is = 2 (html-footnote-suffix-bound 4 3))
  ;; 12 candidates, 2 definitions: up to 11 on one, `-11`.
  (is = 3 (html-footnote-suffix-bound 12 2)))

(define-test html-footnote-backrefs-bound-counts-every-repeat-backref
  ;; Each candidate past one per definition can be a repeat reference, and
  ;; each repeat reference makes one more backref: 5 candidates and 2
  ;; definitions allow 3, each at most the largest one, backref 4 of
  ;; definition 2 with the longest label, 3 octets: 193.
  (is = 579 (html-footnote-backrefs-bound 5 2 3))
  (is = 0 (html-footnote-backrefs-bound 1 1 5) "no repeat reference")
  ;; 12 candidates, 2 definitions, label 1: 10 backrefs of index up to 11,
  ;; each 169 + 6 + 4 x 2 + 2 x 1.
  (is = 1850 (html-footnote-backrefs-bound 12 2 1)))

(define-test footnote-reference-bound-counts-each-bracket-a-reference-can-open
  ;; A reference opens at [ followed by ^, or by \^ or an entity that
  ;; decodes to ^ (handle_close_bracket, src/inlines.c).
  (is = 0 (footnote-reference-bound ""))
  (is = 0 (footnote-reference-bound "["))
  (is = 2 (footnote-reference-bound "[^a] [^b]"))
  (is = 1 (footnote-reference-bound "[^"))
  (is = 1 (footnote-reference-bound "[\\^a]") "a backslash escape")
  (is = 1 (footnote-reference-bound "[&#94;a]") "an entity")
  (is = 1 (footnote-reference-bound "![^a]") "an image's bracket")
  (is = 0 (footnote-reference-bound "[a](b) [b] ^[c]") "brackets no reference opens"))

;;; Plaintext (S_render_node, src/plaintext.c; S_out, src/render.c)

(define-test plaintext-item-marker-width-is-the-marker-and-the-prefix-it-adds
  ;; A bullet: `  - `. Ordered, "%d%s%s": the number, `.` or `)`, and two
  ;; spaces below 10, one from 10.
  (is = 4 (plaintext-item-marker-width :bullet 7))
  (is = 4 (plaintext-item-marker-width :ordered 1) "`1.  `")
  (is = 4 (plaintext-item-marker-width :ordered 9))
  (is = 4 (plaintext-item-marker-width :ordered 10) "`10. `")
  (is = 5 (plaintext-item-marker-width :ordered 123) "`123. `")
  (is = 12 (plaintext-item-marker-width :ordered 1000000000)))

(define-test plaintext-prefix-width-is-what-each-container-adds
  ;; An item adds its marker's width (S_render_node, src/plaintext.c); a
  ;; task item "  " (tasklist.c's commonmark_render), whatever its list; a
  ;; footnote definition "    "; a block quote nothing.
  (is = 5 (plaintext-prefix-width :item 5))
  (is = 2 (plaintext-prefix-width :task-item 4))
  (is = 4 (plaintext-prefix-width :footnote-definition 0))
  (is = 0 (plaintext-prefix-width :block-quote 0))
  (is = 0 (plaintext-prefix-width :list 0)))

(define-test plaintext-out-bound-counts-one-s-out-call
  ;; Its own octets.
  (is = 5 (plaintext-out-bound 5 4 nil))
  ;; A pending newline request: two newlines and the prefix, then the
  ;; prefix again at the start of the line its first byte begins.
  (is = 15 (plaintext-out-bound 5 4 t))
  ;; Wrapping: each space can start a line, so it can cost the prefix.
  (is = 13 (plaintext-out-bound 5 4 nil :spaces 2 :wrap t))
  (is = 5 (plaintext-out-bound 5 4 nil :spaces 2) "no wrapping, no cost")
  ;; Each newline of a literal starts a line, with the prefix.
  (is = 17 (plaintext-out-bound 5 4 nil :newlines 3))
  ;; A table's escape writes a backslash before each pipe.
  (is = 7 (plaintext-out-bound 5 4 nil :escapes 2)))

(defun plaintext-event-bound (event kind prefix pending &rest facts)
  "(PLAINTEXT-STEPS-BOUND (PLAINTEXT-EVENT-STEPS EVENT KIND FACTS...) PREFIX
PENDING), its two values as a list: the octets, and whether a newline
request is left pending."
  (multiple-value-list
   (plaintext-steps-bound (apply #'plaintext-event-steps event kind facts) prefix pending)))

(define-test plaintext-event-steps-of-items
  ;; An item writes its marker with its parent's prefix: here a pending
  ;; blank line first, LF, 8 spaces, LF, then 8 spaces and `  - `.
  (is equal '(22 nil) (plaintext-event-bound :enter :item 8 t :marker-width 4))
  ;; Leaving, it asks for a newline (CR).
  (is equal '(0 t) (plaintext-event-bound :exit :item 8 nil))
  ;; tasklist.c's commonmark_render: CR, then `- [x] ` or `- [ ] `, 6.
  (is equal '(16 nil) (plaintext-event-bound :enter :task-item 4 nil))
  (is equal '(0 t) (plaintext-event-bound :exit :task-item 4 nil)))

(define-test plaintext-event-steps-of-blocks
  ;; A code block: BLANKLINE, its literal (10 octets, 2 newlines, each
  ;; then followed by the prefix), BLANKLINE.
  (is equal '(28 t) (plaintext-event-bound :enter :code-block 4 nil :octets 10 :newlines 2))
  ;; Paragraphs, headings and lists ask for a newline when they end;
  ;; thematic breaks and tables when they start, and tables again when
  ;; they end.
  (is equal '(0 nil) (plaintext-event-bound :enter :paragraph 4 nil))
  (is equal '(0 t) (plaintext-event-bound :exit :paragraph 4 nil))
  (is equal '(0 t) (plaintext-event-bound :exit :heading 4 nil))
  (is equal '(0 t) (plaintext-event-bound :exit :list 4 nil))
  (is equal '(0 t) (plaintext-event-bound :enter :thematic-break 4 nil))
  (is equal '(0 t) (plaintext-event-bound :enter :table 4 nil))
  (is equal '(0 t) (plaintext-event-bound :exit :table 4 nil))
  ;; Block quotes and raw HTML write nothing, and leave a request as it was.
  (is equal '(0 t) (plaintext-event-bound :enter :block-quote 4 t))
  (is equal '(0 nil) (plaintext-event-bound :enter :html-block 4 nil)))

(define-test plaintext-event-steps-of-inlines
  ;; Text: its octets, and the prefix for each space under wrapping.
  (is equal '(9 nil) (plaintext-event-bound :enter :text 4 nil :octets 5 :spaces 1 :wrap t))
  (is equal '(7 nil) (plaintext-event-bound :enter :code 4 nil :octets 5 :escapes 2))
  ;; A softbreak is a CR or a space: counted as both.
  (is equal '(11 nil) (plaintext-event-bound :enter :softbreak 4 nil))
  (is equal '(15 nil) (plaintext-event-bound :enter :softbreak 4 nil :wrap t))
  (is equal '(0 t) (plaintext-event-bound :enter :linebreak 4 nil))
  ;; `[^`, the number, `]`: with a pending request, 2 + 2 + 1 + 1.
  (is equal '(6 nil) (plaintext-event-bound :enter :footnote-reference 0 t :octets 1))
  ;; `[^`, the definition's index, 12, then `]: `.
  (is equal '(9 nil) (plaintext-event-bound :enter :footnote-definition 0 t :number 12))
  ;; strikethrough.c's plaintext_render: `~` on entering and on leaving.
  (is equal '(1 nil) (plaintext-event-bound :enter :strikethrough 0 nil))
  (is equal '(1 nil) (plaintext-event-bound :exit :strikethrough 0 nil))
  (is equal '(0 nil) (plaintext-event-bound :enter :emph 0 nil)))

(define-test plaintext-event-steps-of-tables
  ;; table.c's commonmark_render. A row: CR, `|`.
  (is equal '(7 nil) (plaintext-event-bound :enter :table-header 2 nil))
  (is equal '(3 nil) (plaintext-event-bound :enter :table-row 0 nil))
  ;; A cell: ` ` entering, ` |` leaving.
  (is equal '(1 nil) (plaintext-event-bound :enter :table-cell 0 nil))
  (is equal '(2 nil) (plaintext-event-bound :exit :table-cell 0 nil))
  ;; After the header's last cell: CR, `|`, ` --- |` (6) per column, CR.
  (is equal '(21 t) (plaintext-event-bound :exit :table-header 0 nil :columns 3)))

;;;; FOOTNOTE-ENTITY-INDEX: the input guard's scan (M2 design §5.6; finding
;;;; 16; M2b plan Task 9b). Every form is confirmed against
;;;; vendor/cmark-gfm/src/houdini_html_u.c's grammar, not run through cmark
;;;; itself: this system is pure.

;;; The seven forms that decode to ^ (U+005E, 94)

(define-test footnote-entity-index-decimal-forms
  (is = 0 (footnote-entity-index "[&#94;a]"))
  (is = 0 (footnote-entity-index "[&#094;a]") "a leading zero")
  (is = 0 (footnote-entity-index "[&#00000094;a]")
      "8 digits, the maximum, all leading zeros but the value"))

(define-test footnote-entity-index-hex-forms
  (is = 0 (footnote-entity-index "[&#x5e;a]"))
  (is = 0 (footnote-entity-index "[&#X5E;a]") "the x/X and the digits can each be either case")
  (is = 0 (footnote-entity-index "[&#x0000005E;a]") "8 hex digits, the maximum"))

(define-test footnote-entity-index-named-form
  (is = 0 (footnote-entity-index "[&Hat;a]")))

;;; Near misses: houdini_unescape_ent's grammar, just missed

(define-test footnote-entity-index-near-misses-return-nil
  (false (footnote-entity-index "[&#000000094;a]") "9 digits, one past the 8-digit maximum")
  (false (footnote-entity-index "[&#94a]") "no closing ;")
  (false (footnote-entity-index "[&hat;a]") "lowercase: not an entity at all")
  (false (footnote-entity-index "[&#95;a]") "the wrong codepoint")
  (false (footnote-entity-index "[&#x;a]") "no hex digits at all")
  (false (footnote-entity-index "[&#;a]") "no decimal digits at all")
  (false (footnote-entity-index "[ &#94;a]") "a space between the [ and the &")
  (false (footnote-entity-index "&#94;a") "no [ at all")
  (false (footnote-entity-index "") "the empty string"))

;;; Near misses: non-ASCII digits. houdini.h's _isdigit and _isxdigit are
;;; ASCII-only (<ctype.h> semantics, never HOUDINI_USE_LOCALE here);
;;; DIGIT-CHAR-P accepts Unicode decimal digits too on SBCL, so these three
;;; must still return NIL, or the guard would reject input cmark itself
;;; parses as ordinary text (M2b review p4).

(define-test footnote-entity-index-near-misses-reject-non-ascii-digits
  (false (footnote-entity-index (format nil "[&#~C4;a]" (code-char #x0669)))
         "ARABIC-INDIC DIGIT NINE then 4 is not two ASCII digits")
  (false (footnote-entity-index (format nil "[&#~C~C;a]" (code-char #xFF19) (code-char #xFF14)))
         "FULLWIDTH DIGIT NINE then FULLWIDTH DIGIT FOUR: neither is ASCII")
  (false (footnote-entity-index (format nil "[&#9~C;a]" (code-char #x0664)))
         "9 then ARABIC-INDIC DIGIT FOUR: one non-ASCII digit still misses"))

;;; The first of two matches, and the index returned

(define-test footnote-entity-index-returns-the-first-match
  (is = 3 (footnote-entity-index "abc[&#94;x] [&Hat;y]")))

;;;; VERSION-NUMBER and NUMBER-VERSION: the version cross-check's pure half
;;;; (M3 design §5; M3 plan Task 1). Startup's step 4
;;;; (tests/native/startup.lisp) uses both to check cmark_version()'s number
;;;; against *CMARK-GFM-VERSION*, on top of M2's cmark_version_string check.

(defun version-error-signalled (thunk)
  "Call THUNK. Return the SIMPLE-ERROR it signals, or NIL. Narrower than
generic ERROR on purpose: before VERSION-NUMBER or NUMBER-VERSION exists,
calling either signals UNDEFINED-FUNCTION, itself a subtype of ERROR, which
would otherwise make a bad-input test pass for the wrong reason."
  (handler-case (progn (funcall thunk) nil)
    (simple-error (condition) condition)))

(define-test version-number-of-the-pin
  (is = #x001D000D (version-number *cmark-gfm-version*)))

(define-test number-version-of-the-pin
  (is string= *cmark-gfm-version* (number-version #x001D000D)))

(define-test version-number-and-number-version-round-trip
  (dolist (string '("0.0.0.gfm.0" "1.2.3.gfm.4" "255.255.255.gfm.255"))
    (is string= string (number-version (version-number string))
        "~S should round-trip" string)))

(define-test version-number-rejects-malformed-strings
  (dolist (string (list "0.29.0" "0.29.0.gfm" "a.29.0.gfm.13" "0.256.0.gfm.1" ""
                        "0.29.0.gfm.13 "))
    (true (version-error-signalled (lambda () (version-number string)))
          "~S should signal" string)))

(define-test number-version-rejects-out-of-range-numbers
  (dolist (number (list -1 #x100000000))
    (true (version-error-signalled (lambda () (number-version number)))
          "~S should signal" number)))
