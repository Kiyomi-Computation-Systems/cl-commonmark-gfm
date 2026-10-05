;;;; `make check-docs`'s core: running the Lisp examples in docs/ and
;;;; checking what each one does. A page's examples are the forms in its
;;;; ```lisp blocks, which PARSE finds, so a block is what cmark reads as
;;;; one. The comments between a form and the next one say what the form
;;;; should do:
;;;;
;;;;   (markdown->html "*hi*") ;; => "<p><em>hi</em></p>\n"
;;;;   (markdown->html 42)     ;; signals type-error
;;;;
;;;; A form with neither must not signal an error. A block fenced
;;;; ```lisp no-run, or in another language, is skipped; one that names
;;;; Lisp any other way fails the check, as do a misspelt marker, a marker
;;;; inside a form and a form read with #+ or #-, so that no claim goes
;;;; unchecked. Each page runs in a fresh package that uses COMMON-LISP
;;;; and CL-COMMONMARK-GFM, as a user's own code would. Everything here is
;;;; a function of strings and lists, apart from running the examples: the
;;;; package each page's forms are read and evaluated in, the library's
;;;; variables bound for each page, and EVAL. No file is touched: the
;;;; runner, site/run-check-docs.lisp, reads docs/.

(in-package #:cl-commonmark-gfm.site)

;;; Text

(defun reader-whitespace-p (char)
  "True when CHAR is whitespace to the standard reader: a space, a tab, a
newline, a return or a page break."
  (member char '(#\Space #\Tab #\Newline #\Return #\Page)))

(defun squeeze-whitespace (string)
  "STRING with each run of whitespace turned into one space, and none at
its start or its end."
  (with-output-to-string (out)
    (let ((gap nil)
          (started nil))
      (loop for char across string
            do (cond ((reader-whitespace-p char)
                      (setf gap started))
                     (t
                      (when gap
                        (write-char #\Space out))
                      (write-char char out)
                      (setf gap nil
                            started t)))))))

(defun text-at-p (part text index)
  "True when TEXT holds PART at INDEX."
  (let ((end (+ index (length part))))
    (and (<= end (length text))
         (string= part text :start2 index :end2 end))))

(defun string-prefix-equal-p (prefix string)
  "True when STRING starts with PREFIX, compared without case."
  (and (<= (length prefix) (length string))
       (string-equal prefix string :end2 (length prefix))))

(defun leading-word (string)
  "STRING up to its first whitespace."
  (subseq string 0 (position-if #'reader-whitespace-p string)))

;;; Finding the blocks

(defparameter *example-info* "lisp"
  "The info string of a block whose examples run.")

(defparameter *no-run-info* "lisp no-run"
  "The info string of a Lisp block that check-docs skips: an example that
can't run here.")

(defparameter *lisp-fence-names* '("common-lisp" "cl")
  "The names, other than those that start with lisp, that a fence can give
Lisp: an info string whose first word is one, in any case, names Lisp.")

(defun lisp-info-p (info)
  "True when INFO, a code block's info string, names Lisp: it starts with
lisp, or its first word is one of *LISP-FENCE-NAMES*, compared without
case."
  (or (string-prefix-equal-p "lisp" info)
      (member (leading-word info) *lisp-fence-names* :test #'string-equal)))

(defun block-treatment (info)
  "What check-docs does with a code block whose info string is INFO:
- :RUN when INFO is *EXAMPLE-INFO*, lisp;
- :SKIP when INFO is *NO-RUN-INFO*, lisp no-run, or names another
  language;
- :REFUSE when INFO names Lisp any other way, as LISP-INFO-P reads it,
  such as Lisp, cl or lisp norun: the check fails, so that a typo can't
  turn an example off.
cmark trims the info string, so spaces around it don't count."
  (cond ((string= info *example-info*) :run)
        ((string= info *no-run-info*) :skip)
        ((lisp-info-p info) :refuse)
        (t :skip)))

(defun checked-block-p (node)
  "True when NODE is a code block that check-docs runs or refuses."
  (and (eql (node-kind node) :code-block)
       (not (eql (block-treatment (node-attribute node :info)) :skip))))

(defun lisp-blocks (markdown)
  "Each code block of MARKDOWN that check-docs runs or refuses, as
(INFO . CODE), its info string and its code, in document order, blocks
inside lists and quotes included. PARSE finds them, so a block is what
cmark reads as one."
  (reverse (fold-ast (lambda (node blocks)
                       (if (checked-block-p node)
                           (cons (cons (node-attribute node :info) (node-attribute node :literal))
                                 blocks)
                           blocks))
                     '()
                     (parse markdown))))

;;; Reading a block: comments and markers

(defun line-comment (text start end)
  "The line comment in TEXT that starts at START, a semicolon, and ends at
END, its line's end, as (SEMICOLONS . REST): how many semicolons start it,
and the text after them."
  (let ((after (or (position #\; text :start start :end end :test #'char/=) end)))
    (cons (- after start) (subseq text after end))))

(defparameter *value-arrows*
  (list "=>" "==>" "->" "-->" (string (code-char #x2192)) (string (code-char #x21D2)))
  "The arrows a comment can start with to give a form's value: => is the
marker, and the others, ==>, ->, -->, the arrow U+2192 and the double
arrow U+21D2, are refused, so a claim written with one isn't read as a
remark and left unchecked.")

(defparameter *signals-words* '("signal" "signals" "signalled" "signaled")
  "The words a comment can start with to name the error a form signals:
signals is the marker, and the others, past tenses included, are refused,
so a claim written with one isn't read as a remark and left unchecked.")

(defun signals-word-p (word)
  "True when WORD, a comment's first word, spells a ;; signals marker in
some way: one of *SIGNALS-WORDS*, in any case, with or without a colon."
  (member (string-right-trim ":" word) *signals-words* :test #'string-equal))

(defun comment-marker (line)
  "The marker that LINE, one of a gap's lines, starts with, as three
values: :VALUE for an arrow of *VALUE-ARROWS*, :SIGNALS for a word that
SIGNALS-WORD-P accepts, or NIL when LINE is no line comment, or one that
starts with neither; the text after the marker; and the marker as
written. Neither its spelling nor its semicolons are checked here, so a
marker written ==>, Signals: or with one semicolon is still found, and
refused, rather than read as a remark."
  (when (consp line)
    (let* ((text (string-left-trim '(#\Space #\Tab) (cdr line)))
           (arrow (find-if (lambda (arrow) (text-at-p arrow text 0)) *value-arrows*))
           (word (leading-word text)))
      (cond (arrow (values :value (subseq text (length arrow)) arrow))
            ((signals-word-p word) (values :signals (subseq text (length word)) word))
            (t nil)))))

(defun marker-word (kind)
  "The marker of KIND as check-docs reads it: => for :VALUE, signals for
:SIGNALS."
  (ecase kind
    (:value "=>")
    (:signals "signals")))

(defun marker-spelling-p (kind written)
  "True when WRITTEN, a marker of KIND as written, is MARKER-WORD's."
  (string= written (marker-word kind)))

(defun respelt-marker (kind text)
  "A marker of KIND, followed by TEXT, as check-docs reads it: two
semicolons, then MARKER-WORD's."
  (squeeze-whitespace (format nil ";; ~A ~A" (marker-word kind) text)))

(defun comment-text (line)
  "LINE, a line comment, as it is written, on one line: its semicolons,
then its text."
  (squeeze-whitespace
   (concatenate 'string (make-string (car line) :initial-element #\;) (cdr line))))

(defun two-semicolons-p (line)
  "True when LINE, a line comment, starts with exactly two semicolons."
  (= (car line) 2))

(defun continuation-line-p (line)
  "True when LINE, one of a gap's lines, continues a ;; => value above it:
a line comment written with two semicolons that holds no marker."
  (and (consp line) (two-semicolons-p line) (not (comment-marker line))))

(defun continuation-lines (lines)
  "The lines at the start of LINES that continue a ;; => value."
  (loop for line in lines
        while (continuation-line-p line)
        collect line))

;;; Reading a block: the gap between two forms

(defun block-comment-end (text start)
  "The position just after the block comment, #| ... |#, that starts at
START in TEXT, or TEXT's length when it never ends. Block comments nest,
as the reader reads them."
  (let ((depth 0)
        (index start))
    (loop
      (cond ((>= index (length text))
             (return (length text)))
            ((text-at-p "#|" text index)
             (incf depth)
             (incf index 2))
            ((text-at-p "|#" text index)
             (decf depth)
             (incf index 2)
             (when (zerop depth)
               (return index)))
            (t (incf index))))))

(defun scan-gap (text start)
  "The gap in TEXT from START to the next form: the whitespace and the
comments the reader skips. Returns two values: the gap's lines, and the
next form's start, or NIL when TEXT ends first. Each line is :BLANK; a
line comment, as LINE-COMMENT gives it; or :OTHER, a line that a block
comment touches, unless a line comment that holds a marker ends it, so
the marker is still read. The first line is what follows START on its
line, and the last ends where the next form starts."
  (let ((lines '())
        (line :blank)
        (index start))
    (flet ((end-line ()
             (push line lines)
             (setf line :blank)))
      (loop
        (let ((char (and (< index (length text)) (char text index))))
          (cond ((null char)
                 (end-line)
                 (return (values (nreverse lines) nil)))
                ((char= char #\Newline)
                 (end-line)
                 (incf index))
                ((reader-whitespace-p char)
                 (incf index))
                ((char= char #\;)
                 (let* ((end (or (position #\Newline text :start index) (length text)))
                        (comment (line-comment text index end)))
                   (setf line (if (or (eql line :blank) (comment-marker comment)) comment :other)
                         index end)))
                ((text-at-p "#|" text index)
                 (let ((end (block-comment-end text index)))
                   (setf line :other)
                   (loop for newline = (position #\Newline text :start index :end end)
                         while newline
                         do (end-line)
                            (setf line :other
                                  index (1+ newline)))
                   (setf index end)))
                (t
                 (end-line)
                 (return (values (nreverse lines) index)))))))))

;;; Reading a block: markers inside a form

(defun delimited-end (text start)
  "The position just after the string or the |name| that opens at START
in TEXT, whose delimiter is the character there: just after the next one
that no backslash escapes, or TEXT's length."
  (let ((delimiter (char text start))
        (index (1+ start)))
    (loop
      (cond ((>= index (length text)) (return (length text)))
            ((char= (char text index) #\\) (incf index 2))
            ((char= (char text index) delimiter) (return (1+ index)))
            (t (incf index))))))

(defun hidden-marker (source)
  "The first line comment in SOURCE, an example's form as written, that
holds a marker, as written; or NIL. The reader skips a comment inside a
form, so a claim there is never checked: a ;; => on a form's first line
when the form ends on a later one, say. Strings, |names|, block comments
and the character after a backslash, which covers characters written
#\\, are skipped, as the reader skips them, so a semicolon inside one
starts no comment."
  (let ((index 0))
    (loop
      (when (>= index (length source))
        (return nil))
      (let ((char (char source index)))
        (cond ((or (char= char #\") (char= char #\|))
               (setf index (delimited-end source index)))
              ((char= char #\\)
               (incf index 2))
              ((text-at-p "#|" source index)
               (setf index (block-comment-end source index)))
              ((char= char #\;)
               (let* ((end (or (position #\Newline source :start index) (length source)))
                      (comment (line-comment source index end)))
                 (when (comment-marker comment)
                   (return (comment-text comment)))
                 (setf index end)))
              (t (incf index)))))))

;;; Reading a block: the reader

(define-condition reader-conditional-refused (reader-error) ()
  (:report "uses #+ or #-, which can hide an expectation")
  (:documentation "Signalled while an example is read, at a #+ or a #-. A
reader conditional whose feature is false makes the reader skip the next
form, and the comments after it, so an expectation there would go
unchecked."))

(defun refuse-reader-conditional (stream char argument)
  "The reader macro of #+ and #- in *EXAMPLE-READTABLE*: it signals
READER-CONDITIONAL-REFUSED."
  (declare (ignore char argument))
  (error 'reader-conditional-refused :stream stream))

(defun make-example-readtable ()
  "A copy of the standard readtable in which #+ and #- signal
READER-CONDITIONAL-REFUSED."
  (let ((readtable (copy-readtable nil)))
    (set-dispatch-macro-character #\# #\+ #'refuse-reader-conditional readtable)
    (set-dispatch-macro-character #\# #\- #'refuse-reader-conditional readtable)
    readtable))

(defparameter *example-readtable* (make-example-readtable)
  "The readtable examples are read with: the standard syntax, apart from
#+ and #-, which MAKE-EXAMPLE-READTABLE refuses.")

(defun read-in-page (text start package)
  "Read the form in TEXT that starts at START, in PACKAGE, with
*EXAMPLE-READTABLE*, so #+ and #- are refused, and *READ-EVAL* false, so
#. can't run code while a page is read. Returns three values: the form;
the position just after it, before the whitespace that ends it, so a
comment on its line falls in the gap after it; and NIL. When TEXT holds
no form after START, the first two are NIL. When the reader signals an
error, the first two are NIL and the third is that error."
  (let ((eof (make-symbol "EOF")))
    (handler-case
        (with-standard-io-syntax
          (let ((*package* package)
                (*readtable* *example-readtable*)
                (*read-eval* nil))
            (multiple-value-bind (form end)
                (read-from-string text nil eof :start start :preserve-whitespace t)
              (if (eql form eof)
                  (values nil nil nil)
                  (values form end nil)))))
      (error (condition)
        (values nil nil condition)))))

(defun condition-report (condition package)
  "CONDITION's report, on one line, its symbols printed as PACKAGE sees
them."
  (squeeze-whitespace (let ((*package* package))
                        (princ-to-string condition))))

(defun unreadable-problem (condition package)
  "What a problem says of text that the reader refused with CONDITION:
for a #+ or a #-, READER-CONDITIONAL-REFUSED's report alone; otherwise
that the text can't be read, and why."
  (if (typep condition 'reader-conditional-refused)
      (condition-report condition package)
      (format nil "can't be read: ~A" (condition-report condition package))))

;;; Reading a block: expectations

(defun value-expectation (marker text continuation)
  "The expectation of the ;; => line MARKER, whose text after => is TEXT,
continued by the lines CONTINUATION: (:VALUE VALUE), VALUE their text
joined with its whitespace squeezed. Returns, as a second value, the
problem when they hold no value."
  (let ((value (squeeze-whitespace (format nil "~A~{ ~A~}" text (mapcar #'cdr continuation)))))
    (if (zerop (length value))
        (values nil (format nil "~A holds no value" (comment-text marker)))
        (values (list :value value) nil))))

(defun signals-expectation (marker text package)
  "The expectation of the ;; signals line MARKER, whose text after signals
is TEXT: (:SIGNALS NAME), NAME the name TEXT starts with, read in PACKAGE,
so it may be a library condition or one of COMMON-LISP's. Returns, as a
second value, the problem when TEXT names nothing or can't be read."
  (multiple-value-bind (name end condition) (read-in-page text 0 package)
    (cond (condition
           (values nil (format nil "~A can't be read: ~A"
                               (comment-text marker) (condition-report condition package))))
          ((null end)
           (values nil (format nil "~A names no condition" (comment-text marker))))
          (t (values (list :signals name) nil)))))

(defun gap-expectation (lines package)
  "The expectation that LINES, the gap after a form, hold for it, and the
problem that keeps it from running, as two values; both NIL when LINES
hold no marker.
- ;; => TEXT, on the form's line or a later one: (:VALUE TEXT). The ;;
  lines directly after it continue TEXT, until a line that is blank,
  holds a marker, or is no comment written with two semicolons. So a
  remark below an expectation needs a blank line first.
- ;; signals NAME: (:SIGNALS NAME), NAME read in PACKAGE.
Other ;; comments are remarks. A gap holds at most one marker, spelt =>
or signals and written with two semicolons: anything else is a problem,
not an expectation left unchecked."
  (let ((tail (member-if #'comment-marker lines)))
    (if (null tail)
        (values nil nil)
        (multiple-value-bind (kind text written) (comment-marker (first tail))
          (let* ((continuation (if (eql kind :value) (continuation-lines (rest tail)) '()))
                 (another (find-if #'comment-marker (nthcdr (length continuation) (rest tail)))))
            (cond ((not (marker-spelling-p kind written))
                   (values nil (format nil "write ~A as ~A"
                                       (comment-text (first tail)) (respelt-marker kind text))))
                  ((not (two-semicolons-p (first tail)))
                   (values nil (format nil "~A needs two semicolons" (comment-text (first tail)))))
                  (another
                   (values nil (format nil "~A is a second expectation" (comment-text another))))
                  ((eql kind :value)
                   (value-expectation (first tail) text continuation))
                  (t (signals-expectation (first tail) text package))))))))

;;; Reading a block: the examples

(defstruct example
  "One example of a block, as it is read. SOURCE is its text as written.
FORM is the form read from it, and EXPECTATION what the form should do:
(:VALUE TEXT), its first value prints as TEXT; (:SIGNALS NAME), it signals
an error of the type NAME; or NIL, it signals no error. PROBLEM, when set,
says why the example doesn't run: its expectation is malformed, or a
marker is inside its form; or it is a marker before any form, or text the
reader refuses."
  (source "")
  (form nil)
  (expectation nil)
  (problem nil))

(defun form-example (text start end form package)
  "The example of FORM, read in PACKAGE from TEXT between START and END,
and the next form's start, or NIL, as two values. Its expectation is the
one the gap after it holds. A marker inside the form, which HIDDEN-MARKER
finds, is the example's problem, ahead of any the gap holds."
  (let* ((source (subseq text start end))
         (hidden (hidden-marker source)))
    (multiple-value-bind (lines next) (scan-gap text end)
      (multiple-value-bind (expectation problem) (gap-expectation lines package)
        (values (make-example :source source
                              :form form
                              :expectation expectation
                              :problem (if hidden
                                           (format nil "~A is inside the form, so it checks nothing"
                                                   hidden)
                                           problem))
                next)))))

(defun map-examples (function text package)
  "Call FUNCTION on each example of TEXT, a block's code, read in PACKAGE,
in order, and return the number of forms read. Each form is read only
after FUNCTION has returned for the one before it, so a form can use a
package that an earlier one defines, as at a REPL. Two kinds of example
hold no form, only a problem: a marker before the first form, which no
form owns, and text the reader refuses, a #+ or a #- among it, after
which reading the block stops."
  (multiple-value-bind (lines start) (scan-gap text 0)
    (dolist (line lines)
      (when (comment-marker line)
        (funcall function (make-example :source (comment-text line)
                                        :problem "comes before any form"))))
    (loop with forms = 0
          while start
          do (multiple-value-bind (form end condition) (read-in-page text start package)
               (cond (condition
                      (funcall function
                               (make-example :source (subseq text start)
                                             :problem (unreadable-problem condition package)))
                      (return forms))
                     ((null end)
                      (return forms))
                     (t
                      (incf forms)
                      (multiple-value-bind (example next) (form-example text start end form package)
                        (funcall function example)
                        (setf start next)))))
          finally (return forms))))

(defun block-examples (text package)
  "The examples of TEXT, a block's code, read in PACKAGE and not run, in
order."
  (let ((examples '()))
    (map-examples (lambda (example) (push example examples)) text package)
    (nreverse examples)))

;;; Printing and comparing

(defun print-value (value package)
  "VALUE as an expectation's text is compared with it: PRIN1's text, with
symbols in lower case and without a prefix where PACKAGE sees them, so a
keyword prints as :document; no pretty printing, so the printer adds no
line breaks; and each newline written as the two characters \\n, so a
string with newlines prints on one line. The rest of the printer's state
is the standard one, so the image's settings change nothing, apart from
*PRINT-READABLY*, which stays false, so a value with no readable form,
such as a condition, still prints."
  (let ((printed (with-standard-io-syntax
                   (let ((*package* package)
                         (*print-case* :downcase)
                         (*print-pretty* nil)
                         (*print-readably* nil))
                     (prin1-to-string value)))))
    (with-output-to-string (out)
      (loop for char across printed
            do (if (char= char #\Newline)
                   (write-string "\\n" out)
                   (write-char char out))))))

(defun same-text-p (expected printed)
  "True when EXPECTED, an expectation's text, and PRINTED, a value as
PRINT-VALUE prints it, are the same once each run of whitespace in either
is one space, and none is at either end."
  (string= (squeeze-whitespace expected) (squeeze-whitespace printed)))

;;; Running a page's examples

(defun make-page-package ()
  "A fresh package for one page's examples, which uses COMMON-LISP and
CL-COMMONMARK-GFM, as a user's own package would: named
CL-COMMONMARK-GFM.SITE.EXAMPLES-N, with the first N no package has."
  (loop for index from 1
        for name = (format nil "CL-COMMONMARK-GFM.SITE.EXAMPLES-~D" index)
        unless (find-package name)
          return (make-package name :use '("COMMON-LISP" "CL-COMMONMARK-GFM"))))

(defun compiler-note-type ()
  "SBCL's type for the compiler's notes, SB-EXT:COMPILER-NOTE, found by
name so this file reads in any Lisp; or NIL in a Lisp without it."
  (let ((package (find-package "SB-EXT")))
    (and package (find-symbol "COMPILER-NOTE" package))))

(defun compiler-remark-p (condition)
  "True when CONDITION is the compiler's remark on an example's code,
which decides nothing the check reports: a style warning, such as a call
to a function not yet defined, or a compiler note."
  (or (typep condition 'style-warning)
      (let ((note (compiler-note-type)))
        (and note (typep condition note)))))

(defun muffle (condition)
  "Muffle CONDITION, a warning or a compiler note, when a MUFFLE-WARNING
restart is there to do it; otherwise do nothing."
  (let ((restart (find-restart 'muffle-warning condition)))
    (when restart
      (invoke-restart restart))))

(defun run-form (form package)
  "FORM's first value, evaluated in PACKAGE, with what it writes to
*STANDARD-OUTPUT* discarded; or, as a second value, the error it signals
instead. The third value is the package *PACKAGE* is left bound to, and
the fourth the first warning FORM signals that isn't a compiler remark,
as COMPILER-REMARK-P reads it, or NIL: an undefined variable, say, which
means the example is wrong. Every warning and note is muffled, a remark
because it decides nothing, and a warning because the check reports it.
Only errors are caught: any other condition goes on to the caller's
handlers."
  (let ((warning nil))
    (flet ((handle (condition)
             (cond ((compiler-remark-p condition)
                    (muffle condition))
                   ((typep condition 'warning)
                    (unless warning
                      (setf warning condition))
                    (muffle condition)))))
      (handler-case (let ((*package* package)
                          (*standard-output* (make-broadcast-stream)))
                      (handler-bind ((condition #'handle))
                        (let ((value (eval form)))
                          (values value nil *package* warning))))
        (error (condition)
          (values nil condition package warning))))))

(defun condition-problem (verb condition package)
  "CONDITION, which an example signalled, as a problem names it: VERB,
then its type and its report, such as signalled simple-error: Boom."
  (format nil "~A ~A: ~A"
          verb
          (print-value (type-of condition) package)
          (condition-report condition package)))

(defun signalled (condition package)
  "CONDITION, an error an example signalled, as a problem names it."
  (condition-problem "signalled" condition package))

(defun error-type-p (name)
  "True when NAME, read from a ;; signals line, names ERROR or a subtype of
it. NIL is the empty type, a subtype of every type, but names no
condition; and a name that is no type specifier at all names no
subtype."
  (and name
       (ignore-errors (values (subtypep name 'error)))))

(defun value-problem (expected value condition package)
  "What went wrong with a form whose expectation is (:VALUE EXPECTED), and
which returned VALUE, or signalled CONDITION; or NIL."
  (if condition
      (format nil "expected ~A, but ~A" expected (signalled condition package))
      (let ((printed (print-value value package)))
        (unless (same-text-p expected printed)
          (format nil "expected ~A, got ~A" expected (squeeze-whitespace printed))))))

(defun signals-problem (name value condition package)
  "What went wrong with a form whose expectation is (:SIGNALS NAME), and
which returned VALUE, or signalled CONDITION; or NIL, when CONDITION is of
the type NAME, or of a subtype. NAME must name a subtype of ERROR, since
only errors are caught."
  (let ((named (print-value name package)))
    (cond ((not (error-type-p name))
           (format nil "expected to signal ~A, which isn't a subtype of error" named))
          ((null condition)
           (format nil "expected to signal ~A, but returned ~A"
                   named (squeeze-whitespace (print-value value package))))
          ((typep condition name) nil)
          (t (format nil "expected to signal ~A, but ~A" named (signalled condition package))))))

(defun moved-package-p (condition left package)
  "True when a form run in PACKAGE returned, rather than signal CONDITION,
with *PACKAGE* left bound to LEFT, another package."
  (and (null condition) (not (eql left package))))

(defun check-example (example package)
  "What went wrong with EXAMPLE, run in PACKAGE, as a string, or NIL when
it does what its expectation says. An example with a problem doesn't run:
the problem is what went wrong. Whatever the form returns or signals, it
is refused when it signals a warning that RUN-FORM reports, and then when
it returns with *PACKAGE* bound to another package, as IN-PACKAGE leaves
it: the next form is still read in PACKAGE, as it wouldn't be at a REPL."
  (or (example-problem example)
      (multiple-value-bind (value condition left warning)
          (run-form (example-form example) package)
        (destructuring-bind (&optional kind expected) (example-expectation example)
          (cond (warning
                 (condition-problem "warned" warning package))
                ((moved-package-p condition left package)
                 (format nil "sets *package* to ~A, but each form is read in the page's package"
                         (print-value left package)))
                (t
                 (ecase kind
                   ((nil) (and condition (signalled condition package)))
                   (:value (value-problem expected value condition package))
                   (:signals (signals-problem expected value condition package)))))))))

(defparameter *form-label-width* 60
  "The most characters of an example's text that a problem shows.")

(defun form-label (source)
  "SOURCE, an example's text as written, as a problem shows it: on one
line, each run of whitespace one space, and cut to *FORM-LABEL-WIDTH*
characters, ending in ..., when it is longer."
  (let ((text (squeeze-whitespace source)))
    (if (> (length text) *form-label-width*)
        (concatenate 'string (subseq text 0 (- *form-label-width* (length "..."))) "...")
        text)))

(defun problem-line (name block label problem)
  "PROBLEM, what went wrong in the block numbered BLOCK on the page NAME,
as check-docs reports it: NAME: block BLOCK: LABEL: PROBLEM. LABEL names
what went wrong, such as an example's text as FORM-LABEL shows it."
  (format nil "~A: block ~D: ~A: ~A" name block label problem))

(defun refused-block-problem (name block info)
  "The problem with the block numbered BLOCK on the page NAME, whose info
string INFO names Lisp, but neither runs it nor skips it. INFO is shown
as written, quoted, and not as FORM-LABEL would show it: its whitespace
squeezed would hide the difference from lisp no-run of a fence written
lisp  no-run, with two spaces."
  (problem-line name block (format nil "info string ~S" info)
                "fence it ```lisp to run it, or ```lisp no-run to skip it"))

(defun check-lisp-block (name block info code package)
  "Check the block numbered BLOCK on the page NAME, whose info string is
INFO and whose code is CODE, running its examples in PACKAGE: a block
that BLOCK-TREATMENT refuses is a problem, and its code isn't read.
Returns two values: the block's problems, in order; and its number of
examples, the forms read."
  (ecase (block-treatment info)
    (:run
     (let* ((problems '())
            (examples (map-examples
                       (lambda (example)
                         (let ((problem (check-example example package)))
                           (when problem
                             (push (problem-line name block
                                                 (form-label (example-source example)) problem)
                                   problems))))
                       code
                       package)))
       (values (nreverse problems) examples)))
    (:refuse
     (values (list (refused-block-problem name block info)) 0))))

(defun parse-lisp-blocks (markdown)
  "LISP-BLOCKS of MARKDOWN; or NIL and, as a second value, the error that
parsing MARKDOWN signals instead, such as a limit's."
  (handler-case (values (lisp-blocks markdown) nil)
    (error (condition)
      (values nil condition))))

(defun check-page-blocks (name markdown package)
  "Check the Lisp blocks of the page NAME, whose text is MARKDOWN, in
order, running their examples in PACKAGE, as CHECK-PAGE-EXAMPLES says. A
page that can't be parsed is one problem, which names the error."
  (multiple-value-bind (blocks condition) (parse-lisp-blocks markdown)
    (if condition
        (values (list (format nil "~A: can't be parsed: ~A" name (signalled condition package))) 0)
        (loop for (info . code) in blocks
              for block from 1
              for (block-problems found) = (multiple-value-list
                                            (check-lisp-block name block info code package))
              append block-problems into problems
              sum found into examples
              finally (return (values problems examples))))))

(defun library-variables ()
  "The special variables CL-COMMONMARK-GFM exports, such as *MAX-NODES*."
  (let ((variables '()))
    (do-external-symbols (symbol "CL-COMMONMARK-GFM" variables)
      (when (and (boundp symbol) (not (constantp symbol)))
        (push symbol variables)))))

(defun check-page-examples (name markdown)
  "Run the examples of the page NAME, whose text is MARKDOWN: each block
that runs, in order, in one fresh package from MAKE-PAGE-PACKAGE, so a
block can use what an earlier one defines, but no page sees another's.
The package is deleted afterwards, whatever happens. The page is parsed
and run with LIBRARY-VARIABLES bound afresh, at their values as it
starts, so an example that sets one, *MAX-NODES* say, changes it for its
own page alone. Returns two values: the problems, each NAME: block N:
FORM: WHAT WENT WRONG, the blocks that run or are refused numbered from
1, or one problem for a page that can't be parsed; and the number of
examples, the forms read."
  (let ((variables (library-variables))
        (package (make-page-package)))
    (unwind-protect
         (progv variables (mapcar #'symbol-value variables)
           (check-page-blocks name markdown package))
      (delete-package package))))

(defun check-examples (pages)
  "Run the examples of PAGES, each (NAME . MARKDOWN), page by page, with
CHECK-PAGE-EXAMPLES. Returns three values: the problems, in page order;
the number of examples; and the number of pages that hold one."
  (loop for (name . markdown) in pages
        for (problems found) = (multiple-value-list (check-page-examples name markdown))
        append problems into all-problems
        sum found into examples
        count (plusp found) into holding
        finally (return (values all-problems examples holding))))
