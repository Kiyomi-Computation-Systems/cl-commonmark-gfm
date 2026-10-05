;;;; Link destinations, rewritten for the site. docs/ is written for GitHub:
;;;; a page links to another by its .md file, and to the repository's other
;;;; files by relative paths, so every link works on github.com. On the
;;;; site, a page's link goes to its .html file, and a link to a file
;;;; outside docs/ goes to that file on GitHub. The site holds nothing else
;;;; from docs/, so a link to any other file there is a problem.

(in-package #:cl-commonmark-gfm.site)

(defparameter *repository-url* "https://github.com/Kiyomi-Computation-Systems/cl-commonmark-gfm"
  "The repository on GitHub. A link to one of its files that is no page
goes there.")

(defparameter *docs-directory* "docs"
  "The repository's directory, at its root, that holds the site's pages.
A page's relative paths resolve from it, as GitHub resolves them.")

;;; Strings

(defun string-prefix-p (prefix string)
  "True when STRING starts with PREFIX."
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun string-suffix-p (suffix string)
  "True when STRING ends with SUFFIX."
  (and (<= (length suffix) (length string))
       (string= suffix string :start2 (- (length string) (length suffix)))))

;;; Percent-decoding

(defun hex-digit-p (char)
  "True when CHAR is an ASCII hex digit."
  (find char "0123456789abcdefABCDEF" :test #'char=))

(defun percent-escape-at-p (string index)
  "True when STRING holds a %XX escape at INDEX: a %, then two hex digits."
  (and (<= (+ index 3) (length string))
       (char= (char string index) #\%)
       (hex-digit-p (char string (+ index 1)))
       (hex-digit-p (char string (+ index 2)))))

(defun utf8-sequence-size (lead)
  "The number of octets in the UTF-8 sequence that the octet LEAD starts,
or NIL when no sequence starts with it."
  (cond ((< lead #x80) 1)
        ((<= #xC2 lead #xDF) 2)
        ((<= #xE0 lead #xEF) 3)
        ((<= #xF0 lead #xF4) 4)
        (t nil)))

(defun utf8-code-point (octets start size)
  "The code point of the SIZE-octet UTF-8 sequence at START in OCTETS, a
vector, or NIL when it is malformed: an octet that doesn't continue it, an
overlong form, a surrogate, or a code point past U+10FFFF."
  (if (= size 1)
      (aref octets start)
      (let ((code (ldb (byte (- 7 size) 0) (aref octets start))))
        (loop for index from (1+ start) below (+ start size)
              for octet = (aref octets index)
              do (if (= (ldb (byte 2 6) octet) #b10)
                     (setf code (logior (ash code 6) (ldb (byte 6 0) octet)))
                     (return-from utf8-code-point nil)))
        (and (>= code (ecase size (2 #x80) (3 #x800) (4 #x10000)))
             (not (<= #xD800 code #xDFFF))
             (<= code #x10FFFF)
             code))))

(defun decode-utf8 (octets)
  "OCTETS, a vector of octets, decoded as UTF-8. Each octet that starts no
well-formed sequence becomes U+FFFD, the replacement character. A browser
treats most malformed input the same way, but not all: it gives a sequence
cut short, such as E2 9A, one U+FFFD, where this gives one per octet. No
heading id holds U+FFFD, so the difference never decides whether a
fragment names an id."
  (with-output-to-string (out)
    (let ((index 0))
      (loop while (< index (length octets))
            do (let* ((size (utf8-sequence-size (aref octets index)))
                      (code (and size
                                 (<= (+ index size) (length octets))
                                 (utf8-code-point octets index size))))
                 (cond (code
                        (write-char (code-char code) out)
                        (incf index size))
                       (t
                        (write-char (code-char #xFFFD) out)
                        (incf index))))))))

(defun percent-decode (string)
  "STRING with its %XX escapes decoded, each run of them as UTF-8 by
DECODE-UTF8, much as a browser decodes a URL's fragment before it looks for
the id. A % that two hex digits don't follow is kept as it is."
  (let ((octets (make-array 0 :adjustable t :fill-pointer t))
        (index 0))
    (with-output-to-string (out)
      (flet ((write-octets ()
               (write-string (decode-utf8 octets) out)
               (setf (fill-pointer octets) 0)))
        (loop while (< index (length string))
              do (cond ((percent-escape-at-p string index)
                        (vector-push-extend (parse-integer string :start (1+ index)
                                                                  :end (+ index 3)
                                                                  :radix 16)
                                            octets)
                        (incf index 3))
                       (t
                        (write-octets)
                        (write-char (char string index) out)
                        (incf index))))
        (write-octets)))))

;;; Pages' files

(defun page-html-name (name)
  "The site's file for NAME, a page's docs/ file name: index.html for the
home page, otherwise NAME with .html in place of .md."
  (if (string= name *home-page*)
      "index.html"
      (concatenate 'string (subseq name 0 (- (length name) (length ".md"))) ".html")))

;;; Classifying a destination

(defun ascii-letter-p (char)
  "True when CHAR is an ASCII letter."
  (or (char<= #\a char #\z) (char<= #\A char #\Z)))

(defun scheme-character-p (char)
  "True when CHAR may follow a URL scheme's first letter: an ASCII letter
or digit, +, - or a period."
  (or (ascii-letter-p char)
      (char<= #\0 char #\9)
      (find char "+-." :test #'char=)))

(defun schemep (destination)
  "True when DESTINATION starts with a URL scheme: a letter, then letters,
digits, +, - or periods, then a colon, as in https: or mailto:."
  (let ((colon (position #\: destination)))
    (and colon
         (plusp colon)
         (ascii-letter-p (char destination 0))
         (every #'scheme-character-p (subseq destination 1 colon)))))

(defun kept-destination-p (destination)
  "True when DESTINATION goes onto the site as it is: empty, an #id on the
same page, a URL with a scheme, or one starting with //, which a browser
completes with the page's own scheme."
  (or (zerop (length destination))
      (string-prefix-p "#" destination)
      (string-prefix-p "//" destination)
      (schemep destination)))

(defun split-fragment (destination)
  "DESTINATION's path, before its first #, and, as a second value, its
fragment, from that # on, or NIL when it has none."
  (let ((hash (position #\# destination)))
    (if hash
        (values (subseq destination 0 hash) (subseq destination hash))
        (values destination nil))))

(defun path-segments (path)
  "PATH split at each /."
  (loop for start = 0 then (1+ slash)
        for slash = (position #\/ path :start start)
        collect (subseq path start slash)
        while slash))

(defun resolve-path (path)
  "PATH, a relative path on a page, resolved as GitHub resolves it: from
docs/, or from the repository's root when it starts with /. Returns the
resolved path's segments from the root, or :OUTSIDE when a .. climbs above
the root."
  ;; SEGMENTS is the path resolved so far, its last segment first.
  (let ((segments (if (string-prefix-p "/" path) '() (list *docs-directory*))))
    (dolist (segment (path-segments (string-left-trim "/" path)) (reverse segments))
      (cond ((string= segment "..")
             (if segments
                 (pop segments)
                 (return :outside)))
            ((string= segment ".") nil)
            (t (push segment segments))))))

(defun join-segments (segments)
  "SEGMENTS joined into a path, with a / between each two."
  (format nil "~{~A~^/~}" segments))

(defun inside-docs-p (segments)
  "True when SEGMENTS, a resolved path's from the repository's root, name
something inside docs/, rather than docs/ itself or anything outside it."
  (and segments
       (string= (first segments) *docs-directory*)
       (plusp (length (join-segments (rest segments))))))

(defun classify-destination (destination page-names)
  "How DESTINATION, a link's or an image's destination on a docs/ page,
goes onto the site, as three values: a keyword, a string, and
DESTINATION's fragment, from its #, or NIL.
- :KEPT and DESTINATION: it goes on as it is (KEPT-DESTINATION-P).
- :PAGE and a name of PAGE-NAMES: its path resolves to that page's .md
  file in docs/.
- :REPOSITORY and the path, from the repository's root, that its path
  resolves to: any other file.
- :PROBLEM and what's wrong: its path climbs out of the repository, or
  resolves inside docs/ to something that is no page: a .md file that
  isn't one of PAGE-NAMES, or anything else, since the site copies no
  file but its pages."
  (if (kept-destination-p destination)
      (values :kept destination nil)
      (multiple-value-bind (path fragment) (split-fragment destination)
        (let ((resolved (resolve-path path)))
          (cond ((eql resolved :outside)
                 (values :problem "climbs out of the repository" fragment))
                ((inside-docs-p resolved)
                 (let ((name (join-segments (rest resolved))))
                   (cond ((member name page-names :test #'string=)
                          (values :page name fragment))
                         ((string-suffix-p ".md" name)
                          (values :problem "names no page in docs/" fragment))
                         (t (values :problem "is inside docs/ but isn't a page" fragment)))))
                (t (values :repository (join-segments resolved) fragment)))))))

(defun repository-file-path (path)
  "PATH, a :REPOSITORY path from CLASSIFY-DESTINATION, as the file or
directory it names in the repository: without any ?query, which GitHub
reads but no file name holds, and with its %XX escapes decoded."
  (percent-decode (subseq path 0 (position #\? path))))

;;; Rewriting a destination

(defun rewrite-destination (destination page-names ref)
  "DESTINATION, a :LINK or :IMAGE node's destination on a docs/ page,
rewritten for the site, and, as a second value, a problem string or NIL.
PAGE-NAMES are the docs/ file names of the site's pages, such as
\"usage.md\"; REF is the git ref the site is rendered from, such as a
release tag.
- An empty destination, an #id, a URL with a scheme, and one starting
  with //, are kept.
- A path to a page's .md file becomes the page's .html file, its #id
  kept: usage.md#limits becomes usage.html#limits, and README.md becomes
  index.html.
- A path outside docs/ becomes its file's URL in the repository on
  GitHub, at REF: ../src/api.lisp becomes
  https://github.com/Kiyomi-Computation-Systems/cl-commonmark-gfm/blob/REF/src/api.lisp.
A path resolves from docs/, as on GitHub. A path to a .md file in docs/
that is no page, any other path inside docs/, since the site copies no
file but its pages, and a path that climbs out of the repository, are
problems: the destination comes back empty, and the problem names it."
  (multiple-value-bind (kind value fragment) (classify-destination destination page-names)
    (ecase kind
      (:kept (values destination nil))
      (:page (values (concatenate 'string (page-html-name value) (or fragment "")) nil))
      (:repository (values (format nil "~A/blob/~A/~A~@[~A~]" *repository-url* ref value fragment)
                           nil))
      (:problem (values "" (format nil "~A ~A" destination value))))))
