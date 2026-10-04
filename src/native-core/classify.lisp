;;;; CLASSIFY-NODE: the pure core of node classification. The shell reads a
;;;; node's type code, which of the five cached extension pointers (or
;;;; none, or :OTHER for some foreign one) its own extension equals, and,
;;;; for a node with an extension, its type string, and hands the three
;;;; facts here. Extensions are told apart by pointer because cmark-gfm has
;;;; no public function that returns an extension's name. Nothing here
;;;; touches cmark.

(in-package #:cl-commonmark-gfm.native-core)

(defun signal-unsupported-extension-node (type-code)
  "Signal UNSUPPORTED-EXTENSION-NODE for a CMARK_NODE_CUSTOM_BLOCK or
CMARK_NODE_CUSTOM_INLINE node, naming TYPE-CODE."
  (error 'unsupported-extension-node
         :operation 'classify-node
         :datum type-code
         :reason "custom extension node"))

(defun custom-node-type-p (type-code)
  "True when TYPE-CODE is CMARK_NODE_CUSTOM_BLOCK or CMARK_NODE_CUSTOM_INLINE:
cmark's two escape hatches for a syntax extension's own node kinds, written
directly rather than through cmark_syntax_extension_add_node's dynamically
assigned codes (vendor/cmark-gfm/src/syntax_extension.c). This library
represents neither: cmark-gfm's parser and core extensions never build one,
and the AST vocabulary has no kind for them."
  (or (= type-code +cmark-node-custom-block+)
      (= type-code +cmark-node-custom-inline+)))

(defun classify-core-node-type (type-code)
  "Classify TYPE-CODE, a cmark_node_type, for a node with no extension: the
AST vocabulary kind for each of the pin's node types. A TYPE-CODE this
table doesn't cover -- impossible under the pin, since every non-custom
cmark_node_type is listed here, but not ruled out by cmark's ABI in
general -- comes back as :EXTENSION, the same fallback CLASSIFY-NODE uses
for any other node it cannot place safely."
  (cond
    ((= type-code +cmark-node-document+) :document)
    ((= type-code +cmark-node-block-quote+) :block-quote)
    ((= type-code +cmark-node-list+) :list)
    ((= type-code +cmark-node-item+) :item)
    ((= type-code +cmark-node-code-block+) :code-block)
    ((= type-code +cmark-node-html-block+) :html-block)
    ((= type-code +cmark-node-paragraph+) :paragraph)
    ((= type-code +cmark-node-heading+) :heading)
    ((= type-code +cmark-node-thematic-break+) :thematic-break)
    ((= type-code +cmark-node-footnote-definition+) :footnote-definition)
    ((= type-code +cmark-node-text+) :text)
    ((= type-code +cmark-node-softbreak+) :softbreak)
    ((= type-code +cmark-node-linebreak+) :linebreak)
    ((= type-code +cmark-node-code+) :code)
    ((= type-code +cmark-node-html-inline+) :html-inline)
    ((= type-code +cmark-node-emph+) :emph)
    ((= type-code +cmark-node-strong+) :strong)
    ((= type-code +cmark-node-link+) :link)
    ((= type-code +cmark-node-image+) :image)
    ((= type-code +cmark-node-footnote-reference+) :footnote-reference)
    (t :extension)))

(defun classify-table-node (type-string)
  "Classify a node whose extension is the cached :TABLE pointer, by
TYPE-STRING (get_type_string, vendor/cmark-gfm/extensions/table.c):
\"table\", \"table_header\", \"table_row\" and \"table_cell\" give the four
table kinds. Any other string -- impossible under the pin -- gives
:EXTENSION."
  (cond
    ((string= type-string "table") :table)
    ((string= type-string "table_header") :table-header)
    ((string= type-string "table_row") :table-row)
    ((string= type-string "table_cell") :table-cell)
    (t :extension)))

(defun classify-node (type-code extension type-string)
  "Classify a cmark node into its AST vocabulary kind.

TYPE-CODE is its cmark_node_get_type() result. EXTENSION is NIL for a node
with no syntax extension; otherwise the keyword naming which of the five
cached core extensions it carries -- :TABLE, :STRIKETHROUGH, :AUTOLINK,
:TAGFILTER or :TASKLIST -- or :OTHER when its extension pointer is some
other one entirely. TYPE-STRING is its cmark_node_get_type_string() result,
for a node with an extension; the shell passes NIL for a node with none:
a node with no extension is decided by its type code alone, so the shell
skips the foreign calls that read the string.

A CMARK_NODE_CUSTOM_BLOCK or CMARK_NODE_CUSTOM_INLINE node signals
UNSUPPORTED-EXTENSION-NODE, whatever EXTENSION is: this library never
represents a syntax extension's own custom node kinds. Otherwise, with no
extension, the core type code decides. With the :TABLE extension, the type
string picks one of the four table kinds. With :STRIKETHROUGH, the kind is
always :STRIKETHROUGH. With :TASKLIST on a CMARK_NODE_ITEM, the kind is
:TASK-ITEM (open_tasklist_item, vendor/cmark-gfm/extensions/tasklist.c,
marks an ordinary item node with its extension; the item's type code never
changes).

Everything else this function cannot place safely -- :TASKLIST on a node
that isn't an item, a :TABLE node with an unrecognized type string, and any
:AUTOLINK, :TAGFILTER or :OTHER node -- comes back as :EXTENSION. None of
this can happen under the pin: the autolink extension builds plain
CMARK_NODE_LINK nodes and never sets their extension at all
(vendor/cmark-gfm/extensions/autolink.c), and tagfilter never creates
nodes of its own."
  (cond
    ((custom-node-type-p type-code) (signal-unsupported-extension-node type-code))
    ((null extension) (classify-core-node-type type-code))
    ((eql extension :table) (classify-table-node type-string))
    ((eql extension :strikethrough) :strikethrough)
    ((eql extension :tasklist)
     (if (= type-code +cmark-node-item+) :task-item :extension))
    (t :extension)))
