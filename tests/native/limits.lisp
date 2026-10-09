;;;; The limits through PARSE. Each is checked before cmark does the work
;;;; it guards: the input octets and the table-cell bound before any
;;;; parser, the node count while copying. The monotonic parser count shows
;;;; which came first, and every test ends with the open counters at zero.

(in-package #:cl-commonmark-gfm.native-tests)

;;; The input limit counts UTF-8 octets

(define-test an-input-at-the-octet-limit-parses-and-one-octet-more-does-not
  ;; é is two octets. "abcdefgh" then é is 10 octets in 9 characters.
  ;; "abcdefghi" then é is 11 octets in 10 characters: at the limit by
  ;; characters, and past it by octets.
  (native-state)
  (let ((*max-input-octets* 10))
    (is eql :document (node-kind (parse "abcdefghé")) "10 octets")
    (let* ((parsers (created-parsers))
           (condition (raised resource-limit-exceeded (parse "abcdefghié") "11 octets")))
      (when condition
        (is eql 'parse (condition-operation condition))
        (is eql '*max-input-octets* (condition-limit condition))
        (is eql 11 (condition-datum condition))
        (is eql 10 (condition-maximum condition)))
      (is = parsers (created-parsers) "rejected before any parser")))
  (true (open-counts-zero-p)))

;;; The node limit: the table-cell bound before parsing, then the count
;;; while copying

(defun padded-table (columns rows)
  "A table COLUMNS wide, with ROWS body rows of one cell each. cmark pads
each body row with COLUMNS - 1 empty cells (try_opening_table_row,
extensions/table.c), so it builds COLUMNS x (ROWS + 1) cells."
  (with-output-to-string (out)
    (dotimes (column columns)
      (write-string "| h " out))
    (write-line "|" out)
    (dotimes (column columns)
      (write-string "|---" out))
    (write-line "|" out)
    (dotimes (row rows)
      (write-line "| x |" out))))

(define-test a-padded-table-past-the-cell-bound-is-rejected-before-any-parser
  ;; 100 columns and 50 one-cell rows: cmark would build 5,100 cells. The
  ;; bound is the delimiter row's 100 dash runs times the 52 lines of their
  ;; run: 5,200, past *max-nodes* bound to 5,000.
  (native-state)
  (let* ((parsers (created-parsers))
         (condition (let ((*max-nodes* 5000))
                      (raised resource-limit-exceeded (parse (padded-table 100 50))))))
    (when condition
      (is eql 'parse (condition-operation condition))
      (is eql '*max-nodes* (condition-limit condition))
      (is eql 5200 (condition-datum condition) "the table-cell bound")
      (is eql 5000 (condition-maximum condition)))
    (is = parsers (created-parsers) "rejected before any parser"))
  (true (open-counts-zero-p)))

(define-test a-document-past-max-nodes-is-rejected-while-copying
  ;; Three one-line paragraphs: the document, three paragraphs and three
  ;; texts are 7 nodes, and no table, so the bound is 0. Under 6, cmark
  ;; parses it, and the copy stops at its seventh node.
  (native-state)
  (let ((markdown (markdown-lines "a" "" "b" "" "c")))
    (is eql :document (node-kind (let ((*max-nodes* 7)) (parse markdown))) "7 nodes under 7")
    (let* ((parsers (created-parsers))
           (condition (let ((*max-nodes* 6))
                        (raised resource-limit-exceeded (parse markdown) "7 nodes under 6"))))
      (when condition
        (is eql 'parse (condition-operation condition))
        (is eql '*max-nodes* (condition-limit condition))
        (is eql 7 (condition-datum condition) "the node that broke the limit")
        (is eql 6 (condition-maximum condition)))
      (is = (1+ parsers) (created-parsers) "rejected after cmark parsed it")))
  (true (open-counts-zero-p)))

(define-test a-limit-bound-to-a-non-integer-signals-a-type-error-before-any-parser
  ;; A limit's variable must hold a non-negative integer.
  (native-state)
  (let ((parsers (created-parsers)))
    (let ((*max-input-octets* -1))
      (fail (parse "x") 'type-error "*max-input-octets* -1"))
    (let ((*max-nodes* "many"))
      (fail (parse "x") 'type-error "*max-nodes* \"many\""))
    (is = parsers (created-parsers) "no parser"))
  (true (open-counts-zero-p)))

;;; Every entry point checks all three bindings first, before any native
;;; call, whether or not it uses the limit: a bad *MAX-OUTPUT-OCTETS* must
;;; not wait for a whole parse and bound walk to surface, and PARSE must
;;; notice it too.

(defparameter *limit-variables*
  '(*max-input-octets* *max-nodes* cl-commonmark-gfm:*max-output-octets*)
  "The three limits' variables.")

(defparameter *bad-limit-values* (list -1 "many" 1.5)
  "A value no limit variable may hold: a negative integer, a string and a
float.")

(defun bad-limit-outcome (function variable value)
  "Call FUNCTION, an entry point, on \"x\" with VARIABLE bound to VALUE.
Return a plist: :TYPE-ERROR, true when it signalled a TYPE-ERROR; :DATUM,
that error's datum; :PARSERS, how many parsers it created."
  (native-state)
  (let* ((parsers (created-parsers))
         (condition (handler-case (progv (list variable) (list value)
                                    (funcall function "x")
                                    nil)
                      (type-error (condition) condition))))
    (list :type-error (and condition t)
          :datum (and condition (type-error-datum condition))
          :parsers (- (created-parsers) parsers))))

(define-test a-bad-binding-of-any-limit-is-rejected-before-any-parser-by-every-entry-point
  (dolist (variable *limit-variables*)
    (dolist (value *bad-limit-values*)
      (dolist (function (list #'parse #'markdown->html #'markdown->plaintext
                              #'markdown->html-tree))
        (destructuring-bind (&key type-error datum parsers)
            (bad-limit-outcome function variable value)
          (let ((name (entry-point-name function)))
            (true type-error "~(~A~) ~S, ~A: a type-error" variable value name)
            (is equal value datum "~(~A~) ~S, ~A: the datum" variable value name)
            (is = 0 parsers "~(~A~) ~S, ~A: no parser" variable value name))))))
  (true (open-counts-zero-p)))

;;; The table-cell bound is sound: never below the cells the copy holds.
;;; Each input is built and parsed inside a helper, so no assertion holds a
;;; large one.

(defun crafted-tables ()
  "Tables that probe the table-cell bound: plain, padded, short and long
rows, inside a block quote, a list item and both, without outer pipes,
with lazy rows, escaped pipes or a delimiter-like row, after paragraph
text, with CR and with CRLF line ends, two in a row, with tabs, VT and FF
in the delimiter row, and indented. Every one builds cells under the pinned
CLI."
  (list (markdown-lines "| a | b |" "|---|---|" "| 1 | 2 |")
        (padded-table 7 5)
        (markdown-lines "| a | b | c |" "|:-:|---|--:|" "| 1 |" "| 1 | 2 | 3 | 4 | 5 |")
        (markdown-lines "> | a | b |" "> |---|---|" "> | 1 | 2 |")
        (markdown-lines "- | a | b |" "  |---|---|" "  | 1 | 2 |")
        (markdown-lines "a | b" "--|--" "1 | 2")
        (markdown-lines "| a | b |" "|---|---|" "lazy" "row")
        (markdown-lines "| a \\| b | c |" "|---|---|" "| 1 \\| 2 | 3 |")
        (markdown-lines "text" "| a | b |" "|---|---|" "| 1 | 2 |")
        (markdown-lines "| a |" "|---|" "| b |" "|---|")
        (format nil "| a | b |~C|---|---|~C| 1 | 2 |~C" #\Return #\Return #\Return)
        (format nil "| a | b |~C~C|---|---|~C~C| 1 | 2 |~C~C"
                #\Return #\Linefeed #\Return #\Linefeed #\Return #\Linefeed)
        (markdown-lines "| a |" "|---|" "" "| b | c |" "|---|---|" "| 1 |")
        (markdown-lines "| a | b |"
                        (format nil "|~C-~C|~C--|" #\Tab (code-char 11) (code-char 12))
                        "| 1 | 2 |")
        (markdown-lines "> - a | b" ">   --|--" ">   1 | 2")
        (markdown-lines "   | a |" "   |---|" "   | 1 |")))

(defun pathological-tables ()
  "cmark's \"tables\" stress input (test/pathological_tests.py): 30,000
copies of aaa CR bbb LF - VT LF. 330,000 octets."
  (cl-commonmark-gfm.tests::repeat-string
   (format nil "aaa~Cbbb~C-~C~C" #\Return #\Linefeed (code-char 11) #\Linefeed)
   30000))

(defun table-cell-count (ast)
  "How many :TABLE-CELL nodes AST holds."
  (let ((count 0))
    (walk-ast (lambda (event node)
                (when (and (eql event :enter) (eql (node-kind node) :table-cell))
                  (incf count)))
              ast)
    count))

(defun cells-and-bound (markdown)
  "The cells MARKDOWN's AST holds under PARSE's defaults, and MARKDOWN's
table-cell bound, as (CELLS BOUND)."
  (list (table-cell-count (parse markdown)) (table-cell-bound markdown)))

(defun crafted-table-facts ()
  "What the soundness test checks of CRAFTED-TABLES, as a plist:
:COMPARED, how many it compared; :WITHOUT-CELLS, the index of each that
built no cell; :UNDERCOUNTED, (INDEX CELLS BOUND) for each whose bound is
below its cells."
  (loop for markdown in (crafted-tables)
        for index from 0
        for (cells bound) = (cells-and-bound markdown)
        count t into compared
        when (zerop cells)
          collect index into without-cells
        when (< bound cells)
          collect (list index cells bound) into undercounted
        finally (return (list :compared compared
                              :without-cells without-cells
                              :undercounted undercounted))))

(define-test the-table-cell-bound-never-undercounts-crafted-tables
  (destructuring-bind (&key compared without-cells undercounted) (crafted-table-facts)
    (is = 16 compared)
    (is equal '() without-cells "every crafted table builds cells")
    (is equal '() undercounted)))

(define-test the-table-cell-bound-never-undercounts-cmarks-stress-inputs
  ;; No line of the three deep inputs is a delimiter-row candidate, and
  ;; none builds a table. In "tables", the first aaa is a paragraph, bbb
  ;; heads a one-column table whose delimiter row is - VT, and each of the
  ;; 89,997 lines after is a one-cell row: 89,998 cells. Its 90,000 lines
  ;; make one run, and each candidate line, - VT, holds one dash run: the
  ;; bound is 90,000.
  (is equal '(0 0) (cells-and-bound (nested-block-quotes)) "nested block quotes")
  (is equal '(0 0) (cells-and-bound (nested-emphasis)) "nested strong and emphasis")
  (is equal '(0 0) (cells-and-bound (nested-lists)) "deeply nested lists")
  (is equal '(89998 90000) (cells-and-bound (pathological-tables)) "tables")
  (true (open-counts-zero-p)))

;;; The output limit. MARKDOWN->HTML and MARKDOWN->PLAINTEXT check an upper
;;; bound on what cmark would write against *MAX-OUTPUT-OCTETS* after
;;; parsing and before rendering: a rejection comes after a parser was
;;; created, and before any render buffer. The bounds are HTML-OUTPUT-BOUND
;;; and PLAINTEXT-OUTPUT-BOUND, whose per-node terms the pure suite checks
;;; one by one.
;;;
;;; Inputs are built inside helpers, and every helper returns numbers or
;;; small lists, so no assertion holds a large string: Parachute keeps
;;; every assertion's closure until the run ends.

(defun repeated (string count)
  "STRING, COUNT times over."
  (cl-commonmark-gfm.tests::repeat-string string count))

(defun escaped-quotes (count)
  "COUNT double quotes: text escape_html writes as `&quot;`, 6 octets each
(src/houdini_html_e.c), the largest of its escapes."
  (make-string count :initial-element #\"))

(defun footnote-references (count &optional (label "a"))
  "COUNT references to one footnote labelled LABEL, then its definition.
Each reference writes the label twice and its own backref, which writes it
once more (S_render_node and S_put_footnote_backref, src/html.c)."
  (markdown-lines (repeated (format nil "[^~A] " label) count)
                  ""
                  (format nil "[^~A]: b" label)))

(defun adjacent-footnote-references (count)
  "COUNT references to one footnote labelled ', with nothing between them,
then its definition, whose text is a double quote: every octet of text
escapes at its longest, so the HTML bound's only slack is in its footnote
terms. With 300, the index suffixes outweigh that slack; with 9, whose
indices are all one digit, the slack is 5 octets, less than the footnote
section's 65 or the suffixes' 18."
  (markdown-lines (repeated "[^']" count) "" "[^']: \""))

(defun dropped-definition-references (count)
  "A footnote whose only references, COUNT of them, sit in a definition that
nothing references. process_footnotes (src/blocks.c) counts every one
before it drops that definition, so the kept footnote gets a backref for
each, while the parsed tree keeps none of them."
  (markdown-lines "[^a]: A"
                  ""
                  (concatenate 'string "[^b]:" (repeated " [^a]" count))))

(defun reference-link-expansion (destination-octets count)
  "A link reference definition whose destination is DESTINATION-OCTETS long,
then COUNT references to it: each renders the whole destination."
  (markdown-lines (concatenate 'string "[a]: /"
                               (make-string (1- destination-octets) :initial-element #\x))
                  ""
                  (repeated "[a] " count)))

(defun nested-lazy-list (depth lines)
  "DEPTH list markers on one line, opening DEPTH nested lists, then LINES
lazy continuation lines of the innermost paragraph. Plaintext writes the
innermost item's prefix, 4 x DEPTH spaces, before every one of them
(src/plaintext.c, src/render.c). A list item or a footnote definition
opens only in the first 99 passes of open_new_blocks over one line
(MAX_LIST_DEPTH, src/blocks.c); DEPTH stays well under that here."
  (with-output-to-string (out)
    (write-string (repeated "- " depth) out)
    (write-line "a" out)
    (dotimes (line lines)
      (write-line "b" out))))

(defun nested-code-block (depth lines)
  "DEPTH nested list items, then a fenced code block of LINES lines in the
innermost, indented to its content: every line of the code block starts
with the innermost item's prefix in plaintext."
  (let ((indent (make-string (* 2 depth) :initial-element #\Space)))
    (with-output-to-string (out)
      (write-string (repeated "- " depth) out)
      (write-line "a" out)
      (terpri out)
      (write-line (concatenate 'string indent "```") out)
      (dotimes (line lines)
        (write-line (concatenate 'string indent "x") out))
      (write-line (concatenate 'string indent "```") out))))

;;; Rejection: each source of blowup, under small bindings

(defun entry-point-name (function)
  "The symbol each entry point names itself by in what it signals."
  (cond
    ((eql function #'parse) 'cl-commonmark-gfm:parse)
    ((eql function #'cl-commonmark-gfm:markdown->html) 'cl-commonmark-gfm:markdown->html)
    ((eql function #'cl-commonmark-gfm:markdown->plaintext) 'cl-commonmark-gfm:markdown->plaintext)
    ((eql function #'cl-commonmark-gfm:markdown->html-tree)
     'cl-commonmark-gfm:markdown->html-tree)))

(define-test a-padded-table-past-the-cell-bound-is-rejected-by-every-entry-point
  ;; As A-PADDED-TABLE-PAST-THE-CELL-BOUND-IS-REJECTED-BEFORE-ANY-PARSER, through
  ;; each of the four entry points.
  (native-state)
  (dolist (function (list #'parse
                          #'cl-commonmark-gfm:markdown->html
                          #'cl-commonmark-gfm:markdown->plaintext
                          #'cl-commonmark-gfm:markdown->html-tree))
    (let* ((parsers (created-parsers))
           (condition (let ((*max-nodes* 5000))
                        (raised resource-limit-exceeded (funcall function (padded-table 100 50))
                                "~A" (entry-point-name function)))))
      (when condition
        (is eql (entry-point-name function) (condition-operation condition))
        (is eql '*max-nodes* (condition-limit condition))
        (is eql 5200 (condition-datum condition)))
      (is = parsers (created-parsers) "~A: rejected before any parser"
          (entry-point-name function))))
  (true (open-counts-zero-p)))

(defun output-rejection (function markdown maximum)
  "Call FUNCTION, MARKDOWN->HTML or MARKDOWN->PLAINTEXT, on MARKDOWN with
*MAX-OUTPUT-OCTETS* bound to MAXIMUM. Return a plist: the :TYPE, and the
:OPERATION, :LIMIT, :DATUM and :MAXIMUM, of the RESOURCE-LIMIT-EXCEEDED it
signalled, all NIL when it signalled none; and how many :PARSERS and
:BUFFERS it created."
  (native-state)
  (let* ((parsers (created-parsers))
         (buffers (created-buffers))
         (condition (handler-case
                        (let ((cl-commonmark-gfm:*max-output-octets* maximum))
                          (funcall function markdown)
                          nil)
                      (resource-limit-exceeded (condition) condition))))
    (list :type (and condition (type-of condition))
          :operation (and condition (condition-operation condition))
          :limit (and condition (condition-limit condition))
          :datum (and condition (condition-datum condition))
          :maximum (and condition (condition-maximum condition))
          :parsers (- (created-parsers) parsers)
          :buffers (- (created-buffers) buffers))))

(defmacro rejected-before-rendering (function markdown binding description)
  "Assert that FUNCTION rejects MARKDOWN under *MAX-OUTPUT-OCTETS* bound to
BINDING, an integer: RESOURCE-LIMIT-EXCEEDED for *MAX-OUTPUT-OCTETS*, naming
FUNCTION's entry point, after one parser and before any buffer."
  `(destructuring-bind (&key type operation limit datum maximum parsers buffers)
       (output-rejection ,function ,markdown ,binding)
     (is eql 'resource-limit-exceeded type ,description)
     (is eql (entry-point-name ,function) operation ,description)
     (is eql 'cl-commonmark-gfm:*max-output-octets* limit ,description)
     (is eql ,binding maximum ,description)
     (true (and datum (> datum ,binding)) "~A: the bound, ~A, is past the limit"
           ,description datum)
     (is = 1 parsers "~A: parsed once" ,description)
     (is = 0 buffers "~A: rejected before any buffer" ,description)
     (true (open-counts-zero-p) ,description)))

(define-test footnote-references-past-the-output-limit-are-rejected-before-rendering
  ;; 100 references to [^a]: each about 94 octets of sup and link, and 181
  ;; of repeat backref.
  (rejected-before-rendering #'cl-commonmark-gfm:markdown->html (footnote-references 100)
                             10000 "footnote references"))

(define-test references-in-a-dropped-definition-past-the-output-limit-are-rejected
  ;; 300 references in a definition cmark drops: 299 repeat backrefs on the
  ;; footnote it keeps, about 56,000 octets, from a tree with no reference
  ;; left in it.
  (rejected-before-rendering #'cl-commonmark-gfm:markdown->html
                             (dropped-definition-references 300)
                             10000 "references in a dropped definition"))

(define-test escaped-quotes-past-the-output-limit-are-rejected-before-rendering
  ;; 10,000 quotes: 60,000 octets of `&quot;`.
  (rejected-before-rendering #'cl-commonmark-gfm:markdown->html (escaped-quotes 10000)
                             50000 "escaped quotes"))

(define-test reference-link-expansion-past-the-output-limit-is-rejected-before-rendering
  ;; 100 references to one 1,000-octet destination: each link writes it.
  (rejected-before-rendering #'cl-commonmark-gfm:markdown->html
                             (reference-link-expansion 1000 100)
                             200000 "reference-link expansion"))

(define-test nested-list-prefixes-past-the-output-limit-are-rejected-before-rendering
  ;; 30 nested lists, then 1,000 lazy lines: each written after a 120-space
  ;; prefix, some 121,000 octets of plaintext.
  (rejected-before-rendering #'cl-commonmark-gfm:markdown->plaintext
                             (nested-lazy-list 30 1000)
                             100000 "plaintext prefixes"))

;;; Soundness: below the limits, neither bound is ever below the UTF-8
;;; octets of what cmark renders from the same document

(defun html-bound-and-octets (markdown options)
  "MARKDOWN parsed with OPTIONS, MARKDOWN->HTML's, as (BOUND OCTETS): its
HTML-OUTPUT-BOUND, and the octets cmark_render_html wrote for the same
document, RENDER-HTML's second value. The bound bounds those octets, which
can be fewer than the decoded string's UTF-8: an ill-formed sequence of 1
to 3 octets decodes to U+FFFD, which is 3 octets."
  (call-with-native-document
   markdown options
   (lambda (document checked-options)
     (list (native::html-output-bound document checked-options markdown)
           (nth-value 1 (render-html document checked-options))))
   :entry-point :html))

(defun plaintext-bound-and-octets (markdown options)
  "MARKDOWN parsed with OPTIONS, MARKDOWN->PLAINTEXT's, as (BOUND OCTETS):
its PLAINTEXT-OUTPUT-BOUND, and the octets cmark_render_plaintext wrote for
the same document, RENDER-PLAINTEXT's second value."
  (call-with-native-document
   markdown options
   (lambda (document checked-options)
     (list (native::plaintext-output-bound document checked-options)
           (nth-value 1 (render-plaintext document checked-options))))
   :entry-point :plaintext))

(defparameter *bound-softbreaks* '(:newline :space :br)
  "Every :SOFTBREAK value, as the HTML oracle sweeps them.")

(defun html-bound-option-sets ()
  "Every :SOFTBREAK, with and without :UNSAFE-HTML T, and with and without
:SOURCEPOS T: twelve option sets."
  (loop for softbreak in *bound-softbreaks*
        append (loop for unsafe-html in '(nil t)
                     append (loop for sourcepos in '(nil t)
                                  collect (list :softbreak softbreak
                                                :unsafe-html unsafe-html
                                                :sourcepos sourcepos)))))

(defun plaintext-bound-option-sets ()
  "Every :SOFTBREAK at :WIDTH 0 and 20: six option sets."
  (loop for softbreak in *bound-softbreaks*
        append (loop for width in '(0 20)
                     collect (list :softbreak softbreak :width width))))

(defun median (numbers)
  "The median of NUMBERS, a non-empty list of reals."
  (let* ((sorted (sort (copy-list numbers) #'<))
         (length (length sorted)))
    (if (oddp length)
        (nth (floor length 2) sorted)
        (/ (+ (nth (1- (floor length 2)) sorted) (nth (floor length 2) sorted)) 2))))

(defun bound-soundness (inputs html-option-sets plaintext-option-sets)
  "Check both bounds over INPUTS, a list of (NAME MARKDOWN OPTIONS), where
MARKDOWN is a string or a function that returns one and OPTIONS the
input's own options: the HTML bound under each of HTML-OPTION-SETS added
to them, the plaintext bound under each of PLAINTEXT-OPTION-SETS. Returns
a plist: :COMPARED, the comparisons made; :UNDERCOUNTS, each as (NAME
OPTIONS BOUND OCTETS); and :WORST and :MEDIAN, the ratio of bound to octets
over the comparisons with output, as floats."
  (let ((compared 0)
        (undercounts '())
        (ratios '()))
    (flet ((note (name options bound-and-octets)
             (destructuring-bind (bound octets) bound-and-octets
               (incf compared)
               (when (< bound octets)
                 (push (list name options bound octets) undercounts))
               (when (plusp octets)
                 (push (float (/ bound octets)) ratios)))))
      (loop for (name markdown-or-function options) in inputs
            for markdown = (if (functionp markdown-or-function)
                               (funcall markdown-or-function)
                               markdown-or-function)
            do (dolist (set html-option-sets)
                 (let ((all (append set options)))
                   (note name all (html-bound-and-octets markdown all))))
               (dolist (set plaintext-option-sets)
                 (let ((all (append set options)))
                   (note name all (plaintext-bound-and-octets markdown all))))))
    (list :compared compared
          :undercounts (nreverse undercounts)
          :worst (if ratios (reduce #'max ratios) 0.0)
          :median (if ratios (median ratios) 0.0))))

(defun output-crafted-inputs ()
  "Inputs that probe each output-bound term at its worst, as (NAME MARKDOWN
OPTIONS): every escape at its longest, every footnote repeat, positions,
tagfilter's rewrite, and plaintext's prefixes, wrapping, escapes and
markers. Each is small enough for every option set's limits."
  (list
   (list "escaped quotes" (escaped-quotes 2000) '())
   (list "quotes in a code span" (format nil "`~A`" (escaped-quotes 2000)) '())
   (list "quotes in a code block" (markdown-lines "```" (escaped-quotes 2000) "```") '())
   (list "quotes in an info string" (markdown-lines (format nil "```~A" (escaped-quotes 500))
                                                    "x" "```")
         '())
   (list "an info string past a vertical tab"
         (markdown-lines (format nil "```a~C~A b" (code-char 11) (escaped-quotes 500)) "x" "```")
         '())
   (list "entity quotes" (repeated "&quot;" 300) '())
   (list "smart quotes" (repeated "\"a\" 'b' -- ... " 200) '(:smart t))
   (list "a destination of quotes" (format nil "[a](~A)" (repeated "'" 1000)) '())
   (list "a title of quotes" (format nil "[a](b '~A')" (escaped-quotes 1000)) '())
   (list "an image's source, title and alt text"
         (format nil "![a *b* `c` <i>d</i>](~A '~A')" (repeated "'" 500) (escaped-quotes 500))
         '())
   (list "raw HTML in alt text" (repeated "![<b>\"\"</b>](u) " 100) '())
   (list "nested images" (repeated "![a ![b](c) [d](e)](f) " 100) '())
   (list "footnote references" (footnote-references 200 "''''") '())
   (list "footnote references of one character" (footnote-references 300 "'") '())
   (list "references in a dropped definition" (dropped-definition-references 300) '())
   (list "adjacent footnote references" (adjacent-footnote-references 300) '())
   (list "nine adjacent footnote references" (adjacent-footnote-references 9) '())
   (list "a footnote label cut inside a character"
         (format nil "x [^a~C~%bbbbbb]~%" (code-char #xE9)) '())
   (list "footnotes referencing footnotes"
         (markdown-lines "x [^a] [^b] [^a]" "" "[^a]: see [^b] [^a]" "" "[^b]: see [^a]"
                         "" "[^c]: unreferenced [^b]" "" "[^a]: a duplicate [^a]")
         '())
   (list "a footnote in alt text" (markdown-lines "![[^a]](u)" "" "[^a]: b") '())
   (list "a footnote holding lists and code"
         (markdown-lines "x [^a]" "" "[^a]: - one" "    - two" "" "    ```" "    code" "    ```")
         '())
   (list "reference-link expansion" (reference-link-expansion 500 200) '())
   (list "thematic breaks" (repeated (format nil "***~%") 500) '())
   (list "tagfilter in a block" (markdown-lines "<div>" (repeated "<xmp>" 300) "</div>") '())
   (list "tagfilter inline" (repeated "<xmp> " 300) '())
   (list "raw HTML" (markdown-lines "<div>" "<b>\"x\"</b>" "</div>" "" "a <i>b</i> c") '())
   (list "a nested lazy list" (nested-lazy-list 30 300) '())
   (list "wrapping in a nested list"
         (concatenate 'string (repeated "- " 20) (repeated "a " 500)) '())
   (list "a code block in a nested list" (nested-code-block 10 200) '())
   (list "pipes in a table"
         (markdown-lines "| a |" "|---|" (format nil "| ~A |" (repeated "\\|" 300)))
         '())
   (list "a padded table" (padded-table 20 50) '())
   (list "an aligned table" (markdown-lines "| a | b | c | d |" "|:--|:-:|--:|---|"
                                            "| 1 | 2 |" "| 1 | 2 | 3 | 4 | 5 |")
         '())
   (list "a table in a nested list" (markdown-lines "- - | a | b |" "    |---|---|" "    | 1 | 2 |")
         '())
   (list "task items" (repeated (format nil "- [ ] a~%- [x] b~%") 150) '())
   (list "nested task items" (markdown-lines "- [ ] a" "  - [x] b" "    - [ ] c" "" "      d") '())
   (list "wide ordered markers"
         (concatenate 'string (format nil "999999999. a~%")
                      (repeated (format nil "1. b~%~%   - c~%") 100))
         '())
   (list "strikethrough" (repeated "~~a~~ ~b~ " 300) '())
   (list "a setext heading with softbreaks" (markdown-lines "a" "b b" "c" "===" "" "# d")
         '())
   (list "hard breaks" (repeated (format nil "a  ~%b\\~%") 300) '())
   (list "NUL" (format nil "a~Cb~%~%~C" (code-char 0) (code-char 0)) '())
   (list "loose and tight lists"
         (markdown-lines "- a" "- b" "" "- c" "" "1. d" "2. e" "" "   f" "" "> - g" ">" ">   h")
         '())
   (list "the empty document" "" '())
   (list "quotes under CommonMark" (escaped-quotes 500) '(:profile :commonmark))))

(defun crafted-output-bound-facts ()
  "BOUND-SOUNDNESS over OUTPUT-CRAFTED-INPUTS and CRAFTED-TABLES, under
every HTML and plaintext option set."
  (bound-soundness (append (output-crafted-inputs)
                           (loop for markdown in (crafted-tables)
                                 for index from 0
                                 collect (list (format nil "crafted table ~D" index) markdown '())))
                   (html-bound-option-sets)
                   (plaintext-bound-option-sets)))

(define-test neither-output-bound-undercounts-crafted-inputs
  (destructuring-bind (&key compared undercounts &allow-other-keys) (crafted-output-bound-facts)
    (is = (* 18 (+ 43 16)) compared)
    (is equal '() undercounts)))

(defun stress-inputs ()
  "cmark's stress inputs (test/pathological_tests.py) that fit the default
limits, as (NAME FUNCTION OPTIONS): FUNCTION builds each when called. Two
are cut down to fit: \"backticks\" runs its count to 1,400 instead of
5,000, and \"unclosed <!--\" repeats 250,000 times instead of 300,000."
  (list
   (list "nested strong emph" #'nested-emphasis '())
   (list "many emph closers with no openers" (lambda () (repeated "a_ " 65000)) '())
   (list "many emph openers with no closers" (lambda () (repeated "_a " 65000)) '())
   (list "many link closers with no openers" (lambda () (repeated "a]" 65000)) '())
   (list "many link openers with no closers" (lambda () (repeated "[a" 65000)) '())
   (list "mismatched openers and closers" (lambda () (repeated "*a_ " 50000)) '())
   (list "openers and closers multiple of 3"
         (lambda () (concatenate 'string "a**b" (repeated "c* " 50000))) '())
   (list "link openers and emph closers" (lambda () (repeated "[ a_" 50000)) '())
   (list "pattern [ (]( repeated" (lambda () (repeated "[ (](" 80000)) '())
   (list "pattern ![[]() repeated" (lambda () (repeated "![[]()" 160000)) '())
   (list "hard link/emph case" (lambda () "**x [a*b**c*](d)") '())
   (list "nested brackets"
         (lambda () (concatenate 'string (make-string 50000 :initial-element #\[) "a"
                                 (make-string 50000 :initial-element #\])))
         '())
   (list "nested block quotes" #'nested-block-quotes '())
   (list "deeply nested lists" #'nested-lists '())
   (list "U+0000 in input" (lambda () (format nil "abc~Cde~C" (code-char 0) (code-char 0))) '())
   (list "backticks"
         (lambda ()
           (with-output-to-string (out)
             (loop for count from 1 below 1400
                   do (write-char #\e out)
                      (write-string (make-string count :initial-element #\`) out))))
         '())
   (list "unclosed links A" (lambda () (repeated "[a](<b" 30000)) '())
   (list "unclosed links B" (lambda () (repeated "[a](b" 30000)) '())
   (list "unclosed <!--" (lambda () (concatenate 'string "</" (repeated "<!--" 250000))) '())
   (list "tables" #'pathological-tables '())))

(defun stress-output-bound-facts ()
  "BOUND-SOUNDNESS over STRESS-INPUTS, under four HTML option sets (with and
without :UNSAFE-HTML T and :SOURCEPOS T) and plaintext at :WIDTH 0 and 20."
  (bound-soundness (stress-inputs)
                   (loop for unsafe-html in '(nil t)
                         append (loop for sourcepos in '(nil t)
                                      collect (list :unsafe-html unsafe-html
                                                    :sourcepos sourcepos)))
                   '((:width 0) (:width 20))))

(define-test neither-output-bound-undercounts-cmarks-stress-inputs
  (destructuring-bind (&key compared undercounts &allow-other-keys) (stress-output-bound-facts)
    (is = (* 6 20) compared)
    (is equal '() undercounts))
  (true (open-counts-zero-p)))

(defun corpus-output-bound-facts ()
  "BOUND-SOUNDNESS over every corpus example, with its own options, under
every HTML and plaintext option set."
  (bound-soundness (loop for example in (corpus-examples)
                         collect (list (list (corpus-example-file example)
                                             (corpus-example-number example))
                                       (corpus-example-markdown example)
                                       (corpus-example-options example)))
                   (html-bound-option-sets)
                   (plaintext-bound-option-sets)))

(define-test neither-output-bound-undercounts-the-corpus
  (destructuring-bind (&key compared undercounts &allow-other-keys) (corpus-output-bound-facts)
    (is = (* 18 747) compared)
    (is equal '() undercounts)))

(defun backref-count (markdown)
  "How many footnote backrefs MARKDOWN->HTML writes for MARKDOWN."
  (let ((html (cl-commonmark-gfm:markdown->html markdown))
        (count 0))
    (loop with start = 0
          for found = (search "data-footnote-backref-idx" html :start2 start)
          while found
          do (incf count)
             (setf start (1+ found)))
    count))

(define-test references-in-a-dropped-definition-are-bounded-from-the-input
  ;; The tree keeps none of the 50 references, yet cmark writes a backref
  ;; for each: its first, and 49 repeats. Only the input shows them.
  (is = 0 (length (ast-nodes-of-kind (parse (dropped-definition-references 50))
                                     :footnote-reference)))
  (is = 50 (backref-count (dropped-definition-references 50)))
  (destructuring-bind (bound octets) (html-bound-and-octets (dropped-definition-references 50) '())
    (true (>= bound octets) "bound ~D, rendered ~D" bound octets)))

;;; Deep and ordinary documents fit the default limits

(defun renders-within-the-default-limits-p (function markdown)
  "True when FUNCTION, an entry point, renders MARKDOWN under the default
limits without signalling."
  (handler-case (plusp (length (funcall function markdown)))
    (resource-limit-exceeded () nil)))

(define-test deep-documents-render-within-the-default-limits
  (dolist (input (list #'nested-block-quotes #'nested-emphasis #'nested-lists))
    (true (renders-within-the-default-limits-p #'cl-commonmark-gfm:markdown->html
                                               (funcall input))
          "~A: markdown->html" input)
    (true (renders-within-the-default-limits-p #'cl-commonmark-gfm:markdown->plaintext
                                               (funcall input))
          "~A: markdown->plaintext" input))
  (true (open-counts-zero-p)))

(defun prose (octets)
  "About OCTETS of prose, at most OCTETS: paragraphs of words, punctuation,
emphasis and a link."
  (let* ((paragraph (markdown-lines
                     "The quick brown fox, it is said, jumps over the *lazy* dog; and the"
                     "dog -- unmoved -- watches the fox go by. \"Again?\" it asks, and the"
                     "fox, being [quick](https://example.com/fox), says nothing at all."
                     ""))
         (copies (floor octets (length paragraph))))
    (repeated paragraph copies)))

(defun prose-bounds ()
  "The HTML and plaintext bounds of a megabyte of prose, with the length of
the prose, as (HTML PLAINTEXT OCTETS)."
  (let ((markdown (prose 1048576)))
    (list (first (html-bound-and-octets markdown '()))
          (first (plaintext-bound-and-octets markdown '()))
          (length markdown))))

(define-test a-megabyte-of-prose-bounds-to-a-few-megabytes
  ;; Ordinary documents stay far below the 64 MiB default: the HTML bound
  ;; counts each octet of text as 6, its longest escape; plaintext as 1.
  (destructuring-bind (html plaintext octets) (prose-bounds)
    (true (> octets 1000000))
    (true (< html (* 7 octets)) "HTML bound ~D for ~D octets" html octets)
    (true (< plaintext (* 2 octets)) "plaintext bound ~D for ~D octets" plaintext octets)))
