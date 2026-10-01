;;;; CHECK-OPTIONS: resolving and validating cl-commonmark-gfm's entry-point
;;;; options (M2 design §6.3, §7.2, §7.3). Options arrive as a caller's
;;;; &REST plist (ADR-0014, "Options arrive as &REST (D11)"): every pair is
;;;; checked, a repeated key's too, and the leftmost value wins, as with
;;;; &KEY.

(in-package #:cl-commonmark-gfm.native-core)

;;; CHECKED-OPTIONS: every option resolved to its value or default

(defstruct (checked-options
            (:conc-name checked-)
            (:constructor %make-checked-options)
            (:copier nil))
  "The result of CHECK-OPTIONS (M2 design §7.2): every option
CL-COMMONMARK-GFM's entry points take, resolved to its value or its
function-specific default. Built only by CHECK-OPTIONS."
  (profile nil :read-only t)
  (extensions nil :read-only t)
  (footnotes nil :read-only t)
  (smart nil :read-only t)
  (sourcepos nil :read-only t)
  (softbreak nil :read-only t)
  (unsafe-html nil :read-only t)
  (width nil :read-only t)
  (tree-options nil :read-only t))

;;; Which keys each entry point takes (M2 design §7.2)

(defun parse-keys (entry-point)
  "ENTRY-POINT's keys among the five every entry point resolves the same
way: a bad value always signals INVALID-PARSE-OPTION. :SOURCEPOS is among
them only for :PARSE and :HTML; :PLAINTEXT and :HTML-TREE always parse
without positions, so it isn't one of their keys at all."
  (ecase entry-point
    (:parse '(:profile :extensions :footnotes :smart :sourcepos))
    (:html '(:profile :extensions :footnotes :smart :sourcepos))
    ((:plaintext :html-tree) '(:profile :extensions :footnotes :smart))))

(defun render-keys (entry-point)
  "ENTRY-POINT's render-only keys: a bad value signals INVALID-RENDER-OPTION.
:HTML-TREE has none of these -- its :SOFTBREAK is a tree key instead (M2
design §7.2)."
  (ecase entry-point
    (:parse '())
    (:html '(:softbreak :unsafe-html))
    (:plaintext '(:softbreak :width))
    (:html-tree '())))

(defun tree-keys (entry-point)
  "ENTRY-POINT's tree keys, known only to :HTML-TREE. Their values aren't
checked here: .HTML-TREE's CHECK-TREE-OPTIONS validates them, and
CHECKED-TREE-OPTIONS returns them verbatim."
  (ecase entry-point
    ((:parse :html :plaintext) '())
    (:html-tree '(:softbreak :raw-html :link-policy :document-wrapper))))

;;; Value predicates (M2 design §7.2)

(defun option-boolean-p (value)
  "True when VALUE is exactly T or NIL, the only valid value of a boolean
option."
  (or (eql value t) (null value)))

(defun distinct-list-p (list)
  "True when LIST has no two EQL elements."
  (= (length list) (length (remove-duplicates list))))

(defun valid-profile-p (value)
  "True when VALUE is a valid :PROFILE: :GFM or :COMMONMARK."
  (member value '(:gfm :commonmark)))

(defun valid-extensions-p (value)
  "True when VALUE is a valid :EXTENSIONS: a proper list of distinct
keywords from *EXTENSION-KEYWORDS*, in any order. NIL attaches none."
  (and (proper-list-p value)
       (every (lambda (keyword) (member keyword *extension-keywords*)) value)
       (distinct-list-p value)))

(defun valid-softbreak-p (value)
  "True when VALUE is a valid :SOFTBREAK: :NEWLINE, :SPACE or :BR."
  (member value '(:newline :space :br)))

(defun valid-width-p (value)
  "True when VALUE is a valid :WIDTH: an integer from 0 to 2,147,483,647."
  (typep value '(integer 0 2147483647)))

(defun valid-parse-value-p (key value)
  "True when VALUE is a valid value of KEY, one of the five keys PARSE-KEYS
can list (M2 design §7.2)."
  (ecase key
    (:profile (valid-profile-p value))
    (:extensions (valid-extensions-p value))
    ((:footnotes :smart :sourcepos) (option-boolean-p value))))

(defun valid-render-value-p (key value)
  "True when VALUE is a valid value of KEY, one of RENDER-KEYS' keys (M2
design §7.2)."
  (ecase key
    (:softbreak (valid-softbreak-p value))
    (:unsafe-html (option-boolean-p value))
    (:width (valid-width-p value))))

;;; Signalling (M2 design §7.2, §7.4)

(defun signal-parse-option (operation datum reason)
  "Signal INVALID-PARSE-OPTION for OPERATION, naming DATUM and REASON."
  (error 'invalid-parse-option :operation operation :datum datum :reason reason))

(defun structural-option-condition (entry-point)
  "The condition CHECK-OPTIONS signals for ENTRY-POINT's structural
problems -- an odd-length list, an unknown key, or a bad render-only value:
always INVALID-PARSE-OPTION for :PARSE, which signals it for every problem
(M2 design §7.2); INVALID-RENDER-OPTION for the other three."
  (if (eql entry-point :parse) 'invalid-parse-option 'invalid-render-option))

(defun signal-structural-option (entry-point operation datum reason)
  "Signal ENTRY-POINT's STRUCTURAL-OPTION-CONDITION for OPERATION, naming
DATUM and REASON."
  (error (structural-option-condition entry-point)
         :operation operation :datum datum :reason reason))

(defun parse-value-reason (key)
  "A REASON string for a bad value of KEY, one of the five PARSE-KEYS."
  (ecase key
    (:profile ":profile must be :gfm or :commonmark")
    (:extensions
     (format nil ":extensions must be a proper list of distinct keywords from ~{~S~^, ~}"
             *extension-keywords*))
    (:footnotes ":footnotes must be t or nil")
    (:smart ":smart must be t or nil")
    (:sourcepos ":sourcepos must be t or nil")))

(defun render-value-reason (key)
  "A REASON string for a bad value of KEY, one of the RENDER-KEYS."
  (ecase key
    (:softbreak ":softbreak must be one of :newline, :space, :br")
    (:unsafe-html ":unsafe-html must be t or nil")
    (:width ":width must be an integer from 0 to 2147483647")))

(defun validate-option (entry-point operation key value)
  "Signal the condition ENTRY-POINT's rules call for when KEY/VALUE isn't
valid for it; do nothing for one of ENTRY-POINT's tree keys, whose value
isn't checked here. An unrecognized KEY signals as an unknown key."
  (cond
    ((member key (parse-keys entry-point))
     (unless (valid-parse-value-p key value)
       (signal-parse-option operation value (parse-value-reason key))))
    ((member key (render-keys entry-point))
     (unless (valid-render-value-p key value)
       (signal-structural-option entry-point operation value (render-value-reason key))))
    ((member key (tree-keys entry-point)) nil)
    (t (signal-structural-option entry-point operation key "unknown key"))))

;;; Top-level validation

(defun check-even-length (entry-point operation options)
  "Signal ENTRY-POINT's structural-option condition for OPERATION unless
OPTIONS is a plist of even length."
  (unless (evenp (length options))
    (signal-structural-option entry-point operation options
                               "options must be a plist of even length")))

(defun validate-options (entry-point operation options)
  "Signal the right condition for the first invalid pair of OPTIONS. Every
pair is checked, a repeated key's too (ADR-0014 D11)."
  (loop for tail on options by #'cddr
        for key = (first tail)
        for value = (second tail)
        do (validate-option entry-point operation key value)))

;;; Resolving values and defaults (M2 design §7.2)

(defun option-given-p (options key)
  "True when KEY appears in OPTIONS, even when its value is NIL."
  (loop for tail on options by #'cddr thereis (eql (first tail) key)))

(defun canonical-extensions (extensions)
  "EXTENSIONS reordered to *EXTENSION-KEYWORDS*'s canonical order (M2 design
§6.3, §7.2). Always a fresh list, built by LOOP's COLLECT: REMOVE-IF-NOT may
return *EXTENSION-KEYWORDS* itself when EXTENSIONS names every one of them,
or a tail of it otherwise, and a caller who mutates what CHECK-OPTIONS
returns -- sorting a parsed document's :EXTENSIONS attribute in place, say
-- must never reach, and corrupt, the global."
  (loop for keyword in *extension-keywords* when (member keyword extensions) collect keyword))

(defun profile-default-extensions (profile)
  "PROFILE's default :EXTENSIONS: every extension for :GFM, none for
:COMMONMARK."
  (ecase profile
    (:gfm (copy-list *extension-keywords*))
    (:commonmark '())))

(defun profile-default-footnotes (profile)
  "PROFILE's default :FOOTNOTES: T for :GFM, NIL for :COMMONMARK."
  (ecase profile (:gfm t) (:commonmark nil)))

(defun resolved-extensions (options profile)
  "OPTIONS' :EXTENSIONS, canonicalized, when given; otherwise PROFILE's
default. An explicit :EXTENSIONS overrides the profile's default even when
it is NIL (M2 design §7.2)."
  (if (option-given-p options :extensions)
      (canonical-extensions (getf options :extensions))
      (profile-default-extensions profile)))

(defun resolved-footnotes (options profile)
  "OPTIONS' :FOOTNOTES when given; otherwise PROFILE's default."
  (if (option-given-p options :footnotes)
      (getf options :footnotes)
      (profile-default-footnotes profile)))

(defun sourcepos-default (entry-point)
  "ENTRY-POINT's default :SOURCEPOS, for the two entry points that take it:
T for :PARSE, NIL for :HTML (M2 design §7.2, D14)."
  (ecase entry-point (:parse t) (:html nil)))

(defun resolved-sourcepos (options entry-point)
  "OPTIONS' :SOURCEPOS when ENTRY-POINT takes it; otherwise NIL, since
:PLAINTEXT and :HTML-TREE always parse without positions."
  (if (member :sourcepos (parse-keys entry-point))
      (getf options :sourcepos (sourcepos-default entry-point))
      nil))

(defun checked-value-for (options entry-point key default)
  "OPTIONS' value for KEY when ENTRY-POINT takes KEY as a render key;
DEFAULT otherwise, or when KEY wasn't given. This keeps a tree option of the
same name, such as :HTML-TREE's :SOFTBREAK, from leaking into the core
value: :HTML-TREE's :SOFTBREAK isn't in its RENDER-KEYS, so it is never
consulted here."
  (if (member key (render-keys entry-point))
      (getf options key default)
      default))

(defun tree-options-of (entry-point options)
  "OPTIONS filtered down to ENTRY-POINT's tree keys, as a plist in the
caller's order, repeats included; NIL for an entry point with no tree keys."
  (loop for tail on options by #'cddr
        for key = (first tail)
        for value = (second tail)
        when (member key (tree-keys entry-point))
          append (list key value)))

(defun build-checked-options (entry-point options)
  "ENTRY-POINT's CHECKED-OPTIONS from its already-validated OPTIONS: each
key resolved to its given value (leftmost wins) or its default (M2 design
§7.2)."
  (let ((profile (getf options :profile :gfm)))
    (%make-checked-options
     :profile profile
     :extensions (resolved-extensions options profile)
     :footnotes (resolved-footnotes options profile)
     :smart (getf options :smart nil)
     :sourcepos (resolved-sourcepos options entry-point)
     :softbreak (checked-value-for options entry-point :softbreak :newline)
     :unsafe-html (checked-value-for options entry-point :unsafe-html nil)
     :width (checked-value-for options entry-point :width 0)
     :tree-options (tree-options-of entry-point options))))

;;; CHECK-OPTIONS

(defun check-options (entry-point operation options)
  "Validate OPTIONS, ENTRY-POINT's &REST option list, naming OPERATION in
whatever it signals, and return a CHECKED-OPTIONS: every option resolved to
its value or its function-specific default (M2 design §7.2).

ENTRY-POINT is :PARSE, :HTML, :PLAINTEXT or :HTML-TREE. OPERATION is the
symbol every condition's :OPERATION names: the caller's own function name.

OPTIONS must be a plist of even length, its keys among ENTRY-POINT's own
\(PARSE-KEYS, RENDER-KEYS and, for :HTML-TREE, TREE-KEYS\), each paired with
a valid value. A repeated key's leftmost value wins, as with &KEY, but every
value is checked, a repeated key's too. :HTML-TREE's tree keys --
:SOFTBREAK, :RAW-HTML, :LINK-POLICY and :DOCUMENT-WRAPPER -- are recognized
but not checked here: .HTML-TREE's CHECK-TREE-OPTIONS validates their
values, and CHECKED-TREE-OPTIONS returns them verbatim, in the caller's
order, repeats included.

Signals INVALID-PARSE-OPTION for every problem when ENTRY-POINT is :PARSE.
Otherwise signals INVALID-PARSE-OPTION for a bad :PROFILE, :EXTENSIONS,
:FOOTNOTES, :SMART or :SOURCEPOS value, and INVALID-RENDER-OPTION for
everything else: an odd-length list, an unknown key, or a bad value of any
other option."
  (check-even-length entry-point operation options)
  (validate-options entry-point operation options)
  (build-checked-options entry-point options))

;;; Option bits (M2 design §7.3)

(defun parse-option-bits (checked-options)
  "CHECKED-OPTIONS' CMARK_OPT_ parse bits: VALIDATE_UTF8 always, plus
FOOTNOTES, SMART and SOURCEPOS when each is on (M2 design §7.3)."
  (logior +cmark-opt-validate-utf8+
          (if (checked-footnotes checked-options) +cmark-opt-footnotes+ 0)
          (if (checked-smart checked-options) +cmark-opt-smart+ 0)
          (if (checked-sourcepos checked-options) +cmark-opt-sourcepos+ 0)))

(defun softbreak-bits (checked-options)
  "The HARDBREAKS or NOBREAKS bit CHECKED-OPTIONS' :SOFTBREAK calls for, or
0 for :NEWLINE. Shared by HTML-OPTION-BITS and PLAINTEXT-OPTION-BITS (M2
design §7.3)."
  (ecase (checked-softbreak checked-options)
    (:newline 0)
    (:br +cmark-opt-hardbreaks+)
    (:space +cmark-opt-nobreaks+)))

(defun html-option-bits (checked-options)
  "CHECKED-OPTIONS' CMARK_OPT_ HTML bits: the parse bits, plus the softbreak
bit and UNSAFE for :UNSAFE-HTML T (M2 design §7.3)."
  (logior (parse-option-bits checked-options)
          (softbreak-bits checked-options)
          (if (checked-unsafe-html checked-options) +cmark-opt-unsafe+ 0)))

(defun plaintext-option-bits (checked-options)
  "CHECKED-OPTIONS' CMARK_OPT_ plaintext bits: the parse bits, plus the
softbreak bit (M2 design §7.3)."
  (logior (parse-option-bits checked-options) (softbreak-bits checked-options)))

;;; DOCUMENT-ATTRIBUTES (M2 design §6.3)

(defun document-attributes (checked-options)
  "CHECKED-OPTIONS' attributes for a :DOCUMENT node (M2 design §6.3): its
:PROFILE and :EXTENSIONS, and an :OPTIONS list holding :FOOTNOTES then
:SMART, each only when it is on. Passed straight to MAKE-NODE :DOCUMENT, so
the result must satisfy the AST schema's :DOCUMENT row."
  (list :profile (checked-profile checked-options)
        :extensions (checked-extensions checked-options)
        :options (append (and (checked-footnotes checked-options) (list :footnotes))
                          (and (checked-smart checked-options) (list :smart)))))
