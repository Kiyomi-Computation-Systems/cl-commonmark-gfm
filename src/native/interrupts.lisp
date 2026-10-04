;;;; Deferring interrupts. An interrupt that unwinds out of a cmark call, as
;;;; a THROW from SB-THREAD:INTERRUPT-THREAD or SB-EXT:WITH-TIMEOUT's does,
;;;; can leave a lock of the C heap held: a throw out of cmark's malloc or
;;;; free leaves its arena's lock taken, so the thread's next allocation
;;;; waits on itself, and the C heap can be left inconsistent. So every call
;;;; into cmark runs with interrupts deferred, and so does the bookkeeping
;;;; that records what a call created or freed: the document's own pointers,
;;;; the counters and the holds. An interrupt lands once the call returns.
;;;; Each Lisp's own construct is named here, and only here: these are
;;;; reader conditionals the library allows in /native alone. On ECL the
;;;; deferral doesn't hold in a region that allocates, and under its dynamic
;;;; FFI every deferred region does: CFFI's ECL calls cons, and so does the
;;;; bookkeeping. So interrupting a thread during a call isn't safe there.

(in-package #:cl-commonmark-gfm.native)

(defmacro with-interrupts-deferred (&body body)
  "Run BODY with interrupts deferred, and return its values. An interrupt
that arrives meanwhile, such as SB-THREAD:INTERRUPT-THREAD's or a
timeout's, runs once BODY has returned or exited, never inside it. Nested
uses keep interrupts deferred until the outermost one ends. BODY can still
signal, and a handler can still unwind out of it.

Every call into cmark runs inside one: SB-SYS:WITHOUT-INTERRUPTS on SBCL,
CCL:WITHOUT-INTERRUPTS on CCL and MP:WITHOUT-INTERRUPTS on ECL. So no
interrupt runs on top of a C frame, except on ECL, where the deferral
doesn't hold in a region that allocates, and an interrupt can land during
a call."
  #+sbcl `(sb-sys:without-interrupts ,@body)
  #+ccl `(ccl:without-interrupts ,@body)
  #+ecl `(mp:without-interrupts ,@body)
  #-(or sbcl ccl ecl)
  (error "cl-commonmark-gfm defers interrupts on SBCL, CCL and ECL only, not ~A"
         (lisp-implementation-type)))

(defmacro unwind-protect-deferred (protected-form &body cleanup-forms)
  "Like UNWIND-PROTECT, but CLEANUP-FORMS run with interrupts deferred,
from the moment PROTECTED-FORM is left, however it is left, so an
interrupt can neither skip a cleanup nor cut one short. PROTECTED-FORM
runs with interrupts as the caller had them: deferred inside
WITH-INTERRUPTS-DEFERRED, and otherwise not, so a long body stays
interruptible between its cmark calls. Returns PROTECTED-FORM's values.

SBCL and ECL enter the UNWIND-PROTECT with interrupts deferred, and let
them back in for PROTECTED-FORM alone, with WITH-LOCAL-INTERRUPTS, which
keeps them deferred when an outer use already did. CCL already runs every
cleanup form with interrupts disabled (its *INTERRUPT-LEVEL* is -1 there),
so a plain UNWIND-PROTECT does: the CCL:WITHOUT-INTERRUPTS around its
cleanup forms changes nothing, and only states the deferral."
  #+sbcl `(sb-sys:without-interrupts
            (unwind-protect (sb-sys:with-local-interrupts ,protected-form)
              ,@cleanup-forms))
  #+ecl `(mp:without-interrupts
           (unwind-protect (mp:with-local-interrupts ,protected-form)
             ,@cleanup-forms))
  #+ccl `(unwind-protect ,protected-form
           (ccl:without-interrupts ,@cleanup-forms))
  #-(or sbcl ccl ecl)
  (error "cl-commonmark-gfm defers interrupts on SBCL, CCL and ECL only, not ~A"
         (lisp-implementation-type)))
