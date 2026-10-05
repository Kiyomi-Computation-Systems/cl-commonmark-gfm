;;;; Tests for the site's checks (site/checks.lisp): the pure functions
;;;; that decide which pages, links and refs are problems. None reads a
;;;; file or runs git; BUILD.LISP's GIT-TRACKED-FILES and the docs/
;;;; listings are stood in for by hand-built lists here.

(in-package #:cl-commonmark-gfm.site.tests)

;;; SITE_REF

(defun ref-problem (ref)
  "REF through REF-PROBLEM."
  (cl-commonmark-gfm.site::ref-problem ref))

(defun ref-ok-p (ref)
  "REF through VALID-REF-P."
  (cl-commonmark-gfm.site::valid-ref-p ref))

(define-test valid-ref-p-accepts-an-ordinary-ref
  (true (ref-ok-p "main"))
  (true (ref-ok-p "v0.1.0"))
  (true (ref-ok-p "feature/foo"))
  (is eql nil (ref-problem "main")))

(define-test ref-problem-names-an-empty-ref
  (is string= "is empty" (ref-problem ""))
  (true (not (ref-ok-p ""))))

(define-test ref-problem-names-a-character-a-urls-path-cant-carry
  (dolist (bad (list "a b" "a#b" "a?b" "a%b"
                     (format nil "a~Cb" (code-char 1)) (format nil "a~Cb" (code-char #x7F))))
    (is string= "holds a character a URL's path can't carry as it is" (ref-problem bad))
    (true (not (ref-ok-p bad)))))

(define-test ref-problem-names-a-segment-that-would-leave-blob
  (dolist (bad (list "." ".." "a/./b" "a/../b" "../../x" "/a" "a/" "a//b"))
    (is string= "holds a segment that would leave /blob/" (ref-problem bad))
    (true (not (ref-ok-p bad)))))

;;; Check 1

(define-test unlisted-page-problems-reports-each-direction
  (is equal '("a.md: in docs/, but not listed in *pages*; add it to site/pages.lisp")
      (cl-commonmark-gfm.site::unlisted-page-problems '() '("a.md")))
  (is equal '("b.md: listed in *pages*, but missing from docs/")
      (cl-commonmark-gfm.site::unlisted-page-problems '("b.md") '()))
  (is equal '() (cl-commonmark-gfm.site::unlisted-page-problems '("a.md") '("a.md"))))

(define-test unlisted-page-problems-hints-reference-md
  (is equal '("reference.md: listed in *pages*, but missing from docs/; run 'make reference'")
      (cl-commonmark-gfm.site::unlisted-page-problems '("reference.md") '())))

(define-test duplicate-sidebar-problems-names-a-repeated-page-once
  (is equal '("a.md: listed more than once in *pages*")
      (cl-commonmark-gfm.site::duplicate-sidebar-problems '("a.md" "b.md" "a.md")))
  (is equal '("a.md: listed more than once in *pages*")
      (cl-commonmark-gfm.site::duplicate-sidebar-problems '("a.md" "b.md" "a.md" "a.md"))))

(define-test duplicate-sidebar-problems-passes-no-repeats
  (is equal '() (cl-commonmark-gfm.site::duplicate-sidebar-problems '("a.md" "b.md"))))

(define-test nested-page-problems-names-each-file
  (is equal '("sub/page.md: sits in a directory below docs/, where the site won't render it"
              "deep/down/c.md: sits in a directory below docs/, where the site won't render it")
      (cl-commonmark-gfm.site::nested-page-problems '("sub/page.md" "deep/down/c.md"))))

;;; Repository links

(defparameter *tracked-files*
  '("src/api.lisp" "src/ast/node.lisp" "CHANGELOG.md" "ocicl.csv")
  "A small, hand-built stand-in for GIT-TRACKED-FILES: files, and one,
src/, that is a directory only because others sit under it.")

(define-test repository-path-known-p-finds-an-exact-file
  (true (cl-commonmark-gfm.site::repository-path-known-p "src/api.lisp" *tracked-files* '()))
  (true (cl-commonmark-gfm.site::repository-path-known-p "CHANGELOG.md" *tracked-files* '())))

(define-test repository-path-known-p-finds-a-directory-by-its-files
  (true (cl-commonmark-gfm.site::repository-path-known-p "src" *tracked-files* '()))
  (true (cl-commonmark-gfm.site::repository-path-known-p "src/" *tracked-files* '())))

(define-test repository-path-known-p-refuses-an-unknown-path
  (true (not (cl-commonmark-gfm.site::repository-path-known-p "src/nope.lisp" *tracked-files* '())))
  (true (not (cl-commonmark-gfm.site::repository-path-known-p
              "build/check-docs.log" *tracked-files* '()))))

(define-test repository-path-known-p-does-not-mistake-a-file-for-a-directorys-child
  (true (not (cl-commonmark-gfm.site::repository-path-known-p "ocicl" *tracked-files* '()))))

(define-test repository-path-known-p-accepts-the-repositorys-root
  (true (cl-commonmark-gfm.site::repository-path-known-p "" *tracked-files* '()))
  (true (cl-commonmark-gfm.site::repository-path-known-p "" '() '())))

(define-test missing-repository-link-problems-names-each-missing-link
  (is equal '("usage.md: link src/nope.lisp names no file in the repository")
      (cl-commonmark-gfm.site::missing-repository-link-problems
       '(("usage.md" . "src/api.lisp") ("usage.md" . "src/nope.lisp"))
       *tracked-files* '()))
  (is equal '()
      (cl-commonmark-gfm.site::missing-repository-link-problems
       '(("usage.md" . "src/") ("usage.md" . "CHANGELOG.md") ("usage.md" . ""))
       *tracked-files* '())))

;;; git's raw output

(defun ls-files-entry (mode path)
  "A 'git ls-files -s -z ...' entry naming PATH, its mode MODE and some
object and stage before the tab, as a tracked entry's looks; or, MODE
NIL, PATH alone, as an --others entry's does."
  (if mode (format nil "~A c0ffee 0~C~A" mode #\Tab path) path))

(define-test split-nul-terminated-splits-and-drops-the-final-empty-entry
  (is equal '("a" "b")
      (cl-commonmark-gfm.site::split-nul-terminated
       (format nil "a~Cb~C" (code-char 0) (code-char 0))))
  (is equal '() (cl-commonmark-gfm.site::split-nul-terminated ""))
  (is equal '("solo") (cl-commonmark-gfm.site::split-nul-terminated
                       (format nil "solo~C" (code-char 0)))))

(define-test ls-files-entry-path-strips-a-tracked-entrys-mode-and-object
  (is string= "vendor/cmark-gfm"
      (cl-commonmark-gfm.site::ls-files-entry-path (ls-files-entry "160000" "vendor/cmark-gfm")))
  (is string= "docs/README.md"
      (cl-commonmark-gfm.site::ls-files-entry-path (ls-files-entry nil "docs/README.md"))))

(define-test gitlink-entry-p-finds-mode-160000-alone
  (true (cl-commonmark-gfm.site::gitlink-entry-p (ls-files-entry "160000" "vendor/cmark-gfm")))
  (true (not (cl-commonmark-gfm.site::gitlink-entry-p (ls-files-entry nil "docs/README.md"))))
  (true (not (cl-commonmark-gfm.site::gitlink-entry-p
              (ls-files-entry "100644" "160000-notes.txt")))))

(define-test ls-files-entries-to-paths-keeps-a-gitlink-and-names-it-too
  (multiple-value-bind (paths gitlink-paths)
      (cl-commonmark-gfm.site::ls-files-entries-to-paths
       (list (ls-files-entry nil "docs/README.md")
             (ls-files-entry "160000" "vendor/cmark-gfm")
             (ls-files-entry "100644" "src/api.lisp")))
    (is equal '("docs/README.md" "vendor/cmark-gfm" "src/api.lisp") paths)
    (is equal '("vendor/cmark-gfm") gitlink-paths)))

(define-test tracked-files-minus-deleted-removes-only-the-deleted-ones
  (is equal '("a" "c")
      (cl-commonmark-gfm.site::tracked-files-minus-deleted '("a" "b" "c") '("b")))
  (is equal '("a" "b")
      (cl-commonmark-gfm.site::tracked-files-minus-deleted '("a" "b") '())))

;;; B44: when the only entry under vendor/ is the submodule's own
;;; gitlink, vendor/ still passes, as a directory GitHub serves a
;;; listing for, but the gitlink's own path, and anything below it,
;;; doesn't: GitHub's /blob/ and /tree/ serve no page for either.

(defun vendor-paths (&optional (mode "160000"))
  "LS-FILES-ENTRIES-TO-PATHS over one entry, vendor/cmark-gfm with MODE:
its two values."
  (cl-commonmark-gfm.site::ls-files-entries-to-paths
   (list (ls-files-entry mode "vendor/cmark-gfm"))))

(define-test repository-path-known-p-accepts-a-directory-that-only-holds-a-gitlink
  (multiple-value-bind (paths gitlink-paths) (vendor-paths)
    (true (cl-commonmark-gfm.site::repository-path-known-p "vendor" paths gitlink-paths))
    (true (cl-commonmark-gfm.site::repository-path-known-p "vendor/" paths gitlink-paths))))

(define-test repository-path-known-p-refuses-the-gitlink-itself-and-below-it
  (multiple-value-bind (paths gitlink-paths) (vendor-paths)
    (true (not (cl-commonmark-gfm.site::repository-path-known-p
                "vendor/cmark-gfm" paths gitlink-paths)))
    (true (not (cl-commonmark-gfm.site::repository-path-known-p
                "vendor/cmark-gfm/" paths gitlink-paths)))
    (true (not (cl-commonmark-gfm.site::repository-path-known-p
                "vendor/cmark-gfm/COPYING" paths gitlink-paths)))))
