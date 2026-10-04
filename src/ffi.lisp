;;;; The cl-commonmark-gfm.ffi package: one CFFI declaration per cmark-gfm
;;;; function the native layer calls. The project compiles no C, so these
;;;; declarations stand in for cmark-gfm's headers. Each is named after its
;;;; C function, with - for _, and typed as its header declares it:
;;;; src/cmark-gfm.h, src/cmark-gfm-extension_api.h and
;;;; extensions/cmark-gfm-core-extensions.h. Every C source path in this
;;;; file is cmark-gfm's, relative to vendor/cmark-gfm/.
;;;;
;;;; - C int and every C enum (cmark_node_type, cmark_list_type,
;;;;   cmark_delim_type) are :INT; size_t is :SIZE; uint16_t is :UINT16.
;;;; - Every pointer is :POINTER, strings cmark returns included: the native
;;;;   layer decodes them itself, and can tell a null from an empty string.
;;;; - The task item's C bool is :UINT8, tested against zero, so only its
;;;;   one defined byte is read. No C compiler checks that width here; the
;;;;   vocabulary fixture's checked and unchecked task items test the read.
;;;;
;;;; No library is named here. The native layer loads the pinned pair by
;;;; absolute path at startup; until then, calling any of these signals an
;;;; error, each Lisp its own: SBCL's UNDEFINED-ALIEN-FUNCTION-ERROR, ECL's
;;;; TYPE-ERROR from FOREIGN-DATA-POINTER, and CCL's "Can't resolve foreign
;;;; symbol". In an ECL program with cmark-gfm linked in, each is a direct C
;;;; call, bound when the program was linked, and nothing is loaded.
;;;;
;;;; Every cmark call compiles here, so this file records the method CFFI
;;;; compiled them with (FFI-METHOD). On ECL, CFFI compiles each call by
;;;; CFFI-SYS:*CFFI-ECL-METHOD* as the call compiles (CFFI's
;;;; src/cffi-ecl.lisp): :DFFI and :DLOPEN look the function up in a library
;;;; loaded at run time, and :C/C++ writes a direct C call, which the linker
;;;; binds. At run time the variable holds ECL's default again, whatever the
;;;; build set, so the record is read as this file compiles, with the calls
;;;; themselves. Startup reads it, so a program whose files were compiled
;;;; under different methods behaves by what its calls do.

