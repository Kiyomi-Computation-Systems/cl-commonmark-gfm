;;;; FOOTNOTE-ENTITY-INDEX: the pure scan behind the input guard (M2 design
;;;; §5.6; finding 16; M2b plan Task 9b). Mirrors houdini_unescape_ent
;;;; (vendor/cmark-gfm/src/houdini_html_u.c), restricted to the one
;;;; codepoint that matters here: ^ (U+005E, decimal 94). The shell,
;;;; CHECK-INPUT in src/api.lisp, calls this and signals UNSUPPORTED-INPUT
;;;; for a match; nothing here signals anything.

(in-package #:cl-commonmark-gfm.native-core)

;;; Digit classes (houdini.h's _isdigit and _isxdigit; the pin never
;;; defines HOUDINI_USE_LOCALE, so both are plain ASCII, never
;;; locale-dependent)

(defun ascii-decimal-digit-value (char)
  "CHAR's value as a decimal digit, or NIL when it isn't one (houdini.h's
_isdigit: (c) >= '0' && (c) <= '9'). Checked by explicit ASCII range, never
DIGIT-CHAR-P: on SBCL, DIGIT-CHAR-P also accepts non-ASCII Unicode decimal
digits (ARABIC-INDIC, FULLWIDTH, and others), which _isdigit, always
ASCII-only, never does -- a difference that would let this guard over-match
an \"entity\" cmark itself never decodes."
  (and (char<= #\0 char #\9) (- (char-code char) (char-code #\0))))

(defun ascii-hex-digit-value (char)
  "CHAR's value as a hex digit, 0 to 15, or NIL when it isn't one
(houdini.h's _isxdigit: strchr \"0123456789ABCDEFabcdef\", either case).
Checked by explicit ASCII range, for the same reason as
ASCII-DECIMAL-DIGIT-VALUE."
  (cond
    ((char<= #\0 char #\9) (- (char-code char) (char-code #\0)))
    ((char<= #\A char #\F) (+ 10 (- (char-code char) (char-code #\A))))
    ((char<= #\a char #\f) (+ 10 (- (char-code char) (char-code #\a))))
    (t nil)))

;;; The numeric forms: &#...; and &#x...;/&#X...;

(defconstant +footnote-entity-max-digits+ 8
  "houdini_unescape_ent accepts a run of 1 to this many digits before the
closing ; (num_digits <= 8, vendor/cmark-gfm/src/houdini_html_u.c).")

(defun digit-run (string start length digit-value-fn radix)
  "From START, a run of characters DIGIT-VALUE-FN reads as base-RADIX
digits, accumulated the way houdini_unescape_ent's two numeric branches
do: (VALUES VALUE COUNT END). Stops as soon as COUNT would exceed
+FOOTNOTE-ENTITY-MAX-DIGITS+, without finding the run's true end -- past
that count a match is already impossible (num_digits <= 8), so there is
nothing left worth computing, and a crafted input padding the run to
hundreds of megabytes of digits still costs this call only
+FOOTNOTE-ENTITY-MAX-DIGITS+ + 1 characters. VALUE is meaningless once
COUNT is past the cap."
  (let ((value 0) (count 0) (index start))
    (loop while (and (< index length)
                      (<= count +footnote-entity-max-digits+)
                      (funcall digit-value-fn (char string index)))
          do (setf value (+ (* value radix) (funcall digit-value-fn (char string index))))
             (incf count)
             (incf index))
    (values value count index)))

(defun numeric-entity-decodes-to-caret-p (string position length radix digit-value-fn)
  "True when STRING, from POSITION (one past # or #x/#X), is 1 to
+FOOTNOTE-ENTITY-MAX-DIGITS+ base-RADIX digits, read by DIGIT-VALUE-FN,
whose value is 94 (^, U+005E), then ; -- houdini_unescape_ent's two
numeric branches, restricted to the one codepoint this guard cares about."
  (multiple-value-bind (value count end)
      (digit-run string position length digit-value-fn radix)
    (and (<= 1 count +footnote-entity-max-digits+)
         (< end length)
         (char= (char string end) #\;)
         (= value 94))))

;;; The named form: &Hat; alone (vendor/cmark-gfm/src/entities.inc has one
;;; entry, "Hat", mapping to 94; houdini_unescape_ent's named-entity loop
;;; stops at the first ; or space it meets and either matches that whole
;;; candidate or gives up, so nothing past the first ; can turn a
;;; non-match into a match here: checking these 4 bytes exactly is enough.
;;; "hat" is not an entry, so &hat; is not an entity at all (lowercase is
;;; not folded).

(defun named-entity-decodes-to-caret-p (string position length)
  "True when STRING, from POSITION (the byte right after &), is exactly
\"Hat;\", matched case-sensitively."
  (and (>= (- length position) 4)
       (char= (char string position) #\H)
       (char= (char string (+ position 1)) #\a)
       (char= (char string (+ position 2)) #\t)
       (char= (char string (+ position 3)) #\;)))

;;; Dispatch, mirroring houdini_unescape_ent's own if/else: the numeric
;;; branches run only when what follows & is #, with at least 3 bytes
;;; available; everything else -- short input, or anything not starting
;;; with # -- falls to the named-entity check. There is no trying one
;;; branch and then the other: a failed numeric match is not retried as a
;;; named one, exactly as houdini_unescape_ent returns 0 outright.

(defun entity-decodes-to-caret-p (string position length)
  "True when STRING, from POSITION (the byte right after &), is an entity
houdini_unescape_ent decodes to ^ (U+005E, 94)."
  (let ((size (- length position)))
    (if (and (>= size 3) (char= (char string position) #\#))
        (let ((next (char string (1+ position))))
          (cond
            ((ascii-decimal-digit-value next)
             (numeric-entity-decodes-to-caret-p string (1+ position) length
                                                 10 #'ascii-decimal-digit-value))
            ((or (char= next #\x) (char= next #\X))
             (numeric-entity-decodes-to-caret-p string (+ position 2) length
                                                 16 #'ascii-hex-digit-value))
            (t nil)))
        (named-entity-decodes-to-caret-p string position length))))

;;; FOOTNOTE-ENTITY-INDEX

(defun footnote-entity-index (string)
  "The index in STRING of the first [ immediately followed by an entity
that decodes to ^ (U+005E), or NIL (M2 design §5.6, finding 16): &#, then
1 to 8 decimal digits valued 94, then a semicolon; &#x or &#X, then 1 to 8
hex digits valued 94, then a semicolon; or &Hat;, matched
case-sensitively.

One pass over STRING: the outer scan visits each index once, and the
entity check at a [ never looks past a small, fixed window -- at most
+FOOTNOTE-ENTITY-MAX-DIGITS+ + 1 characters for the numeric forms, 4 for
the named one -- so a long run of digits after [&# cannot make this
quadratic, however STRING is crafted."
  (let ((length (length string)))
    (loop for index from 0 below length
          when (and (char= (char string index) #\[)
                    (< (1+ index) length)
                    (char= (char string (1+ index)) #\&)
                    (entity-decodes-to-caret-p string (+ index 2) length))
            return index)))
