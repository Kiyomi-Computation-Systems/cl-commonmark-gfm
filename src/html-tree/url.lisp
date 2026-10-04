;;;; URL percent-encoding, for link and image destinations and footnote
;;;; labels, and the dangerous-URL check of the :SAFE link policy.

(in-package #:cl-commonmark-gfm.html-tree)

;;; HREF-ENCODE

(defparameter *href-safe-punctuation* "-_.+!*(),%#@?=;:/$~&'"
  "Punctuation HREF-ENCODE leaves unescaped, alongside ASCII alphanumerics.
Mirrors houdini_escape_href's HREF_SAFE table, except that & and ' are safe
here too: the serializer entity-escapes them later.")

(defparameter *hex-digits* "0123456789ABCDEF"
  "Uppercase hex digits, indexed by nibble value, for HREF-ENCODE's %XX
escapes.")

(defun href-safe-octet-p (octet)
  "True when OCTET is an ASCII code (below #x80) that HREF-ENCODE leaves
unescaped: an alphanumeric, or a character of *HREF-SAFE-PUNCTUATION*. Every
octet of a multi-byte UTF-8 sequence is #x80 or above, so this is false for
all of them, and they are always percent-encoded."
  (and (< octet #x80)
       (let ((char (code-char octet)))
         (or (alphanumericp char)
             (find char *href-safe-punctuation* :test #'char=)))))

(defun write-percent-octet (octet stream)
  "Write OCTET to STREAM as a %XX escape, in uppercase hex."
  (write-char #\% stream)
  (write-char (char *hex-digits* (ldb (byte 4 4) octet)) stream)
  (write-char (char *hex-digits* (ldb (byte 4 0) octet)) stream))

(defun href-encode (string)
  "Percent-encode STRING, a link or image destination or a footnote label,
mirroring cmark-gfm's houdini_escape_href. STRING is encoded as UTF-8 with
CHAR-UTF8-OCTETS (cl-commonmark-gfm.util); each octet that is an ASCII
alphanumeric or a character of *HREF-SAFE-PUNCTUATION* stays as its
character, and every other octet becomes %XX in uppercase hex. Because %
passes through unescaped, an existing escape is never re-encoded."
  (with-output-to-string (out)
    (loop for char across string
          do (dolist (octet (char-utf8-octets char))
               (if (href-safe-octet-p octet)
                   (write-char (code-char octet) out)
                   (write-percent-octet octet out))))))

;;; DANGEROUS-URL-P

(defparameter *dangerous-url-schemes* '("javascript:" "vbscript:" "file:" "data:")
  "Schemes DANGEROUS-URL-P blanks under the :SAFE link policy, mirroring
cmark-gfm's _scan_dangerous_url.")

(defparameter *safe-data-image-prefixes*
  '("data:image/png" "data:image/gif" "data:image/jpeg" "data:image/webp")
  "DANGEROUS-URL-P's exception: a data: URL starting with one of these,
checked as a prefix, is not dangerous.")

(defun case-insensitive-prefix-p (prefix string)
  "True when STRING starts with PREFIX, compared with STRING-EQUAL. PREFIX is
always plain ASCII here, so this folds ASCII case only, as cmark-gfm's
_scan_dangerous_url does: on SBCL, CCL and ECL, CHAR-EQUAL's case pairs are
one-to-one, and U+017F (LATIN SMALL LETTER LONG S) is not paired with #\\s
or #\\S, so it cannot fold into a dangerous scheme name on any of the three."
  (and (<= (length prefix) (length string))
       (string-equal prefix string :end2 (length prefix))))

(defun dangerous-url-p (string)
  "True when STRING starts, case-insensitively, with javascript:, vbscript:,
file: or data:, per cmark-gfm's _scan_dangerous_url. The exception: a data:
URL that continues with image/png, image/gif, image/jpeg or image/webp
(checked as a prefix, so \"data:image/pngx\" counts too) is not dangerous."
  (and (some (lambda (scheme) (case-insensitive-prefix-p scheme string))
             *dangerous-url-schemes*)
       (notany (lambda (prefix) (case-insensitive-prefix-p prefix string))
               *safe-data-image-prefixes*)))