(defpackage #:cl-commonmark-gfm.ffi
  (:use #:cl)
  (:export ;; The method these calls were compiled with
           #:ffi-method
           ;; Parser
           #:cmark-parser-new
           #:cmark-parser-attach-syntax-extension
           #:cmark-parser-feed
           #:cmark-parser-finish
           #:cmark-parser-get-syntax-extensions
           #:cmark-parser-free
           #:cmark-node-free
           ;; Walking
           #:cmark-node-first-child
           #:cmark-node-next
           #:cmark-node-parent
           ;; Node facts
           #:cmark-node-get-type
           #:cmark-node-get-type-string
           #:cmark-node-get-syntax-extension
           #:cmark-node-get-literal
           #:cmark-node-get-url
           #:cmark-node-get-title
           #:cmark-node-get-fence-info
           #:cmark-node-get-heading-level
           #:cmark-node-get-list-type
           #:cmark-node-get-list-delim
           #:cmark-node-get-list-start
           #:cmark-node-get-list-tight
           #:cmark-node-get-start-line
           #:cmark-node-get-start-column
           #:cmark-node-get-end-line
           #:cmark-node-get-end-column
           #:cmark-node-parent-footnote-def
           ;; GFM
           #:cmark-gfm-core-extensions-ensure-registered
           #:cmark-find-syntax-extension
           #:cmark-gfm-extensions-get-table-columns
           #:cmark-gfm-extensions-get-table-alignments
           #:cmark-gfm-extensions-get-tasklist-item-checked
           ;; Rendering
           #:cmark-render-html
           #:cmark-render-plaintext
           #:cmark-render-xml
           ;; Other
           #:cmark-version
           #:cmark-version-string
           #:cmark-get-default-mem-allocator))

(in-package #:cl-commonmark-gfm.ffi)

;;; The method these calls were compiled with

(defmacro compiled-ffi-method ()
  "CFFI-SYS:*CFFI-ECL-METHOD*'s value as this macro expands, quoted: on ECL,
the method CFFI compiles foreign calls with then; NIL where CFFI has no
such variable, as on SBCL and CCL. Found by name, so this file needs no
reader conditional. FFI-METHOD's call to it expands as this file compiles,
so its compiled code holds the value as a literal."
  `',(let ((variable (find-symbol "*CFFI-ECL-METHOD*" "CFFI-SYS")))
       (and variable (boundp variable) (symbol-value variable))))

(defun ffi-method ()
  "The method CFFI compiled the cmark calls below with: on ECL, :DFFI,
:DLOPEN or :C/C++, the value CFFI-SYS:*CFFI-ECL-METHOD* had as this file
compiled, kept by COMPILED-FFI-METHOD; NIL on SBCL and CCL. Not the
variable's value now: CFFI sets it again from ECL's features as it loads,
so a linked program would find ECL's default there, :DFFI or :DLOPEN,
whatever its build set. LINKED-METHOD-P tells from it whether the program
is linked, and so whether startup loads anything."
  (compiled-ffi-method))

;;; Parser (src/cmark-gfm.h; src/cmark-gfm-extension_api.h)

(cffi:defcfun ("cmark_parser_new" cmark-parser-new) :pointer
  "cmark_parser *cmark_parser_new(int options)"
  (options :int))

(cffi:defcfun ("cmark_parser_attach_syntax_extension" cmark-parser-attach-syntax-extension) :int
  "int cmark_parser_attach_syntax_extension(cmark_parser *parser,
cmark_syntax_extension *extension). Always returns 1 (src/blocks.c)."
  (parser :pointer)
  (extension :pointer))

(cffi:defcfun ("cmark_parser_feed" cmark-parser-feed) :void
  "void cmark_parser_feed(cmark_parser *parser, const char *buffer, size_t len)"
  (parser :pointer)
  (buffer :pointer)
  (length :size))

(cffi:defcfun ("cmark_parser_finish" cmark-parser-finish) :pointer
  "cmark_node *cmark_parser_finish(cmark_parser *parser)"
  (parser :pointer))

(cffi:defcfun ("cmark_parser_get_syntax_extensions" cmark-parser-get-syntax-extensions) :pointer
  "cmark_llist *cmark_parser_get_syntax_extensions(cmark_parser *parser).
The list belongs to the parser, and is freed with it."
  (parser :pointer))

(cffi:defcfun ("cmark_parser_free" cmark-parser-free) :void
  "void cmark_parser_free(cmark_parser *parser)"
  (parser :pointer))

(cffi:defcfun ("cmark_node_free" cmark-node-free) :void
  "void cmark_node_free(cmark_node *node)"
  (node :pointer))

;;; Walking (src/cmark-gfm.h)

(cffi:defcfun ("cmark_node_first_child" cmark-node-first-child) :pointer
  "cmark_node *cmark_node_first_child(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_next" cmark-node-next) :pointer
  "cmark_node *cmark_node_next(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_parent" cmark-node-parent) :pointer
  "cmark_node *cmark_node_parent(cmark_node *node)"
  (node :pointer))

;;; Node facts (src/cmark-gfm.h; src/cmark-gfm-extension_api.h)

(cffi:defcfun ("cmark_node_get_type" cmark-node-get-type) :int
  "cmark_node_type cmark_node_get_type(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_type_string" cmark-node-get-type-string) :pointer
  "const char *cmark_node_get_type_string(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_syntax_extension" cmark-node-get-syntax-extension) :pointer
  "cmark_syntax_extension *cmark_node_get_syntax_extension(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_literal" cmark-node-get-literal) :pointer
  "const char *cmark_node_get_literal(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_url" cmark-node-get-url) :pointer
  "const char *cmark_node_get_url(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_title" cmark-node-get-title) :pointer
  "const char *cmark_node_get_title(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_fence_info" cmark-node-get-fence-info) :pointer
  "const char *cmark_node_get_fence_info(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_heading_level" cmark-node-get-heading-level) :int
  "int cmark_node_get_heading_level(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_list_type" cmark-node-get-list-type) :int
  "cmark_list_type cmark_node_get_list_type(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_list_delim" cmark-node-get-list-delim) :int
  "cmark_delim_type cmark_node_get_list_delim(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_list_start" cmark-node-get-list-start) :int
  "int cmark_node_get_list_start(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_list_tight" cmark-node-get-list-tight) :int
  "int cmark_node_get_list_tight(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_start_line" cmark-node-get-start-line) :int
  "int cmark_node_get_start_line(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_start_column" cmark-node-get-start-column) :int
  "int cmark_node_get_start_column(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_end_line" cmark-node-get-end-line) :int
  "int cmark_node_get_end_line(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_get_end_column" cmark-node-get-end-column) :int
  "int cmark_node_get_end_column(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_node_parent_footnote_def" cmark-node-parent-footnote-def) :pointer
  "cmark_node *cmark_node_parent_footnote_def(cmark_node *node)"
  (node :pointer))

;;; GFM (extensions/cmark-gfm-core-extensions.h; src/cmark-gfm-extension_api.h)

(cffi:defcfun ("cmark_gfm_core_extensions_ensure_registered"
               cmark-gfm-core-extensions-ensure-registered)
    :void
  "void cmark_gfm_core_extensions_ensure_registered(void). Keeps an unlocked
static flag (extensions/core-extensions.c), so callers serialize it.")

(cffi:defcfun ("cmark_find_syntax_extension" cmark-find-syntax-extension) :pointer
  "cmark_syntax_extension *cmark_find_syntax_extension(const char *name)"
  (name :string))

(cffi:defcfun ("cmark_gfm_extensions_get_table_columns" cmark-gfm-extensions-get-table-columns)
    :uint16
  "uint16_t cmark_gfm_extensions_get_table_columns(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_gfm_extensions_get_table_alignments"
               cmark-gfm-extensions-get-table-alignments)
    :pointer
  "uint8_t *cmark_gfm_extensions_get_table_alignments(cmark_node *node)"
  (node :pointer))

(cffi:defcfun ("cmark_gfm_extensions_get_tasklist_item_checked"
               cmark-gfm-extensions-get-tasklist-item-checked)
    :uint8
  "bool cmark_gfm_extensions_get_tasklist_item_checked(cmark_node *node),
read as its one byte."
  (node :pointer))

;;; Rendering (src/cmark-gfm.h). Each returns a buffer the caller frees,
;;; through the allocator the root was parsed with.

(cffi:defcfun ("cmark_render_html" cmark-render-html) :pointer
  "char *cmark_render_html(cmark_node *root, int options, cmark_llist *extensions)"
  (root :pointer)
  (options :int)
  (extensions :pointer))

(cffi:defcfun ("cmark_render_plaintext" cmark-render-plaintext) :pointer
  "char *cmark_render_plaintext(cmark_node *root, int options, int width)"
  (root :pointer)
  (options :int)
  (width :int))

(cffi:defcfun ("cmark_render_xml" cmark-render-xml) :pointer
  "char *cmark_render_xml(cmark_node *root, int options)"
  (root :pointer)
  (options :int))

;;; Other (src/cmark-gfm.h)

(cffi:defcfun ("cmark_version" cmark-version) :int
  "int cmark_version(void): CMARK_GFM_VERSION, an int packed as (major << 24)
| (minor << 16) | (patch << 8) | gfm (src/cmark-gfm_version.h.in,
src/cmark.c). The comment above this declaration in src/cmark-gfm.h
describes upstream cmark's own layout instead, major in bits 16-23; it
doesn't hold for gfm's packing, so it isn't followed here.")

(cffi:defcfun ("cmark_version_string" cmark-version-string) :pointer
  "const char *cmark_version_string(void)")

(cffi:defcfun ("cmark_get_default_mem_allocator" cmark-get-default-mem-allocator) :pointer
  "cmark_mem *cmark_get_default_mem_allocator(void): a struct of three
function pointers, calloc, realloc and free, in that order (src/cmark-gfm.h).")
