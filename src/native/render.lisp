;;;; Rendering a live document. cmark renders into a buffer it allocates;
;;;; this file copies the buffer's octets out, frees it through the default
;;;; allocator's free, the third slot of its cmark_mem, never with
;;;; CFFI:FOREIGN-FREE, then decodes the octets into a Lisp string. From the
;;;; render to the free, interrupts are deferred: no interrupt runs inside
;;;; the renderer, and none can lose the buffer before it is freed. The
;;;; decoding runs after, interruptible.

(in-package #:cl-commonmark-gfm.native)

;;; Wrappers a test can redefine, NOTINLINE as in document.lisp. Each
;;; returns the buffer, or null.

(declaim (notinline %render-html %render-plaintext %render-xml))

(defun %render-html (root options extensions)
  "Call cmark_render_html on ROOT with OPTIONS and the EXTENSIONS list,
with interrupts deferred."
  (with-interrupts-deferred
    (cmark-render-html root options extensions)))

(defun %render-plaintext (root options width)
  "Call cmark_render_plaintext on ROOT with OPTIONS and WIDTH, with
interrupts deferred."
  (with-interrupts-deferred
    (cmark-render-plaintext root options width)))

(defun %render-xml (root options)
  "Call cmark_render_xml on ROOT with OPTIONS, with interrupts deferred."
  (with-interrupts-deferred
    (cmark-render-xml root options)))

;;; Buffers

(defun free-buffer (state buffer)
  "Free BUFFER through STATE's allocator free, and count it closed, with
interrupts deferred."
  (with-interrupts-deferred
    (cffi:foreign-funcall-pointer (state-free state) () :pointer buffer :void)
    (note-buffer-freed)))

(defun rendered-octets (document render operation)
  "The octets one of cmark's renderers writes for DOCUMENT. RENDER, a
function of no arguments, calls the renderer and returns its buffer. The
buffer is counted open, its octets are copied into a fresh vector, and it
is freed, in UNWIND-PROTECT. RENDER is called, and the buffer copied and
freed, with interrupts deferred, so no interrupt can lose the buffer. A
null buffer signals NATIVE-RENDER-ERROR naming OPERATION."
  (or (with-interrupts-deferred
        (let ((buffer (funcall render)))
          (unless (cffi:null-pointer-p buffer)
            (note-buffer-created)
            (unwind-protect
                 (foreign-octets buffer)
              (free-buffer (document-state document) buffer)))))
      (error 'native-render-error
             :operation operation
             :reason "cmark's renderer returned no buffer")))

(defun decoded-render (octets)
  "OCTETS, which a renderer wrote, decoded by DECODE-UTF8 into a fresh
string, and as a second value how many there were."
  (values (decode-utf8 octets) (length octets)))

;;; The three renderers

(defun render-html (document checked-options)
  "DOCUMENT rendered by cmark_render_html with CHECKED-OPTIONS' HTML bits,
as a string, and as a second value the octets cmark wrote: what
HTML-OUTPUT-BOUND bounds. The string can be longer in UTF-8, where cmark
wrote bytes that aren't UTF-8 (DECODE-UTF8). The renderer gets the
extension list of DOCUMENT's parser, which the parser owns and frees with
itself: that is why the parser lives until the document is released."
  (let ((root (native-root document))
        (parser (document-parser document))
        (options (html-option-bits checked-options)))
    (decoded-render
     (rendered-octets document
                      (lambda ()
                        (%render-html root options (cmark-parser-get-syntax-extensions parser)))
                      'render-html))))

(defun render-plaintext (document checked-options)
  "DOCUMENT rendered by cmark_render_plaintext with CHECKED-OPTIONS'
plaintext bits and :WIDTH, as a string, and as a second value the octets
cmark wrote: what PLAINTEXT-OUTPUT-BOUND bounds."
  (let ((root (native-root document))
        (options (plaintext-option-bits checked-options))
        (width (checked-width checked-options)))
    (decoded-render
     (rendered-octets document
                      (lambda () (%render-plaintext root options width))
                      'render-plaintext))))

(defun render-xml (document)
  "DOCUMENT rendered by cmark_render_xml with DOCUMENT's own parse bits, so
it carries source positions exactly when the parse kept them, as a string,
and as a second value the octets cmark wrote. The library renders no XML:
only the native suite calls this, against the pinned CLI's XML and as the
other side of its XML oracle."
  (let ((root (native-root document))
        (options (document-parse-bits document)))
    (decoded-render
     (rendered-octets document
                      (lambda () (%render-xml root options))
                      'render-xml))))
