;;; The same toolchain as manifest.scm, with ECL alone built without
;;; dynamic FFI. The transformation is applied here, in a manifest of its
;;; own, since `guix shell`'s --with-configure-flag option leaves a
;;; manifest's ECL alone.
;;;
;;; manifest.scm's packages are read from that file -- loaded, not copied,
;;; so the two can't drift apart -- and only the "ecl" entry is rewritten,
;;; so Guix never rebuilds anything else. Enter it with
;;; GUIX_ENV_MANIFEST=manifest-ecl-nodffi.scm scripts/guix-env, or `make
;;; check-ecl-nodffi` on the host. Plain `guix shell -m
;;; manifest-ecl-nodffi.scm` also loads this file, but against whatever
;;; Guix you have pulled.

(use-modules (guix profiles) (guix transformations))

(define without-dffi
  (options->transformation '((with-configure-flag . "ecl=--with-dffi=no"))))

(define base-manifest
  (load (string-append (dirname (current-filename)) "/manifest.scm")))

(manifest
 (map (lambda (entry)
        (if (string=? (manifest-entry-name entry) "ecl")
            (manifest-entry (inherit entry)
                             (item (without-dffi (manifest-entry-item entry))))
            entry))
      (manifest-entries base-manifest)))
