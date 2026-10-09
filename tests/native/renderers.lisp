;;;; The three renderers: MARKDOWN->HTML, MARKDOWN->PLAINTEXT and
;;;; MARKDOWN->HTML-TREE, reached as a caller would, through
;;;; CL-COMMONMARK-GFM. Every value worked out below is confirmed against
;;;; the pinned CLI (`cmark-gfm`), the way tests/native/copier.lisp confirms
;;;; the copier's.

(in-package #:cl-commonmark-gfm.native-tests)

;;; Basic shape: each renderer against one small example, *hi*, and
;;; MARKDOWN->HTML-TREE against the pipeline it is built from.

(define-test markdown->html-renders-emphasis
  (is string= (format nil "<p><em>hi</em></p>~%") (markdown->html "*hi*")))

(define-test markdown->plaintext-renders-without-markup
  ;; EMPH, STRONG and LINK add no markup of their own in plaintext
  ;; (vendor/cmark-gfm/src/plaintext.c): only their children show.
  (is string= (format nil "hi~%") (markdown->plaintext "*hi*")))

(define-test markdown->html-tree-equals-ast->html-tree-of-parse
  (is equal (ast->html-tree (parse "*hi*")) (markdown->html-tree "*hi*")))

;;; Every option reaches cmark, each shown with an effect only that value
;;; can produce (confirmed against the pinned CLI, flags noted alongside
;;; each check).

(define-test markdown->html-every-option-does-what-it-says
  ;; :profile / :extensions: strikethrough is on by :GFM's default, off
  ;; under :COMMONMARK, back on once named (cmark-gfm -e strikethrough).
  (is string= (format nil "<p><del>x</del></p>~%") (markdown->html "~~x~~"))
  (is string= (concatenate 'string "<p>~~x~~</p>" (string #\Newline))
      (markdown->html "~~x~~" :profile :commonmark))
  (is string= (format nil "<p><del>x</del></p>~%")
      (markdown->html "~~x~~" :profile :commonmark :extensions '(:strikethrough)))
  ;; :footnotes: on even with no extensions attached (cmark-gfm -e footnotes).
  (true (search "footnote-ref"
               (markdown->html (markdown-lines "x[^a]" "" "[^a]: note")
                               :profile :commonmark :footnotes t)))
  ;; :smart: curls quotes (cmark-gfm --smart).
  (is string= (format nil "<p>~Cq~C it~Cs</p>~%" (code-char #x201C) (code-char #x201D)
                      (code-char #x2019))
      (markdown->html "\"q\" it's" :smart t))
  ;; :sourcepos: adds data-sourcepos, as cmark-gfm --sourcepos does; off
  ;; by default, unlike PARSE, since HTML reads better without it.
  (is string= (format nil "<p data-sourcepos=\"1:1-1:2\">hi</p>~%")
      (markdown->html "hi" :sourcepos t))
  (false (search "data-sourcepos" (markdown->html "hi")) ":sourcepos nil, the default")
  ;; :softbreak :br gives <br /> (cmark-gfm --hardbreaks).
  (is string= (format nil "<p>a<br />~%b</p>~%")
      (markdown->html (markdown-lines "a" "b") :softbreak :br))
  ;; :unsafe-html: nil, the default, omits raw HTML; t keeps it
  ;; (cmark-gfm / cmark-gfm --unsafe).
  (is string= (format nil "<!-- raw HTML omitted -->~%") (markdown->html "<div>x</div>"))
  (is string= (format nil "<div>x</div>~%") (markdown->html "<div>x</div>" :unsafe-html t)))

(define-test markdown->plaintext-every-option-does-what-it-says
  ;; :profile / :extensions / :footnotes: a footnote reaches cmark with no
  ;; extensions attached, renumbered and moved to the end
  ;; (cmark-gfm -e footnotes --to plaintext).
  (is string= (format nil "x[^1]~%~%[^1]: note~%")
      (markdown->plaintext (markdown-lines "x[^a]" "" "[^a]: note") :profile :commonmark
                           :footnotes t))
  ;; :smart: curls quotes, at the text node, so plaintext shows it too.
  (is string= (format nil "~Cq~C it~Cs~%" (code-char #x201C) (code-char #x201D) (code-char #x2019))
      (markdown->plaintext "\"q\" it's" :smart t))
  ;; :softbreak :space always joins with one space, never a newline
  ;; (cmark-gfm --nobreaks --to plaintext).
  (is string= (format nil "a b~%") (markdown->plaintext (markdown-lines "a" "b") :softbreak :space))
  ;; :softbreak :br forces a newline at its own place even when :width would
  ;; otherwise reflow it there; the default doesn't
  ;; (cmark-gfm --width 10 [--hardbreaks] --to plaintext).
  (is string= (format nil "a b~%") (markdown->plaintext (markdown-lines "a" "b") :width 10))
  (is string= (format nil "a~%b~%")
      (markdown->plaintext (markdown-lines "a" "b") :width 10 :softbreak :br))
  ;; :width: wraps plain paragraphs; 0, the default, never does
  ;; (cmark-gfm --width 20 --to plaintext).
  (is string= (format nil "one two three four~%five six seven~%")
      (markdown->plaintext "one two three four five six seven" :width 20))
  (is string= (format nil "one two three four five six seven~%")
      (markdown->plaintext "one two three four five six seven")))

(define-test markdown->html-tree-every-option-does-what-it-says
  ;; :profile / :extensions / :footnotes / :smart: as MARKDOWN->HTML, through
  ;; the tree.
  (is string= (format nil "<p><del>x</del></p>~%")
      (html-tree->string (markdown->html-tree "~~x~~")))
  (is string= (concatenate 'string "<p>~~x~~</p>" (string #\Newline))
      (html-tree->string (markdown->html-tree "~~x~~" :profile :commonmark)))
  (true (search "footnote-ref"
               (html-tree->string
                (markdown->html-tree (markdown-lines "x[^a]" "" "[^a]: note")
                                     :profile :commonmark :footnotes t))))
  (is string= (format nil "<p>~Cq~C it~Cs</p>~%" (code-char #x201C) (code-char #x201D)
                      (code-char #x2019))
      (html-tree->string (markdown->html-tree "\"q\" it's" :smart t)))
  ;; :softbreak, the tree option: :br gives <br />.
  (is string= (format nil "<p>a<br />~%b</p>~%")
      (html-tree->string (markdown->html-tree (markdown-lines "a" "b") :softbreak :br)))
  ;; :raw-html :text: the literal shows in the tree, escaped like any other
  ;; text, not commented out.
  (is string= (format nil "&lt;div&gt;x&lt;/div&gt;~%")
      (html-tree->string (markdown->html-tree (markdown-lines "<div>x</div>") :raw-html :text)))
  (is string= (format nil "<!-- raw HTML omitted -->~%")
      (html-tree->string (markdown->html-tree (markdown-lines "<div>x</div>"))))
  ;; :link-policy :safe, the default, blanks a dangerous URL; :unsafe keeps
  ;; it.
  (is string= (format nil "<p><a href=\"\">x</a></p>~%")
      (html-tree->string (markdown->html-tree "[x](javascript:alert(1))")))
  (is string= (format nil "<p><a href=\"javascript:alert(1)\">x</a></p>~%")
      (html-tree->string (markdown->html-tree "[x](javascript:alert(1))" :link-policy :unsafe)))
  ;; :document-wrapper wraps the whole tree in the named element, with no
  ;; newline of its own.
  (is string= (format nil "<div><p>x</p>~%</div>")
      (html-tree->string (markdown->html-tree "x" :document-wrapper :div))))

;;; Option errors create no parser: every renderer's own check runs before
;;; any native call. For MARKDOWN->HTML-TREE that includes a bad tree
;;; option, checked by CHECK-TREE-OPTIONS ahead of CHECK-INPUT and any
;;; native call. Each form also names the exact condition it must signal:
;;; INVALID-PARSE-OPTION for a bad :PROFILE, :EXTENSIONS, :FOOTNOTES, :SMART
;;; or :SOURCEPOS value that's one of the renderer's own keys;
;;; INVALID-RENDER-OPTION for everything else -- an odd-length list, an
;;; unknown key (:SOURCEPOS is one for MARKDOWN->PLAINTEXT and
;;; MARKDOWN->HTML-TREE, which don't take it), and a bad render or
;;; tree-option value.

(defmacro no-parser-for-each (&rest type-and-forms)
  "Assert that each (TYPE FORM) of TYPE-AND-FORMS signals exactly TYPE, with
RAISED, and that calling it never raises the parser count."
  `(progn
     ,@(mapcar (lambda (type-and-form)
                (destructuring-bind (type form) type-and-form
                  (let ((before (gensym "BEFORE")))
                    `(let ((,before (created-parsers)))
                       (raised ,type ,form "~S" ',form)
                       (is = 0 (- (created-parsers) ,before) "no parser for ~S" ',form)))))
              type-and-forms)))

(define-test markdown->html-option-errors-create-no-parser
  (native-state)
  (no-parser-for-each
   (invalid-render-option (markdown->html "x" :smart))
   (invalid-render-option (markdown->html "x" :bogus t))
   (invalid-parse-option (markdown->html "x" :profile :github))
   (invalid-parse-option (markdown->html "x" :extensions '(:table :table)))
   (invalid-parse-option (markdown->html "x" :footnotes 1))
   (invalid-parse-option (markdown->html "x" :sourcepos :yes))
   (invalid-render-option (markdown->html "x" :softbreak :bogus))
   (invalid-render-option (markdown->html "x" :unsafe-html 1)))
  (true (open-counts-zero-p)))

(define-test markdown->plaintext-option-errors-create-no-parser
  (native-state)
  (no-parser-for-each
   (invalid-render-option (markdown->plaintext "x" :smart))
   (invalid-render-option (markdown->plaintext "x" :bogus t))
   (invalid-parse-option (markdown->plaintext "x" :extensions '(:emoji)))
   (invalid-render-option (markdown->plaintext "x" :sourcepos t))
   (invalid-render-option (markdown->plaintext "x" :softbreak :bogus))
   (invalid-render-option (markdown->plaintext "x" :width -1))
   (invalid-render-option (markdown->plaintext "x" :width 2147483648)))
  (true (open-counts-zero-p)))

(define-test markdown->html-tree-option-errors-create-no-parser
  (native-state)
  (no-parser-for-each
   (invalid-render-option (markdown->html-tree "x" :smart))
   (invalid-render-option (markdown->html-tree "x" :bogus t))
   (invalid-parse-option (markdown->html-tree "x" :profile :github))
   (invalid-render-option (markdown->html-tree "x" :sourcepos t))
   (invalid-render-option (markdown->html-tree "x" :raw-html :bogus))
   (invalid-render-option (markdown->html-tree "x" :softbreak :bogus))
   (invalid-render-option (markdown->html-tree "x" :link-policy :bogus))
   (invalid-render-option (markdown->html-tree "x" :document-wrapper :br)))
  (true (open-counts-zero-p)))

;;; Non-ASCII round-trips through every entry point.

(define-test non-ascii-text-round-trips-through-every-entry-point
  (let ((markdown (format nil "日本 caf~C" (code-char #xE9))))
    (is string= (format nil "<p>日本 caf~C</p>~%" (code-char #xE9)) (markdown->html markdown))
    (is string= (format nil "日本 caf~C~%" (code-char #xE9)) (markdown->plaintext markdown))
    (is string= (format nil "<p>日本 caf~C</p>~%" (code-char #xE9))
        (html-tree->string (markdown->html-tree markdown)))))

;;; A non-string signals a TYPE-ERROR, before any native call. CHECK-TYPE's
;;; own condition isn't always exactly TYPE-ERROR (SBCL signals
;;; SIMPLE-TYPE-ERROR, a subtype), so this is a FAIL-style supertype check,
;;; unlike NO-PARSER-FOR-EACH's exact one above.

(defmacro no-parser-and-fails-with (type form)
  "Assert, with Parachute's FAIL, that FORM signals a condition of (at least)
TYPE, and that calling it never raises the parser count."
  (let ((before (gensym "BEFORE")))
    `(let ((,before (created-parsers)))
       (fail ,form ,type "~S" ',form)
       (is = 0 (- (created-parsers) ,before) "no parser for ~S" ',form))))

(define-test each-renderer-rejects-a-non-string-before-any-parser
  (native-state)
  (dolist (markdown (list 42 nil #\a :markdown (list "x")))
    (no-parser-and-fails-with 'type-error (markdown->html markdown))
    (no-parser-and-fails-with 'type-error (markdown->plaintext markdown))
    (no-parser-and-fails-with 'type-error (markdown->html-tree markdown)))
  (true (open-counts-zero-p)))

;;; Threads, through the entry points: concurrent PARSE, MARKDOWN->HTML and
;;; MARKDOWN->HTML-TREE calls equal sequential ones.

(defparameter *entry-point-race-markdown*
  (markdown-lines "# Heading" "" "A paragraph with a [link](/x) and a note[^a]." ""
                  "- one" "- two" "" "[^a]: a note")
  "A small document exercising headings, links, lists and footnotes, shared
by the entry-point thread test.")

(define-test concurrent-entry-point-calls-equal-sequential-ones
  ;; The three kinds of call are grouped by position, never mixed in one
  ;; comparison: CALL-TOGETHER returns outcomes in FUNCTIONS' own order, so
  ;; each group of 4 stays its own kind, and NODE=, STRING= and EQUAL each
  ;; meet only the values their own entry point returns.
  (let ((expected-ast (parse *entry-point-race-markdown*))
        (expected-html (markdown->html *entry-point-race-markdown*))
        (expected-tree (markdown->html-tree *entry-point-race-markdown*))
        (outcomes
          (call-together
           (append (loop repeat 4 collect (lambda () (parse *entry-point-race-markdown*)))
                   (loop repeat 4 collect (lambda () (markdown->html *entry-point-race-markdown*)))
                   (loop repeat 4
                         collect (lambda () (markdown->html-tree *entry-point-race-markdown*)))))))
    (false (signalled-conditions outcomes) "no thread signalled")
    (let ((parse-values (returned-values (subseq outcomes 0 4)))
          (html-values (returned-values (subseq outcomes 4 8)))
          (tree-values (returned-values (subseq outcomes 8 12))))
      (is = 4 (length parse-values) "every PARSE thread returned")
      (is = 4 (length html-values) "every MARKDOWN->HTML thread returned")
      (is = 4 (length tree-values) "every MARKDOWN->HTML-TREE thread returned")
      (true (every (lambda (value) (node= expected-ast value)) parse-values) "PARSE calls")
      (true (every (lambda (value) (string= expected-html value)) html-values)
            "MARKDOWN->HTML calls")
      (true (every (lambda (value) (equal expected-tree value)) tree-values)
            "MARKDOWN->HTML-TREE calls")))
  (true (open-counts-zero-p)))

;;; Ill-formed UTF-8 from cmark. A footnote reference that spans a line
;;; break dangles, and cmark writes it back as text cut inside a multi-byte
;;; character: handle_close_bracket (src/inlines.c) copies its label by
;;; columns, which restart at the line break, and process_footnotes
;;; (src/blocks.c) turns the dangling reference into the text [^, those
;;; bytes and ]. The pinned CLI, with the GFM flags, writes <p>x [^a then
;;; 1, 1, 2 or 3 bytes of the cut character then ]</p> for these four, and
;;; x [^a and a newline in plaintext, whose renderer stops a text node at an
;;; ill-formed byte (S_out, src/render.c). Each cut start is one maximal
;;; subpart, so one U+FFFD.

(defun split-label-inputs ()
  "The four inputs, as (NAME MARKDOWN): é cut after its first byte, and
U+1F600 cut after its first, second and third."
  (flet ((split (character tail)
           (format nil "x [^a~C~%~A~%" (code-char character) tail)))
    (list (list "e-acute" (split #xE9 "bbbbbb]"))
          (list "emoji, 1 byte" (split #x1F600 "bbbbbb]"))
          (list "emoji, 2 bytes" (split #x1F600 "bbbbbbb]"))
          (list "emoji, 3 bytes" (split #x1F600 "bbbbbbbb]")))))

(defun split-label-text ()
  "What each split-label input's paragraph holds, decoded."
  (format nil "x [^a~C]" (code-char #xFFFD)))

(defun ast-text (ast)
  "Every :TEXT literal of AST, concatenated in walk order."
  (with-output-to-string (out)
    (walk-ast (lambda (event node)
                (when (and (eql event :enter) (eql (node-kind node) :text))
                  (write-string (node-attribute node :literal) out)))
              ast)))

(define-test ill-formed-utf-8-from-cmark-decodes-through-every-entry-point
  (native-state)
  (dolist (input (split-label-inputs))
    (destructuring-bind (name markdown) input
      (is string= (split-label-text) (ast-text (parse markdown)) "~A: parse" name)
      (is string= (format nil "<p>~A</p>~%" (split-label-text)) (markdown->html markdown)
          "~A: markdown->html" name)
      (is string= (format nil "x [^a~%") (markdown->plaintext markdown)
          "~A: markdown->plaintext" name)
      (is string= (markdown->html markdown) (html-tree->string (markdown->html-tree markdown))
          "~A: the tree path's HTML is markdown->html's" name)))
  (true (open-counts-zero-p)))

(define-test the-renderers-return-one-value
  ;; RENDER-HTML and RENDER-PLAINTEXT also return cmark's octet count; the
  ;; entry points return the string alone.
  (is = 1 (length (multiple-value-list (markdown->html "x"))))
  (is = 1 (length (multiple-value-list (markdown->plaintext "x")))))
