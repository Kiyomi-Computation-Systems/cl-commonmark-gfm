;;;; The version cross-check's pure half: VERSION-NUMBER and NUMBER-VERSION
;;;; turn a cmark-gfm version string into the packed integer
;;;; cmark_version() reports, and back. Startup (src/native/startup.lisp)
;;;; uses both to check what cmark_version() returns against
;;;; *CMARK-GFM-VERSION*, after its cmark_version_string check.
;;;;
;;;; cmark_version() packs the version as gfm does it, not as the comment
;;;; above the function in vendor/cmark-gfm/src/cmark-gfm.h describes
;;;; upstream cmark's layout: (major << 24) | (minor << 16) | (patch << 8) |
;;;; gfm (vendor/cmark-gfm/src/cmark-gfm_version.h.in and
;;;; vendor/cmark-gfm/src/cmark.c). For the pin, 0.29.0.gfm.13, that's
;;;; #x001D000D.

(in-package #:cl-commonmark-gfm.native-core)

(defun split-on-period (string)
  "STRING split at every #\\. , the periods themselves dropped: a list of
the substrings between them, in order."
  (let ((parts '())
        (start 0)
        (length (length string)))
    (loop
      (let ((next (position #\. string :start start)))
        (push (subseq string start (or next length)) parts)
        (if next (setf start (1+ next)) (return))))
    (nreverse parts)))

(defun ascii-digit-string-p (string)
  "True when STRING is non-empty and holds only the ASCII digits 0 to 9."
  (and (plusp (length string))
       (every (lambda (char) (char<= #\0 char #\9)) string)))

(defun parse-version-component (string)
  "STRING parsed as one of \"M.m.p.gfm.N\"'s four numeric components: a
non-negative integer from 0 to 255, written in ASCII digits only, with no
sign and nothing else. NIL when STRING isn't exactly that."
  (and (ascii-digit-string-p string)
       (let ((value (parse-integer string)))
         (and (<= 0 value 255) value))))

(defun version-string-components (string)
  "STRING's four numeric components, (MAJOR MINOR PATCH GFM), when STRING is
exactly \"M.m.p.gfm.N\" and each of M, m, p and N is 0 to 255; NIL
otherwise."
  (let ((parts (split-on-period string)))
    (when (= (length parts) 5)
      (destructuring-bind (major minor patch literal gfm) parts
        (when (string= literal "gfm")
          (let ((major (parse-version-component major))
                (minor (parse-version-component minor))
                (patch (parse-version-component patch))
                (gfm (parse-version-component gfm)))
            (when (and major minor patch gfm)
              (list major minor patch gfm))))))))

(defun version-number (string)
  "STRING, a cmark-gfm version string \"M.m.p.gfm.N\" with each of M, m, p
and N from 0 to 255, as (M << 24) | (m << 16) | (p << 8) | N: the integer
cmark_version() returns for it. For the pin, \"0.29.0.gfm.13\", that's
#x001D000D. An ERROR names STRING when it isn't exactly that shape, or when
a component is out of range."
  (let ((components (version-string-components string)))
    (unless components
      (error "~S is not a cmark-gfm version string of the form \"M.m.p.gfm.N\", ~
             each of M, m, p and N from 0 to 255"
             string))
    (destructuring-bind (major minor patch gfm) components
      (logior (ash major 24) (ash minor 16) (ash patch 8) gfm))))

(defun number-version (number)
  "The inverse of VERSION-NUMBER: NUMBER, (M << 24) | (m << 16) | (p << 8) |
N, as the string \"M.m.p.gfm.N\". An ERROR names NUMBER when it isn't an
integer from 0 to #xFFFFFFFF."
  (unless (typep number '(integer 0 #xFFFFFFFF))
    (error "~S is not a version number from 0 to #xFFFFFFFF" number))
  (format nil "~D.~D.~D.gfm.~D"
          (ldb (byte 8 24) number)
          (ldb (byte 8 16) number)
          (ldb (byte 8 8) number)
          (ldb (byte 8 0) number)))
