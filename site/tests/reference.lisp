;;;; Tests for the API reference: docstrings into Markdown, the page's
;;;; layout, and the check of docs/reference.md against the docstrings.
;;;; Most build entries by hand; a few read this image's exports, as `make
;;;; reference` does.

(in-package #:cl-commonmark-gfm.site.tests)

;;; Helpers

(defun docstring (&rest lines)
  "LINES as one docstring, joined by newlines."
  (format nil "~{~A~^~%~}" lines))

(defun home-package (home)
  "The name of the package HOME stands for: :MAIN, :NATIVE-CORE, :AST,
:HTML-TREE or :CONDITIONS."
  (ecase home
    (:main "CL-COMMONMARK-GFM")
    (:native-core "CL-COMMONMARK-GFM.NATIVE-CORE")
    (:ast "CL-COMMONMARK-GFM.AST")
    (:html-tree "CL-COMMONMARK-GFM.HTML-TREE")
    (:conditions "CL-COMMONMARK-GFM.CONDITIONS")))

(defun entry (name home kind &key lambda-list parents (docstring "Some text.") code-words)
  "A hand-built entry for the export NAME, of KIND, whose home package HOME
stands for, as HOME-PACKAGE reads it."
  (cl-commonmark-gfm.site::make-entry :name name
                                      :package (home-package home)
                                      :kind kind
                                      :lambda-list lambda-list
                                      :parents parents
                                      :docstring docstring
                                      :code-words code-words))

(defun markdown (docstring &key lambda-list code-words)
  "DOCSTRING in Markdown, as the docstring of a function whose lambda list
is LAMBDA-LIST, and among whose words CODE-WORDS name something."
  (cl-commonmark-gfm.site::docstring-markdown
   (entry "f" :main :function :lambda-list lambda-list :docstring docstring
                              :code-words code-words)))

(defun meaning (docstring)
  "What the reference means the Markdown it writes for DOCSTRING to render
to, as a list: its text, then the code it holds, as DOCSTRING-RENDERING
gives them."
  (multiple-value-bind (markdown text codes)
      (cl-commonmark-gfm.site::docstring-rendering (entry "f" :main :function :docstring docstring))
    (declare (ignore markdown))
    (list text codes)))

(defun page-text (entries)
  "The reference page that documents ENTRIES."
  (cl-commonmark-gfm.site::reference-text (cl-commonmark-gfm.site::reference-parts entries)))

(defun text-lines (text)
  "TEXT's lines, split at its newlines."
  (uiop:split-string text :separator (list #\Newline)))

(defun heading-lines (text)
  "TEXT's lines that are ATX headings, starting with #."
  (remove-if-not (lambda (line) (and (plusp (length line)) (char= (char line 0) #\#)))
                 (text-lines text)))

(defun entry-text (entry)
  "ENTRY's part of the page that documents it alone."
  (cdr (assoc (cons :entry (cl-commonmark-gfm.site::entry-name entry))
              (cl-commonmark-gfm.site::reference-parts (list entry))
              :test #'equal)))

(defun replace-first (old new string)
  "STRING with its first OLD replaced by NEW."
  (let ((start (search old string)))
    (concatenate 'string (subseq string 0 start) new (subseq string (+ start (length old))))))

(defun real-entries ()
  "This image's entries, read as `make reference` reads them."
  (cl-commonmark-gfm.site::read-entries cl-commonmark-gfm.site::*reference-package*))

(defun real-entry (name)
  "This image's entry for the export NAME."
  (find name (real-entries) :key #'cl-commonmark-gfm.site::entry-name :test #'string=))

(defun real-code-word-p (name word)
  "True when this image's entry for NAME lists WORD among the words of its
docstring that name something."
  (and (member word (cl-commonmark-gfm.site::entry-code-words (real-entry name))
               :test #'string=)
       t))

(defun real-heading-ids (names)
  "The ids the site gives the headings of this image's reference whose
texts are NAMES, in page order, each as (TEXT . ID). The page goes through
RENDER-SITE, as docs/reference.md does."
  (let* ((page (page-text (real-entries)))
         (texts (mapcar #'heading-text (cl-commonmark-gfm.site::find-headings (parse page))))
         (site-ids (nth-value 1 (render-site (list (cons "README.md" (format nil "# Home~%"))
                                                   (cons "reference.md" page))
                                             "main")))
         (ids (cdr (assoc "reference.md" site-ids :test #'string=))))
    (loop for text in texts
          for id in ids
          when (member text names :test #'string=)
            collect (cons text id))))

(defun tricky-entries ()
  "Entries whose docstrings each hold what one escape guards against, which
Markdown would read as its syntax unescaped: a block's marker at the start
of a paragraph or a list item, and emphasis, code, a link, raw HTML, an
entity, strikethrough and a backslash's escape within one."
  (loop for (name text) in '(("number-period" "1. A number then a period")
                             ("number-parenthesis" "2) A number then a parenthesis")
                             ("hash" "# A hash")
                             ("quote-mark" "> A quote mark")
                             ("plus" "+ A plus")
                             ("rule" "---")
                             ("nested-item" "- - A hyphen in an item")
                             ("emphasis" "Stars *a* and underscores _b_")
                             ("code" "A ` spaced ` pair")
                             ("link" "A [link](target) and [another]")
                             ("raw-html" "A <b>tag</b>")
                             ("entity" "An &amp; entity")
                             ("strikethrough" "Tildes ~~a~~ and ~b~")
                             ("backslash" "A \\. backslash")
                             ("pipes" "| a | b |"))
        collect (entry name :main :function :docstring text)))

(defun rendering-problems-of (docstring &key lambda-list code-words)
  "The render check's problems with an entry F whose docstring is
DOCSTRING, a function whose lambda list is LAMBDA-LIST, and among whose
words CODE-WORDS name something."
  (cl-commonmark-gfm.site::rendering-problems
   (list (entry "f" :main :function :lambda-list lambda-list :docstring docstring
                                    :code-words code-words))))

(defun backquoted-code-advice (run)
  "What the render check says about an entry F whose docstring puts RUN in
backquotes, though the reference makes it code without them."
  (format nil "f's docstring puts ~A in backquotes, which keep its case; ~
               drop them, so the reference makes it code"
          run))

(defun call-with-definition (name function thunk)
  "Call THUNK while the generator's function NAME is FUNCTION, as a broken
generator's would be, and restore the real one however THUNK exits."
  (let ((original (fdefinition name)))
    (unwind-protect
         (progn
           (setf (fdefinition name) function)
           (funcall thunk))
      (setf (fdefinition name) original))))

(defun guard-report (docstring)
  "The report of the error PARSE signals for the Markdown the reference
writes for DOCSTRING, as PRINC writes it."
  (princ-to-string (nth-value 1 (ignore-errors (parse (markdown docstring))))))

(defun real-part-and-piece-counts ()
  "The number of parts of this image's reference, and the number of pieces
its page cuts into, as a list."
  (let ((parts (cl-commonmark-gfm.site::reference-parts (real-entries))))
    (list (length parts)
          (length (cl-commonmark-gfm.site::text-pieces
                   (cl-commonmark-gfm.site::reference-text parts))))))

;;; Docstrings into Markdown

(define-test docstring-markdown-separates-paragraphs-at-blank-lines
  (is string= (format nil "First paragraph on two lines~%~%Second paragraph")
      (markdown (docstring "First paragraph" "on two lines" "" "Second paragraph"))))

(define-test docstring-markdown-writes-list-items-and-their-continuations
  (is string= (format nil "Options~%~%- first item continued~%- second item~%~%After the list")
      (markdown (docstring "Options" "- first item" "  continued" "- second item"
                           "After the list"))))

(define-test docstring-markdown-writes-names-as-lower-case-code
  (is string= "Takes `:gfm`" (markdown "Takes :GFM"))
  (is string= "Binds `*max-nodes*`" (markdown "Binds *MAX-NODES*"))
  (is string= "Signals `resource-limit-exceeded`"
      (markdown "Signals RESOURCE-LIMIT-EXCEEDED" :code-words '("RESOURCE-LIMIT-EXCEEDED")))
  (is string= "Returns `nil`" (markdown "Returns NIL"))
  (is string= "Reads `markdown`"
      (markdown "Reads MARKDOWN" :lambda-list '("markdown" "&rest" "options"))))

(define-test docstring-markdown-leaves-punctuation-after-a-name-as-text
  (is string= "Takes `:profile`: `:gfm`, then `node`'s kind."
      (markdown "Takes :PROFILE: :GFM, then NODE's kind." :code-words '("NODE"))))

(define-test docstring-markdown-writes-what-users-type-as-code
  (is string= "Writes `\"<br />\"`, or `\"<!-- raw HTML omitted -->\"`"
      (markdown "Writes \"<br />\", or \"<!-- raw HTML omitted -->\""))
  (is string= "Reads `CL_COMMONMARK_GFM_LIBS`, as `CMARK_OPT_UNSAFE` does"
      (markdown "Reads CL_COMMONMARK_GFM_LIBS, as CMARK_OPT_UNSAFE does"))
  (is string= "Searches `/usr/lib/<multiarch>`, then `/usr/lib`."
      (markdown "Searches /usr/lib/<multiarch>, then /usr/lib.")))

