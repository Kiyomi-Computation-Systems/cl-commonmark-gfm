;;;; Rendering: cmark's three renderers through a live document, against
;;;; the pinned CLI's output, and under forced collections.

(in-package #:cl-commonmark-gfm.native-tests)

;;; XML

(define-test render-xml-reproduces-the-vocabulary-fixture
  ;; tests/fixtures/vocabulary.xml is the pinned CLI's `--sourcepos -e
  ;; footnotes -e table -e strikethrough -e autolink -e tagfilter -e
  ;; tasklist -t xml` output (make check-vocabulary).
  (is string= (fixture-string "vocabulary.xml")
      (call-with-native-document (fixture-string "vocabulary.md") '(:profile :gfm :sourcepos t)
                                 (lambda (document checked-options)
                                   (declare (ignore checked-options))
                                   (render-xml document)))))

;;; HTML: every oracle fixture, against the pinned CLI's committed HTML

(defun manifest-fields (line)
  "LINE of tests/fixtures/html/cases split at runs of spaces and tabs."
  (let ((fields '())
        (start nil))
    (loop for index from 0 to (length line)
          for char = (and (< index (length line)) (char line index))
          do (cond
               ((and char (not (member char '(#\Space #\Tab))))
                (unless start (setf start index)))
               (start
                (push (subseq line start index) fields)
                (setf start nil))))
    (nreverse fields)))

(defun cli-flag-options (flag)
  "The :HTML options that ask cmark for what the CLI's FLAG does."
  (cond
    ((string= flag "--unsafe") '(:unsafe-html t))
    ((string= flag "--nobreaks") '(:softbreak :space))
    ((string= flag "--hardbreaks") '(:softbreak :br))
    (t (error "tests/fixtures/html/cases names an unknown flag: ~A" flag))))

(defun oracle-fixture-cases ()
  "Every case of tests/fixtures/html/cases as (NAME FILE OPTIONS). Each
case renders with the CLI's GFM flags, the :GFM profile's defaults, plus
its own flags as :HTML options."
  (with-input-from-string (stream (fixture-string "html/cases"))
    (loop for line = (read-line stream nil nil)
          while line
          for fields = (manifest-fields line)
          when (and fields (char/= (char (first fields) 0) #\#))
            collect (list (first fields)
                          (second fields)
                          (mapcan #'cli-flag-options (cddr fields))))))

(define-test render-html-reproduces-every-oracle-fixture
  (let ((cases (oracle-fixture-cases)))
    (is = (length *oracle-cases*) (length cases)
        "every case of the manifest is rendered")
    (dolist (case cases)
      (destructuring-bind (name file options) case
        (is string= (fixture-string (format nil "html/~A.html" name))
            (call-with-native-document (fixture-string (format nil "html/~A" file)) options
                                       #'render-html :entry-point :html)
            "oracle case ~A" name)))))

(define-test render-html-hands-the-extensions-to-the-renderer
  ;; tagfilter works only through the extension list cmark_render_html is
  ;; given (cmark_render_html_with_mem, src/html.c). Expected output from
  ;; the pinned CLI, with and without the GFM flags, both --unsafe.
  (let ((markdown (format nil "<script>x</script>~%~%<b>ok</b>~%")))
    (is string= (format nil "&lt;script>x&lt;/script>~%<p><b>ok</b></p>~%")
        (call-with-native-document markdown '(:unsafe-html t) #'render-html :entry-point :html))
    (is string= (format nil "<script>x</script>~%<p><b>ok</b></p>~%")
        (call-with-native-document markdown '(:profile :commonmark :unsafe-html t)
                                   #'render-html :entry-point :html))))

;;; Plaintext, against the pinned CLI's `-t plaintext`, with the GFM flags

(defparameter *plaintext-markdown*
  (format nil "# Title~%~%Some *emphasised* text that runs long enough to wrap at twenty ~
               columns.~%~%- one~%- two ~~~~gone~~~~~%~%| a | b |~%|---|---|~%| 1 | 2 |~%"))

(define-test render-plaintext-matches-the-pinned-cli
  (is string= (format nil "Title~%~%Some emphasised text that runs long enough to wrap at twenty ~
                           columns.~%~%  - one~%  - two ~~gone~~~%~%| a | b |~%| --- | --- |~%~
                           | 1 | 2 |~%")
      (call-with-native-document *plaintext-markdown* '() #'render-plaintext
                                 :entry-point :plaintext)
      "no wrapping")
  (is string= (format nil "Title~%~%Some emphasised text~%that runs long~%enough to wrap at~%~
                           twenty columns.~%~%  - one~%  - two ~~gone~~~%~%| a | b |~%~
                           | --- | --- |~%| 1 | 2 |~%")
      (call-with-native-document *plaintext-markdown* '(:width 20) #'render-plaintext
                                 :entry-point :plaintext)
      ":width 20"))

;;; Buffers

(define-test every-render-frees-its-buffer
  (native-state)
  (let ((buffers (created-buffers)))
    (call-with-native-document "*hi*" '()
                               (lambda (document checked-options)
                                 (render-html document checked-options)
                                 (render-xml document))
                               :entry-point :html)
    (call-with-native-document "*hi*" '() #'render-plaintext :entry-point :plaintext)
    (is = (+ buffers 3) (created-buffers))
    (true (open-counts-zero-p))))

;;; Forced collections: the same result every time, with a full collection
;;; between parses, and between a parse and its render.

(defun vocabulary-html (&key collect-inside)
  "vocabulary.md rendered to HTML under :gfm, with a full collection between
the parse and the render when COLLECT-INSIDE is true."
  (call-with-native-document (fixture-string "vocabulary.md") '()
                             (lambda (document checked-options)
                               (when collect-inside
                                 (trivial-garbage:gc :full t))
                               (render-html document checked-options))
                             :entry-point :html))

(defun stable-across-collections-p (function iterations)
  "True when FUNCTION returns an EQUAL result on each of ITERATIONS calls,
with a full collection before each."
  (let ((expected (funcall function)))
    (loop repeat iterations
          always (progn
                   (trivial-garbage:gc :full t)
                   (equal expected (funcall function))))))

(define-test parses-and-renders-survive-full-collections
  (true (stable-across-collections-p #'vocabulary-type-strings 10) "walks")
  (true (stable-across-collections-p #'vocabulary-html 10) "renders")
  (true (stable-across-collections-p (lambda () (vocabulary-html :collect-inside t)) 10)
        "renders with a collection inside the document's scope")
  (true (open-counts-zero-p)))

;;; The octets cmark wrote. Each renderer returns them as a second value:
;;; what the output bounds bound. A decoded string can be longer in UTF-8,
;;; by 2 octets for each one-octet maximal subpart turned into U+FFFD. The
;;; pinned CLI, with the GFM flags, writes <p>x [^a, C3, ]</p> and a newline
;;; for x [^aé, a line break and bbbbbb]: 15 octets
;;; (tests/native/renderers.lisp, SPLIT-LABEL-INPUTS).

(defun render-octets (markdown render entry-point)
  "MARKDOWN rendered by RENDER, a function of a document and checked
options, under ENTRY-POINT's defaults, as (OCTETS UTF-8-LENGTH): the octets
RENDER returned as its second value, and the UTF-8 length of its string."
  (call-with-native-document markdown '()
                             (lambda (document checked-options)
                               (multiple-value-bind (string octets)
                                   (funcall render document checked-options)
                                 (list octets (cl-commonmark-gfm.util:utf8-length string))))
                             :entry-point entry-point))

(define-test every-renderer-returns-the-octets-cmark-wrote
  (let ((split (format nil "x [^a~C~%bbbbbb]~%" (code-char #xE9)))
        (xml (lambda (document checked-options)
               (declare (ignore checked-options))
               (render-xml document))))
    (is equal '(15 17) (render-octets split #'render-html :html) "HTML of a split label")
    (is equal '(6 6) (render-octets split #'render-plaintext :plaintext)
        "plaintext of a split label")
    (is equal '(20 20) (render-octets (format nil "*h~C*" (code-char #xE9)) #'render-html :html)
        "well-formed HTML")
    (is equal '(4 4) (render-octets (format nil "*h~C*" (code-char #xE9)) #'render-plaintext
                                    :plaintext)
        "well-formed plaintext")
    (destructuring-bind (octets length) (render-octets "*hi*" xml :parse)
      (true (and octets (= octets length)) "XML: ~A octets, ~A in UTF-8" octets length)))
  (true (open-counts-zero-p)))
