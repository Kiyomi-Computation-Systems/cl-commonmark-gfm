;;;; The output bounds' per-node terms: upper bounds on the octets
;;;; cmark_render_html and cmark_render_plaintext write for each node of a
;;;; parsed tree, read off the pinned C source in vendor/cmark-gfm. The
;;;; output-bound walks in /native read each node's facts -- the UTF-8
;;;; octets of the strings it writes, its flags -- and sum these terms
;;;; (src/native/output-bounds.lisp), and the sum is checked against
;;;; *MAX-OUTPUT-OCTETS* before rendering.
;;;;
;;;; Sound first, tight second. A term may count more than cmark writes,
;;;; never less: an undercount lets through a document that can still make
;;;; cmark_strbuf_grow call abort() (vendor/cmark-gfm/src/buffer.c), which
;;;; no Lisp handler can catch. tests/native/limits.lisp checks that neither
;;;; bound falls below what cmark renders. Each term names the C it reads,
;;;; and writes the C's string literals out as Lisp strings: C's \" is
;;;; Lisp's too, and C's \n is #\Newline here.

(in-package #:cl-commonmark-gfm.native-core)

;;; Measuring C string literals

(defmacro literal-octets (&rest parts)
  "The UTF-8 octets of PARTS end to end: the bytes of a C string literal,
transcribed as Lisp strings and forms that make characters. Measured once,
when this file is loaded."
  `(load-time-value (+ ,@(loop for part in parts collect `(utf8-length (string ,part)))) t))

(defun decimal-width (integer)
  "The characters C's printf %d writes for INTEGER: its decimal digits, after
a minus sign when it is negative."
  (let ((width (if (minusp integer) 2 1))
        (magnitude (abs integer)))
    (loop while (>= magnitude 10)
          do (setf magnitude (floor magnitude 10))
             (incf width))
    width))

;;; The escapes and the newlines cmark's HTML renderer writes

