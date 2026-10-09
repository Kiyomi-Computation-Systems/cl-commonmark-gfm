;;;; Unknown extensions: nodes cmark's public API can build that no parse
;;;; under this pin ever produces, exercised through the real copier, the
;;;; output bounds and AST->HTML-TREE.
;;;;
;;;; The seven test-only bindings below live here, not in /ffi: the library
;;;; builds no cmark node itself and binds none of these calls, so nothing
;;;; outside the test suite should call them. Each is named with a %TEST-
;;;; prefix so it can never clash with an /FFI export.

(in-package #:cl-commonmark-gfm.native-tests)

;;; Test-only cmark bindings (src/cmark-gfm-extension_api.h, src/cmark-gfm.h)

(cffi:defcfun ("cmark_syntax_extension_new" %test-syntax-extension-new) :pointer
  "cmark_syntax_extension *cmark_syntax_extension_new(const char *name)
(src/cmark-gfm-extension_api.h): a newly constructed extension, named NAME,
with every callback null."
  (name :string))

(cffi:defcfun ("cmark_syntax_extension_free" %test-syntax-extension-free) :void
  "void cmark_syntax_extension_free(cmark_mem *mem, cmark_syntax_extension
*extension) (src/cmark-gfm-extension_api.h): calls EXTENSION's own free
function only when it has one (src/syntax_extension.c)."
  (mem :pointer)
  (extension :pointer))

(cffi:defcfun ("cmark_syntax_extension_add_node" %test-syntax-extension-add-node) :int
  "cmark_node_type cmark_syntax_extension_add_node(int is_inline)
(src/cmark-gfm-extension_api.h): the next free block or inline type number,
taken from a process-wide counter with no lock (src/syntax_extension.c).
Call at most once per kind, process-wide, and cache the result."
  (is-inline :int))

(cffi:defcfun ("cmark_node_new" %test-node-new) :pointer
  "cmark_node *cmark_node_new(cmark_node_type type) (src/cmark-gfm.h): a new
node of TYPE, with no extension."
  (type :int))

(cffi:defcfun ("cmark_node_new_with_ext" %test-node-new-with-ext) :pointer
  "cmark_node *cmark_node_new_with_ext(cmark_node_type type,
cmark_syntax_extension *extension) (src/cmark-gfm.h): a new node of TYPE,
carrying EXTENSION."
  (type :int)
  (extension :pointer))

(cffi:defcfun ("cmark_node_set_syntax_extension" %test-node-set-syntax-extension) :int
  "int cmark_node_set_syntax_extension(cmark_node *node, cmark_syntax_extension
*extension) (src/cmark-gfm-extension_api.h): sets the extension responsible
for NODE, without changing its cmark_node_type."
  (node :pointer)
  (extension :pointer))

(cffi:defcfun ("cmark_node_append_child" %test-node-append-child) :int
  "int cmark_node_append_child(cmark_node *node, cmark_node *child)
(src/cmark-gfm.h): 1 on success, 0 when NODE cannot contain CHILD
(cmark_node_can_contain_type, src/node.c)."
  (node :pointer)
  (child :pointer))

;;; An extension, made and freed around one call

