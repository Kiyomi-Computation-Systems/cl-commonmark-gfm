;;;; ADR-0014's two known footnote divergences, as property 1 excuses them
;;;; (ADR-0020; M3 design §6.4), and the oracle properties, 1 and 2 (M3
;;;; design §6.3): the HTML oracle and the XML oracle. Each excuse is a
;;;; function of cmark's HTML, the tree's HTML, and the case's AST parsed
;;;; with :SOURCEPOS T. It excuses a difference only in its own documented
;;;; shape; every other difference stays a failure.
;;;;
;;;; cmark's footnote markup, read from vendor/cmark-gfm, not from memory:
;;;; - A reference (S_render_node's CMARK_NODE_FOOTNOTE_REFERENCE case,
;;;;   src/html.c) is <sup class="footnote-ref"><a href="#fn-L"
;;;;   id="fnref-L" data-footnote-ref>N</a></sup>, its id fnref-L-K for its
;;;;   definition's K-th reference, K >= 2. L is the kept definition's
;;;;   label as written, through houdini_escape_href; N its number.
;;;; - A definition (the CMARK_NODE_FOOTNOTE_DEFINITION case) is an <li
;;;;   id="fn-L">. The first opens <section class="footnotes"
;;;;   data-footnotes>, a newline, <ol>, a newline; after the whole walk,
;;;;   cmark_render_html_with_mem closes them with </ol>, a newline,
;;;;   </section>, a newline: the section always ends the output.
;;;; - Its backrefs (S_put_footnote_backref) are one <a href="#fnref-L"
;;;;   class="footnote-backref" data-footnote-backref ...> for each of the
;;;;   definition's def_count references, the K-th linking to #fnref-L-K
;;;;   from K = 2. N there is the renderer's own count of the definitions
;;;;   written so far.
;;;; - process_footnotes (src/blocks.c) counts each reference, giving it its
;;;;   K, in the tree's order before any definition moves, which is source
;;;;   order, references inside unreferenced and duplicate definitions
;;;;   included. Only then does it drop those definitions, subtrees and all,
;;;;   and move each kept one to the document's end, in number order. A kept
;;;;   definition whose references all sat in dropped ones keeps backrefs to
;;;;   ids nothing writes.
;;;; - Text and attribute values never hold a raw < or ": escape_html and
;;;;   houdini_escape_href escape both, and raw HTML is omitted under every
;;;;   one of the 33 option sets (none sets :UNSAFE-HTML). So the markup
;;;;   below, and " id=\"", can only be cmark's own, and the tree's.
;;;;
;;;; Both excuses are narrower than spec §6.4's words, never wider. The
;;;; repeat excuse touches only the ids of the labels the AST shows in the
;;;; divergent shape, only when the tree numbered them fnref-L, fnref-L-2
;;;; and so on, and rewrites each to the one id cmark gives that reference,
;;;; by its position in the source; the rest, backrefs included, must then
;;;; be cmark's, byte for byte. A removed item must be a definition the AST
;;;; holds no reference to. Three other shapes of the same two causes stay
;;;; failures (M3 finding 9), each confirmed with the pinned CLI: a dangling
;;;; footnote numbered before a kept one, which renumbers every footnote
;;;; after it; repeat references in two definitions whose numbers differ
;;;; from their source order, with no body reference; and a footnote
;;;; referenced from the body and from a dropped definition, whose backrefs
;;;; dangle in part.

