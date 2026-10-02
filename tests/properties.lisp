;;;; Property 5, UTF-8 (ADR-0020; M3 design §6.3), and the self tests of
;;;; tests/property-harness.lisp: splitmix64's known answers, the
;;;; generators' cross-Lisp checksums and bounds, the shrinker, the harness
;;;; and the CL_COMMONMARK_GFM_SEED/CL_COMMONMARK_GFM_CASES settings. Pure:
;;;; runs on SBCL, CCL and ECL.
;;;;
;;;; Parachute keeps every assertion's closure, and the values it compared,
;;;; until the run ends (progress.md's global constraints). So each helper
;;;; here makes its own cases and returns a small summary: a checksum, a
;;;; count, or a short list of reasons. No assertion holds a generated
;;;; input.

(in-package #:cl-commonmark-gfm.tests)

;;; splitmix64

(defun first-outputs (seed count)
  "The first COUNT outputs of a splitmix64 stream from SEED, as a list."
  (let ((stream (make-splitmix64 seed)))
    (loop repeat count collect (splitmix64-next stream))))

(define-test splitmix64-gives-the-reference-outputs-for-seed-0
  ;; The first three outputs of Vigna's reference splitmix64.c from a zero
  ;; state: the multipliers, shifts and increment are all exercised.
  (is equal '(#xE220A8397B1DCDAF #x6E789E6AA1B965F4 #x06C45D188009454F)
      (first-outputs 0 3)))

(defun draw-below-coverage (seed n draws)
  "Over DRAWS draws of (DRAW-BELOW stream N) from SEED: how many fell outside
0 to N-1, and which values below N never came up."
  (let ((stream (make-splitmix64 seed))
        (seen (make-array n :initial-element nil))
        (outside 0))
    (loop repeat draws
          do (let ((value (draw-below stream n)))
               (if (and (integerp value) (<= 0 value) (< value n))
                   (setf (aref seen value) t)
                   (incf outside))))
    (list :outside outside
          :missing (loop for value from 0 below n
                         unless (aref seen value) collect value))))

(define-test draw-below-covers-every-value-below-n-and-nothing-else
  (destructuring-bind (&key outside missing) (draw-below-coverage 1 7 700)
    (is = 0 outside)
    (is equal '() missing))
  (destructuring-bind (&key outside missing) (draw-below-coverage 2 1 50)
    (is = 0 outside)
    (is equal '() missing)))

(define-test draw-below-refuses-an-n-past-2^64
  ;; Past 2^64, no output of the stream is below the last full run of N
  ;; values, so a draw would loop forever: it must signal instead.
  (fail (draw-below (make-splitmix64 1) (1+ (expt 2 64))) 'type-error)
  ;; At 2^64 itself, every output is kept as it comes.
  (is = (first (first-outputs 1 1)) (draw-below (make-splitmix64 1) (expt 2 64))))

(defun weighted-count (seed choices value draws)
  "How many of DRAWS weighted choices over CHOICES, from SEED, gave VALUE."
  (let ((stream (make-splitmix64 seed)))
    (loop repeat draws count (eql value (weighted-choice stream choices)))))

(define-test weighted-choice-draws-in-proportion-to-the-weights
  ;; Weights 3 and 1 over 4,000 draws: about 3,000 and 1,000.
  (let ((often (weighted-count 1 '((3 . :often) (1 . :seldom)) :often 4000)))
    (true (< 2850 often 3150) "~D of 4,000 draws gave the weight-3 value" often)))

(defun table-and-list-differences (seed choices draws)
  "The draw numbers, of DRAWS from SEED, at which a weighted choice over
CHOICES and one over their WEIGHTED-TABLE gave different values."
  (let ((list-stream (make-splitmix64 seed))
        (table-stream (make-splitmix64 seed))
        (table (make-weighted-table choices)))
    (loop for draw from 1 to draws
          unless (eql (weighted-choice list-stream choices)
                      (weighted-choice table-stream table))
            collect draw)))

(define-test a-weighted-table-draws-what-its-list-draws
  ;; The generators draw from tables built once; a table must give the very
  ;; draws its list gives, or our cases would depend on the representation.
  (is equal '() (table-and-list-differences 3 '((5 . :a) (1 . :b) (3 . :c) (1 . :d)) 200)))

;;; The generators: the same cases on every Lisp

(defconstant +fnv-offset-basis+ #xCBF29CE484222325
  "FNV-1a's 64-bit offset basis, where every checksum starts.")

(defconstant +fnv-prime+ #x100000001B3
  "FNV-1a's 64-bit prime.")

(defun fnv-1a (hash octet)
  "HASH, a 64-bit FNV-1a state, after OCTET."
  (logand (* (logxor hash octet) +fnv-prime+) #xFFFFFFFFFFFFFFFF))

(defun fnv-1a-integer (hash integer)
  "HASH after INTEGER's low 32 bits, as four octets, low first: a delimiter
between cases, so cases that join into the same octets still differ."
  (loop for shift from 0 below 32 by 8
        do (setf hash (fnv-1a hash (ldb (byte 8 shift) integer))))
  hash)

(defun case-octets (input)
  "INPUT as octets: a string's UTF-8 encoding, or an octet vector itself."
  (etypecase input
    (string (let ((octets (make-array (utf8-length input) :element-type '(unsigned-byte 8))))
              (encode-utf8 input octets)
              octets))
    (vector input)))

(defun options-index (options)
  "OPTIONS' position in ORACLE-OPTION-SETS, or 255 for no options at all."
  (or (position options (oracle-option-sets) :test #'equal) 255))

(defun cases-checksum (generator seed count)
  "FNV-1a, 64-bit, over the first COUNT cases GENERATOR-SOURCE gives for
GENERATOR and SEED: each case's octets, then its length and its options'
index. Equal on two Lisps only when every case is."
  (let ((source (generator-source generator seed))
        (hash +fnv-offset-basis+))
    (loop repeat count
          do (multiple-value-bind (input options) (funcall source)
               (let ((octets (case-octets input)))
                 (loop for octet across octets
                       do (setf hash (fnv-1a hash octet)))
                 (setf hash (fnv-1a-integer hash (length octets))
                       hash (fnv-1a-integer hash (options-index options))))))
    hash))

(defun own-checksum (generator seed count)
  "CASES-CHECKSUM, with *RANDOM-STATE* bound to a fresh, randomly seeded
state: a source that drew from CL:RANDOM would give a different checksum on
every run, so the recorded value checks that ours never does."
  (let ((*random-state* (make-random-state t)))
    (cases-checksum generator seed count)))

(define-test the-first-100-cases-of-seed-1-match-their-recorded-checksums
  ;; Recorded from SBCL; CCL and ECL must give the same values.
  (is = #x4A1AAF05AE742D39 (own-checksum :syntax-soup 1 100))
  (is = #xFE1F5D7CA7EA6DFE (own-checksum :corpus-splices 1 100))
  (is = #x653367268D7B4FDC (own-checksum :octets 1 100)))

;;; The generators: bounds

(defun bounds-violations (generator seed count)
  "Each of the first COUNT cases GENERATOR gives for SEED that breaks the
generator's bounds, as (CASE-NUMBER REASON)."
  (let ((source (generator-source generator seed)))
    (loop for case from 1 to count
          for reason = (multiple-value-bind (input options) (funcall source)
                         (case-bounds-violation generator input options))
          when reason collect (list case reason))))

(define-test every-case-stays-within-its-generators-bounds
  (is equal '() (bounds-violations :syntax-soup 1 300))
  (is equal '() (bounds-violations :corpus-splices 1 300))
  (is equal '() (bounds-violations :octets 1 300)))

(defun octets-of-length (length)
  "A fresh octet vector of LENGTH zeros."
  (make-array length :element-type '(unsigned-byte 8) :initial-element 0))

(defun lines-of (count)
  "COUNT lines of \"x\", joined by #\\Newline."
  (format nil "~{~A~^~%~}" (make-list count :initial-element "x")))

(defun crafted-violations ()
  "CASE-BOUNDS-VIOLATION on cases crafted to break each bound, as (NAME
REASON) for each: every REASON must be a string."
  (let ((options (first (oracle-option-sets))))
    (list
     (list :soup-too-long
           (case-bounds-violation :syntax-soup (make-string 401 :initial-element #\a) options))
     (list :soup-bad-options
           (case-bounds-violation :syntax-soup "a" (list :profile :gfm :unknown t)))
     (list :soup-not-a-string
           (case-bounds-violation :syntax-soup (octets-of-length 1) options))
     (list :splice-too-many-lines
           (case-bounds-violation :corpus-splices (lines-of 21) options))
     (list :splice-too-many-octets
           (case-bounds-violation :corpus-splices (make-string 70000 :initial-element #\a) options))
     (list :octets-too-long
           (case-bounds-violation :octets (octets-of-length 65) '()))
     (list :octets-not-octets
           (case-bounds-violation :octets "abc" '()))
     (list :octets-with-options
           (case-bounds-violation :octets (octets-of-length 1) options)))))

(define-test the-bounds-check-names-each-broken-bound
  ;; Without this, a bounds check that always said "fine" would let the
  ;; test above pass on any generator.
  (is equal '() (remove-if (lambda (entry) (stringp (second entry))) (crafted-violations)))
  ;; And the largest cases that keep the bounds pass.
  (let ((options (first (oracle-option-sets))))
    (false (case-bounds-violation :syntax-soup (make-string 400 :initial-element #\a) options))
    (false (case-bounds-violation :corpus-splices (lines-of 20) options))
    (false (case-bounds-violation :octets (octets-of-length 64) '()))))

(defun size-span (generator seed count)
  "The smallest and largest size among the first COUNT cases GENERATOR gives
for SEED: characters for syntax soup, lines for corpus splices, and octets
for octets."
  (let ((source (generator-source generator seed))
        (sizes '()))
    (loop repeat count
          do (let ((input (funcall source)))
               (push (ecase generator
                       (:syntax-soup (length input))
                       (:corpus-splices (1+ (count #\Newline input :test #'char=)))
                       (:octets (length input)))
                     sizes)))
    (list (reduce #'min sizes) (reduce #'max sizes))))

(define-test the-generators-span-their-sizes
  ;; Each size is drawn uniformly, so 300 cases come near both ends: within
  ;; 10 of them for soup's 401 sizes, within 2 for octets' 65, and onto
  ;; them for splices' 20.
  (destructuring-bind (smallest largest) (size-span :syntax-soup 1 300)
    (true (<= smallest 10) "the shortest soup is ~D characters" smallest)
    (true (<= 390 largest) "the longest soup is ~D characters" largest))
  (is equal '(1 20) (size-span :corpus-splices 1 300))
  (destructuring-bind (smallest largest) (size-span :octets 1 300)
    (true (<= smallest 2) "the shortest octet case is ~D octets" smallest)
    (true (<= 62 largest) "the longest octet case is ~D octets" largest)))

(defun longest-corpus-line-octets ()
  "The most UTF-8 octets any corpus line holds."
  (reduce #'max (corpus-line-pool) :key #'utf8-length))

(define-test twenty-corpus-lines-stay-within-the-case-octet-bound
  ;; 20 of the longest line, and 19 #\Newline characters between them.
  (let ((longest (longest-corpus-line-octets)))
    (true (<= (+ (* 20 longest) 19) +max-case-octets+) "the longest corpus line is ~D octets"
          longest)))

(define-test the-option-sets-number-thirty-three
  ;; 11 distinct example options in the corpus, each under three :SOFTBREAK
  ;; values.
  (is = 33 (length (oracle-option-sets))))

(defun corpus-oracle-option-sets ()
  "The option sets M2b's HTML oracle compares, read from the corpus as
HTML-ORACLE-MISMATCH-P builds them (tests/native/oracles.lisp): each
distinct example options plist, in the corpus's order, under each
:SOFTBREAK value of the oracle's *SOFTBREAK-VALUES*."
  (let ((distinct '()))
    (dolist (example (corpus-examples))
      (pushnew (corpus-example-options example) distinct :test #'equal))
    (loop for options in (reverse distinct)
          append (loop for softbreak in '(:newline :space :br)
                       collect (list* :softbreak softbreak options)))))

(define-test the-option-sets-are-those-the-html-oracle-compares
  ;; Written out in property-harness.lisp, so this pure file never loads the
  ;; native suite; this keeps the copy honest.
  (true (equal (corpus-oracle-option-sets) (oracle-option-sets))))

;;; The generators: what they draw

(defun soup-alphabet-report (seed count)
  "Over the first COUNT syntax-soup cases from SEED: the codes of characters
that aren't in the alphabet, and the alphabet's items that never appeared."
  (let ((source (generator-source :syntax-soup seed))
        (outside '())
        (unused (copy-list (soup-items))))
    (loop repeat count
          do (let ((input (funcall source)))
               (loop for char across input
                     unless (soup-character-p char)
                       do (pushnew (char-code char) outside))
               (setf unused (remove-if (lambda (item)
                                         (etypecase item
                                           (character (find item input :test #'char=))
                                           (string (search item input :test #'char=))))
                                       unused))))
    (list :outside (sort outside #'<)
          :unused unused)))

(define-test syntax-soup-draws-only-from-its-alphabet-and-uses-all-of-it
  (destructuring-bind (&key outside unused) (soup-alphabet-report 1 300)
    (is equal '() outside)
    (is equal '() unused)))

(define-test soup-character-p-knows-the-alphabet
  ;; Without this, a SOUP-CHARACTER-P that said yes to everything would let
  ;; the test above pass on any generator.
  (is equal '() (remove-if #'soup-character-p
                           (list #\* #\[ #\a #\Z #\7 #\Space #\Tab #\Newline #\Return
                                 (code-char 0) (code-char #xE9) (code-char #x65E5)
                                 (code-char #x1F600))))
  (is equal '() (remove-if-not #'soup-character-p
                               (list (code-char 1) #\Page (code-char #x7F) (code-char #xE8)
                                     (code-char #x65E6) (code-char #x1F601)))))

(defun splice-report (seed count)
  "Over the first COUNT corpus-splice cases from SEED: how many hold exactly
one line that isn't a corpus line (a changed character), and how many hold
more than one (none should)."
  (let ((pool (make-hash-table :test 'equal))
        (source (generator-source :corpus-splices seed))
        (changed 0)
        (broken 0))
    (loop for line across (corpus-line-pool)
          do (setf (gethash line pool) t))
    (loop repeat count
          do (let* ((input (funcall source))
                    (strangers (loop with start = 0
                                     for end = (position #\Newline input :start start
                                                                        :test #'char=)
                                     count (not (gethash (subseq input start end) pool))
                                     while end
                                     do (setf start (1+ end)))))
               (cond
                 ((= strangers 1) (incf changed))
                 ((> strangers 1) (incf broken)))))
    (list :changed changed :broken broken)))

(define-test one-corpus-splice-in-four-changes-one-character
  ;; 400 cases: about 100 changed.
  (destructuring-bind (&key changed broken) (splice-report 1 400)
    (is = 0 broken)
    (true (< 60 changed 140) "~D of 400 splices changed a character" changed)))

(defun four-octet-sequence-p (octets)
  "True when OCTETS hold a well-formed four-octet UTF-8 sequence (Table 3-7
of the Unicode Standard: F0 90-BF, F1-F3 80-BF or F4 80-8F, then two of
80-BF)."
  (loop for index from 0 below (- (length octets) 3)
        for lead = (aref octets index)
        for second = (aref octets (1+ index))
        thereis (and (or (and (= lead #xF0) (<= #x90 second #xBF))
                         (and (<= #xF1 lead #xF3) (<= #x80 second #xBF))
                         (and (= lead #xF4) (<= #x80 second #x8F)))
                     (<= #x80 (aref octets (+ index 2)) #xBF)
                     (<= #x80 (aref octets (+ index 3)) #xBF))))

(defun overlong-p (octets)
  "True when OCTETS hold the start of an overlong form: C0 or C1 then 80-BF,
E0 then 80-9F, or F0 then 80-8F."
  (loop for index from 0 below (1- (length octets))
        for lead = (aref octets index)
        for second = (aref octets (1+ index))
        thereis (or (and (<= #xC0 lead #xC1) (<= #x80 second #xBF))
                    (and (= lead #xE0) (<= #x80 second #x9F))
                    (and (= lead #xF0) (<= #x80 second #x8F)))))

(defun octet-mix-report (seed count)
  "Over the first COUNT octet cases from SEED: how many hold a well-formed
four-octet sequence, and how many an overlong form."
  (let ((source (generator-source :octets seed)))
    (loop repeat count
          for octets = (funcall source)
          count (four-octet-sequence-p octets) into four-octet
          count (overlong-p octets) into overlong
          finally (return (list :four-octet four-octet :overlong overlong)))))

(define-test half-the-octet-cases-mix-well-formed-and-overlong-sequences
  ;; Random octets alone hold a four-octet sequence in about one case in
  ;; fifty, and an overlong form in about one in eight: the mixed half
  ;; must lift both far above that.
  (destructuring-bind (&key four-octet overlong) (octet-mix-report 1 200)
    (true (< 40 four-octet) "~D of 200 cases hold a four-octet sequence" four-octet)
    (true (< 40 overlong) "~D of 200 cases hold an overlong form" overlong)))

;;; The shrinker

(defun star-a-input ()
  "A 400-character input holding *a* once, at index 210, among near misses
(\"* a*b *_a_ ** a *\") and a #\\Newline every 40 characters."
  (let ((noise "x* a*b *_a_ ** a *")
        (string (make-string 400)))
    (dotimes (index 400)
      (setf (char string index) (if (= 39 (mod index 40))
                                    #\Newline
                                    (char noise (mod index (length noise))))))
    (replace string "*a*" :start1 210)))

(defun star-a-p (string)
  "True when STRING contains *a*."
  (and (search "*a*" string :test #'char=) t))

(define-test the-shrinker-reduces-a-failure-to-exactly-star-a-star
  (is string= "*a*" (shrink-string (star-a-input) #'star-a-p)))

(defun ten-line-input ()
  "Ten lines of text, joined by #\\Newline."
  (format nil "~{line ~R of ten~^~%~}" (loop for line from 1 to 10 collect line)))

(defun three-lines-p (string)
  "True when STRING has three lines or more, lines being what #\\Newline
separates."
  (>= (1+ (count #\Newline string :test #'char=)) 3))

(define-test the-shrinker-keeps-three-empty-lines-for-a-three-line-failure
  (is string= (format nil "~%~%") (shrink-string (ten-line-input) #'three-lines-p)))

(defun calls-on-a-shrink-that-never-fails ()
  "How many times SHRINK-STRING calls a STILL-FAILS-P that never holds, on
3,000 lines of \"ab\": the lines alone would take some 6,000 calls."
  (let ((calls 0))
    (shrink-string (format nil "~{~A~^~%~}" (make-list 3000 :initial-element "ab"))
                   (lambda (candidate)
                     (declare (ignore candidate))
                     (incf calls)
                     nil))
    calls))

(define-test the-shrinker-stops-after-2000-calls
  (is = 2000 (calls-on-a-shrink-that-never-fails)))

(defun overlong-input ()
  "64 octets of ASCII with C0 80, an overlong NUL, at index 40."
  (let ((octets (make-array 64 :element-type '(unsigned-byte 8))))
    (dotimes (index 64)
      (setf (aref octets index) (+ #x41 (mod index 26))))
    (replace octets '(#xC0 #x80) :start1 40)))

(defun holds-c0-80-p (octets)
  "True when OCTETS hold C0 then 80."
  (and (search '(#xC0 #x80) octets :test #'=) t))

(define-test the-shrinker-reduces-an-octet-vector-octet-by-octet
  (is equal '(#xC0 #x80) (coerce (shrink-octets (overlong-input) #'holds-c0-80-p) 'list))
  (of-type (simple-array (unsigned-byte 8) (*)) (shrink-octets (overlong-input) #'holds-c0-80-p)))

;;; The harness, on a source whose Nth case is the string of N's digits, so
;;; a property can fail exactly where a test wants it to.

(defun counter-source ()
  "A fresh source of cases \"1\", \"2\", \"3\" and so on, with no options: how
a self test makes RUN-PROPERTY fail at an exact, known case number."
  (let ((number 0))
    (lambda () (values (format nil "~D" (incf number)) '()))))

(defun counter-run (property cases &key (shrink #'shrink-input))
  "RUN-PROPERTY's summary for PROPERTY over CASES counted cases."
  (run-property property :source (counter-source) :generator :counter :cases cases
                         :shrink shrink))

(defun counter-case-number (input)
  "INPUT, a counter case's number, or NIL when INPUT doesn't parse as one.
Real shrinking tries candidates shorter than any case COUNTER-SOURCE gives,
the empty string included, so a property built on it must say what a
non-number means, not let PARSE-INTEGER signal and have RUN-CASE's handler
turn that into a :FAIL that would corrupt the very failure being shrunk."
  (handler-case (parse-integer input)
    (parse-error () nil)))

(defun fails-every-third-case (input options)
  "A property failing on cases 3, 6, 9 and so on; :PASS on anything that
doesn't parse as a case number."
  (declare (ignore options))
  (let ((number (counter-case-number input)))
    (if (and number (zerop (mod number 3)))
        (values :fail "a multiple of three")
        :pass)))

(define-test a-property-failing-every-third-case-fails-a-third-of-them
  (destructuring-bind (&key passed failed guard excused first-failure &allow-other-keys)
      (counter-run 'fails-every-third-case 300)
    (is = 200 passed)
    (is = 100 failed)
    (is = 0 guard)
    (is equal '() excused)
    (is = 3 (getf first-failure :case))
    (is string= "a multiple of three" (getf first-failure :detail))))

(defun outcome-by-case-number (input options)
  "A property whose outcome cycles through :PASS, :GUARD, :EXCUSED-REPEAT
and :EXCUSED-DROPPED, by its case's number modulo 4."
  (declare (ignore options))
  (nth (mod (parse-integer input) 4) '(:pass :guard :excused-repeat :excused-dropped)))

(define-test each-outcome-is-counted-under-its-own-kind
  (destructuring-bind (&key passed failed guard excused &allow-other-keys)
      (counter-run 'outcome-by-case-number 300)
    (is = 75 passed)
    (is = 0 failed)
    (is = 75 guard)
    (is equal '((:excused-repeat . 75) (:excused-dropped . 75)) excused)))

(define-condition property-self-test-surprise (error)
  ()
  (:report "a surprise the property did not expect")
  (:documentation "Signalled by a self-test property, to be caught as a failure."))

(defun signals-a-surprise (input options)
  "A property that signals PROPERTY-SELF-TEST-SURPRISE on every case."
  (declare (ignore input options))
  (error 'property-self-test-surprise))

(define-test an-unexpected-condition-is-a-failure-naming-its-type
  (destructuring-bind (&key passed failed first-failure &allow-other-keys)
      (counter-run 'signals-a-surprise 10)
    (is = 0 passed)
    (is = 10 failed)
    (true (search "PROPERTY-SELF-TEST-SURPRISE" (getf first-failure :detail) :test #'char=))
    (true (search "a surprise the property did not expect" (getf first-failure :detail)
                  :test #'char=))))

(defun signals-at-length (input options)
  "A property that signals an error whose message runs to 1,000 characters."
  (declare (ignore input options))
  (error "~A" (make-string 1000 :initial-element #\z)))

(define-test a-conditions-detail-is-cut-to-200-characters
  (is = 200 (length (getf (getf (counter-run 'signals-at-length 1) :first-failure) :detail))))

(defun returns-no-outcome (input options)
  "A property that returns :MAYBE, which isn't an outcome."
  (declare (ignore input options))
  :maybe)

(define-test a-property-that-returns-no-outcome-fails
  (destructuring-bind (&key failed first-failure &allow-other-keys)
      (counter-run 'returns-no-outcome 5)
    (is = 5 failed)
    (true (search "MAYBE" (getf first-failure :detail) :test #'char=))))

(define-condition property-self-test-interrupt (serious-condition)
  ()
  (:report "an interrupt, which is no error")
  (:documentation "Signalled by a self-test property as Ctrl-C would be: a
serious condition that is neither an ERROR nor a STORAGE-CONDITION, like
SBCL's SB-SYS:INTERACTIVE-INTERRUPT and its timeouts."))

(defun signals-an-interrupt (input options)
  "A property that signals PROPERTY-SELF-TEST-INTERRUPT on every case."
  (declare (ignore input options))
  (error 'property-self-test-interrupt))

(defun interrupt-escapes-p ()
  "True when PROPERTY-SELF-TEST-INTERRUPT, signalled by a property, escapes
RUN-CASE, rather than RUN-CASE returning a failure for it."
  (handler-case (progn (run-case 'signals-an-interrupt "x" '()) nil)
    (property-self-test-interrupt () t)))

(define-test an-interrupt-escapes-run-case
  ;; Counted as a failure, Ctrl-C would leave the run going, with a failure
  ;; that isn't one.
  (true (interrupt-escapes-p)))

(define-condition property-self-test-exhaustion (storage-condition)
  ()
  (:report "storage exhausted")
  (:documentation "Signalled by a self-test property as running out of heap
or stack would be."))

(defun signals-an-exhaustion (input options)
  "A property that signals PROPERTY-SELF-TEST-EXHAUSTION on every case."
  (declare (ignore input options))
  (error 'property-self-test-exhaustion))

(defun exhaustion-outcome ()
  "RUN-CASE's outcome for SIGNALS-AN-EXHAUSTION, and whether its detail
names the condition's type, as a list; or :ESCAPED when the condition
escapes RUN-CASE, caught here so that a RUN-CASE letting it through fails
this test rather than aborting the run."
  (handler-case (multiple-value-bind (outcome detail) (run-case 'signals-an-exhaustion "x" '())
                  (list outcome
                        (and (search "PROPERTY-SELF-TEST-EXHAUSTION" detail :test #'char=) t)))
    (property-self-test-exhaustion () :escaped)))

(define-test an-exhausted-heap-or-stack-is-a-failure-naming-its-type
  ;; A case that exhausts the heap or the stack is a failure of that case:
  ;; the input is what to replay.
  (is equal '(:fail t) (exhaustion-outcome)))

(defun call-with-redefined (name function thunk)
  "Call THUNK with FUNCTION as NAME's global function, restoring the
original in UNWIND-PROTECT however THUNK exits."
  (let ((original (fdefinition name)))
    (unwind-protect
         (progn
           (setf (fdefinition name) function)
           (funcall thunk))
      (setf (fdefinition name) original))))

(defun shrinks-in-a-run (property cases)
  "How many times a run of PROPERTY over CASES counted cases calls its
shrinker: a counting wrapper stands in for SHRINK-INPUT, calling through to
it, passed as RUN-PROPERTY's :SHRINK -- an explicit parameter, not a
redefinition of SHRINK-INPUT itself, since SHRINK-FAILURE's call to it is in
this same file, which some Lisps compile as a direct reference that a
redefinition doesn't reach (found on ECL)."
  (let ((count 0))
    (counter-run property cases
                 :shrink (lambda (input still-fails-p)
                           (incf count)
                           (shrink-input input still-fails-p)))
    count))

(define-test only-the-first-failure-is-shrunk
  (is = 1 (shrinks-in-a-run 'fails-every-third-case 300))
  (is = 0 (shrinks-in-a-run 'outcome-by-case-number 300)))

(defun summary-keys (summary)
  "SUMMARY's keys, in order."
  (loop for (key) on summary by #'cddr collect key))

(define-test a-summary-holds-the-interfaces-keys-in-order
  (is equal '(:property :generator :seed :cases :passed :failed :guard :excused
              :first-failure :seconds)
      (summary-keys (counter-run 'fails-every-third-case 3))))

(defun fails-on-an-asterisk (input options)
  "A property failing on any input holding an asterisk."
  (declare (ignore options))
  (if (find #\* input :test #'char=) (values :fail "an asterisk") :pass))

(define-test run-property-shrinks-the-first-failure-of-a-run
  (destructuring-bind (&key failed first-failure &allow-other-keys)
      (run-property 'fails-on-an-asterisk :generator :syntax-soup :seed 1 :cases 50)
    (true (plusp failed))
    (is string= "*" (getf first-failure :input))
    (true (< 1 (getf first-failure :original-length)) "the failing case was ~D characters"
          (getf first-failure :original-length))
    (true (member (getf first-failure :options) (oracle-option-sets) :test #'equal))))

(defun given-source (&rest inputs)
  "A source of INPUTS, in turn, each with no options."
  (lambda () (values (pop inputs) '())))

(defun asterisk-and-plus-property (input options)
  "A property with two bugs: an input holding an asterisk and a plus fails,
and one holding an asterisk alone signals an error, which is the other
bug."
  (declare (ignore options))
  (cond
    ((not (find #\* input :test #'char=)) :pass)
    ((find #\+ input :test #'char=) (values :fail "an asterisk and a plus"))
    (t (error "an asterisk alone"))))

(defun asterisk-and-plus-shrink ()
  "ASTERISK-AND-PLUS-PROPERTY's first failure on \"ab*cd+ef\", which holds
an asterisk and a plus: its shrunk input and that input's detail."
  (let ((failure (getf (run-property 'asterisk-and-plus-property
                                     :source (given-source "ab*cd+ef") :generator :given :cases 1)
                       :first-failure)))
    (list (getf failure :input) (getf failure :detail))))

(define-test a-shrink-keeps-to-the-failure-it-started-from
  ;; Removing the plus turns the failure into the other bug's error. A
  ;; shrink that took any failure would end at "*", reporting that error,
  ;; and lose the failure it was shrinking.
  (is equal '("*+" "an asterisk and a plus") (asterisk-and-plus-shrink)))

(defun fails-on-an-asterisk-giving-the-length (input options)
  "A property failing on any input holding an asterisk, with a detail that
gives the input's length, so a shrunk input's detail differs from its
original's."
  (declare (ignore options))
  (if (find #\* input :test #'char=)
      (values :fail (format nil "an asterisk among ~D characters" (length input)))
      :pass))

(defun report-omissions ()
  "The pieces a replay needs that SUMMARY-REPORT leaves out of a failing
run's report, by name: the run of FAILS-ON-AN-ASTERISK-GIVING-THE-LENGTH
over 50 syntax-soup cases from seed 7."
  (let* ((summary (run-property 'fails-on-an-asterisk-giving-the-length
                                :generator :syntax-soup :seed 7 :cases 50))
         (failure (getf summary :first-failure))
         (report (summary-report summary)))
    (loop for (name piece)
            in (list (list :property "FAILS-ON-AN-ASTERISK-GIVING-THE-LENGTH")
                     (list :generator ":SYNTAX-SOUP")
                     (list :seed "seed 7,")
                     (list :case (format nil "case ~D," (getf failure :case)))
                     (list :options (printed-options (getf failure :options)))
                     (list :input (described-input (getf failure :input)))
                     (list :detail "an asterisk among 1 characters")
                     (list :original-length
                           (format nil "~D characters;" (getf failure :original-length)))
                     (list :original-detail (getf failure :original-detail)))
          unless (search piece report :test #'char=)
            collect name)))

(define-test a-failing-runs-report-holds-all-a-replay-needs
  (is equal '() (report-omissions)))

(define-test a-report-gives-sizes-in-the-inputs-unit
  (is equal '("1 character" "2 characters" "1 octet" "0 octets")
      (list (size-text 1 "*") (size-text 2 "*")
            (size-text 1 (octets-of-length 1)) (size-text 0 (octets-of-length 1)))))

(defun always-guarded (input options)
  "A property whose every case the input guard rejects."
  (declare (ignore input options))
  :guard)

(define-test a-run-is-sound-when-no-case-failed-and-a-case-passed
  (is equal '() (summary-problems (counter-run 'outcome-by-case-number 8)))
  ;; A run in which every case was guarded tested nothing.
  (is equal '("no case passed") (summary-problems (counter-run 'always-guarded 8)))
  (is equal '("1 of 3 cases failed") (summary-problems (counter-run 'fails-every-third-case 3))))

;;; The settings: CL_COMMONMARK_GFM_SEED and CL_COMMONMARK_GFM_CASES

(define-test the-settings-read-seeds-and-case-counts
  (is = 42 (parse-seed "42"))
  (is = -3 (parse-seed "-3"))
  (of-type (integer 0) (parse-seed "random"))
  (is = 10000 (parse-cases "10000")))

(defun setting-error-slots (thunk)
  "The setting and value of the PROPERTY-SETTING-ERROR THUNK signals, as a
list, or :NONE when it signals none."
  (handler-case (progn (funcall thunk) :none)
    (property-setting-error (condition)
      (list (property-setting-error-setting condition) (property-setting-error-value condition)))))

(define-test a-wrong-setting-signals-naming-the-setting-and-its-value
  (fail (parse-seed "forty-two") 'property-setting-error)
  (is equal '("CL_COMMONMARK_GFM_SEED" "forty-two")
      (setting-error-slots (lambda () (parse-seed "forty-two"))))
  (is equal '("CL_COMMONMARK_GFM_CASES" "0") (setting-error-slots (lambda () (parse-cases "0"))))
  (is equal '("CL_COMMONMARK_GFM_CASES" "ten")
      (setting-error-slots (lambda () (parse-cases "ten")))))

(defun settings-of (seed cases)
  "PROPERTY-SETTINGS' three values for the raw SEED and CASES, as a list,
with a picked seed shown as :PICKED."
  (multiple-value-bind (seed source cases) (property-settings seed cases)
    (list (if (eql source :random) :picked seed) source cases)))

(define-test the-settings-say-where-the-seed-and-the-counts-come-from
  (is equal '(1 :default nil) (settings-of nil nil))
  (is equal '(1 :default nil) (settings-of "" ""))
  (is equal '(42 :given 500) (settings-of "42" "500"))
  (is equal '(:picked :random nil) (settings-of "random" nil)))

(define-test the-settings-line-names-the-seed-and-the-counts
  (is string= "properties: seed 1 (the default); case counts: the defaults"
      (property-settings-line 1 :default nil))
  (is string= (concatenate 'string "properties: seed 42 (CL_COMMONMARK_GFM_SEED); "
                           "case counts: 500 each (CL_COMMONMARK_GFM_CASES)")
      (property-settings-line 42 :given 500))
  (is string= (concatenate 'string "properties: seed 7 (CL_COMMONMARK_GFM_SEED=random); "
                           "case counts: the defaults")
      (property-settings-line 7 :random nil)))

(defun printed-settings ()
  "What INITIALIZE-PROPERTY-SETTINGS prints, whatever this run's environment,
with the settings it sets rebound so this run's stay as they are: how many
lines, and whether it is the settings line for the seed it set."
  (let ((*property-seed* *property-seed*)
        (*property-cases-override* *property-cases-override*))
    (let ((printed (with-output-to-string (out) (initialize-property-settings out))))
      (list :lines (count #\Newline printed :test #'char=)
            :names-the-seed (and (eql 0 (search (format nil "properties: seed ~D (" *property-seed*)
                                                printed :test #'char=))
                                 t)))))

(define-test every-suite-start-prints-its-seed-and-counts
  ;; Not only a random seed: a report must say what to replay, every time.
  (is equal '(:lines 1 :names-the-seed t) (printed-settings)))

;;; Property 5: UTF-8 (M3 design §6.3; ADR-0020), over the octet generator's
;;; vectors:
;;; - DECODE-UTF8 returns on every vector;
;;; - decoding, encoding the result and decoding again gives the first
;;;   decoding's string;
;;; - a string with no lone surrogate survives ENCODE-UTF8 then
;;;   DECODE-UTF8 unchanged.
;;; The third needs a string, and a property sees only its case, so the
;;; string is read from the vector itself (SCALAR-STRING): shrinking the
;;; vector shrinks the string with it.

(defun scalar-code-point (first second third)
  "The scalar value three octets pick: FIRST's top two bits pick the length
of its shortest UTF-8 form, 1 to 4 octets, and the other 22 bits an offset
into the values of that length (SCALAR-VALUE). Each length gets a quarter
of the triples, so all four of the encoder's branches run alike; a uniform
pick would make nearly every character four octets long. Never a
surrogate."
  (let ((bits (logior (ash first 16) (ash second 8) third)))
    (scalar-value (1+ (ldb (byte 2 22) bits)) (ldb (byte 22 0) bits))))

(defun scalar-string (octets)
  "A string read from OCTETS, three octets a character (SCALAR-CODE-POINT),
a last group of one or two padded with zeros. Every character is a scalar
value, a code from 0 to #x10FFFF that isn't a surrogate. Removing an octet
regroups those after it, so a failure found here may shrink to a few
octets where one would do."
  (let ((string (make-string (ceiling (length octets) 3))))
    (loop for index from 0 below (length octets) by 3
          for character-index from 0
          do (flet ((octet (offset)
                      (let ((at (+ index offset)))
                        (if (< at (length octets)) (aref octets at) 0))))
               (setf (char string character-index)
                     (code-char (scalar-code-point (octet 0) (octet 1) (octet 2))))))
    string))

(defun encoded (string)
  "STRING's UTF-8 octets, by ENCODE-UTF8 into a vector UTF8-LENGTH long, and
the count ENCODE-UTF8 returned."
  (let* ((octets (make-array (utf8-length string) :element-type '(unsigned-byte 8)))
         (written (encode-utf8 string octets)))
    (values octets written)))

(defun round-trip-failure (string what)
  "Why STRING, WHAT it is, doesn't survive ENCODE-UTF8 then DECODE-UTF8
unchanged, or NIL when it does. The reason gives lengths and an index,
never the characters."
  (multiple-value-bind (octets written) (encoded string)
    (if (/= written (length octets))
        (format nil "encode-utf8 wrote ~D octets of ~A, utf8-length counts ~D"
                written what (length octets))
        (let* ((again (decode-utf8 octets))
               (index (mismatch string again :test #'char=)))
          (and index
               (format nil "~A changed through encode-utf8 and decode-utf8 at index ~D ~
of ~D (~D after)"
                       what index (length string) (length again)))))))

(defun utf8-property (input options)
  "Property 5 on INPUT, an octet vector; OPTIONS are ignored. :PASS when
DECODE-UTF8 returns a string, that string survives ENCODE-UTF8 then
DECODE-UTF8 unchanged, and so does INPUT's SCALAR-STRING; otherwise :FAIL,
with a detail saying which and where."
  (declare (ignore options))
  (let ((decoded (decode-utf8 input)))
    (if (stringp decoded)
        (let ((failure (or (round-trip-failure decoded "the decoded string")
                           (round-trip-failure (scalar-string input) "the scalar string"))))
          (if failure
              (values :fail failure)
              :pass))
        (values :fail "decode-utf8 returned no string"))))

(register-property :utf8 'utf8-property :generators '(:octets))

(define-test the-utf8-property-is-registered-for-octets
  (true (member :utf8 (property-names)))
  (is equal '(:octets) (property-generators :utf8)))

(defun crafted-octet-vectors ()
  "Octet vectors at UTF-8's edges: empty, ASCII, each sequence length,
overlong forms, an encoded surrogate, past U+10FFFF, truncated sequences,
lone continuations and octets no sequence starts with."
  (mapcar (lambda (octets)
            (make-array (length octets) :element-type '(unsigned-byte 8)
                                        :initial-contents octets))
          '(() (#x61) (#x7F) (#xC2 #x80) (#xDF #xBF) (#xE0 #xA0 #x80) (#xEF #xBF #xBF)
            (#xF0 #x90 #x80 #x80) (#xF4 #x8F #xBF #xBF) (#xC0 #x80) (#xC1 #xBF)
            (#xE0 #x80 #x80) (#xF0 #x80 #x80 #x80) (#xED #xA0 #x80) (#xED #xBF #xBF)
            (#xF4 #x90 #x80 #x80) (#xF5 #x80 #x80 #x80) (#xE2 #x82) (#xF0 #x9F #x98)
            (#x80) (#xBF #xBF) (#xFE) (#xFF #x61) (#x80 #xCF #xFF) (#x80 #xD0 #x00)
            (#xCF #xFF #xFF) (#xFF #xFF #xFF))))

(defun crafted-utf8-outcomes ()
  "Property 5's outcome on each CRAFTED-OCTET-VECTORS vector that didn't
pass, as (INDEX OUTCOME DETAIL)."
  (loop for octets in (crafted-octet-vectors)
        for index from 0
        for (outcome detail) = (multiple-value-list (run-case 'utf8-property octets '()))
        unless (eql outcome :pass)
          collect (list index outcome detail)))

(define-test the-utf8-property-passes-on-utf8s-edges
  (is equal '() (crafted-utf8-outcomes)))

(defun scalar-codes (octets)
  "The codes of SCALAR-STRING's characters for OCTETS, a list of octets."
  (map 'list #'char-code
       (scalar-string (make-array (length octets) :element-type '(unsigned-byte 8)
                                                  :initial-contents octets))))

(define-test scalar-string-spans-the-scalar-values-around-the-surrogates
  ;; Three octets make one character. The top two bits of the first pick
  ;; the encoded length; the other 22 bits pick a value of that length.
  (is equal '(#x00) (scalar-codes '(#x00 #x00 #x00)))
  (is equal '(#x7F) (scalar-codes '(#x00 #x00 #x7F)))
  (is equal '(#x80) (scalar-codes '(#x40 #x00 #x00)))
  (is equal '(#x7FF) (scalar-codes '(#x40 #x07 #x7F)))
  (is equal '(#x800) (scalar-codes '(#x80 #x00 #x00)))
  (is equal '(#xD7FF) (scalar-codes '(#x80 #xCF #xFF)))
  (is equal '(#xE000) (scalar-codes '(#x80 #xD0 #x00)))
  (is equal '(#xFFFF) (scalar-codes '(#x80 #xEF #xFF)))
  (is equal '(#x10000) (scalar-codes '(#xC0 #x00 #x00)))
  (is equal '(#x10FFFF) (scalar-codes '(#xCF #xFF #xFF)))
  (is equal '(#x10000) (scalar-codes '(#xD0 #x00 #x00)))
  ;; A last group of one or two octets is read as if padded with zeros.
  (is equal '(#x61 #x40) (scalar-codes '(#x00 #x00 #x61 #x00 #x00 #x40)))
  (is equal '(#x61 #x00) (scalar-codes '(#x00 #x00 #x61 #x00))))

(defun scalar-code-violations ()
  "Every first octet with second and third octets at the edges: the codes
SCALAR-CODE-POINT gives that are surrogates or past U+10FFFF, as (A B C
CODE)."
  (loop for a from 0 to 255
        nconc (loop for b in '(#x00 #x07 #x7F #xCF #xD0 #xEF #xFF)
                    nconc (loop for c in '(#x00 #x7F #xFF)
                                for code = (scalar-code-point a b c)
                                when (or (<= #xD800 code #xDFFF) (> code #x10FFFF) (minusp code))
                                  collect (list a b c code)))))

(define-test scalar-string-never-makes-a-surrogate
  ;; CCL's CODE-CHAR returns NIL for a surrogate, so one would break the
  ;; property there; SBCL and ECL would make a character of it.
  (is equal '() (scalar-code-violations)))

(defun question-mark-encoder (string octets)
  "A broken ENCODE-UTF8: it writes ? for every character past ASCII, then
pads with zeros to the length UTF8-LENGTH counts."
  (let ((index 0))
    (loop for char across string
          do (setf (aref octets index) (if (< (char-code char) #x80)
                                           (char-code char)
                                           (char-code #\?)))
             (incf index))
    (fill octets 0 :start index)
    (length octets)))

(defun broken-encoder-run ()
  "Property 5 over 200 cases from seed 1, with ENCODE-UTF8 replaced by
QUESTION-MARK-ENCODER: how many failed, and the shrunk input's length."
  (let ((summary (call-with-redefined 'encode-utf8 #'question-mark-encoder
                                      (lambda ()
                                        (run-property :utf8 :generator :octets :seed 1
                                                            :cases 200)))))
    (list :failed (getf summary :failed)
          :shrunk-length (length (getf (getf summary :first-failure) :input)))))

(define-test the-utf8-property-fails-when-the-encoder-breaks
  ;; One octet past ASCII decodes to a character the broken encoder writes
  ;; as ?, so the shrinker gets down to a single octet.
  (destructuring-bind (&key failed shrunk-length) (broken-encoder-run)
    (true (plusp failed) "~D of 200 cases failed" failed)
    (is = 1 shrunk-length)))

;;; The real property test (M3 plan, Task 9): one Parachute test, one
;;; assertion over its summary's problems (SUMMARY-PROBLEMS), so a run that
;;; failed a case, or passed none, fails. The description is SUMMARY-REPORT,
;;; with all a replay needs, made before the assertion runs: the closure
;;; keeps only the short list of problems, no generated input.

(defparameter *property-tests* '(utf8-property-holds)
  "The property tests' names, properties only, for `make fuzz` to run alone
(tests/run-fuzz.lisp), apart from the self tests above.")

(define-test utf8-property-holds
  (let* ((summary (run-property :utf8 :generator :octets :seed *property-seed*
                                :cases (property-cases 60000)))
         (problems (summary-problems summary)))
    (is equal '() problems "~A" (summary-report summary))))
