;;;; The property-testing harness (ADR-0020; M3 design §6.1 to §6.3): our own
;;;; splitmix64 stream, the three generators, the delta-debugging shrinker;
;;;; RUN-PROPERTY, which runs a property over cases from a seed and shrinks
;;;; its first failure; what a property test asserts and reports
;;;; (SUMMARY-PROBLEMS, SUMMARY-REPORT); and the seed and case settings.
;;;; tests/properties.lisp and tests/native/properties.lisp (bounds and
;;;; clean outcomes) and tests/native/divergences.lisp (the oracles) build
;;;; the five properties on it. Pure: no CFFI, so this file loads and runs
;;;; on SBCL, CCL and ECL.
;;;;
;;;; ADR-0020 adopted this generator and shrinker over check-it, the other
;;;; contender it compared against: check-it drew from CL:RANDOM, whose
;;;; states don't replay across Lisps (M3 finding 5), where a splitmix64
;;;; stream, built from integer arithmetic alone, gives the same cases on
;;;; SBCL, CCL and ECL from one seed.

(in-package #:cl-commonmark-gfm.tests)

;;; splitmix64 (Steele, Lea and Flood, "Fast splittable pseudorandom number
;;; generators", 2014; Vigna's reference splitmix64.c). The state advances by
;;; a fixed odd increment; each output mixes the new state.

(defconstant +mask-64+ #xFFFFFFFFFFFFFFFF
  "2^64 - 1: LOGAND with it reduces an integer modulo 2^64.")

(defconstant +splitmix64-increment+ #x9E3779B97F4A7C15
  "The increment the state advances by: 2^64 divided by the golden ratio,
rounded to odd.")

(defconstant +splitmix64-multiplier-1+ #xBF58476D1CE4E5B9
  "The first multiplier of splitmix64's output mix.")

(defconstant +splitmix64-multiplier-2+ #x94D049BB133111EB
  "The second multiplier of splitmix64's output mix.")

(defstruct (splitmix64 (:constructor %make-splitmix64 (state))
                       (:copier nil))
  "A splitmix64 stream: its 64-bit state, which SPLITMIX64-NEXT advances."
  (state 0 :type (unsigned-byte 64)))

(defun make-splitmix64 (seed)
  "A splitmix64 stream from SEED, an integer, taken modulo 2^64: a negative
seed is its two's complement."
  (%make-splitmix64 (logand seed +mask-64+)))

(defun splitmix64-next (stream)
  "Advance STREAM and return its next output, an integer from 0 below 2^64.
Each product is reduced modulo 2^64, as the reference's uint64_t
arithmetic is."
  (let ((z (setf (splitmix64-state stream)
                 (logand (+ (splitmix64-state stream) +splitmix64-increment+) +mask-64+))))
    (setf z (logand (* (logxor z (ash z -30)) +splitmix64-multiplier-1+) +mask-64+))
    (setf z (logand (* (logxor z (ash z -27)) +splitmix64-multiplier-2+) +mask-64+))
    (logxor z (ash z -31))))

;;; Drawing

(defun draw-below (stream n)
  "An integer from 0 below N, drawn from STREAM. N is from 1 to 2^64: past
2^64, no output would ever be kept, and the draw would loop forever. Every
value is equally likely: an output from the last, partial run of N values
below 2^64 is drawn again, so no value gets one more chance than another."
  (check-type n (integer 1 18446744073709551616))
  (let ((limit (- (ash 1 64) (mod (ash 1 64) n))))
    (loop for output = (splitmix64-next stream)
          when (< output limit)
            return (mod output n))))

;;; Weighted choice. The generators draw hundreds of times a case from
;;; alphabets of a hundred items, so they build a table once: its running
;;; totals are searched by halving, not walked.

(defstruct (weighted-table (:constructor %make-weighted-table (items totals total))
                           (:copier nil))
  "The ITEMS to draw from; for each, in TOTALS, the running total of the
weights up to and including its own; and TOTAL, the sum of all of them."
  (items #() :type simple-vector)
  (totals #() :type simple-vector)
  (total 0 :type (integer 1)))

(defun make-weighted-table (choices)
  "A WEIGHTED-TABLE of CHOICES, a list of (WEIGHT . VALUE) with each WEIGHT
a positive integer. WEIGHTED-CHOICE gives the same value from it, for the
same draw, as from CHOICES itself."
  (loop for (weight) in choices
        do (check-type weight (integer 1)))
  (let ((running 0))
    (%make-weighted-table (map 'simple-vector #'cdr choices)
                          (map 'simple-vector (lambda (choice) (incf running (car choice)))
                               choices)
                          running)))

(defun table-choice (table pick)
  "The value of TABLE whose share of the weights holds PICK, an integer from
0 below the table's total: the first value whose running total exceeds
PICK, found by halving."
  (let ((totals (weighted-table-totals table))
        (low 0)
        (high (1- (length (weighted-table-totals table)))))
    (loop while (< low high)
          do (let ((middle (floor (+ low high) 2)))
               (if (< pick (svref totals middle))
                   (setf high middle)
                   (setf low (1+ middle)))))
    (svref (weighted-table-items table) low)))

(defun weighted-choice (stream choices)
  "A value of CHOICES drawn from STREAM, each with a chance in proportion to
its weight. CHOICES is a list of (WEIGHT . VALUE), each WEIGHT a positive
integer, or a WEIGHTED-TABLE made of one. Either way it is one draw below
the total weight, so a list and its table give the same values."
  (etypecase choices
    (weighted-table
     (table-choice choices (draw-below stream (weighted-table-total choices))))
    (list
     (let ((pick (draw-below stream (loop for (weight) in choices sum weight))))
       (loop for (weight . value) in choices
             when (< pick weight)
               return value
             do (decf pick weight))))))

;;; Generators (M3 design §6.2): syntax soup, corpus splices and octets; the
;;; option sets each Markdown case draws from; and the bounds every case
;;; keeps.
;;;
;;; Every draw comes from a splitmix64 stream, and every character from
;;; CODE-CHAR of a code point that is never a surrogate: CCL's CODE-CHAR
;;; gives NIL for one, where SBCL and ECL give a character. So one seed
;;; gives the same cases on all three Lisps.

(defconstant +soup-max-length+ 400
  "The most characters a syntax-soup case holds.")

(defconstant +splice-max-lines+ 20
  "The most corpus lines a corpus-splice case joins.")

(defconstant +octets-max-length+ 64
  "The most octets an octet case holds.")

(defconstant +max-case-octets+ 65536
  "The most UTF-8 octets a Markdown case may hold: a sixteenth of
*MAX-INPUT-OCTETS*' default, so the input limit never decides a case. Soup
stays far below it by construction, and so do 20 corpus lines while no
corpus line passes 3,275 octets, which a self test checks.")

(defparameter *generators* '(:syntax-soup :corpus-splices :octets)
  "Every generator GENERATOR-SOURCE knows how to build cases for.")

;;; Syntax soup: an alphabet weighted toward Markdown's syntax. Each item is
;;; a character or a fragment of several.

(defun ascii-punctuation ()
  "The 32 ASCII punctuation characters, from ! to ~: every printable ASCII
character that isn't a letter or a digit. CommonMark lets each be
backslash-escaped, since each can mean something."
  (loop for code from 33 to 126
        for char = (code-char code)
        unless (alphanumericp char)
          collect char))

(defun characters-between (first last)
  "The characters from FIRST to LAST, by code."
  (loop for code from (char-code first) to (char-code last)
        collect (code-char code)))

(defparameter *soup-alphabet*
  (append
   ;; Punctuation, six to one against a letter: it is what makes syntax.
   (mapcar (lambda (char) (cons 6 char)) (ascii-punctuation))
   (mapcar (lambda (char) (cons 1 char))
           (append (characters-between #\a #\z)
                   (characters-between #\A #\Z)
                   (characters-between #\0 #\9)))
   (list (cons 24 #\Space)
         (cons 4 #\Tab)
         (cons 16 #\Newline)
         (cons 2 #\Return)
         (cons 1 (code-char 0))
         ;; e-acute, the CJK character for "day" and a grinning face: two,
         ;; three and four octets in UTF-8.
         (cons 2 (code-char #xE9))
         (cons 2 (code-char #x65E5))
         (cons 2 (code-char #x1F600)))
   ;; Fragments that open footnotes, tables, entities, raw HTML, fences and
   ;; task items, which single characters would rarely spell.
   (mapcar (lambda (fragment) (cons 3 fragment))
           (list "[^" "]:" "|---|" "&#94;" "&amp;" "<div>" "```" "- [ ] ")))
  "The syntax soup's alphabet: a list of (WEIGHT . ITEM), each ITEM a
character or a string.")

(defparameter *soup-table* (make-weighted-table *soup-alphabet*)
  "*SOUP-ALPHABET* as a weighted table, built once: a case draws up to 400
times.")

(defparameter *soup-characters*
  (let ((characters '()))
    (loop for (nil . item) in *soup-alphabet*
          do (etypecase item
               (character (pushnew item characters :test #'char=))
               (string (loop for char across item
                             do (pushnew char characters :test #'char=)))))
    characters)
  "Every character *SOUP-ALPHABET* holds, alone or in a fragment.")

(defparameter *splice-character-table*
  (make-weighted-table (remove-if-not (lambda (choice)
                                        (and (characterp (cdr choice))
                                             (char/= (cdr choice) #\Newline)))
                                      *soup-alphabet*))
  "The soup's single characters but #\\Newline, as a weighted table: what a
corpus splice's changed character becomes. Never a #\\Newline, so a splice
never holds more lines than it drew.")

(defun soup-items ()
  "A fresh list of the syntax soup's items: characters and fragments."
  (mapcar #'cdr *soup-alphabet*))

(defun soup-character-p (char)
  "True when CHAR is one of the syntax soup's characters, alone or in a
fragment."
  (and (find char *soup-characters* :test #'char=) t))

(defun soup-string (stream)
  "A syntax-soup case's input: a length from 0 to +SOUP-MAX-LENGTH+, drawn
uniformly, then items drawn from the alphabet until it is reached. A
fragment that would run past it is cut there."
  (let* ((length (draw-below stream (1+ +soup-max-length+)))
         (string (make-string length))
         (index 0))
    (loop while (< index length)
          do (let ((item (weighted-choice stream *soup-table*)))
               (etypecase item
                 (character
                  (setf (char string index) item)
                  (incf index))
                 (string
                  (loop for char across item
                        while (< index length)
                        do (setf (char string index) char)
                           (incf index))))))
    string))

;;; Corpus splices: lines of the corpus's 747 examples.

(defvar *corpus-line-pool* nil
  "Every line of every corpus example's Markdown, in the corpus's order, as
a simple vector; NIL until CORPUS-LINE-POOL first reads the corpus.")

(defun text-lines (text)
  "TEXT's lines: the pieces #\\Newline separates, but the empty piece after
a final #\\Newline, which ends a line rather than starting one."
  (let ((lines '())
        (start 0))
    (loop for end = (position #\Newline text :start start :test #'char=)
          while end
          do (push (subseq text start end) lines)
             (setf start (1+ end)))
    (when (< start (length text))
      (push (subseq text start) lines))
    (nreverse lines)))

(defun corpus-line-pool ()
  "Every line of every corpus example's Markdown (tests/corpus.lisp), in
the corpus's order, as a simple vector, read once and kept: repeated lines
stay, so a common line, a blank one above all, is drawn as often as the
corpus uses it."
  (or *corpus-line-pool*
      (setf *corpus-line-pool*
            (coerce (loop for example in (corpus-examples)
                          append (text-lines (corpus-example-markdown example)))
                    'simple-vector))))

(defun join-lines (lines)
  "LINES, a list of strings, joined by #\\Newline into a fresh string made
by MAKE-STRING, so its characters can be changed on every Lisp."
  (let ((string (make-string (+ (reduce #'+ lines :key #'length)
                                (max 0 (1- (length lines))))))
        (index 0))
    (loop for (line . rest) on lines
          do (replace string line :start1 index)
             (incf index (length line))
             (when rest
               (setf (char string index) #\Newline)
               (incf index)))
    string))

(defun corpus-splice (stream)
  "A corpus-splice case's input: 1 to +SPLICE-MAX-LINES+ lines, each drawn
uniformly from the corpus's lines, joined by #\\Newline. One case in four
then changes one character, drawn uniformly, to a soup character other
than #\\Newline."
  (let* ((pool (corpus-line-pool))
         (text (join-lines (loop repeat (1+ (draw-below stream +splice-max-lines+))
                                 collect (svref pool (draw-below stream (length pool)))))))
    (when (and (zerop (draw-below stream 4)) (plusp (length text)))
      (setf (char text (draw-below stream (length text)))
            (weighted-choice stream *splice-character-table*)))
    text))

;;; The option sets: each Markdown case runs under one of the sets M2b's
;;; HTML oracle compares. HTML-ORACLE-MISMATCH-P (tests/native/oracles.lisp)
;;; runs each corpus example under its own options, as the corpus reader
;;; makes them, with each :SOFTBREAK value of the oracle's
;;; *SOFTBREAK-VALUES*. They are written out here so this pure file never
;;; loads the native suite; a self test in tests/properties.lisp reads them
;;; back from the corpus.

(defparameter *corpus-option-sets*
  '((:profile :commonmark :extensions ())
    (:profile :commonmark :extensions (:table))
    (:profile :commonmark :extensions (:strikethrough))
    (:profile :commonmark :extensions (:autolink))
    (:profile :commonmark :extensions (:tagfilter))
    (:profile :commonmark :footnotes t :extensions (:table))
    (:profile :commonmark :footnotes t :extensions ())
    (:profile :commonmark :footnotes t :extensions (:autolink))
    (:profile :commonmark :footnotes t :extensions (:table :strikethrough :autolink))
    (:profile :commonmark :smart t :extensions ())
    (:profile :gfm :extensions (:table :strikethrough :autolink :tagfilter :tasklist)))
  "The 11 distinct options plists of the corpus's examples, in the order the
corpus first uses each.")

(defparameter *softbreak-values* '(:newline :space :br)
  "Every :SOFTBREAK value the HTML oracle sweeps (tests/native/oracles.lisp).")

(defparameter *oracle-option-sets*
  (loop for options in *corpus-option-sets*
        append (loop for softbreak in *softbreak-values*
                     collect (list* :softbreak softbreak options)))
  "The 33 option sets the HTML oracle compares: each corpus options plist,
under each :SOFTBREAK value, built as HTML-ORACLE-MISMATCH-P builds them.")

(defun oracle-option-sets ()
  "The 33 option sets the HTML oracle compares, in order. Shared: don't
change them."
  *oracle-option-sets*)

(defun draw-options (stream)
  "One of the HTML oracle's option sets, drawn uniformly, as a fresh copy, so
a property that changed its options couldn't change the next case's."
  (copy-tree (nth (draw-below stream (length *oracle-option-sets*)) *oracle-option-sets*)))

;;; Octets: half random octets, half valid UTF-8 sequences mixed with
;;; truncated, overlong and other ill-formed ones, for the UTF-8 property.
;;; Table 3-7 of the Unicode Standard lists the well-formed sequences.

(defun scalar-count (length)
  "How many scalar values have a shortest UTF-8 form of LENGTH octets, 1 to
4. Three-octet values exclude the 2,048 surrogates."
  (ecase length
    (1 #x80)
    (2 #x780)
    (3 (- #x10000 #x800 #x800))
    (4 #x100000)))

(defun scalar-value (length offset)
  "The scalar value OFFSET places, modulo SCALAR-COUNT, into those whose
shortest UTF-8 form is LENGTH octets. Three-octet values skip the
surrogates, U+D800 to U+DFFF, so none is ever made: CCL's CODE-CHAR has no
character for one."
  (let ((offset (mod offset (scalar-count length))))
    (ecase length
      (1 offset)
      (2 (+ #x80 offset))
      (3 (let ((code (+ #x800 offset)))
           (if (>= code #xD800) (+ code #x800) code)))
      (4 (+ #x10000 offset)))))

(defun sequence-octets (code length)
  "CODE's bits laid out as a UTF-8 sequence of LENGTH octets, 1 to 4, as a
list. Nothing checks that LENGTH is CODE's shortest form or that CODE is a
scalar value, so this also makes overlong forms, encoded surrogates and
codes past U+10FFFF."
  (ecase length
    (1 (list code))
    (2 (list (logior #xC0 (ash code -6))
             (logior #x80 (logand code #x3F))))
    (3 (list (logior #xE0 (ash code -12))
             (logior #x80 (logand (ash code -6) #x3F))
             (logior #x80 (logand code #x3F))))
    (4 (list (logior #xF0 (ash code -18))
             (logior #x80 (logand (ash code -12) #x3F))
             (logior #x80 (logand (ash code -6) #x3F))
             (logior #x80 (logand code #x3F))))))

(defun draw-scalar-octets (stream length)
  "A scalar value whose shortest form is LENGTH octets, drawn uniformly from
STREAM, as that form's octets."
  (sequence-octets (scalar-value length (draw-below stream (scalar-count length))) length))

(defparameter *octet-pieces*
  (make-weighted-table '((4 . :well-formed)
                         (2 . :truncated)
                         (2 . :overlong)
                         (1 . :surrogate)
                         (1 . :past-maximum)
                         (1 . :continuation)))
  "The kinds of piece a mixed octet case is made of: well-formed sequences,
and ill-formed ones, truncated and overlong above all.")

(defun octet-piece (stream)
  "One piece of a mixed octet case, as a list of octets:
- :WELL-FORMED, a scalar value's shortest form, of 1 to 4 octets;
- :TRUNCATED, the first 1 to N-1 octets of an N-octet one;
- :OVERLONG, a scalar value laid out in more octets than its shortest form;
- :SURROGATE, a surrogate laid out in three octets, ED A0 80 to ED BF BF;
- :PAST-MAXIMUM, a code from U+110000 to U+1FFFFF in four, F4 90 80 80 to
  F7 BF BF BF;
- :CONTINUATION, a lone continuation octet, 80 to BF."
  (ecase (weighted-choice stream *octet-pieces*)
    (:well-formed
     (draw-scalar-octets stream (1+ (draw-below stream 4))))
    (:truncated
     (let ((length (+ 2 (draw-below stream 3))))
       (subseq (draw-scalar-octets stream length) 0 (1+ (draw-below stream (1- length))))))
    (:overlong
     (let* ((shortest (1+ (draw-below stream 3)))
            (length (+ shortest 1 (draw-below stream (- 4 shortest)))))
       (sequence-octets (scalar-value shortest (draw-below stream (scalar-count shortest)))
                        length)))
    (:surrogate
     (sequence-octets (+ #xD800 (draw-below stream #x800)) 3))
    (:past-maximum
     (sequence-octets (+ #x110000 (draw-below stream (- #x200000 #x110000))) 4))
    (:continuation
     (list (+ #x80 (draw-below stream #x40))))))

(defun random-octets (stream length)
  "LENGTH octets, each drawn uniformly from STREAM."
  (let ((octets (make-array length :element-type '(unsigned-byte 8))))
    (dotimes (index length octets)
      (setf (aref octets index) (draw-below stream 256)))))

(defun mixed-octets (stream length)
  "LENGTH octets made of pieces from OCTET-PIECE, the last one cut at
LENGTH."
  (let ((octets (make-array length :element-type '(unsigned-byte 8)))
        (index 0))
    (loop while (< index length)
          do (loop for octet in (octet-piece stream)
                   while (< index length)
                   do (setf (aref octets index) octet)
                      (incf index)))
    octets))

(defun octet-case (stream)
  "An octet case's input: a length from 0 to +OCTETS-MAX-LENGTH+, drawn
uniformly; then, one case in two, that many random octets, and otherwise
that many octets of mixed pieces."
  (let ((length (draw-below stream (1+ +octets-max-length+))))
    (if (zerop (draw-below stream 2))
        (random-octets stream length)
        (mixed-octets stream length))))

;;; A case

(defun generate-case (generator stream)
  "GENERATOR's next case, drawn from STREAM, as two values: the input and
its options. A Markdown case's input comes first, then its options; an
octet case has no options."
  (ecase generator
    (:syntax-soup
     (let ((input (soup-string stream)))
       (values input (draw-options stream))))
    (:corpus-splices
     (let ((input (corpus-splice stream)))
       (values input (draw-options stream))))
    (:octets
     (values (octet-case stream) '()))))

;;; The bounds every case keeps

(defun markdown-bounds-violation (input options)
  "Why INPUT and OPTIONS break the bounds every Markdown case keeps, or NIL:
a string of at most +MAX-CASE-OCTETS+ octets, under one of the HTML
oracle's option sets."
  (cond
    ((not (stringp input))
     "the input is not a string")
    ((> (utf8-length input) +max-case-octets+)
     (format nil "the input is ~D octets, over ~D" (utf8-length input) +max-case-octets+))
    ((not (member options *oracle-option-sets* :test #'equal))
     "the options are not one of the HTML oracle's option sets")))

(defun case-bounds-violation (generator input options)
  "Why INPUT and OPTIONS, a case of GENERATOR, break its bounds, as a short
string, or NIL when they keep them: at most 400 characters of soup, at most
20 lines of splices, at most 64 octets with no options for octets."
  (ecase generator
    (:syntax-soup
     (or (markdown-bounds-violation input options)
         (and (> (length input) +soup-max-length+)
              (format nil "~D characters, over ~D" (length input) +soup-max-length+))))
    (:corpus-splices
     (or (markdown-bounds-violation input options)
         (let ((lines (1+ (count #\Newline input :test #'char=))))
           (and (> lines +splice-max-lines+)
                (format nil "~D lines, over ~D" lines +splice-max-lines+)))))
    (:octets
     (cond
       ((not (typep input '(vector (unsigned-byte 8))))
        "the input is not an octet vector")
       ((> (length input) +octets-max-length+)
        (format nil "~D octets, over ~D" (length input) +octets-max-length+))
       (options
        "an octet case has options")))))

;;; The shrinker (ADR-0020): delta debugging over a failing input. It
;;; removes runs of lines, then runs of characters, halving the run size
;;; each time, and keeps each removal after which the property still fails,
;;; as its caller decides: SHRINK-FAILURE asks for a failure of the
;;; original's kind. An octet vector shrinks the same way, octet by octet.
;;;
;;; It draws nothing, so it is deterministic: the same failure shrinks to
;;; the same input on every Lisp. And it is bounded, so a property that
;;; fails slowly can't hold a run up for long.

(defparameter *shrink-budget* 2000
  "The most calls of STILL-FAILS-P one shrink makes, lines and characters
together.")

(defun remove-run (items start size)
  "A fresh simple vector of ITEMS, a simple vector, without the SIZE items
from START, or as many as there are."
  (concatenate 'simple-vector
               (subseq items 0 start)
               (subseq items (min (length items) (+ start size)))))

(defun shrink-items (items rebuild still-fails-p budget)
  "Remove runs of ITEMS, a simple vector, while the input REBUILD makes of
what is left still fails, as STILL-FAILS-P says; return the smallest ITEMS
found and how much of BUDGET, a number of calls, is left.

Runs start at half the items and halve after each pass over them. A pass
tries each run in turn; a run whose removal still fails is removed, and the
next run is tried in its place. Passes of single items repeat until one
removes nothing, so no single item left can be removed: a failure that
needs only *a* shrinks to exactly *a*. Each call of STILL-FAILS-P spends
one of BUDGET, and the shrink stops when none is left."
  (let ((size (ceiling (length items) 2)))
    (loop while (and (plusp size) (plusp budget))
          do (let ((start 0)
                   (progress nil))
               (loop while (and (< start (length items)) (plusp budget))
                     do (let ((candidate (remove-run items start size)))
                          (decf budget)
                          (if (funcall still-fails-p (funcall rebuild candidate))
                              (setf items candidate
                                    progress t)
                              (incf start size))))
               (unless (and progress (= size 1))
                 (setf size (floor size 2)))))
    (values items budget)))

(defun split-lines (string)
  "STRING's pieces between #\\Newline characters, every one kept, empty ones
included, so JOIN-LINES of them gives STRING back: \"a\" then a #\\Newline
is \"a\" and \"\", and two #\\Newline characters alone are three empty
lines."
  (let ((lines '())
        (start 0))
    (loop for end = (position #\Newline string :start start :test #'char=)
          do (push (subseq string start end) lines)
          while end
          do (setf start (1+ end)))
    (nreverse lines)))

(defun shrink-string (string still-fails-p)
  "The smallest string found that still fails, starting from STRING, a
failing input, as STILL-FAILS-P, a function of a string, says: first by
removing runs of lines, then runs of characters (SHRINK-ITEMS), within
*SHRINK-BUDGET* calls of STILL-FAILS-P in all. A second value counts the
calls made."
  (multiple-value-bind (lines budget)
      (shrink-items (coerce (split-lines string) 'simple-vector)
                    (lambda (lines) (join-lines (coerce lines 'list)))
                    still-fails-p
                    *shrink-budget*)
    (multiple-value-bind (characters budget)
        (shrink-items (coerce (join-lines (coerce lines 'list)) 'simple-vector)
                      (lambda (characters) (coerce characters 'string))
                      still-fails-p
                      budget)
      (values (coerce characters 'string) (- *shrink-budget* budget)))))

(defun octets-of (items)
  "A fresh octet vector of ITEMS, a vector of octets."
  (replace (make-array (length items) :element-type '(unsigned-byte 8)) items))

(defun shrink-octets (octets still-fails-p)
  "The smallest octet vector found that still fails, starting from OCTETS, a
failing input, as STILL-FAILS-P, a function of an octet vector, says: by
removing runs of octets (SHRINK-ITEMS), within *SHRINK-BUDGET* calls. A
second value counts the calls made."
  (multiple-value-bind (items budget)
      (shrink-items (coerce octets 'simple-vector) #'octets-of still-fails-p *shrink-budget*)
    (values (octets-of items) (- *shrink-budget* budget))))

;;; The source and the shrinker a property runs with (ADR-0020's "our own"
;;; contender; check-it, the rejected contender, is gone). Kept as plain
;;; functions, not a generic function with one method, now that only one
;;; way of generating and shrinking cases remains (YAGNI).

(defun generator-source (generator seed)
  "A function of no arguments that yields GENERATOR's next case, drawn from a
splitmix64 stream seeded with SEED: GENERATE-CASE over it, so one seed gives
the same cases on every Lisp (M3 finding 5)."
  (unless (member generator *generators*)
    (error "no generator named ~S, only ~{~S~^, ~}" generator *generators*))
  (let ((stream (make-splitmix64 seed)))
    (lambda () (generate-case generator stream))))

(defun shrink-input (input still-fails-p)
  "The smallest input found, starting from INPUT, a failing case, for which
STILL-FAILS-P, a function of an input, holds: SHRINK-STRING for a string and
SHRINK-OCTETS for an octet vector, whichever generator made it."
  (etypecase input
    (string (values (shrink-string input still-fails-p)))
    ((vector (unsigned-byte 8)) (values (shrink-octets input still-fails-p)))))

;;; Properties: outcomes and the registry. A property file registers each
;;; property as it loads, under a keyword name, so a test or another
;;; property can run it by name without a direct reference to its function.

(defparameter *outcomes* '(:pass :fail :guard :excused-repeat :excused-dropped)
  "What a property returns for a case: :PASS or :FAIL; :GUARD when the input
guard rejected the input; :EXCUSED-REPEAT or :EXCUSED-DROPPED when spec
§6.4 excuses a difference.")

(defparameter *excuses* '(:excused-repeat :excused-dropped)
  "The outcomes spec §6.4 excuses, each counted under its own kind, in this
order.")

(defstruct (property-entry (:constructor make-property-entry (name function generators))
                           (:copier nil))
  "A registered property: its NAME, a keyword; the symbol naming its
FUNCTION; and the GENERATORS it runs on by default."
  (name nil :type keyword)
  (function nil :type symbol)
  (generators '() :type list))

(defvar *properties* '()
  "Every registered property, as PROPERTY-ENTRY structures, in the order
each was first registered. A list, not a hash table, so the runner's order
is the same on every Lisp.")

(defun find-property (name)
  "The PROPERTY-ENTRY registered under NAME, or NIL."
  (find name *properties* :key #'property-entry-name))

(defun register-property (name function &key generators)
  "Register FUNCTION, the symbol naming a property's function, under NAME, a
keyword, to run on GENERATORS by default; return NAME. Registering NAME
again replaces its entry where it stands, so reloading a file changes no
order. The symbol is kept, not its function, so the function that runs is
always the current one, even one a test has replaced."
  (check-type name keyword)
  (check-type function symbol)
  (let ((entry (make-property-entry name function (copy-list generators)))
        (old (find-property name)))
    (setf *properties* (if old
                           (substitute entry old *properties*)
                           (append *properties* (list entry)))))
  name)

(defun property-names ()
  "Every registered property's name, in registration order."
  (mapcar #'property-entry-name *properties*))

(defun property-generators (name)
  "The generators the property registered under NAME runs on by default, or
NIL when no property is."
  (let ((entry (find-property name)))
    (and entry (copy-list (property-entry-generators entry)))))

(defun property-function (property)
  "What to call for PROPERTY: the function symbol registered under it when
it is a keyword, and PROPERTY itself, a function or the symbol of one,
otherwise."
  (if (keywordp property)
      (let ((entry (find-property property)))
        (unless entry
          (error "no property is registered as ~S, only ~{~S~^, ~}" property (property-names)))
        (property-entry-function entry))
      property))

;;; One case

(defparameter *detail-limit* 200
  "The most characters a detail keeps: enough to name a condition and say
what went wrong, never a whole input.")

(defun cut-detail (string)
  "STRING, cut to *DETAIL-LIMIT* characters."
  (if (> (length string) *detail-limit*)
      (subseq string 0 *detail-limit*)
      string))

(defun printed (control &rest arguments)
  "FORMAT NIL of CONTROL and ARGUMENTS with the standard printer settings,
symbols printed with their package: the same text on every Lisp, whatever
the run's printer variables."
  (with-standard-io-syntax
    (let ((*package* (find-package "KEYWORD"))
          (*print-readably* nil)
          (*print-pretty* nil))
      (apply #'format nil control arguments))))

(defun printed-options (options)
  "OPTIONS as a report prints them, with the standard printer settings and
package: keywords print as :NAME and NIL as NIL on every Lisp."
  (with-standard-io-syntax
    (let ((*print-readably* nil)
          (*print-pretty* nil))
      (prin1-to-string options))))

(defun condition-detail (condition)
  "CONDITION's type, with its package, and its message, cut to
*DETAIL-LIMIT* characters. A message whose report itself fails is replaced
by a note saying so."
  (cut-detail (handler-case (printed "~S: ~A" (type-of condition) condition)
                (error ()
                  (printed "~S: (its report signalled an error)" (type-of condition))))))

(defun case-detail (detail)
  "A property's DETAIL as a detail: NIL stays NIL, a string is cut to
*DETAIL-LIMIT* characters, and anything else is printed first."
  (cond
    ((null detail) nil)
    ((stringp detail) (cut-detail detail))
    (t (cut-detail (printed "~A" detail)))))

;;; A failure's kind, RUN-CASE's third value, tells one failure from another
;;; when the shrinker asks whether a candidate still fails: it must fail as
;;; the original did (SHRINK-FAILURE). The kinds are the type of a condition
;;; the case signalled; :NOT-AN-OUTCOME; and :FAIL, for a :FAIL the property
;;; returned itself. So a shrink can't slip from the property's own failure
;;; to an error, or from one condition type to another. Two failures a
;;; property reports itself are one kind, though: a detail is free text, and
;;; no prefix of it names a failure reliably (property 1's "the tree's html
;;; differs" covers every difference). The report shows the original
;;; input's detail beside the shrunk one's, so such a slip shows.

(defun run-case (property input options)
  "PROPERTY's outcome for INPUT and OPTIONS, its detail, and for a :FAIL the
failure's kind, as three values. PROPERTY is a registered property's name,
a function, or a function's symbol.
- An ERROR or a STORAGE-CONDITION that PROPERTY doesn't handle itself is a
  :FAIL whose detail is the condition's type and message, and whose kind is
  its type. A case that runs out of heap or stack fails like any other.
- Any other serious condition goes through: Ctrl-C (SBCL's
  SB-SYS:INTERACTIVE-INTERRUPT) or a timeout must stop the run, not count
  as a failure and let it go on.
- A value that isn't an outcome is a :FAIL of kind :NOT-AN-OUTCOME.
- A :FAIL that PROPERTY returns is of kind :FAIL.
The kind is NIL for every other outcome."
  (handler-case
      (multiple-value-bind (outcome detail)
          (funcall (property-function property) input options)
        (cond
          ((eql outcome :fail)
           (values :fail (case-detail detail) :fail))
          ((member outcome *outcomes*)
           (values outcome (case-detail detail) nil))
          (t
           (values :fail
                   (cut-detail
                    (printed "the property returned ~S, which is not an outcome" outcome))
                   :not-an-outcome))))
    ((or error storage-condition) (condition)
      (values :fail (condition-detail condition) (type-of condition)))))

;;; A run

(defun seconds-since (start)
  "The seconds since START, a GET-INTERNAL-REAL-TIME value, as a single
float, to the millisecond."
  (/ (round (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second)
     1000.0))

(defun default-generator (property)
  "The generator PROPERTY runs on when none is given: the first it was
registered with."
  (or (and (keywordp property) (first (property-generators property)))
      (error "~S has no registered generator: give RUN-PROPERTY a :GENERATOR" property)))

(defun shrink-failure (property case input options detail kind shrink)
  "The :FIRST-FAILURE plist for case number CASE, INPUT and OPTIONS, which
failed with DETAIL, a failure of KIND (RUN-CASE's third value): SHRINK of
INPUT while PROPERTY still fails under OPTIONS, and fails with the same
kind, then the shrunk input runs once more for its own detail. SHRINK is a
function of an input and a STILL-FAILS-P predicate, returning the smallest
input found: SHRINK-INPUT ordinarily, or a self test's own, given as
RUN-PROPERTY's :SHRINK."
  (let* ((start (get-internal-real-time))
         (calls 0)
         (shrunk (funcall shrink input
                          (lambda (candidate)
                            (incf calls)
                            (multiple-value-bind (outcome candidate-detail candidate-kind)
                                (run-case property candidate options)
                              (declare (ignore candidate-detail))
                              (and (eql outcome :fail) (equal candidate-kind kind)))))))
    (multiple-value-bind (outcome shrunk-detail) (run-case property shrunk options)
      (list :case case
            :options options
            :input shrunk
            :detail (if (eql outcome :fail)
                        shrunk-detail
                        (printed "the shrunk input gave ~S when run again" outcome))
            :original-length (length input)
            :original-detail detail
            :shrink-calls calls
            :shrink-seconds (seconds-since start)))))

(defun run-property (property &key generator (seed 1) (cases 100) source (shrink #'shrink-input))
  "Run PROPERTY on CASES cases from SEED, and return a summary plist:
- :PROPERTY, :GENERATOR, :SEED and :CASES, as run;
- :PASSED, :FAILED and :GUARD, counts;
- :EXCUSED, an alist of each excuse that occurred and its count;
- :FIRST-FAILURE, NIL or a plist: the case's number (:CASE) and :OPTIONS,
  the shrunk :INPUT and its :DETAIL, the :ORIGINAL-LENGTH and
  :ORIGINAL-DETAIL, and the shrink's :SHRINK-CALLS and :SHRINK-SECONDS. The
  shrink keeps to the first failure's kind (SHRINK-FAILURE);
- :SECONDS, the whole run's, the shrink included.
PROPERTY is a registered name, which also gives GENERATOR's default, or a
function or its symbol. SOURCE, when given, is a function of no arguments
that yields each case directly, in place of (GENERATOR-SOURCE GENERATOR
SEED). SHRINK, when given, replaces SHRINK-INPUT. Both are explicit
parameters, not something a self test redefines globally: some Lisps
compile a same-file call, such as SHRINK-FAILURE's to SHRINK-INPUT, as a
direct reference that a later (SETF FDEFINITION) doesn't reach (found on
ECL). tests/properties.lisp's self tests use both to drive this with cases
chosen by hand, and to count shrink calls. Only the first failure is
shrunk, once every case has run, so shrinking never changes what the cases
count."
  (let* ((start (get-internal-real-time))
         (function (property-function property))
         (generator (or generator (default-generator property)))
         (source (or source (generator-source generator seed)))
         (passed 0)
         (failed 0)
         (guard 0)
         (excused (mapcar (lambda (kind) (cons kind 0)) *excuses*))
         (first-failure nil))
    (loop for case from 1 to cases
          do (multiple-value-bind (input options) (funcall source)
               (multiple-value-bind (outcome detail kind) (run-case function input options)
                 (ecase outcome
                   (:pass (incf passed))
                   (:guard (incf guard))
                   ((:excused-repeat :excused-dropped) (incf (cdr (assoc outcome excused))))
                   (:fail
                    (incf failed)
                    (unless first-failure
                      (setf first-failure (list case input options detail kind))))))))
    (list :property property
          :generator generator
          :seed seed
          :cases cases
          :passed passed
          :failed failed
          :guard guard
          :excused (remove-if #'zerop excused :key #'cdr)
          :first-failure (and first-failure
                              (destructuring-bind (case input options detail kind) first-failure
                                (shrink-failure function case input options detail kind shrink)))
          :seconds (seconds-since start))))

;;; Reporting a summary: a property test's one assertion is over
;;; SUMMARY-PROBLEMS, and its description is SUMMARY-REPORT, which must
;;; show all a replay needs (ADR-0020's "The suite").

(defun escaped-string (string)
  "STRING in double quotes, with every character outside printable ASCII
escaped, so a printed input shows its NULs and carriage returns: \\n, \\r,
\\t, \\\" and \\\\, and \\u{HEX} for any other."
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for char across string
          for code = (char-code char)
          do (cond
               ((char= char #\") (write-string "\\\"" out))
               ((char= char #\\) (write-string "\\\\" out))
               ((char= char #\Newline) (write-string "\\n" out))
               ((char= char #\Return) (write-string "\\r" out))
               ((char= char #\Tab) (write-string "\\t" out))
               ((<= 32 code 126) (write-char char out))
               (t (format out "\\u{~X}" code))))
    (write-char #\" out)))

(defun described-input (input)
  "INPUT as printed in a report: a string escaped, an octet vector in hex,
or NIL unchanged, for a summary with no first failure."
  (etypecase input
    (null nil)
    (string (escaped-string input))
    (vector (format nil "#(~{#x~2,'0X~^ ~})" (coerce input 'list)))))

(defun excuses-text (excused)
  "EXCUSED, an alist of excuse and count, as text."
  (if excused
      (format nil "~:{~(~A~) ~D~:^, ~}"
              (mapcar (lambda (entry) (list (car entry) (cdr entry))) excused))
      "no excuses"))

(defun size-text (length input)
  "LENGTH in INPUT's unit, characters for a string and octets for an octet
vector: \"1 character\", \"2 octets\"."
  (format nil "~D ~:[octet~;character~]~:[s~;~]" length (stringp input) (= length 1)))

(defun summary-problems (summary)
  "What keeps SUMMARY's run from showing that its property holds, as short
strings, or NIL when nothing does: a case that failed, or no case that
passed, since a run whose every case was guarded or excused tested
nothing."
  (append (and (plusp (getf summary :failed))
               (list (format nil "~D of ~D cases failed"
                             (getf summary :failed) (getf summary :cases))))
          (and (not (plusp (getf summary :passed)))
               (list "no case passed"))))

(defun summary-report (summary)
  "SUMMARY, RUN-PROPERTY's, as a property test reports it. One line says
what ran and what came of it: the property, the generator, the seed, the
case count and each outcome's count. After a failure, four more give all a
replay needs: the first failing case's number and options; the shrunk
input; its detail; and the original input's length and detail, which show
whether the shrink kept to the failure it started from. (RUN-CASE PROPERTY
INPUT OPTIONS) replays the shrunk input alone."
  (destructuring-bind (&key property generator seed cases passed failed guard excused
                         first-failure &allow-other-keys)
      summary
    (with-output-to-string (out)
      (format out "~A on ~A from seed ~D, ~D cases: ~D passed, ~D failed, ~D guarded, ~A"
              (printed "~S" property) (printed "~S" generator) seed cases passed failed guard
              (excuses-text excused))
      (when first-failure
        (destructuring-bind (&key case options input detail original-length original-detail
                               &allow-other-keys)
            first-failure
          (format out "~%first failure: case ~D, options ~A~%shrunk to ~A: ~A~%its detail: ~A~%~
the original input: ~A; its detail: ~A"
                  case (printed-options options) (size-text (length input) input)
                  (described-input input) detail (size-text original-length input)
                  original-detail))))))

;;; Settings: CL_COMMONMARK_GFM_SEED and CL_COMMONMARK_GFM_CASES (ADR-0020;
;;; M3 plan, Task 9). A bad value must fail loudly before any property runs.

(define-condition property-setting-error (error)
  ((setting :reader property-setting-error-setting
            :initarg :setting
            :type string
            :documentation "The environment variable that is wrong.")
   (value :reader property-setting-error-value
          :initarg :value
          :documentation "Its value, as given.")
   (reason :reader property-setting-error-reason
           :initarg :reason
           :type string
           :documentation "What is wrong with it."))
  (:report (lambda (condition stream)
             (format stream "~A=~S ~A"
                     (property-setting-error-setting condition)
                     (property-setting-error-value condition)
                     (property-setting-error-reason condition))))
  (:documentation "Signalled when CL_COMMONMARK_GFM_SEED or
CL_COMMONMARK_GFM_CASES can't be used, before any property runs."))

(defun setting-error (setting value reason)
  "Signal a PROPERTY-SETTING-ERROR for SETTING, given VALUE, saying REASON."
  (error 'property-setting-error :setting setting :value value :reason reason))

(defun integer-or-nil (string)
  "The integer STRING spells, spaces around it allowed, or NIL."
  (handler-case (parse-integer string)
    (parse-error () nil)))

(defun clock-seed ()
  "A seed from the clock, from 0 below 2^32, for CL_COMMONMARK_GFM_SEED=random:
short enough to read off a report and type back in."
  (mod (+ (* (get-universal-time) 1000003) (get-internal-real-time)) (expt 2 32)))

(defun seed-is-random-p (string)
  "True when STRING, CL_COMMONMARK_GFM_SEED's raw value, asks for a seed from
the clock."
  (string-equal (string-trim '(#\Space #\Tab) string) "random"))

(defun parse-seed (string)
  "CL_COMMONMARK_GFM_SEED's value: the integer STRING spells, or a
CLOCK-SEED when it is \"random\"."
  (cond
    ((seed-is-random-p string) (clock-seed))
    ((integer-or-nil string))
    (t (setting-error "CL_COMMONMARK_GFM_SEED" string "is neither an integer nor random"))))

(defun parse-cases (string)
  "CL_COMMONMARK_GFM_CASES' value: the positive integer STRING spells."
  (let ((cases (integer-or-nil string)))
    (if (and cases (plusp cases))
        cases
        (setting-error "CL_COMMONMARK_GFM_CASES" string "is not a positive integer"))))

(defun setting-value-p (value)
  "True when VALUE, an environment variable's raw value, is set: neither
unset (NIL) nor empty."
  (and value (plusp (length value))))

(defun property-settings (seed cases)
  "The settings that SEED and CASES, the raw values of CL_COMMONMARK_GFM_SEED
and CL_COMMONMARK_GFM_CASES, give, as three values:
- the seed, 1 by default;
- where the seed came from: :DEFAULT when SEED is unset or empty, :RANDOM
  when it asks for a CLOCK-SEED, and :GIVEN otherwise;
- the case count every property runs in place of its own, or NIL.
Signals PROPERTY-SETTING-ERROR on a bad value."
  (values (if (setting-value-p seed) (parse-seed seed) 1)
          (cond
            ((not (setting-value-p seed)) :default)
            ((seed-is-random-p seed) :random)
            (t :given))
          (and (setting-value-p cases) (parse-cases cases))))

(defun property-settings-line (seed source cases)
  "The line a suite prints as it starts, so its output says how to replay
it: SEED and SOURCE, PROPERTY-SETTINGS' first two values, then CASES, its
third, NIL when each property runs its own default count."
  (format nil "properties: seed ~D (~A); case counts: ~A"
          seed
          (ecase source
            (:default "the default")
            (:given "CL_COMMONMARK_GFM_SEED")
            (:random "CL_COMMONMARK_GFM_SEED=random"))
          (if cases
              (format nil "~D each (CL_COMMONMARK_GFM_CASES)" cases)
              "the defaults")))

(defvar *property-seed* 1
  "The seed every property test runs from. INITIALIZE-PROPERTY-SETTINGS sets
it from CL_COMMONMARK_GFM_SEED before any property test runs; 1 otherwise,
so a suite loaded and run without it, as the self tests run, is
deterministic.")

(defvar *property-cases-override* nil
  "When not NIL, overrides every property's own CI case count:
CL_COMMONMARK_GFM_CASES.")

(defun property-cases (default)
  "DEFAULT, a property's own CI case count, or *PROPERTY-CASES-OVERRIDE*
when CL_COMMONMARK_GFM_CASES set one."
  (or *property-cases-override* default))

(defun initialize-property-settings (&optional (stream *standard-output*))
  "Read CL_COMMONMARK_GFM_SEED and CL_COMMONMARK_GFM_CASES into
*PROPERTY-SEED* and *PROPERTY-CASES-OVERRIDE*, before any property test runs
(M3 plan, Task 9), and print PROPERTY-SETTINGS-LINE to STREAM: every run
says which seed it used, a picked one included, and whether the case counts
are the defaults, so it can be replayed. Returns the seed. Signals
PROPERTY-SETTING-ERROR on a bad value; callers run this wrapped in a
HANDLER-CASE that exits non-zero, since an uncaught condition doesn't exit
non-zero on every Lisp (progress.md: ECL's top level can exit 0 after one)."
  (multiple-value-bind (seed source cases)
      (property-settings (uiop:getenv "CL_COMMONMARK_GFM_SEED")
                         (uiop:getenv "CL_COMMONMARK_GFM_CASES"))
    (setf *property-seed* seed
          *property-cases-override* cases)
    (format stream "~&~A~%" (property-settings-line seed source cases))
    (finish-output stream)
    seed))
