;;;; The shell around the site's pure core: reading docs/*.md, asking git,
;;;; and writing build/site/. Only this file and the runners that load it,
;;;; site/run-*.lisp, read or write a file, or run another program;
;;;; checks.lisp holds the pure decisions over what this reads -- which
;;;; pages belong, which links and refs are problems -- so each is tested
;;;; directly, with no file or git of its own.
;;;;
;;;; Kept out of cl-commonmark-gfm-site.asd's components, as
;;;; tests/runner.lisp is kept out of cl-commonmark-gfm/tests: the runners
;;;; LOAD it directly, so the system that ships the site's pure core, and
;;;; that its own tests load, never touches a file.

(in-package #:cl-commonmark-gfm.site)

(defparameter *default-ref* "main"
  "The git ref RENDER-SITE is given when none is asked for: MAKE SITE's own
default, and the one CHECK-SITE-PROBLEMS uses, since the ref never decides
which problems it finds.")

;;; Paths

(defun docs-directory-pathname ()
  "The absolute pathname of docs/, where the site's pages live."
  (asdf:system-relative-pathname "cl-commonmark-gfm" "docs/"))

(defun docs-path (name)
  "The absolute pathname of docs/NAME."
  (merge-pathnames name (docs-directory-pathname)))

(defun build-directory-pathname ()
  "The absolute pathname of build/site/, where MAKE SITE writes the site."
  (asdf:system-relative-pathname "cl-commonmark-gfm" "build/site/"))

;;; Reading docs/

(defun docs-markdown-names ()
  "The .md file names directly inside docs/, sorted: each page's own file
name, such as \"usage.md\". The home page, README.md, is included."
  (sort (mapcar #'file-namestring (uiop:directory-files (docs-directory-pathname) "*.md"))
        #'string<))

(defun site-page-names ()
  "The docs/ file names RENDER-SITE renders, in its order: the home page,
then *PAGES*."
  (cons *home-page* *pages*))

(defun read-docs-pages (names)
  "NAMES, docs/ file names, read from docs/ as UTF-8, each as
(NAME . MARKDOWN)."
  (mapcar (lambda (name)
             (cons name (uiop:read-file-string (docs-path name) :external-format :utf-8)))
          names))

(defun render-docs (ref)
  "Read the home page and *PAGES*, in RENDER-SITE's order, from docs/, and
RENDER-SITE them at REF: its five values."
  (render-site (read-docs-pages (site-page-names)) ref))

;;; Repository links: each must name a file or directory GitHub's /blob/
;;; URL serves, so the shell asks git rather than the filesystem: a path
;;; the filesystem holds can still be one git ignores, or one inside the
;;; cmark-gfm submodule, which GitHub's /blob/ doesn't serve either.
;;; SPLIT-NUL-TERMINATED, LS-FILES-ENTRIES-TO-PATHS,
;;; TRACKED-FILES-MINUS-DELETED, REPOSITORY-PATH-KNOWN-P and
;;; MISSING-REPOSITORY-LINK-PROBLEMS, the pure decisions over what this
;;; asks git for, are in checks.lisp.

(defun run-git (&rest arguments)
  "Run git with ARGUMENTS from the repository's root. Two values: its
output, split on NUL -z writes between entries and decoded as UTF-8 --
turning off git's usual C-quoting of a non-ASCII byte, which would
otherwise hide a real file behind an escaped name such as
\"caf\\303\\251.txt\" -- or NIL and a problem string naming why git
failed, such as running outside a checkout."
  (handler-case
      (multiple-value-bind (output error-output status)
          (uiop:run-program (cons "git" arguments)
                            :directory (asdf:system-source-directory "cl-commonmark-gfm")
                            :output :string
                            :external-format :utf-8
                            :error-output :string
                            :ignore-error-status t)
        (if (zerop status)
            (values (split-nul-terminated output) nil)
            (values nil (format nil "git ~{~A~^ ~} failed, status ~D: ~A" arguments status
                                (string-trim '(#\Newline #\Space) error-output)))))
    (error (condition)
      (values nil (format nil "git ~{~A~^ ~} failed: ~A" arguments condition)))))

(defun git-tracked-files ()
  "The repository's tracked files and its new, not yet added ones, a
submodule's own gitlink included, less any git ls-files --deleted names:
every file or gitlink GitHub's /tree/ would list in some directory, even
one, such as vendor/cmark-gfm's, that GitHub's /blob/ and /tree/ serve no
page for itself, since ls-files doesn't recurse into a submodule unasked.
Leaves out what git ignores, such as build/ and ocicl/, and a file
deleted from the working tree without git rm, still in the index. Three
values: the files; the gitlink paths among them; or, on failure, NIL, NIL
and a problem string naming why git failed."
  (multiple-value-bind (entries failure)
      (run-git "ls-files" "-s" "-z" "--cached" "--others" "--exclude-standard")
    (if failure
        (values nil nil failure)
        (multiple-value-bind (deleted deleted-failure) (run-git "ls-files" "-z" "--deleted")
          (if deleted-failure
              (values nil nil deleted-failure)
              (multiple-value-bind (paths gitlink-paths) (ls-files-entries-to-paths entries)
                (values (tracked-files-minus-deleted paths deleted) gitlink-paths nil)))))))

(defun render-docs-problems (ref)
  "RENDER-DOCS at REF, with its own problems, then a problem for each
repository link MISSING-REPOSITORY-LINK-PROBLEMS refuses against
GIT-TRACKED-FILES, or, when git itself fails, one problem for that alone.
Returns four values: the outputs; the number of pages; the number of
links and images checked; and the problems."
  (multiple-value-bind (outputs ids problems links repository-paths) (render-docs ref)
    (declare (ignore ids))
    (multiple-value-bind (tracked-files gitlink-paths git-failure) (git-tracked-files)
      (values outputs (length outputs) links
              (append problems
                      (if git-failure
                          (list git-failure)
                          (missing-repository-link-problems
                           repository-paths tracked-files gitlink-paths)))))))

;;; Check 1: *PAGES* against docs/*.md. UNLISTED-PAGE-PROBLEMS,
;;; DUPLICATE-SIDEBAR-PROBLEMS and NESTED-PAGE-PROBLEMS, the pure
;;; decisions, are in checks.lisp.

(defun nested-docs-markdown-names ()
  "The .md files in a subdirectory below docs/, such as \"sub/page.md\",
sorted: the site reads only docs/*.md directly, so it would never render
them."
  (let ((pattern (merge-pathnames (make-pathname :directory '(:relative :wild :wild-inferiors)
                                                 :name :wild :type "md")
                                  (docs-directory-pathname))))
    (sort (mapcar (lambda (pathname)
                    (namestring (enough-namestring pathname (docs-directory-pathname))))
                  (directory pattern))
          #'string<)))

(defun check-site-listing ()
  "Check 1: *PAGES* against docs/*.md, less the home page -- a name missing
from either list, named twice in *PAGES*, or sitting in a subdirectory
below docs/."
  (append (unlisted-page-problems
           *pages* (remove *home-page* (docs-markdown-names) :test #'string=))
          (duplicate-sidebar-problems *pages*)
          (nested-page-problems (nested-docs-markdown-names))))

(defun check-site-problems (ref)
  "The problems MAKE CHECK-SITE reports over docs/, as three values: the
problems; the number of pages RENDER-SITE rendered, 0 when check 1 already
found one; and the number of links and images it checked. Check 1 runs
first, over a bare listing of docs/*.md, so a page *PAGES* names that
doesn't exist there is never read: RENDER-DOCS-PROBLEMS only runs once
check 1 finds every name in both lists."
  (let ((listing-problems (check-site-listing)))
    (if listing-problems
        (values listing-problems 0 0)
        (multiple-value-bind (outputs pages links problems) (render-docs-problems ref)
          (declare (ignore outputs))
          (values problems pages links)))))

;;; Writing build/site/

(defun under-build-directory-p (directory)
  "True when DIRECTORY is build/ or inside it: DELETE-DIRECTORY-TREE's
guard, so WRITE-SITE can never remove anything outside build/."
  (uiop:subpathp directory (asdf:system-relative-pathname "cl-commonmark-gfm" "build/")))

(defun write-utf8-file (pathname text)
  "Write TEXT to PATHNAME, as UTF-8, creating its directory and replacing
any file already there."
  (ensure-directories-exist pathname)
  (with-open-file (stream pathname :direction :output :if-exists :supersede
                                   :external-format :utf-8)
    (write-string text stream)))

(defun write-page (directory name html)
  "Write one page, NAME and its HTML, as RENDER-SITE's OUTPUTS hold it,
into DIRECTORY: <!DOCTYPE html>, a newline, then HTML."
  (write-utf8-file (merge-pathnames name directory) (format nil "<!DOCTYPE html>~%~A" html)))

(defun copy-static-assets (directory)
  "Copy style.css and theme.js, this generator's own, into DIRECTORY."
  (dolist (name '("style.css" "theme.js"))
    (uiop:copy-file (asdf:system-relative-pathname "cl-commonmark-gfm-site" name)
                    (merge-pathnames name directory))))

(defun write-site (directory outputs)
  "Write OUTPUTS, RENDER-SITE's (HTML-NAME . HTML) pairs, into DIRECTORY,
removed first so a page dropped from docs/ doesn't linger: each page, then
style.css and theme.js."
  (uiop:delete-directory-tree directory
                              :validate #'under-build-directory-p
                              :if-does-not-exist :ignore)
  (ensure-directories-exist directory)
  (dolist (output outputs)
    (write-page directory (car output) (cdr output)))
  (copy-static-assets directory))

;;; MAKE SITE

(defun build-site (ref)
  "Render docs/'s home page and *PAGES* at REF and write build/site/, or
write nothing when there is a problem, RENDER-SITE's own or a missing
repository link. Returns two values: the number of pages written, 0 when
there were problems; and the problems."
  (multiple-value-bind (outputs pages links problems) (render-docs-problems ref)
    (declare (ignore pages links))
    (cond (problems (values 0 problems))
          (t (write-site (build-directory-pathname) outputs)
             (values (length outputs) problems)))))

;;; Reporting, shared by the runners

(defun report-problems (label problems)
  "Print each of PROBLEMS to *ERROR-OUTPUT*, as one LABEL: PROBLEM line."
  (dolist (problem problems)
    (format *error-output* "~&~A: ~A~%" label problem)))

(defun print-cmark-gfm-hint ()
  "Print, to *ERROR-OUTPUT*, the hint tests/run-native.lisp prints when
cmark-gfm can't load: how to fix it on a Guix host, and elsewhere."
  (format *error-output*
          "~&On a Guix host, run it in the project's container: scripts/guix-env ~
           make <target>, which sets CL_COMMONMARK_GFM_LIBS. Elsewhere, install ~
           libcmark-gfm 0.29.0.gfm.13, or set CL_COMMONMARK_GFM_LIBS to the two ~
           library paths.~%"))
