;;;; Tests for PROPER-LIST-P: proper, dotted, circular, non-list and huge
;;;; inputs; for the UTF-8 encoder, CHAR-UTF8-OCTETS, UTF8-LENGTH and
;;;; ENCODE-UTF8; and for the decoder, DECODE-UTF8.

(in-package #:cl-commonmark-gfm.tests)

;;; Proper lists

(define-test proper-list-p-true-for-nil
  (true (proper-list-p nil)))

(define-test proper-list-p-true-for-one-element
  (true (proper-list-p (list 1))))

(define-test proper-list-p-true-for-several-elements
  (true (proper-list-p (list 1 2 3 4 5))))

;;; Dotted lists

(define-test proper-list-p-false-for-a-dotted-pair
  (false (proper-list-p (cons 1 2))))

(define-test proper-list-p-false-for-a-dotted-list
  (false (proper-list-p (list* 1 2 3))))

;;; Circular lists, built at run time -- never with #1= read syntax, so the
;;; reader is never asked to parse a circular datum.

(define-test proper-list-p-false-for-a-cycle-of-length-1
  (let ((list (list 1)))
    (setf (cdr list) list)
    (false (proper-list-p list))))

(define-test proper-list-p-false-for-a-cycle-of-length-2
  (let ((list (list 1 2)))
    (setf (cdr (last list)) list)
    (false (proper-list-p list))))

(define-test proper-list-p-false-for-a-cycle-of-length-3
  (let ((list (list 1 2 3)))
    (setf (cdr (last list)) list)
    (false (proper-list-p list))))

(define-test proper-list-p-false-for-a-cycle-entered-after-a-prefix
  ;; 1 -> 2 -> 3 -> 4 -> 5 -> back to the cons holding 3: a two-element
  ;; acyclic prefix (1 2), then a cycle of length 3 (3 4 5).
  (let* ((list (list 1 2 3 4 5))
         (cycle-start (cddr list)))
    (setf (cdr (last list)) cycle-start)
    (false (proper-list-p list))))

;;; Non-lists

(define-test proper-list-p-false-for-a-string
  (false (proper-list-p "abc")))

(define-test proper-list-p-false-for-a-vector
  (false (proper-list-p (vector 1 2 3))))

(define-test proper-list-p-false-for-a-number
  (false (proper-list-p 42)))

;;; A huge proper list: PROPER-LIST-P must walk it in a loop, not recurse

(define-test proper-list-p-true-for-a-3-000-000-element-list
  (true (proper-list-p (make-list 3000000))))

;;; CHAR-UTF8-OCTETS: encoding-length boundaries. HREF-ENCODE's own tests,
;;; its lone surrogate among them, are in tests/url.lisp.

(define-test char-utf8-octets-one-byte-boundary
  (is equal '(#x7F) (char-utf8-octets (code-char #x7F)))
  (is equal '(#xC2 #x80) (char-utf8-octets (code-char #x80))))

(define-test char-utf8-octets-two-byte-boundary
  (is equal '(#xDF #xBF) (char-utf8-octets (code-char #x7FF)))
  (is equal '(#xE0 #xA0 #x80) (char-utf8-octets (code-char #x800))))

(define-test char-utf8-octets-three-byte-boundary
  (is equal '(#xEF #xBF #xBF) (char-utf8-octets (code-char #xFFFF)))
  (is equal '(#xF0 #x90 #x80 #x80) (char-utf8-octets (code-char #x10000))))

(define-test char-utf8-octets-largest-code-point
  (is equal '(#xF4 #x8F #xBF #xBF) (char-utf8-octets (code-char #x10FFFF))))

(define-test char-utf8-octets-nul-is-one-zero-octet
  (is equal '(0) (char-utf8-octets #\Nul)))

;;; Lone surrogates encode as U+FFFD, EF BF BD, everywhere. On SBCL and ECL,
;;; (CODE-CHAR #xD800) is a character; on CCL it is NIL, so CCL asserts that
;;; fact instead, so every Lisp still asserts something real.

#-ccl
(define-test char-utf8-octets-lone-surrogate-is-the-replacement-character
  (is equal '(#xEF #xBF #xBD) (char-utf8-octets (code-char #xD800))))

#+ccl
(define-test char-utf8-octets-lone-surrogate-is-the-replacement-character
  (false (code-char #xD800)))

;;; UTF8-LENGTH

(define-test utf8-length-of-the-empty-string
  (is = 0 (utf8-length "")))

(define-test utf8-length-boundaries
  (is = 1 (utf8-length (string (code-char #x7F))))
  (is = 2 (utf8-length (string (code-char #x80))))
  (is = 2 (utf8-length (string (code-char #x7FF))))
  (is = 3 (utf8-length (string (code-char #x800))))
  (is = 3 (utf8-length (string (code-char #xFFFF))))
  (is = 4 (utf8-length (string (code-char #x10000))))
  (is = 4 (utf8-length (string (code-char #x10FFFF)))))

(define-test utf8-length-counts-nul-as-one-octet
  (is = 1 (utf8-length (string #\Nul))))

#-ccl
(define-test utf8-length-counts-a-lone-surrogate-as-three-octets
  (is = 3 (utf8-length (string (code-char #xD800)))))

#+ccl
(define-test utf8-length-counts-a-lone-surrogate-as-three-octets
  (false (code-char #xD800)))

;;; ENCODE-UTF8: the count it returns, and the octets it writes. These build
;;; their vectors inside a small local helper, never around an assertion:
;;; Parachute keeps each assertion's closure, and whatever it captures, until
;;; the run ends. These vectors are tiny, but the native tests' large values
;;; need the same habit.

(defun encode-utf8-into-fresh-vector (string)
  "Encode STRING with ENCODE-UTF8 into a freshly made vector sized by
UTF8-LENGTH, and return (VALUES OCTETS COUNT)."
  (let* ((octets (make-array (utf8-length string) :element-type '(unsigned-byte 8)))
         (count (encode-utf8 string octets)))
    (values octets count)))

(define-test encode-utf8-of-the-empty-string
  (multiple-value-bind (octets count) (encode-utf8-into-fresh-vector "")
    (is = 0 count)
    (is = 0 (length octets))))

(define-test encode-utf8-count-agrees-with-utf8-length-on-a-mixed-string
  ;; "A" (1 byte) + U+00E9 e-acute (2 bytes) + U+20AC euro sign (3 bytes) +
  ;; U+1D11E musical G clef (4 bytes): 10 octets in all. The expected octets
  ;; are written out by hand (tests/url.lisp's HREF-ENCODE tests confirm the
  ;; same four UTF-8 sequences independently), not derived from CHAR-UTF8-OCTETS.
  (let ((string (coerce (list #\A (code-char #xE9) (code-char #x20AC) (code-char #x1D11E))
                         'string)))
    (multiple-value-bind (octets count) (encode-utf8-into-fresh-vector string)
      (is = (utf8-length string) count)
      (is = 10 count)
      (true (equalp #(#x41 #xC3 #xA9 #xE2 #x82 #xAC #xF0 #x9D #x84 #x9E) octets)))))

(define-test encode-utf8-writes-from-index-0-into-a-larger-vector
  (let ((octets (make-array 8 :element-type '(unsigned-byte 8) :initial-element 99)))
    (is = 1 (encode-utf8 "A" octets))
    (is = (char-code #\A) (aref octets 0))
    (is = 99 (aref octets 1))))

#-ccl
(define-test encode-utf8-writes-a-lone-surrogate-as-the-replacement-character
  (multiple-value-bind (octets count)
      (encode-utf8-into-fresh-vector (string (code-char #xD800)))
    (is = 3 count)
    (true (equalp #(#xEF #xBF #xBD) octets))))

#+ccl
(define-test encode-utf8-writes-a-lone-surrogate-as-the-replacement-character
  (false (code-char #xD800)))

;;; DECODE-UTF8: octets to a string, with one U+FFFD for each maximal
;;; subpart of an ill-formed sequence, as the Unicode Standard recommends
;;; (§3.9, "U+FFFD Substitution of Maximal Subparts"; Table 3-7 lists the
;;; well-formed byte sequences). cmark can hand back ill-formed UTF-8, as
;;; when it cuts a dangling footnote label inside a character.

(defun octets (&rest values)
  "A fresh (UNSIGNED-BYTE 8) vector holding VALUES."
  (make-array (length values) :element-type '(unsigned-byte 8) :initial-contents values))

(defun decoded-codes (&rest values)
  "The code of each character DECODE-UTF8 makes of the octets VALUES."
  (map 'list #'char-code (cl-commonmark-gfm.util:decode-utf8 (apply #'octets values))))

(defconstant +replacement+ #xFFFD
  "U+FFFD, the replacement character.")

(define-test decode-utf8-of-no-octets-is-the-empty-string
  (is string= "" (cl-commonmark-gfm.util:decode-utf8 (octets))))

(define-test decode-utf8-well-formed-sequences-of-every-length
  ;; Each row of Table 3-7, at its first and last code point.
  (is equal '(#x00) (decoded-codes #x00))
  (is equal '(#x7F) (decoded-codes #x7F))
  (is equal '(#x80) (decoded-codes #xC2 #x80))
  (is equal '(#x7FF) (decoded-codes #xDF #xBF))
  (is equal '(#x800) (decoded-codes #xE0 #xA0 #x80))
  (is equal '(#xFFF) (decoded-codes #xE0 #xBF #xBF))
  (is equal '(#x1000) (decoded-codes #xE1 #x80 #x80))
  (is equal '(#xCFFF) (decoded-codes #xEC #xBF #xBF))
  (is equal '(#xD000) (decoded-codes #xED #x80 #x80))
  (is equal '(#xD7FF) (decoded-codes #xED #x9F #xBF))
  (is equal '(#xE000) (decoded-codes #xEE #x80 #x80))
  (is equal '(#xFFFF) (decoded-codes #xEF #xBF #xBF))
  (is equal '(#x10000) (decoded-codes #xF0 #x90 #x80 #x80))
  (is equal '(#x3FFFF) (decoded-codes #xF0 #xBF #xBF #xBF))
  (is equal '(#x40000) (decoded-codes #xF1 #x80 #x80 #x80))
  (is equal '(#xFFFFF) (decoded-codes #xF3 #xBF #xBF #xBF))
  (is equal '(#x100000) (decoded-codes #xF4 #x80 #x80 #x80))
  (is equal '(#x10FFFF) (decoded-codes #xF4 #x8F #xBF #xBF)))

(defun every-scalar-value ()
  "A string of every Unicode scalar value, U+0000 to U+10FFFF without the
surrogates, in order."
  (let ((string (make-string (- #x110000 #x800))))
    (loop with index = 0
          for code from 0 below #x110000
          unless (<= #xD800 code #xDFFF)
            do (setf (char string index) (code-char code))
               (incf index))
    string))

(defun every-scalar-value-round-trips-p ()
  "True when DECODE-UTF8 turns ENCODE-UTF8's octets for EVERY-SCALAR-VALUE
back into the same string: every well-formed sequence of every length."
  (let* ((string (every-scalar-value))
         (octets (make-array (utf8-length string) :element-type '(unsigned-byte 8))))
    (encode-utf8 string octets)
    (string= string (cl-commonmark-gfm.util:decode-utf8 octets))))

(define-test decode-utf8-round-trips-every-scalar-value
  (true (every-scalar-value-round-trips-p)))

(define-test decode-utf8-replaces-lone-continuation-octets
  (is equal (list +replacement+) (decoded-codes #x80))
  (is equal (list +replacement+) (decoded-codes #xBF))
  (is equal (list +replacement+ +replacement+) (decoded-codes #x80 #xBF))
  (is equal (list #x61 +replacement+ #x62) (decoded-codes #x61 #x80 #x62)))

(define-test decode-utf8-replaces-truncated-sequences
  ;; One U+FFFD for the whole start of a sequence, and the octet that cut
  ;; it short decoded on its own.
  (is equal (list +replacement+) (decoded-codes #xC2))
  (is equal (list +replacement+) (decoded-codes #xE1 #x80))
  (is equal (list +replacement+) (decoded-codes #xF1 #x80 #x80))
  (is equal (list +replacement+ #x41) (decoded-codes #xC2 #x41))
  (is equal (list +replacement+ #x41) (decoded-codes #xE1 #x80 #x41))
  (is equal (list +replacement+ #x41) (decoded-codes #xF1 #x80 #x80 #x41))
  (is equal (list +replacement+ #xE9) (decoded-codes #xE1 #x80 #xC3 #xA9)))

(define-test decode-utf8-replaces-overlong-forms
  ;; C0 and C1 never start a sequence; E0 needs A0 or more next, F0 90.
  (is equal (list +replacement+ +replacement+) (decoded-codes #xC0 #x80))
  (is equal (list +replacement+ +replacement+) (decoded-codes #xC1 #xBF))
  (is equal (list +replacement+ +replacement+ +replacement+) (decoded-codes #xE0 #x80 #x80))
  (is equal (list +replacement+ +replacement+ +replacement+) (decoded-codes #xE0 #x9F #xBF))
  (is equal (make-list 4 :initial-element +replacement+) (decoded-codes #xF0 #x80 #x80 #x80))
  (is equal (make-list 4 :initial-element +replacement+) (decoded-codes #xF0 #x8F #xBF #xBF)))

(define-test decode-utf8-replaces-surrogates
  ;; ED A0..BF would start U+D800 to U+DFFF.
  (is equal (list +replacement+ +replacement+ +replacement+) (decoded-codes #xED #xA0 #x80))
  (is equal (list +replacement+ +replacement+ +replacement+) (decoded-codes #xED #xBF #xBF)))

(define-test decode-utf8-replaces-code-points-above-u+10ffff
  (is equal (make-list 4 :initial-element +replacement+) (decoded-codes #xF4 #x90 #x80 #x80))
  (is equal (make-list 4 :initial-element +replacement+) (decoded-codes #xF5 #x80 #x80 #x80))
  (is equal (make-list 4 :initial-element +replacement+) (decoded-codes #xF7 #xBF #xBF #xBF)))

(define-test decode-utf8-replaces-octets-that-start-nothing
  ;; C0, C1 and F5 to FF, alone.
  (dolist (octet (list* #xC0 #xC1 (loop for octet from #xF5 to #xFF collect octet)))
    (is equal (list +replacement+) (decoded-codes octet) "~2,'0X" octet)))

(define-test decode-utf8-replaces-each-maximal-subpart-once
  ;; F0 80 80: 80 can't follow F0, so F0 alone is the subpart, then each 80.
  ;; E1 80: a 3-octet sequence cut short, one subpart.
  (is equal (make-list 3 :initial-element +replacement+) (decoded-codes #xF0 #x80 #x80))
  (is equal (list +replacement+) (decoded-codes #xE1 #x80))
  ;; The Unicode Standard's own examples (§3.9), in turn: a mix; non-shortest
  ;; forms; surrogates; other ill-formed sequences; truncated sequences.
  (is equal (list #x61 +replacement+ +replacement+ +replacement+ #x62 +replacement+ #x63
                  +replacement+ +replacement+ #x64)
      (decoded-codes #x61 #xF1 #x80 #x80 #xE1 #x80 #xC2 #x62 #x80 #x63 #x80 #xBF #x64))
  (is equal (append (make-list 8 :initial-element +replacement+) (list #x41))
      (decoded-codes #xC0 #xAF #xE0 #x80 #xBF #xF0 #x81 #x82 #x41))
  (is equal (append (make-list 8 :initial-element +replacement+) (list #x41))
      (decoded-codes #xED #xA0 #x80 #xED #xBF #xBF #xED #xAF #x41))
  (is equal (append (make-list 5 :initial-element +replacement+)
                    (list #x41 +replacement+ +replacement+ #x42))
      (decoded-codes #xF4 #x91 #x92 #x93 #xFF #x41 #x80 #xBF #x42))
  (is equal (append (make-list 4 :initial-element +replacement+) (list #x41))
      (decoded-codes #xE1 #x80 #xE2 #xF0 #x91 #x92 #xF1 #xBF #x41)))

(define-test decode-utf8-reads-from-start-to-end
  ;; C3 A9 is é; END cuts it short, START skips into its middle.
  (let ((octets (octets #x61 #xC3 #xA9 #x62)))
    (is string= (format nil "a~Cb" (code-char #xE9)) (cl-commonmark-gfm.util:decode-utf8 octets))
    (is string= (format nil "~Cb" (code-char #xE9))
        (cl-commonmark-gfm.util:decode-utf8 octets :start 1))
    (is string= "a" (cl-commonmark-gfm.util:decode-utf8 octets :end 1))
    (is string= (string (code-char +replacement+))
        (cl-commonmark-gfm.util:decode-utf8 octets :start 1 :end 2))
    (is string= (string (code-char +replacement+))
        (cl-commonmark-gfm.util:decode-utf8 octets :start 2 :end 3))))

(defun shorter-decodings ()
  "Every two-octet sequence whose decoding is shorter in UTF-8 than its two
octets, as a list of (FIRST SECOND)."
  (loop for first below 256
        nconc (loop for second below 256
                    when (< (utf8-length (cl-commonmark-gfm.util:decode-utf8
                                          (octets first second)))
                            2)
                      collect (list first second))))

(define-test decode-utf8-is-never-shorter-in-utf-8-than-its-octets
  ;; A maximal subpart is 1 to 3 octets and U+FFFD is 3.
  (is equal '() (shorter-decodings)))

;;; DECODE-UTF8's bounds: START and END must satisfy (<= 0 START END
;;; (LENGTH OCTETS)), checked before any octet is read, so a bad index
;;; signals the same SIMPLE-TYPE-ERROR, naming it, on every Lisp. Unchecked,
;;; a start past the end would decode nothing, and an index outside the
;;; vector would reach AREF, which each Lisp reports its own way.

(defun decode-utf8-bounds-error (start end)
  "What DECODE-UTF8 signals for START and END over four octets, as the list
(TYPE DATUM EXPECTED-TYPE); the last two are NIL for a condition that isn't
a TYPE-ERROR. :RETURNED when it returns."
  (handler-case (progn (cl-commonmark-gfm.util:decode-utf8 (octets #x61 #x62 #x63 #x64)
                                                           :start start :end end)
                       :returned)
    (error (condition)
      (list (type-of condition)
            (and (typep condition 'type-error) (type-error-datum condition))
            (and (typep condition 'type-error) (type-error-expected-type condition))))))

(define-test decode-utf8-rejects-a-start-past-its-end
  (is equal '(simple-type-error 3 (integer 0 2)) (decode-utf8-bounds-error 3 2)))

(define-test decode-utf8-rejects-an-end-past-its-octets
  (is equal '(simple-type-error 5 (integer 0 4)) (decode-utf8-bounds-error 0 5)))

(define-test decode-utf8-rejects-a-negative-start
  (is equal '(simple-type-error -1 (integer 0 4)) (decode-utf8-bounds-error -1 nil)))

(define-test decode-utf8-accepts-every-bound-at-its-limit
  ;; START at END, both at the vector's length, and END at the length.
  (is string= "" (cl-commonmark-gfm.util:decode-utf8 (octets #x61 #x62) :start 2 :end 2))
  (is string= "" (cl-commonmark-gfm.util:decode-utf8 (octets #x61 #x62) :start 2))
  (is string= "ab" (cl-commonmark-gfm.util:decode-utf8 (octets #x61 #x62) :start 0 :end 2)))
