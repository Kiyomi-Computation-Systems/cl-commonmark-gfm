---
name: Bug report
about: Something broke or behaved unexpectedly
labels: bug
---

**Environment**

- System and architecture (e.g. macOS 15 arm64, Debian 13 amd64):
- Lisp and its version (e.g. SBCL 2.5.2, CCL 1.13, ECL 24.5.10):
- cmark-gfm's version, and how you installed it (e.g. Debian's
  packages, Homebrew, built from source):
- If you named cmark-gfm's libraries yourself, with
  `*cmark-gfm-libraries*` or `CL_COMMONMARK_GFM_LIBS`, the paths:
- How you installed this library (ocicl, a clone):
- Does any other code in the same process load cmark-gfm?

**What happened**

Include the whole report of any error it signalled.

**What you expected**

**The smallest example that shows it**

Ideally a few Lisp forms, run after `(asdf:load-system
"cl-commonmark-gfm")`, with the Markdown input if the bug depends on
it.

**From a clone: does `make test` pass?**

If so, please paste the output of `make info`, which names the versions
it finds.
