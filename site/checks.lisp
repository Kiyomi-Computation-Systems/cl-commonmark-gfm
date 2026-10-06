;;;; The site's checks: pure functions that decide which pages, links and
;;;; refs are problems. BUILD.LISP calls them with what it reads from
;;;; docs/, git and the filesystem; none of these reads or writes
;;;; anything itself, so each is tested directly, in tests/checks.lisp.

(in-package #:cl-commonmark-gfm.site)

;;; Check 1: *PAGES* against docs/*.md

(defun missing-page-hint (name)
  "A hint for NAME, a *PAGES* entry missing from docs/, or NIL:
*REFERENCE-PAGE* is generated, so its hint is to run make reference."
  (when (string= name *reference-page*)
    "run 'make reference'"))

(defun unlisted-page-problems (sidebar-names docs-names)
  "The problems between SIDEBAR-NAMES, *PAGES*, and DOCS-NAMES, docs/'s .md
file names other than the home page: one for each name that is in only one
of the two lists, SIDEBAR-NAMES' order first, then DOCS-NAMES'. A name
missing from docs/ gets MISSING-PAGE-HINT's hint, when it has one; a name
docs/ holds that *PAGES* doesn't list gets told where to add it."
  (append (loop for name in sidebar-names
                unless (member name docs-names :test #'string=)
                  collect (format nil "~A: listed in *pages*, but missing from docs/~@[; ~A~]"
                                  name (missing-page-hint name)))
          (loop for name in docs-names
                unless (member name sidebar-names :test #'string=)
                  collect (format nil "~A: in docs/, but not listed in *pages*; ~
                                       add it to site/pages.lisp"
                                  name))))

(defun duplicate-sidebar-problems (sidebar-names)
  "A problem for each distinct name that SIDEBAR-NAMES, *PAGES*, holds more
than once: RENDER-SITE would give two pages the same output file."
  (loop for name in (remove-duplicates sidebar-names :test #'string= :from-end t)
        when (> (count name sidebar-names :test #'string=) 1)
          collect (format nil "~A: listed more than once in *pages*" name)))

(defun nested-page-problems (nested-names)
  "A problem for each of NESTED-NAMES, .md files that sit in a directory
below docs/, such as \"sub/page.md\": the site reads only docs/*.md
directly, so it would never render them."
  (mapcar (lambda (name)
            (format nil "~A: sits in a directory below docs/, where the site won't render it"
                    name))
          nested-names))

;;; git's raw output: 'git ls-files -s -z --cached --others
;;; --exclude-standard' NUL-separates its entries, SPLIT-NUL-TERMINATED's
;;; job; and -s puts a tracked entry's mode, object and stage before a
;;; tab, which LS-FILES-ENTRIES-TO-PATHS strips, also naming a gitlink,
;;; mode 160000: a submodule's own directory. An --others entry, new and
;;; not yet added, has no such prefix: it has no stage to show.

(defun split-nul-terminated (string)
  "STRING's entries, each ending in a NUL as 'git ls-files -z' writes
them: STRING split at each NUL, with the empty entry after the final one
dropped."
  (loop with start = 0
        for nul = (position (code-char 0) string :start start)
        while nul
        collect (subseq string start nul)
        do (setf start (1+ nul))))

(defun ls-files-digit-run-p (entry start end radix)
  "True when END is within ENTRY and ENTRY's characters from START to
END, exclusive, are all digits in RADIX -- 8 for a tracked entry's mode,
16 for its object name."
  (and (<= end (length entry))
       (every (lambda (char) (digit-char-p char radix)) (subseq entry start end))))

(defun ls-files-object-end (entry start)
  "The position in ENTRY just after the run of 40 or 64 hex digits that
starts at START and that a space follows -- a tracked entry's object
name. Checking the digits alone isn't enough: any 40 of a 64-digit
SHA-256 name are hex digits too, so the 40-digit length would always
match first; the space after it is what tells the two apart. NIL when
neither length fits."
  (loop for object-length in '(40 64)
        for end = (+ start object-length)
        when (and (ls-files-digit-run-p entry start end 16)
                  (< end (length entry))
                  (char= (char entry end) #\Space))
          return end))

(defun tracked-entry-path-start (entry)
  "The position in ENTRY just after its tracked-entry prefix -- six octal
digits, a space, 40 or 64 hex digits, a space, one stage digit, then a
tab -- when ENTRY starts with one; or NIL, an untracked entry, whose own
path may hold a tab of its own."
  (when (and (>= (length entry) 7)
             (ls-files-digit-run-p entry 0 6 8)
             (char= (char entry 6) #\Space))
    (let ((object-end (ls-files-object-end entry 7)))
      (when (and object-end
                 (< (+ 2 object-end) (length entry))
                 (digit-char-p (char entry (1+ object-end)))
                 (char= (char entry (+ 2 object-end)) #\Tab))
        (+ 3 object-end)))))

(defun ls-files-entry-path (entry)
  "ENTRY, one line of 'git ls-files -s -z ...', as the path it names:
when ENTRY starts with a tracked entry's mode, object name and stage
before a tab, as TRACKED-ENTRY-PATH-START finds it, everything from
there on; otherwise, an untracked entry, ENTRY whole, any tab of its own
included."
  (let ((start (tracked-entry-path-start entry)))
    (if start (subseq entry start) entry)))

(defun gitlink-entry-p (entry)
  "True when ENTRY, one line of 'git ls-files -s -z ...', names a
gitlink, mode 160000: a submodule's own directory. Reads ENTRY's prefix
as TRACKED-ENTRY-PATH-START does, so an untracked path that merely looks
like one -- a 160000 of its own, a tab of its own, or both -- can't be
taken for a gitlink."
  (and (tracked-entry-path-start entry)
       (string= entry "160000" :end1 6)))

(defun ls-files-entries-to-paths (entries)
  "ENTRIES, 'git ls-files -s -z ...''s NUL-split lines, as two values:
every entry's own path, through LS-FILES-ENTRY-PATH, a gitlink's
included, since the directory above it still lists it as a child, which
GitHub's /tree/ shows; and, of those, the ones GITLINK-ENTRY-P finds --
a submodule's own directory, for which GitHub's /blob/ and /tree/ serve
no page, nor for anything below it, even though ls-files lists it."
  (let ((paths (mapcar #'ls-files-entry-path entries)))
    (values paths (mapcar #'ls-files-entry-path (remove-if-not #'gitlink-entry-p entries)))))

(defun tracked-files-minus-deleted (tracked-files deleted-files)
  "TRACKED-FILES, less DELETED-FILES: a file 'git ls-files --deleted'
names is still in the index, from --cached, but gone from the working
tree -- deleted without git rm -- so it is no longer one GitHub's /blob/
would serve once the deletion is committed."
  (remove-if (lambda (file) (member file deleted-files :test #'string=)) tracked-files))

;;; Repository links: each must name a file or directory GitHub's /blob/
;;; URL serves

(defun directory-prefix-p (directory file)
  "True when FILE, one of a repository's tracked files, lies under
DIRECTORY: FILE starts with DIRECTORY, then a /."
  (and (string-prefix-p directory file)
       (> (length file) (length directory))
       (char= (char file (length directory)) #\/)))

(defun under-or-at-gitlink-p (path gitlink-paths)
  "True when PATH, with any trailing / trimmed, is one of GITLINK-PATHS,
a submodule's own directory, or DIRECTORY-PREFIX-P finds it lies below
one: GitHub's /blob/ and /tree/ serve no page for either, even though a
directory above a gitlink, which GitHub does serve, lists it as a
child."
  (let ((directory (string-right-trim "/" path)))
    (some (lambda (gitlink)
            (or (string= directory gitlink) (directory-prefix-p gitlink directory)))
          gitlink-paths)))

(defun repository-path-known-p (path tracked-files gitlink-paths)
  "True when PATH, a repository-root-relative string from RENDER-SITE's
fifth value, names the repository's root, empty when a link resolves to
it; is one of TRACKED-FILES, a submodule's own gitlink included, since
the directory above it still lists it as a child; or names a directory
under which one of them lies: PATH with any trailing / trimmed is
DIRECTORY-PREFIX-P some file of TRACKED-FILES. GitHub always serves the
root's own listing. Refused regardless when PATH is UNDER-OR-AT-GITLINK-P
one of GITLINK-PATHS."
  (and (or (zerop (length path))
           (let ((directory (string-right-trim "/" path)))
             (or (member path tracked-files :test #'string=)
                 (some (lambda (file) (directory-prefix-p directory file)) tracked-files))))
       (not (under-or-at-gitlink-p path gitlink-paths))))

(defun missing-repository-link-problems (repository-paths tracked-files gitlink-paths)
  "A problem for each of REPOSITORY-PATHS, RENDER-SITE's fifth value, whose
path REPOSITORY-PATH-KNOWN-P refuses against TRACKED-FILES and
GITLINK-PATHS: a link that goes to GitHub but names nothing its /blob/
URL serves."
  (loop for (name . path) in repository-paths
        unless (repository-path-known-p path tracked-files gitlink-paths)
          collect (format nil "~A: link ~A names no file in the repository" name path)))

;;; SITE_REF

(defun url-path-unsafe-character-p (char)
  "True when CHAR can't sit in a URL's path as it is, so a ref holding it
can't be used to build the /blob/ links: a space, #, ?, %, or an ASCII
control character (below U+0020, or U+007F)."
  (or (char= char #\Space)
      (char= char #\#)
      (char= char #\?)
      (char= char #\%)
      (< (char-code char) #x20)
      (= (char-code char) #x7F)))

(defun unsafe-ref-segment-p (segment)
  "True when SEGMENT, one of REF's /-separated parts, can't sit in a
/blob/ URL as it is: ., which stays put, .., which climbs out of it, or
empty, which a leading, trailing or doubled / makes."
  (or (zerop (length segment))
      (string= segment ".")
      (string= segment "..")))

(defun unsafe-character-name (char)
  "CHAR, one of URL-PATH-UNSAFE-CHARACTER-P's characters, named as
REF-PROBLEM's message gives it: a space, by name; an ASCII control
character, below U+0020 or U+007F, by its code point; otherwise the
character itself."
  (cond ((char= char #\Space) "a space")
        ((or (< (char-code char) #x20) (= (char-code char) #x7F))
         (format nil "the control character U+~4,'0X" (char-code char)))
        (t (format nil "the character ~C" char))))

(defun unsafe-segment-reason (segment position last-position)
  "SEGMENT, one of UNSAFE-REF-SEGMENT-P's segments, found at POSITION
among a ref's segments whose last is at LAST-POSITION, named as
REF-PROBLEM's message gives it: a . or a .. segment; otherwise, from
where its emptiness comes, a leading, a trailing or a doubled /."
  (cond ((string= segment ".") "a . segment")
        ((string= segment "..") "a .. segment")
        ((zerop position) "a leading /")
        ((= position last-position) "a trailing /")
        (t "a doubled /")))

(defun ref-character-problem (ref)
  "The problem with REF from the first character
URL-PATH-UNSAFE-CHARACTER-P refuses, named by UNSAFE-CHARACTER-NAME; or
NIL when REF holds none."
  (let ((char (find-if #'url-path-unsafe-character-p ref)))
    (when char
      (format nil "holds ~A, which a URL's path can't carry as it is"
              (unsafe-character-name char)))))

(defun ref-segment-problem (ref)
  "The problem with REF from the first /-separated segment
UNSAFE-REF-SEGMENT-P refuses, named by UNSAFE-SEGMENT-REASON; or NIL
when none of REF's segments is unsafe."
  (let* ((segments (path-segments ref))
         (position (position-if #'unsafe-ref-segment-p segments)))
    (when position
      (format nil "holds ~A, which a /blob/ link can't carry as it is"
              (unsafe-segment-reason (nth position segments) position (1- (length segments)))))))

(defun ref-problem (ref)
  "Why REF isn't fit to use as the git ref in a /blob/ URL and the site's
closing line, or NIL when it is: empty; holding a character a URL's path
can't carry, named by REF-CHARACTER-PROBLEM; or holding a /-separated
segment a /blob/ link can't carry, named by REF-SEGMENT-PROBLEM."
  (if (zerop (length ref))
      "is empty"
      (or (ref-character-problem ref) (ref-segment-problem ref))))

(defun valid-ref-p (ref)
  "True when REF is fit to use as the git ref in a /blob/ URL and the
site's closing line: REF-PROBLEM gives none."
  (not (ref-problem ref)))