(defun call-with-unknown-extension (function)
  "Make a syntax extension named \"test-unknown\" with
CMARK_SYNTAX_EXTENSION_NEW, call FUNCTION with it, and free it afterwards
with CMARK_SYNTAX_EXTENSION_FREE and the default allocator, in
UNWIND-PROTECT. Starts cmark up first, since these raw bindings need the
pinned library already loaded. FUNCTION must release any document it
parsed before returning: the extension must outlive every node that
carries it, and the document must not outlive the extension. Checked, not
just required: when FUNCTION returns with any native handle still open
(OPEN-COUNTS-ZERO-P false), this signals an error instead of freeing the
extension out from under a document that may still be alive."
  (native-state)
  (let ((extension (native::with-interrupts-deferred
                      (%test-syntax-extension-new "test-unknown"))))
    (unwind-protect
         (funcall function extension)
      (unless (open-counts-zero-p)
        (error "call-with-unknown-extension: ~S left native handles open, so the extension ~
               can't be freed safely: ~S" function (native-open-counts)))
      (native::with-interrupts-deferred
        (%test-syntax-extension-free (cmark-get-default-mem-allocator) extension)))))

;;; New node types, taken once per process and cached

(defvar *unknown-block-type* nil
  "This process's one new CMARK_NODE_TYPE for a block, taken from
CMARK_SYNTAX_EXTENSION_ADD_NODE the first time UNKNOWN-BLOCK-TYPE is called,
and kept: a second call would take another type number, changing
process-wide state again with no lock (src/syntax_extension.c).")

(defvar *unknown-inline-type* nil
  "As *UNKNOWN-BLOCK-TYPE*, for the one new inline CMARK_NODE_TYPE.")

(defun unknown-block-type ()
  "*UNKNOWN-BLOCK-TYPE*, taking it from CMARK_SYNTAX_EXTENSION_ADD_NODE the
first time."
  (or *unknown-block-type*
      (setf *unknown-block-type*
            (native::with-interrupts-deferred (%test-syntax-extension-add-node 0)))))

(defun unknown-inline-type ()
  "*UNKNOWN-INLINE-TYPE*, as UNKNOWN-BLOCK-TYPE for the inline type."
  (or *unknown-inline-type*
      (setf *unknown-inline-type*
            (native::with-interrupts-deferred (%test-syntax-extension-add-node 1)))))

;;; Markdown and a helper shared by several tests below

(defparameter *extension-paragraph-markdown* "a *b* c"
  "One paragraph of three children: a :TEXT, an :EMPH and a :TEXT.")

(defun paragraph-with-unknown-extension (extension document)
  "DOCUMENT's one paragraph, given EXTENSION with
CMARK_NODE_SET_SYNTAX_EXTENSION, and returned. Its CMARK_NODE_TYPE stays
CMARK_NODE_PARAGRAPH -- CMARK_NODE_SET_SYNTAX_EXTENSION never changes it --
so CMARK_NODE_GET_TYPE_STRING falls back to \"paragraph\": the extension has
no get_type_string_func (src/node.c)."
  (let ((paragraph (first (nodes-of-kind document :paragraph))))
    (is = 1 (native::with-interrupts-deferred
              (%test-node-set-syntax-extension paragraph extension))
        "cmark_node_set_syntax_extension")
    paragraph))

;;; 1. An existing node given an unknown extension

(define-test a-node-given-an-unknown-extension-copies-as-extension
  (call-with-unknown-extension
   (lambda (extension)
     (call-with-native-document *extension-paragraph-markdown* '(:profile :gfm :sourcepos t)
       (lambda (document checked-options)
         (paragraph-with-unknown-extension extension document)
         (let* ((ast (copy-native-tree document checked-options))
                (copied (first (node-children ast))))
           (is eql :extension (node-kind copied))
           (is equal '(:extension-name nil :type-name "paragraph") (node-attributes copied))
           (is = 3 (length (node-children copied)) "its three children")
           (is equal (cons (cons 1 1) (cons 1 7)) (node-sourcepos copied)
               "its position: the whole \"a *b* c\" paragraph"))))))
  (true (open-counts-zero-p)))

;;; 2. Nodes of brand new types

(define-test a-new-block-type-node-copies-as-extension-named-unknown
  (call-with-unknown-extension
   (lambda (extension)
     (call-with-native-document "text" '(:profile :gfm :sourcepos t)
       (lambda (document checked-options)
         (let ((node (native::with-interrupts-deferred
                       (%test-node-new-with-ext (unknown-block-type) extension))))
           (is = 1 (native::with-interrupts-deferred
                     (%test-node-append-child (native-root document) node))
               "cmark_node_append_child onto the document")
           (let* ((ast (copy-native-tree document checked-options))
                  (copied (second (node-children ast))))
             (is eql :extension (node-kind copied))
             (is equal '(:extension-name nil :type-name "<unknown>") (node-attributes copied))
             (false (node-sourcepos copied) "its start line is 0: no position")
             (is equal '() (node-children copied))))))))
  (true (open-counts-zero-p)))

(define-test a-new-inline-type-node-is-kept-among-its-siblings
  (call-with-unknown-extension
   (lambda (extension)
     (call-with-native-document "text" '(:profile :gfm :sourcepos t)
       (lambda (document checked-options)
         (let ((paragraph (first (nodes-of-kind document :paragraph)))
               (node (native::with-interrupts-deferred
                       (%test-node-new-with-ext (unknown-inline-type) extension))))
           (is = 1 (native::with-interrupts-deferred
                     (%test-node-append-child paragraph node))
               "cmark_node_append_child onto the paragraph")
           (let* ((ast (copy-native-tree document checked-options))
                  (copied-paragraph (first (node-children ast)))
                  (children (node-children copied-paragraph)))
             (is = 2 (length children))
             (is eql :text (node-kind (first children)) "the text before it")
             (is string= "text" (node-attribute (first children) :literal))
             (is eql :extension (node-kind (second children)) "last, among its siblings")
             (is equal '(:extension-name nil :type-name "<unknown>")
                 (node-attributes (second children)))))))))
  (true (open-counts-zero-p)))

;;; 3. Custom nodes

;;; Each half below gets its own document: NODES-OF-KIND, like every native
;;; walk, classifies every node it crosses, so a custom node already
;;; appended to a shared document would make the other half's own
;;; NODES-OF-KIND call signal UNSUPPORTED-EXTENSION-NODE in turn, before it
;;; ever reaches the assertion meant to catch it.

(define-test a-custom-block-or-inline-node-makes-the-copier-signal-unsupported-extension-node
  (call-with-native-document "text" '(:profile :gfm :sourcepos t)
    (lambda (document checked-options)
      (let ((block (native::with-interrupts-deferred
                     (%test-node-new +cmark-node-custom-block+))))
        (is = 1 (native::with-interrupts-deferred
                  (%test-node-append-child (native-root document) block))
            "cmark_node_append_child, a custom block onto the document")
        (let ((condition (raised unsupported-extension-node
                                 (copy-native-tree document checked-options)
                                 "a custom block")))
          (when condition
            (is eql 'classify-node (condition-operation condition))
            (is = +cmark-node-custom-block+ (condition-datum condition)))))))
  (call-with-native-document "text" '(:profile :gfm :sourcepos t)
    (lambda (document checked-options)
      (let* ((paragraph (first (nodes-of-kind document :paragraph)))
             (inline (native::with-interrupts-deferred
                       (%test-node-new +cmark-node-custom-inline+))))
        (is = 1 (native::with-interrupts-deferred
                  (%test-node-append-child paragraph inline))
            "cmark_node_append_child, a custom inline onto the paragraph")
        (let ((condition (raised unsupported-extension-node
                                 (copy-native-tree document checked-options)
                                 "a custom inline")))
          (when condition
            (is eql 'classify-node (condition-operation condition))
            (is = +cmark-node-custom-inline+ (condition-datum condition)))))))
  (true (open-counts-zero-p)))

;;; 4. The output bounds

(define-test output-bounds-signal-unsupported-extension-node-for-an-extension-node
  (call-with-unknown-extension
   (lambda (extension)
     (call-with-native-document *extension-paragraph-markdown* '(:profile :gfm :sourcepos t)
       (lambda (document checked-options)
         (paragraph-with-unknown-extension extension document)
         (let ((condition (raised unsupported-extension-node
                                  (html-output-bound document checked-options
                                                     *extension-paragraph-markdown*)
                                  "html-output-bound")))
           (when condition
             (is eql 'html-output-bound (condition-operation condition))
             (is string= "paragraph" (condition-datum condition))))
         (let ((condition (raised unsupported-extension-node
                                  (plaintext-output-bound document checked-options)
                                  "plaintext-output-bound")))
           (when condition
             (is eql 'plaintext-output-bound (condition-operation condition))
             (is string= "paragraph" (condition-datum condition))))))))
  (true (open-counts-zero-p)))

;;; 5. AST->HTML-TREE, on an :EXTENSION copy like test 1's

(define-test ast->html-tree-signals-unsupported-extension-node-for-an-extension-node
  (let ((ast (call-with-unknown-extension
              (lambda (extension)
                (call-with-native-document *extension-paragraph-markdown*
                    '(:profile :gfm :sourcepos t)
                  (lambda (document checked-options)
                    (paragraph-with-unknown-extension extension document)
                    (copy-native-tree document checked-options)))))))
    (let ((condition (raised unsupported-extension-node (ast->html-tree ast))))
      (when condition
        (is eql 'ast->html-tree (condition-operation condition))
        (is eql :extension (node-kind (condition-datum condition))))))
  (true (open-counts-zero-p)))
