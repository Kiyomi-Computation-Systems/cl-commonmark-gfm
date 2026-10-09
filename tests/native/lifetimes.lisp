;;;; Lifetimes: every failure path frees what it created, a document used
;;;; after its scope signals, and the two ABI beliefs hold. The library
;;;; binds cmark-gfm with no C compiler to check its ABI, so it believes,
;;;; and tests, two facts: the allocator's `free` is its third function
;;;; pointer, and the tasklist accessor's C `bool` is one byte.

(in-package #:cl-commonmark-gfm.native-tests)

;;; Failure paths. Each test reads the monotonic counters before and after,
;;; so a failure that came before cmark created anything can't pass for one
;;; that came after, and ends with the open counters at zero.

(define-test a-null-parser-signals-native-parse-error
  (native-state)
  (let ((parsers (created-parsers)))
    (with-redefined ((native::%parser-new (lambda (parse-bits)
                                            (declare (ignore parse-bits))
                                            (cffi:null-pointer))))
      (raised native-parse-error (call-with-native-document "text" '() (constantly nil))))
    (is = parsers (created-parsers) "a null parser isn't counted")
    (true (open-counts-zero-p))))

(define-test a-null-root-signals-native-parse-error
  (native-state)
  (let ((parsers (created-parsers))
        (buffers (created-buffers))
        (body-ran nil))
    (with-redefined ((native::%parser-finish (lambda (parser)
                                               (declare (ignore parser))
                                               (cffi:null-pointer))))
      (raised native-parse-error
              (call-with-native-document "text" '()
                                         (lambda (document checked-options)
                                           (declare (ignore document checked-options))
                                           (setf body-ran t)))))
    (false body-ran "the body never runs on a document with no root")
    (is = (1+ parsers) (created-parsers))
    (is = buffers (created-buffers))
    (true (open-counts-zero-p))))

(define-test a-null-buffer-signals-native-render-error
  (native-state)
  (dolist (entry (list (list 'native::%render-html :html #'render-html)
                       (list 'native::%render-plaintext :plaintext #'render-plaintext)
                       (list 'native::%render-xml :parse
                             (lambda (document checked-options)
                               (declare (ignore checked-options))
                               (render-xml document)))))
    (destructuring-bind (wrapper entry-point render) entry
      (let ((parsers (created-parsers))
            (buffers (created-buffers)))
        (call-with-redefined wrapper
                             (lambda (&rest arguments)
                               (declare (ignore arguments))
                               (cffi:null-pointer))
                             (lambda ()
                               (raised native-render-error
                                       (call-with-native-document "text" '() render
                                                                  :entry-point entry-point)
                                       "~(~A~) returning null" wrapper)))
        (is = (1+ parsers) (created-parsers) "~(~A~): one parser" wrapper)
        (is = buffers (created-buffers) "~(~A~): no buffer" wrapper)
        (true (open-counts-zero-p) "~(~A~): nothing left open" wrapper)))))

(define-test a-non-local-exit-from-the-body-releases-the-document
  (native-state)
  (let ((parsers (created-parsers)))
    (is eql :escaped (catch 'escape
                       (call-with-native-document "text" '()
                                                  (lambda (document checked-options)
                                                    (declare (ignore document checked-options))
                                                    (throw 'escape :escaped)))))
    (is = (1+ parsers) (created-parsers))
    (true (open-counts-zero-p))))

(define-test an-error-in-the-body-releases-the-document
  (native-state)
  (let ((parsers (created-parsers)))
    (raised simple-error (call-with-native-document "text" '()
                                                    (lambda (document checked-options)
                                                      (declare (ignore document checked-options))
                                                      (error "the body failed"))))
    (is = (1+ parsers) (created-parsers))
    (true (open-counts-zero-p))))

(define-test a-failed-root-free-still-frees-the-parser
  ;; The root is freed, then its free signals: the parser must be freed all
  ;; the same, and the error still reaches the caller.
  (native-state)
  (let ((free-root (fdefinition 'native::free-root)))
    (with-redefined ((native::free-root (lambda (root)
                                          (funcall free-root root)
                                          (error "freeing the root failed"))))
      (raised simple-error (call-with-native-document "text" '() (constantly nil)))))
  (true (open-counts-zero-p)))

;;; A document used after its scope: every accessor checks the document's
;;; alive flag

(defparameter *node-accessors*
  '(native-first-child native-next native-parent
    native-type native-type-string native-extension native-kind
    native-literal native-url native-title native-fence-info
    native-heading-level
    native-list-type native-list-delimiter native-list-start native-list-tight
    native-start-line native-start-column native-end-line native-end-column
    native-footnote-definition native-table-columns native-table-alignments
    native-task-checked)
  "Every node accessor, each called as (accessor document node).")

(defparameter *other-native-functions*
  '(native-root native-state native-state-published-p
    native-open-counts native-created-counts native-startup-count)
  "The native package's other exported NATIVE- functions.")

(define-test every-exported-native-function-is-listed
  ;; So an accessor added later can't escape the use-after-release test.
  (let ((exported '()))
    (do-external-symbols (symbol '#:cl-commonmark-gfm.native)
      (when (and (fboundp symbol)
                 (not (macro-function symbol))
                 (uiop:string-prefix-p "NATIVE-" (symbol-name symbol)))
        (push symbol exported)))
    (false (set-difference exported (append *node-accessors* *other-native-functions*)))
    (false (set-difference (append *node-accessors* *other-native-functions*) exported))))

(defun released-document-and-root ()
  "A document whose scope has ended, and its root node, as two values."
  (let ((document nil)
        (root nil))
    (call-with-native-document "# heading" '()
                               (lambda (live-document checked-options)
                                 (declare (ignore checked-options))
                                 (setf document live-document
                                       root (native-root live-document))))
    (values document root)))

(define-test every-accessor-signals-after-release
  (multiple-value-bind (document root) (released-document-and-root)
    (raised native::native-document-released (native-root document))
    (dolist (accessor *node-accessors*)
      (raised native::native-document-released (funcall accessor document root)
              "~(~A~) after release" accessor))
    (raised native::native-document-released (walk-native (constantly nil) document))
    (raised native::native-document-released (render-xml document))
    (raised native::native-document-released
            (render-html document (check-options :html 'test '())))
    (raised native::native-document-released
            (render-plaintext document (check-options :plaintext 'test '()))))
  (true (open-counts-zero-p)))

(define-test a-released-document-names-the-accessor
  (multiple-value-bind (document root) (released-document-and-root)
    (let ((condition (raised native::native-document-released (native-literal document root))))
      (is eql 'native-literal (native::released-operation condition)))))

;;; The two ABI beliefs

(define-test the-allocator-holds-three-distinct-functions
  (let* ((state (native-state))
         (allocator (cl-commonmark-gfm.ffi:cmark-get-default-mem-allocator))
         (slots (loop for index below 3
                      collect (cffi:pointer-address (cffi:mem-aref allocator :pointer index)))))
    (false (some #'zerop slots) "calloc, realloc and free are non-null")
    (is = 3 (length (remove-duplicates slots)) "calloc, realloc and free are distinct")
    (is = (third slots) (cffi:pointer-address (native::state-free state))
        "the state frees buffers through the third")))

(define-test checked-and-unchecked-task-items-read-differently
  (is equal '(nil t)
      (call-with-native-document (fixture-string "vocabulary.md") '()
                                 (lambda (document checked-options)
                                   (declare (ignore checked-options))
                                   (mapcar (lambda (node) (native-task-checked document node))
                                           (nodes-of-kind document :task-item))))))
