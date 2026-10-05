;;;; The site's checks: pure functions that decide which pages, links and
;;;; refs are problems. BUILD.LISP calls them with what it reads from
;;;; docs/, git and the filesystem; none of these reads or writes
;;;; anything itself, so each is tested directly, in tests/checks.lisp.

(in-package #:cl-commonmark-gfm.site)

;;; Check 1: *PAGES* against docs/*.md

(defun missing-page-hint (name)
  "A hint for NAME, a *PAGES* entry missing from docs/, or NIL: reference.md
is generated, so its hint is to run make reference."
  (when (string= name "reference.md")
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

(defun ls-files-entry-path (entry)
  "ENTRY, one line of 'git ls-files -s -z ...', as the path it names: the
part after ENTRY's last tab, when it has one -- a tracked entry, shown
with its mode, object and stage before the tab -- or ENTRY whole, an
untracked one."
  (let ((tab (position #\Tab entry :from-end t)))
    (if tab (subseq entry (1+ tab)) entry)))

(defun gitlink-entry-p (entry)
  "True when ENTRY, one line of 'git ls-files -s -z ...', names a
gitlink, mode 160000: a submodule's own directory."
  (and (position #\Tab entry)
       (>= (length entry) 6)
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

(defun ref-problem (ref)
  "Why REF isn't fit to use as the git ref in a /blob/ URL and the site's
closing line, or NIL when it is: empty; holding a character a URL's path
can't carry, found by URL-PATH-UNSAFE-CHARACTER-P; or holding a
/-separated segment that would leave /blob/, found by
UNSAFE-REF-SEGMENT-P -- a ., a .., or one a leading, trailing or doubled /
makes empty."
  (cond ((zerop (length ref)) "is empty")
        ((some #'url-path-unsafe-character-p ref)
         "holds a character a URL's path can't carry as it is")
        ((some #'unsafe-ref-segment-p (path-segments ref))
         "holds a segment that would leave /blob/")
        (t nil)))

(defun valid-ref-p (ref)
  "True when REF is fit to use as the git ref in a /blob/ URL and the
site's closing line: REF-PROBLEM gives none."
  (not (ref-problem ref)))
