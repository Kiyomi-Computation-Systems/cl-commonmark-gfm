;;;; Resource limits that keep cmark-gfm from aborting or exhausting memory
;;;; (M2 design §5.5; ADR-0016).

(in-package #:cl-commonmark-gfm.native-core)

;;; The three variables and their hard caps

(defvar *max-input-octets* 1048576
  "The most UTF-8 octets an entry point accepts as input, checked before
encoding (M2 design §5.5): guards cmark's parse buffers, which can reach
three times the input's octets (a NUL or a smart quote becomes three bytes).
Default 1,048,576 (1 MiB). A binding above +MAX-INPUT-OCTETS-HARD-CAP+,
268,435,456 (256 MiB), is held to that cap (EFFECTIVE-MAXIMUM); the hard cap
applies whatever this variable is bound to.

The remaining risk: on a machine already short of memory, cmark's allocator
can still abort (ADR-0016).")

(defconstant +max-input-octets-hard-cap+ 268435456
  "The hard cap on *MAX-INPUT-OCTETS*, 268,435,456 (256 MiB) (M2 design
§5.5): no binding raises the effective maximum above this.")

(defvar *max-nodes* 1000000
  "The most AST nodes, the document node included, a parse accepts: checked
against the table-cell bound before parsing, and counted while copying the
tree (M2 design §5.5). Guards cmark's own memory -- padded table cells can
multiply nodes well past the input's size -- and the Lisp heap the copy
builds. Default 1,000,000. No hard cap: raise it as far as the machine's
memory allows.

The remaining risk: on a machine already short of memory, cmark's allocator
can still abort (ADR-0016).")

(defvar *max-output-octets* 67108864
  "The most UTF-8 octets MARKDOWN->HTML and MARKDOWN->PLAINTEXT accept
producing, checked after parsing and before rendering (M2 design §5.5):
guards cmark_strbuf_grow's abort(), which fires above 1,073,741,823 bytes
(vendor/cmark-gfm/src/buffer.c). Default 67,108,864 (64 MiB). A binding
above +MAX-OUTPUT-OCTETS-HARD-CAP+, 536,870,912 (512 MiB, half the abort
threshold), is held to that cap (EFFECTIVE-MAXIMUM); the hard cap applies
whatever this variable is bound to.

The remaining risk: on a machine already short of memory, cmark's allocator
can still abort (ADR-0016).")

(defconstant +max-output-octets-hard-cap+ 536870912
  "The hard cap on *MAX-OUTPUT-OCTETS*, 536,870,912 (512 MiB), half cmark's
abort threshold of 1,073,741,823 bytes (M2 design §5.5).")

;;; EFFECTIVE-MAXIMUM

(defun check-non-negative-integer (value)
  "Signal a TYPE-ERROR whose datum is VALUE unless it is a non-negative
integer."
  (unless (typep value '(integer 0))
    (error 'type-error :datum value :expected-type '(integer 0))))

(defun effective-maximum (symbol)
  "The effective maximum for SYMBOL, one of *MAX-INPUT-OCTETS*, *MAX-NODES*
or *MAX-OUTPUT-OCTETS*: its current value, or its hard cap when that is
lower (M2 design §5.5). Returns a second value, true exactly when the hard
cap applied (i.e. when the variable's own value is above its hard cap).

SYMBOL naming anything else is a programming error (ECASE). A value that
isn't a non-negative integer signals a TYPE-ERROR whose datum is that
value."
  (multiple-value-bind (value cap)
      (ecase symbol
        (*max-input-octets* (values *max-input-octets* +max-input-octets-hard-cap+))
        (*max-nodes* (values *max-nodes* nil))
        (*max-output-octets* (values *max-output-octets* +max-output-octets-hard-cap+)))
    (check-non-negative-integer value)
    (if (and cap (> value cap))
        (values cap t)
        (values value nil))))

;;; CHECK-LIMIT

(defun limit-reason (symbol cappedp)
  "The REASON CHECK-LIMIT gives for SYMBOL: naming whichever of the
variable and its hard cap set the effective maximum."
  (if cappedp
      (format nil "~(~A~)'s hard cap exceeded" symbol)
      (format nil "~(~A~) exceeded" symbol)))

(defun check-limit (symbol value operation)
  "Signal RESOURCE-LIMIT-EXCEEDED for OPERATION when VALUE is above SYMBOL's
effective maximum (M2 design §5.5); passes when VALUE is at the maximum
exactly. :DATUM is VALUE, :LIMIT is SYMBOL, :MAXIMUM is the effective
maximum, and :REASON says whether SYMBOL's variable or its hard cap set the
maximum."
  (multiple-value-bind (maximum cappedp) (effective-maximum symbol)
    (when (> value maximum)
      (error 'resource-limit-exceeded
             :operation operation
             :datum value
             :limit symbol
             :maximum maximum
             :reason (limit-reason symbol cappedp)))))

;;; TABLE-CELL-BOUND (M2 design §5.5)

(defun blank-line-char-p (char)
  "True when CHAR may appear in a blank line: space or tab, the only two
characters IS-BLANK accepts (vendor/cmark-gfm/src/blocks.c)."
  (or (char= char #\Space) (char= char #\Tab)))

(defun candidate-line-char-p (char)
  "True when CHAR may appear in a delimiter-row candidate line: >, |, :, -,
space, tab, VT (code 11) or FF (code 12) -- a block-quote or list-item
prefix, then a delimiter row's own characters, TABLE_MARKER's SPACECHAR
included (vendor/cmark-gfm/extensions/ext_scanners.re)."
  (or (member char '(#\> #\| #\: #\-))
      (char= char #\Space)
      (char= char #\Tab)
      (char= char (code-char 11))
      (char= char (code-char 12))))

(defun table-cell-bound (string)
  "An upper bound on the table cells cmark-gfm would build while parsing
STRING (M2 design §5.5), in one pass over STRING that builds no list of
lines.

Lines end at LF, CR or CRLF, a CRLF counting as one line end. A RUN is a
maximal sequence of lines that aren't blank: a blank line holds only spaces
and tabs (IS-BLANK), and an empty line is blank. For each run, the bound
adds the most runs of - on any CANDIDATE line of the run -- a line holding
only CANDIDATE-LINE-CHAR-P's characters, where each column of a delimiter
row is one run of - (TABLE_MARKER) -- times the run's number of lines,
candidate or not."
  (let ((length (length string))
        (index 0)
        (line-length 0)
        (blank-so-far t)
        (candidate-so-far t)
        (dash-runs 0)
        (in-dash-run nil)
        (run-active nil)
        (run-lines 0)
        (run-max-dashes 0)
        (total 0))
    (labels ((start-line ()
               (setf line-length 0 blank-so-far t candidate-so-far t
                     dash-runs 0 in-dash-run nil))
             (close-run ()
               (when run-active
                 (incf total (* run-max-dashes run-lines))
                 (setf run-active nil run-lines 0 run-max-dashes 0)))
             (close-line ()
               (cond
                 (blank-so-far (close-run))
                 (t
                  (unless run-active
                    (setf run-active t run-lines 0 run-max-dashes 0))
                  (incf run-lines)
                  (when (and candidate-so-far (> dash-runs run-max-dashes))
                    (setf run-max-dashes dash-runs)))))
             (note-char (char)
               (incf line-length)
               (when (and blank-so-far (not (blank-line-char-p char)))
                 (setf blank-so-far nil))
               (when (and candidate-so-far (not (candidate-line-char-p char)))
                 (setf candidate-so-far nil))
               (cond
                 ((char= char #\-)
                  (unless in-dash-run
                    (setf in-dash-run t)
                    (incf dash-runs)))
                 (t (setf in-dash-run nil)))))
      (loop while (< index length)
            do (let ((char (char string index)))
                 (cond
                   ((char= char #\Return)
                    (close-line)
                    (incf index (if (and (< (1+ index) length)
                                          (char= (char string (1+ index)) #\Linefeed))
                                     2
                                     1))
                    (start-line))
                   ((char= char #\Linefeed)
                    (close-line)
                    (incf index)
                    (start-line))
                   (t
                    (note-char char)
                    (incf index)))))
      (when (plusp line-length)
        (close-line))
      (close-run))
    total))
