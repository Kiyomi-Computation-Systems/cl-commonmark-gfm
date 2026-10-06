;;;; RESOLVE-CMARK-LIBRARIES: finding the pinned cmark-gfm pair, by absolute
;;;; path only. A bare name would leave the choice of file to the system
;;;; loader. Pure: every filesystem fact -- the operating system, an
;;;; environment variable's value, whether a path names a regular file --
;;;; arrives as an argument, so every branch is tested against synthetic
;;;; listings with nothing on disk.

(in-package #:cl-commonmark-gfm.native-core)

(defvar *cmark-gfm-libraries* nil
  "Where to load cmark-gfm from: NIL, the default, to search a fixed list of
directories, never the loader's own search path; or a list of two absolute
paths, strings or pathnames, naming the pinned libcmark-gfm, then
libcmark-gfm-extensions. Read when cmark-gfm starts, at the first call that
needs it.

The search tries, in order, /usr/lib/<multiarch> (`x86_64-linux-gnu` or
`aarch64-linux-gnu`), /usr/lib64, /usr/lib and /usr/local/lib on Linux, or
/opt/homebrew/lib and /usr/local/lib on macOS, and takes the first that
holds both libraries under their versioned names, such as
`libcmark-gfm.so.0.29.0.gfm.13`.

Takes priority over the CL_COMMONMARK_GFM_LIBS environment variable, which
names the same two paths, separated by a colon. Either override is used as
given, with no fallback to the other or to the search: one that isn't two
absolute paths, or names something that isn't a regular file, signals
NATIVE-LIBRARY-NOT-FOUND, whose report names that override.

On CCL, which can't unload a library, the first pair a process loads stays
its pair, even if starting cmark-gfm then fails: naming another pair after
that signals NATIVE-INITIALIZATION-ERROR, and only a new process can load
it. An ECL program with cmark-gfm linked in loads nothing, and ignores both.")

;;; Signalling

(defun signal-library-not-found (&key override datum reason paths)
  "Signal NATIVE-LIBRARY-NOT-FOUND for RESOLVE-CMARK-LIBRARIES."
  (error 'native-library-not-found
         :operation 'resolve-cmark-libraries
         :override override
         :datum datum
         :reason reason
         :paths paths))

;;; Shared path checks

(defun absolute-path-string-p (value)
  "True when VALUE is a non-empty string starting with a /: an absolute
POSIX path, the only kind an override or the directory search ever names."
  (and (stringp value) (plusp (length value)) (char= (char value 0) #\/)))

(defun as-namestring (value)
  "VALUE as a namestring: itself when it is already a string, or
(NAMESTRING VALUE) when it is a pathname. Touches no file: NAMESTRING only
prints a pathname's own slots."
  (if (pathnamep value) (namestring value) value))

(defun check-regular-files (core extensions override variable-name regular-file-p)
  "Verify CORE then EXTENSIONS with REGULAR-FILE-P, signalling
NATIVE-LIBRARY-NOT-FOUND naming OVERRIDE and the first of the two that
fails. Its reason names VARIABLE-NAME, the override variable that holds
OVERRIDE. No fallback to the directory search: an override is used
verbatim. Returns (CORE EXTENSIONS) once both pass."
  (unless (funcall regular-file-p core)
    (signal-library-not-found
     :override override :datum core
     :reason (format nil "~A names a core library that is not a regular file" variable-name)
     :paths (list core)))
  (unless (funcall regular-file-p extensions)
    (signal-library-not-found
     :override override :datum extensions
     :reason (format nil "~A names an extensions library that is not a regular file"
                     variable-name)
     :paths (list extensions)))
  (list core extensions))

(defun resolve-override-pair (core extensions override variable-name regular-file-p)
  "The common end of both override paths: CORE and EXTENSIONS must both be
absolute path strings, then both must pass REGULAR-FILE-P. Any
NATIVE-LIBRARY-NOT-FOUND carries OVERRIDE, the override's raw value, and
its reason names VARIABLE-NAME, the override variable at fault. Returns
\(CORE EXTENSIONS)."
  (unless (and (absolute-path-string-p core) (absolute-path-string-p extensions))
    (signal-library-not-found :override override :datum override
                               :reason (format nil "~A must name two absolute paths"
                                               variable-name)))
  (check-regular-files core extensions override variable-name regular-file-p))

;;; 1. Override

(defun resolve-libraries-override (libraries regular-file-p)
  "Resolve *CMARK-GFM-LIBRARIES*' value LIBRARIES: a list of exactly two
paths (strings or pathnames), both absolute, both regular files. Anything
else -- one path, three, a dotted pair, a circular list, a relative path, an
empty string -- signals NATIVE-LIBRARY-NOT-FOUND, naming
*CMARK-GFM-LIBRARIES*. PROPER-LIST-P, not LISTP, screens LIBRARIES first: a
dotted LIBRARIES would make LENGTH signal a raw TYPE-ERROR instead, and a
circular one would hang LENGTH outright, under the startup lock."
  (unless (and (proper-list-p libraries) (= (length libraries) 2))
    (signal-library-not-found
     :override libraries :datum libraries
     :reason "*CMARK-GFM-LIBRARIES* must be a list of two absolute paths"))
  (resolve-override-pair (as-namestring (first libraries))
                          (as-namestring (second libraries))
                          libraries
                          "*CMARK-GFM-LIBRARIES*"
                          regular-file-p))

(defun resolve-environment-override (environment regular-file-p)
  "Resolve CL_COMMONMARK_GFM_LIBS' value ENVIRONMENT: \"core:extensions\",
split at its one colon, both halves absolute paths, both regular files.
Anything else -- no colon, more than one, a relative path, an empty string
on either side -- signals NATIVE-LIBRARY-NOT-FOUND, naming
CL_COMMONMARK_GFM_LIBS. An ENVIRONMENT of \"\" (set, but empty) reaches
here too, and fails the same way: it has no colon."
  (unless (= (count #\: environment) 1)
    (signal-library-not-found
     :override environment :datum environment
     :reason "CL_COMMONMARK_GFM_LIBS must be two absolute paths, separated by one colon"))
  (let ((colon (position #\: environment)))
    (resolve-override-pair (subseq environment 0 colon)
                            (subseq environment (1+ colon))
                            environment
                            "CL_COMMONMARK_GFM_LIBS"
                            regular-file-p)))

;;; 2. Directory search

(defun search-directories (os multiarch)
  "The directories RESOLVE-CMARK-LIBRARIES searches, in order, for OS
\(:LINUX or :MACOS\). The Linux multiarch directory is left out when
MULTIARCH is NIL."
  (ecase os
    (:linux (append (and multiarch (list (format nil "/usr/lib/~A" multiarch)))
                     (list "/usr/lib64" "/usr/lib" "/usr/local/lib")))
    (:macos (list "/opt/homebrew/lib" "/usr/local/lib"))))

(defun core-filename (os)
  "The pinned libcmark-gfm's filename on OS: only the versioned name
matches, never a bare or unversioned one. It names the pinned version, and
on Debian the unversioned names come only with the -dev packages."
  (ecase os
    (:linux (format nil "libcmark-gfm.so.~A" *cmark-gfm-version*))
    (:macos (format nil "libcmark-gfm.~A.dylib" *cmark-gfm-version*))))

(defun extensions-filename (os)
  "The pinned libcmark-gfm-extensions' filename on OS."
  (ecase os
    (:linux (format nil "libcmark-gfm-extensions.so.~A" *cmark-gfm-version*))
    (:macos (format nil "libcmark-gfm-extensions.~A.dylib" *cmark-gfm-version*))))

(defun directory-path (directory filename)
  "DIRECTORY and FILENAME joined with one /."
  (format nil "~A/~A" directory filename))

(defun directory-has-pair-p (directory os regular-file-p)
  "True when DIRECTORY holds both the pinned core and extensions libraries
for OS, by REGULAR-FILE-P. A directory holding only one is never paired
with another: the extensions library depends on the core, so the loader
could bring in a second core beside one taken from another directory. That
double load is the hazard this search exists to close."
  (and (funcall regular-file-p (directory-path directory (core-filename os)))
       (funcall regular-file-p (directory-path directory (extensions-filename os)))))

(defun resolve-by-search (os multiarch regular-file-p)
  "Walk SEARCH-DIRECTORIES in order; the first directory holding both
pinned files wins. Signals NATIVE-LIBRARY-NOT-FOUND when none does, with
DATUM the list of directories searched and a REASON that says so and names
both override variables, so the report is useful with neither set."
  (let ((directories (search-directories os multiarch)))
    (dolist (directory directories)
      (when (directory-has-pair-p directory os regular-file-p)
        (return-from resolve-by-search
          (list (directory-path directory (core-filename os))
                (directory-path directory (extensions-filename os))))))
    (signal-library-not-found
     :override nil :datum directories
     :reason (concatenate 'string "no searched directory holds both pinned libraries; set "
                           "*CMARK-GFM-LIBRARIES* or CL_COMMONMARK_GFM_LIBS to override")
     :paths directories)))

;;; The entry point

(defun resolve-cmark-libraries (&key libraries environment os multiarch regular-file-p)
  "Resolve the pinned libcmark-gfm and libcmark-gfm-extensions, by absolute
path only. Returns (CORE EXTENSIONS), two namestrings, and as a second
value the name of the override that gave them, \"*CMARK-GFM-LIBRARIES*\"
or \"CL_COMMONMARK_GFM_LIBS\", or NIL when the directory search found
them.

LIBRARIES is the current value of *CMARK-GFM-LIBRARIES*. ENVIRONMENT is the
current value of CL_COMMONMARK_GFM_LIBS, or NIL when it is unset -- an
empty string counts as set. OS is :LINUX or :MACOS. MULTIARCH is
\"x86_64-linux-gnu\", \"aarch64-linux-gnu\", or NIL to skip the multiarch
directory. REGULAR-FILE-P is a function of one path string, true when it
names an existing regular file.

A pathname in LIBRARIES is turned into a namestring here, with NAMESTRING,
not a native-namestring conversion. NAMESTRING can misread a pathname whose
components hold wildcard characters (* or ?); a caller holding one of those
should pass a native namestring of its own instead. /NATIVE already does,
with UIOP:NATIVE-NAMESTRING, before LIBRARIES ever reaches here.

1. When LIBRARIES is non-NIL, it is used verbatim: RESOLVE-LIBRARIES-OVERRIDE.
2. Otherwise, when ENVIRONMENT is non-NIL, it is used verbatim:
   RESOLVE-ENVIRONMENT-OVERRIDE. Neither override falls back to the other
   or to the directory search when it is invalid or its files are missing.
3. Otherwise, RESOLVE-BY-SEARCH walks the fixed directories for OS.

Every failure signals NATIVE-LIBRARY-NOT-FOUND, with :OPERATION
RESOLVE-CMARK-LIBRARIES, :OVERRIDE the override's value in effect (or NIL
for the directory search), :PATHS the path that failed or every directory
searched (NIL for a malformed override), :DATUM the offending value, and a
:REASON saying what is wrong, which names the override variable at fault
when an override is in effect. This function touches no file itself;
REGULAR-FILE-P is the only filesystem access, so every branch is tested
against a synthetic listing with nothing on disk."
  (cond
    (libraries
     (values (resolve-libraries-override libraries regular-file-p) "*CMARK-GFM-LIBRARIES*"))
    (environment
     (values (resolve-environment-override environment regular-file-p) "CL_COMMONMARK_GFM_LIBS"))
    (t (values (resolve-by-search os multiarch regular-file-p) nil))))
