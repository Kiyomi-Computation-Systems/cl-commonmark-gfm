;;;; The API reference, docs/reference.md: a page generated from the
;;;; docstrings of the symbols cl-commonmark-gfm exports. READ-ENTRIES reads
;;;; them from this image, the one function here that looks at it.
;;;; Everything after it reads and writes no file: entries in, the page's
;;;; text out, and the problems with it, among them each docstring the
;;;; library doesn't render as its own text. The runner,
;;;; site/run-reference.lisp, reads and writes docs/reference.md.

(in-package #:cl-commonmark-gfm.site)

(defparameter *reference-package* "CL-COMMONMARK-GFM"
  "The package the reference documents: each symbol it exports gets an
entry.")

(defparameter *reference-title* "API reference"
  "The reference's title, its page's # heading.")

(defparameter *reference-opening*
  "This page lists every exported symbol, from its docstring."
  "The line under the reference's title.")

(defparameter *reference-sections*
  '(("CL-COMMONMARK-GFM" . "Rendering and parsing")
    ("CL-COMMONMARK-GFM.AST" . "The AST")
    ("CL-COMMONMARK-GFM.HTML-TREE" . "The HTML tree")
    ("CL-COMMONMARK-GFM.CONDITIONS" . "Conditions"))
  "The reference's sections, in order, each (PACKAGE-NAME . TITLE): a home
package's name, and the title of the section that documents the exports
whose home it is. An export whose home package isn't listed, such as the
limits' variables, which cl-commonmark-gfm takes from its native layer,
goes in the first section, the documented package's own.")

;;; Entries

(defstruct (reference-entry (:conc-name entry-) (:constructor make-entry))
  "One exported symbol, as the reference documents it. NAME is its name in
lower case, as users type it, and PACKAGE its home package's name. KIND is
:STRUCTURE, :CONDITION, :FUNCTION, :MACRO or :VARIABLE. LAMBDA-LIST is a
function's or macro's parameters, as LAMBDA-LIST-NAMES gives them, and
PARENTS a condition's direct superclasses' names, in lower case. DOCSTRING
is its docstring, or NIL. CODE-WORDS are the words of DOCSTRING, as
DOCSTRING-WORDS finds them, that name a function, macro, variable, class or
type in *REFERENCE-PACKAGE*."
  (name "")
  (package "")
  (kind :function)
  (lambda-list '())
  (parents '())
  (docstring nil)
  (code-words '()))

(defun read-entries (package)
  "Each symbol the package PACKAGE exports, read from this image, as a
REFERENCE-ENTRY, in no particular order. Its CODE-WORDS are the words of
its docstring that name a function, macro, variable, class or type
accessible in PACKAGE: a symbol merely interned there, as every local
variable's name is, names nothing. Signals an error for an export that
names none of the five kinds an entry can have, or more than one. Only
SBCL can read a function's lambda list and a condition's parents, through
sb-introspect and sb-mop, so the reference is generated on SBCL alone."
  (declare (ignorable package))
  #+sbcl
  (let ((entries '()))
    (do-external-symbols (symbol package entries)
      (let* ((class (find-class symbol nil))
             (kinds (remove nil (list (and class (subtypep class 'condition) :condition)
                                      (and (typep class 'structure-class) :structure)
                                      (and (macro-function symbol) :macro)
                                      (and (fboundp symbol) (not (macro-function symbol)) :function)
                                      (and (boundp symbol) :variable))))
             (kind (first kinds))
             (docstring (and kind
                             (documentation symbol (ecase kind
                                                     ((:function :macro) 'function)
                                                     (:variable 'variable)
                                                     ((:structure :condition) 'type))))))
        (unless (= (length kinds) 1)
          (error "~S names ~:[nothing~;~:*~{~(~A~)~^ and ~}~], but an entry documents one ~
                  function, macro, variable, structure or condition."
                 symbol kinds))
        (push (make-entry
               :name (string-downcase (symbol-name symbol))
               :package (package-name (symbol-package symbol))
               :kind kind
               :lambda-list (when (member kind '(:function :macro))
                              (lambda-list-names (sb-introspect:function-lambda-list symbol)))
               :parents (when (eql kind :condition)
                          (mapcar (lambda (parent)
                                    (string-downcase (symbol-name (class-name parent))))
                                  (sb-mop:class-direct-superclasses class)))
               :docstring docstring
               :code-words (remove-if-not
                            (lambda (word)
                              (multiple-value-bind (named status) (find-symbol word package)
                                (and status
                                     (or (fboundp named)
                                         (boundp named)
                                         (sb-ext:valid-type-specifier-p named)))))
                            (docstring-words (or docstring ""))))
              entries))))
  #-sbcl
  (error "The reference is generated on SBCL: reading a function's lambda list and a ~
          condition's parents needs SBCL's sb-introspect and sb-mop."))

(defun lambda-list-names (lambda-list)
  "LAMBDA-LIST, a function's or macro's, as the lower-case names its call
form shows: each parameter by its name alone, without its default or its
supplied-p variable, and each lambda-list keyword, such as &key. A keyword
parameter written ((:KEY VAR) ...) shows as KEY, the keyword a call passes.
A macro's destructuring list shows as its own names, in parentheses."
  (let ((names '())
        (defaulting nil))
    (dolist (item lambda-list (nreverse names))
      (cond ((member item lambda-list-keywords)
             (setf defaulting (member item '(&optional &key &aux)))
             (push (string-downcase (symbol-name item)) names))
            ((symbolp item)
             (push (string-downcase (symbol-name item)) names))
            (defaulting
             (let ((variable (first item)))
               (push (string-downcase (symbol-name (if (consp variable) (first variable) variable)))
                     names)))
            (t
             (push (format nil "(~{~A~^ ~})" (lambda-list-names item)) names))))))

;;; Words

(defun whitespace-character-p (char)
  "True when CHAR is a space, a tab or a line break."
  (member char '(#\Space #\Tab #\Newline #\Return)))

(defun word-character-p (char)
  "True when CHAR can be part of a word: any character but whitespace and
the ones that end a symbol's name when Lisp reads it, ( ) \" ' ` , and ;."
  (not (or (whitespace-character-p char) (find char "()\"'`,;"))))

(defun word-end (text start)
  "The end of the run of word characters in TEXT that starts at START."
  (or (position-if-not #'word-character-p text :start start) (length text)))

(defun word-name (word)
  "WORD, a run of word characters, without the punctuation that ends a
clause or a sentence after it: :PROFILE: names :PROFILE, NODE. names NODE."
  (string-right-trim ".:?!" word))

(defun upper-case-word-p (word)
  "True when WORD has a letter and no lower-case one: how a docstring
writes a symbol's name, and also an acronym, such as UTF-8."
  (and (some #'alpha-char-p word) (notany #'lower-case-p word)))

(defun docstring-words (docstring)
  "DOCSTRING's upper-case words, as WORD-NAME gives them, each once, in the
order they first appear. READ-ENTRIES asks which of them name something."
  (let ((words '())
        (index 0))
    (loop while (< index (length docstring))
          do (if (word-character-p (char docstring index))
                 (let* ((end (word-end docstring index))
                        (word (word-name (subseq docstring index end))))
                   (when (upper-case-word-p word)
                     (pushnew word words :test #'string=))
                   (setf index end))
                 (incf index)))
    (nreverse words)))

(defun keyword-word-p (word)
  "True when WORD is written as a keyword: a colon, then a name holding no
other colon, such as :GFM."
  (and (> (length word) 1)
       (char= (char word 0) #\:)
       (not (find #\: word :start 1))))

(defun special-word-p (word)
  "True when WORD is written as a special variable's name, *NAME*, with or
without a package prefix: *MAX-NODES*, CFFI-SYS:*CFFI-ECL-METHOD*."
  (let ((name (subseq word (1+ (or (position #\: word :from-end t) -1)))))
    (and (> (length name) 2)
         (char= (char name 0) #\*)
         (char= (char name (1- (length name))) #\*))))

(defun parameter-word-p (word entry)
  "True when WORD is one of ENTRY's parameters."
  (member (string-downcase word) (entry-lambda-list entry) :test #'string=))

(defun common-lisp-word-p (word)
  "True when WORD is the name of an external symbol of COMMON-LISP, such as
NIL or TYPE-ERROR. The standard fixes that package's external symbols, so
this asks nothing of the rest of the image."
  (eql (nth-value 1 (find-symbol word "COMMON-LISP")) :external))

(defun code-word-p (word entry)
  "True when WORD, a word of ENTRY's docstring as WORD-NAME gives it, names
something, so the reference writes it as code. WORD must be in upper case,
and written as a keyword or a special variable's name; or be one of ENTRY's
parameters; or one of its CODE-WORDS; or name an external symbol of
COMMON-LISP. An upper-case word that names nothing, such as UTF-8 or HTML,
stays text."
  (and (upper-case-word-p word)
       (or (keyword-word-p word)
           (special-word-p word)
           (parameter-word-p word entry)
           (member word (entry-code-words entry) :test #'string=)
           (common-lisp-word-p word))
       t))

;;; Forms

(defun form-end (text start)
  "The end of the parenthesized form that opens at START in TEXT, just past
its closing parenthesis, or NIL when it doesn't close. A parenthesis in a
string, between double quotes, doesn't count, and a backslash in a string
escapes the character after it."
  (let ((depth 0)
        (in-string nil)
        (escaped nil))
    (loop for index from start below (length text)
          for char = (char text index)
          do (cond (escaped (setf escaped nil))
                   (in-string (cond ((char= char #\\) (setf escaped t))
                                    ((char= char #\") (setf in-string nil))))
                   ((char= char #\") (setf in-string t))
                   ((char= char #\() (incf depth))
                   ((char= char #\))
                    (decf depth)
                    (when (zerop depth)
                      (return (1+ index))))))))

(defun form-segments (form)
  "FORM's text in segments, in order, each (IN-STRING-P . TEXT): its
strings, each from its opening double quote through its closing one, a
backslash in one escaping the character after it, and the text between
them."
  (let ((segments '())
        (start 0)
        (in-string nil)
        (escaped nil))
    (loop for index from 0 below (length form)
          for char = (char form index)
          do (cond (escaped (setf escaped nil))
                   ((and in-string (char= char #\\)) (setf escaped t))
                   ((and in-string (char= char #\"))
                    (push (cons t (subseq form start (1+ index))) segments)
                    (setf start (1+ index)
                          in-string nil))
                   ((char= char #\")
                    (push (cons nil (subseq form start index)) segments)
                    (setf start index
                          in-string t))))
    (push (cons in-string (subseq form start)) segments)
    (nreverse segments)))

(defun lisp-text-p (form)
  "True when FORM reads as Lisp, as a docstring writes it: no lower-case
letter, and no comma, outside its strings. A remark in parentheses has
lower-case words, as (*MAX-NODES* or a list) has, or commas between its
names, as (PARSE, MARKDOWN->HTML) has."
  (loop for (in-string-p . text) in (form-segments form)
        never (and (not in-string-p)
                   (or (some #'lower-case-p text) (find #\, text)))))

(defun form-code (form)
  "FORM as code: in lower case, but for its strings."
  (format nil "~{~A~}" (loop for (in-string-p . text) in (form-segments form)
                             collect (if in-string-p text (string-downcase text)))))

(defun first-word (text start)
  "The first word in TEXT after the opening parenthesis at START, past any
whitespace, as WORD-NAME gives it; or NIL when no word follows it."
  (let ((word-start (position-if-not #'whitespace-character-p text :start (1+ start))))
    (when (and word-start (word-character-p (char text word-start)))
      (word-name (subseq text word-start (word-end text word-start))))))

(defun code-form-end (text start entry)
  "The end of the parenthesized form that opens at START in TEXT, a part of
ENTRY's docstring, when the form is code; otherwise NIL. A form is code
when it closes, its first word names something, as CODE-WORD-P says, and
it reads as Lisp, as LISP-TEXT-P says: (AST->HTML-TREE (PARSE MARKDOWN))
is code, and (*MAX-NODES* or a list) a remark."
  (let ((end (form-end text start))
        (word (first-word text start)))
    (when (and end word (code-word-p word entry) (lisp-text-p (subseq text start end)))
      end)))

;;; Markdown text

(defparameter *markdown-characters* "\\`*_[]<&|~"
  "The characters Markdown or GFM give a meaning to anywhere in a line: a
backslash's escape, code, emphasis, a link, raw HTML or an autolink, an
entity, a table's cell, strikethrough. Text escapes each of them.")

(defparameter *block-start-characters* "#>+-="
  "The characters that make a line start a Markdown block when they start
it: a heading, a quote, a list item, a rule, a heading's underline. Text
that starts a paragraph or a list item escapes one there.")

(defun block-start-escape (text)
  "The index of the character that would make TEXT, at the start of a
paragraph or a list item, start a Markdown block instead: its first, when
that is one of *BLOCK-START-CHARACTERS*; or the . or ) after a number it
starts with, which would make an ordered list's item. NIL when there is
none."
  (let ((digits (or (position-if-not #'digit-char-p text) (length text))))
    (cond ((zerop (length text)) nil)
          ((find (char text 0) *block-start-characters*) 0)
          ((and (plusp digits) (< digits (length text)) (find (char text digits) ".)")) digits)
          (t nil))))

(defun escape-text (text at-start)
  "TEXT as Markdown that renders as TEXT: a backslash before each of
*MARKDOWN-CHARACTERS*, and, when TEXT starts a paragraph or a list item,
AT-START, before the character BLOCK-START-ESCAPE finds. Every other
character stays as written."
  (let ((start-escape (and at-start (block-start-escape text))))
    (with-output-to-string (out)
      (loop for char across text
            for index from 0
            do (when (or (and start-escape (= index start-escape))
                         (find char *markdown-characters*))
                 (write-char #\\ out))
               (write-char char out)))))

(defun added-backslash-p (text index)
  "True when the character at INDEX in TEXT, Markdown that ESCAPE-TEXT
wrote, is a backslash ESCAPE-TEXT added: one before a character of
*MARKDOWN-CHARACTERS*; at TEXT's start, one before a character of
*BLOCK-START-CHARACTERS*; or one before the . or ) after a number TEXT
starts with."
  (and (< (1+ index) (length text))
       (char= (char text index) #\\)
       (let ((next (char text (1+ index))))
         (or (find next *markdown-characters*)
             (and (zerop index) (find next *block-start-characters*))
             (and (plusp index)
                  (not (find-if-not #'digit-char-p text :end index))
                  (find next ".)"))))))

(defun unescape-text (text)
  "TEXT, Markdown that ESCAPE-TEXT wrote, without the backslashes it adds,
as ADDED-BACKSLASH-P finds them. Every other backslash stays. A backslash
of the text ESCAPE-TEXT was given comes out doubled, so it comes back
single."
  (with-output-to-string (out)
    (loop with index = 0
          while (< index (length text))
          do (cond ((added-backslash-p text index)
                    (write-char (char text (1+ index)) out)
                    (incf index 2))
                   (t
                    (write-char (char text index) out)
                    (incf index))))))

(defun longest-backtick-run (text)
  "The length of TEXT's longest run of backticks."
  (let ((longest 0)
        (run 0))
    (loop for char across text
          do (if (char= char #\`)
                 (setf longest (max longest (incf run)))
                 (setf run 0)))
    longest))

(defun code-span (code)
  "CODE as a Markdown code span: between runs of backticks one longer than
its own longest, with a space inside each end when CODE starts or ends with
a backtick, which the span would otherwise run into."
  (let ((fence (make-string (1+ (longest-backtick-run code)) :initial-element #\`))
        (pad (if (and (plusp (length code))
                      (or (char= (char code 0) #\`)
                          (char= (char code (1- (length code))) #\`)))
                 " "
                 "")))
    (concatenate 'string fence pad code pad fence)))

;;; What users type

(defun string-end (text start)
  "The end of the double-quoted string that opens at START in TEXT, just
past its closing quote, or NIL when it doesn't close. A backslash in it
escapes the character after it."
  (let ((escaped nil))
    (loop for index from (1+ start) below (length text)
          for char = (char text index)
          do (cond (escaped (setf escaped nil))
                   ((char= char #\\) (setf escaped t))
                   ((char= char #\") (return (1+ index)))))))

(defun backquote-partner (text start)
  "The index of the partner of the backquote at START in TEXT: the next
backquote on its line, TEXT's lines being joined by newlines, as JOIN-LINES
joins them. NIL when there is none."
  (position #\` text :start (1+ start)
                     :end (or (position #\Newline text :start start) (length text))))

(defun backquoted-run-p (text start partner)
  "True when the backquote at START in TEXT and its PARTNER, as
BACKQUOTE-PARTNER finds it, enclose code: at least one character, no
whitespace just inside either backquote, and neither backquote beside
another backquote. Any other pair is text, as written: CommonMark would
read it otherwise, or it reads more like punctuation than code. CommonMark
trims a space from each end of a code span that has one at both, and takes
backquotes side by side as one longer fence."
  (and (> partner (1+ start))
       (not (whitespace-character-p (char text (1+ start))))
       (not (whitespace-character-p (char text (1- partner))))
       (not (and (plusp start) (char= (char text (1- start)) #\`)))
       (not (and (< (1+ partner) (length text)) (char= (char text (1+ partner)) #\`)))))

(defun backquoted-code-p (run entry)
  "True when RUN, the text of a backquoted run in ENTRY's docstring, is code
without its backquotes, in lower case: a word that names something, as
CODE-WORD-P says of its WORD-NAME, or a form that CODE-FORM-END says is
code, whole. The backquotes would keep its case, as no other name or form
in the reference keeps it."
  (or (and (= (word-end run 0) (length run))
           (code-word-p (word-name run) entry))
      (and (char= (char run 0) #\()
           (eql (code-form-end run 0 entry) (length run)))))

(defun underscore-name-p (word)
  "True when WORD is an upper-case name holding an underscore, as an
environment variable's or a C macro's is: CL_COMMONMARK_GFM_LIBS."
  (and (upper-case-word-p word) (find #\_ word) t))

(defun absolute-path-p (word)
  "True when WORD is an absolute path: a slash, then a letter or a digit,
as in /usr/lib."
  (and (> (length word) 1)
       (char= (char word 0) #\/)
       (alphanumericp (char word 1))))

(defun word-code (word entry)
  "WORD, a word of ENTRY's docstring as WORD-NAME gives it, as the code it
is, or NIL when it is text: in lower case when it names something, as
CODE-WORD-P says; as written when users type it so, as an upper-case name
holding an underscore or an absolute path."
  (cond ((code-word-p word entry) (string-downcase word))
        ((or (underscore-name-p word) (absolute-path-p word)) word)
        (t nil)))

;;; Pieces

(defun merge-text-pieces (pieces)
  "PIECES with each run of text pieces joined into one, and empty text
left out."
  (let ((merged '()))
    (dolist (piece pieces (nreverse merged))
      (destructuring-bind (kind . string) piece
        (cond ((zerop (length string)) nil)
              ((and (eql kind :text) merged (eql (car (first merged)) :text))
               (setf (first merged)
                     (cons :text (concatenate 'string (cdr (first merged)) string))))
              (t (push piece merged)))))))

(defun inline-pieces (text entry)
  "TEXT, a paragraph or a list item of ENTRY's docstring, its lines joined
by newlines, in pieces, in order, each (:CODE . CODE), (:RUN . CODE) or
(:TEXT . TEXT):
- a backquoted run, a backquote and its partner that BACKQUOTED-RUN-P
  accepts, is a :RUN piece, code: what lies between them, as written;
- a parenthesized form that CODE-FORM-END finds is code, whole, in lower
  case but for its strings;
- a double-quoted string is code as written, quotes included;
- a word that WORD-CODE makes code is that code, and the punctuation that
  WORD-NAME leaves after it is text;
- everything else is text, as written: among it, a backquote with no
  partner, and both backquotes of a pair that isn't a run.
TEXT is read left to right, so whichever opens first, a backquote, a form
or a double quote, holds what follows to its end: a backquote inside a
string is the string's, and a double quote inside a run is the run's. Each
newline comes out as a space."
  (let ((pieces '())
        (index 0)
        (text-partner nil))
    (loop while (< index (length text))
          do (let* ((char (char text index))
                    (partner (and (char= char #\`)
                                  (not (eql index text-partner))
                                  (backquote-partner text index)))
                    (form (and (char= char #\() (code-form-end text index entry)))
                    (quoted (and (char= char #\") (string-end text index))))
               (cond ((and partner (backquoted-run-p text index partner))
                      (push (cons :run (subseq text (1+ index) partner)) pieces)
                      (setf index (1+ partner)))
                     (partner
                      ;; Not a run: the partner is text too, so it can't
                      ;; open a run of its own.
                      (push (cons :text (string char)) pieces)
                      (setf text-partner partner)
                      (incf index))
                     (form
                      (push (cons :code (form-code (subseq text index form))) pieces)
                      (setf index form))
                     (quoted
                      (push (cons :code (subseq text index quoted)) pieces)
                      (setf index quoted))
                     ((word-character-p char)
                      (let* ((end (word-end text index))
                             (word (subseq text index end))
                             (name (word-name word))
                             (code (word-code name entry)))
                        (cond (code
                               (push (cons :code code) pieces)
                               (push (cons :text (subseq word (length name))) pieces))
                              (t (push (cons :text word) pieces)))
                        (setf index end)))
                     (t
                      (push (cons :text (string char)) pieces)
                      (incf index)))))
    (mapcar (lambda (piece) (cons (car piece) (substitute #\Space #\Newline (cdr piece))))
            (merge-text-pieces (nreverse pieces)))))

(defun pieces-markdown (pieces)
  "PIECES, a paragraph's or a list item's, as Markdown: each code piece and
backquoted run as a code span, and each text piece through ESCAPE-TEXT, the
first as the start of its block."
  (with-output-to-string (out)
    (loop for (kind . string) in pieces
          for at-start = t then nil
          do (write-string (ecase kind
                             ((:code :run) (code-span string))
                             (:text (escape-text string at-start)))
                           out))))

(defun pieces-text (pieces)
  "The text PIECES render to: each piece's own, code and text alike."
  (format nil "~{~A~}" (mapcar #'cdr pieces)))

(defun pieces-codes (pieces)
  "The code of PIECES' code pieces and backquoted runs, in order."
  (loop for (kind . string) in pieces
        when (member kind '(:code :run))
          collect string))

(defun pieces-runs (pieces)
  "The text of PIECES' backquoted runs, in order."
  (loop for (kind . string) in pieces
        when (eql kind :run)
          collect string))

;;; Docstrings

(defun split-lines (text)
  "TEXT split at each newline."
  (loop for start = 0 then (1+ newline)
        for newline = (position #\Newline text :start start)
        collect (subseq text start newline)
        while newline))

(defun blank-line-p (line)
  "True when LINE holds nothing but whitespace."
  (every #'whitespace-character-p line))

(defun list-item-line-p (line)
  "True when LINE starts a list item: it starts with a hyphen and a space."
  (and (>= (length line) 2) (string= "- " line :end2 2)))

(defun indented-line-p (line)
  "True when LINE starts with whitespace."
  (and (plusp (length line)) (whitespace-character-p (char line 0))))

(defun join-lines (lines)
  "LINES, each trimmed of whitespace, joined by newlines, so INLINE-PIECES
can tell where each line ends."
  (format nil "~{~A~^~%~}"
          (mapcar (lambda (line) (string-trim '(#\Space #\Tab #\Newline #\Return) line)) lines)))

(defun docstring-blocks (docstring)
  "DOCSTRING's blocks, in order, each (:PARAGRAPH TEXT) or (:LIST TEXTS), a
TEXT being a paragraph's or a list item's lines, joined by JOIN-LINES.
Blank lines separate blocks. A line starting with \"- \" starts a list
item, and the indented lines after it continue it; any other line ends the
list, and starts or continues a paragraph."
  (let ((blocks '())
        (paragraph '())
        (items '()))
    (flet ((end-paragraph ()
             (when paragraph
               (push (list :paragraph (join-lines (reverse paragraph))) blocks)
               (setf paragraph '())))
           (end-list ()
             (when items
               (push (list :list (mapcar (lambda (item) (join-lines (reverse item)))
                                         (reverse items)))
                     blocks)
               (setf items '()))))
      (dolist (line (split-lines docstring))
        (cond ((blank-line-p line)
               (end-paragraph)
               (end-list))
              ((list-item-line-p line)
               (end-paragraph)
               (push (list (subseq line 2)) items))
              ((and items (indented-line-p line))
               (push line (first items)))
              (t
               (end-list)
               (push line paragraph))))
      (end-paragraph)
      (end-list))
    (nreverse blocks)))

(defun docstring-rendering (entry)
  "ENTRY's docstring as the reference writes it, and what that means, as
four values. First, its Markdown: the blocks DOCSTRING-BLOCKS reads,
separated by blank lines, each list item on a line of its own after
\"- \". Then the text that Markdown renders to, each paragraph's and list
item's after a space; the code it holds, each code span's, in order; and
the text of each backquoted run among that code, in order. Each paragraph
and list item goes through INLINE-PIECES once, for all four, so a test
that renders the Markdown can compare the result with what was meant.
With no docstring, the empty string twice, then NIL twice."
  (let ((blocks (loop for (kind content) in (docstring-blocks (or (entry-docstring entry) ""))
                      collect (cons kind (mapcar (lambda (text) (inline-pieces text entry))
                                                 (if (eql kind :list) content (list content)))))))
    (values (format nil "~{~A~^~%~%~}"
                    (loop for (kind . items) in blocks
                          collect (ecase kind
                                    (:paragraph (pieces-markdown (first items)))
                                    (:list (format nil "~{- ~A~^~%~}"
                                                   (mapcar #'pieces-markdown items))))))
            (format nil "~{~A~^ ~}" (loop for (nil . items) in blocks
                                          append (mapcar #'pieces-text items)))
            (loop for (nil . items) in blocks
                  append (mapcan #'pieces-codes items))
            (loop for (nil . items) in blocks
                  append (mapcan #'pieces-runs items)))))

(defun docstring-markdown (entry)
  "ENTRY's docstring in Markdown, as DOCSTRING-RENDERING writes it."
  (values (docstring-rendering entry)))

;;; The page

(defun section-index (entry)
  "The position in *REFERENCE-SECTIONS* of ENTRY's section: its home
package's, or the first when its home package has none."
  (or (position (entry-package entry) *reference-sections* :key #'car :test #'string=) 0))

(defun kind-rank (kind)
  "KIND's place in a section: structures, then conditions, then functions
and macros together, then variables."
  (ecase kind
    (:structure 0)
    (:condition 1)
    ((:function :macro) 2)
    (:variable 3)))

(defun entry< (a b)
  "True when the entry A comes before the entry B on the page: by section,
then by KIND-RANK, then by name."
  (let ((section-a (section-index a))
        (section-b (section-index b))
        (rank-a (kind-rank (entry-kind a)))
        (rank-b (kind-rank (entry-kind b))))
    (cond ((/= section-a section-b) (< section-a section-b))
          ((/= rank-a rank-b) (< rank-a rank-b))
          (t (and (string< (entry-name a) (entry-name b)) t)))))

(defun sort-entries (entries)
  "ENTRIES in the page's order, as ENTRY< orders them."
  (sort (copy-list entries) #'entry<))

(defun section-groups (entries)
  "ENTRIES grouped by section, in the page's order: each (TITLE . ENTRIES),
for each section of *REFERENCE-SECTIONS* that has an entry."
  (let ((sorted (sort-entries entries)))
    (loop for index from 0
          for (nil . title) in *reference-sections*
          for members = (remove-if-not (lambda (entry) (= (section-index entry) index)) sorted)
          when members
            collect (cons title members))))

(defun entry-ids (groups)
  "The ids the site gives the entries' headings on the page GROUPS lay
out, as SECTION-GROUPS gives them: each (NAME . ID). They are UNIQUE-IDS
over every heading on the page, in order, the title's and the sections'
included, since two names can make one id: node and node= both make node,
so node=, the second, takes node-1."
  (let ((headings (cons (cons nil *reference-title*)
                        (loop for (title . entries) in groups
                              collect (cons nil title)
                              append (mapcar (lambda (entry) (cons entry (entry-name entry)))
                                             entries)))))
    (loop for (entry . nil) in headings
          for id in (unique-ids (mapcar #'cdr headings))
          when entry
            collect (cons (entry-name entry) id))))

(defun join-and (items)
  "ITEMS, strings, joined as a sentence lists them: a, a and b, a, b and
c."
  (format nil "~{~A~#[~; and ~:;, ~]~}" items))

(defun parent-link (name ids)
  "The kind line's mention of a condition's parent NAME: a link to its
entry, by its id in IDS, or plain code when it has no entry, as error
hasn't."
  (let ((id (cdr (assoc name ids :test #'string=))))
    (if id
        (format nil "[~A](#~A)" (code-span name) id)
        (code-span name))))

(defun kind-line (entry ids)
  "The line under ENTRY's heading that names its kind. A condition's also
names its direct parents, each through PARENT-LINK."
  (ecase (entry-kind entry)
    (:function "Function")
    (:macro "Macro")
    (:variable "Variable")
    (:structure "Structure")
    (:condition (format nil "Condition, a subtype of ~A"
                        (join-and (mapcar (lambda (parent) (parent-link parent ids))
                                          (entry-parents entry)))))))

(defun call-form (entry)
  "ENTRY's call form as code, when it is a function or a macro: its name,
then its lambda list's names. NIL for any other kind."
  (when (member (entry-kind entry) '(:function :macro))
    (code-span (format nil "(~A~{ ~A~})" (entry-name entry) (entry-lambda-list entry)))))

(defun blocks-text (blocks)
  "BLOCKS, Markdown blocks, as one text: a blank line between each two,
then a newline. An empty block, or a NIL, is left out."
  (format nil "~{~A~^~%~%~}~%" (remove-if (lambda (block) (zerop (length block))) blocks)))

(defun entry-markdown (entry ids)
  "ENTRY's part of the page: a heading, its name as code; its kind line; a
function's or macro's call form; and its docstring, through
DOCSTRING-MARKDOWN. IDS are every entry's heading's id, as ENTRY-IDS gives
them."
  (blocks-text (list (format nil "### ~A" (code-span (entry-name entry)))
                     (kind-line entry ids)
                     (call-form entry)
                     (docstring-markdown entry))))

(defun reference-parts (entries)
  "The reference page that documents ENTRIES, in parts, in order, each
(LABEL . TEXT). The LABELs are (:OPENING), for the title and the line
under it; (:SECTION . TITLE), for a section's heading; and (:ENTRY . NAME),
for an entry. Sections follow *REFERENCE-SECTIONS*, and the entries in
each follow ENTRY<. Each TEXT ends in a newline."
  (let* ((groups (section-groups entries))
         (ids (entry-ids groups)))
    (cons (cons (list :opening)
                (blocks-text (list (format nil "# ~A" *reference-title*) *reference-opening*)))
          (loop for (title . members) in groups
                collect (cons (cons :section title) (blocks-text (list (format nil "## ~A" title))))
                append (mapcar (lambda (entry)
                                 (cons (cons :entry (entry-name entry)) (entry-markdown entry ids)))
                               members)))))

(defun reference-text (parts)
  "The page that PARTS, as REFERENCE-PARTS gives them, make: their texts,
in order, with a blank line between each two."
  (format nil "~{~A~^~%~}" (mapcar #'cdr parts)))

;;; The render check

(defparameter *rendered-tags* '(:p :ul :li :code)
  "The elements a docstring's Markdown may render as: paragraphs, lists and
their items, and code. Any other means the Markdown says more than the
docstring does: a link, say, from an address GFM links by itself.")

(defun normalize-whitespace (text)
  "TEXT with each run of whitespace made one space, and none at either end."
  (with-output-to-string (out)
    (let ((space nil)
          (started nil))
      (loop for char across text
            do (cond ((whitespace-character-p char)
                      (setf space started))
                     (t
                      (when space
                        (write-char #\Space out)
                        (setf space nil))
                      (write-char char out)
                      (setf started t)))))))

(defun element-text (element)
  "The text ELEMENT, an HTML tree element, holds: its strings and its
elements' strings, in document order. Loops over an explicit stack of child
lists."
  (with-output-to-string (out)
    (let ((stack (list (cddr element))))
      (loop while stack
            do (let ((nodes (pop stack)))
                 (when nodes
                   (push (rest nodes) stack)
                   (let ((node (first nodes)))
                     (if (stringp node)
                         (write-string node out)
                         (push (cddr node) stack)))))))))

(defun rendered-contents (tree)
  "What TREE, a docstring's HTML tree, holds, as three values: its strings,
joined in document order; each code element's text, in order; and each
element whose tag isn't one of *RENDERED-TAGS*, in order, as (TAG . TEXT).
TEXT is what the element holds, whitespace normalized, or empty for an
HTML comment, whose text is cmark's own. Loops over an explicit stack of
child lists."
  (let* ((codes '())
         (strays '())
         (stack (list tree))
         (text (with-output-to-string (out)
                 (loop while stack
                       do (let ((nodes (pop stack)))
                            (when nodes
                              (push (rest nodes) stack)
                              (let ((node (first nodes)))
                                (cond ((stringp node) (write-string node out))
                                      (t
                                       (let ((tag (first node)))
                                         (cond ((eql tag :code)
                                                (push (element-text node) codes))
                                               ((not (member tag *rendered-tags*))
                                                (push (cons tag
                                                            (if (eql tag :*comment*)
                                                                ""
                                                                (normalize-whitespace
                                                                 (element-text node))))
                                                      strays))))
                                       (push (cddr node) stack))))))))))
    (values text (nreverse codes) (nreverse strays))))

(defun excerpt (text start)
  "Up to 50 characters of TEXT around START: from 10 before it, so a
reader sees where it falls."
  (subseq text (max 0 (- start 10)) (min (length text) (+ start 40))))

(defun backquoted-code-problem (name run)
  "The problem with the docstring of the entry NAME putting RUN in
backquotes, though BACKQUOTED-CODE-P says it is code without them, and what
to do: drop the backquotes, which keep its case, so the reference makes it
code by its other rules."
  (format nil "~A's docstring puts ~A in backquotes, which keep its case; ~
               drop them, so the reference makes it code"
          name run))

(defun stray-element-problem (name tag text)
  "The problem with the docstring of the entry NAME rendering an element
whose tag, TAG, isn't one of *RENDERED-TAGS*, from TEXT, as the docstring
holds it, and what to do: put that text in backquotes, so the reference
makes it code, as written, which renders as nothing else. A backquoted run
can't hold a backquote, so for TEXT that holds one, the advice is double
quotes, which make it code too, quotes included."
  (cond ((zerop (length text))
         (format nil "~A's docstring renders an <~(~A~)> element; ~
                      put what makes it in backquotes, so it becomes code"
                 name tag))
        ((find #\` text)
         (format nil "~A's docstring renders ~A as an <~(~A~)> element; ~
                      write it in double quotes, ~S, so it becomes code"
                 name text tag text))
        (t
         (format nil "~A's docstring renders ~A as an <~(~A~)> element; ~
                      put it in backquotes, `~A`, so it becomes code"
                 name text tag text))))

(defparameter *docstring-unsupported-input-fix*
  (concatenate 'string "write the pattern as text, outside double quotes and backquotes, "
               "or split it into two quoted strings")
  "How to write a docstring that the footnote guard refuses, so it parses.
PARSE refuses a [ followed by an entity that decodes to ^ anywhere, a code
span included, and a docstring's double-quoted string or backquoted run
becomes a code span. As text, outside double quotes and backquotes, the
reference escapes the [ and the &, so the pattern shows as written. As
code, it is split into two quoted strings, with a word between them, each
its own code span. Writing its & as &amp;, as a page does, would show
&amp;: the reference escapes that & too.")

(defun docstring-parse-problem (name condition)
  "The problem with the docstring of the entry NAME when the library
refuses to parse the Markdown the reference writes for it, signalling
CONDITION: its type and report, as PARSE-PROBLEM words a page's; then, for
UNSUPPORTED-INPUT, how to write the docstring so it parses."
  (format nil "~A's docstring: can't be parsed: ~(~A~): ~A~@[; ~A~]"
          name
          (type-of condition)
          condition
          (and (typep condition 'unsupported-input) *docstring-unsupported-input-fix*)))

(defun rendered-tree (name markdown)
  "MARKDOWN, which the reference writes for the docstring of the entry NAME,
rendered by the library as an HTML tree; or NIL and, as a second value,
DOCSTRING-PARSE-PROBLEM's problem when the library signals one of its
errors, so one docstring can't end the check."
  (handler-case (values (ast->html-tree (parse markdown)) nil)
    (commonmark-gfm-error (condition)
      (values nil (docstring-parse-problem name condition)))))

(defun rendering-differences (name tree text codes)
  "The problems with TREE, the HTML tree the docstring of the entry NAME
renders as, against TEXT and CODES, the text and the code
DOCSTRING-RENDERING means it to hold. It must hold nothing but
*RENDERED-TAGS*' elements, its text must be TEXT, whitespace aside, and its
code elements' must be CODES. Each element of another tag is a problem,
which STRAY-ELEMENT-PROBLEM words: GFM links an address such as
www.example.com by itself, and backquotes make it code. GFM takes a link's
text from the Markdown, escapes included, so the problem gives what the
element holds through UNESCAPE-TEXT, as the docstring holds it. Failing
that, a difference in the text, or else in the code, is the problem,
naming what rendered and what was meant."
  (multiple-value-bind (rendered rendered-codes strays) (rendered-contents tree)
    (let* ((meant (normalize-whitespace text))
           (found (normalize-whitespace rendered))
           (at (mismatch meant found)))
      (cond (strays
             (loop for (tag . held) in strays
                   collect (stray-element-problem name tag (unescape-text held))))
            (at
             (list (format nil "~A's docstring renders ~S where it means ~S"
                           name (excerpt found at) (excerpt meant at))))
            ((not (equal codes rendered-codes))
             (list (format nil "~A's docstring renders ~:[no code~;~:*the code ~{~S~^, ~}~] ~
                                where it means ~:[no code~;~:*the code ~{~S~^, ~}~]"
                           name rendered-codes codes)))
            (t '())))))

(defun entry-rendering-problems (entry)
  "The problems with how the library renders the Markdown the reference
writes for ENTRY's docstring, each saying what to do; NIL when there are
none. First, each backquoted run that BACKQUOTED-CODE-P says is code
without its backquotes, as BACKQUOTED-CODE-PROBLEM words it. Then a
docstring the library refuses to parse is the problem RENDERED-TREE gives;
any other, RENDERING-DIFFERENCES finds."
  (let ((name (entry-name entry)))
    (multiple-value-bind (markdown text codes runs) (docstring-rendering entry)
      (append (loop for run in runs
                    when (backquoted-code-p run entry)
                      collect (backquoted-code-problem name run))
              (multiple-value-bind (tree problem) (rendered-tree name markdown)
                (if problem
                    (list problem)
                    (rendering-differences name tree text codes)))))))

(defun rendering-problems (entries)
  "The problems ENTRY-RENDERING-PROBLEMS finds with ENTRIES' docstrings, in
the page's order."
  (loop for entry in (sort-entries entries)
        append (entry-rendering-problems entry)))

;;; The check

(defun documentedp (entry)
  "True when ENTRY has a docstring with more than whitespace in it."
  (let ((docstring (entry-docstring entry)))
    (and docstring (notevery #'whitespace-character-p docstring))))

(defun docstring-problems (entries)
  "A problem for each of ENTRIES that has no docstring, in the page's
order."
  (loop for entry in (sort-entries entries)
        unless (documentedp entry)
          collect (format nil "~A has no docstring" (entry-name entry))))

(defun heading-line-p (text start)
  "True when the line of TEXT that starts at START is a section's or an
entry's heading: it starts with ## or ###, then a space."
  (flet ((starts-with-p (prefix)
           (let ((end (+ start (length prefix))))
             (and (<= end (length text)) (string= prefix text :start2 start :end2 end)))))
    (or (starts-with-p "## ") (starts-with-p "### "))))

(defun text-pieces (text)
  "TEXT, a reference page's, cut before each line that HEADING-LINE-P says
is a heading: the opening, then a piece for each section's heading and
each entry, each running to the next, the blank line after it included.
The page REFERENCE-TEXT makes cuts into one piece per part."
  (let ((starts (cons 0 (loop for newline = (position #\Newline text)
                                then (position #\Newline text :start (1+ newline))
                              while newline
                              when (heading-line-p text (1+ newline))
                                collect (1+ newline)))))
    (loop for (start end) on starts
          collect (subseq text start end))))

(defun trim-newlines (text)
  "TEXT without the newlines at its end."
  (string-right-trim '(#\Newline) text))

(defun differing-part (parts text)
  "The LABEL of the part, of PARTS as REFERENCE-PARTS gives them, where
TEXT first differs from their page, or NIL when TEXT is that page. Both
are cut by TEXT-PIECES and compared piece by piece, so a difference names
the part it is in, whichever part the blank line between two is counted
with:
- the first piece that differs, but for the newlines at its end;
- else, when TEXT has fewer pieces, the first part it lacks;
- else the first piece that differs only in those newlines;
- else, TEXT running on past the page's end, the last part."
  (let ((page (reference-text parts)))
    (unless (string= page text)
      (let ((wanted (text-pieces page))
            (found (text-pieces text)))
        (or (loop for (label) in parts
                  for want in wanted
                  for have in found
                  unless (string= (trim-newlines want) (trim-newlines have))
                    return label)
            (when (< (length found) (length parts))
              (car (nth (length found) parts)))
            (loop for (label) in parts
                  for want in wanted
                  for have in found
                  unless (string= want have)
                    return label)
            (car (first (last parts))))))))

(defun part-place (label)
  "Where on the page LABEL's part is, as a problem names it."
  (ecase (car label)
    (:opening "its opening")
    (:section (format nil "the section ~A" (cdr label)))
    (:entry (format nil "the entry for ~A" (cdr label)))))

(defun reference-problems (entries text)
  "The problems MAKE CHECK-REFERENCE reports: each of ENTRIES with no
docstring, as DOCSTRING-PROBLEMS names them; each docstring that doesn't
render as its own text, as RENDERING-PROBLEMS words it; then, when TEXT,
the text of docs/reference.md, isn't the page REFERENCE-PARTS makes from
ENTRIES, the part where it first differs, as DIFFERING-PART finds it: an
entry, the opening, or a section's heading. TEXT is NIL when that file is
missing."
  (let ((label (and text (differing-part (reference-parts entries) text))))
    (append (docstring-problems entries)
            (rendering-problems entries)
            (cond ((null text)
                   (list (format nil "docs/~A is missing: run make reference" *reference-page*)))
                  (label
                   (list (format nil "docs/~A differs at ~A: run make reference"
                                 *reference-page* (part-place label))))
                  (t '())))))
