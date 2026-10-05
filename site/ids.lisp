;;;; Heading ids, as GitHub gives them, so that a link to a heading works
;;;; both on github.com and on the site.

(in-package #:cl-commonmark-gfm.site)

(defun id-character-p (char)
  "True when CHAR stays in a heading's id: a letter or a digit, Unicode's
included, or -, _ or a space."
  (or (alphanumericp char)
      (char= char #\-)
      (char= char #\_)
      (char= char #\Space)))

(defun heading-id (text)
  "The id GitHub gives a heading whose text is TEXT: TEXT lowercased, every
character but letters, digits, -, _ and spaces dropped, and each space
turned into -. Runs of spaces and hyphens are kept, so
\"2.0.0 - 2026-06-07\" gives \"200---2026-06-07\". The rule is GitHub's
for ASCII text alone: RENDER-SITE refuses a heading holding any other
character."
  (map 'string
       (lambda (char) (if (char= char #\Space) #\- char))
       (remove-if-not #'id-character-p (string-downcase text))))

(defun unique-ids (texts)
  "The ids of one page's headings, whose texts are TEXTS, in order: each
text's HEADING-ID, a repeat numbered by how often its id came before on the
page. Each id has its own count, as GitHub numbers them: a changelog's
headings Added, Fixed, Added, Fixed, Added get added, fixed, added-1,
fixed-1, added-2. Two ids can still be the same: A, A 1 and A give a, a-1
and a-1, which RENDER-SITE reports as a problem."
  (let ((counts (make-hash-table :test 'equal)))
    (mapcar (lambda (text)
              (let* ((id (heading-id text))
                     (count (gethash id counts 0)))
                (setf (gethash id counts) (1+ count))
                (if (zerop count)
                    id
                    (format nil "~A-~D" id count))))
            texts)))

(defun heading-text (heading)
  "The text of HEADING, a :HEADING node: the literals of its :TEXT and :CODE
nodes, in order. Emphasis, a link and an image give the text inside them; a
code span gives its code, without the backticks."
  (let ((literals (fold-ast (lambda (node literals)
                              (if (member (node-kind node) '(:text :code))
                                  (cons (node-attribute node :literal) literals)
                                  literals))
                            '()
                            heading)))
    (with-output-to-string (out)
      (dolist (literal (reverse literals))
        (write-string literal out)))))
