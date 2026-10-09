;;;; Two of the native properties: the bounds (:BOUNDS), and clean outcomes
;;;; (:CLEAN-OUTCOMES). Registered for the :SYNTAX-SOUP and :CORPUS-SPLICES
;;;; generators, on the HTML oracle's 33 option sets
;;;; (tests/property-harness.lisp's ORACLE-OPTION-SETS). Run on SBCL, CCL and
;;;; ECL, as the rest of the native suite is; in CI, CCL's and ECL's run
;;;; only on a push to main or a dispatch, not on pull requests, since they
;;;; are slow.
;;;;
;;;; The :BOUNDS property reaches past the entry points, straight to
;;;; CALL-WITH-NATIVE-DOCUMENT, RENDER-HTML, RENDER-PLAINTEXT and the two
;;;; output bounds -- none of which apply the entry points' own input guard,
;;;; CL-COMMONMARK-GFM::CHECK-INPUT (src/api.lisp). So every case here runs
;;;; CHECK-INPUT itself, with the options' resolved :FOOTNOTES, before any of
;;;; those calls: an input matching cmark's footnote-entity bug, with
;;;; footnotes on, must never reach cmark -- it reads freed heap memory and
;;;; can crash the process.
;;;;
;;;; Each of the 33 option sets carries keys built for the HTML oracle, not
;;;; for any one entry point: PARSE, say, has no :SOFTBREAK key at all, and
;;;; would signal INVALID-PARSE-OPTION for one.
;;;; ENTRY-POINT-OPTIONS filters each case's options down to the keys the
;;;; entry point in hand accepts, by CHECK-OPTIONS' own tables
;;;; (src/native-core/options.lisp), so a filtering mistake can never be
;;;; mistaken for a library failure.

(in-package #:cl-commonmark-gfm.native-tests)

;;; Each entry point's own options

(defun entry-point-keys (entry-point)
  "The option keys ENTRY-POINT (:PARSE, :HTML, :PLAINTEXT or :HTML-TREE)
accepts, exactly as CHECK-OPTIONS resolves them
(src/native-core/options.lisp): its parse keys, its render keys and its
tree keys."
  (append (native-core::parse-keys entry-point)
          (native-core::render-keys entry-point)
          (native-core::tree-keys entry-point)))

(defun entry-point-options (entry-point options)
  "OPTIONS, one of the HTML oracle's 33 plists, filtered down to the keys
ENTRY-POINT-KEYS says ENTRY-POINT accepts, keeping OPTIONS' order. :PARSE
has no :SOFTBREAK key, say, so a case's :SOFTBREAK is dropped for it, and
CHECK-OPTIONS never signals INVALID-PARSE-OPTION or INVALID-RENDER-OPTION
for a key the oracle's own 33 sets carry for a different entry point."
  (let ((keys (entry-point-keys entry-point)))
    (loop for (key value) on options by #'cddr
          when (member key keys)
            append (list key value))))

;;; The :BOUNDS property

(defun html-bound-failure (input options)
  "NIL when HTML-OUTPUT-BOUND covers what RENDER-HTML writes for INPUT
under OPTIONS, already filtered to :HTML's own keys; a detail string
otherwise."
  (call-with-native-document
   input options
   (lambda (document checked-options)
     (let ((bound (html-output-bound document checked-options input 'html-bound-failure)))
       (multiple-value-bind (string octets) (render-html document checked-options)
         (declare (ignore string))
         (unless (>= bound octets)
           (format nil "html-output-bound ~D is below render-html's ~D octets" bound octets)))))
   :entry-point :html))

(defun plaintext-bound-failure (input options)
  "NIL when PLAINTEXT-OUTPUT-BOUND covers what RENDER-PLAINTEXT writes for
INPUT under OPTIONS, already filtered to :PLAINTEXT's own keys; a detail
string otherwise."
  (call-with-native-document
   input options
   (lambda (document checked-options)
     (let ((bound (plaintext-output-bound document checked-options 'plaintext-bound-failure)))
       (multiple-value-bind (string octets) (render-plaintext document checked-options)
         (declare (ignore string))
         (unless (>= bound octets)
           (format nil "plaintext-output-bound ~D is below render-plaintext's ~D octets"
                   bound octets)))))
   :entry-point :plaintext))

(defun table-cell-bound-failure (input options)
  "NIL when TABLE-CELL-BOUND of INPUT covers the :TABLE-CELL nodes PARSE's
AST holds for INPUT under OPTIONS, already filtered to :PARSE's own keys; a
detail string otherwise. PARSE applies its own input guard, already
confirmed clear by BOUNDS-PROPERTY before this runs, so calling it directly
is safe here."
  (let* ((ast (apply #'parse input options))
         (cells (table-cell-count ast))
         (bound (table-cell-bound input)))
    (unless (>= bound cells)
      (format nil "table-cell-bound ~D is below the ~D :table-cell nodes parse's ast holds"
              bound cells))))

(defun bounds-property (input options)
  "The bounds property, registered under :BOUNDS: HTML-OUTPUT-BOUND
is at least what RENDER-HTML writes, PLAINTEXT-OUTPUT-BOUND is at least what
RENDER-PLAINTEXT writes, and TABLE-CELL-BOUND of INPUT is at least the
:TABLE-CELL nodes PARSE's AST holds -- each for the same document and
options. INPUT the guard rejects is :GUARD.

Runs CL-COMMONMARK-GFM::CHECK-INPUT itself first, since HTML-BOUND-FAILURE
and PLAINTEXT-BOUND-FAILURE call CALL-WITH-NATIVE-DOCUMENT and
RENDER-HTML/RENDER-PLAINTEXT directly, which skip the entry points' own
guard. :FOOTNOTES resolves the same way whichever entry point's filtered
options CHECK-OPTIONS sees, since no filtering drops :PROFILE or
:FOOTNOTES, so checking once, with :HTML's options, covers every call this
makes."
  (let* ((html-options (entry-point-options :html options))
         (plaintext-options (entry-point-options :plaintext options))
         (parse-options (entry-point-options :parse options))
         (checked-html (check-options :html 'bounds-property html-options))
         (guardedp (handler-case
                       (progn (cl-commonmark-gfm::check-input input checked-html 'bounds-property)
                              nil)
                     (unsupported-input () t))))
    (if guardedp
        :guard
        (let ((detail (or (html-bound-failure input html-options)
                           (plaintext-bound-failure input plaintext-options)
                           (table-cell-bound-failure input parse-options))))
          (if detail (values :fail detail) :pass)))))

(register-property :bounds 'bounds-property :generators '(:syntax-soup :corpus-splices))

;;; The :CLEAN-OUTCOMES property

(defvar *clean-outcomes-cases* 0
  "How many :CLEAN-OUTCOMES cases have run in this image: a full
TRIVIAL-GARBAGE:GC runs every 100.")

(defun maybe-gc-every-100-cases ()
  "Run a full TRIVIAL-GARBAGE:GC on every 100th call, counted in
*CLEAN-OUTCOMES-CASES*."
  (when (zerop (mod (incf *clean-outcomes-cases*) 100))
    (trivial-garbage:gc :full t)))

(defun clean-outcomes-checks (input parse-options ast)
  "AST, from a first PARSE of INPUT under PARSE-OPTIONS, checked against
the :CLEAN-OUTCOMES property's remaining rules: the open counters zero, and
a second PARSE NODE= to it. Its third rule, no foreign pointer in the AST,
needs no check: the AST's schema guarantees it (see
THE-AST-SCHEMA-REJECTS-A-FOREIGN-POINTER, below)."
  (cond
    ((not (open-counts-zero-p))
     (values :fail (format nil "the open counters aren't zero after the case: ~S"
                           (native-open-counts))))
    ((not (node= ast (apply #'parse input parse-options)))
     (values :fail "a second parse gave an ast that isn't node= to the first"))
    (t :pass)))

(defun clean-outcomes-case (input options)
  "One case of the :CLEAN-OUTCOMES property: call each entry point with its
own filtered options (ENTRY-POINT-OPTIONS), then CLEAN-OUTCOMES-CHECKS.
Each entry point runs its own input guard, with the same INPUT and the
same resolved :FOOTNOTES (no filtering drops :PROFILE or :FOOTNOTES), so
one signalling UNSUPPORTED-INPUT means they all would: the whole case is
:GUARD."
  (let ((parse-options (entry-point-options :parse options)))
    (handler-case
        (let ((ast (apply #'parse input parse-options)))
          (apply #'markdown->html input (entry-point-options :html options))
          (apply #'markdown->plaintext input (entry-point-options :plaintext options))
          (apply #'markdown->html-tree input (entry-point-options :html-tree options))
          (clean-outcomes-checks input parse-options ast))
      (unsupported-input () :guard))))

(defun clean-outcomes-property (input options)
  "The clean-outcomes property, registered under :CLEAN-OUTCOMES: PARSE,
MARKDOWN->HTML, MARKDOWN->PLAINTEXT and MARKDOWN->HTML-TREE each return, or
signal UNSUPPORTED-INPUT (:GUARD); anything else is :FAIL (RUN-CASE catches
a condition none of this handles). CLEAN-OUTCOMES-CASE's four calls and
second parse run wrapped so MAYBE-GC-EVERY-100-CASES always runs, whatever
the case's outcome."
  (unwind-protect (clean-outcomes-case input options)
    (maybe-gc-every-100-cases)))

(register-property :clean-outcomes 'clean-outcomes-property
                   :generators '(:syntax-soup :corpus-splices))

;;; Self tests: ENTRY-POINT-OPTIONS' filtering against all 33 of the HTML
;;; oracle's option sets; crafted inputs that must pass :BOUNDS and
;;; :CLEAN-OUTCOMES; the footnote-entity guard both share, which no parse
;;; may precede; and each clause seen to fail: a redefined output bound and
;;; table-cell bound for :BOUNDS, a deliberate parser leak and a copy that
;;; differs between two parses for :CLEAN-OUTCOMES, and the schema that
;;; leaves :CLEAN-OUTCOMES no foreign pointer to find.
;;;
;;; Parachute keeps every assertion's closure until the run ends, so every
;;; helper here returns a small summary -- an outcome keyword, a short list,
;;; a detail string -- never a generated input or a live AST.

(define-test entry-point-options-drops-softbreak-for-parse-but-keeps-it-elsewhere
  (is equal '(:profile :gfm) (entry-point-options :parse '(:softbreak :newline :profile :gfm)))
  (is equal '(:profile :gfm) (entry-point-options :plaintext '(:profile :gfm :sourcepos t)))
  (is equal '(:softbreak :newline :profile :gfm)
      (entry-point-options :html '(:softbreak :newline :profile :gfm)))
  (is equal '(:softbreak :newline :profile :gfm)
      (entry-point-options :html-tree '(:softbreak :newline :profile :gfm))))

(define-test an-unfiltered-oracle-option-set-is-not-one-parse-accepts
  ;; Without ENTRY-POINT-OPTIONS' filtering, :SOFTBREAK alone would make
  ;; every :PARSE case of :BOUNDS and :CLEAN-OUTCOMES an
  ;; INVALID-PARSE-OPTION, never a library failure worth reporting as one.
  (fail (check-options :parse 'self-test (first (oracle-option-sets))) 'invalid-parse-option))

(defun entry-point-option-failures ()
  "For each of CHECK-OPTIONS' four entry points and each of the HTML
oracle's 33 option sets: the (ENTRY-POINT INDEX CONDITION-TYPE) of any whose
ENTRY-POINT-OPTIONS filtering CHECK-OPTIONS still rejects."
  (loop for entry-point in '(:parse :html :plaintext :html-tree)
        append (loop for options in (oracle-option-sets)
                     for index from 0
                     for failure = (handler-case
                                       (progn (check-options entry-point 'self-test
                                                             (entry-point-options entry-point
                                                                                  options))
                                              nil)
                                     ((or invalid-parse-option invalid-render-option) (condition)
                                       (type-of condition)))
                     when failure
                       collect (list entry-point index failure))))

(define-test every-entry-point-accepts-its-filtered-options-for-all-33-oracle-sets
  (is equal '() (entry-point-option-failures)))

;;; :BOUNDS: a crafted pass

(defun short-row-table ()
  "A pipe table whose body row has one cell where the header has two: cmark
pads it to two (try_opening_table_row, extensions/table.c)."
  (format nil "| a | b |~%|---|---|~%| 1 |~%"))

(define-test a-pipe-table-with-a-short-row-passes-bounds
  (is eql :pass (run-case :bounds (short-row-table)
                          (list :softbreak :newline :profile :commonmark :extensions '(:table)))))

;;; :BOUNDS: a redefined bound must be caught. Each test here is its own
;;; mutation: it breaks one bound, and the property must fail.

(defun zero-html-output-bound (document checked-options markdown &optional operation)
  "A broken HTML-OUTPUT-BOUND: always 0, whatever it is asked about."
  (declare (ignore document checked-options markdown operation))
  0)

(define-test bounds-fails-when-html-output-bound-is-redefined-to-return-zero
  (let ((options (list :softbreak :newline :profile :commonmark :extensions '(:table))))
    (with-redefined ((html-output-bound #'zero-html-output-bound))
      (multiple-value-bind (outcome detail) (run-case :bounds (short-row-table) options)
        (is eql :fail outcome)
        (true (search "html-output-bound" detail :test #'char=) "names the broken bound: ~A"
              detail)))))

(defun zero-table-cell-bound (string)
  "A broken TABLE-CELL-BOUND: always 0, whatever STRING holds."
  (declare (ignore string))
  0)

(define-test bounds-fails-when-table-cell-bound-is-redefined-to-return-zero
  ;; The short-row table parses into four cells, padding included. The
  ;; output bounds don't read this bound, so the table-cell clause alone
  ;; can fail here.
  (let ((options (list :softbreak :newline :profile :commonmark :extensions '(:table))))
    (with-redefined ((table-cell-bound #'zero-table-cell-bound))
      (multiple-value-bind (outcome detail) (run-case :bounds (short-row-table) options)
        (is eql :fail outcome)
        (true (search "table-cell-bound 0" detail :test #'char=) "names the broken bound: ~A"
              detail))))
  (true (open-counts-zero-p)))

;;; :CLEAN-OUTCOMES: a crafted pass

(defun footnote-reference-markdown ()
  "A minimal footnote reference and its definition."
  (format nil "a note[^1]~%~%[^1]: words~%"))

(define-test a-footnote-reference-passes-clean-outcomes
  (is eql :pass (run-case :clean-outcomes (footnote-reference-markdown) (list :profile :gfm))))

;;; The footnote-entity guard both properties share: never let this input
;;; reach cmark, which reads freed heap memory on it.

(define-test the-footnote-entity-bug-pattern-guards-both-properties
  ;; :GUARD alone would hold even with the guard run after the native
  ;; calls; the monotonic parser count shows that no parse ran
  ;; (tests/native/guard.lisp).
  (native-state)
  (let ((before (created-parsers)))
    (is eql :guard (run-case :bounds "x [&#94;a]" (list :profile :gfm)))
    (is eql :guard (run-case :clean-outcomes "x [&#94;a]" (list :profile :gfm)))
    (is = before (created-parsers) "the guarded input reached no parser"))
  (true (open-counts-zero-p)))

;;; :CLEAN-OUTCOMES: a deliberate leak must be caught. The property
;;; skipping its open-counter check must make this test fail.

(define-test clean-outcomes-fails-when-a-parser-leaks
  ;; NOTE-PARSER-CREATED is what OPEN-PARSER calls on a real parser
  ;; (src/native/counters.lisp; src/native/document.lisp); calling it here
  ;; directly, with no matching free, simulates a leak without any real
  ;; native call. Restored in UNWIND-PROTECT, so the open counters return to
  ;; zero whatever this test does, as every native test must leave them.
  (native::note-parser-created)
  (unwind-protect
       (multiple-value-bind (outcome detail)
           (run-case :clean-outcomes "hello" (list :profile :commonmark))
         (is eql :fail outcome)
         (true (search "open counters" detail :test #'char=) "names the open counters: ~A"
               detail))
    (native::note-parser-freed))
  (true (open-counts-zero-p)))

;;; :CLEAN-OUTCOMES: a copy that differs between two parses must be caught

(defun counting-copied-attributes (original)
  "A COPIED-ATTRIBUTES (src/native/copy.lisp) that calls ORIGINAL, then
appends to each :TEXT node's :LITERAL how many text nodes it has copied so
far: no two copies of one document agree, as a nondeterministic copier's
wouldn't."
  (let ((copied 0))
    (lambda (document node kind checked-options stack operation)
      (let ((attributes (funcall original document node kind checked-options stack operation)))
        (if (eql kind :text)
            (list :literal (format nil "~A~D" (getf attributes :literal) (incf copied)))
            attributes)))))

(define-test clean-outcomes-fails-when-a-second-parse-differs
  (with-redefined ((native::copied-attributes
                    (counting-copied-attributes #'native::copied-attributes)))
    (multiple-value-bind (outcome detail)
        (run-case :clean-outcomes "hello" (list :profile :commonmark))
      (is eql :fail outcome)
      (true (search "second parse" detail :test #'char=) "names the second parse: ~A" detail)))
  (true (open-counts-zero-p)))

;;; :CLEAN-OUTCOMES needs no check for foreign pointers in the AST: every
;;; node is built by MAKE-NODE, whose schema (src/ast/schema.lisp) takes
;;; strings, keywords, integers, booleans and lists of keywords as attribute
;;; values, and integers in positions. A foreign pointer is none of these,
;;; so MAKE-NODE signals INVALID-AST-NODE, which RUN-CASE counts as a
;;; :FAIL.

(defun pointer-attribute-outcomes ()
  "What MAKE-NODE does with a foreign pointer as a :TEXT node's :LITERAL, and
as a :LINK's :DESTINATION: the condition type it signals for each, or
:BUILT."
  (loop for (kind key) in '((:text :literal) (:link :destination))
        collect (handler-case (progn (make-node kind :attributes (list key (cffi:null-pointer)))
                                     :built)
                  (error (condition) (type-of condition)))))

(define-test the-ast-schema-rejects-a-foreign-pointer
  (is equal '(cl-commonmark-gfm.conditions:invalid-ast-node
              cl-commonmark-gfm.conditions:invalid-ast-node)
      (pointer-attribute-outcomes)))

;;; The real property tests: one Parachute test per property and
;;; generator, one assertion over its run's problems, so a run that failed
;;; a case, passed none, or left a native handle open fails.
;;; The description is the harness's SUMMARY-REPORT, with all a replay
;;; needs, made before the assertion runs: the closure keeps only the short
;;; list of problems, no generated input.

(defparameter *property-tests*
  '(bounds-holds-on-syntax-soup bounds-holds-on-corpus-splices
    clean-outcomes-holds-on-syntax-soup clean-outcomes-holds-on-corpus-splices)
  "The native property tests' names, properties only, for `make fuzz` to run
alone (tests/run-native-fuzz.lisp), apart from the self tests above.
tests/native/divergences.lisp adds its own with ADD-PROPERTY-TESTS.")

(defun add-property-tests (names)
  "Add NAMES to *PROPERTY-TESTS*, after those already there, each once
however often this runs: reloading a file that adds its tests changes
nothing."
  (setf *property-tests*
        (append *property-tests*
                (remove-if (lambda (name) (member name *property-tests*)) names))))

(defun native-run-problems (summary)
  "What makes SUMMARY's native run unsound, as short strings: the harness's
SUMMARY-PROBLEMS, and open counters that aren't zero once it has run,
which mean a native handle leaked. NIL when it is sound."
  (append (summary-problems summary)
          (unless (open-counts-zero-p)
            (list (format nil "the open counters aren't zero after the run: ~S"
                          (native-open-counts))))))

(defmacro define-property-test (name property generator cases)
  "Define a Parachute test NAME: one assertion that PROPERTY, run on
GENERATOR from *PROPERTY-SEED* for CASES cases (overridden by
*PROPERTY-CASES-OVERRIDE*), failed no case, passed at least one, and left
the open counters at zero (NATIVE-RUN-PROBLEMS). The assertion's
description is the run's SUMMARY-REPORT, so a failure can be replayed."
  `(define-test ,name
     (let* ((summary (run-property ,property :generator ,generator :seed *property-seed*
                                   :cases (property-cases ,cases)))
            (problems (native-run-problems summary)))
       (is equal '() problems "~A" (summary-report summary)))))

(define-property-test bounds-holds-on-syntax-soup :bounds :syntax-soup 36000)
(define-property-test bounds-holds-on-corpus-splices :bounds :corpus-splices 36000)
(define-property-test clean-outcomes-holds-on-syntax-soup :clean-outcomes :syntax-soup 12000)
(define-property-test clean-outcomes-holds-on-corpus-splices :clean-outcomes :corpus-splices
  12000)
