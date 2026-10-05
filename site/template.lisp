;;;; The page template: a whole page as an HTML tree. Its structure and
;;;; class names are the ones site/style.css styles, so neither changes
;;;; without the other.

(in-package #:cl-commonmark-gfm.site)

(defparameter *project-name* "cl-commonmark-gfm"
  "The project's name: above the sidebar, as the link home, and the home
page's title.")

(defun nav-link (entry current)
  "The sidebar's link to ENTRY, a (NAME . LABEL) page, marked as the current
page when NAME is CURRENT."
  (destructuring-bind (name . label) entry
    (if (string= name current)
        `(:a ((:href ,(page-html-name name)) (:class "on") (:aria-current "page")) ,label)
        `(:a ((:href ,(page-html-name name))) ,label))))

(defun toc-link (entry)
  "The \"On this page\" link to ENTRY, an (ID . TEXT) heading."
  (destructuring-bind (id . text) entry
    `(:a ((:href ,(concatenate 'string "#" id))) ,text)))

(defun page-nav (previous next)
  "The links to the PREVIOUS and NEXT pages, each a (NAME . LABEL) page or
NIL, as a list to splice: one div, or nothing when both are NIL. The div
spreads its two children to its edges, so a missing side is an empty span,
which keeps the other link at its own edge."
  (when (or previous next)
    (list `(:div ((:class "pagenav"))
            ,(if previous
                 `(:a ((:href ,(page-html-name (car previous))))
                   (:span ((:class "lbl")) "Previous")
                   ,(format nil "~C ~A" (code-char #x2190) (cdr previous)))
                 '(:span nil))
            ,(if next
                 `(:a ((:href ,(page-html-name (car next))) (:class "next"))
                   (:span ((:class "lbl")) "Next")
                   ,(format nil "~A ~C" (cdr next) (code-char #x2192)))
                 '(:span nil))))))

(defun closing-line (ref)
  "The line that closes a page's column, naming the REF it was rendered
from."
  `(:p nil ,(format nil "Rendered from Markdown by ~A, ~A" *project-name* ref)))

(defun page-document (&key nav current title body toc prev next ref)
  "A whole page, as an HTML tree for HTML-TREE->STRING: its html element.
- NAV: the sidebar's pages, each (NAME . LABEL), NAME a docs/ file name.
- CURRENT: this page's file name. Its sidebar link is marked.
- TITLE: the page's title.
- BODY: the page's content, a list of HTML tree nodes.
- TOC: the \"On this page\" links, each (ID . TEXT).
- PREV and NEXT: the pages before and after this one, each (NAME . LABEL),
  or NIL.
- REF: the git ref the page is rendered from, named on its closing line.
The script theme.js is the body's last element: it looks up the theme
toggle as it runs, so the toggle must come before it."
  `(:html nil
    (:head nil
     (:meta ((:charset "utf-8")))
     (:meta ((:name "viewport") (:content "width=device-width, initial-scale=1")))
     (:title nil ,title)
     (:link ((:rel "stylesheet") (:href "style.css"))))
    (:body nil
     (:div ((:class "topbar"))
      (:button ((:id "theme") (:class "toggle") (:aria-label "Toggle theme"))
       (:span ((:class "knob") (:aria-hidden "true")))
       (:span ((:id "theme-label")) "Dark mode")))
     (:div ((:class "layout"))
      (:aside ((:class "side"))
       (:a ((:class "mark") (:href "index.html")) ,*project-name*)
       (:nav nil ,@(mapcar (lambda (entry) (nav-link entry current)) nav)))
      (:main ((:class "main"))
       (:div ((:class "col")) ,@body ,@(page-nav prev next) ,(closing-line ref)))
      (:aside ((:class "toc"))
       (:div ((:class "lbl")) "On this page")
       ,@(mapcar #'toc-link toc)))
     (:script ((:src "theme.js"))))))