(defconstant +escape-factor+ 6
  "The most octets escape_html (vendor/cmark-gfm/src/html.c) writes for one
byte: houdini_escape_html0 (vendor/cmark-gfm/src/houdini_html_e.c), called
with secure 0, turns \" into &quot;, 6. Its other escapes are &amp; in 5,
and &lt; and &gt; in 4; ' and / pass through.")

(defconstant +href-escape-factor+ 6
  "The most octets houdini_escape_href
(vendor/cmark-gfm/src/houdini_href_e.c) writes for one byte: ' becomes
&#x27;, 6. & becomes &amp;, 5, and every other byte outside HREF_SAFE %XX,
3: a percent-escape is not its worst case.")

(defconstant +cr-octets+ 1
  "What cmark_html_render_cr (vendor/cmark-gfm/src/html.h) writes: a
newline, unless the buffer is empty or already ends in one. Counted as
written every time.")

(defun escaped-octets (octets)
  "The most escape_html writes for OCTETS bytes."
  (* +escape-factor+ octets))

(defun href-octets (octets)
  "The most houdini_escape_href writes for OCTETS bytes."
  (* +href-escape-factor+ octets))

(defun html-sourcepos-octets (start-line start-column end-line end-column)
  "What cmark_html_render_sourcepos (vendor/cmark-gfm/src/html.h) writes
under CMARK_OPT_SOURCEPOS: \" data-sourcepos=\\\"%d:%d-%d:%d\\\"\" of a
node's four positions, as cmark_node_get_start_line and the others return
them. Its snprintf buffer is 100 bytes, and the attribute with four ints
takes at most 65, so it never truncates.

Every HTML term below that takes SOURCEPOS takes this, for a node of its
kind, under :SOURCEPOS T, and 0 without."
  (+ (literal-octets " data-sourcepos=\"" ":" "-" ":" "\"")
     (decimal-width start-line) (decimal-width start-column)
     (decimal-width end-line) (decimal-width end-column)))

;;; HTML: the blocks (S_render_node, vendor/cmark-gfm/src/html.c). The
;;; node's own markup, entering and leaving, its children aside.

(defun html-block-quote-bound (sourcepos)
  "A block quote: entering, a cr, \"<blockquote\", data-sourcepos, \">\\n\";
leaving, a cr and \"</blockquote>\\n\"."
  (+ +cr-octets+ (literal-octets "<blockquote") sourcepos (literal-octets ">" #\Newline)
     +cr-octets+ (literal-octets "</blockquote>" #\Newline)))

(defun html-list-bound (type start sourcepos)
  "A list of TYPE, :BULLET or :ORDERED, starting at START: entering, a cr,
then \"<ul\" for a bullet list, \"<ol\" for an ordered one starting at 1, and
\"<ol start=\\\"%d\\\"\" for any other, then data-sourcepos and \">\\n\";
leaving, \"</ul>\\n\" or \"</ol>\\n\". The snprintf buffer of BUFFER_SIZE,
100 bytes, holds any int's start attribute."
  (+ +cr-octets+
     (ecase type
       (:bullet (literal-octets "<ul"))
       (:ordered (if (= start 1)
                     (literal-octets "<ol")
                     (+ (literal-octets "<ol start=\"") (decimal-width start)
                        (literal-octets "\"")))))
     sourcepos
     (literal-octets ">" #\Newline)
     (ecase type
       (:bullet (literal-octets "</ul>" #\Newline))
       (:ordered (literal-octets "</ol>" #\Newline)))))

(defun html-item-bound (sourcepos)
  "A list item: entering, a cr, \"<li\", data-sourcepos, \">\"; leaving,
\"</li>\\n\"."
  (+ +cr-octets+ (literal-octets "<li") sourcepos (literal-octets ">")
     (literal-octets "</li>" #\Newline)))

(defun html-task-item-bound (checked sourcepos)
  "A task item (html_render, vendor/cmark-gfm/extensions/tasklist.c):
entering, a cr, \"<li\", data-sourcepos, \">\", then its checkbox, CHECKED
or not; leaving, \"</li>\\n\"."
  (+ +cr-octets+ (literal-octets "<li") sourcepos (literal-octets ">")
     (if checked
         (literal-octets "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ")
         (literal-octets "<input type=\"checkbox\" disabled=\"\" /> "))
     (literal-octets "</li>" #\Newline)))

(defun html-heading-bound (sourcepos)
  "A heading: entering, a cr, \"<h0\" with its level's digit for the 0,
data-sourcepos, \">\"; leaving, \"</h0\", again with the digit, and
\">\\n\"."
  (+ +cr-octets+ (literal-octets "<h0") sourcepos (literal-octets ">")
     (literal-octets "</h0") (literal-octets ">" #\Newline)))

(defun cmark-space-p (char)
  "True when CHAR is one cmark_isspace (vendor/cmark-gfm/src/cmark_ctype.c)
counts as whitespace: tab, line feed, carriage return or space. Not a
vertical tab or a form feed."
  (find char '(#\Tab #\Newline #\Return #\Space) :test #'char=))

(defun code-block-language-octets (info)
  "The UTF-8 octets of the first word of INFO, a code block's info string:
the language S_render_node (vendor/cmark-gfm/src/html.c) writes in its
class, everything up to the first CMARK-SPACE-P character."
  (utf8-length (subseq info 0 (or (position-if #'cmark-space-p info) (length info)))))

(defun html-code-block-bound (info language literal sourcepos)
  "A code block whose info string is INFO octets, the first word of it
LANGUAGE octets (CODE-BLOCK-LANGUAGE-OCTETS), and whose literal is LITERAL
octets, which cmark's iterator visits once, as a leaf: a cr; with no info
string, \"<pre\", data-sourcepos and \"><code>\"; with one, \"<pre\",
data-sourcepos, \"><code class=\\\"language-\", its first word escaped, and
\"\\\">\"; then the literal escaped, and \"</code></pre>\\n\".
HTML-OPTION-BITS never sets CMARK_OPT_GITHUB_PRE_LANG or
CMARK_OPT_FULL_INFO_STRING, the bits that would change this markup and
write the rest of the info string."
  (+ +cr-octets+ (literal-octets "<pre") sourcepos
     (if (zerop info)
         (literal-octets "><code>")
         (+ (literal-octets "><code class=\"language-") (escaped-octets language)
            (literal-octets "\">")))
     (escaped-octets literal)
     (literal-octets "</code></pre>" #\Newline)))

(defun html-html-block-bound (literal less-thans unsafe tagfilter)
  "Raw HTML, a block of LITERAL octets holding LESS-THANS < characters,
which cmark's iterator visits once, as a leaf: a cr, then, without UNSAFE
\(CMARK_OPT_UNSAFE, from :UNSAFE-HTML T), \"<!-- raw HTML omitted -->\";
with it and TAGFILTER, true when the tagfilter extension is attached,
filter_html_block's copy, which writes each < as < or &lt; and every other
byte once; with UNSAFE alone, the literal; then a cr."
  (+ +cr-octets+
     (cond
       ((not unsafe) (literal-octets "<!-- raw HTML omitted -->"))
       (tagfilter (+ literal (* less-thans (1- (literal-octets "&lt;")))))
       (t literal))
     +cr-octets+))

(defun html-thematic-break-bound (sourcepos)
  "A thematic break, a leaf: a cr, \"<hr\", data-sourcepos, \" />\\n\"."
  (+ +cr-octets+ (literal-octets "<hr") sourcepos (literal-octets " />" #\Newline)))

(defun html-paragraph-bound (tight sourcepos)
  "A paragraph: nothing when TIGHT, true when its grandparent is a tight
list; otherwise, entering, a cr, \"<p\", data-sourcepos, \">\", and leaving,
\"</p>\\n\". The space and backref a footnote definition's last paragraph
adds are HTML-FOOTNOTE-DEFINITION-BOUND's."
  (if tight
      0
      (+ +cr-octets+ (literal-octets "<p") sourcepos (literal-octets ">")
         (literal-octets "</p>" #\Newline))))

;;; HTML: the inlines. Inside an image, S_render_node writes its children
;;; as alt text, in plain mode: text, code and raw HTML escaped, a break
;;; as a space, and nothing else. Every term below but raw HTML's already
;;; counts at least that much.

(defun html-text-bound (literal)
  "Text of LITERAL octets: escaped."
  (escaped-octets literal))

(defun html-softbreak-bound (softbreak)
  "A softbreak under :SOFTBREAK SOFTBREAK: \"<br />\\n\" for :BR, which sets
CMARK_OPT_HARDBREAKS; a space for :SPACE, CMARK_OPT_NOBREAKS; a newline for
:NEWLINE."
  (ecase softbreak
    (:br (literal-octets "<br />" #\Newline))
    (:space (literal-octets " "))
    (:newline (literal-octets #\Newline))))

(defun html-linebreak-bound ()
  "A hard line break: \"<br />\\n\"."
  (literal-octets "<br />" #\Newline))

(defun html-code-bound (literal)
  "A code span of LITERAL octets: \"<code>\", the literal escaped,
\"</code>\"."
  (+ (literal-octets "<code>") (escaped-octets literal) (literal-octets "</code>")))

(defun html-html-inline-bound (literal unsafe tagfilter plain)
  "Raw inline HTML of LITERAL octets: in an image's alt text, PLAIN, the
literal escaped whatever the options; otherwise, without UNSAFE, \"<!-- raw
HTML omitted -->\"; with it, the literal, or, when TAGFILTER's filter
rejects it, \"&lt;\" then all of it but its first byte."
  (cond
    (plain (escaped-octets literal))
    ((not unsafe) (literal-octets "<!-- raw HTML omitted -->"))
    (tagfilter (+ literal (1- (literal-octets "&lt;"))))
    (t literal)))

(defun html-emph-bound ()
  "Emphasis: \"<em>\" and \"</em>\"."
  (+ (literal-octets "<em>") (literal-octets "</em>")))

(defun html-strong-bound (nested)
  "Strong emphasis: \"<strong>\" and \"</strong>\", or nothing when NESTED,
true when its parent is strong emphasis too."
  (if nested
      0
      (+ (literal-octets "<strong>") (literal-octets "</strong>"))))

(defun html-strikethrough-bound ()
  "A strikethrough (html_render, vendor/cmark-gfm/extensions/strikethrough.c):
\"<del>\" and \"</del>\"."
  (+ (literal-octets "<del>") (literal-octets "</del>")))

(defun html-link-bound (url title)
  "A link whose destination is URL octets and title TITLE octets: entering,
\"<a href=\\\"\", the destination href-escaped, then for a title
\"\\\" title=\\\"\" and the title escaped, then \"\\\">\"; leaving, \"</a>\".
Without CMARK_OPT_UNSAFE a dangerous destination is left out; it is
counted anyway."
  (+ (literal-octets "<a href=\"") (href-octets url)
     (if (plusp title)
         (+ (literal-octets "\" title=\"") (escaped-octets title))
         0)
     (literal-octets "\">")
     (literal-octets "</a>")))

(defun html-image-bound (url title)
  "An image whose source is URL octets and title TITLE octets: entering,
\"<img src=\\\"\", the source href-escaped, \"\\\" alt=\\\"\", then its
children as alt text; leaving, for a title \"\\\" title=\\\"\" and the title
escaped, then \"\\\" />\". Without CMARK_OPT_UNSAFE a dangerous source is left
out; it is counted anyway."
  (+ (literal-octets "<img src=\"") (href-octets url) (literal-octets "\" alt=\"")
     (if (plusp title)
         (+ (literal-octets "\" title=\"") (escaped-octets title))
         0)
     (literal-octets "\" />")))

;;; HTML: tables (html_render, vendor/cmark-gfm/extensions/table.c)

(defun html-table-bound (sourcepos)
  "A table: entering, a cr, \"<table\", data-sourcepos, \">\"; leaving, a cr,
\"</tbody>\" and a cr when it has a body, then a cr, \"</table>\" and a cr.
The \"<tbody>\" and cr its first body row writes are counted here, once."
  (+ +cr-octets+ (literal-octets "<table") sourcepos (literal-octets ">")
     (literal-octets "<tbody>") +cr-octets+
     +cr-octets+ (literal-octets "</tbody>") +cr-octets+
     +cr-octets+ (literal-octets "</table>") +cr-octets+))

(defun html-table-header-bound (sourcepos)
  "A table's header row: entering, a cr, \"<thead>\", a cr, \"<tr\",
data-sourcepos, \">\"; leaving, a cr, \"</tr>\", a cr, \"</thead>\"."
  (+ +cr-octets+ (literal-octets "<thead>") +cr-octets+
     (literal-octets "<tr") sourcepos (literal-octets ">")
     +cr-octets+ (literal-octets "</tr>") +cr-octets+ (literal-octets "</thead>")))

(defun html-table-row-bound (sourcepos)
  "A table's body row: entering, a cr, \"<tr\", data-sourcepos, \">\";
leaving, a cr and \"</tr>\". The first one's \"<tbody>\" is
HTML-TABLE-BOUND's."
  (+ +cr-octets+ (literal-octets "<tr") sourcepos (literal-octets ">")
     +cr-octets+ (literal-octets "</tr>")))

(defun html-table-cell-bound (align sourcepos)
  "A table cell aligned ALIGN, :LEFT, :CENTER, :RIGHT or NIL: entering, a
cr, \"<th\" or \"<td\", the alignment, data-sourcepos, \">\"; leaving,
\"</th>\" or \"</td>\". The alignment is \" align=\\\"\", the word, and
\"\\\"\" (html_table_add_align): HTML-OPTION-BITS never sets
CMARK_OPT_TABLE_PREFER_STYLE_ATTRIBUTES, which would write a style
attribute instead."
  (+ +cr-octets+ (literal-octets "<td")
     (ecase align
       ((nil) 0)
       (:left (literal-octets " align=\"" "left" "\""))
       (:center (literal-octets " align=\"" "center" "\""))
       (:right (literal-octets " align=\"" "right" "\"")))
     sourcepos (literal-octets ">") (literal-octets "</td>")))

;;; HTML: footnotes (S_render_node, S_put_footnote_backref and
;;; cmark_render_html, vendor/cmark-gfm/src/html.c). A footnote's label
;;; appears once in its definition, twice in each reference, and once in
;;; each backref; and its definition writes a backref for each reference
;;; process_footnotes (vendor/cmark-gfm/src/blocks.c) counted for it -- its
;;; def_count -- whether or not the parsed tree still holds that reference.
;;; A reference in a definition that nothing references, or in a duplicate
;;; definition, is counted, then dropped with its definition. So the repeat
;;; backrefs are bounded from the input (FOOTNOTE-REFERENCE-BOUND), not
;;; from the tree.

(defun html-first-backref-bound (label number)
  "The first backref S_put_footnote_backref writes for a footnote
definition labelled LABEL octets, the NUMBERth rendered: \"<a
href=\\\"#fnref-\", the label href-escaped, the class and idx attributes,
NUMBER, the aria-label, NUMBER again, and \"\\\">\", U+21A9 in 3 octets,
\"</a>\"."
  (+ (literal-octets "<a href=\"#fnref-") (href-octets label)
     (literal-octets
      "\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"")
     (decimal-width number)
     (literal-octets "\" aria-label=\"Back to reference ")
     (decimal-width number)
     (literal-octets "\">" (code-char #x21A9) "</a>")))

(defun html-footnote-definition-bound (label number)
  "A footnote definition labelled LABEL octets, as written, the NUMBERth
rendered: entering, \"<li id=\\\"fn-\", the label href-escaped and
\"\\\">\\n\"; its first backref, which S_put_footnote_backref writes once,
in its last paragraph or on leaving it, however many references it has;
the space that paragraph writes before the backref, or the newline after
one written on leaving, both counted; leaving, \"</li>\\n\". Its repeat
backrefs are HTML-FOOTNOTE-BACKREFS-BOUND's."
  (+ (literal-octets "<li id=\"fn-") (href-octets label) (literal-octets "\">" #\Newline)
     (html-first-backref-bound label number)
     (literal-octets " ") (literal-octets #\Newline)
     (literal-octets "</li>" #\Newline)))

(defun html-footnote-reference-bound (label number suffix)
  "A footnote reference whose definition's label is LABEL octets, whose own
literal, its definition's number, is NUMBER octets, and whose index suffix
is SUFFIX octets: \"<sup class=\\\"footnote-ref\\\"><a href=\\\"#fn-\", the
label href-escaped, \"\\\" id=\\\"fnref-\", the label again, the suffix,
\"\\\" data-footnote-ref>\", the number, \"</a></sup>\". The suffix, \"-\"
and the reference's index, appears from a definition's second reference on.
The number holds only the digits process_footnotes printed with %d, which
houdini_escape_href leaves as they are."
  (+ (literal-octets "<sup class=\"footnote-ref\"><a href=\"#fn-") (href-octets label)
     (literal-octets "\" id=\"fnref-") (href-octets label)
     suffix
     (literal-octets "\" data-footnote-ref>") number
     (literal-octets "</a></sup>")))

(defun html-footnote-backref-bound (label index number)
  "The INDEXth backref, from the second on, that S_put_footnote_backref
writes for a definition labelled LABEL octets, the NUMBERth rendered:
\" <a href=\\\"#fnref-\", the label href-escaped, \"-\" and INDEX; the idx
attribute, NUMBER, \"-\" and INDEX; the aria-label, NUMBER, \"-\" and INDEX;
\"\\\">\", U+21A9 in 3 octets, \"<sup class=\\\"footnote-ref\\\">\", INDEX,
\"</sup></a>\"."
  (+ (literal-octets " <a href=\"#fnref-") (href-octets label)
     (literal-octets "-") (decimal-width index)
     (literal-octets
      "\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"")
     (decimal-width number) (literal-octets "-") (decimal-width index)
     (literal-octets "\" aria-label=\"Back to reference ")
     (decimal-width number) (literal-octets "-") (decimal-width index)
     (literal-octets "\">" (code-char #x21A9) "<sup class=\"footnote-ref\">")
     (decimal-width index)
     (literal-octets "</sup></a>")))

(defun html-footnote-section-bound ()
  "What wraps the footnote definitions once there is one: S_render_node's
\"<section class=\\\"footnotes\\\" data-footnotes>\\n<ol>\\n\" before the
first, and cmark_render_html's \"</ol>\\n</section>\\n\" at the end."
  (+ (literal-octets "<section class=\"footnotes\" data-footnotes>" #\Newline
                     "<ol>" #\Newline)
     (literal-octets "</ol>" #\Newline "</section>" #\Newline)))

(defun html-footnote-suffix-bound (candidates definitions)
  "The longest index suffix any footnote reference can carry, from an input
holding CANDIDATES brackets that can open a reference
\(FOOTNOTE-REFERENCE-BOUND) and a tree holding DEFINITIONS definitions.
process_footnotes numbers a definition's references 1, 2 and on, counting
those in definitions it then drops, and every definition it keeps has at
least one: so no index passes CANDIDATES - DEFINITIONS + 1. Only an index
past 1 writes its suffix, \"-\" and its digits."
  (let ((largest (1+ (- candidates definitions))))
    (if (> largest 1)
        (+ (literal-octets "-") (decimal-width largest))
        0)))

(defun html-footnote-backrefs-bound (candidates definitions longest-label)
  "Every repeat backref -- each past a definition's first -- for a tree of
DEFINITIONS footnote definitions, the longest label LONGEST-LABEL octets,
from an input holding CANDIDATES brackets that can open a reference. A
definition writes a backref for each reference process_footnotes counted
for it, its def_count, dropped ones included. Their counts total at most
CANDIDATES, and each is at least 1: at most CANDIDATES - DEFINITIONS
repeats, each at most HTML-FOOTNOTE-BACKREF-BOUND's for the longest label,
the largest index, and the last definition's number."
  (let ((repeats (- candidates definitions)))
    (if (plusp repeats)
        (* repeats (html-footnote-backref-bound longest-label (1+ repeats) definitions))
        0)))

(defun footnote-reference-bound (string)
  "An upper bound on the footnote references cmark creates while parsing
STRING: the [ characters followed at once by ^, \\ or &.
handle_close_bracket (vendor/cmark-gfm/src/inlines.c) makes a reference of
a bracket whose next inline is text starting with ^. That text starts with
the byte after the [, so the byte is ^ itself, a backslash escape of it, or
an entity \(&#94;, &Hat;). Each reference takes its own [. cmark strips
container prefixes only at line starts, and a table cell's unescaped \\|
only turns a backslash after a [ into a pipe, so no [ meets a ^ in an
inline that it didn't meet in STRING. [, ^, \\ and & are ASCII: a character
of STRING is a byte of its UTF-8."
  (let ((count 0))
    (loop for index from 0 below (1- (length string))
          do (when (and (char= (char string index) #\[)
                        (find (char string (1+ index)) "^\\&" :test #'char=))
               (incf count)))
    count))

;;; Plaintext (cmark_render_plaintext: S_render_node,
;;; vendor/cmark-gfm/src/plaintext.c; cmark_render and S_out,
;;; vendor/cmark-gfm/src/render.c; the extensions' plaintext renderers)
;;;
;;; Plaintext escapes almost nothing, but repeats a prefix of spaces at the
;;; start of every line: each enclosing list item's marker width, 2 for a
;;; task item and 4 for a footnote definition. A line starts after a
;;; newline request -- CR() and BLANKLINE() set need_cr, which the next
;;; S_out call writes as up to two newlines and the prefix -- after a
;;; literal newline, and, with :WIDTH above 0, at a wrap or a space at the
;;; start of a line. A node's events become steps: :REQUEST for each CR()
;;; or BLANKLINE(), and (:OUT OCTETS SPACES NEWLINES ESCAPES WRAP) for each
;;; S_out call. The prefix only grows just after an S_out call (an item's
;;; marker, a task item's, a footnote definition's label), so whatever a
;;; request or a breakable space later writes is at most the prefix in
;;; effect when it was made.

(defun plaintext-item-marker-width (type index)
  "The marker a list item of a TYPE list writes, and the width it adds to
the prefix: \"  - \" for :BULLET; for :ORDERED, \"%d%s%s\" of its INDEX
\(cmark_render numbers the items from their list's start), \".\" or \")\",
and two spaces below 10, one from 10."
  (ecase type
    (:bullet (literal-octets "  - "))
    (:ordered (+ (decimal-width index) (literal-octets ".")
                 (if (< index 10) (literal-octets "  ") (literal-octets " "))))))

(defun plaintext-prefix-width (kind marker-width)
  "How much a node of KIND widens the prefix for its children: an item by
its MARKER-WIDTH; a task item by the \"  \" of commonmark_render
(vendor/cmark-gfm/extensions/tasklist.c); a footnote definition by the
\"    \" of S_render_node (vendor/cmark-gfm/src/plaintext.c); anything else
not at all."
  (ecase kind
    (:item marker-width)
    (:task-item (literal-octets "  "))
    (:footnote-definition (literal-octets "    "))
    ((:document :block-quote :list :code-block :html-block :paragraph :heading
      :thematic-break :text :softbreak :linebreak :code :html-inline :emph :strong
      :link :image :footnote-reference :strikethrough :table :table-header :table-row
      :table-cell)
     0)))

(defun plaintext-out-bound (octets prefix pending &key (spaces 0) (newlines 0) (escapes 0) wrap)
  "An upper bound on what one S_out call writes for a string of OCTETS
octets holding SPACES spaces and NEWLINES newlines, with a prefix of PREFIX
octets, when PENDING is true because a newline request waits:
- the request: at most two newlines and the prefix, then the prefix again
  before the string's first byte, which starts a line;
- the string, a byte for a byte, and a backslash before each of its ESCAPES
  characters, those the table extension's commonmark_escape_func flags;
- the prefix after each literal newline, at the start of the line it
  begins;
- under WRAP, the prefix for each space: one at the start of a line writes
  the prefix and nothing else, and any other can become the break a later
  wrap turns into a newline and the prefix. A wrap moves the bytes after
  its break, and adds only the prefix."
  (+ (if pending (+ 2 (* 2 prefix)) 0)
     octets
     escapes
     (* newlines prefix)
     (if wrap (* spaces prefix) 0)))

(defun plaintext-out (octets &key (spaces 0) (newlines 0) (escapes 0) wrap)
  "A step for one S_out call of a string of OCTETS octets: see
PLAINTEXT-OUT-BOUND."
  (list :out octets spaces newlines escapes wrap))

(defun plaintext-event-steps (event kind &key (octets 0) (spaces 0) (newlines 0) (escapes 0)
                                              wrap (marker-width 0) (number 0) (columns 0))
  "The steps cmark_render_plaintext takes for EVENT, :ENTER or :EXIT, of a
node of KIND, in order: :REQUEST for each CR() or BLANKLINE(), and a
PLAINTEXT-OUT for each S_out call. The facts each kind takes:
- :TEXT and :CODE: their literal's OCTETS, SPACES, NEWLINES and ESCAPES,
  and WRAP, true when wrapping is on;
- :CODE-BLOCK: its literal's OCTETS and NEWLINES;
- :SOFTBREAK: WRAP;
- :ITEM: its MARKER-WIDTH;
- :FOOTNOTE-REFERENCE: its literal's OCTETS, its definition's number;
- :FOOTNOTE-DEFINITION: its NUMBER, its place among the definitions;
- :TABLE-HEADER: its table's COLUMNS.
A request cmark makes only sometimes, such as a list's CR() before a
following list or code block, is always taken: a request only ever adds."
  (let ((entering (eql event :enter)))
    (flet ((when-entering (&rest steps) (if entering steps '()))
           (when-leaving (&rest steps) (if entering '() steps)))
      (ecase kind
        ((:document :block-quote :html-block :html-inline :emph :strong :link :image) '())
        ;; CR() leaving a list; BLANKLINE() leaving a heading or a paragraph
        ((:list :heading :paragraph) (when-leaving :request))
        ;; The marker, then the prefix grows; leaving, CR()
        (:item (if entering
                   (list (plaintext-out marker-width))
                   (list :request)))
        ;; commonmark_render (vendor/cmark-gfm/extensions/tasklist.c): CR(),
        ;; "- [x] " or "- [ ] ", then the prefix grows; leaving, CR()
        (:task-item (if entering
                        (list :request (plaintext-out (literal-octets "- [x] ")))
                        (list :request)))
        ;; BLANKLINE() unless first in an item, the literal, BLANKLINE()
        (:code-block (when-entering :request (plaintext-out octets :newlines newlines) :request))
        ((:thematic-break :linebreak) (when-entering :request))
        ((:text :code)
         (when-entering (plaintext-out octets :spaces spaces :newlines newlines
                                              :escapes escapes :wrap wrap)))
        ;; CR(), or a space: both counted
        (:softbreak
         (when-entering :request (plaintext-out (literal-octets " ") :spaces 1 :wrap wrap)))
        (:footnote-reference
         (when-entering (plaintext-out (literal-octets "[^"))
                        (plaintext-out octets)
                        (plaintext-out (literal-octets "]"))))
        ;; Then the prefix grows
        (:footnote-definition
         (when-entering (plaintext-out (literal-octets "[^"))
                        (plaintext-out (decimal-width number))
                        (plaintext-out (literal-octets "]: "))))
        ;; plaintext_render (vendor/cmark-gfm/extensions/strikethrough.c):
        ;; "~" entering and leaving
        (:strikethrough (list (plaintext-out (literal-octets "~"))))
        ;; commonmark_render (vendor/cmark-gfm/extensions/table.c):
        ;; BLANKLINE() entering and leaving a table; CR() and "|" entering a
        ;; row; " " entering a cell and " |" leaving it; after the header's
        ;; last cell, CR(), "|", " --- |" or its aligned form per column,
        ;; CR()
        (:table (list :request))
        (:table-header (if entering
                           (list :request (plaintext-out (literal-octets "|")))
                           (list :request (plaintext-out (literal-octets "|"))
                                 (plaintext-out (* columns (literal-octets " --- |")))
                                 :request)))
        (:table-row (when-entering :request (plaintext-out (literal-octets "|"))))
        (:table-cell (list (plaintext-out (if entering
                                              (literal-octets " ")
                                              (literal-octets " |")))))))))

(defun plaintext-steps-bound (steps prefix pending)
  "An upper bound on what STEPS write with a prefix of PREFIX octets, when
PENDING is true because a newline request waits, and whether one waits
after them: (VALUES OCTETS PENDING). A :REQUEST leaves one waiting, and the
next S_out call writes it."
  (let ((total 0))
    (dolist (step steps)
      (if (eql step :request)
          (setf pending t)
          (destructuring-bind (octets spaces newlines escapes wrap) (rest step)
            (incf total (plaintext-out-bound octets prefix pending
                                             :spaces spaces :newlines newlines
                                             :escapes escapes :wrap wrap))
            (setf pending nil))))
    (values total pending)))
