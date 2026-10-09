;;;; The pinned corpus, read the way vendor/cmark-gfm/test/spec_tests.py's
;;;; GET_TESTS reads it. Pure: no native call, no option checking. Every
;;;; corpus-driven test in the native suite builds its examples through this
;;;; reader.

(in-package #:cl-commonmark-gfm.tests)

;;; Mirroring Python's line splitting and str.strip()/str.split(): spec_tests.py
;;; opens its file with newline='\n', so a line is only ever terminated by LF; a
;;; lone CR (regression.txt has one) is ordinary content, never a separator.

(defparameter *corpus-whitespace-chars* '(#\Space #\Tab #\Newline #\Return #\Page)
  "The characters GET_TESTS' str.strip() and str.split() treat as whitespace,
close enough for the pinned corpus's own text: space, tab, LF, CR and form
feed.")

(defun corpus-lines (text)
  "TEXT split into lines at #\\Newline only, each line keeping its own
trailing #\\Newline except possibly the last (spec_tests.py's `for line in
specf`, opened with newline='\\n'): a lone #\\Return is ordinary content,
never a line terminator. Built with a loop, not recursion."
  (let ((lines '())
        (start 0)
        (length (length text)))
    (loop for newline = (position #\Newline text :start start)
          while newline
          do (push (subseq text start (1+ newline)) lines)
             (setf start (1+ newline)))
    (when (< start length)
      (push (subseq text start length) lines))
    (nreverse lines)))

(defun corpus-whitespace-char-p (char)
  "True when CHAR is one of *CORPUS-WHITESPACE-CHARS*."
  (member char *corpus-whitespace-chars*))

(defun corpus-trim (string)
  "STRING with leading and trailing *CORPUS-WHITESPACE-CHARS* removed, as
Python's str.strip()."
  (string-trim *corpus-whitespace-chars* string))

(defun corpus-split-words (string)
  "STRING's whitespace-separated words, as Python's str.split() with no
argument: runs of *CORPUS-WHITESPACE-CHARS* separate words, and a leading or
trailing run contributes none. Built with a loop, not recursion."
  (let ((words '())
        (start 0)
        (length (length string)))
    (loop while (< start length)
          do (setf start (or (position-if-not #'corpus-whitespace-char-p string :start start)
                             length))
             (when (< start length)
               (let ((end (or (position-if #'corpus-whitespace-char-p string :start start)
                              length)))
                 (push (subseq string start end) words)
                 (setf start end))))
    (nreverse words)))

(defun corpus-starts-with-p (prefix string)
  "True when STRING starts with PREFIX."
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun join-corpus-lines (lines)
  "LINES, each already ending in its own newline except possibly the last,
concatenated in order into one fresh string."
  (with-output-to-string (out)
    (dolist (line lines)
      (write-string line out))))

(defun replace-arrows-with-tabs (string)
  "STRING with every U+2192 (RIGHTWARDS ARROW) replaced by a tab, as
spec_tests.py's `.replace('\\u2192', \"\\t\")`."
  (substitute #\Tab (code-char #x2192) string))

;;; The fence: 32 backticks, trimmed, open and close an example;
;;; DEFPARAMETER, not DEFCONSTANT, since a fresh string built by MAKE-STRING
;;; isn't EQL to the last one, and DEFCONSTANT may evaluate its value more
;;; than once: as the file compiles, and at each load.

(defparameter *corpus-fence* (make-string 32 :initial-element #\`)
  "The 32-backtick fence that opens and closes a corpus example
(vendor/cmark-gfm/test/spec_tests.py, GET_TESTS).")

(defparameter *corpus-fence-start* (concatenate 'string *corpus-fence* " example")
  "A trimmed line that opens a corpus example starts with this; the words
after it are the example's fence words.")

;;; Section headings: GET_TESTS' header_re, #+ , matched at the very start
;;; of the untrimmed line, outside any example. None of the six files repeats
;;; the pattern within one heading line, so stripping only the leading run
;;; gives the same text Python's header_re.sub('', line).strip() would.

(defun corpus-heading-hash-count (line)
  "The number of LINE's leading #\\# characters, when at least one is
immediately followed by a space; NIL when LINE doesn't open a heading."
  (let ((hashes (or (position-if-not (lambda (char) (char= char #\#)) line) (length line))))
    (when (and (plusp hashes) (< hashes (length line)) (char= (char line hashes) #\Space))
      hashes)))

(defun corpus-section-heading (line)
  "LINE's section heading text when LINE opens one at top level; NIL
otherwise."
  (let ((hashes (corpus-heading-hash-count line)))
    (when hashes
      (corpus-trim (subseq line (1+ hashes))))))

;;; Each example's options: FILE's base options, a fence word "footnotes"
;;; setting :FOOTNOTES T, and every other fence word folded into
;;; :EXTENSIONS, which starts from :PROFILE's own defaults and keeps
;;; *EXTENSION-KEYWORDS*' canonical order with no repeats.

(defun corpus-extension-keyword (word)
  "WORD, a fence word that isn't \"footnotes\", as the keyword :EXTENSIONS
expects: uppercased and interned as a keyword, so \"table\" becomes :TABLE,
matching *EXTENSION-KEYWORDS*."
  (intern (string-upcase word) :keyword))

(defun corpus-base-extensions (profile)
  "PROFILE's default :EXTENSIONS: every one of *EXTENSION-KEYWORDS* under
:GFM, none under :COMMONMARK."
  (ecase profile
    (:gfm (copy-list *extension-keywords*))
    (:commonmark '())))

(defun fenced-options (base-options fence-words)
  "BASE-OPTIONS, extended by FENCE-WORDS, an example's fence-line words:
\"footnotes\" adds :FOOTNOTES T; every other word joins :EXTENSIONS,
canonical order, no repeats, starting from :PROFILE's own defaults.
:EXTENSIONS is always a fresh list, built by LOOP's COLLECT, never
REMOVE-IF-NOT: REMOVE-IF-NOT may return *EXTENSION-KEYWORDS* itself when
PRESENT names every one of them, or a tail of it otherwise (the same hazard
CANONICAL-EXTENSIONS guards against in src/native-core/options.lisp)."
  (let* ((profile (getf base-options :profile))
         (footnotesp (member "footnotes" fence-words :test #'string=))
         (named (mapcar #'corpus-extension-keyword
                        (remove "footnotes" fence-words :test #'string=)))
         (present (append (corpus-base-extensions profile) named))
         (extensions (loop for keyword in *extension-keywords*
                            when (member keyword present) collect keyword)))
    (append base-options
            (and footnotesp (list :footnotes t))
            (list :extensions extensions))))

;;; CORPUS-EXAMPLE and the per-file reader

(defstruct (corpus-example
            (:constructor make-corpus-example (file section number markdown html options))
            (:copier nil))
  "One enabled example of the pinned corpus: FILE, its name under
vendor/cmark-gfm/test/; SECTION, the heading text above it; NUMBER, its
1-based position among FILE's examples, disabled ones counted too; MARKDOWN
and HTML, each with every -> already a tab; and OPTIONS, the plist FILE's
base options and the example's own fence words make (FENCED-OPTIONS)."
  file section number markdown html options)

(defun corpus-file-examples (file base-options text)
  "Every enabled example of TEXT, FILE's content, as CORPUS-EXAMPLEs, in file
order. Mirrors GET_TESTS in vendor/cmark-gfm/test/spec_tests.py line by
line, built with a loop, not recursion:
- a line, once trimmed, starting with the 32-backtick fence then \" example\"
  opens an example; the words after that are its fence words;
- a line of exactly the fence, trimmed, closes it, numbering it whether or
  not it is enabled: \"disabled\" among its fence words skips it;
- a trimmed line of exactly \".\" separates its Markdown from its HTML;
  every other line, untrimmed, collects into whichever side is open;
- outside an example, a line starting with one or more # then a space opens
  a new SECTION, the rest of the line trimmed.
Every -> becomes a tab in both MARKDOWN and HTML."
  (let ((state 0)                       ; 0 regular text, 1 markdown, 2 html
        (number 0)
        (section "")
        (fence-words '())
        (markdown-lines '())
        (html-lines '())
        (examples '()))
    (dolist (line (corpus-lines text) (nreverse examples))
      (let* ((trimmed (corpus-trim line))
             (heading (and (zerop state) (corpus-section-heading line))))
        (cond
          ((corpus-starts-with-p *corpus-fence-start* trimmed)
           (setf state 1
                 fence-words (corpus-split-words (subseq trimmed (length *corpus-fence-start*)))))
          ((string= trimmed *corpus-fence*)
           (incf number)
           (unless (member "disabled" fence-words :test #'string=)
             (push (make-corpus-example
                    file section number
                    (replace-arrows-with-tabs (join-corpus-lines (nreverse markdown-lines)))
                    (replace-arrows-with-tabs (join-corpus-lines (nreverse html-lines)))
                    (fenced-options base-options fence-words))
                   examples))
           (setf state 0 markdown-lines '() html-lines '()))
          ((string= trimmed ".") (setf state 2))
          ((= state 1) (push line markdown-lines))
          ((= state 2) (push line html-lines))
          (heading (setf section heading)))))))

;;; The six files and their base options

(defparameter *corpus-files*
  (list (list "spec.txt" (list :profile :commonmark))
        (list "regression.txt" (list :profile :commonmark))
        (list "smart_punct.txt" (list :profile :commonmark :smart t))
        (list "extensions.txt" (list :profile :gfm))
        (list "extensions-full-info-string.txt" (list :profile :gfm))
        (list "extensions-table-prefer-style-attributes.txt" (list :profile :gfm)))
  "The pinned corpus's six files, in the order CORPUS-EXAMPLES reads them,
each with its own base options. spec.txt, regression.txt and
smart_punct.txt are plain CommonMark, smart_punct.txt with :SMART T; the
other three are :GFM. extensions-full-info-string.txt and
extensions-table-prefer-style-attributes.txt test CLI flags that no option
of this library sets (--full-info-string, --table-prefer-style-attributes).")

(defun corpus-pathname (file)
  "The absolute pathname of vendor/cmark-gfm/test/FILE."
  (asdf:system-relative-pathname "cl-commonmark-gfm/tests"
                                 (concatenate 'string "vendor/cmark-gfm/test/" file)))

(defun read-corpus-file (file base-options)
  "FILE's enabled examples, read from vendor/cmark-gfm/test/FILE as UTF-8."
  (corpus-file-examples file base-options
                        (uiop:read-file-string (corpus-pathname file) :external-format :utf-8)))

(defun corpus-examples ()
  "Every enabled example of the pinned corpus's six files, in *CORPUS-FILES*'
order, each file's own numbering intact: 747 in all."
  (loop for (file base-options) in *corpus-files*
        append (read-corpus-file file base-options)))

;;; FENCED-OPTIONS: its :EXTENSIONS must share no structure with the global
;;; (the same hazard CANONICAL-EXTENSIONS guards against in
;;; src/native-core/options.lisp; NO-SHARED-CONS-P is defined in
;;; tests/native-core.lisp, which loads first).

(define-test fenced-options-extensions-share-no-cons-with-the-global
  ;; :GFM's base extensions alone already name every one of
  ;; *EXTENSION-KEYWORDS*, so a naive REMOVE-IF-NOT here could return the
  ;; global itself, exactly as CANONICAL-EXTENSIONS could.
  (true (no-shared-cons-p (getf (fenced-options (list :profile :gfm) '()) :extensions)
                          *extension-keywords*)))

;;; Tests: the counts, and one example per file checked field by field.

(defun corpus-counts-by-file ()
  "An alist of each *CORPUS-FILES* name to how many enabled examples
CORPUS-EXAMPLES found for it."
  (mapcar (lambda (entry) (cons (first entry) (length (read-corpus-file (first entry)
                                                                        (second entry)))))
          *corpus-files*))

(define-test the-corpus-has-747-enabled-examples-in-six-files
  (is equal '(("spec.txt" . 670) ("regression.txt" . 26) ("smart_punct.txt" . 16)
              ("extensions.txt" . 30) ("extensions-full-info-string.txt" . 4)
              ("extensions-table-prefer-style-attributes.txt" . 1))
      (corpus-counts-by-file))
  (is = 747 (length (corpus-examples))))

(defun find-corpus-example (file number)
  "FILE's example numbered NUMBER, or NIL."
  (find number (read-corpus-file file (second (assoc file *corpus-files* :test #'string=)))
        :key #'corpus-example-number))

(defun tab ()
  "A string holding one tab, spelled out so a test needn't embed a raw tab
character in source (AGENTS.md: max 100 columns, ASCII source)."
  (string #\Tab))

(define-test spec-example-1-has-a-tab-in-both-fields
  ;; Section "Tabs": -> appears in spec.txt (21 lines); a literal tab never
  ;; does. Here, in both the Markdown and the expected HTML, example 1's ->
  ;; has already become a real tab, via REPLACE-ARROWS-WITH-TABS.
  (let ((example (find-corpus-example "spec.txt" 1)))
    (is string= "Tabs" (corpus-example-section example))
    (is string= (concatenate 'string (tab) "foo" (tab) "baz" (tab) (tab) "bim" (string #\Newline))
        (corpus-example-markdown example))
    (is string= (concatenate 'string "<pre><code>foo" (tab) "baz" (tab) (tab) "bim"
                            (string #\Newline) "</code></pre>" (string #\Newline))
        (corpus-example-html example))
    (is equal '(:profile :commonmark :extensions ()) (corpus-example-options example))))

(define-test regression-example-13-has-a-fence-line-with-two-names
  ;; Fence line "table footnotes": :footnotes t from the word "footnotes",
  ;; :extensions (:table) from "table", in canonical order.
  (let ((example (find-corpus-example "regression.txt" 13)))
    (is string= "Regression tests" (corpus-example-section example))
    (is string= (format nil "A footnote in a paragraph[^1]~%~%| Column1   | Column2 |~%~
| --------- | ------- |~%| foot [^1] | note    |~%~%[^1]: a footnote~%")
        (corpus-example-markdown example))
    (is string=
        (format nil "<p>A footnote in a paragraph<sup class=\"footnote-ref\"><a href=\"#fn-1\" ~
id=\"fnref-1\" data-footnote-ref>1</a></sup></p>~%<table>~%<thead>~%<tr>~%<th>Column1</th>~%~
<th>Column2</th>~%</tr>~%</thead>~%<tbody>~%<tr>~%<td>foot <sup class=\"footnote-ref\">~
<a href=\"#fn-1\" id=\"fnref-1-2\" data-footnote-ref>1</a></sup></td>~%<td>note</td>~%</tr>~%~
</tbody>~%</table>~%<section class=\"footnotes\" data-footnotes>~%<ol>~%<li id=\"fn-1\">~%~
<p>a footnote <a href=\"#fnref-1\" class=\"footnote-backref\" data-footnote-backref ~
data-footnote-backref-idx=\"1\" aria-label=\"Back to reference 1\">~A</a> ~
<a href=\"#fnref-1-2\" class=\"footnote-backref\" data-footnote-backref ~
data-footnote-backref-idx=\"1-2\" aria-label=\"Back to reference 1-2\">~A~
<sup class=\"footnote-ref\">2</sup></a></p>~%</li>~%</ol>~%</section>~%"
                (string (code-char #x21A9)) (string (code-char #x21A9)))
        (corpus-example-html example))
    (is equal '(:profile :commonmark :footnotes t :extensions (:table))
        (corpus-example-options example))))

(define-test smart-punct-example-1-has-smart-t-in-its-base-options
  (let ((example (find-corpus-example "smart_punct.txt" 1)))
    (is string= "Smart punctuation" (corpus-example-section example))
    (is equal '(:profile :commonmark :smart t :extensions ())
        (corpus-example-options example))))

(define-test extensions-example-1-has-every-extension-by-profile-default
  (let ((example (find-corpus-example "extensions.txt" 1)))
    (is string= "Tables" (corpus-example-section example))
    (is equal '(:profile :gfm
                :extensions (:table :strikethrough :autolink :tagfilter :tasklist))
        (corpus-example-options example))))

(define-test extensions-full-info-string-example-1-fields
  (let ((example (find-corpus-example "extensions-full-info-string.txt" 1)))
    (is string= (format nil "```ruby~%module Foo~%```~%") (corpus-example-markdown example))
    (is string= (format nil "<pre><code class=\"language-ruby\">module Foo~%</code></pre>~%")
        (corpus-example-html example))
    (is equal '(:profile :gfm
                :extensions (:table :strikethrough :autolink :tagfilter :tasklist))
        (corpus-example-options example))))

(define-test extensions-table-prefer-style-attributes-example-1-fields
  (let ((example (find-corpus-example "extensions-table-prefer-style-attributes.txt" 1)))
    (is string= "Tables" (corpus-example-section example))
    (is equal '(:profile :gfm
                :extensions (:table :strikethrough :autolink :tagfilter :tasklist))
        (corpus-example-options example))))

(define-test the-ignore-example-is-extensions-20-in-autolinks
  (let ((example (find-corpus-example "extensions.txt" 20)))
    (is string= "Autolinks" (corpus-example-section example))
    (is string= (format nil "<IGNORE>~%") (corpus-example-html example))))
