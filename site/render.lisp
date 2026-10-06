;;;; Rendering the site, in two passes over its pages. The first parses
;;;; every page and gives its headings their ids. The second rewrites each
;;;; page's links, checks them against every page's ids, and builds the
;;;; page from the template. RENDER-SITE reads and writes no file: the
;;;; pages' Markdown comes in, and their HTML, the problems found, the
;;;; number of links checked and the repository paths the links name go
;;;; out.

(in-package #:cl-commonmark-gfm.site)

;;; The first pass: each page parsed, and its headings' ids

(defstruct (page (:constructor make-page (name ast headings texts ids &optional problem)))
  "One page after the first pass. NAME is its docs/ file name and AST its
parse. HEADINGS are its :HEADING nodes, in document order; TEXTS their
HEADING-TEXTs and IDS their ids, in the same order. PROBLEM is NIL, or,
for a page the library refused to parse, the problem that says so, and
the page then has no AST, headings or ids."
  name
  ast
  headings
  texts
  ids
  problem)

(defun find-headings (ast)
  "AST's :HEADING nodes, in document order."
  (reverse (fold-ast (lambda (node headings)
                       (if (eql (node-kind node) :heading)
                           (cons node headings)
                           headings))
                     '()
                     ast)))

(defparameter *unsupported-input-fix*
  (concatenate 'string
               "write its & as &amp; outside code; as code, split it into two code "
               "spans with a word between; in a Lisp example, build the string from "
               "two pieces, as (concatenate 'string \"[\" \"&#94;\")")
  "How to write a page that the footnote guard refuses, so it parses. PARSE
refuses a [ followed by an entity that decodes to ^ anywhere, a code block
included. Outside code, &amp; shows the & as written; inside a code span
the pattern is split into two code spans, with a word between them; inside
a Lisp example, the two pieces are written as separate strings and joined
at run time, so the example's own source never holds the pattern whole.")

(defparameter *generated-page-fix*
  (concatenate 'string "the page is generated: fix the docstring that make check-reference "
               "names, then run make reference")
  "How to change the API reference when the footnote guard refuses it. Make
reference writes the page from the library's docstrings, so the pattern
comes from one of them, which make check-reference names: an edit to the
page itself would be lost when it is written again.")

(defun reference-page-p (name)
  "True when NAME is the API reference's, *REFERENCE-PAGE*."
  (string= name *reference-page*))

(defun parse-problem (name condition)
  "The problem with the page NAME when the library refused to parse it,
signalling CONDITION: the condition's type and report, then, for
UNSUPPORTED-INPUT, how to change the page so it parses: through its
docstrings for the generated API reference, otherwise the page itself."
  (format nil "~A: can't be parsed: ~A: ~A~@[; ~A~]"
          name
          (string-downcase (symbol-name (type-of condition)))
          condition
          (and (typep condition 'unsupported-input)
               (if (reference-page-p name) *generated-page-fix* *unsupported-input-fix*))))

(defun parse-page (name markdown)
  "MARKDOWN, the text of the page NAME, parsed as GFM; or NIL and, as a
second value, PARSE-PROBLEM's problem when the library signals one of its
errors."
  (handler-case (values (parse markdown) nil)
    (commonmark-gfm-error (condition)
      (values nil (parse-problem name condition)))))

(defun read-page (name markdown)
  "The first pass over the page NAME: its MARKDOWN parsed as GFM, and its
headings' texts and ids, as a PAGE. A page the library refuses to parse
holds the problem instead."
  (multiple-value-bind (ast problem) (parse-page name markdown)
    (if problem
        (make-page name nil '() '() '() problem)
        (let* ((headings (find-headings ast))
               (texts (mapcar #'heading-text headings)))
          (make-page name ast headings texts (unique-ids texts))))))

(defun page-label (page)
  "PAGE's label in the sidebar: its first heading's text, or its file name
when it has no heading."
  (or (first (page-texts page)) (page-name page)))

(defun page-title (page)
  "PAGE's title: the project's name for the home page, otherwise its label."
  (if (string= (page-name page) *home-page*)
      *project-name*
      (page-label page)))

(defun page-toc (page)
  "PAGE's \"On this page\" links: its ## headings, each as (ID . TEXT)."
  (loop for heading in (page-headings page)
        for text in (page-texts page)
        for id in (page-ids page)
        when (= (node-attribute heading :level) 2)
          collect (cons id text)))

(defun site-nav (pages)
  "The sidebar's pages: each of PAGES but the home page, in order, as
(NAME . LABEL)."
  (loop for page in pages
        unless (string= (page-name page) *home-page*)
          collect (cons (page-name page) (page-label page))))

(defun neighbours (name nav)
  "The pages before and after the page NAME in NAV, as two values, each a
(NAME . LABEL) or NIL. A page that isn't in NAV, such as the home page,
has neither."
  (loop for previous = nil then entry
        for (entry . rest) on nav
        when (string= (car entry) name)
          return (values previous (first rest))
        finally (return (values nil nil))))

;;; The second pass: links

(defun link-node-p (node)
  "True when NODE is a :LINK or an :IMAGE, whose destination the site
rewrites."
  (member (node-kind node) '(:link :image)))

(defun rewrite-links (ast page-names ref)
  "AST with each :LINK and :IMAGE node's destination rewritten for the site
by REWRITE-DESTINATION."
  (transform-ast (lambda (node)
                   (if (link-node-p node)
                       (copy-node node :attributes
                                  (list :destination
                                        (rewrite-destination (node-attribute node :destination)
                                                             page-names
                                                             ref)))
                       node))
                 ast))

;;; The second pass: the HTML tree

(defun elementp (node)
  "True when NODE, an HTML tree node, is an element: a list whose first
item is a keyword."
  (and (consp node) (keywordp (first node))))

(defstruct (rebuild-frame (:constructor make-rebuild-frame (element remaining)))
  "One REBUILD-ELEMENTS frame: ELEMENT, entered and not yet rebuilt, or NIL
for the top-level nodes; REMAINING, its children still to visit; and BUILT,
its children already rebuilt, the newest first."
  element
  remaining
  (built '()))

(defun rebuild-elements (function nodes)
  "NODES, a list of HTML tree nodes, rebuilt bottom up: each element is
rebuilt around its rebuilt children, then replaced by FUNCTION's result on
it and on the element as NODES held it, so FUNCTION can look the original
up. FUNCTION meets the elements in the order they end, which, among
elements that never hold one another, such as headings, is document order.
Strings are kept as they are. Loops over an explicit stack, so memory, not
the Lisp call stack, bounds a tree's depth."
  (let ((stack (list (make-rebuild-frame nil nodes))))
    (loop
      (let ((frame (first stack)))
        (cond ((rebuild-frame-remaining frame)
               (let ((node (pop (rebuild-frame-remaining frame))))
                 (if (elementp node)
                     (push (make-rebuild-frame node (cddr node)) stack)
                     (push node (rebuild-frame-built frame)))))
              (t
               (pop stack)
               (let ((element (rebuild-frame-element frame))
                     (children (reverse (rebuild-frame-built frame))))
                 (if (null stack)
                     (return children)
                     (push (funcall function
                                    (list* (first element) (second element) children)
                                    element)
                           (rebuild-frame-built (first stack)))))))))))

(defun first-text-character (element)
  "The first character of ELEMENT's text that isn't a newline, or NIL. The
newlines cmark writes between blocks are layout, not text, and a comment's
text isn't the element's. Loops over an explicit stack of child lists."
  (let ((stack (list (cddr element))))
    (loop while stack
          do (let ((nodes (pop stack)))
               (when nodes
                 (push (rest nodes) stack)
                 (let ((node (first nodes)))
                   (cond ((stringp node)
                          (let ((char (find-if (lambda (char) (char/= char #\Newline)) node)))
                            (when char
                              (return char))))
                         ((and (elementp node) (not (eql (first node) :*comment*)))
                          (push (cddr node) stack)))))))))

(defconstant +warning-sign+ (code-char #x26A0)
  "U+26A0, the warning sign. A blockquote whose text starts with it, with
or without U+FE0F after it, which asks for its emoji form, is a warning.")

(defun warning-blockquote-p (element)
  "True when ELEMENT is a blockquote whose text starts with +WARNING-SIGN+."
  (and (eql (first element) :blockquote)
       (let ((char (first-text-character element)))
         (and char (char= char +warning-sign+)))))

(defun heading-element-p (element)
  "True when ELEMENT is a heading, h1 to h6."
  (member (first element) '(:h1 :h2 :h3 :h4 :h5 :h6)))

(defun callout-blockquotes (nodes)
  "The blockquotes of NODES, a list of HTML tree nodes, that become
callouts, as a table of the elements themselves: each warning blockquote
that no other one holds. A callout is wrapped whole, quotes inside it
included, so the walk doesn't look inside one. Loops over an explicit
stack of child lists."
  (let ((callouts (make-hash-table))
        (stack (list nodes)))
    (loop while stack
          do (let ((nodes (pop stack)))
               (when nodes
                 (push (rest nodes) stack)
                 (let ((node (first nodes)))
                   (when (elementp node)
                     (if (warning-blockquote-p node)
                         (setf (gethash node callouts) t)
                         (push (cddr node) stack)))))))
    callouts))

(defun decorate-body (body ids)
  "BODY, a page's HTML tree from AST->HTML-TREE, with IDS on its heading
elements, in order, and each blockquote CALLOUT-BLOCKQUOTES finds wrapped
in a callout div. IDS are the ids of the page's :HEADING nodes, which
convert to its heading elements one for one, in the same order. Signals an
error when the two counts differ, rather than put an id on the wrong
heading."
  (let* ((remaining ids)
         (callouts (callout-blockquotes body))
         (decorated
           (rebuild-elements
            (lambda (element original)
              (cond ((heading-element-p element)
                     (when (null remaining)
                       (error "The page's HTML has more headings than its ~D ids." (length ids)))
                     (list* (first element)
                            (cons (list :id (pop remaining)) (second element))
                            (cddr element)))
                    ((gethash original callouts)
                     (list :div '((:class "callout warning")) element))
                    (t element)))
            body)))
    (when remaining
      (error "The page's HTML has ~D headings for its ~D ids."
             (- (length ids) (length remaining))
             (length ids)))
    decorated))

;;; The second pass: problems

(defun heading-node-p (node)
  "True when NODE is a :HEADING."
  (and node (eql (node-kind node) :heading)))

(defun title-heading-p (node)
  "True when NODE is a level-1 heading, written #."
  (and (heading-node-p node) (= (node-attribute node :level) 1)))

(defun raw-html-p (node)
  "True when NODE is raw HTML, which AST->HTML-TREE omits by default."
  (member (node-kind node) '(:html-block :html-inline)))

(defun heading-markdown (heading)
  "HEADING as an ATX heading writes it, its level in #s, then its text:
## Usage."
  (format nil "~A ~A"
          (make-string (node-attribute heading :level) :initial-element #\#)
          (heading-text heading)))

(defun first-line (string)
  "STRING up to its first newline."
  (subseq string 0 (position #\Newline string)))

(defun start-problems (name first-block)
  "The problems with how the page NAME starts, whose first block is
FIRST-BLOCK, or NIL when it has no block: none when it starts with a #
heading, otherwise one."
  (cond ((title-heading-p first-block) '())
        ((heading-node-p first-block)
         (list (format nil "~A: starts with ~A, not a # heading"
                       name (heading-markdown first-block))))
        (t (list (format nil "~A: doesn't start with a # heading" name)))))

(defun destination-anchor (destination name kind value fragment)
  "The page and the id that DESTINATION, on the page NAME, links to, as two
values, or NIL when it links to no id on the site. KIND, VALUE and
FRAGMENT are CLASSIFY-DESTINATION's values for it. An #id is an id on NAME
itself."
  (cond ((string-prefix-p "#" destination) (values name (subseq destination 1)))
        ((and (eql kind :page) fragment) (values value (subseq fragment 1)))
        (t (values nil nil))))

(defun id-on-page-p (id page site-ids)
  "True when ID is one of the page PAGE's heading ids in SITE-IDS, a list
of (NAME . IDS), as it is written or once its %XX escapes are decoded: a
browser looks for the fragment as written, then decoded."
  (let ((ids (cdr (assoc page site-ids :test #'string=))))
    (or (member id ids :test #'string=)
        (member (percent-decode id) ids :test #'string=))))

(defun link-problem (node name page-names site-ids)
  "What's wrong with NODE, a :LINK or :IMAGE on the page NAME, or NIL: it
is an image with a relative path, which would go to GitHub's page for the
file rather than to the image; its destination can't be rewritten; or it
links to an id that isn't on its page. An empty id, a bare #, links to the
top of the page."
  (let ((destination (node-attribute node :destination))
        (what (string-downcase (symbol-name (node-kind node)))))
    (multiple-value-bind (kind value fragment) (classify-destination destination page-names)
      (cond ((and (eql (node-kind node) :image) (not (eql kind :kept)))
             (format nil "~A: image ~A has a relative path, which the site can't show"
                     name destination))
            ((eql kind :problem)
             (format nil "~A: ~A ~A ~A" name what destination value))
            (t
             (multiple-value-bind (page id)
                 (destination-anchor destination name kind value fragment)
               (when (and page (plusp (length id)) (not (id-on-page-p id page site-ids)))
                 (format nil "~A: ~A ~A names no id on ~A" name what destination page))))))))

(defun repository-path (node page-names)
  "The file or directory in the repository that NODE, a :LINK or :IMAGE,
names when the site sends it to GitHub, or NIL. Only a link goes there: an
image with a relative path is a problem instead."
  (when (eql (node-kind node) :link)
    (multiple-value-bind (kind value)
        (classify-destination (node-attribute node :destination) page-names)
      (when (eql kind :repository)
        (repository-file-path value)))))

(defun ascii-text-p (text)
  "True when every character of TEXT is ASCII."
  (every (lambda (char) (< (char-code char) 128)) text))

(defun holds-node-p (node kind)
  "True when NODE, or a node below it, is of KIND."
  (fold-ast (lambda (child found) (or found (eql (node-kind child) kind))) nil node))

(defun duplicate-id-problems (page)
  "A table from each heading on PAGE that is the second to have its id to
the problem that names the id, and how many headings have it. UNIQUE-IDS
counts each id's repeats apart, so a heading whose own id ends in a hyphen
and a number can share it with another's numbered repeat: A, A 1 and A
give a, a-1 and a-1. Two headings with one id make a link to it
ambiguous, and how GitHub numbers such headings isn't known, so the site
refuses the page rather than guess."
  (let ((counts (make-hash-table :test 'equal))
        (seen (make-hash-table :test 'equal))
        (problems (make-hash-table)))
    (dolist (id (page-ids page))
      (incf (gethash id counts 0)))
    (loop for heading in (page-headings page)
          for id in (page-ids page)
          when (= (incf (gethash id seen 0)) 2)
            do (setf (gethash heading problems)
                     (format nil "~A: ~R headings have the id ~A"
                             (page-name page) (gethash id counts) id)))
    problems))

(defun heading-problems (heading name first-block duplicates)
  "The problems with HEADING, on the page NAME whose first block is
FIRST-BLOCK, as a list:
- a # heading that isn't the first block;
- text outside ASCII, an image, or a footnote reference. GitHub's
  published id rules disagree with each other and with HEADING-ID on
  those, and the ids github.com gives them aren't known, so the site
  refuses such a heading rather than guess;
- an empty id, which no link can name;
- an id another heading has, from DUPLICATES, DUPLICATE-ID-PROBLEMS'
  table."
  (let ((text (heading-text heading)))
    (flet ((unknown-id (what)
             (format nil "~A: heading ~A holds ~A, whose GitHub id isn't known" name text what)))
      (remove nil
              (list (when (and (title-heading-p heading) (not (eql heading first-block)))
                      (format nil "~A: ~A: only the first block may be a # heading"
                              name (heading-markdown heading)))
                    (unless (ascii-text-p text)
                      (unknown-id "non-ASCII text"))
                    (when (holds-node-p heading :image)
                      (unknown-id "an image"))
                    (when (holds-node-p heading :footnote-reference)
                      (unknown-id "a footnote reference"))
                    (when (zerop (length (heading-id text)))
                      (format nil "~A: heading ~A gives an empty id" name text))
                    (gethash heading duplicates))))))

(defun node-problems (node name first-block page-names site-ids duplicates)
  "The problems with NODE, on the page NAME whose first block is
FIRST-BLOCK, as a list: a link or image that LINK-PROBLEM refuses; raw
HTML, which the site would omit; or a heading's HEADING-PROBLEMS."
  (cond ((link-node-p node)
         (let ((problem (link-problem node name page-names site-ids)))
           (if problem (list problem) '())))
        ((raw-html-p node)
         (list (format nil "~A: raw HTML ~A" name (first-line (node-attribute node :literal)))))
        ((heading-node-p node)
         (heading-problems node name first-block duplicates))
        (t '())))

(defun page-problems (page page-names site-ids)
  "The problems on PAGE's AST, in document order: how it starts, then each
node's NODE-PROBLEMS. SITE-IDS are every page's ids, as (NAME . IDS).
Returns two more values, from its links and images: how many it checked;
and, in document order, each path in the repository that one of them goes
to on GitHub, from REPOSITORY-PATH."
  (let* ((name (page-name page))
         (ast (page-ast page))
         (first-block (first (node-children ast)))
         (duplicates (duplicate-id-problems page))
         (links 0)
         (paths '())
         (problems (fold-ast (lambda (node problems)
                               (when (link-node-p node)
                                 (incf links)
                                 (let ((path (repository-path node page-names)))
                                   (when path
                                     (push path paths))))
                               (append (reverse (node-problems node name first-block
                                                               page-names site-ids duplicates))
                                       problems))
                             '()
                             ast)))
    (values (append (start-problems name first-block) (reverse problems))
            links
            (reverse paths))))

(defun link-attributes (document)
  "Each href and src attribute in DOCUMENT, an HTML tree element, as
(NAME VALUE), in document order. Loops over an explicit stack of child
lists."
  (let ((stack (list (list document)))
        (found '()))
    (loop while stack
          do (let ((nodes (pop stack)))
               (when nodes
                 (push (rest nodes) stack)
                 (let ((node (first nodes)))
                   (when (elementp node)
                     (dolist (attribute (second node))
                       (when (member (first attribute) '(:href :src))
                         (push attribute found)))
                     (push (cddr node) stack))))))
    (nreverse found)))

(defun stale-destination-reason (destination)
  "Why DESTINATION, an href or a src on the site, still points into the
repository instead of the site, or NIL: it is a relative path that ends in
.md, before any #, or that starts with ../."
  (cond ((kept-destination-p destination) nil)
        ((string-suffix-p ".md" (split-fragment destination)) "ends in .md")
        ((string-prefix-p "../" destination) "starts with ../")
        (t nil)))

(defun stale-link-problems (name document)
  "A problem for each href and src in DOCUMENT, the page NAME's whole HTML
tree, that still points into the repository instead of the site. After
REWRITE-DESTINATION, none is left: one that is shows the rewrite is
broken."
  (loop for (attribute value) in (link-attributes document)
        for reason = (stale-destination-reason value)
        when reason
          collect (format nil "~A: ~(~A~) ~A still ~A" name attribute value reason)))

;;; Both passes

(defun build-page (page nav page-names site-ids ref)
  "The second pass over PAGE: its HTML; as a second value, its problems,
those on its AST, then those STALE-LINK-PROBLEMS finds in its whole tree;
then, as PAGE-PROBLEMS gives them, the number of links and images it
checked, and the repository paths its links go to on GitHub. NAV is the
sidebar's pages, PAGE-NAMES every page's name, SITE-IDS every page's ids,
and REF the git ref the site is rendered from."
  (let* ((name (page-name page))
         (body (decorate-body (ast->html-tree (rewrite-links (page-ast page) page-names ref))
                              (page-ids page)))
         (document (multiple-value-bind (previous next) (neighbours name nav)
                     (page-document :nav nav
                                    :current name
                                    :title (page-title page)
                                    :body body
                                    :toc (page-toc page)
                                    :prev previous
                                    :next next
                                    :ref ref))))
    (multiple-value-bind (problems links paths) (page-problems page page-names site-ids)
      (values (html-tree->string document)
              (append problems (stale-link-problems name document))
              links
              paths))))

(defun render-site (pages ref)
  "Render PAGES, each (NAME . MARKDOWN), NAME a docs/ file name: the home
page, README.md, first, then the sidebar's pages, in its order. REF is the
git ref the site is rendered from, such as a release tag: links to the
repository's files point into it. Returns five values:
- each page's HTML, as (HTML-NAME . HTML), README.md's as index.html. The
  HTML is the page's serialized tree, with no doctype before it;
- each page's heading ids, in document order, as (NAME . IDS);
- the problems found, as strings that start with their page's name, in
  page order, then document order;
- the number of links and images checked, across all the pages;
- each path in the repository that a link goes to on GitHub, as
  (NAME . PATH), in page order, then document order. PATH is from the
  repository's root, without the link's #fragment or ?query, and with its
  %XX escapes decoded. Whether the file exists is for the caller to check,
  since RENDER-SITE reads no file.
A link to an id on another page is checked against that page's ids, so
the first pass parses every page and gives its headings their ids, and
the second rewrites and checks each page's links and builds the page. A
page the library refuses to parse, signalling one of its errors, is one
problem, PARSE-PROBLEM's, in its place: it has no HTML, no place in the
sidebar, and no ids, so a link to an id on it names none."
  (let* ((page-names (mapcar #'car pages))
         (parsed (mapcar (lambda (page) (read-page (car page) (cdr page))) pages))
         (site-ids (mapcar (lambda (page) (cons (page-name page) (page-ids page))) parsed))
         (nav (site-nav (remove-if #'page-problem parsed))))
    (loop for page in parsed
          for (html problems links paths)
            = (if (page-problem page)
                  (list nil (list (page-problem page)) 0 '())
                  (multiple-value-list (build-page page nav page-names site-ids ref)))
          unless (page-problem page)
            collect (cons (page-html-name (page-name page)) html) into outputs
          append problems into all-problems
          sum links into link-count
          append (mapcar (lambda (path) (cons (page-name page) path)) paths)
            into repository-paths
          finally (return (values outputs site-ids all-problems link-count
                                  repository-paths)))))