(define-test docstring-markdown-writes-a-backquoted-run-as-code-without-its-backquotes
  (is string= "Links `libcmark-gfm.a` statically" (markdown "Links `libcmark-gfm.a` statically"))
  (is equal '("Links libcmark-gfm.a statically" ("libcmark-gfm.a"))
      (meaning "Links `libcmark-gfm.a` statically")))

(define-test rendering-problems-refuse-a-backquoted-run-that-is-code-without-them
  (is equal (mapcar #'backquoted-code-advice
                    '("*MAX-NODES*" ":GFM" "MARKDOWN" "PARSE" "NIL." "(PARSE MARKDOWN)"))
      (rendering-problems-of (docstring "Names `*MAX-NODES*`, `:GFM`, `MARKDOWN`, `PARSE`, `NIL.`"
                                        "and `(PARSE MARKDOWN)`.")
                             :lambda-list '("markdown") :code-words '("PARSE")))
  (is equal '() (rendering-problems-of "Keeps `UTF-8`, `NO-SUCH-NAME` and `libcmark-gfm.a`.")))

(define-test docstring-markdown-keeps-a-backquoted-run-as-written
  (is string= "Keeps `UTF-8`, `x86_64-linux-gnu`, `a*b*c` and `<multiarch>` as written"
      (markdown "Keeps `UTF-8`, `x86_64-linux-gnu`, `a*b*c` and `<multiarch>` as written")))

(define-test docstring-markdown-leaves-a-lone-backquote-escaped
  (is string= "A lone \\` backquote" (markdown "A lone ` backquote"))
  (is string= "A lone \\`backquote here" (markdown "A lone `backquote here"))
  (is string= "Opens \\`here and closes\\` on the next line"
      (markdown (docstring "Opens `here and" "closes` on the next line"))))

(define-test docstring-markdown-leaves-a-pair-commonmark-reads-otherwise-escaped
  (is string= "Empty \\`\\` pair" (markdown "Empty `` pair"))
  (is string= "Spaced \\` a\\` and \\`b \\` pairs" (markdown "Spaced ` a` and `b ` pairs"))
  (is string= "Doubled \\`a\\`\\`b\\` pairs" (markdown "Doubled `a``b` pairs"))
  (is string= "Then \\`a \\`b\\` stays text" (markdown "Then `a `b` stays text")))

(define-test docstring-markdown-reads-a-string-or-a-run-whichever-opens-first
  (is string= "Quotes ``\"a`b\"`` then c\\`d" (markdown "Quotes \"a`b\" then c`d"))
  (is string= "Runs `a\"b` then `\"c\"`" (markdown "Runs `a\"b` then \"c\"")))

(define-test docstring-markdown-writes-a-form-as-one-code-span
  (is string= "Same as `(ast->html-tree (parse markdown ...) ...)`, but faster"
      (markdown (docstring "Same as (AST->HTML-TREE (PARSE" "MARKDOWN ...) ...), but faster")
                :lambda-list '("markdown") :code-words '("AST->HTML-TREE" "PARSE"))))

(define-test docstring-markdown-reads-past-a-parenthesis-in-a-forms-string
  (is string= "Calls `(format nil \")\")` once" (markdown "Calls (FORMAT NIL \")\") once")))

(define-test docstring-markdown-fences-code-holding-a-backtick-with-two
  (is string= "Calls ``(format nil \"`\")`` once" (markdown "Calls (FORMAT NIL \"`\") once")))

(define-test docstring-markdown-keeps-the-case-of-a-forms-strings
  (is string= "Writes `(:*comment* nil \" raw HTML omitted \")`"
      (markdown "Writes (:*COMMENT* NIL \" raw HTML omitted \")")))

(define-test docstring-markdown-leaves-a-remark-in-parentheses-as-text
  (is string= "Read (`*max-nodes*` or a list) first"
      (markdown "Read (*MAX-NODES* or a list) first"))
  (is string= "A list (CORE EXTENSIONS)" (markdown "A list (CORE EXTENSIONS)")))

(define-test docstring-markdown-leaves-a-remark-with-a-comma-as-text
  (is string= "Signalled by (`parse`, `markdown->html`) alike"
      (markdown "Signalled by (PARSE, MARKDOWN->HTML) alike"
                :code-words '("PARSE" "MARKDOWN->HTML"))))

(define-test docstring-markdown-leaves-words-that-name-nothing-as-text
  (is string= "UTF-8 and HTML" (markdown "UTF-8 and HTML")))

(define-test docstring-markdown-escapes-markdowns-characters-anywhere
  (is string= "Escapes \\\\ \\` \\* \\_ \\[ \\] \\< \\& \\| and \\~"
      (markdown "Escapes \\ ` * _ [ ] < & | and ~")))

(define-test docstring-markdown-leaves-other-punctuation-as-written
  (is string= "A, b. c: d's (e) $f% ^g@ !h? {i} =j +k -l #m >n 1. o 2) p"
      (markdown "A, b. c: d's (e) $f% ^g@ !h? {i} =j +k -l #m >n 1. o 2) p")))

(define-test unescape-text-takes-out-the-backslashes-escape-text-adds
  (dolist (text '("# a" "> a" "+ a" "- a" "= a" "1. a" "12) a" "\\- a" "a - b. 3) c"
                  "a\\b `c` *d* _e_ [f] <g> &h |i| ~j"))
    (is string= text (cl-commonmark-gfm.site::unescape-text
                      (cl-commonmark-gfm.site::escape-text text t)))))

(define-test unescape-text-leaves-every-other-backslash
  (is string= "a \\- b \\. c \\q" (cl-commonmark-gfm.site::unescape-text "a \\- b \\. c \\q")))

(define-test docstring-markdown-escapes-what-would-start-a-block
  (is string= "\\# Not a heading" (markdown "# Not a heading"))
  (is string= "\\> Not a quote" (markdown "> Not a quote"))
  (is string= "\\+ Not an item" (markdown "+ Not an item"))
  (is string= "\\-1 is no item" (markdown "-1 is no item"))
  (is string= "\\= Not an underline" (markdown "= Not an underline"))
  (is string= "1\\. Not an item" (markdown "1. Not an item"))
  (is string= "12\\) Not an item" (markdown "12) Not an item"))
  (is string= "- \\- Not a nested item" (markdown "- - Not a nested item")))

(define-test reference-entries-render-as-their-own-text
  (is equal '() (cl-commonmark-gfm.site::rendering-problems (real-entries)))
  (is equal '() (cl-commonmark-gfm.site::rendering-problems (tricky-entries))))

(defparameter *link-advice*
  (concatenate 'string "f's docstring renders www.example.com as an <a> element; "
               "put it in backquotes, `www.example.com`, so it becomes code")
  "What the render check says about an entry F whose docstring holds
www.example.com, which GFM links by itself.")

(define-test rendering-problems-say-to-backquote-what-renders-as-a-link
  (is equal (list *link-advice*)
      (cl-commonmark-gfm.site::rendering-problems
       (list (entry "f" :main :function :docstring "See www.example.com for more.")))))

(define-test rendering-problems-say-to-double-quote-a-link-holding-a-backquote
  (is equal (list (concatenate 'string "f's docstring renders www.example.com` "
                               "as an <a> element; write it in double quotes, "
                               "\"www.example.com`\", so it becomes code"))
      (rendering-problems-of "See www.example.com` for more.")))

(define-test rendering-problems-give-a-link-as-the-docstring-holds-it
  (is equal (list (concatenate 'string "f's docstring renders www.example.com/a_b "
                               "as an <a> element; put it in backquotes, "
                               "`www.example.com/a_b`, so it becomes code"))
      (rendering-problems-of "See www.example.com/a_b for more.")))

(define-test stray-element-problem-says-to-backquote-what-makes-an-empty-element
  (is string= (concatenate 'string "f's docstring renders an <*comment*> element; "
                           "put what makes it in backquotes, so it becomes code")
      (cl-commonmark-gfm.site::stray-element-problem "f" :*comment* "")))

(define-test rendering-problems-pass-a-quoted-address
  (is equal '()
      (cl-commonmark-gfm.site::rendering-problems
       (list (entry "f" :main :function
                        :docstring "See \"https://www.example.com\" for more.")))))

(define-test rendering-problems-pass-backquoted-runs
  (is equal '()
      (rendering-problems-of (docstring "Links `libcmark-gfm.a` for `x86_64-linux-gnu`, writes"
                                        "`<b>*a*_b_</b>`, and reads `https://www.example.com`."))))

(define-test rendering-problems-report-a-docstring-the-footnote-guard-refuses
  (flet ((guard-problem (docstring)
           (format nil "f's docstring: can't be parsed: unsupported-input: ~A; ~
                        write the pattern as text, outside double quotes and backquotes, ~
                        or split it into two quoted strings"
                   (guard-report docstring))))
    (is equal (list (guard-problem "Quotes \"[&#94;\" in code."))
        (rendering-problems-of "Quotes \"[&#94;\" in code."))
    (is equal (list (guard-problem "Quotes `[&#94;` in a run."))
        (rendering-problems-of "Quotes `[&#94;` in a run."))))

(define-test rendering-problems-pass-the-guards-pattern-as-text-or-split
  (is equal '() (rendering-problems-of "Writes [&#94; as text."))
  (is equal '() (rendering-problems-of "Quotes \"[\" then \"&#94;\" in code.")))

(define-test rendering-problems-name-the-text-a-lost-escape-changes
  (flet ((unescaped (docstring)
           (call-with-definition 'cl-commonmark-gfm.site::escape-text
                                 (lambda (text at-start)
                                   (declare (ignore at-start))
                                   text)
                                 (lambda () (rendering-problems-of docstring)))))
    (is equal '("f's docstring renders \"An & entity\" where it means \"An &amp; entity\"")
        (unescaped "An &amp; entity"))
    (is equal '("f's docstring renders \"A . backslash\" where it means \"A \\\\. backslash\"")
        (unescaped "A \\. backslash"))))

(define-test rendering-problems-name-the-code-a-lost-span-changes
  (is equal '("f's docstring renders no code where it means the code \":gfm\"")
      (call-with-definition 'cl-commonmark-gfm.site::code-span
                            (lambda (code) code)
                            (lambda () (rendering-problems-of "Takes :GFM")))))

;;; Lambda lists

(define-test lambda-list-names-are-bare-lowercase-names
  (is equal '("a" "&optional" "b" "&key" "cee" "d")
      (cl-commonmark-gfm.site::lambda-list-names '(a &optional (b 1 b-p) &key ((:cee c) 2) d)))
  (is equal '("(var list)" "&body" "body")
      (cl-commonmark-gfm.site::lambda-list-names '((var list) &body body))))

(define-test read-entries-gives-bare-lambda-lists
  (is equal '("node" "&key" "attributes" "children" "sourcepos")
      (cl-commonmark-gfm.site::entry-lambda-list (real-entry "copy-node")))
  (is equal '("function" "node")
      (cl-commonmark-gfm.site::entry-lambda-list (real-entry "map-ast"))))

;;; Reading the image

(define-test read-entries-gives-a-conditions-direct-parents
  (is equal '("commonmark-gfm-error")
      (cl-commonmark-gfm.site::entry-parents (real-entry "resource-limit-exceeded")))
  (is equal '("error") (cl-commonmark-gfm.site::entry-parents (real-entry "commonmark-gfm-error"))))

(define-test read-entries-finds-the-docstring-words-that-name-something
  ;; MAKE-NODE isn't accessible in INVALID-AST-NODE's home package, the
  ;; conditions', but is in the one the reference documents.
  (true (real-code-word-p "invalid-ast-node" "MAKE-NODE"))
  ;; MARKDOWN is interned there, as PARSE's parameter, but names nothing.
  (is eql :internal (nth-value 1 (find-symbol "MARKDOWN" "CL-COMMONMARK-GFM")))
  (true (member "MARKDOWN"
                (cl-commonmark-gfm.site::docstring-words
                 (cl-commonmark-gfm.site::entry-docstring (real-entry "parse")))
                :test #'string=))
  (is eql nil (real-code-word-p "parse" "MARKDOWN")))

;;; The page's layout

(define-test reference-page-opens-with-its-title-and-a-line-on-what-it-lists
  (let ((lines (text-lines (page-text (list (entry "parse" :main :function
                                                   :lambda-list '("markdown")))))))
    (is equal '("# API reference" ""
                "This page lists every exported symbol, from its docstring."
                "")
        (subseq lines 0 4))))

(define-test reference-page-has-a-section-per-home-package-in-order
  (is equal '("# API reference"
              "## Rendering and parsing" "### `parse`" "### `*max-nodes*`"
              "## The AST" "### `node`"
              "## The HTML tree" "### `html-tree->string`"
              "## Conditions" "### `commonmark-gfm-error`" "### `invalid-html-tree`")
      (heading-lines
       (page-text (list (entry "invalid-html-tree" :conditions :condition
                               :parents '("commonmark-gfm-error"))
                        (entry "html-tree->string" :html-tree :function :lambda-list '("tree"))
                        (entry "*max-nodes*" :native-core :variable)
                        (entry "node" :ast :structure)
                        (entry "commonmark-gfm-error" :conditions :condition :parents '("error"))
                        (entry "parse" :main :function :lambda-list '("markdown")))))))

(define-test reference-page-orders-a-section-by-kind-then-name
  (is equal '("# API reference" "## The AST"
              "### `yard`" "### `zone`"
              "### `alarm-error`" "### `bell-error`"
              "### `copy-node`" "### `do-nodes`" "### `walk-ast`" "### `with-node`"
              "### `*a-limit*`" "### `*z-limit*`")
      (heading-lines
       (page-text (list (entry "*z-limit*" :ast :variable)
                        (entry "with-node" :ast :macro :lambda-list '("(var node)" "&body" "body"))
                        (entry "bell-error" :ast :condition :parents '("error"))
                        (entry "zone" :ast :structure)
                        (entry "walk-ast" :ast :function :lambda-list '("function" "node"))
                        (entry "*a-limit*" :ast :variable)
                        (entry "do-nodes" :ast :macro :lambda-list '("(var node)" "&body" "body"))
                        (entry "alarm-error" :ast :condition :parents '("error"))
                        (entry "copy-node" :ast :function :lambda-list '("node"))
                        (entry "yard" :ast :structure))))))

(define-test reference-entries-show-their-kind-call-form-and-docstring
  (is string= (format nil "### `copy-node`~%~%Function~%~%~
                           `(copy-node node &key attributes children sourcepos)`~%~%~
                           Copies `node`.~%")
      (entry-text (entry "copy-node" :ast :function
                         :lambda-list '("node" "&key" "attributes" "children" "sourcepos")
                         :docstring "Copies NODE.")))
  (is string= (format nil "### `with-node`~%~%Macro~%~%`(with-node (var node) &body body)`~%~%~
                           Some text.~%")
      (entry-text (entry "with-node" :ast :macro :lambda-list '("(var node)" "&body" "body"))))
  (is string= (format nil "### `*max-nodes*`~%~%Variable~%~%Some text.~%")
      (entry-text (entry "*max-nodes*" :main :variable)))
  (is string= (format nil "### `node`~%~%Structure~%~%Some text.~%")
      (entry-text (entry "node" :ast :structure))))

(define-test reference-conditions-name-their-parents
  (is equal '("Condition, a subtype of `error`"
              "Condition, a subtype of [`native-error`](#native-error) and `type-error`"
              "Condition, a subtype of [`commonmark-gfm-error`](#commonmark-gfm-error)")
      (remove-if-not (lambda (line) (eql 0 (search "Condition" line)))
                     (text-lines
                      (page-text (list (entry "native-error" :conditions :condition
                                              :parents '("commonmark-gfm-error"))
                                       (entry "dual-error" :conditions :condition
                                              :parents '("native-error" "type-error"))
                                       (entry "commonmark-gfm-error" :conditions :condition
                                              :parents '("error"))))))))

(define-test reference-links-a-parent-by-its-headings-id
  (is equal '("Condition, a subtype of `error`"
              "Condition, a subtype of [`base-error`](#base-error-1)")
      (remove-if-not (lambda (line) (eql 0 (search "Condition" line)))
                     (text-lines
                      (page-text (list (entry "base-error=" :main :function :lambda-list '("x"))
                                       (entry "base-error" :conditions :condition
                                              :parents '("error"))
                                       (entry "child-error" :conditions :condition
                                              :parents '("base-error"))))))))

(define-test reference-puts-node-before-node=-which-takes-node-1
  (is equal '(("node" . "node") ("node=" . "node-1")) (real-heading-ids '("node" "node="))))

;;; The check

(defun check-entries (&key (node-docstring "Some text."))
  "Three entries, one in each of three sections, NODE's docstring
NODE-DOCSTRING."
  (list (entry "parse" :main :function :lambda-list '("markdown"))
        (entry "node" :ast :structure :docstring node-docstring)
        (entry "commonmark-gfm-error" :conditions :condition :parents '("error"))))

(define-test reference-page-cuts-into-one-piece-per-part
  (destructuring-bind (parts pieces) (real-part-and-piece-counts)
    (is = parts pieces)))

(define-test reference-problems-accepts-a-current-page
  (is equal '() (cl-commonmark-gfm.site::reference-problems (check-entries)
                                                             (page-text (check-entries)))))

(define-test reference-problems-names-the-entry-that-differs
  (is equal '("docs/reference.md differs at the entry for node: run make reference")
      (cl-commonmark-gfm.site::reference-problems
       (check-entries) (page-text (check-entries :node-docstring "Edited.")))))

(define-test reference-problems-names-the-opening-or-the-section-that-differs
  (let ((page (page-text (check-entries))))
    (is equal '("docs/reference.md differs at its opening: run make reference")
        (cl-commonmark-gfm.site::reference-problems (check-entries)
                                                     (concatenate 'string "Edited. " page)))
    (is equal '("docs/reference.md differs at the section The AST: run make reference")
        (cl-commonmark-gfm.site::reference-problems (check-entries)
                                                     (replace-first "## The AST" "## The Tree"
                                                                    page)))
    (is equal (list (concatenate 'string "docs/reference.md differs at the entry for "
                                 "commonmark-gfm-error: run make reference"))
        (cl-commonmark-gfm.site::reference-problems (check-entries)
                                                     (concatenate 'string page "Edited.")))))

(define-test reference-problems-names-the-entry-that-lost-its-docstring
  (is equal '("node has no docstring"
              "docs/reference.md differs at the entry for node: run make reference")
      (cl-commonmark-gfm.site::reference-problems (check-entries :node-docstring nil)
                                                   (page-text (check-entries)))))

(define-test reference-problems-names-the-part-before-an-extra-blank-line
  (is equal '("docs/reference.md differs at the entry for parse: run make reference")
      (cl-commonmark-gfm.site::reference-problems
       (check-entries) (replace-first (format nil "~%## The AST") (format nil "~%~%## The AST")
                                      (page-text (check-entries))))))

(define-test reference-problems-names-the-entry-a-short-page-lacks
  (let ((entries (cons (entry "condition-reason" :conditions :function :lambda-list '("condition"))
                       (check-entries))))
    (is equal (list (concatenate 'string "docs/reference.md differs at the entry for "
                                 "condition-reason: run make reference"))
        (cl-commonmark-gfm.site::reference-problems entries (page-text (check-entries))))))

(define-test reference-problems-report-a-docstring-that-renders-a-link
  (let ((entries (list (entry "f" :main :function :docstring "See www.example.com for more."))))
    (is equal (list *link-advice*)
        (cl-commonmark-gfm.site::reference-problems entries (page-text entries)))))

(define-test reference-problems-names-a-missing-page
  (is equal '("docs/reference.md is missing: run make reference")
      (cl-commonmark-gfm.site::reference-problems (check-entries) nil)))

(define-test reference-problems-names-each-export-with-no-docstring
  (let ((entries (list (entry "walk-ast" :ast :function :lambda-list '("function" "node"))
                       (entry "node" :ast :structure :docstring (format nil " ~%"))
                       (entry "parse" :main :function :lambda-list '("markdown") :docstring nil))))
    (is equal '("parse has no docstring" "node has no docstring")
        (cl-commonmark-gfm.site::reference-problems entries (page-text entries)))))
