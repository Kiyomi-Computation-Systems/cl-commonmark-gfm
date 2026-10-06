;;;; Tests for the site's core: heading ids, link destinations, the page
;;;; template, RENDER-SITE over small sites built here, and the site's use
;;;; of the library's public API alone.

(in-package #:cl-commonmark-gfm.site.tests)

;;; Helpers

(defun lines (&rest lines)
  "LINES as one Markdown text, each line ending in a newline."
  (format nil "~{~A~%~}" lines))

(defun first-block (markdown)
  "The first block of MARKDOWN's AST."
  (first (node-children (parse markdown))))

(defun newline ()
  "A string holding one newline, as cmark writes between blocks."
  (string #\Newline))

(defun child-elements (element)
  "ELEMENT's children that are elements, in order."
  (remove-if-not #'consp (cddr element)))

(defun attribute (element name)
  "The value of ELEMENT's attribute NAME, or NIL."
  (second (assoc name (second element))))

(defun find-element (tag class tree)
  "The first element of TREE, an HTML tree element, in document order whose
tag is TAG and, unless CLASS is NIL, whose class is CLASS; or NIL. Loops
over an explicit stack of child lists."
  (let ((stack (list (list tree))))
    (loop while stack
          do (let ((nodes (pop stack)))
               (when nodes
                 (push (rest nodes) stack)
                 (let ((node (first nodes)))
                   (when (consp node)
                     (when (and (eql (first node) tag)
                                (or (null class) (equal class (attribute node :class))))
                       (return node))
                     (push (cddr node) stack))))))))

(defun output (name outputs)
  "The HTML that RENDER-SITE's OUTPUTS hold for the file NAME, or NIL."
  (cdr (assoc name outputs :test #'string=)))

(defun between (start end string)
  "The part of STRING from its first START through the first END after it,
or NIL."
  (let* ((from (search start string))
         (to (and from (search end string :start2 from))))
    (and to (subseq string from (+ to (length end))))))

(defun holdsp (part string)
  "True when STRING holds PART."
  (and (search part string) t))

;;; Heading ids

(define-test heading-id-follows-githubs-rule
  (is string= "markdown-html-procedure" (heading-id "markdown->html (procedure)"))
  (is string= "hardbreaks-and-nobreaks" (heading-id "hardbreaks? and nobreaks?"))
  (is string= "serializing-your-serializer-not-ours"
      (heading-id "Serializing: your serializer, not ours")))

(define-test heading-id-turns-every-space-into-a-hyphen
  (is string= "200---2026-06-07" (heading-id "2.0.0 - 2026-06-07")))

(define-test heading-id-keeps-underscores-and-hyphens
  (is string= "snake_case-and-kebab-case" (heading-id "snake_case and kebab-case!")))

(define-test unique-ids-numbers-repeats-per-id
  (is equal '("changelog" "200---2026-06-07" "added" "fixed"
              "110---2026-05-01" "added-1" "fixed-1"
              "100---2026-04-01" "added-2")
      (unique-ids '("Changelog" "2.0.0 - 2026-06-07" "Added" "Fixed"
                    "1.1.0 - 2026-05-01" "Added" "Fixed"
                    "1.0.0 - 2026-04-01" "Added"))))

(define-test heading-text-joins-text-and-code-literals
  (let ((text (heading-text (first-block (lines "## `markdown->html` and `*max-nodes*`")))))
    (is string= "markdown->html and *max-nodes*" text)
    (is string= "markdown-html-and-max-nodes" (heading-id text))))

(define-test heading-text-reads-through-emphasis-and-links
  (is string= "Strong, emphasis and a link"
      (heading-text (first-block (lines "# **Strong**, *emphasis* and [a link](usage.md)")))))

;;; Link destinations

(defparameter *page-names* '("README.md" "usage.md" "options.md")
  "The pages of the site the link tests rewrite for.")

(defun rewrite (destination)
  "DESTINATION rewritten for a site of *PAGE-NAMES* at the ref v1.2.3: the
new destination and the problem, as a list."
  (multiple-value-list (rewrite-destination destination *page-names* "v1.2.3")))

(defun blob (path)
  "PATH's URL in the repository on GitHub, at the ref v1.2.3."
  (concatenate 'string
               "https://github.com/Kiyomi-Computation-Systems/cl-commonmark-gfm/blob/v1.2.3/"
               path))

(define-test rewrite-destination-sends-a-page-to-its-html
  (is equal '("usage.html" nil) (rewrite "usage.md"))
  (is equal '("usage.html#the-limits" nil) (rewrite "usage.md#the-limits"))
  (is equal '("usage.html" nil) (rewrite "./usage.md"))
  (is equal '("usage.html#x" nil) (rewrite "../docs/usage.md#x")))

(define-test rewrite-destination-sends-the-home-page-to-index
  (is equal '("index.html" nil) (rewrite "README.md"))
  (is equal '("index.html#a-taste" nil) (rewrite "README.md#a-taste")))

(define-test rewrite-destination-keeps-same-page-ids-and-empty-destinations
  (is equal '("#a-table" nil) (rewrite "#a-table"))
  (is equal '("" nil) (rewrite "")))

(define-test rewrite-destination-keeps-urls-with-a-scheme
  (is equal '("https://example.com/x" nil) (rewrite "https://example.com/x"))
  (is equal '("https://example.com/x#y" nil) (rewrite "https://example.com/x#y"))
  (is equal '("https://example.com/notes.md" nil) (rewrite "https://example.com/notes.md"))
  (is equal '("mailto:someone@example.com" nil) (rewrite "mailto:someone@example.com")))

(define-test rewrite-destination-keeps-urls-starting-with-two-slashes
  (is equal '("//example.com/y" nil) (rewrite "//example.com/y"))
  (is equal '("//example.com/y#z" nil) (rewrite "//example.com/y#z")))

(define-test rewrite-destination-sends-other-paths-to-github
  (is equal (list (blob "src/api.lisp") nil) (rewrite "../src/api.lisp"))
  (is equal (list (blob "src/api.lisp#L10") nil) (rewrite "../src/api.lisp#L10"))
  (is equal (list (blob "CHANGELOG.md") nil) (rewrite "../CHANGELOG.md"))
  (is equal (list (blob "CHANGELOG.md#100") nil) (rewrite "../CHANGELOG.md#100"))
  (is equal (list (blob "src/") nil) (rewrite "../src/"))
  (is equal (list (blob "src/api.lisp") nil) (rewrite "/src/api.lisp")))

(define-test rewrite-destination-refuses-a-missing-page
  (is equal '("" "nowhere.md names no page in docs/") (rewrite "nowhere.md"))
  (is equal '("" "nowhere.md#x names no page in docs/") (rewrite "nowhere.md#x")))

(define-test rewrite-destination-refuses-other-paths-inside-docs
  (is equal '("" "logo.png is inside docs/ but isn't a page") (rewrite "logo.png"))
  (is equal '("" "usage.html#x is inside docs/ but isn't a page") (rewrite "usage.html#x"))
  (is equal '("" "../docs/notes/ is inside docs/ but isn't a page") (rewrite "../docs/notes/")))

(define-test rewrite-destination-refuses-a-climb-out-of-the-repository
  (is equal '("" "../../x climbs out of the repository") (rewrite "../../x"))
  (is equal '("" "../../x#y climbs out of the repository") (rewrite "../../x#y")))

;;; The template

(defun sample-document (&key (prev '("usage.md" . "Usage")) (next '("ast.md" . "The AST")))
  "PAGE-DOCUMENT's tree for options.md, between PREV and NEXT, at the ref
v1.2.3."
  (page-document :nav '(("usage.md" . "Usage") ("options.md" . "Options") ("ast.md" . "The AST"))
                 :current "options.md"
                 :title "Options"
                 :body (list '(:h1 ((:id "options")) "Options") (newline)
                             '(:p nil "Some text.") (newline))
                 :toc '(("the-limits" . "The limits") ("profiles" . "Profiles"))
                 :prev prev
                 :next next
                 :ref "v1.2.3"))

(define-test page-document-is-html-with-a-head-and-a-body
  (let* ((document (sample-document))
         (tags (cons (first document) (mapcar #'first (child-elements document)))))
    (is equal '(:html :head :body) tags)))

(define-test page-document-head
  (let ((head (find-element :head nil (sample-document))))
    (is equal '(:head nil
                (:meta ((:charset "utf-8")))
                (:meta ((:name "viewport") (:content "width=device-width, initial-scale=1")))
                (:title nil "Options")
                (:link ((:rel "stylesheet") (:href "style.css"))))
        head)))

(define-test page-document-top-bar-holds-the-theme-toggle
  (let ((top-bar (first (child-elements (find-element :body nil (sample-document))))))
    (is equal '(:div ((:class "topbar"))
                (:button ((:id "theme") (:class "toggle") (:aria-label "Toggle theme"))
                 (:span ((:class "knob") (:aria-hidden "true")))
                 (:span ((:id "theme-label")) "Dark mode")))
        top-bar)))

(define-test page-document-body-ends-with-theme-js
  (let ((body (child-elements (find-element :body nil (sample-document)))))
    (is equal '(:div :div :script) (mapcar #'first body))
    (is equal '(:script ((:src "theme.js"))) (first (last body)))))

(define-test page-document-layout-is-side-main-and-toc
  (let ((layout (find-element :div "layout" (sample-document))))
    (is equal '((:aside "side") (:main "main") (:aside "toc"))
        (mapcar (lambda (element) (list (first element) (attribute element :class)))
                (child-elements layout)))))

(define-test page-document-side-marks-the-current-page
  (let ((side (find-element :aside "side" (sample-document))))
    (is equal '((:a ((:class "mark") (:href "index.html")) "cl-commonmark-gfm")
                (:nav nil
                 (:a ((:href "usage.html")) "Usage")
                 (:a ((:href "options.html") (:class "on") (:aria-current "page")) "Options")
                 (:a ((:href "ast.html")) "The AST")))
        (cddr side))))

(define-test page-document-column-holds-the-body-then-pagenav-then-closing-line
  (let ((column (cddr (find-element :div "col" (sample-document)))))
    (is equal (list '(:h1 ((:id "options")) "Options") (newline) '(:p nil "Some text.") (newline))
        (subseq column 0 (min 4 (length column))))
    (is equal `(:div ((:class "pagenav"))
                (:a ((:href "usage.html"))
                 (:span ((:class "lbl")) "Previous")
                 ,(format nil "~C Usage" (code-char #x2190)))
                (:a ((:href "ast.html") (:class "next"))
                 (:span ((:class "lbl")) "Next")
                 ,(format nil "The AST ~C" (code-char #x2192))))
        (fifth column))
    (is equal '(:p nil "Rendered from Markdown by cl-commonmark-gfm, v1.2.3") (sixth column))
    (is = 6 (length column))))

(define-test page-document-pagenav-keeps-an-empty-side
  (let ((first-page (find-element :div "pagenav" (sample-document :prev nil)))
        (last-page (find-element :div "pagenav" (sample-document :next nil))))
    (is equal '(:span nil) (third first-page))
    (is equal '(:span nil) (fourth last-page))))

(define-test page-document-without-neighbours-has-no-pagenav
  (let ((column (cddr (find-element :div "col" (sample-document :prev nil :next nil)))))
    (is equal '(:p nil "Rendered from Markdown by cl-commonmark-gfm, v1.2.3") (car (last column)))
    (is = 5 (length column))))

(define-test page-document-toc-lists-on-this-page
  (let ((toc (find-element :aside "toc" (sample-document))))
    (is equal '(:aside ((:class "toc"))
                (:div ((:class "lbl")) "On this page")
                (:a ((:href "#the-limits")) "The limits")
                (:a ((:href "#profiles")) "Profiles"))
        toc)))

(define-test page-document-serializes-its-void-elements-as-void
  (let* ((html (html-tree->string (sample-document)))
         (meta (holdsp (concatenate 'string
                                     "<head><meta charset=\"utf-8\" />"
                                     "<meta name=\"viewport\""
                                     " content=\"width=device-width, initial-scale=1\" />")
                        html))
         (link (holdsp "<link rel=\"stylesheet\" href=\"style.css\" /></head>" html))
         (script (holdsp "<script src=\"theme.js\"></script></body></html>" html)))
    (true meta "the head opens with the two void meta elements")
    (true link "the stylesheet's link is void")
    (true script "theme.js's script closes the body")))

;;; RENDER-SITE

(defun small-site ()
  "Three pages for RENDER-SITE, with no problems: the home page, then
usage.md and options.md."
  (list (cons "README.md"
              (lines "# Home"
                     ""
                     "Read [the usage](usage.md) and [the limits](options.md#the-limits)."
                     ""
                     "## A taste"))
        (cons "usage.md"
              (lines "# Usage"
                     ""
                     "## A table"
                     ""
                     "## A table"
                     ""
                     "## `markdown->html` and `*max-nodes*`"
                     ""
                     "### Deeper"
                     ""
                     "See [the second table](#a-table-1), [home](README.md#a-taste)"
                     "and [the source](../src/api.lisp)."))
        (cons "options.md"
              (lines "# Options"
                     ""
                     "## The limits"
                     ""
                     (format nil "> ~C~C With the selector." (code-char #x26A0) (code-char #xFE0F))
                     ""
                     "> A plain quote."
                     ""
                     (format nil "> ~C Without it." (code-char #x26A0))))))

(define-test render-site-names-its-outputs-and-the-ids
  (multiple-value-bind (outputs ids problems) (render-site (small-site) "v1.2.3")
    (let ((names (mapcar #'car outputs)))
      (is equal '(("index.html" "usage.html" "options.html") ()) (list names problems))
      (is equal '(("README.md" "home" "a-taste")
                  ("usage.md" "usage" "a-table" "a-table-1" "markdown-html-and-max-nodes" "deeper")
                  ("options.md" "options" "the-limits"))
          ids))))

(define-test render-site-puts-the-ids-on-the-headings
  (let* ((usage (output "usage.html" (render-site (small-site) "v1.2.3")))
         (headings (list (holdsp "<h1 id=\"usage\">Usage</h1>" usage)
                         (holdsp "<h2 id=\"a-table\">A table</h2>" usage)
                         (holdsp "<h2 id=\"a-table-1\">A table</h2>" usage)
                         (holdsp (concatenate 'string
                                               "<h2 id=\"markdown-html-and-max-nodes\">"
                                               "<code>markdown-&gt;html</code> and "
                                               "<code>*max-nodes*</code></h2>")
                                  usage)
                         (holdsp "<h3 id=\"deeper\">Deeper</h3>" usage))))
    (is equal '(t t t t t) headings)))

(define-test render-site-lists-level-2-headings-on-this-page
  (let* ((outputs (render-site (small-site) "v1.2.3"))
         (home (between "<aside class=\"toc\">" "</aside>" (output "index.html" outputs)))
         (usage (between "<aside class=\"toc\">" "</aside>" (output "usage.html" outputs))))
    (is string= (concatenate 'string
                             "<aside class=\"toc\"><div class=\"lbl\">On this page</div>"
                             "<a href=\"#a-taste\">A taste</a></aside>")
        home)
    (is string= (concatenate 'string
                             "<aside class=\"toc\"><div class=\"lbl\">On this page</div>"
                             "<a href=\"#a-table\">A table</a>"
                             "<a href=\"#a-table-1\">A table</a>"
                             "<a href=\"#markdown-html-and-max-nodes\">"
                             "markdown-&gt;html and *max-nodes*</a></aside>")
        usage)))

(define-test render-site-wraps-warning-blockquotes-as-callouts
  (let* ((options (output "options.html" (render-site (small-site) "v1.2.3")))
         (callouts (list (holdsp (format nil "<div class=\"callout warning\"><blockquote>~%~
                                               <p>~C~C With the selector.</p>~%</blockquote></div>"
                                          (code-char #x26A0) (code-char #xFE0F))
                                  options)
                         (holdsp (format nil "<div class=\"callout warning\"><blockquote>~%~
                                               <p>~C Without it.</p>~%</blockquote></div>"
                                          (code-char #x26A0))
                                  options)))
         (plain (holdsp (format nil "~%<blockquote>~%<p>A plain quote.</p>~%</blockquote>~%")
                         options)))
    (is equal '(t t) callouts)
    (true plain "a blockquote not led by the warning sign isn't wrapped")))

(define-test render-site-fills-the-template
  (let* ((outputs (render-site (small-site) "v1.2.3"))
         (pages (mapcar (lambda (name) (output name outputs))
                        '("index.html" "usage.html" "options.html")))
         (titles (mapcar (lambda (html) (between "<title>" "</title>" html)) pages))
         (navs (mapcar (lambda (html) (between "<nav>" "</nav>" html)) pages))
         (pagenavs (mapcar (lambda (html) (between "<div class=\"pagenav\">" "</div>" html))
                           pages)))
    (is equal '("<title>cl-commonmark-gfm</title>" "<title>Usage</title>" "<title>Options</title>")
        titles)
    (is equal (list (concatenate 'string
                                 "<nav><a href=\"usage.html\">Usage</a>"
                                 "<a href=\"options.html\">Options</a></nav>")
                    (concatenate 'string
                                 "<nav><a href=\"usage.html\" class=\"on\" aria-current=\"page\">"
                                 "Usage</a><a href=\"options.html\">Options</a></nav>")
                    (concatenate 'string
                                 "<nav><a href=\"usage.html\">Usage</a>"
                                 "<a href=\"options.html\" class=\"on\" aria-current=\"page\">"
                                 "Options</a></nav>"))
        navs)
    (is equal (list nil
                    (format nil "<div class=\"pagenav\"><span></span>~
                                 <a href=\"options.html\" class=\"next\">~
                                 <span class=\"lbl\">Next</span>Options ~C</a></div>"
                            (code-char #x2192))
                    (format nil "<div class=\"pagenav\"><a href=\"usage.html\">~
                                 <span class=\"lbl\">Previous</span>~C Usage</a>~
                                 <span></span></div>"
                            (code-char #x2190)))
        pagenavs)))

(define-test render-site-rewrites-links-and-names-the-ref
  (let* ((outputs (render-site (small-site) "v1.2.3"))
         (home (output "index.html" outputs))
         (usage (output "usage.html" outputs))
         (found (list (holdsp "<a href=\"usage.html\">the usage</a>" home)
                      (holdsp "<a href=\"options.html#the-limits\">the limits</a>" home)
                      (holdsp "<a href=\"#a-table-1\">the second table</a>" usage)
                      (holdsp "<a href=\"index.html#a-taste\">home</a>" usage)
                      (holdsp (format nil "<a href=\"~A\">the source</a>" (blob "src/api.lisp"))
                               usage)
                      (holdsp "<p>Rendered from Markdown by cl-commonmark-gfm, v1.2.3</p>" usage)))
         (start (subseq home 0 (min 12 (length home)))))
    (is equal '(t t t t t t) found)
    (is string= "<html><head>" start)))

;;; The problems RENDER-SITE reports

(defun site-problems (&rest pages)
  "The problems RENDER-SITE reports for PAGES, each a (NAME . MARKDOWN)."
  (nth-value 2 (render-site pages "main")))

(define-test render-site-reports-missing-anchors
  (is equal '("README.md: link usage.md#nowhere names no id on usage.md"
              "README.md: link #nowhere names no id on README.md")
      (site-problems
       (cons "README.md"
             (lines "# Home"
                    ""
                    "[a](usage.md#nowhere), [b](#nowhere), [c](usage.md), [d](usage.md#usage)"
                    "and [e](#home)."))
       (cons "usage.md" (lines "# Usage")))))

(define-test render-site-reports-links-the-rewrite-refuses
  (is equal '("README.md: link nowhere.md#x names no page in docs/"
              "README.md: link ../../logo.png climbs out of the repository"
              "README.md: link usage.html is inside docs/ but isn't a page")
      (site-problems
       (cons "README.md"
             (lines "# Home" "" "[a](nowhere.md#x), [b](../../logo.png) and [c](usage.html).")))))

(define-test render-site-reports-images-with-relative-paths
  (is equal '("README.md: image pic.png has a relative path, which the site can't show"
              "README.md: image ../logo.png has a relative path, which the site can't show"
              "README.md: image /docs/pic.png has a relative path, which the site can't show"
              "README.md: image usage.md has a relative path, which the site can't show")
      (site-problems
       (cons "README.md"
             (lines "# Home" ""
                    "![a](pic.png) ![b](../logo.png) ![c](/docs/pic.png) ![d](usage.md)"
                    "![e](https://example.com/pic.png) ![f](//example.com/pic.png)"))
       (cons "usage.md" (lines "# Usage")))))

(define-test render-site-takes-a-bare-hash-to-the-top-of-a-page
  (multiple-value-bind (outputs ids problems)
      (render-site (list (cons "README.md" (lines "# Home" "" "[top](#) and [usage](usage.md#)."))
                         (cons "usage.md" (lines "# Usage")))
                   "main")
    (declare (ignore ids))
    (let ((names (mapcar #'car outputs)))
      (is equal '(("index.html" "usage.html") ()) (list names problems)))))

(define-test render-site-decodes-a-fragment-before-looking-its-id-up
  (is equal '("README.md: heading Café holds non-ASCII text, whose GitHub id isn't known"
              "README.md: link #a%2Dc names no id on README.md")
      (site-problems
       (cons "README.md"
             (lines "# Home" "" "## A-b" "" "## Café" ""
                    "[a](#a%2Db), [b](#caf%C3%A9), [c](#a%2Dc) and [d](usage.md#a%2db)."))
       (cons "usage.md" (lines "# Usage" "" "## A-b")))))

(define-test percent-decode-reads-escapes-as-utf-8
  (is equal (list "café" "café" "a-b" (string (code-char #x26A0))
                  "100%" "%zz" (string (code-char #xFFFD)) (format nil "~Cx" (code-char #xFFFD)))
      (mapcar #'cl-commonmark-gfm.site::percent-decode
              '("caf%C3%A9" "caf%c3%a9" "a%2Db" "%E2%9A%A0" "100%" "%zz" "%FF" "%C3x"))))

(defun replacements (count)
  "COUNT replacement characters, U+FFFD, as a string."
  (make-string count :initial-element (code-char #xFFFD)))

(define-test percent-decode-refuses-malformed-utf-8
  (is string= (replacements 3) (cl-commonmark-gfm.site::percent-decode "%E0%81%A1")
      "an overlong a")
  (is string= (replacements 3) (cl-commonmark-gfm.site::percent-decode "%ED%A0%80")
      "a surrogate, U+D800")
  (is string= (replacements 4) (cl-commonmark-gfm.site::percent-decode "%F4%90%80%80")
      "a code point past U+10FFFF")
  (is string= (format nil "~CA" (code-char #xFFFD))
      (cl-commonmark-gfm.site::percent-decode "%C3%41")
      "a lead octet that the next doesn't continue")
  (is string= (replacements 2) (cl-commonmark-gfm.site::percent-decode "%E2%9A")
      "a truncated sequence, one replacement per octet"))

(define-test render-site-refuses-a-fragment-only-an-overlong-form-would-name
  (is equal '("README.md: link #%E0%81%A1 names no id on README.md")
      (site-problems (cons "README.md" (lines "# Home" "" "## A" "" "[a](#%E0%81%A1).")))))

(define-test render-site-refuses-headings-whose-github-id-isnt-known
  (is equal '("README.md: heading Café holds non-ASCII text, whose GitHub id isn't known"
              "README.md: heading logo Logo holds an image, whose GitHub id isn't known"
              "README.md: heading Note holds a footnote reference, whose GitHub id isn't known")
      (site-problems
       (cons "README.md"
             (lines "# Home" "" "## Café" "" "## ![logo](https://example.com/logo.png) Logo" ""
                    "## Note[^1]" "" "[^1]: A note.")))))

(define-test render-site-refuses-headings-with-empty-ids
  (is equal '("README.md: heading !!! gives an empty id"
              "README.md: heading ??? gives an empty id")
      (site-problems (cons "README.md" (lines "# Home" "" "## !!!" "" "## ???")))))

(define-test render-site-wraps-a-warning-quote-inside-another-once
  (let* ((home (output "index.html"
                       (render-site (list (cons "README.md"
                                                (lines "# Home" ""
                                                       (format nil "> > ~C Inner."
                                                               (code-char #x26A0)))))
                                    "main")))
         (callout (between "<div class=\"callout warning\">" "</div>" home)))
    (is string= (format nil "<div class=\"callout warning\"><blockquote>~%<blockquote>~%~
                             <p>~C Inner.</p>~%</blockquote>~%</blockquote></div>"
                        (code-char #x26A0))
        callout)))

(defun call-with-rewrite-keeping-destinations (thunk)
  "Call THUNK while REWRITE-DESTINATION keeps every destination as it is
written, as a broken rewrite would, and restore the real one however THUNK
exits. A correct rewrite leaves no link for the stale-link scan to find, so
only a broken one shows that RENDER-SITE runs the scan on every page."
  (let ((original (fdefinition 'rewrite-destination)))
    (unwind-protect
         (progn
           (setf (fdefinition 'rewrite-destination)
                 (lambda (destination page-names ref)
                   (declare (ignore page-names ref))
                   (values destination nil)))
           (funcall thunk))
      (setf (fdefinition 'rewrite-destination) original))))

(define-test render-site-scans-each-page-for-links-the-rewrite-missed
  (is equal '("README.md: href usage.md still ends in .md"
              "README.md: href ../src/api.lisp still starts with ../")
      (call-with-rewrite-keeping-destinations
       (lambda ()
         (site-problems
          (cons "README.md" (lines "# Home" "" "[a](usage.md) and [b](../src/api.lisp)."))
          (cons "usage.md" (lines "# Usage")))))))

(define-test render-site-lists-the-repository-paths-its-links-name
  (is equal '(("README.md" . "src/api.lisp")
              ("README.md" . "CHANGELOG.md")
              ("README.md" . "src/")
              ("README.md" . "my notes.txt")
              ("usage.md" . "LICENSE"))
      (nth-value 4 (render-site
                    (list (cons "README.md"
                                (lines "# Home" ""
                                       "[a](../src/api.lisp#L10), [b](/CHANGELOG.md),"
                                       "[c](usage.md), [d](https://example.com/x), [e](../src/),"
                                       "[f](../my%20notes.txt?plain=1) and ![g](../logo.png)."))
                          (cons "usage.md"
                                (lines "# Usage" "" "[h](../LICENSE#top) and [i](nowhere.md).")))
                    "main"))))

(defun parse-report (markdown)
  "The report of the error PARSE signals for MARKDOWN, as PRINC writes it."
  (princ-to-string (nth-value 1 (ignore-errors (parse markdown)))))

(define-test render-site-reports-a-page-the-library-cant-parse
  (let ((guard (lines "# Guard" "" "Its pattern, `[&#94;`, can't be shown in one code span.")))
    (multiple-value-bind (outputs ids problems)
        (render-site (list (cons "README.md"
                                 (lines "# Home" "" "[a](guard.md) and [b](guard.md#guard)."))
                           (cons "guard.md" guard)
                           (cons "usage.md" (lines "# Usage")))
                     "main")
      (let ((names (mapcar #'car outputs)))
        (is equal '("index.html" "usage.html") names)
        (is equal '(("README.md" "home") ("guard.md") ("usage.md" "usage")) ids)
        (is equal (list "README.md: link guard.md#guard names no id on guard.md"
                        (format nil "guard.md: can't be parsed: unsupported-input: ~A; write ~
                                     its & as &amp; outside code; as code, split it into two ~
                                     code spans with a word between; in a Lisp example, build ~
                                     the string from two pieces, as (concatenate 'string \"[\" ~
                                     \"&#94;\")"
                                (parse-report guard)))
            problems)))))

(define-test render-site-sends-the-generated-reference-back-to-its-docstrings
  (let ((reference (lines "# API reference" "" "A docstring quoting `[&#94;`.")))
    (is equal (list (format nil "reference.md: can't be parsed: unsupported-input: ~A; the page ~
                                 is generated: fix the docstring that make check-reference ~
                                 names, then run make reference"
                            (parse-report reference)))
        (site-problems (cons "README.md" (lines "# Home")) (cons "reference.md" reference)))))

(define-test render-site-reports-raw-html
  (is equal '("README.md: raw HTML <b>"
              "README.md: raw HTML </b>"
              "README.md: raw HTML <div class=\"note\">")
      (site-problems
       (cons "README.md"
             (lines "# Home" "" "Some <b>bold</b> text." "" "<div class=\"note\">" "A block."
                    "</div>")))))

(define-test render-site-reports-pages-not-starting-with-one-level-1-heading
  (is equal '("usage.md: starts with ## Usage, not a # heading"
              "usage.md: # Again: only the first block may be a # heading"
              "options.md: doesn't start with a # heading"
              "options.md: # Options: only the first block may be a # heading"
              "ast.md: # Quoted: only the first block may be a # heading"
              "empty.md: doesn't start with a # heading")
      (site-problems (cons "README.md" (lines "# Home"))
                     (cons "usage.md" (lines "## Usage" "" "# Again"))
                     (cons "options.md" (lines "Text first." "" "# Options"))
                     (cons "ast.md" (lines "# The AST" "" "> # Quoted"))
                     (cons "empty.md" ""))))

(define-test render-site-reports-headings-sharing-an-id
  (is equal '("README.md: two headings have the id a-1"
              "README.md: two headings have the id b-1"
              "usage.md: two headings have the id step-1")
      (site-problems
       (cons "README.md"
             (lines "# Home" "" "## A" "" "## A 1" "" "## A" "" "## Added" "" "## Added" ""
                    "## B" "" "## B 1" "" "## B"))
       (cons "usage.md" (lines "# Usage" "" "## Step 1" "" "## Step" "" "## Step")))))

(define-test render-site-counts-the-links-and-images-it-checks
  (is = 5 (nth-value 3 (render-site
                        (list (cons "README.md"
                                    (lines "# Home" "" "[a](usage.md) and ![b](logo.png)."))
                              (cons "usage.md"
                                    (lines "# Usage" "" "[![c](logo.png)](README.md)" ""
                                           "## [d](#usage)"))
                              (cons "options.md" (lines "# Options")))
                        "main"))))

(define-test stale-links-are-found-in-a-hand-built-tree
  (is equal '("usage.md: href options.md#x still ends in .md"
              "usage.md: src ../logo.png still starts with ../"
              "usage.md: href ../CHANGELOG.md still ends in .md")
      (cl-commonmark-gfm.site::stale-link-problems
       "usage.md"
       '(:html nil
         (:head nil
          (:link ((:rel "stylesheet") (:href "style.css"))))
         (:body nil
          (:a ((:href "options.md#x")) "a")
          (:p nil (:img ((:src "../logo.png") (:alt "logo"))))
          (:a ((:href "../CHANGELOG.md")) "b")
          (:a ((:href "index.html")) "c")
          (:a ((:href "#id")) "d")
          (:a ((:href "https://github.com/o/r/blob/main/CHANGELOG.md")) "e")
          (:a ((:href "//example.com/notes.md")) "f")
          (:a ((:href "")) "g")
          (:script ((:src "theme.js"))))))))

(define-test decorate-body-refuses-ids-that-dont-match-the-headings
  (fail (cl-commonmark-gfm.site::decorate-body (list '(:h1 nil "A") (newline) '(:h2 nil "B"))
                                               '("a"))
        'simple-error)
  (fail (cl-commonmark-gfm.site::decorate-body (list '(:h1 nil "A")) '("a" "b"))
        'simple-error))

;;; The library's public API

(defun library-packages ()
  "The library's packages in this image: each whose name starts with
CL-COMMONMARK-GFM's, other than CL-COMMONMARK-GFM.SITE and the packages
named below it, which are the site's own."
  (let ((library (package-name (find-package '#:cl-commonmark-gfm)))
        (site (package-name (find-package '#:cl-commonmark-gfm.site))))
    (remove-if-not (lambda (package)
                     (let ((name (package-name package)))
                       (and (cl-commonmark-gfm.site::string-prefix-p library name)
                            (not (string= site name))
                            (not (cl-commonmark-gfm.site::string-prefix-p
                                  (concatenate 'string site ".") name)))))
                   (list-all-packages))))

(defun library-symbols-in-site ()
  "The symbols accessible in CL-COMMONMARK-GFM.SITE whose home is one of
LIBRARY-PACKAGES, each once."
  (let ((packages (library-packages))
        (symbols '()))
    (do-symbols (symbol '#:cl-commonmark-gfm.site)
      (when (member (symbol-package symbol) packages)
        (pushnew symbol symbols)))
    symbols))

(defun publicp (symbol)
  "True when SYMBOL is external in CL-COMMONMARK-GFM, the library's public
package."
  (multiple-value-bind (found status) (find-symbol (symbol-name symbol) '#:cl-commonmark-gfm)
    (and (eql found symbol) (eql status :external))))

(define-test the-site-reaches-the-library-through-its-exports-alone
  (let* ((packages (mapcar #'package-name (library-packages)))
         (symbols (library-symbols-in-site))
         (seen (list (and (member "CL-COMMONMARK-GFM" packages :test #'string=) t)
                     (and (member "CL-COMMONMARK-GFM.NATIVE" packages :test #'string=) t)
                     (and (member 'parse symbols) t)))
         (internal (sort (mapcar #'symbol-name (remove-if #'publicp symbols)) #'string<)))
    (is equal '(t t t) seen
        "the library's packages, the internal NATIVE among them, and the site's import PARSE")
    (is equal '() internal
        "the library's symbols the site can reach that CL-COMMONMARK-GFM doesn't export")))

;;; The library's public API, in the site's source
;;;
;;; A reference written PACKAGE::NAME, or PACKAGE:NAME for one of the
;;; library's packages other than CL-COMMONMARK-GFM, interns nothing in the
;;; site's package, so the test above can't see it: these read the site's
;;; source instead.

(defun code-only (text)
  "TEXT, Lisp source, with its comments, strings and |names| blanked to
spaces, its newlines kept, so the code left stands where it was. The
character after a backslash is skipped, as the reader skips it, so one
written #\\; or #\\\" opens no comment or string."
  (let ((code (copy-seq text))
        (index 0))
    (flet ((blank (end)
             (loop for position from index below end
                   unless (char= (char code position) #\Newline)
                     do (setf (char code position) #\Space))
             (setf index end)))
      (loop while (< index (length text))
            do (let ((char (char text index)))
                 (cond ((or (char= char #\") (char= char #\|))
                        (blank (cl-commonmark-gfm.site::delimited-end text index)))
                       ((char= char #\\)
                        (incf index 2))
                       ((cl-commonmark-gfm.site::text-at-p "#|" text index)
                        (blank (cl-commonmark-gfm.site::block-comment-end text index)))
                       ((char= char #\;)
                        (blank (or (position #\Newline text :start index) (length text))))
                       (t
                        (incf index))))))
    code))

(defun name-character-p (char)
  "True when CHAR can be part of a package's or a symbol's name as the
site's source writes them: not whitespace, and no character that ends or
opens a token."
  (not (or (member char '(#\Space #\Tab #\Newline #\Return #\Page))
           (find char "()'`,\"#;|" :test #'char=))))

(defun library-package-name-p (name)
  "True when NAME, a package's name as source writes it, names one of the
library's packages: it starts with cl-commonmark-gfm, in any case, and
isn't the site's own, cl-commonmark-gfm.site or a package named below it."
  (and (cl-commonmark-gfm.site::string-prefix-equal-p "cl-commonmark-gfm" name)
       (not (string-equal "cl-commonmark-gfm.site" name))
       (not (cl-commonmark-gfm.site::string-prefix-equal-p "cl-commonmark-gfm.site." name))))

(defun code-tokens (code)
  "The tokens of CODE, Lisp source with its comments and strings blanked:
each run of characters NAME-CHARACTER-P accepts, in order."
  (let ((tokens '())
        (start nil))
    (loop for index from 0 to (length code)
          do (if (and (< index (length code)) (name-character-p (char code index)))
                 (unless start
                   (setf start index))
                 (when start
                   (push (subseq code start index) tokens)
                   (setf start nil))))
    (nreverse tokens)))

(defun library-reference-p (token)
  "True when TOKEN, from the site's code, names a symbol of one of the
library's packages other than as CL-COMMONMARK-GFM exports it: with ::,
or with one colon after a package other than CL-COMMONMARK-GFM itself. A
symbol named CL-COMMONMARK-GFM:NAME is one of its exports, since the
reader refuses that for any other. A token that starts with its colon, a
keyword or #:NAME, names no package."
  (let ((colon (position #\: token)))
    (and colon
         (plusp colon)
         (let ((package (subseq token 0 colon))
               (two-colons (and (< (1+ colon) (length token))
                                (char= (char token (1+ colon)) #\:))))
           (and (library-package-name-p package)
                (or two-colons
                    (not (string-equal package "cl-commonmark-gfm"))))))))

(defun library-references (text)
  "Each reference in the code of TEXT, Lisp source, that LIBRARY-REFERENCE-P
refuses, as written, in order."
  (remove-if-not #'library-reference-p (code-tokens (code-only text))))

(defun site-source-references ()
  "The site's Lisp files, site/*.lisp, found through ASDF and read, as two
values: their names, and each LIBRARY-REFERENCES reference in them, as
FILE: REFERENCE."
  (let ((files (sort (directory (merge-pathnames
                                 "*.lisp" (asdf:system-source-directory "cl-commonmark-gfm-site")))
                     #'string< :key #'namestring)))
    (values (mapcar #'file-namestring files)
            (loop for file in files
                  append (mapcar (lambda (reference)
                                   (format nil "~A: ~A" (file-namestring file) reference))
                                 (library-references
                                  (uiop:read-file-string file :external-format :utf-8)))))))

(define-test library-references-skip-comments-strings-and-names
  (is equal '("cl-commonmark-gfm.ast::%node-kind"
              "CL-COMMONMARK-GFM::CHECK-INPUT"
              "cl-commonmark-gfm.native::render-html"
              "cl-commonmark-gfm.native:render-html")
      (library-references
       (lines "; cl-commonmark-gfm::in-a-comment"
              "#| cl-commonmark-gfm::in-a-block #| cl-commonmark-gfm::nested |# |#"
              "(defun f (x)"
              "  \"cl-commonmark-gfm::in-a-docstring\""
              "  (list #\\; #\\\" #\\| (cl-commonmark-gfm.ast::%node-kind x)"
              "        '|cl-commonmark-gfm::in-a-name|"
              "        (CL-COMMONMARK-GFM::CHECK-INPUT x nil 'parse)"
              "        #'cl-commonmark-gfm.native::render-html"
              "        #'cl-commonmark-gfm.native:render-html"
              "        'cl-commonmark-gfm.site::own 'cl-commonmark-gfm.site.tests::own"
              "        'cl-commonmark-gfm.site:x :keyword '#:cl-commonmark-gfm.native"
              "        'cl-commonmark-gfm:parse))"))))

(define-test the-site-source-names-no-library-internals
  (multiple-value-bind (files references) (site-source-references)
    (true (subsetp '("ids.lisp" "links.lisp" "render.lisp" "build.lisp") files
                   :test #'string=)
          "the scan reads the site's source, ~{~A~^, ~}" files)
    (is equal '() references
        "the library's symbols the site's source names other than as its exports")))
