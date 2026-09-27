;;; Development toolchain for cl-commonmark-gfm (ADR-0004).
;;;
;;; Enter it with scripts/guix-env, which pins Guix to channels.scm and runs
;;; this manifest in a container. Plain `guix shell -m manifest.scm` also
;;; loads this file, but against whatever Guix you have pulled.
;;;
;;; ocicl is not packaged in Guix. `make ocicl` builds the pinned release
;;; from source with the sbcl below, into .guix-env/ (ADR-0003).

(specifications->manifest
 '(;; The three Lisps the plan targets. Guix builds them for x86_64-linux.
   "sbcl" "ecl" "ccl"
   ;; The pinned native dependency (ADR-0002) and what builds the shim.
   "cmark-gfm" "gcc-toolchain" "pkg-config"
   ;; ocicl's TLS loads libcrypto through CFFI by bare name, which resolves
   ;; only because scripts/guix-env-enter sets LD_LIBRARY_PATH.
   "openssl"
   ;; What the Makefile and scripts shell out to. The container has nothing
   ;; else.
   "bash" "coreutils" "make" "git" "grep" "sed" "gawk" "findutils"
   "diffutils" "nss-certs"))