(in-package #:cl-commonmark-gfm.native-tests)

;;; The AST side

(defun ast-footnote-references (ast)
  "Every :FOOTNOTE-REFERENCE of AST, in tree order, as (LABEL START
INSIDE-DEFINITION-P): its :LABEL, the copier's label of its definition as
written; the (LINE . COLUMN) its position starts at, or NIL; and whether a
:FOOTNOTE-DEFINITION holds it."
  (let ((definitions 0)
        (references '()))
    (walk-ast (lambda (event node)
                (let ((kind (node-kind node)))
                  (cond
                    ((eql kind :footnote-definition)
                     (if (eql event :enter) (incf definitions) (decf definitions)))
                    ((and (eql kind :footnote-reference) (eql event :enter))
                     (push (list (node-attribute node :label)
                                 (car (node-sourcepos node))
                                 (plusp definitions))
                           references))))
                nil)
              ast)
    (nreverse references)))

(defun footnote-definition-labels (ast)
  "The :LABEL of every :FOOTNOTE-DEFINITION of AST, in tree order."
  (let ((labels '()))
    (walk-ast (lambda (event node)
                (when (and (eql event :enter) (eql (node-kind node) :footnote-definition))
                  (push (node-attribute node :label) labels))
                nil)
              ast)
    (nreverse labels)))

(defun position< (a b)
  "True when A, a (LINE . COLUMN), comes before B in the source."
  (or (< (car a) (car b))
      (and (= (car a) (car b)) (< (cdr a) (cdr b)))))

(defun repeat-divergent-labels (ast)
  "Each label L, once, for which AST, parsed with :SOURCEPOS T, holds a
reference to L inside a definition that starts, in the source, before a
body reference to L: the shape of ADR-0014's first divergence. Such a
reference is a repeat in the tree, which puts every definition after the
body, but cmark counted it first (process_footnotes, src/blocks.c). A
reference without a position decides nothing."
  (let* ((references (ast-footnote-references ast))
         (body (remove-if #'third references))
         (labels '()))
    (dolist (reference references (nreverse labels))
      (destructuring-bind (label start inside) reference
        (when (and inside
                   start
                   (some (lambda (other)
                           (destructuring-bind (other-label other-start other-inside) other
                             (declare (ignore other-inside))
                             (and other-start
                                  (string= label other-label)
                                  (position< start other-start))))
                         body))
          (pushnew label labels :test #'string=))))))

(defun html-label (label)
  "LABEL as cmark writes it in an id or href: houdini_escape_href
(src/houdini_href_e.c) percent-encodes it, but & and ', which it writes as
&amp; and &#x27;. The tree's HREF-ENCODE, then the serializer's escapes for
an id, give the same; a bug in either only makes an excuse fail."
  (with-output-to-string (out)
    (html-tree::write-escaped-string (html-tree::href-encode label) out t)))

;;; Reading cmark's markup

(defparameter *item-start* "<li id=\"fn-"
  "What starts a footnote item: the CMARK_NODE_FOOTNOTE_DEFINITION case of
S_render_node (src/html.c).")

(defparameter *reference-start* "<a href=\"#fn-"
  "What starts a footnote reference's anchor, its label next (the
CMARK_NODE_FOOTNOTE_REFERENCE case of S_render_node, src/html.c). A link
of the reader's own writes no id after its href, so *REFERENCE-ID-START*
tells the two apart.")

(defparameter *reference-id-start* "\" id=\""
  "What follows a footnote reference's label: the end of its href, and the
start of its id, fnref-L or fnref-L-K.")

(defparameter *reference-id-end* "\" data-footnote-ref>"
  "What follows a footnote reference's id.")

(defparameter *backref-start* "<a href=\"#fnref-"
  "What starts a backref, its target's id next (S_put_footnote_backref,
src/html.c).")

(defparameter *backref-href-end* "\" class=\"footnote-backref\" data-footnote-backref "
  "What follows a backref's href: no link of the reader's own has a class.")

(defparameter *section-start*
  (format nil "<section class=\"footnotes\" data-footnotes>~%<ol>~%")
  "What the first footnote definition opens (S_render_node, src/html.c).")

(defparameter *section-end* (format nil "</ol>~%</section>~%")
  "What cmark_render_html_with_mem (src/html.c) writes after the whole walk
when it wrote a footnote: the end of every output with a section.")

(defun starts-at-p (prefix string index)
  "True when STRING holds PREFIX at INDEX."
  (let ((end (+ index (length prefix))))
    (and (<= end (length string))
         (string= prefix string :start2 index :end2 end))))

(defun quoted-value (string start)
  "The characters of STRING from START up to the next double quote, and
that quote's index; NIL when no double quote follows."
  (let ((end (position #\" string :start start :test #'char=)))
    (if end
        (values (subseq string start end) end)
        nil)))

;;; :EXCUSED-REPEAT: each repeat reference's id, as cmark numbers it. Both
;;; give a label's K-th reference the id fnref-L-K, but cmark counts K in
;;; source order (process_footnotes, src/blocks.c), and the tree in tree
;;; order (ADR-0014). A backref doesn't depend on that order:
;;; S_put_footnote_backref (src/html.c) writes fnref-L, then fnref-L-2 up to
;;; the definition's count, and so does the tree.

(defun numbered-reference-id (html-label k)
  "The id of the K-th reference to the footnote whose label HTML writes as
HTML-LABEL: fnref-L for the first, fnref-L-K from the second on (the
CMARK_NODE_FOOTNOTE_REFERENCE case of S_render_node, src/html.c, and the
tree's REFERENCE-ID)."
  (if (= k 1)
      (concatenate 'string "fnref-" html-label)
      (format nil "fnref-~A-~D" html-label k)))

(defun reference-id-spans (html html-label)
  "Where HTML writes the id of each reference to the footnote whose label it
writes as HTML-LABEL, in order: a list of (START . END), the id's value
running from START to END. A reference's anchor names its footnote in its
href, then gives its id."
  (loop for index in (substring-starts *reference-start* html 0 (length html))
        nconc (multiple-value-bind (label label-end)
                  (quoted-value html (+ index (length *reference-start*)))
                (when (and label
                           (string= label html-label)
                           (starts-at-p *reference-id-start* html label-end))
                  (let ((id-start (+ label-end (length *reference-id-start*))))
                    (multiple-value-bind (id id-end) (quoted-value html id-start)
                      (and id
                           (starts-at-p *reference-id-end* html id-end)
                           (list (cons id-start id-end)))))))))

(defun tree-numbered-p (html label)
  "True when HTML's ids for the references to LABEL are, in order, exactly
those the tree gives them: fnref-L, then fnref-L-2, fnref-L-3 and so on."
  (let ((html-label (html-label label)))
    (loop for (start . end) in (reference-id-spans html html-label)
          for k from 1
          always (string= (numbered-reference-id html-label k) html :start2 start :end2 end))))

(defun label-reference-starts (ast label)
  "Where each of AST's references to LABEL starts in the source, in tree
order: a (LINE . COLUMN), or NIL for a reference without a position."
  (loop for (reference-label start) in (ast-footnote-references ast)
        when (string= reference-label label)
          collect start))

(defun source-ranks (starts)
  "The rank in source order of each of STARTS, (LINE . COLUMN) positions,
in STARTS' own order: 1 for the one the source holds first. NIL when one is
missing or two are equal, since the source order isn't known then."
  (and (notany #'null starts)
       (loop for (start . rest) on starts
             never (member start rest :test #'equal))
       (loop for start in starts
             collect (1+ (count-if (lambda (other) (position< other start)) starts)))))

(defun spliced (string edits)
  "STRING with each of EDITS, a (START END REPLACEMENT), putting REPLACEMENT
in place of the characters from START to END. EDITS come in order of START,
and don't overlap."
  (with-output-to-string (out)
    (let ((index 0))
      (loop for (start end replacement) in edits
            do (write-string string out :start index :end start)
               (write-string replacement out)
               (setf index end))
      (write-string string out :start index))))

(defun source-numbered-html (tree-html ast labels)
  "TREE-HTML with the ids of the references to LABELS numbered as cmark
numbers them: for each label, the I-th of its ids, in TREE-HTML's order,
which is the tree's, becomes the id of the I-th reference's rank in source
order, by its position in AST, parsed with :SOURCEPOS T. NIL when a
label's positions give no source order. When TREE-HTML holds more or fewer
of a label's ids than AST holds references to it, only the shorter count
is rewritten and the rest of TREE-HTML's own ids are left in place, so the
result differs from cmark's; EXCUSED-REPEAT-P catches that by comparing
the result, not by a NIL here. The ids it replaces aren't checked:
TREE-NUMBERED-P checks them."
  (let ((edits '()))
    (dolist (label labels)
      (let ((html-label (html-label label))
            (ranks (source-ranks (label-reference-starts ast label))))
        (let ((spans (reference-id-spans tree-html html-label)))
          (unless ranks
            (return-from source-numbered-html nil))
          (loop for (start . end) in spans
                for rank in ranks
                do (push (list start end (numbered-reference-id html-label rank)) edits)))))
    (spliced tree-html (sort edits #'< :key #'first))))

(defun excused-repeat-p (cmark-html tree-html ast)
  "True when spec §6.4 excuses the difference between CMARK-HTML and
TREE-HTML as ADR-0014's first divergence, repeat references counted in tree
order, and as nothing else:
- AST, the parse with :SOURCEPOS T, has the divergence's shape: for some
  label L, a reference inside a definition that comes, in the source,
  before a body reference to L (REPEAT-DIVERGENT-LABELS);
- for each such L, TREE-HTML's ids are exactly those the tree gives L's
  references: fnref-L, fnref-L-2 and so on (TREE-NUMBERED-P), one for each
  reference AST holds (SOURCE-NUMBERED-HTML);
- and once each of those ids is rewritten to the id cmark gives its
  reference, by source order (SOURCE-NUMBERED-HTML), TREE-HTML is
  CMARK-HTML, byte for byte, backrefs included."
  (let ((labels (repeat-divergent-labels ast)))
    (and labels
         (every (lambda (label) (tree-numbered-p tree-html label)) labels)
         (equal cmark-html (source-numbered-html tree-html ast labels)))))

;;; :EXCUSED-DROPPED: footnotes whose every backref dangles

(defun footnote-section (html)
  "Where cmark's footnote section lies in HTML, as three indices: where it
starts, where its first item starts, and where its last item ends. NIL when
HTML holds no section, or not exactly one, ending HTML."
  (let ((start (search *section-start* html))
        (items-end (- (length html) (length *section-end*))))
    (if (and start
             (not (search *section-start* html :start2 (1+ start)))
             (<= (+ start (length *section-start*)) items-end)
             (starts-at-p *section-end* html items-end))
        (values start (+ start (length *section-start*)) items-end)
        nil)))

(defun substring-starts (pattern html start end)
  "The index of every occurrence of PATTERN in HTML from START to END."
  (loop for index = (search pattern html :start2 start :end2 end)
          then (search pattern html :start2 (1+ index) :end2 end)
        while index
        collect index))

(defun html-ids (html)
  "The value of every id attribute in HTML: the footnote items' fn-L and
the references' fnref-L and fnref-L-K, the only ids cmark writes."
  (loop for index in (substring-starts " id=\"" html 0 (length html))
        for id = (quoted-value html (+ index (length " id=\"")))
        when id
          collect id))

(defun backref-targets (html start end)
  "The id each backref between START and END in HTML links to."
  (loop for index in (substring-starts *backref-start* html start end)
        append (multiple-value-bind (id id-end)
                   (quoted-value html (+ index (length *backref-start*)))
                 (and id
                      (starts-at-p *backref-href-end* html id-end)
                      (list (concatenate 'string "fnref-" id))))))

(defun dangling-item-p (html start end ids)
  "True when the footnote item from START to END in HTML has a backref, and
every backref it has links to none of IDS."
  (let ((targets (backref-targets html start end)))
    (and targets
         (notany (lambda (target) (member target ids :test #'string=)) targets))))

(defun without-dangling-items (html)
  "HTML, cmark's, without each footnote item whose every backref links to
no id in HTML, and without the whole section when none is left: what the
tree writes when a definition referenced only from dropped definitions is
gone. As a second value, the removed items' labels, as HTML writes them, in
order. HTML itself and NIL when no item is removed."
  (multiple-value-bind (section-start items-start items-end) (footnote-section html)
    (let ((starts (and section-start
                       (substring-starts *item-start* html items-start items-end))))
      (if (or (null starts) (/= (first starts) items-start))
          (values html '())
          (let ((ids (html-ids html))
                (kept '())
                (removed '()))
            (loop for (start next) on starts
                  for end = (or next items-end)
                  do (if (dangling-item-p html start end ids)
                         (push (values (quoted-value html (+ start (length *item-start*))))
                               removed)
                         (push (subseq html start end) kept)))
            (values (cond
                      ((null removed) html)
                      ((null kept) (subseq html 0 section-start))
                      (t (apply #'concatenate 'string
                                (subseq html 0 items-start)
                                (append (nreverse kept) (list (subseq html items-end))))))
                    (nreverse removed)))))))

(defun unreferenced-definition-label-p (label ast)
  "True when AST holds a definition whose label, as HTML-LABEL writes it, is
LABEL, and no reference to it: the parsed tree has lost every reference to
it (ADR-0014, \"Known divergences\")."
  (and (member label (mapcar #'html-label (footnote-definition-labels ast)) :test #'string=)
       (notany (lambda (reference) (string= label (html-label (first reference))))
               (ast-footnote-references ast))))

(defun excused-dropped-p (cmark-html tree-html ast)
  "True when spec §6.4 excuses the difference between CMARK-HTML and
TREE-HTML as ADR-0014's second divergence, a definition referenced only
from a dropped definition: the two are equal once cmark's footnote items
are removed wherever every backref links to no id in cmark's output. Each
removed item must also be a definition AST holds no reference to, so a
footnote the tree should still render, one referenced from an image's alt
text say, is never excused."
  (multiple-value-bind (remaining removed) (without-dangling-items cmark-html)
    (and removed
         (every (lambda (label) (unreferenced-definition-label-p label ast)) removed)
         (string= remaining tree-html))))

;;; The outcome

(defparameter *snippet-length* 32
  "How many characters of each output a difference's detail shows.")

(defun snippet (string index)
  "Up to *SNIPPET-LENGTH* characters of STRING from INDEX, escaped as a
property report escapes an input."
  (let ((start (min index (length string))))
    (cl-commonmark-gfm.tests::escaped-string
     (subseq string start (min (length string) (+ start *snippet-length*))))))

(defun difference-detail (what cmark ours)
  "A detail for a mismatch: WHAT, then where OURS first differs from CMARK,
and a few characters of each from there. Never a whole input."
  (let ((index (or (mismatch cmark ours) 0)))
    (format nil "~A at character ~D: cmark's ~A, ours ~A"
            what index (snippet cmark index) (snippet ours index))))

(defun html-oracle-outcome (cmark-html tree-html ast)
  "Property 1's outcome for one case, from cmark's HTML, the tree's HTML
and AST, the case parsed with :SOURCEPOS T: :PASS when the two are equal;
:EXCUSED-REPEAT or :EXCUSED-DROPPED when spec §6.4 excuses their difference
in that shape; otherwise :FAIL, and a detail."
  (cond
    ((string= cmark-html tree-html) :pass)
    ((excused-repeat-p cmark-html tree-html ast) :excused-repeat)
    ((excused-dropped-p cmark-html tree-html ast) :excused-dropped)
    (t (values :fail (difference-detail "the tree's html differs from cmark's"
                                        cmark-html tree-html)))))

;;; The guard

(defun guarded-p (input options operation)
  "True when the input guard, CL-COMMONMARK-GFM::CHECK-INPUT, rejects INPUT
under OPTIONS, one of the oracle's sets, for OPERATION. :FOOTNOTES, the one
option the guard reads, resolves alike for every entry point, since no
filtering drops :PROFILE or :FOOTNOTES, so :PARSE's options decide for all."
  (let ((checked (check-options :parse operation (entry-point-options :parse options))))
    (handler-case (progn (cl-commonmark-gfm::check-input input checked operation)
                         nil)
      (unsupported-input () t))))

;;; Property 1: the HTML oracle

(defun html-oracle-sides (input options)
  "cmark's HTML and the tree's HTML for INPUT under OPTIONS, as
THE-HTML-ORACLE-MATCHES-EVERY-EXAMPLE-BUT-THE-KNOWN-DIVERGENCES compares
them (tests/native/oracles.lisp): MARKDOWN->HTML, and its TREE-PATH,
HTML-TREE->STRING of MARKDOWN->HTML-TREE, both under the case's options,
:SOFTBREAK included. Call only once the guard has cleared INPUT."
  (values (apply #'markdown->html input (entry-point-options :html options))
          (apply #'tree-path input (entry-point-options :html-tree options))))

(defun positions-ast (input options)
  "INPUT's AST under OPTIONS, parsed with :SOURCEPOS T, as the repeat
excuse needs it: the AST alone can't tell which reference came first."
  (apply #'parse input :sourcepos t (entry-point-options :parse options)))

(defun html-oracle-property (input options)
  "Property 1 (M3 design §6.3), registered under :HTML-ORACLE: the tree's
HTML equals cmark's under the case's options, unless spec §6.4 excuses the
difference as one of ADR-0014's two divergences (HTML-ORACLE-OUTCOME). An
input the guard rejects is :GUARD, before anything reaches cmark."
  (if (guarded-p input options 'html-oracle-property)
      :guard
      (multiple-value-bind (cmark tree) (html-oracle-sides input options)
        (if (string= cmark tree)
            :pass
            (html-oracle-outcome cmark tree (positions-ast input options))))))

(register-property :html-oracle 'html-oracle-property
                   :generators '(:syntax-soup :corpus-splices))

;;; Property 2: the XML oracle

(defun cmark-xml (input options)
  "cmark's own XML for INPUT, parsed with OPTIONS, PARSE's keys: RENDER-XML
of a native document of its own. Call only once the guard has cleared
INPUT."
  (call-with-native-document
   input options
   (lambda (document checked-options)
     (declare (ignore checked-options))
     (values (render-xml document)))))

(defun xml-oracle-property (input options)
  "Property 2 (M3 design §6.3), registered under :XML-ORACLE: the AST PARSE
copies for INPUT with :SOURCEPOS T, written as cmark's XML by
AST->CMARK-XML (tests/native/xml.lisp), equals cmark's own RENDER-XML of
the same input and options, positions included. An input the guard rejects
is :GUARD, before anything reaches cmark."
  (let ((options (list* :sourcepos t (entry-point-options :parse options))))
    (if (guarded-p input options 'xml-oracle-property)
        :guard
        (let ((copied (ast->cmark-xml (apply #'parse input options)))
              (cmark (cmark-xml input options)))
          (if (string= cmark copied)
              :pass
              (values :fail (difference-detail "the copied ast's xml differs from cmark's"
                                               cmark copied)))))))

(register-property :xml-oracle 'xml-oracle-property
                   :generators '(:syntax-soup :corpus-splices))

;;; Self tests (M3 plan, Task 5, "Tests first"): ADR-0014's two pinned
;;; divergences, each excused as its own kind; every one-character change to
;;; a pin's tree HTML failing; mismatches that a rewrite by source order
;;; alone would hide, failing when the AST holds no in-definition reference
;;; before a body reference; a dangling footnote the AST still references,
;;; never excused; broken repeat ids failing, on the repeat pin too; M3
;;; finding 9's three shapes failing; property 2 on vocabulary.md, with and
;;; without the copier's end positions; and the footnote-entity guard both
;;; properties share, which no parse may precede.
;;;
;;; Parachute keeps every assertion's closure until the run ends
;;; (progress.md's global constraints), so every helper here computes its
;;; HTML, ASTs and changed strings itself, and returns a small summary: an
;;; outcome keyword, a short list of indices, a boolean.

(defun gfm-options ()
  "The HTML oracle's option set for :GFM at :SOFTBREAK :NEWLINE: the
options the oracle's own pins render with (tests/native/oracles.lisp), as
one of the 33 sets a case can draw."
  (find-if (lambda (options)
             (and (eql (getf options :profile) :gfm)
                  (eql (getf options :softbreak) :newline)))
           (oracle-option-sets)))

(defun repeat-pin ()
  "REPEAT-REFERENCES-COUNTED-IN-TREE-ORDER-STILL-DIVERGES' input
(tests/native/oracles.lisp): b's definition holds a reference to b, which
the source puts before the body's reference to b."
  (markdown-lines "[^b]:[^b]" "" "[^b]"))

(defun dropped-pin ()
  "A-DEFINITION-REFERENCED-ONLY-FROM-A-DROPPED-DEFINITION-STILL-DIVERGES'
input (tests/native/oracles.lisp): a's definition nests b's, which nothing
references, and b's holds the only reference to a."
  (markdown-lines "[^a]:[^b]:[^a]"))

(defun dropped-after-a-kept-footnote ()
  "The dropped pin after a body reference to c and c's definition: cmark
numbers c 1 and the dangling a 2, so its HTML without a's item is the tree's,
which is not empty (confirmed with the pinned CLI)."
  (markdown-lines "x[^c]" "" "[^c]: C" "" "[^a]:[^b]:[^a]"))

(defun footnotes-on-p (options)
  "True when OPTIONS, one of the HTML oracle's sets, turn footnotes on."
  (checked-footnotes
   (check-options :parse 'oracle-self-tests (entry-point-options :parse options))))

;;; Each pin is excused, as its own kind

(defun pin-outcomes (markdown)
  "Property 1's outcomes for MARKDOWN over all 33 option sets: the distinct
outcomes where footnotes are on, and those where they are off."
  (let ((on '())
        (off '()))
    (dolist (options (oracle-option-sets))
      (if (footnotes-on-p options)
          (pushnew (run-case :html-oracle markdown options) on)
          (pushnew (run-case :html-oracle markdown options) off)))
    (list :footnotes-on on :footnotes-off off)))

(define-test each-pinned-divergence-is-excused-as-its-own-kind
  (is eql :excused-repeat (run-case :html-oracle (repeat-pin) (gfm-options)))
  (is eql :excused-dropped (run-case :html-oracle (dropped-pin) (gfm-options)))
  ;; Wherever footnotes are on, each is excused; where they are off, there
  ;; are no footnotes, and the two paths agree.
  (is equal '(:footnotes-on (:excused-repeat) :footnotes-off (:pass))
      (pin-outcomes (repeat-pin)))
  (is equal '(:footnotes-on (:excused-dropped) :footnotes-off (:pass))
      (pin-outcomes (dropped-pin)))
  (true (open-counts-zero-p)))

;;; One character changed: the excuses hide nothing outside their shape

(defun changed-character (char)
  "A character other than CHAR: the next digit, for a digit, so a changed
number is still a number; #\\y for #\\x; #\\x for anything else."
  (cond
    ((char<= #\0 char #\9) (digit-char (mod (1+ (digit-char-p char)) 10)))
    ((char= char #\x) #\y)
    (t #\x)))

(defun with-character-changed (string index)
  "A copy of STRING with the character at INDEX changed by CHANGED-CHARACTER."
  (let ((copy (copy-seq string)))
    (setf (char copy index) (changed-character (char string index)))
    copy))

(defun one-character-survivors (markdown)
  "MARKDOWN's outcome under GFM-OPTIONS, computed from its two HTML sides and
its AST with positions, then each index of the tree's HTML at which a
one-character change gives any outcome but :FAIL."
  (multiple-value-bind (cmark tree) (html-oracle-sides markdown (gfm-options))
    (let ((ast (positions-ast markdown (gfm-options))))
      (list :unchanged (html-oracle-outcome cmark tree ast)
            :survivors (loop for index below (length tree)
                             unless (eql :fail (html-oracle-outcome
                                                cmark (with-character-changed tree index) ast))
                               collect index)))))

(define-test no-one-character-change-to-the-repeat-pin-is-excused
  ;; The excuse requires the tree's ids to be fnref-b then fnref-b-2,
  ;; rewrites each to the id cmark gives its reference by source order, and
  ;; compares the rest byte for byte. So every one-character change must
  ;; fail: a repeat number in an id or in a backref's href, the label in
  ;; either, the reference's shown number and the backrefs' indices
  ;; included.
  (is equal '(:unchanged :excused-repeat :survivors ())
      (one-character-survivors (repeat-pin))))

(defun one-character-additions (markdown)
  "MARKDOWN's outcome under GFM-OPTIONS, and each character of cmark's own
HTML for it which, as the tree's whole HTML, gives any outcome but :FAIL."
  (multiple-value-bind (cmark tree) (html-oracle-sides markdown (gfm-options))
    (let ((ast (positions-ast markdown (gfm-options))))
      (list :tree-length (length tree)
            :unchanged (html-oracle-outcome cmark tree ast)
            :survivors (loop for char across (remove-duplicates cmark)
                             unless (eql :fail (html-oracle-outcome cmark (string char) ast))
                               collect char)))))

(define-test the-dropped-pin-fails-with-any-character-added
  ;; Its tree HTML is empty, so the one change it can take is an addition.
  (is equal '(:tree-length 0 :unchanged :excused-dropped :survivors ())
      (one-character-additions (dropped-pin))))

(define-test the-dropped-pin-after-a-kept-footnote-fails-with-any-character-changed
  (is equal '(:unchanged :excused-dropped :survivors ())
      (one-character-survivors (dropped-after-a-kept-footnote))))

;;; A swapped pair of repeat-reference ids still fails here, but not from
;;; the shape check: these three asts already lack the repeat divergence's
;;; shape (no in-definition reference before a body reference to the same
;;; label), so REPEAT-DIVERGENT-LABELS excludes them on its own. Swapping
;;; a label's two ids also always breaks TREE-NUMBERED-P's own fnref-L,
;;; fnref-L-2 order, so a REPEAT-DIVERGENT-LABELS mutated to keep one of
;;; these labels would still pass here, unnoticed: this test no longer
;;; exercises the shape check.
;;; EACH-PINNED-DIVERGENCE-IS-EXCUSED-AS-ITS-OWN-KIND and
;;; THE-REPEAT-EXCUSE-NEEDS-A-BODY-REFERENCE-AFTER-AN-IN-DEFINITION-ONE
;;; guard that; this one now guards TREE-NUMBERED-P's rejection of a
;;; swapped pair, on AST shapes the repeat excuse never reaches.

(defun swapped-substrings (string first second)
  "STRING with each occurrence of FIRST and of SECOND, read left to right,
replaced by the other."
  (with-output-to-string (out)
    (loop with index = 0
          while (< index (length string))
          do (cond
               ((string= first string :start2 index
                                      :end2 (min (length string) (+ index (length first))))
                (write-string second out)
                (incf index (length first)))
               ((string= second string :start2 index
                                       :end2 (min (length string) (+ index (length second))))
                (write-string first out)
                (incf index (length second)))
               (t
                (write-char (char string index) out)
                (incf index))))))

(defun swapped-reference-ids (markdown)
  "For MARKDOWN under GFM-OPTIONS, a tree HTML made from cmark's own by
swapping its reference ids fnref-a and fnref-a-2: whether that changes it;
whether rewriting a's ids by source order alone, without the excuse's
checks, hides the change; and the outcome."
  (multiple-value-bind (cmark tree) (html-oracle-sides markdown (gfm-options))
    (declare (ignore tree))
    (let ((ast (positions-ast markdown (gfm-options)))
          (swapped (swapped-substrings cmark "id=\"fnref-a\"" "id=\"fnref-a-2\"")))
      (list :changed (and (string/= cmark swapped) t)
            :hidden (equal cmark (source-numbered-html swapped ast '("a")))
            :outcome (html-oracle-outcome cmark swapped ast)))))

(defun two-body-references ()
  "Two body references to a, and no reference inside a definition."
  (markdown-lines "x[^a] y[^a]" "" "[^a]: A"))

(defun in-definition-reference-after-the-body-reference ()
  "A body reference to a, then a's definition holding the second: the
source and the tree count them in the same order."
  (markdown-lines "x[^a]" "" "[^a]: A [^a]"))

(defun in-definition-reference-before-another-label ()
  "A body reference to a; b's definition, holding a reference to a; then a
body reference to b. The in-definition reference to a comes before a body
reference, but to b, not to a."
  (markdown-lines "x[^a]" "" "[^b]: [^a]" "" "y[^b]" "" "[^a]: A"))

(define-test a-hidden-mismatch-without-an-earlier-in-definition-reference-fails
  (is equal '(:changed t :hidden t :outcome :fail)
      (swapped-reference-ids (two-body-references))
      "no reference inside a definition")
  (is equal '(:changed t :hidden t :outcome :fail)
      (swapped-reference-ids (in-definition-reference-after-the-body-reference))
      "the in-definition reference comes after the body reference")
  (is equal '(:changed t :hidden t :outcome :fail)
      (swapped-reference-ids (in-definition-reference-before-another-label))
      "the in-definition reference comes before a body reference to another label")
  (true (open-counts-zero-p)))

;;; A dangling footnote the AST still references is not excused as dropped

(defun image-alt-reference ()
  "A footnote referenced only from an image's alt text: cmark writes no id
for a reference inside an image (S_render_node's plain mode, src/html.c),
so its backref dangles, in the tree's HTML as in cmark's."
  (markdown-lines "![x[^a]](u)" "" "[^a]: A"))

(defun image-alt-outcomes ()
  "Property 1's outcome for IMAGE-ALT-REFERENCE; the labels of the items
cmark's HTML has whose every backref dangles; and the outcome when the
tree's HTML is cmark's without them."
  (multiple-value-bind (cmark tree) (html-oracle-sides (image-alt-reference) (gfm-options))
    (declare (ignore tree))
    (multiple-value-bind (without removed) (without-dangling-items cmark)
      (list :property (run-case :html-oracle (image-alt-reference) (gfm-options))
            :dangling removed
            :without-them (html-oracle-outcome
                           cmark without (positions-ast (image-alt-reference) (gfm-options)))))))

(define-test a-dangling-footnote-the-ast-still-references-is-not-excused
  (is equal '(:property :pass :dangling ("a") :without-them :fail) (image-alt-outcomes))
  (true (open-counts-zero-p)))

;;; Property 1 catches a broken tree path

(defun suffixless-reference-id (footnote k)
  "A broken REFERENCE-ID (src/html-tree/convert.lisp): fnref-L for every K,
the -K suffix of every repeat reference dropped."
  (declare (ignore k))
  (concatenate 'string "fnref-" (html-tree::footnote-anchor footnote)))

(defun suffixless-outcomes ()
  "Property 1's outcome for TWO-BODY-REFERENCES, then with REFERENCE-ID
broken by SUFFIXLESS-REFERENCE-ID, with whether its detail names the HTML
difference."
  (let ((unchanged (run-case :html-oracle (two-body-references) (gfm-options))))
    (with-redefined ((html-tree::reference-id #'suffixless-reference-id))
      (multiple-value-bind (outcome detail) (run-case :html-oracle (two-body-references)
                                                      (gfm-options))
        (list :unchanged unchanged
              :broken outcome
              :names-the-html (and (search "html differs from cmark's" detail) t))))))

(define-test property-1-fails-when-repeat-reference-ids-lose-their-suffix
  (is equal '(:unchanged :pass :broken :fail :names-the-html t) (suffixless-outcomes))
  (true (open-counts-zero-p)))

;;; The repeat excuse is exact: a broken REFERENCE-ID fails on the repeat
;;; pin, the one input the excuse covers

(defun off-by-one-reference-id (footnote k)
  "A broken REFERENCE-ID (src/html-tree/convert.lisp): fnref-L for the first
reference, then fnref-L-K+1, every repeat number one too high."
  (if (= k 1)
      (concatenate 'string "fnref-" (html-tree::footnote-anchor footnote))
      (format nil "fnref-~A-~D" (html-tree::footnote-anchor footnote) (1+ k))))

(defun repeat-pin-outcome-with (reference-id)
  "Property 1's outcome for the repeat pin under GFM-OPTIONS, with
REFERENCE-ID installed as HTML-TREE::REFERENCE-ID."
  (call-with-redefined 'html-tree::reference-id reference-id
                       (lambda () (run-case :html-oracle (repeat-pin) (gfm-options)))))

(define-test the-repeat-pin-fails-when-repeat-reference-ids-lose-their-suffix
  (is eql :fail (repeat-pin-outcome-with #'suffixless-reference-id))
  (true (open-counts-zero-p)))

(define-test the-repeat-pin-fails-when-repeat-numbers-are-one-too-high
  (is eql :fail (repeat-pin-outcome-with #'off-by-one-reference-id))
  (true (open-counts-zero-p)))

;;; M3 finding 9's three shapes stay failures (ADR-0014, "Known
;;; divergences")

(defun finding-9-shapes ()
  "M3 finding 9's three inputs, each confirmed with the pinned CLI: a
dangling footnote numbered before a kept one; repeat references in two
definitions, swapped, with no body reference; a footnote referenced from
the body and from a dropped definition."
  (list (format nil "[^a]: [^b]~%~%[^b]: B~%~%x[^c]~%~%[^c]: C~%")
        (format nil "x[^b] y[^a]~%~%[^a]: [^c]~%~%[^b]: [^c]~%~%[^c]: C~%")
        (format nil "[^a]: [^b]~%~%x[^b]~%~%[^b]: text~%")))

(define-test property-1-fails-on-each-of-m3-finding-9s-shapes
  (is equal '(:fail :fail :fail)
      (mapcar (lambda (markdown) (run-case :html-oracle markdown (gfm-options)))
              (finding-9-shapes)))
  (true (open-counts-zero-p)))

(defun source-order-rewrite (markdown label)
  "For MARKDOWN under GFM-OPTIONS: whether the tree's HTML differs from
cmark's; whether rewriting LABEL's reference ids by source order alone,
without the excuse's checks, makes it cmark's; and property 1's outcome."
  (multiple-value-bind (cmark tree) (html-oracle-sides markdown (gfm-options))
    (let ((ast (positions-ast markdown (gfm-options))))
      (list :differs (and (string/= cmark tree) t)
            :hidden (equal cmark (source-numbered-html tree ast (list label)))
            :outcome (html-oracle-outcome cmark tree ast)))))

(define-test the-repeat-excuse-needs-a-body-reference-after-an-in-definition-one
  ;; Rewriting by source order would make both of these cmark's. The repeat
  ;; pin has the shape ADR-0014 documents, and is excused; finding 9's
  ;; second shape has no body reference to c, and stays a failure.
  (is equal '(:differs t :hidden t :outcome :excused-repeat)
      (source-order-rewrite (repeat-pin) "b"))
  (is equal '(:differs t :hidden t :outcome :fail)
      (source-order-rewrite (second (finding-9-shapes)) "c"))
  (true (open-counts-zero-p)))

;;; Property 2 on vocabulary.md, with and without end positions

(defun end-dropping-sourcepos (original)
  "A COPIED-SOURCEPOS (src/native/copy.lisp) that calls ORIGINAL, then drops
the end position, leaving 0:0 in its place."
  (lambda (document node)
    (let ((sourcepos (funcall original document node)))
      (and sourcepos (cons (car sourcepos) (cons 0 0))))))

(defun vocabulary-xml-outcomes ()
  "Property 2's outcome for tests/fixtures/vocabulary.md under GFM-OPTIONS;
then with COPIED-SOURCEPOS dropping end positions, with whether its detail
names the XML difference."
  (let* ((markdown (fixture-string "vocabulary.md"))
         (unchanged (run-case :xml-oracle markdown (gfm-options))))
    (with-redefined ((native::copied-sourcepos (end-dropping-sourcepos #'native::copied-sourcepos)))
      (multiple-value-bind (outcome detail) (run-case :xml-oracle markdown (gfm-options))
        (list :unchanged unchanged
              :without-ends outcome
              :names-the-xml (and (search "xml differs from cmark's" detail) t))))))

(define-test property-2-passes-vocabulary-md-and-fails-without-end-positions
  (is equal '(:unchanged :pass :without-ends :fail :names-the-xml t) (vocabulary-xml-outcomes))
  (true (open-counts-zero-p)))

(define-test property-1-passes-vocabulary-md
  (is eql :pass (run-case :html-oracle (fixture-string "vocabulary.md") (gfm-options))))

;;; The footnote-entity guard both properties share (M2 design finding 16;
;;; ADR-0019): this input must never reach cmark.

(define-test the-footnote-entity-bug-pattern-guards-both-oracle-properties
  ;; :GUARD alone would hold even with the guard run after the native
  ;; calls; the monotonic parser count shows that no parse ran
  ;; (tests/native/guard.lisp).
  (native-state)
  (let ((before (created-parsers)))
    (is eql :guard (run-case :html-oracle "x [&#94;a]" (gfm-options)))
    (is eql :guard (run-case :xml-oracle "x [&#94;a]" (gfm-options)))
    (is = before (created-parsers) "the guarded input reached no parser"))
  (true (open-counts-zero-p)))

;;; Both properties are registered for the two Markdown generators

(define-test the-oracle-properties-are-registered-for-the-markdown-generators
  (is equal '(:syntax-soup :corpus-splices) (property-generators :html-oracle))
  (is equal '(:syntax-soup :corpus-splices) (property-generators :xml-oracle)))

;;; The native property tests are each listed once, however often this file
;;; loads

(defun listings-after-adding-twice (name)
  "How many times *PROPERTY-TESTS* lists NAME after ADD-PROPERTY-TESTS adds
it twice, to a copy, so the real list stays as it is."
  (let ((*property-tests* (copy-list *property-tests*)))
    (add-property-tests (list name))
    (add-property-tests (list name))
    (count name *property-tests*)))

(define-test the-native-property-tests-are-each-listed-once
  (is equal (remove-duplicates *property-tests* :from-end t) *property-tests*)
  (is = 1 (listings-after-adding-twice 'html-oracle-matches-on-syntax-soup))
  (is = 1 (listings-after-adding-twice 'a-test-not-listed-yet)))

;;; The real property tests (M3 plan, Task 9): one Parachute test per
;;; property and generator, one assertion over its summary.

(add-property-tests
 '(html-oracle-matches-on-syntax-soup html-oracle-matches-on-corpus-splices
   xml-oracle-matches-on-syntax-soup xml-oracle-matches-on-corpus-splices))

(define-property-test html-oracle-matches-on-syntax-soup :html-oracle :syntax-soup 44000)
(define-property-test html-oracle-matches-on-corpus-splices :html-oracle :corpus-splices 44000)
(define-property-test xml-oracle-matches-on-syntax-soup :xml-oracle :syntax-soup 46000)
(define-property-test xml-oracle-matches-on-corpus-splices :xml-oracle :corpus-splices 46000)
