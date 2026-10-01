;;;; Tests for HREF-ENCODE and DANGEROUS-URL-P.

(in-package #:cl-commonmark-gfm.tests)

;;; A local helper, independent of HREF-ENCODE's own implementation

(defun expected-percent-hex (code)
  "The expected %XX escape for CODE, an integer 0-255, computed without
reusing any of HREF-ENCODE's own machinery. ~X always prints hex digits
uppercase, independently of *PRINT-CASE* (which cases symbols, not radix
output), so no printer variable needs binding here."
  (format nil "%~2,'0X" code))

;;; HREF-ENCODE: every ASCII code, written out here independently of the
;;; implementation's own safe-character table

(define-test href-encode-every-ascii-code-passes-through-or-is-percent-encoded
  (let ((safe-ascii-characters
          ;; Alphanumerics, plus -_.+!*(),%#@?=;:/$~, plus & and ' (M1 design
          ;; §5.5). Written out by hand from the spec, not derived from
          ;; *HREF-SAFE-PUNCTUATION* or HREF-SAFE-OCTET-P.
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.+!*(),%#@?=;:/$~&'"))
    (dotimes (code 128)
      (let ((char (code-char code)))
        (if (find char safe-ascii-characters :test #'char=)
            (is string= (string char)
                (cl-commonmark-gfm.html-tree::href-encode (string char))
                "ASCII code ~D (~S) should pass through" code char)
            (is string= (expected-percent-hex code)
                (cl-commonmark-gfm.html-tree::href-encode (string char))
                "ASCII code ~D (~S) should be percent-encoded" code char))))))

;;; HREF-ENCODE: specific characters and strings

(define-test href-encode-passes-through-ampersand-and-apostrophe
  ;; The serializer entity-escapes these later; HREF-ENCODE must not.
  (is string= "&" (cl-commonmark-gfm.html-tree::href-encode "&"))
  (is string= "'" (cl-commonmark-gfm.html-tree::href-encode "'"))
  (is string= "a&b'c" (cl-commonmark-gfm.html-tree::href-encode "a&b'c")))

(define-test href-encode-does-not-re-encode-an-existing-percent-escape
  ;; % is itself safe, so "%41" is left alone rather than becoming "%2541".
  (is string= "%41" (cl-commonmark-gfm.html-tree::href-encode "%41")))

(define-test href-encode-space-becomes-percent-20
  (is string= "%20" (cl-commonmark-gfm.html-tree::href-encode " ")))

(define-test href-encode-percent-encodes-a-two-byte-utf8-character
  ;; U+00E9 (é) is #xC3 #xA9 in UTF-8.
  (is string= "%C3%A9" (cl-commonmark-gfm.html-tree::href-encode (string (code-char #xE9)))))

(define-test href-encode-percent-encodes-a-three-byte-utf8-character
  ;; U+20AC (€) is #xE2 #x82 #xAC in UTF-8.
  (is string= "%E2%82%AC"
      (cl-commonmark-gfm.html-tree::href-encode (string (code-char #x20AC)))))

(define-test href-encode-percent-encodes-a-four-byte-utf8-character
  ;; U+1D11E (musical G clef) is #xF0 #x9D #x84 #x9E in UTF-8.
  (is string= "%F0%9D%84%9E"
      (cl-commonmark-gfm.html-tree::href-encode (string (code-char #x1D11E)))))

;;; UTF-8 encoding-length boundaries: one below and one at the top of each
;;; multi-byte range (S5).

(define-test href-encode-utf8-boundary-two-byte-range-lower
  ;; U+0080 is the smallest code point needing two UTF-8 bytes.
  (is string= "%C2%80" (cl-commonmark-gfm.html-tree::href-encode (string (code-char #x80)))))

(define-test href-encode-utf8-boundary-two-byte-range-upper
  ;; U+07FF is the largest code point still fitting in two UTF-8 bytes.
  (is string= "%DF%BF" (cl-commonmark-gfm.html-tree::href-encode (string (code-char #x7FF)))))

(define-test href-encode-utf8-boundary-three-byte-range-lower
  ;; U+0800 is the smallest code point needing three UTF-8 bytes.
  (is string= "%E0%A0%80" (cl-commonmark-gfm.html-tree::href-encode (string (code-char #x800)))))

(define-test href-encode-utf8-boundary-three-byte-range-upper
  ;; U+FFFF is the largest code point still fitting in three UTF-8 bytes.
  (is string= "%EF%BF%BF" (cl-commonmark-gfm.html-tree::href-encode (string (code-char #xFFFF)))))

(define-test href-encode-utf8-boundary-four-byte-range-lower
  ;; U+10000 is the smallest code point needing four UTF-8 bytes.
  (is string= "%F0%90%80%80"
      (cl-commonmark-gfm.html-tree::href-encode (string (code-char #x10000)))))

(define-test href-encode-hex-digits-are-uppercase
  ;; Exercises hex digits A-F specifically, on both nibbles.
  (is string= "%3C%3E%5B%5D" (cl-commonmark-gfm.html-tree::href-encode "<>[]"))
  (isnt string= "%3c%3e%5b%5d" (cl-commonmark-gfm.html-tree::href-encode "<>[]")))

(define-test href-encode-empty-string
  (is string= "" (cl-commonmark-gfm.html-tree::href-encode "")))

;;; DANGEROUS-URL-P: dangerous

(define-test dangerous-url-p-true-for-each-dangerous-scheme
  (true (cl-commonmark-gfm.html-tree::dangerous-url-p "javascript:alert(1)"))
  (true (cl-commonmark-gfm.html-tree::dangerous-url-p "JavaScript:x"))
  (true (cl-commonmark-gfm.html-tree::dangerous-url-p "VBSCRIPT:x"))
  (true (cl-commonmark-gfm.html-tree::dangerous-url-p "file:///etc/passwd"))
  (true (cl-commonmark-gfm.html-tree::dangerous-url-p "data:text/html,x"))
  (true (cl-commonmark-gfm.html-tree::dangerous-url-p "data:image/svg+xml,x"))
  (true (cl-commonmark-gfm.html-tree::dangerous-url-p "DATA:x")))

;;; DANGEROUS-URL-P: safe, including the data:image/* exception

(define-test dangerous-url-p-false-for-the-data-image-exception-in-any-case
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p "data:image/png;base64,x"))
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p "data:image/gif;base64,x"))
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p "DATA:IMAGE/JPEG;base64,X"))
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p "data:image/webp;base64,x"))
  ;; Only the prefix counts: the exception applies even when what follows
  ;; "image/png" isn't a real data URL at all.
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p "data:image/pngx")))

(define-test dangerous-url-p-false-for-non-matching-strings
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p "javascript"))
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p " javascript:x"))
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p "http://x.org"))
  (false (cl-commonmark-gfm.html-tree::dangerous-url-p "")))

;;; HREF-ENCODE: a lone surrogate (M2 design §6.5, finding 11). On SBCL and
;;; ECL, (CODE-CHAR #xD800) is a character; on CCL it is NIL, so CCL asserts
;;; that fact instead, so every Lisp still asserts something real.

#-ccl
(define-test href-encode-percent-encodes-a-lone-surrogate-as-the-replacement-character
  (is string= "%EF%BF%BD"
      (cl-commonmark-gfm.html-tree::href-encode (string (code-char #xD800)))))

#+ccl
(define-test href-encode-percent-encodes-a-lone-surrogate-as-the-replacement-character
  (false (code-char #xD800)))

