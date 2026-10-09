;;;; The native walker and the node accessors, over
;;;; tests/fixtures/vocabulary.md, which holds every kind once or more.

(in-package #:cl-commonmark-gfm.native-tests)

;;; The XML fixture's element names: cmark's XML renderer names each element
;;; with cmark_node_get_type_string (S_render_node, src/xml.c), so they are
;;; the type strings in walk order. A footnote node has no type string of
;;; its own, so it prints as "<unknown>" and its start tag as "<<unknown>".

(defun xml-start-tag-name (line)
  "The element name of LINE, an XML line with its indentation trimmed that
starts with a start tag: \"<unknown>\", or the run of letters and
underscores after the <."
  (if (uiop:string-prefix-p "<<unknown>" line)
      "<unknown>"
      (subseq line 1 (position-if-not (lambda (char) (or (alpha-char-p char) (char= char #\_)))
                                      line :start 1))))

(defun xml-element-names (xml)
  "The name of every element of XML, cmark's XML output, in document order.
Each element starts its own line; lines starting </, <? or <!, and the
lines of a literal's text, start none."
  (with-input-from-string (stream xml)
    (loop for line = (read-line stream nil nil)
          while line
          for trimmed = (string-left-trim '(#\Space) line)
          when (and (> (length trimmed) 1)
                    (char= (char trimmed 0) #\<)
                    (not (member (char trimmed 1) '(#\/ #\? #\!))))
            collect (xml-start-tag-name trimmed))))

(defun vocabulary-type-strings ()
  "The type strings WALK-NATIVE enters for vocabulary.md, under :gfm."
  (call-with-native-document (fixture-string "vocabulary.md") '()
                             (lambda (document checked-options)
                               (declare (ignore checked-options))
                               (type-strings-entered document))))

(define-test the-xml-fixture-names-76-elements
  ;; Guards the reader below: one that found nothing would let any walk pass.
  (is = 76 (length (xml-element-names (fixture-string "vocabulary.xml")))))

(define-test walk-native-enters-nodes-in-the-xml-order
  (is equal (xml-element-names (fixture-string "vocabulary.xml")) (vocabulary-type-strings)))

;;; The walk protocol: WALK-AST's

(defun document-events (document skip)
  "Every (EVENT TYPE-STRING) WALK-NATIVE makes over DOCUMENT, in order.
Returns :SKIP from the :ENTER of each node whose type string is SKIP."
  (let ((events '()))
    (walk-native (lambda (event node)
                   (let ((type-string (native-type-string document node)))
                     (push (list event type-string) events)
                     (when (and (eql event :enter) (equal type-string skip))
                       :skip)))
                 document)
    (nreverse events)))

(defun walk-events (markdown &key skip)
  "DOCUMENT-EVENTS for MARKDOWN, parsed under :GFM."
  (call-with-native-document markdown '()
                             (lambda (document checked-options)
                               (declare (ignore checked-options))
                               (document-events document skip))))

(define-test walk-native-enters-and-exits-every-node
  ;; A leaf gets both events; siblings come in order; parents exit last.
  (is equal '((:enter "document")
              (:enter "paragraph")
              (:enter "text") (:exit "text")
              (:enter "emph") (:enter "text") (:exit "text") (:exit "emph")
              (:exit "paragraph")
              (:enter "paragraph") (:enter "text") (:exit "text") (:exit "paragraph")
              (:exit "document"))
      (walk-events (format nil "a *b*~%~%c~%"))))

(defun without-subtree (events type-string)
  "EVENTS with everything after (:ENTER TYPE-STRING) removed, up to and
including the matching (:EXIT TYPE-STRING): what :SKIP leaves of a walk."
  (let* ((start (1+ (position (list :enter type-string) events :test #'equal)))
         (end (1+ (position (list :exit type-string) events :test #'equal :start start))))
    (append (subseq events 0 start) (subseq events end))))

(define-test walk-native-skips-a-subtree
  (let ((markdown (fixture-string "vocabulary.md")))
    (is equal (without-subtree (walk-events markdown) "table")
        (walk-events markdown :skip "table")
        "the table's descendants and its :exit are skipped, and nothing else")
    (is equal '((:enter "document")) (walk-events markdown :skip "document")
        "skipping the root ends the walk")))

;;; Classification: the extension pointer and the type string.
;;; vocabulary.md holds every kind but :extension.

(define-test every-kind-but-extension-is-classified-in-the-vocabulary
  (is equal '(:block-quote :code :code-block :document :emph :footnote-definition
              :footnote-reference :heading :html-block :html-inline :image :item
              :linebreak :link :list :paragraph :softbreak :strikethrough :strong
              :table :table-cell :table-header :table-row :task-item :text
              :thematic-break)
      (call-with-native-document (fixture-string "vocabulary.md") '()
                                 (lambda (document checked-options)
                                   (declare (ignore checked-options))
                                   (let ((kinds '()))
                                     (walk-native (lambda (event node)
                                                    (when (eql event :enter)
                                                      (pushnew (native-kind document node) kinds)))
                                                  document)
                                     (sort kinds #'string<))))))

(define-test native-extension-names-the-cached-extension
  (is equal '(:table :strikethrough :tasklist nil)
      (call-with-native-document (fixture-string "vocabulary.md") '()
                                 (lambda (document checked-options)
                                   (declare (ignore checked-options))
                                   (loop for kind in '(:table :strikethrough :task-item :paragraph)
                                         for node = (first (nodes-of-kind document kind))
                                         collect (native-extension document node))))))

;;; CLASSIFY-NODE reads a node's type string only when the node has an
;;; extension. Reading it costs three foreign calls, each a symbol lookup
;;; under ECL's dynamic FFI, so NATIVE-KIND reads it for no other node.

(defun type-string-reads (document)
  "Classify every node of DOCUMENT with NATIVE-KIND, and return the nodes
whose type string it read, through cmark_node_get_type_string. That CFFI
function is wrapped for the walk and restored however the walk ends."
  (let ((original (fdefinition 'cl-commonmark-gfm.ffi:cmark-node-get-type-string))
        (read-for '()))
    (unwind-protect
         (progn
           (setf (fdefinition 'cl-commonmark-gfm.ffi:cmark-node-get-type-string)
                 (lambda (node)
                   (push node read-for)
                   (funcall original node)))
           (walk-native (lambda (event node)
                          (when (eql event :enter)
                            (native-kind document node))
                          nil)
                        document))
      (setf (fdefinition 'cl-commonmark-gfm.ffi:cmark-node-get-type-string) original))
    read-for))

(defun type-string-read-facts ()
  "For vocabulary.md: how many nodes have an extension, and for how many of
those NATIVE-KIND read a type string; how many have none, and for how many
of those it read one; as (WITH READ-WITH WITHOUT READ-WITHOUT)."
  (call-with-native-document
   (fixture-string "vocabulary.md") '()
   (lambda (document checked-options)
     (declare (ignore checked-options))
     (let ((read-for (type-string-reads document))
           (with 0)
           (read-with 0)
           (without 0)
           (read-without 0))
       (walk-native (lambda (event node)
                      (when (eql event :enter)
                        (let ((read (member node read-for :test #'cffi:pointer-eq)))
                          (cond ((native-extension document node)
                                 (incf with)
                                 (when read (incf read-with)))
                                (t (incf without)
                                   (when read (incf read-without)))))))
                    document)
       (list with read-with without read-without)))))

(define-test native-kind-reads-no-type-string-for-a-node-without-an-extension
  (destructuring-bind (with read-with without read-without) (type-string-read-facts)
    (true (plusp with) "nodes with an extension: ~D" with)
    ;; The control: the wrapper sees every read NATIVE-KIND makes, so a read
    ;; that went around it can't make the last assertion pass.
    (is = with read-with "type strings read for nodes with an extension: each one")
    (true (plusp without) "nodes without one: ~D" without)
    (is = 0 read-without "type strings read for nodes without an extension"))
  (true (open-counts-zero-p)))

;;; The accessors, against tests/fixtures/vocabulary.xml's attributes

(defun first-of-kind (document kind)
  "DOCUMENT's first node of KIND, in walk order."
  (first (nodes-of-kind document kind)))

(define-test the-accessors-read-the-vocabulary
  (call-with-native-document
   (fixture-string "vocabulary.md") '()
   (lambda (document checked-options)
     (declare (ignore checked-options))
     (let ((heading (first-of-kind document :heading))
           (lists (nodes-of-kind document :list))
           (link (first-of-kind document :link))
           (image (first-of-kind document :image))
           (code-block (first-of-kind document :code-block))
           (code (first-of-kind document :code))
           (table (first-of-kind document :table)))
       (is = 1 (native-heading-level document heading))
       (is equal '(1 1 1 45)
           (list (native-start-line document heading) (native-start-column document heading)
                 (native-end-line document heading) (native-end-column document heading)))
       (is equal '(:ordered :period 1 t)
           (list (native-list-type document (first lists))
                 (native-list-delimiter document (first lists))
                 (native-list-start document (first lists))
                 (native-list-tight document (first lists))))
       (is equal '(:bullet nil t)
           (list (native-list-type document (second lists))
                 (native-list-delimiter document (second lists))
                 (native-list-tight document (second lists))))
       (is string= "http://x.org" (native-url document link))
       (is string= "t" (native-title document link))
       (is string= "a.png" (native-url document image))
       (is string= "it" (native-title document image))
       (is string= "lisp" (native-fence-info document code-block))
       (is string= (format nil "(+ 1 2)~%") (native-literal document code-block))
       (is string= "code" (native-literal document code))
       (is = 3 (native-table-columns document table))
       (is equal '(:left :center :right) (native-table-alignments document table))))))

(define-test a-string-accessor-on-another-kind-signals-native-parse-error
  ;; cmark_node_get_literal returns null for a kind without a literal
  ;; (src/node.c), as the URL, title and fence-info accessors do for theirs.
  (call-with-native-document "para" '()
                             (lambda (document checked-options)
                               (declare (ignore checked-options))
                               (let ((paragraph (first-of-kind document :paragraph)))
                                 (raised native-parse-error (native-literal document paragraph))
                                 (raised native-parse-error (native-url document paragraph))
                                 (raised native-parse-error (native-title document paragraph))
                                 (raised native-parse-error (native-fence-info document paragraph))
                                 (is eql nil (native-list-type document paragraph))
                                 (is eql nil (native-list-delimiter document paragraph))))))

(define-test a-table-column-without-alignment-reads-nil
  (is equal '(nil :right)
      (call-with-native-document (format nil "| a | b |~%|---|--:|~%")  '()
                                 (lambda (document checked-options)
                                   (declare (ignore checked-options))
                                   (native-table-alignments document
                                                            (first-of-kind document :table))))))

(define-test a-footnote-reference-reads-its-definition
  ;; After parsing, a reference's own literal is its number; its label as
  ;; written is its definition's literal (process_footnotes,
  ;; src/blocks.c).
  (call-with-native-document (format nil "x[^note]~%~%[^note]: N.~%") '()
                             (lambda (document checked-options)
                               (declare (ignore checked-options))
                               (let* ((reference (first-of-kind document :footnote-reference))
                                      (definition (native-footnote-definition document reference)))
                                 (is string= "1" (native-literal document reference))
                                 (is eql :footnote-definition (native-kind document definition))
                                 (is string= "note" (native-literal document definition))))))

(define-test the-walk-pointers-agree
  ;; A node's first child names it as parent; a last child has no next.
  (call-with-native-document (format nil "a *b*~%") '()
                             (lambda (document checked-options)
                               (declare (ignore checked-options))
                               (let* ((root (native-root document))
                                      (paragraph (native-first-child document root))
                                      (text (native-first-child document paragraph))
                                      (emph (native-next document text)))
                                 (false (native-parent document root))
                                 (true (cffi:pointer-eq root (native-parent document paragraph)))
                                 (true (cffi:pointer-eq paragraph (native-parent document emph)))
                                 (false (native-next document emph))
                                 (false (native-next document paragraph))))))
