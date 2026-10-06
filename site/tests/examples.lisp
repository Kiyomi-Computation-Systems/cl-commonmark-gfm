;;;; Tests for `make check-docs`'s core: finding a page's Lisp blocks,
;;;; reading their forms and expectations, printing and comparing values,
;;;; and running a page's examples into the problems it reports. The pages
;;;; are built here; the examples call cmark-gfm, as docs/'s do.

(in-package #:cl-commonmark-gfm.site.tests)

;;; Helpers

(defun fence (info &rest code)
  "A fenced code block as Markdown lines: an opening fence whose info string
is INFO, the lines CODE, the closing fence, and a blank line."
  (append (list (concatenate 'string "```" info)) code (list "```" "")))

(defun example-page (&rest blocks)
  "A page whose first block is the heading # Examples, followed by BLOCKS,
each a list of Markdown lines, such as FENCE makes."
  (apply #'lines "# Examples" "" (apply #'append blocks)))

(defun read-block (&rest code)
  "The examples of a block whose lines are CODE, read in a fresh page
package and not run, each as (SOURCE EXPECTATION PROBLEM)."
  (let ((package (cl-commonmark-gfm.site::make-page-package)))
    (unwind-protect
         (mapcar (lambda (example)
                   (list (cl-commonmark-gfm.site::example-source example)
                         (cl-commonmark-gfm.site::example-expectation example)
                         (cl-commonmark-gfm.site::example-problem example)))
                 (cl-commonmark-gfm.site::block-examples (apply #'lines code) package))
      (delete-package package))))

(defun check-blocks (&rest blocks)
  "What CHECK-PAGE-EXAMPLES finds on a page a.md made of BLOCKS, as
EXAMPLE-PAGE makes it: its problems and its number of examples, as a list."
  (multiple-value-list
   (cl-commonmark-gfm.site::check-page-examples "a.md" (apply #'example-page blocks))))

(defun in-block-1 (&rest problems)
  "PROBLEMS, each a form and what went wrong with it, as CHECK-BLOCKS
reports them for the first block of a.md."
  (mapcar (lambda (problem) (concatenate 'string "a.md: block 1: " problem)) problems))

(defun print-in-page (value)
  "VALUE as check-docs prints it, in a fresh page package."
  (let ((package (cl-commonmark-gfm.site::make-page-package)))
    (unwind-protect (cl-commonmark-gfm.site::print-value value package)
      (delete-package package))))

(defun package-names ()
  "The names of every package in this image."
  (mapcar #'package-name (list-all-packages)))

(defun block-problem (&rest code)
  "The problem READ-BLOCK finds with the first example of a block whose
lines are CODE, or NIL."
  (third (first (apply #'read-block code))))

(defun error-output-of (&rest blocks)
  "What CHECK-BLOCKS writes to *ERROR-OUTPUT* for a page made of BLOCKS."
  (let ((*error-output* (make-string-output-stream)))
    (apply #'check-blocks blocks)
    (get-output-stream-string *error-output*)))

(define-condition escaping-condition (serious-condition) ()
  (:documentation "A serious condition that isn't an error, so it gets past
CHECK-PAGE-EXAMPLES, which catches errors alone."))

;;; Finding the blocks

(defun treatments (&rest infos)
  "Each of INFOS, a code block's info string, with BLOCK-TREATMENT's
answer for it, as (INFO . TREATMENT)."
  (mapcar (lambda (info) (cons info (cl-commonmark-gfm.site::block-treatment info))) infos))

(define-test block-treatment-runs-lisp-and-skips-lisp-no-run
  (is equal '(("lisp" . :run) ("lisp no-run" . :skip))
      (treatments "lisp" "lisp no-run")))

(define-test block-treatment-refuses-any-other-name-for-lisp
  (is equal '(("lisp norun" . :refuse) ("lisp  no-run" . :refuse)
              ("lisp no-run now" . :refuse) ("lisp-no-run" . :refuse) ("lispy" . :refuse)
              ("Lisp" . :refuse) ("LISP no-run" . :refuse)
              ("common-lisp" . :refuse) ("Common-Lisp x" . :refuse)
              ("cl" . :refuse) ("CL x" . :refuse))
      (treatments "lisp norun" "lisp  no-run" "lisp no-run now" "lisp-no-run" "lispy"
                  "Lisp" "LISP no-run" "common-lisp" "Common-Lisp x" "cl" "CL x")))

(define-test block-treatment-skips-other-languages
  (is equal '(("python" . :skip) ("" . :skip) ("elisp" . :skip) ("emacs-lisp" . :skip)
              ("clojure" . :skip) ("clj" . :skip) ("c" . :skip))
      (treatments "python" "" "elisp" "emacs-lisp" "clojure" "clj" "c")))

(define-test lisp-blocks-are-the-lisp-fences-in-order
  (is equal (list (cons "lisp" (lines "(+ 1 2)"))
                  (cons "Lisp" (lines "(+ 7 8)"))
                  (cons "lisp" (lines "(+ 3 4)"))
                  (cons "lisp" (lines "(+ 5 6)")))
      (cl-commonmark-gfm.site::lisp-blocks
       (example-page (fence "lisp" "(+ 1 2)")
                     (fence "lisp no-run" "(launch)")
                     (fence "python" "1 + 2")
                     (fence "Lisp" "(+ 7 8)")
                     (fence "" "(no-language)")
                     (list "    (indented)" "")
                     (list "- A step:" "" "  ```lisp" "  (+ 3 4)" "  ```" "")
                     (fence "lisp" "(+ 5 6)")))))

;;; Reading a block

(define-test block-examples-reads-an-expectation-on-the-forms-line
  (is equal '(("(+ 1 2)" (:value "3") nil))
      (read-block "(+ 1 2) ;; => 3")))

(define-test block-examples-reads-an-expectation-on-a-following-line
  (is equal '(("(+ 1 2)" (:value "3") nil))
      (read-block "(+ 1 2)" ";; => 3"))
  (is equal '(("(+ 1 2)" (:value "3") nil))
      (read-block "(+ 1 2)" ";; The sum:" ";; => 3")))

(define-test block-examples-continues-an-expectation-until-a-line-isnt-a-comment
  (is equal '(("(list \"a\" \"b\")" (:value "(\"a\" \"b\")") nil))
      (read-block "(list \"a\" \"b\")" ";; => (\"a\"" ";;     \"b\")"))
  (is equal '(("(+ 1 2)" (:value "3 is the sum.") nil))
      (read-block "(+ 1 2)" ";; => 3" ";; is the sum."))
  (is equal '(("(+ 1 2)" (:value "3") nil))
      (read-block "(+ 1 2)" ";; => 3" "" ";; A remark.")))

(define-test block-examples-reads-each-form-with-its-own-expectation
  (is equal (list '("(+ 1 2)" (:value "3") nil)
                  (list (format nil "(list 1~%  2)") '(:value "(1 2)") nil)
                  '("(+ 3 4)" nil nil))
      (read-block "(+ 1 2) ;; => 3" "(list 1" "  2)" ";; => (1 2)" "(+ 3 4)")))

(define-test block-examples-reads-a-signals-name-in-the-page-package
  (is equal '(("(markdown->html 42)" (:signals type-error) nil))
      (read-block "(markdown->html 42) ;; signals type-error"))
  (is equal '(("(parse \"x\" :profile :nope)"
               (:signals cl-commonmark-gfm:invalid-parse-option) nil))
      (read-block "(parse \"x\" :profile :nope) ;; signals invalid-parse-option")))

(define-test block-examples-reads-a-form-with-neither-as-no-expectation
  (is equal '(("(+ 1 2)" nil nil))
      (read-block "(+ 1 2) ;; A remark." ";; signalling nothing.")))

(define-test block-examples-refuses-an-expectation-before-any-form
  (is equal '((";; => 3" nil "comes before any form") ("(+ 1 2)" nil nil))
      (read-block ";; => 3" "(+ 1 2)")))

(define-test block-examples-refuses-a-malformed-expectation
  (is equal '(("(+ 1 2)" nil "; => 3 needs two semicolons"))
      (read-block "(+ 1 2) ; => 3"))
  (is equal '(("(+ 1 2)" nil ";;; => 3 needs two semicolons"))
      (read-block "(+ 1 2) ;;; => 3"))
  (is equal '(("(+ 1 2)" nil ";; => 4 is a second expectation"))
      (read-block "(+ 1 2) ;; => 3" "" ";; => 4"))
  (is equal '(("(+ 1 2)" nil ";; signals type-error is a second expectation"))
      (read-block "(+ 1 2) ;; => 3" ";; signals type-error"))
  (is equal '(("(+ 1 2)" nil ";; => holds no value"))
      (read-block "(+ 1 2) ;; =>"))
  (is equal '(("(+ 1 2)" nil ";; signals names no condition"))
      (read-block "(+ 1 2) ;; signals")))

(define-test block-examples-stops-at-text-it-cant-read
  (let* ((examples (read-block "(+ 1 2) ;; => 3" "(+ 1" ";; => 4"))
         (unread (second examples)))
    (is equal '("(+ 1 2)" (:value "3") nil) (first examples))
    (is equal (list (format nil "(+ 1~%;; => 4~%") nil) (subseq unread 0 2))
    (true (eql 0 (search "can't be read: end of file" (third unread))))
    (is = 2 (length examples))))

(define-test block-examples-reads-a-marker-after-a-block-comment
  (is equal '(("(+ 1 2)" (:value "3") nil))
      (read-block "(+ 1 2) #| A remark. |# ;; => 3"))
  (is equal '(("(+ 1 2)" (:value "3") nil))
      (read-block "(+ 1 2)" "#| A remark" "   over two lines. |# ;; => 3"))
  (is equal '(("(+ 1 2)" (:value "3") nil))
      (read-block "(+ 1 2)" "#| A remark. |#" ";; => 3")))

(define-test block-examples-refuses-other-spellings-of-a-marker
  (is equal (list "write ;; ==> 4 as ;; => 4"
                  "write ;; -> 4 as ;; => 4"
                  (format nil "write ;; ~C 4 as ;; => 4" (code-char #x2192))
                  (format nil "write ;; ~C 4 as ;; => 4" (code-char #x21D2))
                  "write ; ==> 4 as ;; => 4")
      (list (block-problem "(+ 1 2) ;; ==> 4")
            (block-problem "(+ 1 2) ;; -> 4")
            (block-problem (format nil "(+ 1 2) ;; ~C 4" (code-char #x2192)))
            (block-problem (format nil "(+ 1 2) ;; ~C 4" (code-char #x21D2)))
            (block-problem "(+ 1 2) ; ==> 4")))
  (is equal '("write ;; Signals type-error as ;; signals type-error"
              "write ;; signals: type-error as ;; signals type-error"
              "write ;; signal type-error as ;; signals type-error"
              "write ;; SIGNAL: type-error as ;; signals type-error")
      (list (block-problem "(+ 1 2) ;; Signals type-error")
            (block-problem "(+ 1 2) ;; signals: type-error")
            (block-problem "(+ 1 2) ;; signal type-error")
            (block-problem "(+ 1 2) ;; SIGNAL: type-error"))))

(define-test block-examples-refuses-the-past-tense-and-a-long-arrow
  (is equal '("write ;; signalled type-error as ;; signals type-error"
              "write ;; Signalled: type-error as ;; signals type-error"
              "write ;; signaled type-error as ;; signals type-error"
              "write ;; --> 4 as ;; => 4")
      (list (block-problem "(+ 1 2) ;; signalled type-error")
            (block-problem "(+ 1 2) ;; Signalled: type-error")
            (block-problem "(+ 1 2) ;; signaled type-error")
            (block-problem "(+ 1 2) ;; --> 4"))))

(define-test block-examples-reads-other-comments-as-remarks
  (is equal '(("(+ 1 2)" nil nil) ("(+ 3 4)" nil nil))
      (read-block "(+ 1 2) ;; = 4" "(+ 3 4) ;; returns 7")))

(define-test block-examples-refuses-a-marker-inside-a-form
  (is equal (list (list (format nil "(list 1 ;; => (9 9)~%2)") nil
                        ";; => (9 9) is inside the form, so it checks nothing"))
      (read-block "(list 1 ;; => (9 9)" "2)")))

(define-test block-examples-finds-no-comment-inside-a-token
  (is equal '(nil nil nil nil nil nil)
      (list (block-problem "(list \";; => 1\")")
            (block-problem "(list \"a\\\" ;; => 2\")")
            (block-problem "(list #\\; => 3)")
            (block-problem "(list '|;; => 4|)")
            (block-problem "(list 'a\\; => 5)")
            (block-problem "(list #| a|b ;; => 6 |# 7)"))))

(define-test block-examples-refuses-reader-conditionals
  (is equal (list (list (format nil "#+nil (+ 1 2) ;; => 4~%") nil
                        "uses #+ or #-, which can hide an expectation"))
      (read-block "#+nil (+ 1 2) ;; => 4"))
  (is equal (list '("(+ 1 1)" (:value "2") nil)
                  (list (format nil "(list 1 #-nil 2)~%") nil
                        "uses #+ or #-, which can hide an expectation"))
      (read-block "(+ 1 1) ;; => 2" "(list 1 #-nil 2)")))

(define-test block-examples-reads-with-read-eval-off
  (let ((examples (read-block "#.(+ 1 2) ;; => 3")))
    (is equal (list (format nil "#.(+ 1 2) ;; => 3~%") nil)
        (subseq (first examples) 0 2))
    (true (eql 0 (search "can't be read: " (third (first examples)))))
    (is = 1 (length examples))))

;;; Printing and comparing

(define-test print-value-writes-each-newline-as-backslash-n
  (is string= "\"<p><em>hi</em></p>\\n\""
      (print-in-page (cl-commonmark-gfm:markdown->html "*hi*")))
  (is string= "((:p nil (:em nil \"hi\")) \"\\n\")"
      (print-in-page (cl-commonmark-gfm:markdown->html-tree "*hi*"))))

(define-test print-value-writes-symbols-in-lower-case-as-the-page-sees-them
  (is string= ":document"
      (print-in-page (cl-commonmark-gfm:node-kind (cl-commonmark-gfm:parse "*hi*"))))
  (is string= "parse" (print-in-page 'cl-commonmark-gfm:parse)))

(define-test print-value-prints-a-long-list-on-one-line
  (let ((printed (print-in-page (make-list 30 :initial-element "abcdef"))))
    (is string= (format nil "(~{~S~^ ~})" (make-list 30 :initial-element "abcdef")) printed)))

(define-test same-text-p-compares-runs-of-whitespace-as-one-space
  (true (cl-commonmark-gfm.site::same-text-p (format nil "(1  2~%~C 3)" #\Tab) " (1 2 3) "))
  (parachute:false (cl-commonmark-gfm.site::same-text-p "(1 2 3)" "(1 23)")))

;;; Running a page's examples

(define-test check-page-examples-passes-a-page-whose-examples-hold
  (is equal '(() 7)
      (check-blocks (fence "lisp"
                           "(+ 1 2) ;; => 3"
                           "(markdown->html \"*hi*\")"
                           ";; => \"<p><em>hi</em></p>\\n\""
                           "(list 1 2) ;; =>   (1"
                           ";;                  2)"
                           "(values 1 2) ;; => 1"
                           "(markdown->html 42) ;; signals type-error"
                           "(parse \"x\" :profile :nope) ;; signals commonmark-gfm-error"
                           "(+ 3 4)"))))

(define-test check-page-examples-names-the-page-the-block-and-the-form
  (is equal '(("a.md: block 2: (+ 2 2): expected 5, got 4") 3)
      (check-blocks (fence "lisp" "(+ 1 2) ;; => 3")
                    (fence "lisp no-run" "(+ 1 1) ;; => 3")
                    (fence "python" "1 + 1")
                    (fence "lisp" "(+ 1 1) ;; => 2" "(+ 2 2) ;; => 5"))))

(define-test check-page-examples-puts-a-long-form-on-one-short-line
  (is equal (list (in-block-1 (concatenate 'string
                                           "(length (list \"aaaaaaaaaa\" \"bbbbbbbbbb\" "
                                           "\"cccccccccc\" \"ddd...: expected 4, got 5"))
                  1)
      (check-blocks (fence "lisp"
                           "(length (list \"aaaaaaaaaa\" \"bbbbbbbbbb\""
                           "              \"cccccccccc\" \"dddddddddd\" \"eeeeeeeeee\"))"
                           ";; => 4"))))

(define-test check-page-examples-reports-what-it-cant-read
  (is equal (list (in-block-1 ";; => 3: comes before any form"
                              "(+ 1 2): ; => 3 needs two semicolons")
                  1)
      (check-blocks (fence "lisp" ";; => 3" "(+ 1 2) ; => 3"))))

(define-test check-page-examples-refuses-lisp-blocks-it-wouldnt-run
  (let ((fix ": fence it ```lisp to run it, or ```lisp no-run to skip it"))
    (is equal (list (list (concatenate 'string "a.md: block 1: info string \"lisp norun\"" fix)
                          (concatenate 'string "a.md: block 2: info string \"common-lisp\"" fix)
                          (concatenate 'string "a.md: block 3: info string \"cl\"" fix)
                          (concatenate 'string "a.md: block 4: info string \"Lisp\"" fix))
                    1)
        (check-blocks (fence "lisp norun" "(+ 1 2) ;; => 4")
                      (fence "common-lisp" "(+ 1 2) ;; => 4")
                      (fence "cl" "(+ 1 2) ;; => 4")
                      (fence "Lisp" "(+ 1 2) ;; => 4")
                      (fence "lisp no-run" "(+ 1 2) ;; => 4")
                      (fence "python" "(+ 1 2) ;; => 4")
                      (fence "lisp" "(+ 1 2) ;; => 3")))))

(define-test check-page-examples-shows-a-refused-info-string-as-written
  (is equal (list (in-block-1 (concatenate 'string
                                           "info string \"lisp  no-run\": fence it ```lisp to "
                                           "run it, or ```lisp no-run to skip it"))
                  0)
      (check-blocks (fence "lisp  no-run" "(+ 1 2) ;; => 4"))))

(define-test check-page-examples-refuses-a-warning
  (is equal (list (in-block-1 "(progn (warn \"Careful.\") 3): warned simple-warning: Careful.") 1)
      (check-blocks (fence "lisp" "(progn (warn \"Careful.\") 3) ;; => 3"))))

(define-test check-page-examples-refuses-the-compilers-warning
  (destructuring-bind (problems examples)
      (check-blocks (fence "lisp" "(defun review-h (x) (+ x review-free-y))"))
    (is equal '(1 1) (list (length problems) examples))
    (true (eql 0 (search (concatenate 'string
                                      "a.md: block 1: (defun review-h (x) (+ x review-free-y)): "
                                      "warned simple-warning: undefined variable: ")
                         (first problems)))))
  (is string= "" (error-output-of (fence "lisp" "(defun review-i (x) (+ x review-free-z))"))))

(define-test check-page-examples-refuses-a-warning-whatever-it-returns
  (is equal (list (in-block-1 (concatenate 'string
                                           "(progn (warn \"Careful.\") (error \"Boom.\")): "
                                           "warned simple-warning: Careful."))
                  1)
      (check-blocks (fence "lisp" "(progn (warn \"Careful.\") (error \"Boom.\"))"
                           ";; signals simple-error"))))

(define-test check-page-examples-refuses-reader-conditionals
  (is equal (list (in-block-1 (concatenate 'string
                                           "#+nil (+ 1 2) ;; => 4: "
                                           "uses #+ or #-, which can hide an expectation"))
                  0)
      (check-blocks (fence "lisp" "#+nil (+ 1 2) ;; => 4"))))

(define-test check-page-examples-checks-a-marker-after-a-block-comment
  (is equal (list (in-block-1 "(+ 1 2): expected 4, got 3") 2)
      (check-blocks (fence "lisp" "(+ 1 2) #| A remark. |# ;; => 4"
                           "(+ 1 2) #| A remark. |# ;; => 3"))))

(define-test check-page-examples-refuses-a-form-that-changes-the-package
  (is equal (list (in-block-1 (concatenate 'string
                                           "(in-package :cl-user): sets *package* to "
                                           "#<package \"COMMON-LISP-USER\">, but each form is "
                                           "read in the page's package"))
                  2)
      (check-blocks (fence "lisp" "(in-package :cl-user)" "(+ 1 2) ;; => 3"))))

(defun noted-fence ()
  "A block whose example has the compiler make a note: it compiles a
function with SPEED, whose generic arithmetic SBCL notes."
  (fence "lisp"
         "(funcall (compile nil '(lambda (x) (declare (optimize speed)) (+ x 1)))"
         "         2)"
         ";; => 3"))

(define-test check-page-examples-muffles-the-compilers-remarks
  (is string= "" (error-output-of (fence "lisp" "(defun call-nothing () (no-such-function 1))")))
  (is string= "" (error-output-of (noted-fence))))

(define-test check-page-examples-passes-the-compilers-remarks
  (is equal '(() 1) (check-blocks (fence "lisp" "(defun call-nothing () (no-such-function 1))")))
  (is equal '(() 1) (check-blocks (noted-fence))))

(define-test check-examples-keeps-a-setf-of-a-library-variable-on-its-page
  (let ((cl-commonmark-gfm:*max-nodes* cl-commonmark-gfm:*max-nodes*))
    (let* ((before cl-commonmark-gfm:*max-nodes*)
           (result (multiple-value-list
                    (cl-commonmark-gfm.site::check-examples
                     (list (cons "a.md" (example-page (fence "lisp" "(setf *max-nodes* 3)")))
                           (cons "b.md" (example-page (fence "lisp" "(+ 1 2) ;; => 3"))))))))
      (is equal '(() 2 2) result)
      (is = before cl-commonmark-gfm:*max-nodes*))))

(define-test check-examples-reports-a-page-it-cant-parse
  (destructuring-bind (problems examples pages)
      (let ((cl-commonmark-gfm:*max-input-octets* 10))
        (multiple-value-list
         (cl-commonmark-gfm.site::check-examples
          (list (cons "a.md" (example-page (fence "lisp" "(+ 1 2) ;; => 3")))
                (cons "b.md" (lines "# B"))))))
    (is equal '(1 0 0) (list (length problems) examples pages))
    (true (eql 0 (search "a.md: can't be parsed: signalled resource-limit-exceeded: "
                         (first problems))))))

(define-test check-examples-advises-the-guards-pattern-in-a-code-block
  (let ((markdown (example-page (fence "lisp" "\"[&#94;\""))))
    (destructuring-bind (problems examples pages)
        (multiple-value-list
         (cl-commonmark-gfm.site::check-examples (list (cons "a.md" markdown))))
      (is equal '(1 0 0) (list (length problems) examples pages))
      (is equal (list (format nil "a.md: can't be parsed: signalled unsupported-input: ~A; ~
                                   write its & as &amp; outside code; as code, split it ~
                                   into two code spans with a word between; in a Lisp ~
                                   example, build the string from two pieces, as ~
                                   (concatenate 'string \"[\" \"&#94;\")"
                              (parse-report markdown)))
          problems))))

(define-test check-page-examples-refuses-an-error-without-signals
  (is equal (list (in-block-1 "(error \"Boom.\"): signalled simple-error: Boom."
                              "(error \"Bang.\"): expected 3, but signalled simple-error: Bang.")
                  2)
      (check-blocks (fence "lisp" "(error \"Boom.\")" "(error \"Bang.\") ;; => 3"))))

(define-test check-page-examples-checks-signals-by-type-and-subtype
  (is equal (list (in-block-1 "(+ 1 2): expected to signal type-error, but returned 3"
                              (concatenate 'string
                                           "(error \"Boom.\"): expected to signal type-error, "
                                           "but signalled simple-error: Boom.")
                              "(+ 1 2): expected to signal warning, which isn't a subtype of error"
                              (concatenate 'string
                                           "(+ 1 2): expected to signal no-such-condition, "
                                           "which isn't a subtype of error"))
                  6)
      (check-blocks (fence "lisp"
                           "(markdown->html 42) ;; signals type-error"
                           "(parse \"x\" :profile :nope) ;; signals commonmark-gfm-error"
                           "(+ 1 2) ;; signals type-error"
                           "(error \"Boom.\") ;; signals type-error"
                           "(+ 1 2) ;; signals warning"
                           "(+ 1 2) ;; signals no-such-condition"))))

(define-test check-page-examples-discards-what-an-example-prints
  (let* ((output (make-string-output-stream))
         (result (let ((*standard-output* output))
                   (check-blocks (fence "lisp" "(progn (print \"Noise.\") 3) ;; => 3"))))
         (printed (get-output-stream-string output)))
    (is equal '(() 1) result)
    (is string= "" printed)))

(define-test check-examples-shares-definitions-within-a-page-alone
  (is equal '(() 3 2)
      (multiple-value-list
       (cl-commonmark-gfm.site::check-examples
        (list (cons "a.md" (example-page (fence "lisp" "(defun twice (x) (* 2 x))")
                                         (fence "lisp" "(twice 21) ;; => 42")))
              (cons "b.md" (example-page (fence "lisp no-run" "(twice 21)")))
              (cons "c.md" (example-page (fence "lisp" "(fboundp 'twice) ;; => nil"))))))))

(define-test check-page-examples-deletes-its-package
  (let* ((before (package-names))
         (result (check-blocks (fence "lisp" "(+ 1 2) ;; => 3")))
         (left (set-difference (package-names) before :test #'string=)))
    (is equal '(() 1) result)
    (is equal '() left)))

(define-test check-page-examples-deletes-its-package-whatever-happens
  (let* ((before (package-names))
         (escaped (handler-case
                      (progn
                        (check-blocks
                         (fence "lisp" "(error 'cl-commonmark-gfm.site.tests::escaping-condition)"))
                        nil)
                    (escaping-condition () t)))
         (left (set-difference (package-names) before :test #'string=)))
    (true escaped)
    (is equal '() left)))
