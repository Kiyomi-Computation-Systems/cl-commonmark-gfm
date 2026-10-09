;;;; The input guard, through the public API. With footnotes on, a [
;;;; immediately followed by an entity that decodes to ^ makes cmark read
;;;; freed heap memory, so the guard refuses such input before cmark sees
;;;; it. PARSE, MARKDOWN->HTML, MARKDOWN->PLAINTEXT, MARKDOWN->HTML-TREE and
;;;; UNSUPPORTED-INPUT are imported into CL-COMMONMARK-GFM.NATIVE-TESTS
;;;; (tests/native/package.lisp), so they're named and called unqualified
;;;; here.
;;;;
;;;; tests/native-core.lisp tests FOOTNOTE-ENTITY-INDEX itself, purely, on
;;;; bare substrings; this file exercises the same grammar end to end,
;;;; through PARSE, MARKDOWN->HTML, MARKDOWN->PLAINTEXT and
;;;; MARKDOWN->HTML-TREE, confirming the guard actually runs before any
;;;; native call and that :FOOTNOTES NIL turns it off.

(in-package #:cl-commonmark-gfm.native-tests)

;;; The seven forms that decode to ^ (U+005E, 94), and four near misses

(defparameter *caret-entity-forms*
  (list "&#94;" "&#094;" "&#00000094;" "&#x5e;" "&#X5E;" "&#x0000005E;" "&Hat;")
  "Every form of the guard's grammar that decodes to ^ (U+005E, 94), the
8-digit, zero-padded edge included. Mirrors tests/native-core.lisp's pure
FOOTNOTE-ENTITY-INDEX tests, through the public API.")

(defparameter *near-miss-markdown*
  (list "[&#000000094;ab]"   ; 9 digits, one past the 8-digit maximum
        "[&#94ab]"           ; no closing ;
        "[&hat;ab]"          ; lowercase: not an entity at all
        "[ &#94;ab]")        ; a space between the [ and the &
  "Markdown holding a near miss of the guard's grammar at or right after a
[, each of which must still parse.")

(defun bracketed-entity (entity)
  "[ ENTITY, a short label, and ] -- Markdown exercising the guard with a
label a few characters long, never one long enough to fault the process
with the guard removed, as a mutation run removes it."
  (format nil "[~Aab]" entity))

;;; The four entry points, paired with the symbol each signals conditions as

(defparameter *guard-entry-points*
  (list (cons 'parse #'parse)
        (cons 'markdown->html #'markdown->html)
        (cons 'markdown->plaintext #'markdown->plaintext)
        (cons 'markdown->html-tree #'markdown->html-tree))
  "Every entry point, paired with the symbol it signals conditions as, for
exercising the guard through every entry point.")

(defun call-guard-entry-point (entry-point markdown &rest options)
  "Call ENTRY-POINT's (an element of *GUARD-ENTRY-POINTS*) function on
MARKDOWN and OPTIONS."
  (apply (cdr entry-point) markdown options))

(defun parses-without-error-p (thunk)
  "True when THUNK returns normally; false when it signals a
COMMONMARK-GFM-ERROR or a TYPE-ERROR."
  (handler-case (progn (funcall thunk) t)
    (commonmark-gfm-error () nil)
    (type-error () nil)))

;;; Rejection: every form, through every entry point, before any parser

(define-test footnote-entity-guard-rejects-every-form-through-every-entry-point
  (native-state)
  (dolist (entity *caret-entity-forms*)
    (let ((markdown (bracketed-entity entity)))
      (dolist (entry-point *guard-entry-points*)
        (let* ((name (car entry-point))
               (before (created-parsers))
               (condition (raised unsupported-input
                                   (call-guard-entry-point entry-point markdown)
                                   "~A on ~S" name entity)))
          (when condition
            (is eql name (condition-operation condition))
            (is eql 0 (condition-datum condition))
            (true (condition-reason condition)))
          (is = before (created-parsers) "~A on ~S should create no parser" name entity)))))
  (true (open-counts-zero-p)))

;;; Near misses still parse, through every entry point

(define-test footnote-entity-guard-near-misses-parse-through-every-entry-point
  (native-state)
  (dolist (markdown *near-miss-markdown*)
    (dolist (entry-point *guard-entry-points*)
      (true (parses-without-error-p (lambda () (call-guard-entry-point entry-point markdown)))
            "~A on ~S should parse" (car entry-point) markdown)))
  (true (open-counts-zero-p)))

;;; With :FOOTNOTES NIL, the guard doesn't run

(define-test footnote-entity-guard-off-when-footnotes-are-off
  (native-state)
  (dolist (entity *caret-entity-forms*)
    (let ((markdown (bracketed-entity entity)))
      (dolist (entry-point *guard-entry-points*)
        (true (parses-without-error-p
               (lambda () (call-guard-entry-point entry-point markdown :footnotes nil)))
              "~A on ~S with :footnotes nil should parse" (car entry-point) entity))))
  (true (open-counts-zero-p)))

(define-test footnote-entity-guard-off-renders-the-entity-as-text
  ;; Confirmed against the pinned CLI, cmark-gfm 0.29.0.gfm.13 (`cmark-gfm
  ;; -e table -e strikethrough -e autolink -e tagfilter -e tasklist`, the
  ;; :GFM profile's extensions, without -e footnotes): with footnotes off,
  ;; [&#94;ab] has no footnote meaning at all, the entity still decodes to
  ;; ^ as usual, and the brackets stay literal text.
  (is string= (format nil "<p>[^ab]</p>~%") (markdown->html "[&#94;ab]" :footnotes nil)))
