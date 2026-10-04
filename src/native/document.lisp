;;;; Native documents (M2 design §5.4; ADR-0008; chez-cmark-gfm ADR-0005
;;;; and ADR-0006). A native document owns one cmark parser and the root it
;;;; finished, together: the parser owns the extension list the HTML
;;;; renderer is given, so it must outlive rendering. WITH-NATIVE-DOCUMENT
;;;; creates both, runs its body, and frees both exactly once, however the
;;;; body exits. Every accessor checks the document's alive flag first, so a
;;;; document used after its scope signals instead of touching freed memory.
;;;; A document parsed under the published state holds that state until it
;;;; is released, so cmark-gfm is never closed under it (M2 design §5.3).
;;;; Strings come back from cmark copied whole and decoded by DECODE-UTF8,
;;;; with U+FFFD for any ill-formed byte (M2 design §6.5).
;;;;
;;;; Every call into cmark runs with interrupts deferred (M2 design §5.4,
;;;; finding 21), and so does recording what it created or freed: a parser
;;;; or a root is in the document, and counted, by the time an interrupt can
;;;; land, and the release runs deferred from its first step to its last.

(in-package #:cl-commonmark-gfm.native)

;;; The state a document runs under

(defstruct (native-state
            (:conc-name state-)
            (:constructor make-native-state (core-library extensions-library paths))
            (:copier nil))
  "What startup found (M2 design §5.2): the two library objects
CFFI:LOAD-FOREIGN-LIBRARY returned, the two PATHS they were loaded from,
the VERSION cmark reported, the EXTENSIONS, an alist from each of
*EXTENSION-KEYWORDS* to cmark's pointer for that syntax extension, and
FREE, the default allocator's free."
  core-library
  extensions-library
  paths
  (version nil)
  (extensions '())
  (free nil))

(defun state-extension (state keyword)
  "STATE's pointer for the syntax extension KEYWORD names."
  (cdr (assoc keyword (state-extensions state))))

;;; The document and its alive flag (M2 design §5.4, D13)

(defstruct (native-document
            (:conc-name document-)
            (:constructor make-native-document (state parse-bits))
            (:copier nil))
  "One parse under STATE, with PARSE-BITS: cmark's PARSER and the ROOT it
finished, owned together. ALIVE is true from the moment the root exists
until the release begins; every accessor checks it."
  state
  parse-bits
  (parser nil)
  (root nil)
  (alive nil))

(define-condition native-document-released (error)
  ((operation :reader released-operation
              :initarg :operation
              :initform nil
              :documentation "The accessor that was called on the released document."))
  (:report (lambda (condition stream)
             (format stream "~(~A~): a native document was used after its release"
                     (released-operation condition))))
  (:documentation
   "Signalled when a native accessor is given a document whose
WITH-NATIVE-DOCUMENT scope has ended (M2 design §5.4, D13). Internal and
unexported: no caller of the public API ever holds a native document, so
this always means a bug in cl-commonmark-gfm itself."))

(defun check-alive (document operation)
  "Signal NATIVE-DOCUMENT-RELEASED, naming OPERATION, unless DOCUMENT is
alive."
  (unless (document-alive document)
    (error 'native-document-released :operation operation)))

;;; The finish lock (M2 design §5.4 step 4, §7.5; finding 14)

(defvar *finish-lock* (bt2:make-lock :name "cl-commonmark-gfm finish")
  "Held around the one call to cmark_parser_finish, in %PARSER-FINISH, and
nothing else. That call is the only one that parses inlines
(finalize_document, then process_inlines, src/blocks.c), and
process_inlines adds the attached extensions' special characters to two
process-wide tables, SPECIAL_CHARS and SKIP_CHARS
(cmark_inlines_add_special_character, src/inlines.c), then removes them
when it is done. Two finishes at once corrupt each other's inlines. Lock
order: startup's smoke parse takes this lock while holding *STARTUP-LOCK*;
nothing takes *STARTUP-LOCK* while holding this one (M2 design §5.2). A
thread waits for it with interrupts deferred, so a timeout waits until it
gets the lock and the call returns (M2 design §11).")

;;; Wrappers a test can redefine. CLHS 3.2.2.3 lets a compiler assume that
;;; a call to a function defined in the same file refers to that very
;;; definition unless the function is declared NOTINLINE, so these are.

(declaim (notinline %parser-new %parser-finish free-root))

(defun %parser-new (parse-bits)
  "Call cmark_parser_new with PARSE-BITS, with interrupts deferred. It can
return null, in principle."
  (with-interrupts-deferred
    (cmark-parser-new parse-bits)))

(defun %parser-finish (parser)
  "Call cmark_parser_finish on PARSER, holding *FINISH-LOCK*, and return
its root or null. The one call to cmark_parser_finish: the only cmark call
that parses inlines (M2 design §5.4 step 4, finding 14). Interrupts are
deferred from the wait for the lock until its release."
  (with-interrupts-deferred
    (bt2:with-lock-held (*finish-lock*)
      (cmark-parser-finish parser))))

;;; Creating and freeing, each with its count (M2 design §5.4)

(defun open-parser (document)
  "Create a cmark parser for DOCUMENT's parse bits, and keep it in
DOCUMENT, counted as open. Interrupts are deferred from the call until the
parser is kept, so no interrupt can lose it. A null parser signals
NATIVE-PARSE-ERROR (M2 design §5.4 step 1)."
  (unless (with-interrupts-deferred
            (let ((parser (%parser-new (document-parse-bits document))))
              (unless (cffi:null-pointer-p parser)
                (note-parser-created)
                (setf (document-parser document) parser))))
    (error 'native-parse-error
           :operation 'with-native-document
           :datum (document-parse-bits document)
           :reason "cmark_parser_new returned no parser")))

(defun free-parser (parser)
  "Free PARSER, and count it closed, with interrupts deferred."
  (with-interrupts-deferred
    (cmark-parser-free parser)
    (note-parser-freed)))

(defun free-root (root)
  "Free ROOT and every node under it, and count it closed, with interrupts
deferred."
  (with-interrupts-deferred
    (cmark-node-free root)
    (note-root-freed)))

;;; Parsing into a document (M2 design §5.4 steps 1 to 4)

(defun encode-input (string)
  "STRING's UTF-8 octets, in a fresh vector CFFI can pin for a foreign call.
A lone surrogate becomes U+FFFD (M2 design §6.5)."
  (let ((octets (cffi:make-shareable-byte-vector (utf8-length string))))
    (encode-utf8 string octets)
    octets))

(defun feed-parser (parser octets)
  "Feed OCTETS to PARSER in one cmark_parser_feed call, with interrupts
deferred, pinning OCTETS for that call only: cmark copies whatever it
keeps (S_parser_feed, src/blocks.c)."
  (with-interrupts-deferred
    (cffi:with-pointer-to-vector-data (pointer octets)
      (cmark-parser-feed parser pointer (length octets)))))

(defun attach-extensions (document extensions)
  "Attach each syntax extension of EXTENSIONS, a list of keywords, to
DOCUMENT's parser, each call with interrupts deferred: it allocates.
cmark_parser_attach_syntax_extension always returns 1 (src/blocks.c; M2
design finding 10), so there is nothing to check."
  (let ((state (document-state document))
        (parser (document-parser document)))
    (dolist (keyword extensions)
      (let ((extension (state-extension state keyword)))
        (with-interrupts-deferred
          (cmark-parser-attach-syntax-extension parser extension))))))

(defun finish-document (document)
  "Finish DOCUMENT's parse, and keep the root in DOCUMENT, counted as open.
Interrupts are deferred from the call until the root is kept, so no
interrupt can lose it. A null root signals NATIVE-PARSE-ERROR (M2 design
§5.4 step 4)."
  (unless (with-interrupts-deferred
            (let ((root (%parser-finish (document-parser document))))
              (unless (cffi:null-pointer-p root)
                (note-root-created)
                (setf (document-root document) root))))
    (error 'native-parse-error
           :operation 'with-native-document
           :reason "cmark_parser_finish returned no root")))

(defun parse-into-document (document string extensions)
  "Parse STRING into DOCUMENT with EXTENSIONS attached, and mark DOCUMENT
alive (M2 design §5.4 steps 1 to 4). The input is encoded before the
parser exists, and its octets are garbage once fed."
  (let ((octets (encode-input string)))
    (open-parser document)
    (attach-extensions document extensions)
    (feed-parser (document-parser document) octets))
  (finish-document document)
  (setf (document-alive document) t))

(defun release-document (document)
  "Clear DOCUMENT's alive flag, then free its root and then its parser,
each at most once: a second release frees nothing. A failure freeing the
root still frees the parser (M2 design §5.4 step 6). Runs with interrupts
deferred throughout, so no interrupt can stop it between taking a pointer
out of DOCUMENT and freeing it."
  (with-interrupts-deferred
    (setf (document-alive document) nil)
    (let ((root (document-root document))
          (parser (document-parser document)))
      (setf (document-root document) nil
            (document-parser document) nil)
      (unwind-protect
           (when root
             (free-root root))
        (when parser
          (free-parser parser))))))

(defun call-with-parsed-document (function string checked-options state)
  "Parse STRING under STATE, call FUNCTION with the live document, and
release it however FUNCTION exits. The release runs with interrupts
deferred from the moment FUNCTION is left, by UNWIND-PROTECT-DEFERRED, so
an interrupt can neither skip it nor cut it short; the parse and FUNCTION
stay interruptible between cmark calls (M2 design §5.4)."
  (let ((document (make-native-document state (parse-option-bits checked-options))))
    (unwind-protect-deferred
        (progn
          (parse-into-document document string (checked-extensions checked-options))
          (funcall function document))
      (release-document document))))

(defun invoke-with-native-document (function string checked-options state)
  "The function behind WITH-NATIVE-DOCUMENT: CALL-WITH-PARSED-DOCUMENT
under STATE, or, when STATE is NIL, under the published state, held for
the document's whole life by CALL-WITH-NATIVE-STATE (M2 design §5.3)."
  (if state
      (call-with-parsed-document function string checked-options state)
      (call-with-native-state
       (lambda (published)
         (call-with-parsed-document function string checked-options published)))))

(defmacro with-native-document ((document string checked-options &key state) &body body)
  "Parse STRING with CHECKED-OPTIONS' parse bits and extensions, and run
BODY with DOCUMENT bound to the live native document (M2 design §5.4):

1. cmark_parser_new with the parse bits; a null signals NATIVE-PARSE-ERROR;
2. attach the selected extensions;
3. feed STRING's UTF-8 octets in one call, from a vector pinned for that
   call only;
4. cmark_parser_finish; a null root signals NATIVE-PARSE-ERROR;
5. run BODY;
6. on any exit: clear the alive flag, then free the root, then the parser,
   each exactly once.

STATE is the native state to parse under: one a caller holds, by
WITH-NATIVE-STATE, or startup's own, which it hasn't published yet. When
STATE is NIL, the published state is used, after starting up when none is
published, and held until the document is released, so it can't be
closed under the parse (M2 design §5.3). Returns BODY's values."
  `(invoke-with-native-document (lambda (,document) ,@body) ,string ,checked-options ,state))

;;; The accessors (M2 design §5.1). Each takes the document and a node of
;;; its tree, checks the alive flag, then asks cmark, with interrupts
;;; deferred during each call: cmark_chunk_to_cstr, behind the string
;;; accessors, can allocate (src/chunk.h).

(defmacro define-node-accessor (name (document node) documentation &body body)
  "Define NAME as a function of DOCUMENT and NODE that checks DOCUMENT's
alive flag, naming NAME, before running BODY."
  `(defun ,name (,document ,node)
     ,documentation
     (check-alive ,document ',name)
     ,@body))

(defun native-root (document)
  "DOCUMENT's root: the :DOCUMENT node cmark_parser_finish returned."
  (check-alive document 'native-root)
  (document-root document))

(defun node-or-nil (pointer)
  "POINTER, a node pointer cmark returned, or NIL when it is null."
  (if (cffi:null-pointer-p pointer) nil pointer))

(defun foreign-octets (pointer)
  "The bytes of the NUL-terminated C string at POINTER, its NUL left out,
copied into a fresh octet vector: one strlen, then one memcpy into the
vector, pinned for that call, never a foreign read per byte. Both calls
run with interrupts deferred."
  (with-interrupts-deferred
    (let* ((count (cffi:foreign-funcall "strlen" :pointer pointer :size))
           (octets (cffi:make-shareable-byte-vector count)))
      (when (plusp count)
        (cffi:with-pointer-to-vector-data (destination octets)
          (cffi:foreign-funcall "memcpy" :pointer destination :pointer pointer :size count
                                         :pointer)))
      octets)))

(defun foreign-utf8-string (pointer)
  "The NUL-terminated string at POINTER, decoded from UTF-8 by DECODE-UTF8
into a fresh Lisp string, and as a second value the octets it held. cmark
can write bytes that aren't UTF-8: a dangling footnote reference's label
cut inside a character (M2 design finding 19). Each ill-formed sequence
becomes U+FFFD, one for each maximal subpart (M2 design §6.5)."
  (let ((octets (foreign-octets pointer)))
    (values (decode-utf8 octets) (length octets))))

(defun borrowed-string (pointer operation)
  "The string cmark lent at POINTER, copied into a fresh Lisp string by
FOREIGN-UTF8-STRING. Never freed here: cmark owns it. A null signals
NATIVE-PARSE-ERROR naming OPERATION: the string accessors are only called
on the kinds they serve, where cmark_chunk_to_cstr (src/chunk.h) never
returns null (M2 design §5.1)."
  (when (cffi:null-pointer-p pointer)
    (error 'native-parse-error
           :operation operation
           :reason "cmark returned a null string"))
  (values (foreign-utf8-string pointer)))

(define-node-accessor native-first-child (document node)
  "NODE's first child, or NIL when it has none."
  (node-or-nil (with-interrupts-deferred (cmark-node-first-child node))))

(define-node-accessor native-next (document node)
  "NODE's next sibling, or NIL when it is the last."
  (node-or-nil (with-interrupts-deferred (cmark-node-next node))))

(define-node-accessor native-parent (document node)
  "NODE's parent, or NIL for the root."
  (node-or-nil (with-interrupts-deferred (cmark-node-parent node))))

(define-node-accessor native-type (document node)
  "NODE's cmark_node_type, an integer. A table node's comes from the table
extension, assigned when it registered."
  (with-interrupts-deferred (cmark-node-get-type node)))

(define-node-accessor native-type-string (document node)
  "NODE's type string, as cmark's XML renderer names its element: from its
extension when it has one, \"<unknown>\" for a footnote node
(cmark_node_get_type_string, src/node.c)."
  (borrowed-string (with-interrupts-deferred (cmark-node-get-type-string node))
                   'native-type-string))

(define-node-accessor native-extension (document node)
  "Which of the state's five syntax extensions NODE carries: :TABLE,
:STRIKETHROUGH, :AUTOLINK, :TAGFILTER or :TASKLIST; NIL when it carries
none; :OTHER when it carries some other one (M2 design §6.2)."
  (let ((extension (with-interrupts-deferred (cmark-node-get-syntax-extension node))))
    (if (cffi:null-pointer-p extension)
        nil
        (or (car (find extension (state-extensions (document-state document))
                       :key #'cdr :test #'cffi:pointer-eq))
            :other))))

(define-node-accessor native-kind (document node)
  "NODE's AST vocabulary kind, by CLASSIFY-NODE (M2 design §6.2; ADR-0008).
CLASSIFY-NODE decides a node with no extension by its type code alone, so
the type string, three foreign calls and a string, is read only for a node
with an extension: under ECL's dynamic FFI, every foreign call looks its
function up first (M4 design §5.7)."
  (let ((type (native-type document node))
        (extension (native-extension document node)))
    (classify-node type extension (and extension (native-type-string document node)))))

(define-node-accessor native-literal (document node)
  "NODE's literal: the text of a :TEXT, :CODE, :CODE-BLOCK, :HTML-BLOCK or
:HTML-INLINE; a footnote definition's label as written; a footnote
reference's number (M2 design finding 6)."
  (borrowed-string (with-interrupts-deferred (cmark-node-get-literal node)) 'native-literal))

(define-node-accessor native-url (document node)
  "A link's or an image's destination."
  (borrowed-string (with-interrupts-deferred (cmark-node-get-url node)) 'native-url))

(define-node-accessor native-title (document node)
  "A link's or an image's title, empty when it has none."
  (borrowed-string (with-interrupts-deferred (cmark-node-get-title node)) 'native-title))

(define-node-accessor native-fence-info (document node)
  "A code block's info string, empty when it has none."
  (borrowed-string (with-interrupts-deferred (cmark-node-get-fence-info node))
                   'native-fence-info))

(define-node-accessor native-heading-level (document node)
  "A heading's level, from 1 to 6."
  (with-interrupts-deferred (cmark-node-get-heading-level node)))

(define-node-accessor native-list-type (document node)
  "A list's type, :BULLET or :ORDERED; NIL for a node that isn't a list
(CMARK_NO_LIST)."
  (let ((type (with-interrupts-deferred (cmark-node-get-list-type node))))
    (cond
      ((= type +cmark-bullet-list+) :bullet)
      ((= type +cmark-ordered-list+) :ordered)
      ((zerop type) nil)
      (t (error 'native-parse-error
                :operation 'native-list-type
                :datum type
                :reason "cmark returned an unknown list type")))))

(define-node-accessor native-list-delimiter (document node)
  "An ordered list's delimiter, :PERIOD or :PAREN; NIL for a bullet list or
a node that isn't a list (CMARK_NO_DELIM)."
  (let ((delimiter (with-interrupts-deferred (cmark-node-get-list-delim node))))
    (cond
      ((= delimiter +cmark-period-delim+) :period)
      ((= delimiter +cmark-paren-delim+) :paren)
      ((zerop delimiter) nil)
      (t (error 'native-parse-error
                :operation 'native-list-delimiter
                :datum delimiter
                :reason "cmark returned an unknown list delimiter")))))

(define-node-accessor native-list-start (document node)
  "An ordered list's start number."
  (with-interrupts-deferred (cmark-node-get-list-start node)))

(define-node-accessor native-list-tight (document node)
  "True when a list is tight."
  (not (zerop (with-interrupts-deferred (cmark-node-get-list-tight node)))))

(define-node-accessor native-start-line (document node)
  "NODE's first line, or 0 when cmark has no position for it."
  (with-interrupts-deferred (cmark-node-get-start-line node)))

(define-node-accessor native-start-column (document node)
  "NODE's first column, a byte offset."
  (with-interrupts-deferred (cmark-node-get-start-column node)))

(define-node-accessor native-end-line (document node)
  "NODE's last line."
  (with-interrupts-deferred (cmark-node-get-end-line node)))

(define-node-accessor native-end-column (document node)
  "NODE's last column, a byte offset."
  (with-interrupts-deferred (cmark-node-get-end-column node)))

(define-node-accessor native-footnote-definition (document node)
  "The footnote definition a footnote reference resolves to, or NIL. Its
literal is the reference's label as written (M2 design finding 6)."
  (node-or-nil (with-interrupts-deferred (cmark-node-parent-footnote-def node))))

(define-node-accessor native-table-columns (document node)
  "A table's number of columns; 0 for a node that isn't a table."
  (with-interrupts-deferred (cmark-gfm-extensions-get-table-columns node)))

(defun alignment-keyword (byte)
  "The alignment a table's alignment BYTE stands for: :LEFT, :CENTER or
:RIGHT for l, c or r, NIL for 0 (try_opening_table_header,
extensions/table.c)."
  (cond
    ((zerop byte) nil)
    ((= byte (char-code #\l)) :left)
    ((= byte (char-code #\c)) :center)
    ((= byte (char-code #\r)) :right)
    (t (error 'native-parse-error
              :operation 'native-table-alignments
              :datum byte
              :reason "cmark returned an unknown table alignment"))))

(define-node-accessor native-table-alignments (document node)
  "A table's alignment for each of its columns, in order: :LEFT, :CENTER,
:RIGHT or NIL for none. cmark keeps one byte per column
(cmark_gfm_extensions_get_table_alignments, extensions/table.c)."
  (multiple-value-bind (columns alignments)
      (with-interrupts-deferred
        (values (cmark-gfm-extensions-get-table-columns node)
                (cmark-gfm-extensions-get-table-alignments node)))
    (cond
      ((zerop columns) '())
      ((cffi:null-pointer-p alignments)
       (error 'native-parse-error
              :operation 'native-table-alignments
              :datum columns
              :reason "cmark returned no alignments for a table with columns"))
      (t (loop for index below columns
               collect (alignment-keyword (cffi:mem-aref alignments :uint8 index)))))))

(define-node-accessor native-task-checked (document node)
  "True when a task item is checked: cmark's C bool, read as its one byte
and tested against zero (ADR-0008)."
  (not (zerop (with-interrupts-deferred
                (cmark-gfm-extensions-get-tasklist-item-checked node)))))
