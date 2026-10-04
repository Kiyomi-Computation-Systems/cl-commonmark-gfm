;;;; The cl-commonmark-gfm.util package: small helpers that depend on
;;;; nothing, shared by the pure and the native systems: a stack-safe
;;;; PROPER-LIST-P, a UTF-8 encoder for the URL helpers and the native
;;;; layer, and a UTF-8 decoder for the strings cmark-gfm returns.

(defpackage #:cl-commonmark-gfm.util
  (:use #:cl)
  (:export #:proper-list-p
           #:char-utf8-octets
           #:utf8-length
           #:encode-utf8
           #:decode-utf8))

(in-package #:cl-commonmark-gfm.util)

;;; PROPER-LIST-P

(defun proper-list-p (value)
  "True when VALUE is a finite, NIL-terminated (proper) list. Uses Floyd's
cycle detection, so a circular list is rejected rather than looping forever."
  (and (listp value)
       (or (null value)
           (loop for slow = value then (cdr slow)
                 for fast = (cdr value) then (cddr fast)
                 do (cond
                      ((null fast) (return t))
                      ((atom fast) (return nil))
                      ((null (cdr fast)) (return t))
                      ((atom (cdr fast)) (return nil))
                      ((eql slow (cdr fast)) (return nil)))))))

;;; UTF-8 code-point arithmetic, shared by CHAR-UTF8-OCTETS, UTF8-LENGTH and
;;; ENCODE-UTF8. All three treat a lone surrogate (U+D800 to U+DFFF) as
;;; U+FFFD, the replacement character, so cmark never has to see one: on
;;; SBCL and ECL, CODE-CHAR returns a character for a surrogate code point,
;;; so one can reach these functions; on CCL, CODE-CHAR returns NIL instead,
;;; so one never does.

(defun effective-code-point (code)
  "CODE, or U+FFFD (the replacement character) when CODE is a lone surrogate
(U+D800 to U+DFFF), invalid on its own in UTF-8. Shared by CHAR-UTF8-OCTETS,
UTF8-LENGTH and ENCODE-UTF8 so the substitution is written once."
  (if (<= #xD800 code #xDFFF) #xFFFD code))

(defun utf8-octet-count (code)
  "The number of UTF-8 octets CODE encodes to: 1 below #x80, 2 below #x800, 3
below #x10000, 4 otherwise. CODE must already be EFFECTIVE-CODE-POINT's
result, never a raw surrogate. Shared by CHAR-UTF8-OCTETS, UTF8-LENGTH and
ENCODE-UTF8 so the four ranges are stated once."
  (cond
    ((< code #x80) 1)
    ((< code #x800) 2)
    ((< code #x10000) 3)
    (t 4)))

;;; CHAR-UTF8-OCTETS

(defun char-utf8-octets (char)
  "Return CHAR's Unicode code point as a list of UTF-8 octets: one octet
below #x80, two below #x800, three below #x10000, and four otherwise. A lone
surrogate (U+D800 to U+DFFF) encodes as U+FFFD, EF BF BD, instead of its own
code point."
  (let ((code (effective-code-point (char-code char))))
    (ecase (utf8-octet-count code)
      (1 (list code))
      (2 (list (logior #xC0 (ash code -6))
               (logior #x80 (logand code #x3F))))
      (3 (list (logior #xE0 (ash code -12))
               (logior #x80 (logand (ash code -6) #x3F))
               (logior #x80 (logand code #x3F))))
      (4 (list (logior #xF0 (ash code -18))
               (logior #x80 (logand (ash code -12) #x3F))
               (logior #x80 (logand (ash code -6) #x3F))
               (logior #x80 (logand code #x3F)))))))

;;; UTF8-LENGTH

(defun utf8-length (string)
  "The number of UTF-8 octets STRING encodes to. Loops once over STRING
without consing a list, so it is cheap to call before ENCODE-UTF8 even on a
256 MiB input. A lone surrogate counts as U+FFFD, three octets."
  (loop for char across string
        sum (utf8-octet-count (effective-code-point (char-code char)))))

;;; ENCODE-UTF8

(defun encode-utf8 (string octets)
  "Write STRING's UTF-8 encoding into OCTETS, an (UNSIGNED-BYTE 8) vector at
least (UTF8-LENGTH STRING) long, starting at index 0. Return the number of
octets written, (UTF8-LENGTH STRING). Loops once over STRING, writing
directly into OCTETS: it builds no list, so a 256 MiB input is encoded
without a per-character allocation. A lone surrogate is written as U+FFFD,
EF BF BD."
  (let ((index 0))
    (loop for char across string
          for code = (effective-code-point (char-code char))
          do (ecase (utf8-octet-count code)
               (1
                (setf (aref octets index) code)
                (incf index 1))
               (2
                (setf (aref octets index) (logior #xC0 (ash code -6)))
                (setf (aref octets (+ index 1)) (logior #x80 (logand code #x3F)))
                (incf index 2))
               (3
                (setf (aref octets index) (logior #xE0 (ash code -12)))
                (setf (aref octets (+ index 1)) (logior #x80 (logand (ash code -6) #x3F)))
                (setf (aref octets (+ index 2)) (logior #x80 (logand code #x3F)))
                (incf index 3))
               (4
                (setf (aref octets index) (logior #xF0 (ash code -18)))
                (setf (aref octets (+ index 1)) (logior #x80 (logand (ash code -12) #x3F)))
                (setf (aref octets (+ index 2)) (logior #x80 (logand (ash code -6) #x3F)))
                (setf (aref octets (+ index 3)) (logior #x80 (logand code #x3F)))
                (incf index 4))))
    index))

;;; DECODE-UTF8. cmark can write bytes that aren't UTF-8, even for valid
;;; input: handle_close_bracket (vendor/cmark-gfm/src/inlines.c) counts a
;;; footnote label's length in source columns, which restart at a line
;;; break, so a label that spans lines comes out short and can end inside
;;; a character; the reference then matches no definition and becomes
;;; text, cut label included. The decoder turns each ill-formed sequence
;;; into U+FFFD, one per maximal subpart, as the Unicode Standard
;;; recommends (§3.9, "U+FFFD Substitution of Maximal Subparts"). A maximal
;;; subpart is the longest start of a well-formed sequence found at a
;;; position, or else the one octet there.

(defun utf8-lead-facts (lead)
  "What Table 3-7 of the Unicode Standard (well-formed UTF-8 byte
sequences) says of a sequence starting with the octet LEAD, as four values:
its length in octets, the lowest and highest octet that may follow LEAD,
and the bits LEAD itself carries. The length is 1 for an ASCII octet, and
0 for an octet that starts no sequence: 80 to C1, and F5 to FF. The
second octet's range is narrower than 80 to BF after E0 and F0, which
would otherwise start overlong forms, after ED, which would start a
surrogate, and after F4, which would pass U+10FFFF."
  (cond
    ((< lead #x80) (values 1 0 0 lead))
    ((< lead #xC2) (values 0 0 0 0))
    ((< lead #xE0) (values 2 #x80 #xBF (logand lead #x1F)))
    ((= lead #xE0) (values 3 #xA0 #xBF (logand lead #x0F)))
    ((= lead #xED) (values 3 #x80 #x9F (logand lead #x0F)))
    ((< lead #xF0) (values 3 #x80 #xBF (logand lead #x0F)))
    ((= lead #xF0) (values 4 #x90 #xBF (logand lead #x07)))
    ((< lead #xF4) (values 4 #x80 #xBF (logand lead #x07)))
    ((= lead #xF4) (values 4 #x80 #x8F (logand lead #x07)))
    (t (values 0 0 0 0))))

(defun decode-utf8-at (octets index end)
  "Decode the sequence that starts at INDEX in OCTETS, a simple octet
vector, reading no octet at or past END, and return two values: its code
point, and the index just past it. An ill-formed sequence gives U+FFFD and
the index just past its maximal subpart: the lead octet and every octet
after it that Table 3-7 allows there, so the octet that cut the sequence
short is decoded on its own next."
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum index end))
  (multiple-value-bind (length low high code) (utf8-lead-facts (aref octets index))
    (if (zerop length)
        (values #xFFFD (1+ index))
        (loop for next fixnum from (1+ index)
              for position from 1 below length
              for octet = (and (< next end) (aref octets next))
              do (if (and octet
                          (if (= position 1)
                              (<= low octet high)
                              (<= #x80 octet #xBF)))
                     (setf code (logior (ash code 6) (logand octet #x3F)))
                     (return (values #xFFFD next)))
              finally (return (values code (+ index length)))))))

;;; The two passes. Each takes an ASCII octet inline, the common case, and
;;; any other through DECODE-UTF8-AT. The type declarations hold by
;;; construction: DECODE-UTF8 coerces its octets to a simple octet vector,
;;; and MAKE-STRING's default element type is CHARACTER.

(defun utf8-character-count (octets start end)
  "How many characters DECODE-UTF8 makes of OCTETS, a simple octet vector,
from START to END."
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end))
  (loop with index fixnum = start
        while (< index end)
        count t
        do (setf index (if (< (aref octets index) #x80)
                           (1+ index)
                           (nth-value 1 (decode-utf8-at octets index end))))))

(defun write-utf8-characters (octets start end string)
  "Write the characters OCTETS, a simple octet vector, encodes from START to
END into STRING, from index 0, and return STRING."
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end)
           (type (simple-array character (*)) string))
  (loop with index fixnum = start
        for position fixnum from 0
        while (< index end)
        do (let ((octet (aref octets index)))
             (if (< octet #x80)
                 (setf (schar string position) (code-char octet)
                       index (1+ index))
                 (multiple-value-bind (code next) (decode-utf8-at octets index end)
                   (setf (schar string position) (code-char code)
                         index next)))))
  string)

(defun check-octet-bounds (start end length)
  "Signal a SIMPLE-TYPE-ERROR naming START or END, whichever is bad, unless
(<= 0 START END LENGTH): DECODE-UTF8's bounds over LENGTH octets. END is
checked first, against LENGTH, then START against END. Plain comparisons,
since the native layer decodes every string cmark lends through here: the
type in the error is built only when one is signalled."
  (unless (and (integerp end) (<= 0 end length))
    (error 'simple-type-error
           :datum end
           :expected-type `(integer 0 ,length)
           :format-control "decode-utf8: :END ~S lies outside the ~D octets"
           :format-arguments (list end length)))
  (unless (and (integerp start) (<= 0 start end))
    (error 'simple-type-error
           :datum start
           :expected-type `(integer 0 ,end)
           :format-control "decode-utf8: :START ~S lies outside 0 to :END ~S"
           :format-arguments (list start end))))

(defun decode-utf8 (octets &key (start 0) end)
  "The characters OCTETS, a vector of octets, encodes in UTF-8 from START
to END (the end of OCTETS when NIL), as a fresh string. A sequence END
cuts short counts as ill-formed. Each ill-formed sequence becomes U+FFFD,
one for each maximal subpart, as the Unicode Standard recommends (§3.9,
U+FFFD Substitution of Maximal Subparts; Table 3-7 lists the well-formed
sequences): so no surrogate, overlong form or code point past U+10FFFF is
ever decoded. A maximal subpart is 1 to 3 octets and U+FFFD encodes as 3,
so the string is never shorter in UTF-8 than the octets it came from. Two
passes, one to count the characters and one to write them, so the string
is allocated once, at its length. OCTETS that aren't a simple octet vector
are copied into one first.

Unless (<= 0 START END (LENGTH OCTETS)), signals a SIMPLE-TYPE-ERROR whose
datum is the bad index, before reading any octet."
  (let* ((octets (coerce octets '(simple-array (unsigned-byte 8) (*))))
         (end (or end (length octets))))
    (check-octet-bounds start end (length octets))
    (write-utf8-characters octets start end
                           (make-string (utf8-character-count octets start end)))))
