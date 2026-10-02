;;;; Render stress (ADR-0008, ADR-0013; M2 design §8.4): documents up to the
;;;; default input limit, each parsed and rendered again and again, render
;;;; the same every time and leave nothing open. No tool in CI inspects
;;;; native memory (ADR-0013), so this catches crashes and leaks under
;;;; repeated large renders, not any one cause: a buffer freed through the
;;;; wrong slot of the allocator (ADR-0008's first ABI belief), which the
;;;; slot test can't catch, is one of them. Calling `calloc` or `realloc`
;;;; where `free` belongs is undefined behavior, not a guaranteed leak: a
;;;; reviewer called the real free site that way and, on SBCL 2.6.4
;;;; x86-64, it aborted the process on the first render; elsewhere it
;;;; might only leak, which nothing here measures either.

(in-package #:cl-commonmark-gfm.native-tests)

(defparameter *stress-repetitions* 5
  "How many times each stress document is parsed and rendered, per format.")

(defun stress-chunk ()
  "What a stress document repeats: tests/fixtures/vocabulary.md, which holds
every node kind, then a paragraph of characters two, three and four octets
long in UTF-8."
  (concatenate 'string
               (fixture-string "vocabulary.md")
               (format nil "~%~A~%~%" (coerce (list (code-char #xE9) (code-char #x20AC)
                                                    (code-char #x65E5) (code-char #x1F600))
                                              'string))))

(defun stress-copies (octets)
  "How many copies of STRESS-CHUNK a stress document of OCTETS octets holds."
  (floor octets (cl-commonmark-gfm.util:utf8-length (stress-chunk))))

(defun stress-document (octets)
  "A document of exactly OCTETS octets of UTF-8: STRESS-COPIES copies of
STRESS-CHUNK, then newlines."
  (let ((chunk (stress-chunk))
        (copies (stress-copies octets)))
    (concatenate 'string
                 (cl-commonmark-gfm.tests::repeat-string chunk copies)
                 (make-string (- octets (* copies (cl-commonmark-gfm.util:utf8-length chunk)))
                              :initial-element #\Newline))))

(defun stress-sizes ()
  "The stress documents' sizes, in octets: a ladder up to
*MAX-INPUT-OCTETS*, the default input limit."
  (let ((limit cl-commonmark-gfm.native-core:*max-input-octets*))
    (list (floor limit 64) (floor limit 8) limit)))

(defun differing-renders (markdown options entry-point render)
  "Parse MARKDOWN with OPTIONS, ENTRY-POINT's options, and render it with
RENDER, *STRESS-REPETITIONS* times, each from a fresh parse. Return how
many renders differ from the first."
  (flet ((parse-and-render ()
           (call-with-native-document markdown options render :entry-point entry-point)))
    (let ((first (parse-and-render)))
      (loop repeat (1- *stress-repetitions*)
            count (string/= first (parse-and-render))))))

(define-test the-largest-stress-document-fills-the-limit-and-renders-whole
  (let ((limit cl-commonmark-gfm.native-core:*max-input-octets*))
    (is = limit (cl-commonmark-gfm.util:utf8-length (stress-document limit)))
    (is = (stress-copies limit)
        (occurrences "<table>" (render-html-of (stress-document limit) '()))
        "one table per copy of the chunk")))

(define-test large-documents-render-the-same-every-time
  (native-state)
  (let ((parsers (created-parsers))
        (buffers (created-buffers))
        (renders (* 2 (length (stress-sizes)) *stress-repetitions*)))
    (dolist (octets (stress-sizes))
      (is = 0 (differing-renders (stress-document octets) '() :html #'render-html)
          "HTML renders of ~D octets unlike the first" octets)
      (is = 0 (differing-renders (stress-document octets) '() :plaintext #'render-plaintext)
          "plaintext renders of ~D octets unlike the first" octets))
    (is = (+ parsers renders) (created-parsers) "each render parsed afresh")
    (is = (+ buffers renders) (created-buffers) "each render made one buffer")
    (true (open-counts-zero-p))))
