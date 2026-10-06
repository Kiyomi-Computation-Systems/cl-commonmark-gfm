;;;; The site's pages: the home page, and the sidebar's pages in order.

(in-package #:cl-commonmark-gfm.site)

(defparameter *home-page* "README.md"
  "The docs/ file that is the site's home page, written as index.html.
GitHub shows it when docs/ is opened. The project's name, above the
sidebar, links to it, so it isn't one of *PAGES*.")

(defparameter *pages* '("installing.md" "usage.md" "options.md" "ast.md" "html-tree.md"
                        "safety.md" "errors.md" "ecl.md" "support.md" "reference.md")
  "The sidebar's pages, in order: docs/ file names, such as \"usage.md\".
Each is labelled with its page's first heading.")

(defparameter *reference-page* "reference.md"
  "The reference's file name in docs/.")
